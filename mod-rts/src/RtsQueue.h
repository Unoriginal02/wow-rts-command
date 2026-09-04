#ifndef MOD_RTS_QUEUE_H
#define MOD_RTS_QUEUE_H

#include "ObjectGuid.h"

#include <functional>
#include <string>

class Player;

// LA COLA DE HECHIZOS.
//
// El brief de la barra de control pide que pulsar un hechizo mientras el
// personaje esta ocupado lo deje ESPERANDO en vez de fallar: *"queda en cola
// hasta que el personaje tenga un tick/hueco disponible; se lanza en cuanto
// termine el casteo actual"*.
//
// Eso no se puede hacer desde el cliente. Quien sabe si el hueco esta libre --
// enfriamiento global, casteo en curso, el bot sentado, el bot andando -- es el
// servidor, y ademas la respuesta cambia varias veces por segundo. Un
// reintento desde el addon serian veinte mensajes de chat por hechizo.
//
// EL CASO QUE MAS LO JUSTIFICA NO ES EL CASTEO: es que
// `PlayerbotAI::CastSpell` empieza con `if (!bot->IsStandState())`, levanta al
// bot y **devuelve false**. O sea que el PRIMER click sobre un bot que esta
// comiendo SIEMPRE falla. Sin cola, "los botones no funcionan cuando estan
// descansando" -- y funcionando a la segunda, que es peor de diagnosticar.
//
// El inventario completo de que fallos son transitorios y cuales definitivos
// esta en `docs/HECHIZOS-COLA.md` §10.
namespace rts
{
    namespace queue
    {
        // POR DONDE CONTESTA. El transporte lo tiene `mod_rts.cpp` y solo el, que
        // es la separacion que este modulo si tiene bien hecha (revision de
        // arquitectura §11). La cola habla en su propio tick, asi que no puede
        // esperar a que alguien le pregunte: se le instala el sumidero al cargar.
        using Sink = std::function<void(Player*, std::string const&)>;
        void SetSink(Sink sink);

        // Encolar un lanzamiento. Sustituye lo que ese bot tuviera pendiente:
        // una cola de UNO por personaje, a proposito -- sin eso, cuatro clicks
        // nerviosos son cuatro hechizos saliendo seguidos diez segundos
        // despues, que no es lo que nadie pidio al hacer el cuarto click.
        //
        // Intenta lanzar YA. Lo normal es que salga a la primera y la cola no
        // llegue a existir.
        void Push(Player* master, std::string const& botName, uint32 spellId,
                  ObjectGuid target);

        // Todo lo pendiente de ese maestro, fuera. Lo llama el logout.
        void Drop(Player* master);

        void Update(uint32 diff);
    }
}

#endif
