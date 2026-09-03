#ifndef MOD_RTS_NPC_H
#define MOD_RTS_NPC_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Hablar con el entrenador y con el vendedor SIENDO EL BOT.
    //
    // === ESTO NO ERA EL CAMINO CARO, Y CASI SE DESCARTA POR NO MIRAR ========
    //
    // El plan original daba esto por imposible sin reescribir el cliente, con el
    // argumento de que "esas ventanas las abre el cliente cuando el servidor le
    // habla a TU personaje". La primera mitad es cierta. La conclusion no, y se
    // cae abriendo `Trainer.h`:
    //
    //     trainer->GetSpells()                  // la lista entera
    //     trainer->CanTeachSpell(bot, &spell)   // ¿puede aprenderlo YA? PARA EL BOT
    //     trainer->TeachSpell(npc, bot, id)     // le cobra y se lo ensena
    //     trainer->IsTrainerValidForPlayer(bot)
    //
    // Las cuatro son publicas y toman un `Player*` cualquiera. Lo unico que hace
    // `WorldSession::SendTrainerList` por encima de eso es EMPAQUETARLO hacia su
    // propia sesion -- y esa parte no hace falta, porque la lista la dibujamos
    // nosotros en nuestra ventana.
    //
    // === `GetSpellState` ES PRIVADA, Y ESO COSTO UNA COMPILACION ===========
    //
    // La primera version de este fichero la llamaba, porque la exploracion
    // previa la habia listado como publica y **no se comprobo abriendo
    // `Trainer.h`**. Esta debajo del `private:`. Es exactamente el error que
    // este proyecto lleva cinco etapas documentando -- creer una lectura
    // convincente en vez de mirar -- cometido esta vez sobre el informe de una
    // busqueda en vez de sobre internet.
    //
    // No hace falta: los tres estados salen de lo que si es publico, y salen
    // MEJOR para lo que queremos.
    //
    //     HasSpell(id)              -> lo sabe
    //     CanTeachSpell(bot, &s)    -> puede aprenderlo ahora mismo
    //     ninguna de las dos        -> todavia no
    //
    // `CanTeachSpell` es `GetSpellState(...) == Available` mas la comprobacion
    // de hueco de profesion primaria (`Trainer.cpp:133-148`), asi que es
    // ligeramente MAS estricta que el estado a secas -- y esa diferencia es la
    // que queremos: la pregunta del boton es "¿puede aprenderlo?", no "¿esta
    // teoricamente disponible?".
    //
    // O sea que no hay que falsificar ni un paquete, ni tocar
    // `ServerScript::CanPacketReceive`, ni acercarse a lo que provoco el
    // ERROR #134 de la etapa 6. Es la misma forma que las bolsas y las
    // misiones: el servidor calcula, el addon dibuja.
    //
    // La leccion es la de la etapa 5n otra vez: **el plan razono por analogia en
    // vez de abrir el fichero.** Lo unico que sigue sin poderse es que se abra
    // LA VENTANA DE BLIZZARD con datos del bot, y eso deja de importar en cuanto
    // dibujas la tuya.
    //
    // === LA DISTANCIA AQUI SI SE RESPETA, Y ES DELIBERADO ===================
    //
    // Al reves que en las misiones. `Player::BuyItemFromVendorSlot` hace
    // `GetNPCIfCanInteractWith` por dentro (`Player.cpp:10925`), asi que comprar
    // exige tener el vendedor delante -- y se deja asi. En las misiones la via
    // libre compraba algo concreto que se pidio ("aceptar para todo el grupo sin
    // ir uno por uno"); aqui no compraria nada, porque el bot camina hasta el
    // NPC de todas formas. Saltarse una regla del juego sin ganar nada es solo
    // saltarse una regla del juego.
    namespace npc
    {
        enum SpellState
        {
            SP_AVAILABLE   = 0,
            SP_UNAVAILABLE = 1,
            SP_KNOWN       = 2,
        };

        struct TrainSpell
        {
            uint32 spellId = 0;
            uint32 cost = 0;       // ya con el descuento de reputacion aplicado
            uint32 state = SP_UNAVAILABLE;
            uint32 reqLevel = 0;
        };

        struct VendorEntry
        {
            uint32 slot = 0;       // el indice que quiere `BuyItemFromVendorSlot`
            uint32 itemId = 0;
            uint32 price = 0;      // con descuento
            int32  left = -1;      // -1 = sin limite
            uint32 extendedCost = 0;
        };

        // La lista del entrenador, calculada PARA EL BOT.
        bool TrainerList(Player* master, std::string const& botName, ObjectGuid npcGuid,
                     std::vector<TrainSpell>& out, uint32& copper, std::string* why = nullptr);

        // `spellId` 0 = todo lo que pueda pagar, en orden de coste creciente.
        //
        // EN ORDEN DE COSTE Y NO EN EL DEL ENTRENADOR, y esto es una decision:
        // "que aprenda todo lo que pueda" con veinte monedas de oro justas
        // deberia dar los hechizos baratos primero, no gastarlo todo en el
        // primero caro que aparezca en la tabla. El orden de la tabla no
        // significa nada.
        bool Train(Player* master, std::string const& botName, ObjectGuid npcGuid,
                   uint32 spellId, int& learned, uint32& spent, std::string* why = nullptr);

        bool Vendor(Player* master, std::string const& botName, ObjectGuid npcGuid,
                    std::vector<VendorEntry>& out, uint32& copper, std::string* why = nullptr);

        bool Buy(Player* master, std::string const& botName, ObjectGuid npcGuid,
                 uint32 slot, uint32 count, std::string* why = nullptr);

        // Vender la basura gris. Devuelve cuantos objetos y cuanto se saco.
        bool SellJunk(Player* master, std::string const& botName, ObjectGuid npcGuid,
                      int& sold, uint32& earned, std::string* why = nullptr);

        bool Repair(Player* master, std::string const& botName, ObjectGuid npcGuid,
                    uint32& cost, std::string* why = nullptr);
    }
}

#endif  // MOD_RTS_NPC_H
