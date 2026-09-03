#ifndef MOD_RTS_SWAP_H
#define MOD_RTS_SWAP_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;
class WorldSession;

namespace rts
{
    // CAMBIAR DE PERSONAJE SIN CERRAR SESION: dejas el heroe, coges al
    // compañero, y el que dejas se queda de bot.
    //
    // === POR QUE ESTO NO ES UNA LOCURA, Y NO TOCA AzerothCore ==============
    //
    // Porque **mod-playerbots ya lo hace**, desde un modulo y con API publica,
    // cada vez que mete un bot en el mundo. La secuencia entera esta en
    // `PlayerbotMgr.cpp:148-210` y es esta:
    //
    //     auto holder = std::make_shared<LoginQueryHolder>(accountId, guid);
    //     holder->Initialize();
    //     sWorld->AddQueryHolderCallback(CharacterDatabase.DelayQueryHolder(holder))
    //         .AfterComplete([](SQLQueryHolderBase const& qh) {
    //             session->HandlePlayerLoginFromDB(static_cast<LoginQueryHolder const&>(qh));
    //         });
    //
    // Las cuatro piezas son publicas y estan en cabeceras que un modulo ve:
    // `LoginQueryHolder` en `WorldSession.h:293` (no escondida en el .cpp, que
    // es lo que habria matado la idea), `LogoutPlayer` en `:546`,
    // `HandlePlayerLoginFromDB` en `:695`, y `AddQueryHolderCallback` en
    // `World.h:265`.
    //
    // La unica diferencia con lo que hace playerbots es que aqui NO se crea una
    // sesion nueva: se reutiliza la del jugador y se le cambia el personaje
    // debajo.
    //
    // === POR QUE YA NO HACE FALTA LA PANTALLA DE SELECCION ================
    //
    // La primera version mandaba `LogoutPlayer(true)` y con el
    // `SMSG_LOGOUT_COMPLETE` el cliente se iba a la lista de personajes. Ahi
    // **cambia su tabla de eventos** de las 722 del mundo a 41, y la rafaga de
    // login que llegaba detras disparaba el evento 492 --
    // `FrameScript_SignalEvent` no comprueba el rango y el cliente moria con
    // ERROR #132 (2026-09-03, todo el detalle en `CLAUDE.md`).
    //
    // La lectura de entonces fue *"el cliente no acepta un login que empieza en
    // el servidor"*. **Era falsa, y la falsedad estaba a una instruccion de
    // distancia.** Lo que el cliente no acepta es un login ESTANDO EN LA
    // PANTALLA DE SELECCION. Dentro del mundo la tabla buena esta puesta, el
    // evento 492 esta en rango, y no pasa nada.
    //
    // Y la identidad -- el "ahora eres otro", que parecia lo imposible -- la
    // cambia un paquete corriente. Desensamblado el manejador de creacion de
    // objeto del cliente (`0x004D6C00`):
    //
    //     004D6CC8  test byte ptr [ebp-0x44], 1     ; UPDATEFLAG_SELF
    //     004D6CCC  je   0x4D6CF6
    //     004D6CE7  mov  [objmgr + 0xC0], guid.lo   ; <-- "yo soy este"
    //     004D6CF0  mov  [objmgr + 0xC4], guid.hi
    //
    // Sin mas condiciones: **el cliente adopta como suyo cualquier objeto que
    // llegue con `UPDATEFLAG_SELF`**, este donde este. Y ese paquete lo manda
    // `Map::SendInitSelf`, que es una de las llamadas de
    // `HandlePlayerLoginToCharInWorld`/`FromDB` -- o sea que la rafaga de login
    // ya sabe hacerlo y siempre lo supo.
    //
    // Asi que el logout se queda (hace falta: guarda el heroe y lo saca del
    // mundo) y lo que se quita es que el CLIENTE se entere:
    // `WorldSession::SendPacket` pasa por `sScriptMgr->CanPacketSend`
    // (`WorldSession.cpp:356`), asi que un `ServerScript` se traga el
    // `SMSG_LOGOUT_COMPLETE` durante el cambio. El cliente sigue en el mundo,
    // con su tabla de 722, y un instante despues le llega la rafaga del otro
    // personaje.
    //
    // === EL PSEUDO-LOGIN PRECARGADO, QUE ES LO QUE HACE LA VENTANA CERO =====
    //
    // Entre el logout y el login el cliente esta en el mundo con un personaje
    // que el servidor ya ha borrado. Esa ventana tiene que ser CERO, no corta:
    // el cliente sigue mandando movimiento y el servidor no tiene a quien
    // aplicarselo.
    //
    // Por eso la consulta del personaje de destino se lanza ANTES de soltar el
    // heroe y se guarda el `LoginQueryHolder` resuelto. Cuando llega, el logout
    // y el login pasan **en la misma vuelta del mundo**, sin ninguna espera de
    // base de datos en medio.
    //
    // Es exactamente la idea de *"un pseudo login que no acabe de finalizarse"*.
    // Lo que se precarga no es el `Player` -- ese ya existia, es un bot -- sino
    // la CONSULTA, que es la unica parte que tardaba.
    //    // === LA REGLA DURA: SOLO TU PROPIA CUENTA ==============================
    //
    // El personaje de destino tiene que ser de la MISMA cuenta. `WorldSession`
    // lleva un `accountId` y lo usan el correo, la hermandad, los objetos de
    // cuenta y el guardado; meter en tu sesion un personaje de otra cuenta
    // "funciona" y corrompe despacio, que es la peor clase de que funcione.
    //
    // `HandlePlayerLoginFromDB` NO comprueba eso -- la comprobacion vive en
    // `HandlePlayerLoginOpcode` (`IsLegitCharacterForAccount`), que es privada y
    // que aqui no se pasa. Asi que la hacemos nosotros, y por eso esto sirve
    // para TUS ALTS y no para los bots aleatorios.
    namespace swap
    {
        // Empezar el cambio. Devuelve false y llena `why` si no se puede ni
        // intentar (otra cuenta, no existe, ya estas en ese, hay uno en curso).
        //
        // Devolver true NO quiere decir que el cambio se haya hecho: quiere
        // decir que empieza. `Update` lo lleva por sus tres fases.
        bool To(Player* master, std::string const& name, std::string* why = nullptr);

        // Del tick del mundo. `justSwapped` recoge a quien acaba de entrar en su
        // personaje nuevo, para que el canal del addon siga viviendo en un solo
        // sitio (`mod_rts.cpp`) en vez de repartirse por los ficheros de
        // dominio: este espacio de nombres no sabe hablar con el cliente y no
        // hace falta que aprenda.
        void Update(uint32 diff, std::vector<Player*>* justSwapped = nullptr);

        // EL CLIENTE DICE QUE YA HA RECARGADO EL MUNDO. Lo manda el addon al
        // recibir `PLAYER_ENTERING_WORLD`, y es lo unico que sabe de verdad
        // cuando el mundo del cliente esta otra vez en pie.
        //
        // HIZO FALTA PORQUE EL ACUSE DEL PROPIO CLIENTE NO SE PUEDE VER. El
        // `MSG_MOVE_WORLDPORT_ACK` es `STATUS_TRANSFER`, y el nucleo solo
        // procesa esa clase de paquete **cuando el jugador NO esta en el mundo**
        // (`WorldSession.cpp:497`, `if (_player && !_player->IsInWorld())`).
        // Aqui el heroe sigue dentro -- todavia no se ha soltado -- asi que el
        // acuse se tira antes de llegar a ningun gancho. El cliente lo mandaba;
        // no habia forma de enterarse.
        bool ClientPorted(Player* master);

        // EL PAQUETE QUE EL CLIENTE NO DEBE VER. `mod_rts.cpp` engancha un
        // `ServerScript::CanPacketSend` que pregunta esto por cada paquete
        // saliente y descarta el que diga.
        //
        // Solo dice que si al `SMSG_LOGOUT_COMPLETE` de la sesion que esta
        // cambiando, y solo durante la llamada a `LogoutPlayer` -- se arma y se
        // desarma alrededor de ella, en la misma vuelta. Fuera de esa ventana
        // NO filtra nada, que es lo que impide que un cambio a medias deje a un
        // jugador sin poder salir del juego nunca mas.
        bool SuppressOutgoing(WorldSession* session, uint16 opcode);

// AQUI HABIA UN `NoticeIncoming` QUE MIRABA EL ACUSE DEL CLIENTE, y esta
        // BORRADO porque no podia dispararse nunca: ver `ClientPorted`. Dejarlo
        // habria sido peor que no tenerlo -- una comprobacion que no corre
        // parece cubrir un caso que en realidad esta descubierto.

        // NO HAY `ForgetPlayer` AQUI, Y ES A PROPOSITO.
        //
        // Los otros cuatro espacios de nombres de este modulo tienen uno y
        // `OnPlayerLogout` los llama a todos. Este NO se apunta ahi, porque **el
        // logout que dispara ese gancho a mitad de un cambio es NUESTRO**: lo
        // hace `Update` como segunda fase de la operacion. Un `ForgetPlayer`
        // enganchado ahi borraria el estado justo entre soltar un personaje y
        // cargar el otro -- y ademas lo haria desde dentro del bucle que recorre
        // ese mismo mapa, que es corrupcion de memoria, no un fallo logico.
        //
        // La desconexion de verdad ya esta cubierta: `Update` comprueba en cada
        // vuelta que la sesion siga existiendo y se olvida si no.
    }
}

#endif  // MOD_RTS_SWAP_H
