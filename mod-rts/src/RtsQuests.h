#ifndef MOD_RTS_QUESTS_H
#define MOD_RTS_QUESTS_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Todas las quests de un NPC, y quien del grupo puede cogerlas o
    // entregarlas. Aceptar y entregar para varios de una vez.
    //
    // === ESTO NO TOCA mod-playerbots ========================================
    //
    // Ni una llamada. Un bot es un `Player`, y las funciones de quest del nucleo
    // toman un `Player`. Lo unico que se pide a `RtsBotApi` es `Resolve`, que es
    // nucleo puro.
    //
    // === LA DISTANCIA: POR QUE ESTO ES LEGAL ================================
    //
    // Lo del video -- *"you don't have to actually be next to it"* -- sale
    // gratis, y no por un truco: **ninguna** de las funciones de dominio del
    // nucleo comprueba distancia. Verificado linea a linea en `PlayerQuest.cpp`:
    // `CanTakeQuest` (:252), `CanAddQuest` (:266), `AddQuest` (:520),
    // `CanRewardQuest` (:387/:471) y `RewardQuest` (:675) validan estado, nivel,
    // reputacion, hueco en la bolsa y en el registro -- y nada mas.
    //
    // La unica puerta de distancia es `Player::CanInteractWithQuestGiver`
    // (`Player.cpp:2095` -> `GetNPCIfCanInteractWith` -> `IsWithinDistInMap`), y
    // la llaman SOLO los manejadores de opcode (`QuestHandler.cpp:134, 270, 368,
    // 492`), comentada por el propio nucleo como *"some kind of WPE
    // protection"*. O sea: es una defensa contra un CLIENTE que miente sobre
    // donde esta, no una regla del juego. Nosotros no venimos de un cliente.
    //
    // Y no es una lectura nuestra: **mod-playerbots ya lo explota igual**.
    // `QuestAction::AcceptQuest` (`QuestAction.cpp:244-248`) cae a
    // `bot->AddQuest(quest, pObject)` directo cuando el bot esta lejos, y
    // `TalkToQuestGiverAction` (`:107-132`) llama `CanRewardQuest`/`RewardQuest`
    // sin pasar por el manejador nunca.
    namespace quests
    {
        // El estado de UNA quest para UN personaje. Numeros propios y no los del
        // nucleo: `QuestStatus` mezcla cosas que aqui se dibujan igual y separa
        // cosas que aqui se dibujan distinto, y el cliente necesita justo estas
        // cinco.
        enum Status
        {
            ST_NO      = 0,   // no le vale: nivel, raza, clase, cadena, registro lleno
            ST_CAN     = 1,   // puede cogerla ahora
            ST_DOING   = 2,   // la lleva, sin terminar
            ST_READY   = 3,   // la lleva y esta lista para entregar
            ST_DONE    = 4,   // ya la hizo
        };

        enum Flag
        {
            FLAG_CHOICE = 1,   // tiene recompensa a elegir
            FLAG_GIVES  = 2,   // este NPC la DA
            FLAG_TAKES  = 4,   // este NPC la RECIBE
        };

        struct Member
        {
            std::string name;
            uint8       status = ST_NO;
        };

        struct Offer
        {
            uint32      questId = 0;
            uint32      flags = 0;
            uint32      level = 0;
            std::string title;
            std::vector<Member> members;

            // Los objetos entre los que hay que elegir, si los hay. Van aqui y
            // no se piden aparte porque el cliente los necesita en el mismo
            // instante en que dibuja la fila: una mision marcada "elige
            // recompensa" con un boton de entregar que no ofrece nada que
            // elegir es peor que no marcarla.
            std::vector<uint32> choices;
        };

        // Todo lo que este NPC tiene que ofrecer al grupo. Vacio si el guid no
        // es una criatura visible.
        bool Look(Player* master, ObjectGuid npcGuid, std::vector<Offer>& out);

        // QUIEN DEL GRUPO LLEVA UNA MISION CONCRETA.
        //
        // Una sola mision y no las 25 del registro, porque el unico consumidor
        // es el tooltip del boton de compartir del registro NATIVO: se pregunta
        // por la que este seleccionada y por ninguna mas.
        //
        // `gives` va a `true` al puntuar: aqui no hay ningun PNJ delante, asi
        // que "puede cogerla" quiere decir *"el nucleo se la daria"* y no
        // *"este PNJ se la daria"*. Es justo la distincion que `PRUEBAS-20` B
        // obligo a hacer en `Look`, y aqui cae del otro lado por el mismo
        // motivo: quien la va a dar somos nosotros.
        //
        // El maestro NO sale en la lista: la pregunta es sobre sus companeros,
        // y su propia mision ya la esta mirando en pantalla.
        bool Holders(Player* master, uint32 questId, std::vector<Member>& out);

        // DARLE UNA DE MIS MISIONES A QUIEN NO LA LLEVA.
        //
        // Mismo motor que `CatchUp` -- marca las anteriores de la cadena y
        // luego intenta darsela -- con la puerta cambiada de sitio, que es lo
        // unico que separa a las dos:
        //
        //   `CatchUp` exige que el PNJ QUE TIENES DELANTE de esa mision.
        //   `Share`   exige que LA LLEVES TU.
        //
        // Las dos existen para lo mismo: que el addon no pueda pedir que se
        // marque como hecha una cadena cualquiera del juego. Y la de `Share` es
        // la mas estrecha de las dos, porque tu registro son 25 misiones y las
        // que da un PNJ pueden ser de cualquiera.
        //
        // El `questGiver` que se le pasa al nucleo es el MAESTRO, no null: para
        // una mision con reloj `Player::AddQuest` copia el tiempo que le queda
        // al que la comparte (`PlayerQuest.cpp`, `questGiver->IsPlayer()`), que
        // es exactamente el reparto que hace el compartir misiones del juego.
        bool Share(Player* master, uint32 questId,
                   std::vector<std::string> const& names,
                   int& okOut, int& failOut,
                   std::vector<std::string>& notes, std::string* why = nullptr);

        // PONER AL DIA LA CADENA, para el companero que se quedo atras.
        //
        // El caso: vas por la mitad de una cadena, un bot no te siguio, y ahora
        // no puede coger la que toca porque le faltan las anteriores. Sin esto
        // ese bot se queda descolgado de la cadena PARA SIEMPRE -- las misiones
        // de antes ya no las da nadie donde estas.
        //
        // === POR QUE ESTO NO ES UN TRUCO, Y POR QUE NO HACEN FALTA COMANDOS GM
        //
        // El requisito de cadena que el nucleo comprueba es literalmente
        // `IsQuestRewarded(prevId)` (`PlayerQuest.cpp:1039`), y hay un metodo
        // publico que lo pone: `Player::SetRewardedQuest(id)`, tres lineas que
        // insertan en `m_RewardedQuests` y lo marcan para guardar. No se
        // falsifica un paquete, no se toca la base de datos a mano, y no hace
        // falta seleccionar a cada bot para escribirle un `.quest complete`:
        // los comandos GM llaman a este mismo nucleo, solo que de uno en uno y
        // sobre tu seleccion.
        //
        // SOLO SE FUERZA LA CADENA. Nivel, clase, raza, reputacion y registro
        // lleno se dejan como estan y se DICEN: son motivos distintos de "no te
        // siguio", y taparlos convertiria un boton honesto en uno que a veces
        // hace algo que no entiendes.
        //
        // Los eslabones NEGATIVOS de `prevQuests` no se pueden arreglar asi --
        // piden la mision ACTIVA, no recompensada (`:1071`) -- y por eso se
        // informan en vez de fingirse.
        bool CatchUp(Player* master, ObjectGuid npcGuid, uint32 questId,
                     std::vector<std::string> const& names,
                     int& okOut, int& failOut,
                     std::vector<std::string>& notes, std::string* why = nullptr);

        // Aceptar / entregar para una lista de nombres (el jugador incluido).
        // `okOut` y `failOut` reciben cuantos salieron bien y cuantos no, para
        // que el cliente pueda decir algo concreto en vez de "hecho".
        //
        // `why` recibe el motivo cuando la operacion entera no se pudo ni
        // intentar (no existe la quest, el NPC no la da...).
        bool Accept(Player* master, ObjectGuid npcGuid, uint32 questId,
                    std::vector<std::string> const& names,
                    int& okOut, int& failOut, std::string* why = nullptr);

        // `reward` = AUTO_REWARD significa "elige tu por cada uno". Lo pidio
        // `PRUEBAS-20` B: *"si no selecciono nada, el bot debe escoger la que
        // mejor le funcione por stats / clase"*.
        //
        // Y no es solo comodidad: es lo que hace posible entregar en automatico
        // una mision con eleccion. Sin esto, la unica opcion segura era saltarse
        // esas misiones -- porque elegir el mismo objeto para cuatro clases
        // distintas es acertar en una y regalar basura a tres, y eso no se
        // deshace.
        //
        // 255 y no 0: 0 es un indice de recompensa perfectamente valido.
        constexpr uint32 AUTO_REWARD = 255;

        // `force` = COMPLETAR Y ENTREGAR aunque no la lleven hecha.
        //
        // === Y SOLO SOBRE LO QUE TU YA ENTREGASTE ===========================
        //
        // El forzado se ignora si el MAESTRO no tiene esa mision cobrada. Sin
        // esa puerta el alcance era mucho mas ancho de lo que se pidio: el
        // disparador de la entrega automatica es `QUEST_FINISHED`, que en
        // 3.3.5a significa *"se cerro el dialogo"* y nada mas -- no lleva el id
        // de nada, y el manejador de Blizzard solo hace `HideUIPanel`. Asi que
        // cerrar la ventana en un PNJ que recibe tres misiones habria
        // completado las tres, **incluidas las que el jugador aun esta
        // haciendo**.
        //
        // La puerta es exacta y no necesita adivinar cual acabas de entregar:
        // cuando llega esta llamada el nucleo ya te ha recompensado, asi que la
        // que acabas de entregar cumple, y las que llevas a medias no.
        //
        // Lo que SI sigue alcanzando, y es deliberado: una mision que
        // entregaste hace tiempo en ese mismo PNJ y que a un bot le falta --
        // p.ej. uno que entro al grupo despues. Ponerle al dia es justo para lo
        // que existe esto.
        //
        // La misma puerta esta ademas en el cliente, que filtra antes de
        // mandar. Aqui esta por ser el lado con autoridad: el cliente decide
        // que pedir, el servidor decide que es legal.
        //
        // Sin el, solo entrega quien ya tiene la mision en COMPLETE, o sea
        // quien hizo los objetivos. Con el, cada companero acaba con la mision
        // hecha y cobrada, y el camino tiene TRES escalones porque hay tres
        // formas distintas de quedarse atras:
        //
        //   1. NO LA LLEVA        -> se le marca la cadena y se le da (mismo
        //                            motor que `Share`).
        //   2. LE FALTAN OBJETOS  -> se le meten en la bolsa. Ver abajo.
        //   3. LA LLEVA A MEDIAS  -> `Player::CompleteQuest`, que pone el
        //                            estado y la ranura del registro.
        //
        // === LOS OBJETOS NO SON UN DETALLE: SIN ELLOS EL NUCLEO SE NIEGA =====
        //
        // `CompleteQuest` pone el estado y nada mas -- no inventa los objetos.
        // Y `CanRewardQuest` (`PlayerQuest.cpp`, rama `QUEST_SPECIAL_FLAGS_DELIVER`)
        // vuelve a contar lo que hay en la bolsa y devuelve false si falta algo.
        // O sea que forzar el estado NO basta para una mision de recoger: el
        // nucleo la rechazaria igual, en silencio y solo en esas.
        //
        // Asi que se le completan las pilas que le falten antes de entregar, y
        // `RewardQuest` las destruye acto seguido -- eso ultimo ya lo hacia
        // (`DestroyItemCount` sobre `RequiredItemId` y sobre `ItemDrop`), que es
        // la otra mitad de lo que se pidio: que los objetos de mision
        // desaparezcan de las bolsas al entregar.
        //
        // Lo que NO se salta: `CanRewardQuest` entera. Sitio en la bolsa para la
        // recompensa, misiones diarias, y el dinero de las que CUESTAN oro
        // (`GetRewOrReqMoney() < 0`). Forzar el estado es una cosa; dejar a un
        // bot en numeros rojos por saltarse una comprobacion es otra.
        //
        // `notes` recibe una linea por companero, igual que `CatchUp`: "2 bien y
        // 1 mal" no dice cual ni por que, y aqui el por que es la mitad del
        // valor.
        bool TurnIn(Player* master, ObjectGuid npcGuid, uint32 questId, uint32 reward,
                    std::vector<std::string> const& names,
                    int& okOut, int& failOut,
                    std::vector<std::string>& notes,
                    bool force = false, std::string* why = nullptr);

        // APAGAR LA MAQUINARIA DE MISIONES DE LA IA DE CADA BOT. Devuelve a
        // cuantos les llego.
        //
        // NO ES UNA PREFERENCIA: es lo que hace que "espera a que yo pulse" sea
        // cierto. La estrategia `quest` de mod-playerbots
        // (`QuestStrategies.cpp:27`) responde al disparador "gossip hello", y
        // ese disparador lo arma el `CMSG_GOSSIP_HELLO` / `CMSG_QUESTGIVER_HELLO`
        // que manda TU cliente al abrir la conversacion
        // (`PlayerbotAI.cpp:164-165`). O sea que **con solo abrir la ventana del
        // PNJ**, cada bot ejecuta `TalkToQuestGiverAction` contra el objetivo del
        // maestro y ENTREGA ahi mismo todo lo que tenga completado, eligiendo la
        // recompensa por su cuenta.
        //
        // Peor: con `AiPlayerbot.SyncQuestWithPlayer = 1` esa misma accion
        // primero COMPLETA la mision del bot si la tuya esta completa
        // (`TalkToQuestGiverAction.cpp:39-46`), asi que ni siquiera hace falta
        // que el bot haya hecho el trabajo.
        //
        // Reportado exactamente asi: *"i tried to turn a quest and bots auto
        // turned it automatically while i didnt even press the complete
        // button (...) any time i opened the npc's quest window the log said the
        // bots turned the quest"*.
        //
        // NO SE PIERDE NADA AL QUITARLA, y esa es la razon de que sea la salida
        // correcta y no un parche: todo lo que esa estrategia daba lo hace ya
        // este modulo, y ademas atado a un click tuyo -- `Accept`/`Share` para
        // dar misiones, `TurnIn` para entregarlas. Lo que se va con ella es solo
        // el camino que se disparaba SOLO. El credito de objetivos (matar,
        // recoger) no pasa por aqui: eso es el nucleo, no la IA.
        //
        // Y NO PUEDE HABER RECOMPENSA DOBLE, ni antes ni ahora, que era el otro
        // miedo del informe: `Player::RewardQuest` solo corre detras de
        // `CanRewardQuest`, y un `GetQuestRewardStatus` cierto la corta. La
        // propia `TalkToQuestGiverAction::TurnInQuest` empieza con esa misma
        // guarda. Cobrar cinco veces no estaba pasando; lo que pasaba es que
        // cobraban UNA vez, sin que lo pidieras.
        int SetGroupAI(Player* master, bool on);

        // ABANDONAR POR EL GRUPO. La otra mitad de "quiero el mismo registro de
        // misiones que ellos": aceptar y entregar ya iban juntos, y abandonar
        // no, asi que una mision tirada por ti se quedaba en los cuatro bots
        // para siempre.
        //
        // NO HAY NADA EN mod-playerbots QUE LO HAGA, y esto se comprobo antes de
        // escribirlo: no hay ningun manejador de `CMSG_QUESTLOG_REMOVE_QUEST`
        // entre los `masterIncomingPacketHandlers` (`PlayerbotAI.cpp:160-220`),
        // y el unico sitio donde un bot suelta una mision por su cuenta es
        // `CleanQuestLogAction`, que tira las GRISES por nivel y no tiene nada
        // que ver con lo que tu hagas.
        //
        // LA SECUENCIA ES LA DEL NUCLEO, COPIADA DE SU PROPIO MANEJADOR
        // (`QuestHandler.cpp:396`, `HandleQuestLogRemoveQuest`) y no inventada:
        // `TakeQuestSourceItem` -> `AbandonQuest` (que devuelve los objetos de
        // mision) -> `RemoveActiveQuest` -> limpiar el hueco del registro. Es la
        // misma regla que ya se siguio con el intercambio de bolsas: cuando el
        // nucleo tiene escrita la secuencia, se copia de ahi.
        //
        // Se respeta `TakeQuestSourceItem`, que puede decir que NO -- un objeto
        // de mision equipado que no se puede quitar. El nucleo aborta ahi el
        // abandono del jugador, y aqui igual: dejar la mision a medio quitar
        // seria peor que no quitarla.
        bool Drop(Player* master, uint32 questId,
                  std::vector<std::string> const& names,
                  int& okOut, int& failOut,
                  std::vector<std::string>& notes, std::string* why = nullptr);

        // LA MISION DE CLASE QUE LE TOCA, al subir de nivel. Devuelve el id de
        // la que se le dio, o 0 si no habia ninguna o no se pudo.
        //
        // Vale para un bot y para el jugador: lo unico que mira es el registro
        // de misiones y el nivel, y ninguna de las dos cosas sabe quien lleva el
        // personaje.
        //
        // === UNA SOLA EN EL REGISTRO ========================================
        //
        // Es la regla que se pidio, y ademas es la que hace que esto no pueda
        // hacer dano: el registro son 25 huecos, y un personaje de nivel 40 que
        // estrene esto cumple las condiciones de una docena de misiones de clase
        // a la vez. Sin el tope, el primer nivel que subiera le llenaria el
        // registro de golpe con misiones repartidas por medio mundo.
        //
        // Con el tope, el ritmo es: una al subir de nivel, la haces, la entregas
        // en tu entrenador COMO SIEMPRE -- esto no toca la entrega -- y la
        // siguiente llega al subir otra vez.
        //
        // === LOS ESLABONES QUE FALTAN SE HACEN, NO SE FINGEN =================
        //
        // Si la que le toca cuelga de otras que no hizo, se le hacen enteras
        // primero: darsela, completarla y COBRARLA. El motivo esta en el cuerpo,
        // y en una linea es que la recompensa de una mision de clase suele ser
        // un hechizo que no vende ningun entrenador -- marcarlas y ya dejaria a
        // un brujo sin esbirros y a un druida sin forma de oso.
        uint32 GrantClassQuest(Player* who);

        // UNA FILA DEL REGISTRO DE ALGUIEN. Lo que la ventana necesita para
        // dibujar una linea y nada mas.
        struct Entry
        {
            std::string name;               // de quien es el registro
            uint32      questId = 0;
            std::string title;
            std::string zone;               // vacio si es de clase o no tiene
            uint8       status = ST_DOING;  // solo ST_DOING o ST_READY
            bool        classQuest = false;
        };

        // EL REGISTRO DE MISIONES DE TODO EL GRUPO, EL MAESTRO INCLUIDO.
        //
        // Es lo unico que no se podia ver: tus misiones ya las dibuja el
        // registro del juego, y las de tus companeros no las dibuja nadie.
        //
        // Se leen las 25 RANURAS y no `m_QuestStatus`, que es la diferencia
        // entre "lo que lleva" y "lo que ha tocado alguna vez". El porque esta
        // en el cuerpo.
        //
        // La zona sale de `ZoneOrSort` cuando es positiva. Las de clase van con
        // la zona vacia A PROPOSITO: son su propio grupo, se pidieron como su
        // propio grupo, y varias de ellas ni siquiera tienen zona en los datos.
        bool Registry(Player* master, std::vector<Entry>& out);

        // DARLA POR HECHA Y COBRADA, SIN PNJ Y SIN IR A NINGUN SITIO.
        //
        // === EN QUE SE DIFERENCIA DE `TurnIn(force)` ========================
        //
        // `TurnIn` necesita un PNJ delante que reciba esa mision, y ademas solo
        // fuerza lo que TU ya entregaste -- una puerta que existe porque su
        // disparador es "se cerro el dialogo", que no dice de cual (ver la nota
        // de `TurnIn` arriba).
        //
        // Aqui no hay ninguna de las dos cosas, y no es un descuido: el
        // disparador es un boton en una fila que NOMBRA la mision y NOMBRA al
        // personaje. No hay nada que adivinar, asi que no hay nada de lo que
        // protegerse. Fue la decision explicita al pedir esta ventana --
        // *"completar y cobrar, ahi mismo"*.
        //
        // Lo que SIGUE sin saltarse es `CanRewardQuest`: sitio en la bolsa,
        // diarias y el oro de las que cuestan dinero. Y los objetos que falten
        // se ponen antes, porque si no el nucleo rechaza en silencio las de
        // recoger. Las dos cosas estan explicadas en `TurnIn`.
        //
        // La recompensa a elegir la pone `BestReward`, por personaje.
        bool ForceFinish(Player* master, uint32 questId,
                         std::vector<std::string> const& names,
                         int& okOut, int& failOut,
                         std::vector<std::string>& notes, std::string* why = nullptr);
    }
}

#endif  // MOD_RTS_QUESTS_H
