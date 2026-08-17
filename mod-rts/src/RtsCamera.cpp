#include "RtsCamera.h"

#include "CharmInfo.h"   // CharmType / CHARM_TYPE_POSSESS -- Unit.h only forward-declares the enum
#include "Config.h"
#include "Creature.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "TemporarySummon.h"

#include <algorithm>
#include <cmath>
#include <unordered_map>

namespace
{
    // "Invisible Stalker" -- a world trigger that already ships in every world
    // database: invisible model, faction 35 (friendly to everything), and
    // already flagged not-selectable. Borrowing it rather than shipping a
    // creature_template row keeps this module free of schema changes, which
    // matters because the world DB gets re-imported wholesale on a core update
    // and a module's own rows are the first thing to go missing.
    constexpr uint32 kCameraEntry = 15214;

    constexpr float kDefaultHeight = 12.0f;   // yards above the player to start
    constexpr float kDefaultSpeed  = 3.0f;    // multiple of base run speed

    std::unordered_map<ObjectGuid, ObjectGuid> g_cameras;   // player -> camera

    // Where each player wants the camera to sit relative to their character.
    // Held in memory only: the addon owns the persistence, sends it on every
    // enable, and is the one place a per-character setting is already saved.
    struct Offset { float back; float up; };
    std::unordered_map<ObjectGuid, Offset> g_offsets;

    // Players currently holding a height key: +1 up, -1 down. Only populated
    // while a key is down, so the common case is an empty map and a free tick.
    std::unordered_map<ObjectGuid, int> g_vertical;

    constexpr float kDefaultLift = 14.0f;   // yards per second on Q/E

    // --- pivot ------------------------------------------------------------
    //
    // Q/E used to be TURNLEFT/TURNRIGHT, which yaws the camera IN PLACE: what
    // you were looking at swings off the screen. Pivoting instead carries the
    // camera around an arc centred on the point it is looking at, so that point
    // stays put and you see it from a new side -- the WC3/SC2 gesture.
    //
    // The focus point is taken a fixed distance ahead of the camera rather than
    // from the character, because in an RTS the camera spends most of its time
    // somewhere the character is not. Pivoting around the character would
    // behave correctly only while they happened to be on screen.
    //
    // Pitch is deliberately not involved. The camera's tilt lives on the client
    // and the server never sees it, but the orbit only needs the point's
    // position on the HORIZONTAL plane -- rotating about a vertical axis is the
    // same arc whatever the tilt. So the focus is computed flat, at the
    // camera's own height, and the tilt takes care of itself.
    std::unordered_map<ObjectGuid, int> g_pivot;   // player -> -1 left, +1 right

    constexpr float kDefaultPivotDist  = 26.0f;   // yards ahead of the camera
    constexpr float kDefaultPivotSpeed = 0.9f;    // radians per second

    // Read ONCE, not per tick.
    //
    // The previous attempt at a camera option called GetOption from inside
    // Update(), so a property missing from the conf file logged its "Missing
    // property" warning on every world tick and buried the console. A compiled
    // default keeps the module working without a conf file; it does not silence
    // that warning. Function-local statics initialise on first use and never
    // again, which is the whole fix.
    float PivotDistance()
    {
        static float const d =
            sConfigMgr->GetOption<float>("RTS.Camera.PivotDistance", kDefaultPivotDist);
        return d;
    }

    float PivotSpeed()
    {
        static float const s =
            sConfigMgr->GetOption<float>("RTS.Camera.PivotSpeed", kDefaultPivotSpeed);
        return s;
    }

    // Give every direction the SAME absolute speed.
    //
    // `speed` arrives as a multiple of base run speed, and the obvious thing --
    // applying that rate to each move type -- does not work, because every type
    // has a different base: run is 7.0 yards/s but run-BACK is 4.5. The same
    // rate on both therefore leaves reversing visibly slower than advancing,
    // which is exactly how it felt in game. A camera has no business being
    // faster one way than the other, so convert to an absolute target once and
    // give each type whatever rate reproduces it.
    void ApplySpeed(Creature* cam, float speed)
    {
        float const target = baseMoveSpeed[MOVE_RUN] * speed;

        UnitMoveType const types[] = {
            MOVE_WALK, MOVE_RUN, MOVE_RUN_BACK,
            MOVE_SWIM, MOVE_SWIM_BACK,
            MOVE_FLIGHT, MOVE_FLIGHT_BACK
        };

        for (UnitMoveType const mt : types)
        {
            if (baseMoveSpeed[mt] > 0.0f)
                cam->SetSpeed(mt, target / baseMoveSpeed[mt], true);
        }
    }

    // Placement, shared by Enable and Recenter so a camera cannot come back to a
    // different spot than it started at. `back` runs opposite the character's
    // facing, so a positive value sits behind them looking forward over their
    // shoulder -- which is what pulls the party down into frame instead of
    // leaving them directly underneath.
    void PlacementFor(Player const* player, float& x, float& y, float& z)
    {
        float back = 0.0f;
        float up   = sConfigMgr->GetOption<float>("RTS.Camera.Height", kDefaultHeight);

        auto it = g_offsets.find(player->GetGUID());
        if (it != g_offsets.end())
        {
            back = it->second.back;
            up   = it->second.up;
        }

        float const o = player->GetOrientation();
        x = player->GetPositionX() - std::cos(o) * back;
        y = player->GetPositionY() - std::sin(o) * back;
        z = player->GetPositionZ() + up;
    }

    Creature* FindCamera(Player const* player)
    {
        auto it = g_cameras.find(player->GetGUID());
        if (it == g_cameras.end())
            return nullptr;
        return ObjectAccessor::GetCreature(*player, it->second);
    }

    void Despawn(Creature* cam)
    {
        if (!cam)
            return;
        if (TempSummon* summon = cam->ToTempSummon())
            summon->UnSummon();
        else
            cam->DespawnOrUnsummon();
    }

    // Undo possession and make certain the player is not left seeing through a
    // creature we are about to delete.
    //
    // Releasing with a bare SetClientControl(player, true) does NOT clear the
    // viewpoint: SetClientControl skips SetViewpoint when the target is the
    // player itself (Player.cpp:13171, `if (this != target)`). That left
    // PLAYER_FARSIGHT pointing at a despawned creature and killed the client
    // with ERROR #134 on the next /reload. Player::SetViewpoint warns about it
    // twice in its own source: "must immediately set seer back otherwise may
    // crash". RemoveCharmedBy does it right, calling SetClientControl(camera,
    // false) first -- where the target is not the player.
    void Release(Player* player, Creature* cam)
    {
        if (cam && cam->GetCharmerGUID() == player->GetGUID())
            cam->RemoveCharmedBy(player);

        if (WorldObject* seen = player->GetViewpoint())
            player->SetViewpoint(seen, false);
    }
}

bool rts::camera::IsActive(Player const* player)
{
    return player && g_cameras.find(player->GetGUID()) != g_cameras.end();
}

bool rts::camera::Enable(Player* player)
{
    if (!player || !player->IsInWorld())
        return false;

    if (IsActive(player))
        return true;

    // A camera while dead, on a taxi, or in a vehicle would be handing control
    // away from something that already owns it. Refuse rather than untangle it.
    if (!player->IsAlive() || player->IsInFlight() || player->GetVehicle())
        return false;

    float const speed = sConfigMgr->GetOption<float>("RTS.Camera.Speed", kDefaultSpeed);

    float cx, cy, cz;
    PlacementFor(player, cx, cy, cz);

    TempSummon* cam = player->SummonCreature(
        kCameraEntry,
        cx, cy, cz,
        player->GetOrientation(),
        TEMPSUMMON_MANUAL_DESPAWN, 0, nullptr,
        /*visibleBySummonerOnly*/ true);

    if (!cam)
    {
        LOG_ERROR("module.rts", "RTS camera: could not summon creature {} for player '{}'",
                  kCameraEntry, player->GetName());
        return false;
    }

    // Nothing may fight it, target it, or assist it.
    cam->SetFaction(player->GetFaction());
    cam->SetUnitFlag(UnitFlags(UNIT_FLAG_NON_ATTACKABLE | UNIT_FLAG_NOT_SELECTABLE |
                               UNIT_FLAG_IMMUNE_TO_PC | UNIT_FLAG_IMMUNE_TO_NPC));
    cam->SetReactState(REACT_PASSIVE);

    // POSSESS it, do not merely SetClientControl. SetClientControl alone moves
    // the VIEW and nothing else -- confirmed in game, the camera detached and
    // then would not budge. The possess branch (Unit.cpp:14754, marked
    // "verified" in the core's own source) is what makes the client actually
    // drive the unit, and it roots the player's character as a side effect,
    // which is exactly what an RTS camera wants.
    if (!cam->SetCharmedBy(player, CHARM_TYPE_POSSESS))
    {
        LOG_ERROR("module.rts", "RTS camera: possession refused for player '{}'", player->GetName());
        Despawn(cam);
        return false;
    }

    // FLIGHT MUST BE SET AFTER POSSESSION, not before.
    //
    // SetCanFly and SetDisableGravity both branch on IsClientControlled()
    // (Unit.cpp:16569 and 16509). That is false until the possess path sets
    // UNIT_FLAG_PLAYER_CONTROLLED, so calling them first quietly took the
    // server-side branch: the flags went into m_movementInfo and the CLIENT was
    // never told. In game the camera refused to change height at all, with
    // space and X falling through to the character as a jump and a sit --
    // exactly what those keys do when the client is not in flight mode.
    //
    // No SetHover: hover pins a unit to a fixed height above the ground, which
    // is the opposite of what a free camera wants.
    //
    // Gravity is disabled either way -- that is what keeps the camera hanging
    // where it is put. FLIGHT is separate and now defaults OFF, because it is
    // what makes the client move the camera along the view vector instead of
    // across the ground: tilt down, press forward, descend. See SetFly.
    cam->SetDisableGravity(true);
    cam->SetCanFly(sConfigMgr->GetOption<bool>("RTS.Camera.Fly", false));
    ApplySpeed(cam, speed);

    g_cameras[player->GetGUID()] = cam->GetGUID();

    LOG_DEBUG("module.rts", "RTS camera on for '{}' (speed {}, at {:.1f} {:.1f} {:.1f})",
              player->GetName(), speed, cx, cy, cz);
    return true;
}

bool rts::camera::Disable(Player* player)
{
    if (!player)
        return false;

    auto it = g_cameras.find(player->GetGUID());
    if (it == g_cameras.end())
        return false;

    Creature* cam = ObjectAccessor::GetCreature(*player, it->second);
    g_cameras.erase(it);
    g_pivot.erase(player->GetGUID());

    // Release FIRST, despawn second. Despawning a unit the client is still
    // moving and seeing through is what took the client down the first time.
    Release(player, cam);
    Despawn(cam);

    LOG_DEBUG("module.rts", "RTS camera off for '{}'", player->GetName());
    return true;
}

bool rts::camera::Recenter(Player* player)
{
    Creature* cam = player ? FindCamera(player) : nullptr;
    if (!cam)
        return false;

    float cx, cy, cz;
    PlacementFor(player, cx, cy, cz);
    cam->NearTeleportTo(cx, cy, cz, player->GetOrientation());
    return true;
}

void rts::camera::SetOffset(Player const* player, float back, float up)
{
    if (!player)
        return;

    // Clamped so a bad value cannot put the camera somewhere the client will
    // not follow it to, or underground.
    back = std::max(-200.0f, std::min(200.0f, back));
    up   = std::max(-20.0f,  std::min(200.0f, up));
    g_offsets[player->GetGUID()] = Offset{ back, up };
}

bool rts::camera::MeasureOffset(Player const* player, float& back, float& up)
{
    Creature* cam = player ? FindCamera(player) : nullptr;
    if (!cam)
        return false;

    float const dx = cam->GetPositionX() - player->GetPositionX();
    float const dy = cam->GetPositionY() - player->GetPositionY();
    float const o  = player->GetOrientation();

    // Project the horizontal offset onto the character's facing. Negating it
    // gives "distance behind", which is the direction this is normally used in
    // and keeps the saved number positive for the common case.
    back = -(dx * std::cos(o) + dy * std::sin(o));
    up   = cam->GetPositionZ() - player->GetPositionZ();
    return true;
}

void rts::camera::ForgetOffset(Player const* player)
{
    if (player)
    {
        g_offsets.erase(player->GetGUID());
        g_vertical.erase(player->GetGUID());
    }
}

void rts::camera::SetVertical(Player const* player, int direction)
{
    if (!player)
        return;

    if (direction == 0)
        g_vertical.erase(player->GetGUID());
    else
        g_vertical[player->GetGUID()] = (direction > 0) ? 1 : -1;
}

void rts::camera::SetPivot(Player const* player, int direction)
{
    if (!player)
        return;

    if (direction == 0)
        g_pivot.erase(player->GetGUID());
    else
        g_pivot[player->GetGUID()] = (direction > 0) ? 1 : -1;
}

void rts::camera::Update(uint32 diff)
{
    // --- pivot ------------------------------------------------------------
    //
    // Orbit the camera around the point it is looking at. The focus is
    // recomputed from the CURRENT orientation every step, which is what keeps
    // it exactly still: with F = pos + D*(cos o, sin o), moving to
    // pos' = F - D*(cos o', sin o') and o' = o + a leaves F unchanged by
    // construction. No drift to correct, and no stored pivot to go stale if the
    // player pans mid-turn.
    if (!g_pivot.empty())
    {
        float const dist = PivotDistance();
        float const rate = PivotSpeed();

        for (auto it = g_pivot.begin(); it != g_pivot.end();)
        {
            Player* player = ObjectAccessor::FindPlayer(it->first);
            Creature* cam  = player ? FindCamera(player) : nullptr;
            if (!cam)
            {
                it = g_pivot.erase(it);
                continue;
            }

            float const o  = cam->GetOrientation();
            float const a  = rate * (static_cast<float>(diff) / 1000.0f)
                             * static_cast<float>(it->second);
            float const no = o + a;

            float const fx = cam->GetPositionX() + std::cos(o) * dist;
            float const fy = cam->GetPositionY() + std::sin(o) * dist;

            cam->NearTeleportTo(fx - std::cos(no) * dist,
                                fy - std::sin(no) * dist,
                                cam->GetPositionZ(), no);
            ++it;
        }
    }

    // --- height keys ------------------------------------------------------
    if (g_vertical.empty())
        return;

    // Matched to the horizontal speed by default, because "the camera moves at
    // one speed" is the whole expectation -- rising should not feel like a
    // different vehicle from panning. RTS.Camera.LiftSpeed overrides it with an
    // absolute yards-per-second if they ever want to differ.
    float rate = sConfigMgr->GetOption<float>("RTS.Camera.LiftSpeed", 0.0f);
    if (rate <= 0.0f)
        rate = baseMoveSpeed[MOVE_RUN] *
               sConfigMgr->GetOption<float>("RTS.Camera.Speed", kDefaultSpeed);

    for (auto it = g_vertical.begin(); it != g_vertical.end();)
    {
        Player* player = ObjectAccessor::FindPlayer(it->first);
        Creature* cam = player ? FindCamera(player) : nullptr;
        if (!cam)
        {
            it = g_vertical.erase(it);   // camera or player gone
            continue;
        }

        float const step = rate * (static_cast<float>(diff) / 1000.0f) * it->second;

        // NearTeleportTo, because the camera is client-controlled and there is
        // no server-side movement generator running on it to spline. That makes
        // the climb a series of small steps rather than a glide -- tune
        // RTS.Camera.LiftSpeed if the stepping shows; a slower rate with the
        // same tick interval is smoother, not coarser.
        cam->NearTeleportTo(cam->GetPositionX(), cam->GetPositionY(),
                            cam->GetPositionZ() + step, cam->GetOrientation());

        // The saved offset follows the camera up and down, so that recentring
        // and the next enable come back to the height you left it at rather
        // than snapping to where the framing was first saved.
        if (player)
        {
            auto off = g_offsets.find(player->GetGUID());
            if (off != g_offsets.end())
                off->second.up += step;
        }

        ++it;
    }
}

bool rts::camera::SetSpeed(Player* player, float speed)
{
    if (speed < 0.5f || speed > 50.0f)
        return false;

    Creature* cam = player ? FindCamera(player) : nullptr;
    if (!cam)
        return false;

    ApplySpeed(cam, speed);
    return true;
}

bool rts::camera::SetFly(Player* player, bool fly)
{
    Creature* cam = player ? FindCamera(player) : nullptr;
    if (!cam)
        return false;

    // Same ordering rule as Enable: the client is only told about a flight flag
    // change while the unit is client-controlled, which it is here because the
    // camera is possessed. Gravity is deliberately left disabled in both modes
    // -- dropping flight must not drop the camera out of the sky.
    cam->SetCanFly(fly);
    cam->SetDisableGravity(true);
    return true;
}

bool rts::camera::IsFlying(Player const* player)
{
    Creature* cam = player ? FindCamera(const_cast<Player*>(player)) : nullptr;
    return cam && cam->CanFly();
}

void rts::camera::Abandon(Player* player)
{
    if (!player)
        return;

    auto it = g_cameras.find(player->GetGUID());
    if (it == g_cameras.end())
        return;

    Creature* cam = ObjectAccessor::GetCreature(*player, it->second);
    g_cameras.erase(it);
    g_pivot.erase(player->GetGUID());

    // Same order as Disable. Even on the way out the viewpoint has to be torn
    // down before the creature goes, or the seer dangles.
    if (player->IsInWorld())
        Release(player, cam);

    Despawn(cam);
}
