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
#include "LootObjectStack.h"
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

std::string rts::bots::SpecRole(Player* bot)
{
    if (!bot)
        return std::string();

    // El `true` es `bySpec`, y es todo el motivo de llamar a esto.
    if (PlayerbotAI::IsTank(bot, true))
        return "tank";
    if (PlayerbotAI::IsHeal(bot, true))
        return "heal";
    return "dps";
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

bool rts::bots::SelfDrive(Player* master, bool on, std::string* why)
{
    auto fail = [why](char const* reason)
    {
        if (why)
            *why = reason;
        return false;
    };

    if (!master)
        return fail("no hay jugador");

    PlayerbotAI* ai = AiFor(master);

    if (!on)
    {
        if (!ai)
            return true;   // ya estaba fuera

        // EL `delete` ES EL CAMINO DE PLAYERBOTS, no un atajo: su destructor se
        // borra a si mismo del registro (`PlayerbotAI.cpp`, `RemovePlayerBotData`),
        // que es justo lo que hace su propio comando al apagarlo.
        delete ai;
        return true;
    }

    if (ai)
        return true;   // ya la lleva

    // LA MISMA PUERTA QUE EL COMANDO, y por eso se lee de su config y no de la
    // nuestra: si el servidor tiene el selfbot cerrado, atarlo al modo RTS no
    // es motivo para saltarselo.
    if (sPlayerbotAIConfig.selfBotLevel == 0)
        return fail("el selfbot esta apagado (AiPlayerbot.SelfBotLevel = 0)");
    if (sPlayerbotAIConfig.selfBotLevel == 1 && !master->CanBeGameMaster())
        return fail("el selfbot esta reservado a GM (AiPlayerbot.SelfBotLevel = 1)");

    PlayerbotsMgr::instance().AddPlayerbotData(master, true);

    PlayerbotAI* fresh = AiFor(master);
    if (!fresh)
        return fail("playerbots no engancho la IA");

    // TU AMO ERES TU, que es literalmente lo que `IsRealPlayer()` comprueba
    // (`PlayerbotAI.h:541`) para no hacer por ti lo que le toca a tu cliente:
    // confirmar teleports, disparar tus area triggers, soltarte el espiritu.
    fresh->SetMaster(master);

    // Y SUS ESTRATEGIAS GUARDADAS, que es lo que hace que el rol que pusiste
    // ayer siga puesto hoy. Mismo orden que el comando.
    PlayerbotRepository::instance().Load(fresh);
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

bool rts::bots::Preempt(Player* bot)
{
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    ai->InterruptSpell();

    if (AiObjectContext* context = ai->GetAiObjectContext())
        context->GetValue<LootObject>("loot target")->Set(LootObject());

    ai->SetNextCheckDelay(0);
    return true;
}

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
