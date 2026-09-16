#include "RtsBotApi.h"

#include "Group.h"
#include "ObjectAccessor.h"
#include "Player.h"

// LAS UNICAS CABECERAS DE mod-playerbots EN TODO mod-rts. Ver `RtsBotApi.h`.
//
// `AiObjectContext` solo esta declarada adelante en `PlayerbotAI.h`, y `GetValue`
// es una plantilla suya, asi que hace falta la definicion completa aqui.
#include "AiObjectContext.h"
#include "LastMovementValue.h"
#include "LootStrategyValue.h"
#include "PlayerbotAI.h"
#include "PlayerbotAIConfig.h"
#include "PlayerbotMgr.h"
#include "PlayerbotRepository.h"
#include "PositionValue.h"

namespace
{
    PlayerbotAI* AiFor(Player* bot)
    {
        return bot ? PlayerbotsMgr::instance().GetPlayerbotAI(bot) : nullptr;
    }

    AiObjectContext* ContextFor(Player* bot)
    {
        PlayerbotAI* ai = AiFor(bot);
        return ai ? ai->GetAiObjectContext() : nullptr;
    }

    BotState StateOf(rts::bots::Where where)
    {
        return where == rts::bots::COMBAT ? BOT_STATE_COMBAT : BOT_STATE_NON_COMBAT;
    }
}

// === resolucion =============================================================

Player* rts::bots::Resolve(Player* master, std::string const& name)
{
    if (!master || name.empty())
        return nullptr;

    Player* bot = ObjectAccessor::FindPlayerByName(name, false);
    if (!bot || bot == master || !bot->IsInWorld())
        return nullptr;

    Group* group = master->GetGroup();
    if (!group || !group->IsMember(bot->GetGUID()))
        return nullptr;

    return bot;
}

bool rts::bots::Driven(Player* bot)
{
    return AiFor(bot) != nullptr;
}

Player* rts::bots::MasterOf(Player* bot)
{
    PlayerbotAI* ai = AiFor(bot);
    return ai ? ai->GetMaster() : nullptr;
}

// === estrategias ============================================================

bool rts::bots::Change(Player* bot, std::string const& changes, Where where)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    if (where == BOTH)
    {
        ai->ChangeStrategy(changes, BOT_STATE_NON_COMBAT);
        ai->ChangeStrategy(changes, BOT_STATE_COMBAT);
        return true;
    }

    ai->ChangeStrategy(changes, StateOf(where));
    return true;
}

bool rts::bots::Has(Player* bot, std::string const& name, Where where)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    if (where == BOTH)
        return ai->HasStrategy(name, BOT_STATE_COMBAT)
            || ai->HasStrategy(name, BOT_STATE_NON_COMBAT);

    return ai->HasStrategy(name, StateOf(where));
}

std::set<std::string> rts::bots::Supported(Player* bot)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context)
        return {};

    return context->GetSupportedStrategies();
}

void rts::bots::Save(Player* bot)
{
    if (PlayerbotAI* ai = AiFor(bot))
        PlayerbotRepository::instance().Save(ai);
}

bool rts::bots::Add(Player* master, ObjectGuid guid)
{
    if (!master || !master->GetSession() || !guid)
        return false;

    PlayerbotMgr* mgr = PlayerbotsMgr::instance().GetPlayerbotMgr(master);
    if (!mgr)
        return false;

    mgr->AddPlayerBot(guid, master->GetSession()->GetAccountId());
    return true;
}

bool rts::bots::Remove(Player* master, ObjectGuid guid)
{
    if (!master || !guid)
        return false;

    PlayerbotMgr* mgr = PlayerbotsMgr::instance().GetPlayerbotMgr(master);
    if (!mgr)
        return false;

    mgr->LogoutPlayerBot(guid);
    return true;
}

bool rts::bots::Reset(Player* bot)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    // `false` = las de fabrica de su clase, no las que tuviera guardadas. Con
    // `true` volveria a cargar exactamente lo que queremos olvidar.
    ai->ResetStrategies(false);
    return true;
}

// === posicion ===============================================================

bool rts::bots::SetAnchor(Player* bot, char const* key,
                          float x, float y, float z, uint32 mapId)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context || !key)
        return false;

    PositionMap& posMap = context->GetValue<PositionMap&>("position")->Get();
    PositionInfo pos = posMap[key];
    pos.Set(x, y, z, mapId);
    posMap[key] = pos;
    return true;
}

bool rts::bots::ClearAnchor(Player* bot, char const* key)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context || !key)
        return false;

    PositionMap& posMap = context->GetValue<PositionMap&>("position")->Get();
    PositionInfo pos = posMap[key];
    pos.Reset();
    posMap[key] = pos;
    return true;
}

bool rts::bots::ForgetLastMove(Player* bot)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context)
        return false;

    context->GetValue<LastMovement&>("last movement")->Get().clear();
    return true;
}

// === acciones ===============================================================

bool rts::bots::DoAction(Player* bot, char const* action)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai || !action)
        return false;

    return ai->DoSpecificAction(action, Event(), true);
}

bool rts::bots::Cast(Player* bot, uint32 spellId, Unit* target)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai || !spellId)
        return false;

    return ai->CastSpell(spellId, target);
}

bool rts::bots::HoldAi(Player* bot, uint32 ms)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    // `SetNextCheckDelay` es publica y viene de `PlayerbotAIBase`, que es de
    // donde cuelga `PlayerbotAI`. No hay nada que reimplementar: es el mismo
    // mando que ellos usan para no pensar durante un GCD.
    ai->SetNextCheckDelay(ms);
    return true;
}

float rts::bots::ReactDistance()
{
    return sPlayerbotAIConfig.reactDistance;
}

// === valores del contexto ===================================================

bool rts::bots::SetLootAll(Player* bot, bool everything)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context)
        return false;

    LootStrategy* wanted = everything ? LootStrategyValue::all : LootStrategyValue::normal;
    context->GetValue<LootStrategy*>("loot strategy")->Set(wanted);
    return true;
}

bool rts::bots::SetFocusHeal(Player* bot, std::list<ObjectGuid> const& targets)
{
    AiObjectContext* context = ContextFor(bot);
    if (!context)
        return false;

    context->GetValue<std::list<ObjectGuid>>("focus heal targets")->Set(targets);
    return true;
}
