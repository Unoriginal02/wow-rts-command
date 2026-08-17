#ifndef MOD_RTS_CAMERA_H
#define MOD_RTS_CAMERA_H

#include "Define.h"   // uint32, for the tick Update() takes

class Player;

namespace rts
{
    // A detached RTS camera, free flight only.
    //
    // The client's camera always looks at whatever unit the client is currently
    // MOVING -- its "active mover". So rather than fighting the camera struct
    // from outside the process, we summon an invisible creature and hand the
    // client control of it. The camera follows it because that is what the
    // camera does, WASD flies it because that is what movement keys do, and the
    // player's own character stays where it was standing, in view below.
    //
    // This is the mechanism behind Eye of Kilrogg, Mind Control and Far Sight.
    // See Player::SetClientControl (Player.cpp), which sends
    // SMSG_CLIENT_CONTROL_UPDATE and then does SetViewpoint + SetMover.
    //
    // Server-driven follow and frame modes were built here and REMOVED
    // 2026-08-14: driving the camera from the server means giving up
    // possession, and a camera the player cannot grab and correct is worse than
    // one that simply stays where it is put. Fine positioning belongs to the
    // hand on the mouse, which is what the addon's mouselook-while-flying does
    // instead.
    namespace camera
    {
        bool Enable(Player* player);
        bool Disable(Player* player);
        bool IsActive(Player const* player);
        bool SetSpeed(Player* player, float speed);

        // Q/E turn rate, as a multiple of the client's own 180 deg/s. Below 1
        // is slower.
        //
        // Q and E are bound to the client's TURNLEFT/TURNRIGHT, so the turn is
        // the client's own smooth continuous one -- but the RATE is
        // MOVE_TURN_RATE, which is the server's to set even for a unit the
        // client is driving (SetSpeed sends SMSG_FORCE_TURN_RATE_CHANGE).
        // ApplySpeed never touched that move type, so the camera inherited the
        // full character turn rate.
        bool SetTurnRate(Player* player, float rate);

        // ACCELERATION, AND WHY THERE IS NO DECELERATION.
        //
        // The pan ramps up from a standing start over RTS.Camera.Accel seconds,
        // done by changing the camera's speed while the client keeps driving it
        // -- so there is no server-side movement fighting the client for the
        // position.
        //
        // The same trick cannot give a glide on release. The client stops the
        // unit on its own authority the moment the key comes up, and the server
        // only finds out afterwards; by then there is no motion left to slow
        // down. Coasting would mean the server pushing the camera onward after
        // the client believes it has stopped, which is a position fight with
        // possession -- a different and much more expensive job than this.

        // Flight mode, live-switchable, because it decides how WASD behaves and
        // the two behaviours are opposites.
        //
        // WITH flight the client moves the camera along the VIEW vector: tilt
        // down, press forward, and you descend. That is correct for a flying
        // mount and wrong for an RTS, where forward means forward across the
        // map no matter how far down the camera is looking.
        //
        // WITHOUT it -- gravity still disabled, so the camera hangs where it is
        // put -- the client moves it horizontally and the tilt only affects what
        // you SEE. That is the WC3 behaviour. The cost is that space and X stop
        // raising and lowering it, because those are flight actions; height
        // becomes the addon's job.
        bool SetFly(Player* player, bool fly);
        bool IsFlying(Player const* player);

        // Put the camera back over its saved offset from the character.
        bool Recenter(Player* player);

        // Where the camera sits relative to the character, as a distance BEHIND
        // (along the character's facing) and a height ABOVE.
        //
        // SaveView on the client stores the camera's pitch and its distance from
        // whatever it is orbiting -- but not where that thing is standing. So a
        // saved framing came back at the right angle with the party sitting in
        // the wrong part of the screen. This is the missing half: the camera
        // creature's own placement, measured once and reapplied on every enable.
        void SetOffset(Player const* player, float back, float up);

        // The offset the camera is at RIGHT NOW, for saving. False if no camera.
        bool MeasureOffset(Player const* player, float& back, float& up);

        // Drop a player's saved offset (logout, or an explicit clear).
        void ForgetOffset(Player const* player);

        // Vertical drive: -1 down, 0 stop, +1 up. Held while the key is held.
        //
        // Height HAS to come from the server. The camera is possessed, so the
        // client owns its position -- and with flight off (which is what makes
        // WASD run flat) the client has no vertical movement to give. So the
        // addon reports the key state and Update() below does the moving.
        //
        // The alternative was to make Q/E zoom, which changes the DISTANCE to
        // the group rather than the height, and is now what the scroll wheel is
        // for.
        void SetVertical(Player const* player, int direction);

        // Called every world tick; moves any camera with a live vertical drive.
        void Update(uint32 diff);

        // Drop the camera WITHOUT handing control back -- for logout and map
        // changes, where the player object is going away anyway and touching
        // client control would be pointless or unsafe.
        void Abandon(Player* player);
    }
}

#endif  // MOD_RTS_CAMERA_H
