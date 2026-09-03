#ifndef MOD_RTS_CHAIN_H
#define MOD_RTS_CHAIN_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Ataque encadenado: marcas enemigos 1, 2, 3, 4 y el grupo va a por ellos en
    // ese orden, pasando al siguiente cuando cae el anterior.
    //
    // === NO HAY INDICE, Y ESA ES TODA LA IDEA ===============================
    //
    // El objetivo actual **no se guarda**: es, por definicion, *el primero de la
    // lista que sigue vivo*. Se recalcula en cada tick.
    //
    // La version obvia -- un indice que avanza cuando muere el de turno -- tiene
    // tres formas de romperse que esta no tiene: el cliente vuelve a mandar la
    // lista cada vez que anades un enemigo (y entonces el indice significa otra
    // cosa), un enemigo puede desaparecer sin morir (huye, lo mata otro, sale de
    // la vista), y un bot puede matar al tercero antes que al segundo. Con "el
    // primero vivo" los tres casos se arreglan solos porque no hay nada que
    // mantener sincronizado.
    //
    // Lo unico que si se recuerda es a quien se le ORDENO ya, para no repetir la
    // orden veinte veces por segundo -- que ademas de ruido reiniciaria el
    // movimiento del bot en cada tick.
    //
    // === LO UNICO DE ESTAS FEATURES QUE TOCA PLAYERBOTS =====================
    //
    // Y lo toca a traves de `rts::orders::AttackBot`, que ya existia y ya pasa
    // por `RtsBotApi`. Aqui no hay ni un `#include` suyo.
    namespace chain
    {
        // La lista entera, cada vez. Vacia = parar.
        //
        // Se manda completa y no incremental a proposito: "anadir el cuarto" y
        // "quitar el segundo" y "el segundo se murio" serian tres mensajes
        // distintos que pueden cruzarse, y el estado compartido acabaria
        // discrepando. Una lista completa no puede discrepar de si misma.
        bool Set(Player* master, std::vector<ObjectGuid> const& targets,
                 std::vector<std::string> const& names);

        void Stop(Player* master);

        // Del tick del mundo. Barato: solo mira si el objetivo de turno sigue
        // vivo, y solo cada `kTickMs`.
        void Update(uint32 diff);

        // Para el logout, igual que el resto del modulo.
        void ForgetPlayer(Player* master);

        // El objetivo de turno y cuantos quedan, para que el cliente pueda
        // ensenar cual va. Devuelve false si no hay cadena.
        bool Current(Player* master, ObjectGuid& guid, int& done, int& total);
    }
}

#endif  // MOD_RTS_CHAIN_H
