#include "RtsCommandMode.h"

#include "RtsOrders.h"

#include "Group.h"
#include "GroupReference.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include "AiObjectContext.h"
#include "LastMovementValue.h"
#include "MotionMaster.h"
#include "PlayerbotAI.h"
#include "PlayerbotMgr.h"
#include "PlayerbotRepository.h"

#include <algorithm>
#include <list>
#include <set>
#include <unordered_map>
#include <unordered_set>

namespace
{
    // How long after your last cast the bot goes back to its own devices.
    // Deliberately measured from the CAST, not from the click: a 2.5s heal must
    // not be cut off by its own timeout.
    constexpr uint32 kIdleReleaseMs = 3000;

    struct Borrowed
    {
        ObjectGuid bot;
        uint32 sinceLastCast = 0;
        bool suppressed = false;
        // COMO ESTABA ANTES DE QUE LO TOCARAMOS. Ver `Suppress`: devolver el bot
        // "a no pasivo" no es devolverlo a como estaba si el jugador lo habia
        // puesto en Esperar a proposito.
        bool wasPassiveCombat = false;
        bool wasPassiveIdle = false;
    };

    // master guid -> the bot they are currently casting through.
    std::unordered_map<ObjectGuid, Borrowed> g_borrowed;

    Player* ResolveBot(Player* master, std::string const& name)
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

    PlayerbotAI* AiFor(Player* bot)
    {
        return bot ? PlayerbotsMgr::instance().GetPlayerbotAI(bot) : nullptr;
    }

    // TOMAR PRESTADO UN BOT PARA LANZAR POR EL, y devolverlo COMO ESTABA.
    //
    // Un `-passive` a secas al soltarlo no es una restauracion, es una
    // suposicion: da por hecho que el bot no estaba pasivo antes. Si el jugador
    // le habia puesto el rol "Esperar" a mano, usar una de sus habilidades se lo
    // quitaba tres segundos despues -- sin decir nada, y con el boton de la fila
    // apagandose solo. Una orden explicita deshecha por un efecto secundario de
    // otra es de las peores porque el jugador no relaciona las dos cosas.
    //
    // Es la misma regla dura que `Camera.lua` aplica a sus CVars y `Chrome.lua`
    // a los frames de Blizzard: capturar antes del primer cambio y devolver a lo
    // capturado, nunca a un valor por defecto.
    void Suppress(PlayerbotAI* ai, Borrowed& b, bool on)
    {
        if (!ai)
            return;

        if (on)
        {
            b.wasPassiveCombat = ai->HasStrategy("passive", BOT_STATE_COMBAT);
            b.wasPassiveIdle   = ai->HasStrategy("passive", BOT_STATE_NON_COMBAT);
            ai->ChangeStrategy("+passive", BOT_STATE_NON_COMBAT);
            ai->ChangeStrategy("+passive", BOT_STATE_COMBAT);
            return;
        }

        if (!b.wasPassiveIdle)
            ai->ChangeStrategy("-passive", BOT_STATE_NON_COMBAT);
        if (!b.wasPassiveCombat)
            ai->ChangeStrategy("-passive", BOT_STATE_COMBAT);
    }
}

std::vector<uint32> rts::command::ActionBarSpells(Player* master, std::string const& botName)
{
    std::vector<uint32> out;

    Player* bot = ResolveBot(master, botName);
    if (!bot)
        return out;

    std::unordered_set<uint32> seen;

    for (uint8 slot = 0; slot < MAX_ACTION_BUTTONS; ++slot)
    {
        ActionButton const* button = bot->GetActionButton(slot);
        if (!button || button->GetType() != ACTION_BUTTON_SPELL)
            continue;

        uint32 const spellId = button->GetAction();
        if (!spellId || seen.count(spellId))
            continue;

        // A bar can hold spells the character has since unlearned, or ranks it
        // has outgrown. Sending those would give you buttons that silently fail.
        if (!bot->HasSpell(spellId))
            continue;

        SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
        if (!info || info->IsPassive())
            continue;

        seen.insert(spellId);
        out.push_back(spellId);
    }

    return out;
}

bool rts::command::CastAs(Player* master, std::string const& botName, uint32 spellId,
                          ObjectGuid targetGuid, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return fail("that unit is not one of yours");

    if (!bot->HasSpell(spellId))
        return fail("it does not know that spell");

    // Named target, or whatever the bot already has. Casting a heal at nothing
    // should not silently become a self-cast, so an explicit target that cannot
    // be found is an error rather than a fallback.
    Unit* target = nullptr;
    if (targetGuid)
    {
        target = ObjectAccessor::GetUnit(*bot, targetGuid);
        if (!target)
            return fail("cannot see that target");
    }
    else if (ObjectGuid const own = bot->GetTarget())
    {
        target = ObjectAccessor::GetUnit(*bot, own);
    }

    if (!target)
        target = bot;   // no target at all: a self-cast is the sane default

    // NOW take the wheel -- on the cast, not on selection. Until you actually
    // use a bot, it carries on doing whatever it was doing.
    Borrowed& b = g_borrowed[master->GetGUID()];
    if (b.bot != bot->GetGUID())
    {
        // Switched to a different bot: give the previous one back first.
        if (b.bot)
            Release(master, "");
        b.bot = bot->GetGUID();
        b.suppressed = false;
    }
    if (!b.suppressed)
    {
        Suppress(ai, b, true);
        b.suppressed = true;
    }
    b.sinceLastCast = 0;

    // QUIETO ANTES DE LANZAR, Y ESA LINEA ES EL ARREGLO DE PRUEBAS-18 E1/E3.
    //
    // Reportado como "intenta tirar el hechizo y la animacion se cancela
    // enseguida". Lo unico que corta un lanzamiento sin dano de por medio es el
    // MOVIMIENTO, y el bot se estaba moviendo por dos motivos a la vez:
    //
    //   * `PlayerbotAI::CastSpell` se rinde el solo si el bot esta andando y el
    //     hechizo tiene tiempo de lanzamiento (PlayerbotAI.cpp, `bot->isMoving()
    //     && spell->GetCastTime()`), y entonces ni empieza.
    //   * y si empieza, `passive` -- que es lo que `Suppress` acaba de poner --
    //     NO apaga el seguimiento: `PassiveMultiplier` lleva "follow" en su
    //     lista de partes permitidas a proposito. Asi que un bot que estuviera
    //     recolocandose para seguirte se mueve DURANTE el lanzamiento y lo
    //     interrumpe. Es exactamente el sintoma reportado.
    //
    // Pararlo aqui cuesta tres llamadas y no le quita nada: la orden que estaba
    // ejecutando era "seguir", que se rehace sola en cuanto se le devuelve el
    // mando. Limpiar `last movement` es lo mismo que hace `MoveBot`, y por el
    // mismo motivo -- sin eso el motor bloquea el siguiente movimiento durante
    // lo que durase el viaje anterior.
    bot->StopMoving();
    bot->GetMotionMaster()->Clear();
    if (AiObjectContext* ctx = ai->GetAiObjectContext())
        ctx->GetValue<LastMovement&>("last movement")->Get().clear();

    // Routed through the bot's own AI rather than Unit::CastSpell, so range,
    // facing, cooldowns and the global cooldown are all respected exactly as
    // they are when the bot casts for itself.
    if (!ai->CastSpell(spellId, target))
        return fail("no salio (alcance, enfriamiento, linea de vision o estaba en movimiento)");

    return true;
}

std::string rts::command::CurrentTargetName(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!bot)
        return "";

    // AttackAction.cpp:176 does bot->SetSelection(target), so this field is a
    // reliable read of what the bot is pointed at -- which for a healer is
    // usually who it is healing, and for anyone else who it is hitting.
    ObjectGuid const guid = bot->GetTarget();
    if (!guid)
        return "";

    Unit* target = ObjectAccessor::GetUnit(*bot, guid);
    return target ? target->GetName() : "";
}

std::vector<rts::command::Engaged> rts::command::GroupTargets(Player* master)
{
    std::vector<Engaged> out;
    if (!master)
        return out;

    Group* group = master->GetGroup();
    if (!group)
        return out;

    auto add = [&out, master](Unit* unit)
    {
        if (!unit || !unit->IsInWorld() || !unit->IsAlive())
            return;

        for (Engaged& e : out)
        {
            if (e.guid == unit->GetGUID())
            {
                ++e.count;
                return;
            }
        }

        Engaged e;
        e.guid = unit->GetGUID();
        e.name = unit->GetName();
        e.count = 1;
        e.hostile = master->IsValidAttackTarget(unit);
        e.isPlayer = unit->IsPlayer();
        e.healthPct = unit->GetMaxHealth()
            ? static_cast<uint8>((unit->GetHealth() * 100) / unit->GetMaxHealth())
            : 0;
        out.push_back(e);
    };

    for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
    {
        Player* member = ref->GetSource();
        if (!member || !member->IsInWorld())
            continue;

        // A unit pointed at ITSELF is idle, not engaged -- several playerbots
        // actions park the selection on the bot. Listing that would fill the
        // panel with your own party staring at themselves.
        ObjectGuid const guid = member->GetTarget();
        if (!guid || guid == member->GetGUID())
            continue;

        add(ObjectAccessor::GetUnit(*member, guid));
    }

    return out;
}

bool rts::command::Aim(Player* master, std::string const& botName, ObjectGuid targetGuid)
{
    Player* bot = ResolveBot(master, botName);
    if (!bot || !targetGuid)
        return false;

    Unit* target = ObjectAccessor::GetUnit(*bot, targetGuid);
    if (!target || !target->IsInWorld())
        return false;

    bot->SetSelection(targetGuid);
    return true;
}

// === roles ==================================================================

namespace
{
    // The five that mean something as a role. Every one of them is a strategy
    // name taken from mod-playerbots' own source, not invented here:
    //
    //   tank/dps/heal  the class combat stances (PaladinAiObjectContext.cpp:93)
    //   cc             crowd control (DruidAiObjectContext.cpp:34)
    //   passive        stand down -- the same one Suppress() uses above
    //
    // The list being a constant is fine BECAUSE nothing is assumed from it:
    // each name is checked against the bot's own supported set before it is
    // offered, so a class that lacks one simply does not get the button. A
    // sixth can be added here and it appears wherever it exists.
    char const* const kRoleNames[] = { "tank", "dps", "heal", "cc", "passive" };

    // Turning one of these on turns the other two off. They are the class's
    // combat stance -- bear or cat, holy or ret -- and having two at once is
    // not a configuration, it is a bug you would spend a fight diagnosing.
    bool IsStance(std::string const& name)
    {
        return name == "tank" || name == "dps" || name == "heal";
    }
}

std::vector<rts::command::Role> rts::command::Roles(Player* master, std::string const& botName)
{
    std::vector<Role> out;

    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return out;

    AiObjectContext* context = ai->GetAiObjectContext();
    if (!context)
        return out;

    std::set<std::string> const supported = context->GetSupportedStrategies();

    for (char const* name : kRoleNames)
    {
        if (!supported.count(name))
            continue;

        Role r;
        r.name = name;
        // `passive` cuenta como puesto si lo esta en CUALQUIERA de los dos
        // estados: es lo que hace que un bot dejado pasivo por `Hold` se vea
        // encendido en la fila y se pueda apagar desde ahi.
        r.active = ai->HasStrategy(name, BOT_STATE_COMBAT)
                || (std::string(name) == "passive" && ai->HasStrategy(name, BOT_STATE_NON_COMBAT));
        out.push_back(r);
    }

    return out;
}

bool rts::command::SetRole(Player* master, std::string const& botName,
                           std::string const& role, bool on)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai || role.empty())
        return false;

    AiObjectContext* context = ai->GetAiObjectContext();
    if (!context || !context->GetSupportedStrategies().count(role))
        return false;

    // The stance goes first and alone: drop the other two before adding this
    // one, so there is never an instant with two of them on.
    if (on && IsStance(role))
    {
        for (char const* other : kRoleNames)
        {
            if (role != other && IsStance(other) && ai->HasStrategy(other, BOT_STATE_COMBAT))
                ai->ChangeStrategy(std::string("-") + other, BOT_STATE_COMBAT);
        }
    }

    ai->ChangeStrategy((on ? "+" : "-") + role, BOT_STATE_COMBAT);

    // `passive` VA EN LOS DOS ESTADOS, y las demas no. Las tres posturas
    // (tank/dps/heal) solo significan algo en combate, pero "esperar" significa
    // "no hagas nada", y un bot con `passive` puesto solo en el estado de
    // combate sigue yendo a por cosas fuera de el.
    //
    // Y la mitad que importa es la de APAGARLO. Dos sitios ponen `+passive` en
    // LOS DOS estados -- `Suppress` (tomar prestado el bot para lanzar por el) y
    // `PossessBot` -- y los dos lo quitan de los dos al soltar. Pero si ese
    // soltar no llega a correr (el bot se va del grupo, el maestro se desconecta,
    // el jugador cambia de bot), el `+passive` del estado NO combate se queda.
    //
    // Con un `-passive` que solo tocara el de combate, ese bot quedaba pasivo
    // fuera de combate PARA SIEMPRE: no reacciona a nada, y la fila de roles leia
    // el estado de combate, lo veia apagado, y no ofrecia nada que pulsar. Se lee
    // como "los bots ya no atacan" y no hay ningun boton que lo explique.
    //
    // NOTA, porque estuvo mal escrito aqui una version: `Hold` NO pone passive.
    // Manda el `stay` de playerbots, y el camino de `stay` de este modulo
    // (`MoveBot`) hace justo lo contrario -- `-passive` en los dos estados.
    if (role == "passive")
        ai->ChangeStrategy((on ? "+" : "-") + role, BOT_STATE_NON_COMBAT);

    // A role the player set by hand should survive the bot logging out with the
    // rest of its strategies. This is the same save the `co` chat command does
    // (ChangeStrategyAction.cpp:26) -- without it the setting lives only in
    // memory and comes back wrong after a restart, which reads as "the roles do
    // not stick" rather than as "they were never written down".
    PlayerbotRepository::instance().Save(ai);
    return true;
}

// === persistent focus =======================================================

bool rts::command::SetFocus(Player* master, std::string const& botName,
                            ObjectGuid targetGuid, bool* hostile)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai || !targetGuid)
        return false;

    Unit* target = ObjectAccessor::GetUnit(*bot, targetGuid);
    if (!target || !target->IsInWorld())
        return false;

    bool const enemy = bot->IsValidAttackTarget(target);
    if (hostile)
        *hostile = enemy;

    if (enemy)
    {
        // The bot's own attack action, which is sticky because the AI keeps
        // working on what it is attacking. Nothing to re-assert.
        return rts::orders::AttackBot(master, botName, targetGuid);
    }

    // Friendly: one name on the focus-heal list, and the strategy that reads it.
    //
    // ONE, NOT APPENDED. "Focus the tank" means the tank and not "the tank as
    // well as whoever I picked ten minutes ago" -- a list that only ever grows
    // would quietly stop meaning anything after the third click, and there is
    // no way to see it from the client.
    AiObjectContext* context = ai->GetAiObjectContext();
    if (!context)
        return false;

    std::list<ObjectGuid> focus;
    focus.push_back(targetGuid);
    context->GetValue<std::list<ObjectGuid>>("focus heal targets")->Set(focus);
    ai->ChangeStrategy("+focus heal targets", BOT_STATE_COMBAT);
    return true;
}

bool rts::command::ClearFocus(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    AiObjectContext* context = ai->GetAiObjectContext();
    if (!context)
        return false;

    context->GetValue<std::list<ObjectGuid>>("focus heal targets")->Set(std::list<ObjectGuid>());
    ai->ChangeStrategy("-focus heal targets", BOT_STATE_COMBAT);
    return true;
}

void rts::command::Release(Player* master, std::string const& /*botName*/)
{
    if (!master)
        return;

    auto it = g_borrowed.find(master->GetGUID());
    if (it == g_borrowed.end())
        return;

    if (it->second.suppressed)
    {
        if (Player* bot = ObjectAccessor::FindPlayer(it->second.bot))
            Suppress(AiFor(bot), it->second, false);
    }

    g_borrowed.erase(it);
}

void rts::command::ReleaseAll(Player* master)
{
    Release(master, "");
}

void rts::command::Update(uint32 diff)
{
    for (auto it = g_borrowed.begin(); it != g_borrowed.end();)
    {
        Borrowed& b = it->second;
        b.sinceLastCast += diff;

        if (b.sinceLastCast < kIdleReleaseMs)
        {
            ++it;
            continue;
        }

        if (b.suppressed)
        {
            if (Player* bot = ObjectAccessor::FindPlayer(b.bot))
                Suppress(AiFor(bot), b, false);
        }
        it = g_borrowed.erase(it);
    }
}
