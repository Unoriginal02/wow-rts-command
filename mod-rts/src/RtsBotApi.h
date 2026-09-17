#ifndef MOD_RTS_BOT_API_H
#define MOD_RTS_BOT_API_H

#include "ObjectGuid.h"

#include <list>
#include <set>
#include <string>

class Player;
class Unit;

namespace rts
{
    // LA UNICA PUERTA A mod-playerbots.
    //
    // === POR QUE EXISTE ESTE FICHERO =========================================
    //
    // mod-playerbots se actualiza, y cuando se actualiza cambia nombres. Antes
    // de esto habia unas ochenta llamadas suyas repartidas entre `RtsOrders.cpp`
    // y `RtsCommandMode.cpp`, mezcladas con logica nuestra: un cambio suyo daba
    // errores de compilacion en dos ficheros de mil lineas y habia que entender
    // cada sitio para saber que hacia.
    //
    // Ahora `RtsBotApi.cpp` es la UNICA unidad de traduccion que incluye una
    // cabecera de playerbots, y esta cabecera no expone ni un tipo suyo -- solo
    // `Player*`, `Unit*`, `ObjectGuid` y tipos de la biblioteca estandar. Asi
    // que una actualizacion que rompa algo:
    //
    //   * rompe UN fichero, no dos;
    //   * rompe en un sitio donde cada funcion hace UNA cosa y su nombre dice
    //     cual, en vez de en medio de la logica de una orden;
    //   * y no puede romper nada por transitividad, porque nadie mas ve sus
    //     tipos.
    //
    // La comprobacion de que sigue siendo cierto es una linea, y merece la pena
    // correrla despues de tocar el modulo:
    //
    //     grep -rln '#include "\(Playerbot\|AiObjectContext\|LootStrategy\|PositionValue\|LastMovement\)' mod-rts/src/
    //     # tiene que imprimir exactamente: mod-rts/src/RtsBotApi.cpp
    //
    // Se mira el `#include` y NO el nombre de la clase a proposito: media docena
    // de comentarios de este modulo citan `PlayerbotAI.cpp:3066` y compania para
    // explicar por que algo esta escrito como esta, y esos comentarios son de lo
    // mas valioso que hay aqui. Una comprobacion que los contara como
    // dependencias daria un falso positivo permanente, y a una comprobacion que
    // siempre falla se le deja de hacer caso -- que es peor que no tenerla.
    //
    // === LO QUE NO ES ========================================================
    //
    // No es una capa de abstraccion que intente esconder que usamos playerbots.
    // Al reves: hace VISIBLE cuanto dependemos de ellos, que antes no se veia.
    // Cada funcion de aqui es una dependencia declarada, y la lista entera cabe
    // en una pantalla.
    //
    // Tampoco es generica. No hay `ChangeStrategy(cualquier cosa)` como API
    // publica porque no hace falta: los sitios que la llaman son contados y
    // conocidos. Una API generica seria mas comoda de escribir hoy y no diria
    // nada sobre que dependemos de ellos, que es justo lo que este fichero
    // existe para decir.
    namespace bots
    {
        // Los dos estados de estrategia de un bot. `BOTH` es una comodidad para
        // los sitios que aplican lo mismo en los dos, que son la mayoria -- pero
        // NO todos, y esa asimetria ya ha costado un fallo real: `passive`
        // puesto solo en combate deja un bot que no reacciona a nada fuera de
        // el, y la fila de roles lo lee apagado. Ver `SetRole` en
        // `RtsCommandMode.cpp`.
        enum Where
        {
            IDLE   = 0,   // BOT_STATE_NON_COMBAT
            COMBAT = 1,   // BOT_STATE_COMBAT
            BOTH   = 2,
        };

        // --- resolucion ------------------------------------------------------

        // El bot tiene que ser alguien a quien este jugador manda de verdad. Sin
        // esto, cualquiera podria anclar los bots de otro sabiendo su nombre.
        //
        // ESTO NO USA PLAYERBOTS -- es `ObjectAccessor::FindPlayerByName` mas
        // `Group::IsMember`, nucleo puro. Vive aqui porque todo lo que necesita
        // un bot necesita esto primero, y porque antes estaba DUPLICADO palabra
        // por palabra en `RtsOrders.cpp` y `RtsCommandMode.cpp`.
        Player* Resolve(Player* master, std::string const& name);

        // Si este `Player` lo lleva playerbots. Un bot de playerbots es un
        // `Player` normal para el nucleo, asi que esto es lo unico que los
        // distingue.
        bool Driven(Player* bot);

        // QUIEN LO ANADIO. Nulo si no lo lleva playerbots, y nulo TAMBIEN si es
        // un bot aleatorio: esos los mete el servidor solo y no tienen maestro.
        //
        // Esa segunda mitad no es un efecto secundario, es media funcion. Es lo
        // unico que separa *"un alt tuyo que acabas de meter con `.playerbots
        // bot add`"* de *"uno de los quinientos que el servidor pasea por el
        // mundo"*, y las dos cosas no piden el mismo trato: lo que sea caro o
        // deje historial escrito en el personaje se le hace al primero y no a
        // los otros quinientos.
        Player* MasterOf(Player* bot);

        // --- estrategias -----------------------------------------------------

        // "+stay,-passive,-move from group" y compania. Devuelve false si el bot
        // no lo lleva playerbots, para que quien llama pueda decirlo en vez de
        // dar la orden por buena.
        bool Change(Player* bot, std::string const& changes, Where where);

        // Con `BOTH`, cierto si la lleva en CUALQUIERA de los dos estados.
        bool Has(Player* bot, std::string const& name, Where where);

        // Las que la clase de este bot tiene registradas. Se pregunta en vez de
        // escribir una tabla de clase a roles: una tabla escrita a mano falla
        // dejando un boton que no hace nada, sin error.
        std::set<std::string> Supported(Player* bot);

        // Persistir las estrategias del bot, para que sobrevivan a su relogueo.
        void Save(Player* bot);

        // DEVOLVER AL BOT A SUS ESTRATEGIAS DE FABRICA.
        //
        // Es la salida de emergencia que `PRUEBAS-20` 0.2 pidio: *"una
        // integrante del grupo debe tener un rol distinto y ya no va a atacar
        // (...) necesitamos algo para volverlos al estado basico"*.
        //
        // Y hace falta precisamente porque las estrategias son PEGAJOSAS a
        // proposito -- se guardan con el bot y sobreviven al relogueo -- asi que
        // un `passive` puesto hace tres sesiones sigue puesto y no hay nada en
        // pantalla que lo diga. Sin un boton de "olvida todo", la unica salida
        // era adivinar cual de las diez estrategias estaba de mas.
        bool Reset(Player* bot);

        // --- meter y sacar del mundo -----------------------------------------

        // Poner a un personaje en el mundo como bot de `master`, y quitarlo.
        //
        // Es lo que hace `.playerbots bot add|remove`, y es la mitad de
        // playerbots que hace posible el cambio de personaje: al cambiarte a un
        // alt hay que SACARLO de bot primero, y al que dejas hay que METERLO
        // despues. Sin esto, el personaje de destino estaria en el mundo dos
        // veces y el login fallaria con un "duplicate character" que no explica
        // nada.
        bool Add(Player* master, ObjectGuid guid);
        bool Remove(Player* master, ObjectGuid guid);

        // TU PROPIO PERSONAJE, CON IA O SIN ELLA. Es lo que hace
        // `.playerbots bot self` (`PlayerbotMgr.cpp:1059`), hecho desde aqui
        // para poder atarlo al modo RTS: con IA tu heroe pelea solo -- rota,
        // responde cuando atacan al grupo -- y tiene rol como los demas;
        // sin ella lo mueves tu y el rol vuelve a ser la postura.
        //
        // LA POLITICA ES DEL SERVIDOR, NO NUESTRA: `AiPlayerbot.SelfBotLevel`
        // decide si esta permitido (0 no, 1 solo GM, 2 cualquiera), y aqui se
        // respeta la misma puerta que el comando. `why` recoge el motivo para
        // poder decirlo en vez de no hacer nada.
        bool SelfDrive(Player* master, bool on, std::string* why = nullptr);

        // --- posicion --------------------------------------------------------

        // HASTA DONDE LLEGA EL BRAZO DE SU IA, en yardas.
        //
        // Es `AiPlayerbot.ReactDistance` (150 de fabrica), y no es un dato
        // decorativo: `MoveToPositionAction::isUseful()` es literalmente
        //
        //     pos.isSet() && distance > followDistance && distance < reactDistance
        //
        // asi que un ancla mas lejos que esto NO ES UTIL para su IA y el bot no
        // arranca siquiera -- se queda quieto con la orden puesta. De ahi sale
        // el presupuesto de cada tramo en `orders::NextLeg`, que es quien parte
        // un viaje largo en trozos que si estan dentro del brazo.
        //
        // Se lee en vez de escribirse a mano porque es CONFIGURABLE: un numero
        // copiado aqui quedaria desmentido por el `.conf` sin que nada avise.
        float ReactDistance();

        // Los anclajes con nombre de playerbots ("stay", "return"). Poner el
        // anclaje es lo que hace que el bot camine ahi y se quede, en vez de
        // empujarle nosotros cada tick.
        bool SetAnchor(Player* bot, char const* key, float x, float y, float z, uint32 mapId);
        bool ClearAnchor(Player* bot, char const* key);

        // Olvidar el ultimo movimiento. HACE DOS COSAS y las dos importan: corta
        // el paso que el bot tuviera en marcha, y evita que su IA lo reanude en
        // el tick siguiente pisando la orden que se le acaba de dar. Tambien es
        // lo que impide que un lanzamiento se cancele solo -- playerbots se
        // rinde si el bot anda y el hechizo tiene tiempo de lanzamiento.
        bool ForgetLastMove(Player* bot);

        // --- acciones --------------------------------------------------------

        // Disparar una accion concreta de la IA, saltandose sus estrategias.
        //
        // OJO CON LO QUE ESTO NO HACE, que costo una ronda de pruebas: los
        // multiplicadores (y por tanto `passive`) solo se aplican en
        // `DoNextAction`, sobre lo que sale de la cola. `ExecuteAction` -- por
        // donde entra esto -- no los mira. Asi que la accion SALE aunque el bot
        // este pasivo, y lo que la continuaria muere en el tick siguiente: la
        // orden reporta exito y en pantalla no pasa nada. Quien llame a esto
        // sobre un bot pasivo tiene que decirlo.
        bool DoAction(Player* bot, char const* action);

        // Lanzar por el bot, a traves de su propia IA -- asi respeta alcance,
        // enfriamiento y GCD, y falla como fallaria el bot solo.
        bool Cast(Player* bot, uint32 spellId, Unit* target);

        // CALLAR SU IA UNOS MILISEGUNDOS. Es `SetNextCheckDelay`, lo mismo que
        // playerbots se hace a si mismo tras un GCD (`PlayerbotAI.cpp:1476`).
        //
        // HACE FALTA PARA QUE UN LANZAMIENTO LARGO LLEGUE A TERMINAR, y es el
        // arreglo de `PRUEBAS-23` C6 ("empieza la animacion y cancela al medio
        // segundo"). `StopMoving` corta el paso que el bot lleva en ese
        // instante; lo que no puede es impedir que su IA le mande otro en el
        // tick siguiente -- y `passive`, que es lo que `Suppress` acaba de
        // ponerle, lleva "follow" en su lista de partes permitidas A PROPOSITO
        // (`PassiveMultiplier.cpp`). Asi que un bot recolocandose se movia
        // DURANTE el casteo y lo interrumpia, exactamente medio segundo
        // despues, que es lo que tarda su siguiente vuelta.
        //
        // Parar el movimiento era necesario y no suficiente, y esa distincion es
        // la que costo la ronda: el arreglo de la etapa 5o se dio por bueno
        // porque el sintoma se movio, no porque desapareciera.
        bool HoldAi(Player* bot, uint32 ms);

        // --- valores del contexto -------------------------------------------

        // La estrategia de botin: `all` recoge todo (grises incluidos), la de
        // fabrica es `normal`, que pasa por ItemUsage y deja los grises.
        //
        // NO ES LO MISMO QUE EL METODO DE BOTIN DEL GRUPO (quien tiene derecho a
        // lootear), y las dos mitades se estorbaban: ver la nota junto a
        // AiPlayerbot.FreeMethodLoot en playerbots.conf.
        bool SetLootAll(Player* bot, bool everything);

        // La lista que lee la estrategia "focus heal targets". Se pasa entera,
        // no se anade: "cuida del tanque" significa el tanque, no el tanque
        // ademas de a quien elegiste hace diez minutos. Lista vacia la limpia.
        bool SetFocusHeal(Player* bot, std::list<ObjectGuid> const& targets);
    }
}

#endif  // MOD_RTS_BOT_API_H
