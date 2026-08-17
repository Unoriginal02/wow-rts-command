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

    // Q/E turn rate, as a multiple of the base 3.141594 rad/s (180 deg/s).
    // Below 1 is slower. This is MOVE_TURN_RATE, which the server really does
    // own even though the client is the one driving: SetSpeed sends
    // SMSG_FORCE_TURN_RATE_CHANGE and the client turns at whatever it is told.
    // ApplySpeed used to leave this type alone entirely, so the camera spun at
    // a full 180 deg/s -- fine for a character dodging, far too fast for framing
    // a shot.
    constexpr float kDefaultTurnRate = 0.6f;

    // Seconds from a standing start to full pan speed. 0 disables the ramp and
    // restores the old instant-on behaviour.
    constexpr float kDefaultAccel = 0.35f;

    // Speed the camera sits at while it is NOT moving, as a fraction of full.
    //
    // The ramp has to be armed BEFORE the client starts moving, not after: the
    // server only learns about a keypress from the movement packet that follows
    // it, and by then the first strides have already happened at whatever speed
    // was in force. So an idle camera is parked at this fraction, and the ramp
    // is a climb away from it rather than a dip and a recovery.
    constexpr float kEaseFloor = 0.22f;

    // What each camera is currently being driven at. `target` and `turn` are the
    // configured values; `ease` is where the ramp has got to, 0..1 as a fraction
    // of target.
    struct Drive { float target; float turn; float ease; };
    std::unordered_map<ObjectGuid, Drive> g_drive;   // player -> drive state

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

    // Give every direction the SAME absolute speed.
    //
    // `speed` arrives as a multiple of base run speed, and the obvious thing --
    // applying that rate to each move type -- does not work, because every type
    // has a different base: run is 7.0 yards/s but run-BACK is 4.5. The same
    // rate on both therefore leaves reversing visibly slower than advancing,
    // which is exactly how it felt in game. A camera has no business being
    // faster one way than the other, so convert to an absolute target once and
    // give each type whatever rate reproduces it.
    // MOVE_TURN_RATE is deliberately NOT in this list: turning is not a
    // direction of travel, so giving it the same absolute yards-per-second as
    // the others is meaningless -- its unit is radians per second. It is set
    // separately, and only when it changes, by ApplyTurn below.
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

    void ApplyTurn(Creature* cam, float rate)
    {
        cam->SetSpeed(MOVE_TURN_RATE, rate, true);
    }

    float ConfiguredAccel()
    {
        return sConfigMgr->GetOption<float>("RTS.Camera.Accel", kDefaultAccel);
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
    // Start parked at the floor, not at full speed: the ramp has to be armed
    // before the first keypress, because the server only hears about one after
    // the fact. See the note in Update().
    float const turn = sConfigMgr->GetOption<float>("RTS.Camera.TurnRate", kDefaultTurnRate);
    float const ease = ConfiguredAccel() > 0.0f ? kEaseFloor : 1.0f;

    ApplySpeed(cam, speed * ease);
    ApplyTurn(cam, turn);

    g_drive[player->GetGUID()] = { speed, turn, ease };
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
    g_drive.erase(player->GetGUID());

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

void rts::camera::Update(uint32 diff)
{
    // --- easing -----------------------------------------------------------
    //
    // WoW has no acceleration: a movement key is on or off, and the unit is at
    // full speed on the first frame or stopped. That is right for a character
    // and wrong for a camera, where the snap is what makes a pan feel like a
    // teleport rather than a move.
    //
    // The ramp is done by changing the camera's SPEED, not its position, so the
    // client stays in charge of driving and there is nothing to fight. Cost is
    // one forced-speed packet per step, which is why it only sends when the
    // value actually moved (kEpsilon) and stops sending once it is at target.
    //
    // DECELERATION IS NOT DONE HERE AND CANNOT BE. When the key comes up the
    // client stops the unit itself, on its own authority, before the server
    // hears about it -- so there is no movement left whose speed we could ramp
    // down. A glide would mean the server pushing the camera on after the
    // client believes it has stopped, which is the one thing possession makes
    // expensive. See the note in RtsCamera.h.
    float const accel = ConfiguredAccel();
    constexpr float kEpsilon = 0.02f;

    for (auto it = g_drive.begin(); it != g_drive.end();)
    {
        Player* player = ObjectAccessor::FindPlayer(it->first);
        Creature* cam  = player ? FindCamera(player) : nullptr;
        if (!cam)
        {
            it = g_drive.erase(it);
            continue;
        }

        Drive& d = it->second;
        float const want = cam->isMoving() ? 1.0f : kEaseFloor;

        float next;
        if (accel <= 0.0f)
        {
            next = want;                       // ramp off: old instant behaviour
        }
        else if (want > d.ease)
        {
            next = std::min(want, d.ease + (1.0f - kEaseFloor)
                                           * (static_cast<float>(diff) / 1000.0f) / accel);
        }
        else
        {
            // Back to the floor at once. There is nothing to glide (see above),
            // and leaving it high would mean the NEXT press started at full
            // speed -- which is exactly the snap the ramp exists to remove.
            next = want;
        }

        if (std::fabs(next - d.ease) > kEpsilon || (next == want && d.ease != want))
        {
            d.ease = next;
            ApplySpeed(cam, d.target * next);
        }

        ++it;
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

    // Through the drive state, so the ramp keeps working after a speed change
    // instead of being overwritten back to full on the next tick.
    auto it = g_drive.find(player->GetGUID());
    float const ease = (it != g_drive.end()) ? it->second.ease : 1.0f;
    if (it != g_drive.end())
        it->second.target = speed;

    ApplySpeed(cam, speed * ease);
    return true;
}

bool rts::camera::SetTurnRate(Player* player, float rate)
{
    // 0.05 is about 9 deg/s, slow enough to be useless but not broken; 3.0 is
    // three times the client's own turn and already unusable. The range only
    // exists to keep a typo from making the camera unrecoverable.
    if (rate < 0.05f || rate > 3.0f)
        return false;

    Creature* cam = player ? FindCamera(player) : nullptr;
    if (!cam)
        return false;

    auto it = g_drive.find(player->GetGUID());
    if (it != g_drive.end())
        it->second.turn = rate;

    ApplyTurn(cam, rate);
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
    g_drive.erase(player->GetGUID());

    // Same order as Disable. Even on the way out the viewpoint has to be torn
    // down before the creature goes, or the seer dangles.
    if (player->IsInWorld())
        Release(player, cam);

    Despawn(cam);
}
