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

        bool TurnIn(Player* master, ObjectGuid npcGuid, uint32 questId, uint32 reward,
                    std::vector<std::string> const& names,
                    int& okOut, int& failOut, std::string* why = nullptr);
    }
}

#endif  // MOD_RTS_QUESTS_H
