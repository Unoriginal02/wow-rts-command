#ifndef MOD_RTS_LFG_H
#define MOD_RTS_LFG_H

#include <cstdint>

class Player;
class WorldPacket;
class WorldSession;

namespace rts
{
    // LA COMPROBACION DE FUNCIONES DEL BUSCADOR DE MAZMORRAS, contestada por
    // nosotros en nombre de los bots.
    //
    // === QUE PASABA =========================================================
    //
    // Pedir mazmorra con el grupo no llegaba a ninguna parte: cada bot elegia
    // TANQUE -- el mago tambien -- y el chat se llenaba de "X ha elegido:
    // Tanque" y "se ha iniciado una comprobacion de funcion" en bucle.
    //
    // Son dos cosas, y la segunda explica el bucle entero. playerbots contesta
    // desde un manejador colgado del PAQUETE `SMSG_LFG_ROLE_CHECK_UPDATE`
    // (`lfg role check`, visto en `Playerbots.log`), y ese paquete lo manda el
    // nucleo A TODO EL GRUPO cada vez que ALGUIEN contesta. O sea: un bot
    // contesta -> el nucleo avisa a los cinco -> los cinco vuelven a contestar
    // -> el nucleo avisa otra vez. La unica salida es que la comprobacion
    // TERMINE, y no podia terminar porque cuatro tanques no son un grupo valido
    // (`LFGMgr::CheckGroupRoles`).
    //
    // La eleccion tampoco es cosa nuestra: `LfgJoinAction::GetRoles` pregunta
    // `IsTank`, que es `ContainsStrategy(STRATEGY_TYPE_TANK)` sobre los DOS
    // motores del bot. Basta una estrategia marcada como de tanque en cualquier
    // sitio para que un mago se ofrezca a aguantar la mazmorra.
    //
    // === QUE HACE ESTO ======================================================
    //
    // Contesta por ellos, con el rol que TU les tienes puesto en la fila de
    // roles -- que es el que estan jugando de verdad -- y lo hace para todos en
    // la misma vuelta, asi que la comprobacion se cierra de una vez y el bucle
    // no llega a empezar.
    //
    // Y PARA NO PELEARSE CON PLAYERBOTS, LES CALLA LA IA UN PAR DE SEGUNDOS
    // (`bots::HoldAi`) antes de contestar. Sus manejadores de paquete corren en
    // su vuelta de pensamiento, asi que con la IA en pausa no contestan; cuando
    // despiertan, la comprobacion ya no existe y su respuesta se pierde en el
    // suelo -- `LFGMgr::UpdateRoleCheck` se vuelve sin hacer nada si el grupo
    // ya no tiene una en marcha. No se les quita ninguna estrategia ni se toca
    // su codigo: se les gana por la mano.
    // SE LLAMA `dungeon` Y NO `lfg` POR UNA RAZON TONTA Y REAL: el nucleo tiene
    // su propio `namespace lfg`, y `sLFGMgr` se expande a `lfg::LFGMgr::...`.
    // Dentro de un `rts::lfg` esa expansion buscaria `LFGMgr` DENTRO del
    // nuestro, no lo encontraria, y el error de compilacion no se pareceria en
    // nada a la causa.
    namespace dungeon
    {
        // Del tick del mundo.
        void Update(uint32_t diff);

        // EL AVISO DE QUE HAY MAZMORRA, camino de uno de nuestros bots.
        //
        // VIENE DEL GANCHO `OnPlayerbotPacketSent` Y NO DE `CanPacketSend`, y
        // esa es toda la diferencia entre funcionar y no: un bot no tiene
        // socket, y `WorldSession::SendPacket` se vuelve en `if (!m_Socket)
        // return;` ANTES de llegar al gancho de envio. O sea que por ahi los
        // paquetes de los bots no pasan nunca. El de playerbots se dispara una
        // linea antes, justo para esto.
        //
        // Se mira aqui y no se contesta aqui: cuando este paquete sale, el
        // nucleo esta DENTRO de su propia lista de propuestas, y llamar a
        // `UpdateProposal` desde el gancho seria tocarla mientras la recorre.
        // Se apunta el numero de propuesta y lo contesta el tick.
        //
        // Por que hace falta contestar nosotros: playerbots acepta desde su
        // propio manejador, pero **manda un NO si el bot esta en combate o
        // muerto** (`LfgAcceptAction`), y un bot que dice que no deja al grupo
        // entero fuera de la mazmorra. Aqui se acepta y punto: si has pedido
        // mazmorra, la respuesta ya la has dado tu.
        void NoteProposal(Player* bot, WorldPacket const* packet);

        // QUITARLES LO QUE LES IMPIDE ENTRAR, a todo tu grupo: el castigo de
        // desertor, cualquier resto de una cola anterior y -- si hace falta --
        // el propio grupo. Es literalmente "como si no hubieran estado en
        // cola".
        //
        // === POR QUE PUEDE DISOLVER EL GRUPO ==============================
        //
        // Un grupo formado por el buscador queda marcado como GRUPO DE BUSCADOR
        // (`GROUPTYPE_LFG`, el 8 de `groups.groupType`) y el nucleo **no tiene
        // forma de quitarle esa marca**: hay `ConvertToLFG` y no existe el
        // inverso. Mientras la lleva, `MapMgr::PlayerCannotEnter` le prohibe
        // entrar en cualquier mapa que no sea la mazmorra que el buscador le
        // asigno -- y en cuanto esa asignacion caduca, eso es TODAS.
        //
        // El sintoma es una puerta que no deja pasar y una linea que no
        // explica nada: *"No se puede introducir el mapa en este momento"*. Y
        // no se arregla saliendo y volviendo a entrar al juego, porque la marca
        // esta guardada.
        //
        // Lo unico que la quita es deshacer el grupo. Asi que si el grupo lleva
        // la marca, este mando lo deshace y lo dice: con los bots, volver a
        // formarlo es un boton (`Traer bots`).
        //
        // OJO: si el grupo esta encolado AHORA, esto lo saca de la cola. Es lo
        // que se pide -- dejarlo como si nada -- y hay que volver a encolar.
        int Clear(Player* master, int& deserters, int& queues, bool& disbanded);

        // TODO LO QUE PUEDE CERRARTE UNA PUERTA, QUITADO DE UNA VEZ.
        //
        // `Clear` limpia lo de la COLA. Esto ademas borra lo de HABER ESTADO
        // DENTRO, que es lo otro que deja a un grupo fuera sin explicar nada:
        //
        //   * las ATADURAS a instancias (`character_instance`): "ya has estado
        //     hoy aqui, esta es tu copia guardada". Se quitan todas, a todo el
        //     grupo, menos la del mapa en el que estes ahora mismo -- esa no se
        //     puede soltar sin sacarte primero, y es justo la que no estorba.
        //   * el castigo de DESERTOR.
        //   * el estado de cola y la marca de grupo de buscador (via `Clear`).
        //   * y los ENFRIAMIENTOS de mazmorra del buscador, que son globales.
        //
        // Es el mando del boton de la fila de arriba: un solo gesto que deja al
        // grupo como recien llegado al servidor, en lo que a mazmorras se
        // refiere.
        int FreeEntry(Player* master, int& unbound, int& deserters, bool& disbanded);
    }
}

#endif  // MOD_RTS_LFG_H
