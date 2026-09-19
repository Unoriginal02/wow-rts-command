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
        // desertor y cualquier resto de una cola anterior. Es literalmente
        // "como si no hubieran estado en cola".
        //
        // OJO: si el grupo esta encolado AHORA, esto lo saca de la cola. Es lo
        // que se pide -- dejarlo como si nada -- y hay que volver a encolar.
        int Clear(Player* master, int& deserters, int& queues);
    }
}

#endif  // MOD_RTS_LFG_H
