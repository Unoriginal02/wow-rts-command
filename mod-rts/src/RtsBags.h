#ifndef MOD_RTS_BAGS_H
#define MOD_RTS_BAGS_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Las bolsas de todo el grupo, y mover un objeto de uno a otro sin ventana
    // de intercambio.
    //
    // === ESTO NO TOCA mod-playerbots ========================================
    //
    // Ni una llamada. Un bot de playerbots es un `Player` normal para el
    // nucleo, asi que darle un objeto es exactamente el mismo codigo que
    // darselo a un jugador de verdad -- y ese codigo lleva anos sin cambiar de
    // nombre, que es justo lo que se pidio: que actualizar no duela.
    //
    // Lo unico que se le pide a `RtsBotApi` es `Resolve`, que tampoco usa
    // playerbots (es `FindPlayerByName` mas `Group::IsMember`): la comprobacion
    // de que ese personaje esta en TU grupo, sin la cual cualquiera podria
    // vaciar las bolsas de otro sabiendo su nombre.
    //
    // === LA SECUENCIA DE MOVER ES LA DEL PROPIO NUCLEO =======================
    //
    // `CanStoreItem` -> `MoveItemFromInventory` -> `MoveItemToInventory`, que es
    // literalmente lo que hace `TradeHandler.cpp:134,150` al cerrar un
    // intercambio. Se copia de ahi y no de `GiveItemAction` de playerbots, que
    // hace lo mismo con UNA diferencia importante: pasa
    // `in_characterInventoryDB = false`, o sea `ITEM_NEW`, o sea "crea la fila
    // en character_inventory". Aqui la fila YA existe -- `RemoveItem` dice de si
    // mismo, en el nucleo, *"does not actually change the item, it only takes
    // the item out of storage temporarily"* -- asi que lo correcto es `true` /
    // `ITEM_CHANGED`, que es lo que hace el intercambio de verdad. Es la ruta
    // que ha ejercitado cada trade que se ha hecho nunca en un servidor.
    namespace bags
    {
        // Una linea del volcado. `bag` 255 es la mochila; los demas son la
        // posicion de la bolsa equipada, tal cual la entiende `GetItemByPos`,
        // asi que el cliente puede devolvernos el par y no hay que traducir.
        struct Entry
        {
            uint8      bag = 0;
            uint8      slot = 0;
            ObjectGuid guid;
            uint32     itemId = 0;
            uint32     count = 0;
            uint32     quality = 0;
            uint32     flags = 0;
        };

        // Un contenedor y su tamano. El cliente dibuja huecos vacios tambien --
        // una bolsa medio vacia tiene que verse medio vacia, o no se sabe si
        // cabe lo que quieres mover.
        struct Container
        {
            uint8  bag = 0;
            uint8  size = 0;
        };

        enum Flag
        {
            // Vinculado a ese personaje: no se puede mover, y el cliente lo
            // pinta apagado en vez de dejar intentarlo y fallar.
            FLAG_BOUND     = 1,
            // Es una bolsa. Solo se puede mover si esta vacia.
            FLAG_CONTAINER = 2,
        };

        // Volcado de las bolsas de `name`, que puede ser el propio jugador o un
        // bot de su grupo. Devuelve false si no es ninguna de las dos cosas.
        bool Dump(Player* master, std::string const& name,
                  std::vector<Container>& bagsOut,
                  std::vector<Entry>& itemsOut,
                  uint32& copper, uint32& freeSlots);

        // Mover un objeto entero de `from` a `to`. Los dos tienen que ser el
        // jugador o alguien de su grupo.
        //
        // PILAS ENTERAS Y NADA MAS, a proposito. Partir una pila es
        // `Player::SplitItem`, que es otra maquina entera (crear el objeto
        // nuevo, repartir la cuenta, deshacerlo si el destino no admite la
        // mitad), y de las dos formas de equivocarse aqui una duplica objetos.
        // La version que hace falta hoy es "pasale esto", que es una pila.
        //
        // `why` recibe el motivo en castellano cuando falla. Un objeto que no se
        // mueve y no dice por que es indistinguible de un click que no llego,
        // que es la confusion que este proyecto lleva pagando desde la etapa 5o.
        bool Move(Player* master, std::string const& from, std::string const& to,
                  ObjectGuid itemGuid, std::string* why = nullptr);
    }
}

#endif  // MOD_RTS_BAGS_H
