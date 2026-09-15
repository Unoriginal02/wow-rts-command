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

        // NO GROUND HOLD. Keeping a constant clearance over the terrain while
        // panning was built and both mechanisms were seen in game 2026-08-23;
        // both are gone rather than parked, because each fails in a way that is
        // inherent to it and not to the tuning:
        //
        //   the server measuring the terrain and moving the camera with
        //   NearTeleportTo descends in visible steps, and every teleport
        //   cancels the movement the CLIENT is applying -- so forward motion
        //   stops dead on each one. It feels like a lift, not a camera.
        //
        //   UNIT_FIELD_HOVERHEIGHT + SMSG_MOVE_SET_HOVER is the client's own
        //   "float this unit N yards over the ground", and it needs GRAVITY ON
        //   to have any ground-following to modify. Gravity is exactly what the
        //   camera has disabled so that it hangs where it is put -- so arming
        //   hover drops the camera to the floor and the hover then lifts it
        //   back. The drop is the mechanism, not a bug in it.
        //
        // The header used to justify the absence of hover with "hover pins a
        // unit to a fixed height above the ground, which is the opposite of
        // what a free camera wants". That reason had expired -- a ground hold
        // is what was asked for -- and the new reason is the gravity coupling,
        // which is not a matter of what we want. If it is ever revisited, the
        // thing to find first is a way to get client-side ground-following
        // without gravity, because without that both roads lead back here.

        // Pivot drive: -1 left, 0 stop, +1 right. Held while Q or E is held.
        //
        // ORBIT, NOT YAW. Q/E were bound to the client's own TURNLEFT/TURNRIGHT,
        // which turns the camera where it stands -- so whatever you were looking
        // at swings off the screen. Pivoting carries the camera around an arc
        // centred on the point it is looking at, which stays put while you see
        // it from a new side. That is the WC3/SC2 gesture and the reason to want
        // it.
        //
        // The cost is that it has to come from the server. Yaw was free because
        // the client owns turning; an orbit is a change of POSITION, and the
        // camera is possessed, so only NearTeleportTo can move it -- the same
        // per-tick stepping the height keys use, with the same risk of showing
        // as steps rather than a glide. RTS.Camera.PivotSpeed is the dial if it
        // does.
        void SetPivot(Player const* player, int direction);

        // Called every world tick; moves any camera with a live vertical drive.
        void Update(uint32 diff);

        // Drop the camera WITHOUT handing control back -- for logout and map
        // changes, where the player object is going away anyway and touching
        // client control would be pointless or unsafe.
        void Abandon(Player* player);

        // Put a player back in control of their own character, whatever we left
        // behind. Called on every world entry: a client that comes back without
        // control of itself has no collision, so the character clips through the
        // ground and falls forever -- and the server never notices, because ITS
        // idea of where the character is stays perfectly valid. See the note on
        // the implementation.
        void Rescue(Player* player);

        // === THE PROBE INTO THE CLIENT'S OWN FREE CAMERA ===================
        //
        // Opens (or closes) the client's COMMENTATOR camera, which is a free
        // camera with a Lua API that this `Wow.exe` already ships:
        //
        //     CommentatorSetCamera(x, y, z, yaw, pitch, fov)   0x0056A0F0
        //     CommentatorSetCameraCollision(bool)              0x0056AB70
        //     CommentatorFollowPlayer(faction, index)          0x00569B50
        //     CommentatorSetTargetHeightOffset(float)
        //     CommentatorSetMoveSpeed(speed)
        //
        // POR QUE IMPORTA. Todo lo que la camara de HOY no puede hacer sale de
        // una sola causa: es una criatura del servidor que el jugador POSEE, o
        // sea que el CLIENTE es dueño de su posicion y desde aqui solo se la
        // puede mover con `NearTeleportTo` -- que CANCELA el movimiento que el
        // cliente esta aplicando. De ahi salen, con la misma causa, que no se
        // pueda avanzar y subir a la vez (ver `SetVertical`) y que la altura
        // sobre el terreno se construyera por los dos caminos y se borrara el
        // 2026-08-23 (ver el bloque NO GROUND HOLD de arriba).
        //
        // Si el cliente dibuja desde la camara de comentarista en mundo
        // abierto, eso se cae entero: el cliente pasa a ser dueño de la camara
        // y nosotros solo del objetivo, que es aritmetica en Lua a frame rate.
        //
        // === LA PUERTA SON DOS FLAGS Y LOS PONEMOS NOSOTROS ================
        //
        // El predicado del cliente en `0x006DE980`, desensamblado de ESTE
        // binario (MD5 45892BDEDD0AD70AED4CCD22D9FB5984):
        //
        //     mov ecx, [player + 0x1008]
        //     mov ecx, [ecx + 8]
        //     shr edx, 0x13 ; test bit 19  -> APAGADO: return false
        //     shr ecx, 0x16 ; test bit 22  -> ENCENDIDO: return true, y ya
        //                                  ; si no: hace falta mapa tipo 4
        //
        // OJO: DESDE 2026-09-11 EL SERVIDOR SOLO PONE EL BIT 22. El bit 19 lo
        // escribe `rts_core` en la memoria del cliente, porque el nucleo se niega
        // a dejar atacar a quien lo lleve (`Unit.cpp:10762`). Ver `Spectate`.
        // Bit 19 y bit 22 son `PLAYER_FLAGS_UBER` (0x00080000) y
        // `PLAYER_FLAGS_COMMENTATOR2` (0x00400000) -- comprobados contra el
        // enum del propio nucleo (`Player.h:478,481`) y no de memoria. El 22
        // solo es lo que SALTA el requisito de estar en una arena; el 19 es
        // obligatorio. Y el nucleo ya trae el setter del 22:
        // `Player::SetCommentator(bool)` (`Player.h:1169`).
        //
        // === Y EL MODO LO ARBITRA EL SERVIDOR, QUE SOMOS NOSOTROS ==========
        //
        // `CommentatorToggleMode` manda `CMSG_COMMENTATOR_ENABLE` (0x3B5) y
        // espera `SMSG_COMMENTATOR_STATE_CHANGED` (0x3B6). Su manejador en el
        // cliente (`0x0056B8A0`) lee `uint64 guid` + `uint8 enable`, exige que
        // el guid sea el del receptor, vuelve a pasar por el mismo predicado, y
        // entonces mete la camara activa en modo comentarista.
        //
        // NO HACE FALTA QUE EL CLIENTE LO PIDA, y de hecho no se puede
        // escuchar: `CMSG_COMMENTATOR_ENABLE` es `STATUS_NEVER` +
        // `Handle_NULL` (`Opcodes.cpp:1080`), y `STATUS_NEVER` ni llega a
        // `CanPacketReceive` -- su `case` solo hace `LOG_ERROR` y `break`. Asi
        // que el addon lo pide por su canal y el 0x3B6 lo mandamos aqui. Que
        // ese opcode este declarado `STATUS_NEVER` tampoco impide MANDARLO:
        // `WorldSession::SendPacket` solo rechaza `NULL_OPCODE`.
        //
        // === LOS FLAGS SE DEVUELVEN, QUE ES LA REGLA DURA ==================
        //
        // `PLAYER_FLAGS_UBER` puesto y olvidado es estado del jugador que
        // sobrevive a la sesion. Se quitan en `Spectate(false)`, en el logout y
        // en `Abandon`, igual que `Camera.lua` hace con sus CVars.
        //
        // ESTO ES UN SONDEO. No cambia nada del camino del Puppet: la camara
        // de siempre sigue funcionando igual mientras esto se prueba.
        //
        // === Y VA EN DOS MITADES, QUE ES LO QUE COSTO LA PRIMERA PASADA =====
        //
        // `Spectate` pone los flags y NADA MAS. `Arm` manda el paquete. La
        // primera version hacia las dos cosas de golpe y era una carrera:
        // `SetPlayerFlag` solo marca el campo sucio -- la actualizacion sale en
        // el siguiente flush, ~100 ms despues -- mientras que `SendPacket` sale
        // ya. El paquete llegaba primero, el predicado leia los flags viejos, y
        // **la rama de puerta cerrada no es un no-op**: cae en la misma que
        // `enable == 0` y mete la camara en modo 1 con el estado que hubiera.
        // En pantalla, la camara se fue lejisimo y bajo el suelo.
        //
        // Quien decide cuando armar es el CLIENTE: el addon sondea
        // `CommentatorGetCamera()`, que devuelve seis numeros en cuanto la
        // puerta esta abierta, y solo entonces pide `Arm`. Misma leccion que
        // `HasServer()` y que el `PORTED` del cambio de personaje.
        bool Spectate(Player* player, bool on);
        bool Arm(Player* player, bool on);

        // ¿Esta este jugador en la camara libre? Lo pregunta `orders::MoveSelf`
        // para saber si puede mover el cuerpo: con la camara libre el cliente
        // ya no conduce al personaje, aunque no haya ninguna posesion.
        bool IsSpectating(Player const* player);

        // QUIEN CONDUCE EL CUERPO, Y ES UN TRATO CON DOS MITADES.
        //
        // `SetClientControl(player, false)` deja que el servidor mueva tu
        // personaje (lo pide `orders::MoveSelf`), y a cambio **el cliente se
        // apaga entero para pelear**: escribe un cero en `0x00BCFB8C` y ese
        // global es el que miran tanto el cursor de ataque (`0x004F7FA5`) como
        // el ataque de verdad (`0x0072C3E9`). Ni espada ni click derecho.
        //
        // De fabrica el cliente SE QUEDA el control -- el raton normal pesa mas
        // -- y esto lo cambia en caliente para poder medir el otro lado.
        bool HoldControl(Player* player, bool on);
        bool HoldsControl(Player const* player);

    }
}

#endif  // MOD_RTS_CAMERA_H
