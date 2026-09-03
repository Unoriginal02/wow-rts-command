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

        if (who->GetQuestStatus(questId) != QUEST_STATUS_COMPLETE ||
            !who->CanRewardQuest(quest, pick, false))
        {
            ++failOut;
            continue;
        }

        who->RewardQuest(quest, pick, npc, true);
        ++okOut;
    }

    return true;
}
