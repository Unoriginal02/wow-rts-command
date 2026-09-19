#ifndef MOD_RTS_FIGHT_H
#define MOD_RTS_FIGHT_H

#include <cstdint>

namespace rts
{
    // LO QUE PASA MIENTRAS SE PELEA, Y LO QUE PASA AL MORIR.
    //
    // Dos reglas, las dos pedidas en juego y las dos vigiladas desde el mismo
    // tick:
    //
    //   1. NADIE RECOGE BOTIN CON LA PELEA EN MARCHA, ni hasta unos segundos
    //      despues de que termine.
    //   2. QUIEN MUERE DENTRO DE UNA INSTANCIA REVIVE EN LA PUERTA, fuera, sin
    //      carrera de cadaver: *"al morir en una instance quiero que los bots y
    //      heroe resuciten a la puerta del portal de la instance (fuera)
    //      directamente"*.
    //
    // === LA PUERTA NO SE ADIVINA, SE PREGUNTA ==============================
    //
    // El sitio exacto lo sabe el nucleo: `ObjectMgr::GetGoBackTrigger(mapa)` es
    // la salida de esa instancia -- mapa, x, y, z -- y es la misma que usa el
    // propio nucleo cuando tiene que sacar a alguien de un mapa que ya no
    // existe. Sin ella habria que mantener una tabla de coordenadas por
    // mazmorra, escrita a mano, que se queda vieja sin avisar.
    //
    // Y SE ESPERA UN POCO. Revivir dentro del mismo instante en que el nucleo
    // esta matando al personaje es meterse en medio de su propio trabajo, asi
    // que el tick lo ve muerto, lo apunta, y lo revive un par de segundos
    // despues -- que ademas es tiempo de sobra para que se vea morir.
    //
    // === EL BOTIN: POR QUE PASABA ==========================================
    //
    // Recoger es cosa de `LootNonCombatStrategy`, que vive en el motor de FUERA
    // de combate, y playerbots cambia de motor segun `bot->IsInCombat()` -- lo
    // que mira es SU combate, no el de nadie mas. Asi que en cuanto un bot deja
    // de estar en combate el solo -- el sanador al que nadie pega, el mago cuyo
    // bicho acaba de caer -- se va a por el saco a mitad de pelea, andando
    // delante de todo el mundo, y deja de hacer lo suyo.
    //
    // Visto en juego, y en esas palabras: *"los bots se han puesto a intentar
    // lootear en medio del combate, y a menudo olvidaban de seguir atacando"*.
    //
    // === COMO SE ARREGLA ===================================================
    //
    // El combate se mira POR GRUPO y no por bot: si alguno de los tuyos esta
    // peleando, la pelea es de todos. Mientras dure -- y unos segundos despues,
    // porque un bicho cae y el siguiente llega -- se les quita la estrategia
    // `loot` y se les devuelve al acabar.
    //
    // SE QUITA Y SE DEVUELVE, no se fuerza. Si el jugador no la tenia puesta,
    // no se le pone al salir del combate: solo vuelve lo que estaba. Es la
    // misma regla de capturar y devolver que siguen las teclas, los frames de
    // Blizzard y la fila de roles.
    namespace fight
    {
        // Del tick del mundo.
        void Update(uint32_t diff);
    }
}

#endif  // MOD_RTS_FIGHT_H
