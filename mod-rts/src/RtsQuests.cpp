#include "RtsQuests.h"

#include "RtsBotApi.h"   // solo por `Resolve` -- ver la cabecera

#include "Creature.h"
#include "Group.h"
#include "GroupReference.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ItemTemplate.h"
#include "QuestDef.h"

#include <algorithm>
#include <set>
#include <string>
#include <vector>

namespace
{
    Player* Who(Player* master, std::string const& name)
    {
        if (!master || name.empty())
            return nullptr;
        if (name == master->GetName())
            return master;
        return rts::bots::Resolve(master, name);
    }

    Creature* NpcOf(Player* master, ObjectGuid guid)
    {
        if (!master || !guid)
            return nullptr;
        return ObjectAccessor::GetCreature(*master, guid);
    }

    // El jugador va PRIMERO en el reparto. Es su grupo y es quien mira la
    // ventana, asi que su fila es la que busca el ojo.
    std::vector<Player*> Party(Player* master)
    {
        std::vector<Player*> out;
        if (!master)
            return out;

        out.push_back(master);

        if (Group* group = master->GetGroup())
        {
            for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
            {
                Player* m = ref->GetSource();
                if (m && m != master && m->IsInWorld())
                    out.push_back(m);
            }
        }
        return out;
    }

    // `gives` = este NPC la DA. Sin eso no puede haber "puede cogerla": ver
    // abajo.
    // LA MEJOR RECOMPENSA PARA ESTE PERSONAJE, entre las que la mision ofrece.
    //
    // El criterio, por orden y a proposito simple:
    //
    //   1. que PUEDA usarla (`CanUseItem` mira clase, raza y requisitos);
    //   2. entre esas, la de mayor nivel de objeto;
    //   3. si ninguna le vale, la que mas valga al venderla -- porque una
    //      recompensa que no puede llevar es oro, y mas oro es mejor que menos.
    //
    // NO se usa `ItemUsageValue` de playerbots aunque puntue mejor: seria la
    // unica llamada suya en todo este fichero, y la regla de este plan es
    // preferir el nucleo siempre que haya eleccion. El nucleo sabe si puede
    // equiparlo, que es el 90% de la decision.
    uint32 BestReward(Player* who, Quest const* quest)
    {
        uint32 const count = quest->GetRewChoiceItemsCount();
        if (count == 0)
            return 0;

        uint32 best = 0;
        bool   have = false;
        bool   bestUsable = false;
        uint32 bestLevel = 0;
        uint32 bestPrice = 0;

        for (uint32 i = 0; i < count && i < QUEST_REWARD_CHOICES_COUNT; ++i)
        {
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(quest->RewardChoiceItemId[i]);
            if (!proto)
                continue;

            bool const usable = (who->CanUseItem(proto) == EQUIP_ERR_OK);

            bool take;
            if (!have)
                take = true;                           // el primero valido manda
            else if (usable != bestUsable)
                take = usable;                         // lo usable gana siempre
            else if (usable)
                take = proto->ItemLevel > bestLevel;   // entre usables, el mejor
            else
                take = proto->SellPrice > bestPrice;   // entre inutiles, el caro

            if (take)
            {
                best = i;
                have = true;
                bestUsable = usable;
                bestLevel = proto->ItemLevel;
                bestPrice = proto->SellPrice;
            }
        }

        return best;
    }

    uint8 StatusFor(Player* who, Quest const* quest, bool gives)
    {
        uint32 const id = quest->GetQuestId();

        // Lo primero es "ya la hizo", porque una quest no repetible ya
        // entregada tambien saldria como "no puede cogerla" y las dos cosas se
        // dibujan distinto: una es un tick y la otra es un aspa.
        if (who->GetQuestRewardStatus(id))
            return rts::quests::ST_DONE;

        switch (who->GetQuestStatus(id))
        {
            case QUEST_STATUS_COMPLETE:
                return rts::quests::ST_READY;
            case QUEST_STATUS_INCOMPLETE:
            case QUEST_STATUS_FAILED:
                return rts::quests::ST_DOING;
            default:
                break;
        }

        // "PUEDE COGERLA" SOLO SI ESTE PNJ LA DA, y esto es el arreglo de
        // `PRUEBAS-20` B: *"personajes con misiones disponibles (naranja) no me
        // deja hacer que la cojan, no hay forma"*.
        //
        // Una mision que este PNJ solo RECIBE (empieza en otro sitio) salia
        // naranja para quien no la llevaba -- porque `CanTakeQuest` mira si
        // podria cogerla EN ALGUN SITIO, no aqui. El boton de aceptar no
        // aparecia, y con razon: este PNJ no la da. Pero el punto decia que si.
        //
        // El punto tenia razon sobre el personaje y mentia sobre el PNJ, que es
        // la peor combinacion: parece un boton roto en vez de una mision que no
        // es de aqui.
        if (!gives)
            return rts::quests::ST_NO;

        // `msg = false` en las dos: son PREGUNTAS, y con `true` el nucleo le
        // manda al personaje un paquete de error de quest. Para un bot eso va a
        // una sesion falsa, pero para el jugador serian avisos rojos en pantalla
        // cada vez que se pasa el raton por un NPC.
        if (who->CanTakeQuest(quest, false) && who->CanAddQuest(quest, false))
            return rts::quests::ST_CAN;

        return rts::quests::ST_NO;
    }
}

bool rts::quests::Look(Player* master, ObjectGuid npcGuid, std::vector<Offer>& out)
{
    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return false;

    uint32 const entry = npc->GetEntry();

    // Las que DA y las que RECIBE son dos tablas distintas, y una quest puede
    // estar en las dos (empieza y acaba en el mismo NPC). Se juntan en un mapa
    // por id con banderas para que salga UNA fila por quest -- si no, la de "ve
    // y vuelve" saldria dos veces y no habria forma de saber cual es cual.
    std::vector<uint32> order;
    std::vector<uint32> flagsFor;

    auto add = [&](uint32 questId, uint32 flag)
    {
        for (std::size_t i = 0; i < order.size(); ++i)
        {
            if (order[i] == questId)
            {
                flagsFor[i] |= flag;
                return;
            }
        }
        order.push_back(questId);
        flagsFor.push_back(flag);
    };

    {
        QuestRelationBounds const bounds = sObjectMgr->GetCreatureQuestRelationBounds(entry);
        for (auto it = bounds.first; it != bounds.second; ++it)
            add(it->second, FLAG_GIVES);
    }
    {
        QuestRelationBounds const bounds = sObjectMgr->GetCreatureQuestInvolvedRelationBounds(entry);
        for (auto it = bounds.first; it != bounds.second; ++it)
            add(it->second, FLAG_TAKES);
    }

    std::vector<Player*> const party = Party(master);

    for (std::size_t i = 0; i < order.size(); ++i)
    {
        Quest const* quest = sObjectMgr->GetQuestTemplate(order[i]);
        if (!quest)
            continue;

        Offer o;
        o.questId = quest->GetQuestId();
        o.flags   = flagsFor[i];
        o.level   = static_cast<uint32>(std::max<int32>(0, quest->GetQuestLevel()));
        o.title   = quest->GetTitle();

        uint32 const choices = quest->GetRewChoiceItemsCount();
        if (choices > 0)
        {
            o.flags |= FLAG_CHOICE;
            for (uint32 c = 0; c < choices && c < QUEST_REWARD_CHOICES_COUNT; ++c)
                o.choices.push_back(quest->RewardChoiceItemId[c]);
        }

        for (Player* m : party)
        {
            Member e;
            e.name   = m->GetName();
            e.status = StatusFor(m, quest, (o.flags & FLAG_GIVES) != 0);
            o.members.push_back(e);
        }

        out.push_back(o);
    }

    return true;
}

namespace
{
    // Todos los eslabones POSITIVOS de los que cuelga una mision, hacia atras.
    //
    // El tope no es decoracion: `prevQuests` sale de datos del mundo y un ciclo
    // ahi -- una fila mal montada, un parche de terceros -- seria una recursion
    // sin fondo en el hilo del mundo. El conjunto ya corta los ciclos simples;
    // la profundidad corta el resto.
    constexpr int kMaxDepth = 32;

    void CollectChain(uint32 questId, std::set<uint32>& out, int depth)
    {
        if (depth > kMaxDepth)
            return;

        Quest const* q = sObjectMgr->GetQuestTemplate(questId);
        if (!q)
            return;

        for (int32 raw : q->prevQuests)
        {
            // Los negativos piden la mision ACTIVA y no recompensada, asi que
            // marcarlos no arregla nada. Se saltan aqui y el motivo se cuenta
            // arriba, donde se puede decir.
            if (raw <= 0)
                continue;

            uint32 const prev = static_cast<uint32>(raw);
            if (!prev || out.count(prev))
                continue;

            out.insert(prev);
            CollectChain(prev, out, depth + 1);
        }
    }

    // QUE PUERTA LE CIERRA EL PASO, con el nombre que el jugador entiende.
    //
    // Todas las `SatisfyQuest*` del nucleo son publicas, asi que se puede decir
    // CUAL falla en vez de "no puede". Es la diferencia entre un boton que se
    // explica y uno que hay que adivinar -- y aqui importa mas de lo normal,
    // porque el boton promete arreglar una cosa concreta y todo lo demas queda
    // fuera a proposito.
    //
    // El orden es el de `CanTakeQuest`: se informa la PRIMERA que falla, que es
    // la que el nucleo habria contestado.
    char const* Blocker(Player* who, Quest const* q)
    {
        if (!who->SatisfyQuestRace(q, false))       return "no es de su raza";
        if (!who->SatisfyQuestClass(q, false))      return "no es de su clase";
        if (!who->SatisfyQuestLevel(q, false))      return "le falta nivel";
        if (!who->SatisfyQuestPreviousQuest(q, false)) return "le falta una anterior que no se puede forzar";
        if (!who->SatisfyQuestSkill(q, false))      return "le falta habilidad";
        if (!who->SatisfyQuestReputation(q, false)) return "le falta reputacion";
        if (!who->SatisfyQuestExclusiveGroup(q, false)) return "hizo otra del mismo grupo";
        if (!who->SatisfyQuestStatus(q, false))     return "ya la tiene o ya la hizo";
        if (!who->SatisfyQuestBreadcrumb(q, false)) return "va por otra rama";
        if (!who->SatisfyQuestNextChain(q, false))  return "ya lleva la siguiente";
        if (!who->SatisfyQuestPrevChain(q, false))  return "le falta la rama previa";
        if (!who->SatisfyQuestLog(false))           return "registro de misiones lleno";
        return "no puede, y el nucleo no dice por que";
    }

    // MARCAR COMO RECOMPENSADOS LOS ESLABONES ANTERIORES. Devuelve cuantos.
    // Lo usan los dos caminos que dan una mision a la fuerza -- el boton de
    // compartir y la entrega forzada -- asi que sale aqui antes de ser dos
    // copias de la misma media docena de lineas.
    int MarkChain(Player* who, uint32 questId)
    {
        std::set<uint32> chain;
        CollectChain(questId, chain, 0);

        int marked = 0;
        for (uint32 prev : chain)
        {
            if (who->IsQuestRewarded(prev))
                continue;
            who->SetRewardedQuest(prev);
            ++marked;
        }
        return marked;
    }

    // LOS OBJETOS QUE LE FALTEN PARA PODER ENTREGAR. Ver la cabecera: sin esto
    // el nucleo rechaza la entrega de cualquier mision de recoger, y solo de
    // esas -- que es la peor forma de fallar, porque parece que el boton
    // funciona a veces.
    //
    // Se le meten los que falten y `RewardQuest` los destruye a continuacion,
    // asi que el saldo en la bolsa es cero. Se cuenta lo mismo que cuenta
    // `CanRewardQuest` (`GetItemCount(id)`), no algo parecido: contar distinto
    // aqui seria meter una pila de mas o de menos.
    bool Supply(Player* who, Quest const* quest, std::string& whyNot)
    {
        if (!quest->HasSpecialFlag(QUEST_SPECIAL_FLAGS_DELIVER))
            return true;

        for (uint8 i = 0; i < QUEST_ITEM_OBJECTIVES_COUNT; ++i)
        {
            uint32 const id = quest->RequiredItemId[i];
            uint32 const need = quest->RequiredItemCount[i];
            if (!id || !need)
                continue;

            uint32 const have = who->GetItemCount(id);
            if (have >= need)
                continue;

            uint32 const missing = need - have;

            ItemPosCountVec dest;
            InventoryResult const res =
                who->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, id, missing);
            if (res != EQUIP_ERR_OK)
            {
                whyNot = "no le cabe el objeto de mision en la bolsa";
                return false;
            }

            who->StoreNewItem(dest, id, true);
        }

        return true;
    }

    // EL MOTOR QUE COMPARTEN `CatchUp` Y `Share`.
    //
    // Estaba escrito una sola vez dentro de `CatchUp` y ahora tiene dos
    // llamantes, asi que sale aqui antes de que sea dos copias: lo que cambia
    // entre los dos es la PUERTA (que el PNJ la de / que la lleves tu) y quien
    // figura como dador, y nada del reparto.
    void CatchUpEach(Player* master, Quest const* quest, Object* questGiver,
                     std::vector<std::string> const& names,
                     int& okOut, int& failOut, std::vector<std::string>& notes)
    {
        uint32 const questId = quest->GetQuestId();

        for (std::string const& name : names)
        {
            Player* who = Who(master, name);
            if (!who)
            {
                ++failOut;
                continue;
            }

            // Ya la lleva o ya la hizo: no hay nada que poner al dia, y
            // marcarle eslabones de mas seria escribirle historial que no pidio
            // nadie.
            if (who->GetQuestStatus(questId) != QUEST_STATUS_NONE || who->IsQuestRewarded(questId))
            {
                notes.push_back(name + ": ya la tiene");
                continue;
            }

            int const marked = MarkChain(who, questId);

            if (!who->CanTakeQuest(quest, false) || !who->CanAddQuest(quest, false))
            {
                ++failOut;
                notes.push_back(name + ": " + Blocker(who, quest) +
                                (marked ? " (" + std::to_string(marked) + " de la cadena si le quedaron dadas)" : ""));
                continue;
            }

            who->AddQuestAndCheckCompletion(quest, questGiver);
            ++okOut;
            notes.push_back(name + ": " + std::to_string(marked) + " anteriores + la actual");
        }
    }
}

bool rts::quests::CatchUp(Player* master, ObjectGuid npcGuid, uint32 questId,
                          std::vector<std::string> const& names,
                          int& okOut, int& failOut,
                          std::vector<std::string>& notes, std::string* why)
{
    okOut = 0;
    failOut = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
        return fail("esa mision no existe");

    // LA MISMA PUERTA QUE `Accept`, y por la misma razon: sin ella el addon
    // podria pedir que se marque como hecha cualquier cadena del juego contra
    // cualquier PNJ. Que el PNJ que tienes delante DE esa mision es lo que
    // convierte esto en "ponerlos al dia con lo que estoy haciendo".
    bool gives = false;
    QuestRelationBounds const bounds = sObjectMgr->GetCreatureQuestRelationBounds(npc->GetEntry());
    for (auto it = bounds.first; it != bounds.second && !gives; ++it)
        gives = (it->second == questId);
    if (!gives)
        return fail("ese personaje no da esa mision");

    CatchUpEach(master, quest, npc, names, okOut, failOut, notes);
    return true;
}

bool rts::quests::Holders(Player* master, uint32 questId, std::vector<Member>& out)
{
    if (!master)
        return false;

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
        return false;

    // El maestro no entra. `Party` lo devuelve el primero a proposito, y se
    // descarta por PUNTERO y no por posicion: una lista vacia y un orden que
    // cambie son dos formas distintas de que esto se rompa callado.
    for (Player* m : Party(master))
    {
        if (m == master)
            continue;

        Member e;
        e.name   = m->GetName();
        e.status = StatusFor(m, quest, true);
        out.push_back(e);
    }

    return true;
}

bool rts::quests::Share(Player* master, uint32 questId,
                        std::vector<std::string> const& names,
                        int& okOut, int& failOut,
                        std::vector<std::string>& notes, std::string* why)
{
    okOut = 0;
    failOut = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    if (!master)
        return fail("no hay heroe");

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
        return fail("esa mision no existe");

    // LA PUERTA. Ver la cabecera: lo que autoriza a escribir historial de
    // cadena en otro personaje es que esa mision este en TU registro.
    if (master->GetQuestStatus(questId) == QUEST_STATUS_NONE && !master->IsQuestRewarded(questId))
        return fail("esa mision no la llevas tu");

    CatchUpEach(master, quest, master, names, okOut, failOut, notes);
    return true;
}

bool rts::quests::Accept(Player* master, ObjectGuid npcGuid, uint32 questId,
                         std::vector<std::string> const& names,
                         int& okOut, int& failOut, std::string* why)
{
    okOut = 0;
    failOut = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
        return fail("esa mision no existe");

    // Que el NPC la DE de verdad. Sin esto, el addon podria pedir cualquier id
    // de mision del juego contra cualquier NPC -- y el nucleo lo aceptaria,
    // porque `AddQuest` no comprueba de donde sale la mision.
    bool gives = false;
    QuestRelationBounds const bounds = sObjectMgr->GetCreatureQuestRelationBounds(npc->GetEntry());
    for (auto it = bounds.first; it != bounds.second && !gives; ++it)
        gives = (it->second == questId);
    if (!gives)
        return fail("ese personaje no da esa mision");

    for (std::string const& name : names)
    {
        Player* who = Who(master, name);
        if (!who)
        {
            ++failOut;
            continue;
        }

        if (!who->CanTakeQuest(quest, false) || !who->CanAddQuest(quest, false))
        {
            ++failOut;
            continue;
        }

        // `AddQuestAndCheckCompletion` y no `AddQuest` a secas: hay misiones que
        // nacen completas (las de "habla con"), y con `AddQuest` se quedarian en
        // el registro sin marcarse listas -- o sea aceptadas y aparentemente
        // rotas.
        who->AddQuestAndCheckCompletion(quest, npc);
        ++okOut;
    }

    return true;
}

bool rts::quests::TurnIn(Player* master, ObjectGuid npcGuid, uint32 questId, uint32 reward,
                         std::vector<std::string> const& names,
                         int& okOut, int& failOut,
                         std::vector<std::string>& notes,
                         bool force, std::string* why)
{
    okOut = 0;
    failOut = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
        return fail("esa mision no existe");

    bool takes = false;
    QuestRelationBounds const bounds =
        sObjectMgr->GetCreatureQuestInvolvedRelationBounds(npc->GetEntry());
    for (auto it = bounds.first; it != bounds.second && !takes; ++it)
        takes = (it->second == questId);
    if (!takes)
        return fail("ese personaje no recibe esa mision");

    // LA ELECCION DE RECOMPENSA SE VALIDA AQUI Y NO SE ADIVINA.
    //
    // `RewardQuest` usa `reward` como indice del array de recompensas a elegir
    // sin comprobar el rango cuando la mision no las tiene. Un indice fuera de
    // sitio en una mision con eleccion es dar el objeto equivocado -- y eso no
    // se deshace.
    // EL FORZADO SOLO ALCANZA A LO QUE TU YA ENTREGASTE. Ver la cabecera: el
    // disparador es "se cerro el dialogo", que no dice cual, asi que sin esto
    // el alcance eran TODAS las misiones que recibe ese PNJ.
    bool const doForce = force && master->GetQuestRewardStatus(questId);
    if (force && !doForce)
        notes.push_back("(no fuerzo esa: no la has entregado tu)");

    uint32 const choices = quest->GetRewChoiceItemsCount();
    bool const autoPick = (reward == AUTO_REWARD);
    if (choices > 0 && !autoPick && reward >= choices)
        return fail("esa mision te deja elegir recompensa y no has elegido");
    if (choices == 0)
        reward = 0;

    for (std::string const& name : names)
    {
        Player* who = Who(master, name);
        if (!who)
        {
            ++failOut;
            continue;
        }

        // La eleccion se decide POR PERSONAJE, no una vez para todos: el
        // guerrero y el mago no quieren lo mismo, y ese es el motivo entero de
        // que exista `AUTO_REWARD`.
        uint32 const pick = (autoPick && choices > 0) ? BestReward(who, quest)
                                                      : (choices > 0 ? reward : 0);

        // Ya la cobro: no se toca y no cuenta como fallo. Es lo primero
        // porque una mision ya entregada tambien fallaria mas abajo, y las dos
        // cosas no significan lo mismo.
        if (who->GetQuestRewardStatus(questId))
        {
            notes.push_back(name + ": ya la hizo");
            continue;
        }

        if (doForce)
        {
            // 1. QUE LA LLEVE. Mismo motor que el boton de compartir.
            if (who->GetQuestStatus(questId) == QUEST_STATUS_NONE)
            {
                int const marked = MarkChain(who, questId);
                if (!who->CanTakeQuest(quest, false) || !who->CanAddQuest(quest, false))
                {
                    ++failOut;
                    notes.push_back(name + ": " + Blocker(who, quest) +
                                    (marked ? " (" + std::to_string(marked) +
                                              " de la cadena si le quedaron dadas)" : ""));
                    continue;
                }
                who->AddQuestAndCheckCompletion(quest, npc);
            }

            // 2. QUE TENGA LOS OBJETOS. Ver la cabecera: sin esto el nucleo
            //    rechaza la entrega de las misiones de recoger.
            std::string whyNot;
            if (!Supply(who, quest, whyNot))
            {
                ++failOut;
                notes.push_back(name + ": " + whyNot);
                continue;
            }

            // 3. QUE ESTE HECHA.
            if (who->GetQuestStatus(questId) != QUEST_STATUS_COMPLETE)
                who->CompleteQuest(questId);

            // Y UNA MISION `TRACKING` SE COBRA SOLA AHI DENTRO.
            // `Player::CompleteQuest` acaba con
            // `if (qInfo->HasFlag(QUEST_FLAGS_TRACKING)) RewardQuest(qInfo, 0, this, false)`,
            // asi que para esas ya esta todo hecho al volver. Sin esta salida,
            // `CanRewardQuest` diria que no -- correctamente, porque ya esta
            // cobrada -- y lo contariamos como FALLO: un exito presentado como
            // error, que manda a buscar un problema que no existe.
            if (who->GetQuestRewardStatus(questId))
            {
                ++okOut;
                notes.push_back(name + ": hecha (se cobra sola)");
                continue;
            }
        }

        if (who->GetQuestStatus(questId) != QUEST_STATUS_COMPLETE)
        {
            ++failOut;
            notes.push_back(name + (doForce ? ": no se dejo completar"
                                            : ": no la tiene lista"));
            continue;
        }

        // NO SE SALTA. Sitio en la bolsa, diarias, y el oro de las que cuestan
        // dinero. Forzar el estado es una cosa; dejar a un bot en numeros rojos
        // saltandose una comprobacion del nucleo es otra.
        if (!who->CanRewardQuest(quest, pick, false))
        {
            ++failOut;
            notes.push_back(name + ": el nucleo no deja entregarsela "
                                   "(bolsa llena, diaria o le falta oro)");
            continue;
        }

        who->RewardQuest(quest, pick, npc, true);
        ++okOut;
    }

    return true;
}

int rts::quests::SetGroupAI(Player* master, bool on)
{
    if (!master)
        return 0;

    std::string const change = on ? "+quest" : "-quest";
    int changed = 0;

    // EL MAESTRO EL PRIMERO, Y FUERA DEL BUCLE DEL GRUPO A PROPOSITO. Con el
    // selfbot puesto tu personaje lleva la misma IA, asi que la estrategia le
    // entregaba a EL sus propias misiones completadas nada mas abrir la
    // conversacion. Y tiene que estar fuera porque el caso "sin grupo" existe:
    // el selfbot no necesita companeros, y un `return 0` temprano lo dejaria
    // sin apagar justo cuando juegas solo.
    if (rts::bots::Change(master, change, rts::bots::BOTH))
        ++changed;

    Group* group = master->GetGroup();
    if (!group)
        return changed;

    for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
    {
        Player* member = ref->GetSource();
        if (!member || member == master)
            continue;

        if (!rts::bots::Change(member, change, rts::bots::BOTH))
            continue;   // sin IA: no es un bot, no hay nada que apagar

        ++changed;
    }

    return changed;
}

bool rts::quests::Drop(Player* master, uint32 questId,
                       std::vector<std::string> const& names,
                       int& okOut, int& failOut,
                       std::vector<std::string>& notes, std::string* why)
{
    okOut = 0;
    failOut = 0;

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    if (!quest)
    {
        if (why)
            *why = "esa mision no existe";
        return false;
    }

    for (std::string const& name : names)
    {
        Player* who = Who(master, name);
        if (!who)
        {
            ++failOut;
            continue;
        }

        // El hueco se busca ANTES de tocar nada: `RemoveActiveQuest` deja de
        // contestar por esta mision, y sin el numero de hueco no se puede
        // limpiar la fila del registro que ve el cliente del bot.
        uint16 const slot = who->FindQuestSlot(questId);
        if (slot >= MAX_QUEST_LOG_SIZE)
        {
            notes.push_back(name + ": no la lleva");
            continue;
        }

        if (!who->TakeQuestSourceItem(questId, true))
        {
            ++failOut;
            notes.push_back(name + ": no puede soltar un objeto de la mision");
            continue;
        }

        if (quest->HasSpecialFlag(QUEST_SPECIAL_FLAGS_TIMED))
            who->RemoveTimedQuest(questId);

        who->AbandonQuest(questId);
        who->RemoveActiveQuest(questId);
        who->SetQuestSlot(slot, 0);
        ++okOut;
    }

    return true;
}
