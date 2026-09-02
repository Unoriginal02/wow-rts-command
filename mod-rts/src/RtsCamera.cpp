#include "RtsCamera.h"

#include "CharmInfo.h"   // CharmType / CHARM_TYPE_POSSESS -- Unit.h only forward-declares the enum
#include "Config.h"
#include "Creature.h"
#include "DBCStructure.h"   // SummonPropertiesEntry, built by hand below
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SharedDefines.h"   // SUMMON_CATEGORY_PUPPET
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

    constexpr float kDefaultPivotDist  = 12.0f;   // yards ahead of the camera
    constexpr float kDefaultPivotSpeed = 1.6f;    // radians per second

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

// A PUPPET, AND THAT IS THE WHOLE FIX FOR THE ABORT.
//
// The camera used to be an ordinary TempSummon that we possessed by hand with
// Unit::SetCharmedBy(player, CHARM_TYPE_POSSESS). That works -- and it is a
// LANDMINE, because the core undoes charms by removing AURAS, and a bare
// SetCharmedBy leaves none. Player::StopCastingCharm strips the four charm aura
// types, finds the player still charming something, and calls ABORT(): to the
// core, a charm it cannot unwind is its own state corrupted. Dying with the
// camera up killed the worldserver, and so would a flight path or a spec
// switch, and there is no hook for either.
//
// The core already has the answer, because it needs the same thing itself. A
// Puppet -- Eye of Acherus and friends -- IS an aura-less possession:
// Puppet::InitSummon does exactly the SetCharmedBy(owner, CHARM_TYPE_POSSESS)
// we were doing by hand. And StopCastingCharm opens with a branch for it:
//
//     if (charm->ToCreature()->HasUnitTypeMask(UNIT_MASK_PUPPET))
//         ((Puppet*)charm)->UnSummon();
//
// UnSummon -> Puppet::RemoveFromWorld -> RemoveCharmedBy(nullptr). The charm is
// gone before the check that aborts ever runs. So the camera does not need an
// aura and it does not need a hook for every unwind path in the core: it needs
// to BE the thing the core already knows how to take apart.
//
// Making it a Puppet is one argument: Map::SummonCreature switches on
// properties->Category, and WorldObject::SummonCreature already forwards a
// SummonPropertiesEntry. Ours is written here rather than looked up in
// SummonProperties.dbc on purpose -- every other field of a real row does
// something (Slot evicts whatever else is in that slot, Faction overrides the
// faction, Flags change the summon rules) and we want none of it. Six fields,
// five of them zero, and no DBC row to go missing.
//
// What comes with being a Minion: SetOwnerGUID, a place in the owner's
// m_Controlled (so RemoveAllControlled tidies it too), UNIT_FLAG_PLAYER_
// CONTROLLED, REACT_PASSIVE and the owner's level and faction. None of that
// fights what the camera wants; the pet slot is untouched because a Puppet is
// not a GuardianPet and Type 0 is not SUMMON_TYPE_MINIPET.
SummonPropertiesEntry const kPuppetProps =
{
    0,                          // Id     -- not looked up, never used
    SUMMON_CATEGORY_PUPPET,     // Category -- the only field that matters
    0,                          // Faction  -- 0 = keep the owner's
    SUMMON_TYPE_NONE,           // Type
    0,                          // Slot     -- 0 = evict nothing
    0                           // Flags
};

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

    // AND NOT WHILE THE CLIENT IS STILL ARRIVING. Possession mid-load is a
    // known-bad state, and the core says so in the most direct way available:
    // the failure log inside Puppet::InitSummon prints IsBeingTeleported() and
    // isBeingLoaded() -- somebody put those two there because that is what goes
    // wrong. A possession that half-succeeds leaves the client controlling
    // nothing, which costs the player their collision.
    if (player->IsBeingTeleported() || player->isBeingLoaded() ||
        player->IsDuringRemoveFromWorld())
    {
        LOG_DEBUG("module.rts", "RTS camera: refused for '{}' -- still arriving",
                  player->GetName());
        return false;
    }

    float const speed = sConfigMgr->GetOption<float>("RTS.Camera.Speed", kDefaultSpeed);

    float cx, cy, cz;
    PlacementFor(player, cx, cy, cz);

    // The properties are what make this a Puppet, and the Puppet is what
    // possesses itself in InitSummon -- so the camera is already being driven by
    // the client when this call returns. See the note on kPuppetProps.
    TempSummon* cam = player->SummonCreature(
        kCameraEntry,
        cx, cy, cz,
        player->GetOrientation(),
        TEMPSUMMON_MANUAL_DESPAWN, 0, &kPuppetProps,
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

    // POSSESSION IS ALREADY DONE, by Puppet::InitSummon inside the summon
    // above. It is still the same call we used to make by hand -- possess, not
    // merely SetClientControl, because SetClientControl alone moves the VIEW and
    // nothing else (confirmed in game: the camera detached and then would not
    // budge). The possess branch is what makes the client drive the unit, and it
    // roots the player's character as a side effect, which is what an RTS camera
    // wants.
    //
    // It is CHECKED and not assumed: InitSummon only logs when SetCharmedBy
    // fails (the ABORT beside it is commented out in the core), so a refusal
    // would otherwise leave a camera creature standing there that the client
    // cannot move -- which reads as "the camera is broken" rather than as "the
    // possession was refused".
    if (cam->GetCharmerGUID() != player->GetGUID())
    {
        LOG_ERROR("module.rts", "RTS camera: possession refused for player '{}' "
                  "(already charming something?)", player->GetName());
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
    // --- the sweep --------------------------------------------------------
    //
    // Anything in the core may now take the camera down without telling us --
    // that is the POINT of it being a Puppet -- so our own table has to be able
    // to notice. A stale entry would leave IsActive() saying yes about a
    // creature that is gone: the addon would think the camera is on, and
    // re-enabling would be refused as already-on.
    //
    // Cheap because it only runs while a camera exists, which is almost never
    // more than one.
    for (auto it = g_cameras.begin(); it != g_cameras.end();)
    {
        Player* player = ObjectAccessor::FindPlayer(it->first);
        Creature* cam = player ? ObjectAccessor::GetCreature(*player, it->second) : nullptr;

        // Gone, or no longer ours. Either way it is not a camera any more.
        if (player && (!cam || cam->GetCharmerGUID() != player->GetGUID()))
        {
            LOG_DEBUG("module.rts", "RTS camera for '{}' was taken down elsewhere; "
                      "forgetting it", player->GetName());
            g_pivot.erase(it->first);
            g_vertical.erase(it->first);
            it = g_cameras.erase(it);

            // The creature is already gone, so the viewpoint is the only thing
            // that could still dangle -- and a dangling seer is what takes the
            // CLIENT down with ERROR #134 on the next reload.
            if (WorldObject* seen = player->GetViewpoint())
                player->SetViewpoint(seen, false);
            continue;
        }
        ++it;
    }

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
    //
    // The LAST section, and the only one that touches the camera's Z. There
    // used to be a ground hold below this -- keep a constant clearance over the
    // terrain while panning -- and it is GONE, not parked: both mechanisms were
    // seen in game 2026-08-23 and both were worse than no feature at all. The
    // server-side one (measure the terrain, NearTeleportTo) descends in visible
    // steps and each teleport cancels the movement the client is applying, so
    // panning stops dead every step. The client-side one (UNIT_FIELD_HOVERHEIGHT
    // + SMSG_MOVE_SET_HOVER) needs gravity back ON to have any ground-following
    // to modify, and gravity is what the camera has disabled so it hangs where
    // it is put -- so arming it drops the camera to the floor and the hover then
    // lifts it back, every time. That drop IS the mechanism, not a bug in it.
    //
    // So the camera is back to what it always was: it hangs at the height it is
    // given, and Q/E -- SPACE/C now -- are the only thing that moves it.
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

// WHAT THIS IS FOR, because a function that quietly fixes things is worthless
// if nobody knows what it was fixing.
//
// The symptom: entering the world, the character clips through the ground and
// falls forever. The server logs nothing -- and that absence is the clue. If the
// server thought the character were under the map it would say so and yank them
// to a graveyard; the saved position is a perfectly ordinary bit of Elwynn. So
// the server's idea of the character is fine and the CLIENT's is not: it came
// back into the world without control of its own character, and a client that is
// not the mover has no collision.
//
// Which is exactly the shape of a possession that was taken apart badly. The
// camera hands control of the character away, and every path that gives it back
// runs through Unit::RemoveCharmedBy -- which has an early return in it:
//
//     if (!charmer) return;      // "If charmer still exists"
//
// Everything that restores the player is BELOW that line: SetClientControl,
// RemoveUnitFlag(UNIT_FLAG_DISABLE_MOVE), SetCharm(this, false). So a teardown
// that happens while the player cannot be resolved -- mid-logout, mid-map-change
// -- undoes the charm halfway and leaves the client with nothing to drive. No
// error, no log line, and the damage is only visible on the NEXT login.
//
// So this does not try to prove which path did it. It checks the four things
// that must be true for a player who is standing in the world under their own
// control, and puts back whatever is not. Every repair is logged, because a
// rescue that fires silently every login is a bug we would never hear about.
void rts::camera::Rescue(Player* player)
{
    if (!player || !player->IsInWorld())
        return;

    // 1. A viewpoint. Ours is always a camera creature that no longer exists by
    //    the time we get here, and a dangling seer is what takes the CLIENT down
    //    with ERROR #134 on the next reload.
    if (WorldObject* seen = player->GetViewpoint())
    {
        LOG_INFO("module.rts", "RTS rescue: '{}' entered the world still seeing "
                 "through something else", player->GetName());
        player->SetViewpoint(seen, false);
    }

    ObjectGuid const charmed = player->GetCharmGUID();
    if (charmed)
    {
        Unit* charm = ObjectAccessor::GetUnit(*player, charmed);
        if (charm && charm->GetEntry() == kCameraEntry)
        {
            // 2. Still possessing a camera. Take it apart properly, which from
            //    here works because the player is resolvable again.
            LOG_INFO("module.rts", "RTS rescue: '{}' entered the world still "
                     "possessing a camera; releasing it", player->GetName());
            charm->RemoveCharmedBy(player);
            if (Creature* c = charm->ToCreature())
                c->DespawnOrUnsummon();
        }
        else if (!charm)
        {
            // 3. Possessing a unit that does not exist. This is the state that
            //    costs the collision, and there is no polite way out of it:
            //    StopCastingCharm cannot help, because it starts by resolving
            //    the charm and gives up when that fails. The field is cleared by
            //    hand and control handed back.
            LOG_INFO("module.rts", "RTS rescue: '{}' entered the world charming a "
                     "unit that no longer exists ({}); clearing it",
                     player->GetName(), charmed.ToString());
            player->SetGuidValue(UNIT_FIELD_CHARM, ObjectGuid::Empty);
            player->RemoveUnitFlag(UNIT_FLAG_DISABLE_MOVE);
            player->SetClientControl(player, true);
        }
    }
    else if (player->HasUnitFlag(UNIT_FLAG_DISABLE_MOVE))
    {
        // 4. Rooted by a possession that is over. UNIT_FLAG_DISABLE_MOVE is the
        //    flag the possess path puts on the CHARMER, and with nothing charmed
        //    there is nothing that should still be holding it. Ordinary roots do
        //    not use this flag -- they are UNIT_STATE_ROOT and an aura -- so this
        //    is not stepping on a live effect.
        LOG_INFO("module.rts", "RTS rescue: '{}' entered the world rooted by a "
                 "possession that is over", player->GetName());
        player->RemoveUnitFlag(UNIT_FLAG_DISABLE_MOVE);
        player->SetClientControl(player, true);
    }
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
