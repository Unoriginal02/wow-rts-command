#include "RtsCommandMode.h"

#include "RtsBotApi.h"   // la unica puerta a mod-playerbots
#include "RtsOrders.h"

#include "Group.h"
#include "GroupReference.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include "MotionMaster.h"
#include "Pet.h"

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

    // Estaba DUPLICADA palabra por palabra con la de `RtsOrders.cpp`. Ahora las
    // dos son un alias de `rts::bots::Resolve`, que es donde vive la unica
    // copia -- y donde vive tambien la comprobacion de que el bot esta en tu
    // grupo, que es lo unico que impide mandar los bots de otro.
    Player* ResolveBot(Player* master, std::string const& name)
    {
        return rts::bots::Resolve(master, name);
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
    void Suppress(Player* bot, Borrowed& b, bool on)
    {
        if (!rts::bots::Driven(bot))
            return;

        if (on)
        {
            b.wasPassiveCombat = rts::bots::Has(bot, "passive", rts::bots::COMBAT);
            b.wasPassiveIdle   = rts::bots::Has(bot, "passive", rts::bots::IDLE);
            rts::bots::Change(bot, "+passive", rts::bots::BOTH);
            return;
        }

        if (!b.wasPassiveIdle)
            rts::bots::Change(bot, "-passive", rts::bots::IDLE);
        if (!b.wasPassiveCombat)
            rts::bots::Change(bot, "-passive", rts::bots::COMBAT);
    }
}

// QUE LETRA LE TOCA A ESTE HECHIZO.
//
// EL ORDEN ES PARTE DE LA RESPUESTA y no es alfabetico: la primera que da
// cierto gana. Un Renovar es a la vez "positivo" y "necesita objetivo", y para
// la cola manda lo segundo; un totem tiene su categoria Y no pide objetivo, y
// manda que sea totem porque eso decide donde cae.
//
// Todo esto lo contesta `SpellInfo`, que el nucleo ya tiene cargado. Ni una
// sola lista de ids -- que es lo que este proyecto lleva seis etapas evitando,
// desde `nameplateMaxDistance`.
char rts::command::ClassifySpell(SpellInfo const* info)
{
    if (!info)
        return 'N';

    // P -- pasivo. No se ofrece siquiera; queda aqui por si algun camino lo
    // pregunta antes de filtrarlo.
    if (info->IsPassive())
        return 'P';

    // T -- totem u objeto colocado. Playerbots lo pone donde esta el bot.
    if (info->Totem[0] || info->Totem[1] || info->TotemCategory[0] || info->TotemCategory[1])
        return 'T';

    // D -- sobre un muerto. Resucitar. Va antes que A/H porque tambien pide
    // objetivo explicito y su segundo click es distinto (uno muerto).
    if (info->IsRequiringDeadTarget())
        return 'D';

    // G -- suelo o area con destino. NO NECESITA UN CLICK EN EL TERRENO:
    // `PlayerbotAI::CastSpell` hace `targets.SetDst(*target)` para estos, o sea
    // que apuntando a una unidad el hechizo cae DONDE ESTA esa unidad. Lluvia
    // de fuego sobre el lobo es "apunta al lobo". Ver `docs/HECHIZOS-COLA.md`.
    if (info->Targets & TARGET_FLAG_DEST_LOCATION)
        return 'G';

    // S -- solo sobre uno mismo. Se trata como "sin objetivo", que es lo que
    // el brief proponia.
    if (info->IsSelfCast())
        return 'S';

    // A / H -- con objetivo, amigo o enemigo.
    if (info->NeedsExplicitUnitTarget())
        return info->IsPositive() ? 'A' : 'H';

    // N -- lo demas: gritos, auras, posturas. Se manda y ya.
    return 'N';
}

std::vector<rts::command::BarSpell> rts::command::ActionBarSpells(Player* master,
                                                                  std::string const& botName)
{
    std::vector<BarSpell> out;

    Player* bot = ResolveBot(master, botName);
    if (!bot)
        return out;

    // LA MASCOTA, QUE ES LA TRAMPA CARA. `PlayerbotAI::CastSpell` empieza con
    // `Pet* pet = bot->GetPet(); if (pet && pet->HasSpell(spellId))`, y en ese
    // caso alterna el autocast de la mascota, susurra al maestro y **devuelve
    // true** -- sin lanzar nada. Un hueco con uno de esos seria un boton que no
    // hace nada, que reporta exito, y que ademas alterna entre dos estados
    // invisibles: en pantalla, "ese boton funciona a veces".
    //
    // Se filtra AQUI y no en el addon porque aqui es donde se sabe que mascota
    // tiene el bot ahora mismo.
    Pet* pet = bot->GetPet();

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

        if (pet && pet->HasSpell(spellId))
            continue;

        SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
        if (!info || info->IsPassive())
            continue;

        seen.insert(spellId);
        out.push_back(BarSpell{ spellId, ClassifySpell(info) });
    }

    return out;
}

bool rts::command::CastAs(Player* master, std::string const& botName, uint32 spellId,
                          ObjectGuid targetGuid, std::string* why, bool* retryable)
{
    // Por defecto NO se reintenta. Lo que se marca expresamente es lo que puede
    // salir bien mas tarde, que es lo prudente: una cola que reintenta lo que
    // nunca va a salir es ocho segundos de silencio en vez de un mensaje.
    if (retryable)
        *retryable = false;

    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return fail("ese no es uno de los tuyos");

    if (!bot->HasSpell(spellId))
        return fail("no conoce ese hechizo");

    // Named target, or whatever the bot already has. Casting a heal at nothing
    // should not silently become a self-cast, so an explicit target that cannot
    // be found is an error rather than a fallback.
    Unit* target = nullptr;
    if (targetGuid)
    {
        target = ObjectAccessor::GetUnit(*bot, targetGuid);
        if (!target)
            return fail("no ve ese objetivo");
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
        Suppress(bot, b, true);
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
    rts::bots::ForgetLastMove(bot);

    // Routed through the bot's own AI rather than Unit::CastSpell, so range,
    // facing, cooldowns and the global cooldown are all respected exactly as
    // they are when the bot casts for itself.
    if (!rts::bots::Cast(bot, spellId, target))
    {
        // AQUI ES DONDE SE ACABA LO QUE SE PUEDE SABER. `PlayerbotAI::CastSpell`
        // devuelve un bool y nada mas, asi que desde fuera no hay forma de
        // separar "el enfriamiento global, vuelve en un segundo" de "le faltan
        // reagentes y no van a aparecer".
        //
        // Se dice reintentable y **es el PLAZO quien descarta** lo que nunca iba
        // a salir. La alternativa -- reimplementar `Spell::CheckCast` aqui para
        // sacar el codigo de error -- seria escribir una segunda version de una
        // regla del juego que ya existe, que es como se acaba con dos respuestas
        // distintas a la misma pregunta.
        if (retryable)
            *retryable = true;
        return fail("no salio (alcance, enfriamiento, linea de vision o estaba en movimiento)");
    }

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
    if (!rts::bots::Driven(bot))
        return out;

    std::set<std::string> const supported = rts::bots::Supported(bot);
    if (supported.empty())
        return out;

    for (char const* name : kRoleNames)
    {
        if (!supported.count(name))
            continue;

        Role r;
        r.name = name;
        // `passive` cuenta como puesto si lo esta en CUALQUIERA de los dos
        // estados: es lo que hace que un bot dejado pasivo por `Hold` se vea
        // encendido en la fila y se pueda apagar desde ahi.
        r.active = rts::bots::Has(bot, name, rts::bots::COMBAT)
                || (std::string(name) == "passive"
                    && rts::bots::Has(bot, name, rts::bots::IDLE));
        out.push_back(r);
    }

    return out;
}

bool rts::command::SetRole(Player* master, std::string const& botName,
                           std::string const& role, bool on)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot) || role.empty())
        return false;

    if (!rts::bots::Supported(bot).count(role))
        return false;

    // The stance goes first and alone: drop the other two before adding this
    // one, so there is never an instant with two of them on.
    if (on && IsStance(role))
    {
        for (char const* other : kRoleNames)
        {
            if (role != other && IsStance(other)
                && rts::bots::Has(bot, other, rts::bots::COMBAT))
                rts::bots::Change(bot, std::string("-") + other, rts::bots::COMBAT);
        }
    }

    rts::bots::Change(bot, (on ? "+" : "-") + role, rts::bots::COMBAT);

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
        rts::bots::Change(bot, (on ? "+" : "-") + role, rts::bots::IDLE);

    // A role the player set by hand should survive the bot logging out with the
    // rest of its strategies. This is the same save the `co` chat command does
    // (ChangeStrategyAction.cpp:26) -- without it the setting lives only in
    // memory and comes back wrong after a restart, which reads as "the roles do
    // not stick" rather than as "they were never written down".
    rts::bots::Save(bot);
    return true;
}

// === persistent focus =======================================================

bool rts::command::SetFocus(Player* master, std::string const& botName,
                            ObjectGuid targetGuid, bool* hostile)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot) || !targetGuid)
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
    std::list<ObjectGuid> focus;
    focus.push_back(targetGuid);
    if (!rts::bots::SetFocusHeal(bot, focus))
        return false;

    rts::bots::Change(bot, "+focus heal targets", rts::bots::COMBAT);
    return true;
}

bool rts::command::ClearFocus(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::SetFocusHeal(bot, std::list<ObjectGuid>()))
        return false;

    rts::bots::Change(bot, "-focus heal targets", rts::bots::COMBAT);
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
            Suppress(bot, it->second, false);
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
                Suppress(bot, b, false);
        }
        it = g_borrowed.erase(it);
    }
}
