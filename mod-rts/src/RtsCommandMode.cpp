#include "RtsCommandMode.h"

#include "RtsBotApi.h"   // la unica puerta a mod-playerbots
#include "RtsOrders.h"

#include "DBCStores.h"
#include "Group.h"
#include "GroupReference.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SharedDefines.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include "MotionMaster.h"
#include "Pet.h"

#include <algorithm>
#include <cstring>
#include <list>
#include <set>
#include <unordered_map>
#include <unordered_set>
#include <vector>

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

// ESTA EN EL LIBRO DE HECHIZOS, O SOLO EN EL MAPA?
//
// `GetSpellMap()` trae bastante mas de lo que el cliente dibuja en el libro. En
// un personaje de nivel 3 salian, junto a Punicion y Sanacion inferior:
// "Duelo", "Objetivo sin honor", "Cerrando" (tres veces), "Activar
// especializacion principal" y "Atacar automaticamente". Reportado, con razon,
// como *"los hechizos disponibles son raros de cojones"*.
//
// **No se pueden reconocer por el nombre ni por los atributos**, y se comprobo
// antes de escribir nada: los seis tienen entrada en `SkillLineAbility` igual
// que los buenos, y el bit 0x80 de "no mostrar" lo llevan unos si y otros no
// (Objetivo sin honor no lo lleva). Un filtro por cualquiera de esas dos cosas
// habria dejado basura dentro y se habria descubierto en juego.
//
// LO QUE SI LOS SEPARA, Y LO DICE CON TODAS LAS LETRAS: los seis cuelgan de la
// linea de habilidad **183, "GENERIC (DND)"**, cuya categoria es la 12 --
// llamada en `SkillLineCategory.dbc` literalmente **"Not Displayed"**. Los de
// verdad cuelgan de una linea de clase (Holy, Discipline, Fury) o de una racial
// (Night Elf Racial). Es la regla de siempre de este proyecto: no inventar una
// constante, leer la que el cliente ya tiene puesta -- y la categoria 12 hasta
// tiene nombre en el nucleo, `SKILL_CATEGORY_GENERIC`.
//
// Verificado leyendo `dist\data\dbc` con un guion, no deducido: la categoria 12
// tiene UNA sola linea (la 183) y ninguno de los hechizos buenos pasa por ella.
//
// Un hechizo que ademas cuelgue de una linea normal se queda: se descarta solo
// si TODAS sus lineas son de la categoria oculta. Y sin ninguna entrada tampoco
// esta en el libro -- el cliente no tendria pestana donde ponerlo.
namespace
{
    bool InSpellBook(uint32 spellId)
    {
        SkillLineAbilityMapBounds const bounds =
            sSpellMgr->GetSkillLineAbilityMapBounds(spellId);

        for (auto it = bounds.first; it != bounds.second; ++it)
        {
            SkillLineEntry const* line = sSkillLineStore.LookupEntry(it->second->SkillLine);
            if (!line || line->categoryId != SKILL_CATEGORY_GENERIC)
                return true;
        }

        // Ni una linea normal, o ninguna linea: el cliente no tendria donde
        // ponerlo, asi que no esta en el libro.
        return false;
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

// DE QUIEN SON LOS HECHIZOS QUE SE PIDEN.
//
// `ResolveBot` rechaza a proposito que te resuelvas a ti mismo -- lo hace para
// que nadie se mande ordenes de bot a su propio personaje, y ahi esta bien.
// Pero el CATALOGO de hechizos no es una orden: es una lectura, y tu personaje
// tiene uno igual que los demas.
//
// ESO ERA EL "NEFERITE NO TIENE SPELLS" DE `PRUEBAS-23` C2. Con tu heroe de
// primario, `BARS` resolvia a nullptr y contestaba la lista vacia; el addon
// caia a leer TU barra con `GetActionInfo`, cuyo segundo valor puede ser el
// indice del libro en vez del id -- y el filtro que protege de eso (contrastar
// contra el icono dibujado) se lleva por delante la lista entera cuando pasa.
// Dos caminos distintos para la misma pregunta, y el tuyo era el malo.
static Player* SpellSubject(Player* master, std::string const& name)
{
    if (!master)
        return nullptr;
    if (name.empty() || name == master->GetName())
        return master;
    return rts::bots::Resolve(master, name);
}

std::vector<rts::command::SpellCd> rts::command::Cooldowns(Player* master,
                                                           std::string const& botName,
                                                           std::vector<uint32> const& ids)
{
    std::vector<SpellCd> out;

    Player* bot = SpellSubject(master, botName);
    if (!bot)
        return out;

    for (uint32 id : ids)
    {
        if (!id)
            continue;

        uint32 const remain = bot->GetSpellCooldownDelay(id);
        if (!remain)
            continue;       // no enfria: no se manda, que es la mayoria

        // EL TOTAL SALE DEL HECHIZO Y NO DEL NUCLEO, porque el nucleo no lo
        // guarda: `m_spellCooldowns` solo apunta CUANDO ACABA. De las dos que
        // trae el hechizo se coge la mayor -- un hechizo con categoria (las
        // pociones, los sellos) tiene la suya en `CategoryRecoveryTime` y la
        // propia a cero, y quedarse con la propia dibujaria una rueda de
        // duracion cero sobre algo que si esta enfriando.
        uint32 total = 0;
        if (SpellInfo const* info = sSpellMgr->GetSpellInfo(id))
            total = std::max(info->RecoveryTime, info->CategoryRecoveryTime);

        // Y SI EL HECHIZO NO DECLARA NINGUNA, lo que queda ES el total. Pasa con
        // los enfriamientos que pone un aura o un efecto, y sin esto la rueda
        // saldria con duracion cero -- o sea, no saldria. Mejor una rueda que
        // empieza llena y baja bien que ninguna.
        if (total < remain)
            total = remain;

        out.push_back({ id, remain, total });
    }

    return out;
}

namespace
{
    // EL ENFRIAMIENTO BASE DE UN HECHIZO. Los dos campos cuentan y se coge el
    // mayor: hay hechizos cuyo tiempo esta en el de su CATEGORIA y no en el
    // suyo (las pociones son el ejemplo de manual), y mirar solo `RecoveryTime`
    // los daria como si no enfriaran.
    uint32 BaseCooldownMs(SpellInfo const* info)
    {
        if (!info)
            return 0;
        return std::max(info->RecoveryTime, info->CategoryRecoveryTime);
    }
}

std::vector<rts::command::BarSpell> rts::command::ActionBarSpells(Player* master,
                                                                  std::string const& botName)
{
    std::vector<BarSpell> out;

    Player* bot = SpellSubject(master, botName);
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
    std::vector<BarSpell> extra;   // lo que sabe y no tiene en la barra

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
        out.push_back(BarSpell{ spellId, ClassifySpell(info), BaseCooldownMs(info) });
    }

    // Y DETRAS, TODO LO DEMAS QUE SEPA. Es la respuesta a la pregunta de
    // `PRUEBAS-23` C2 -- *"¿son los de mi barra o los de playerbot?"*.
    //
    // Playerbots NO TIENE una lista de hechizos suya que consultar: su IA elige
    // por accion, en el momento, y no guarda ningun catalogo. Asi que "los de
    // playerbot" no existe como fuente. Lo que si existe y ademas es lo que el
    // jugador queria -- una lista que **se actualiza sola segun el personaje
    // sube** -- es el libro de hechizos del propio personaje, que el nucleo
    // mantiene y que aqui se lee entero.
    //
    // LA BARRA VA PRIMERO Y SE QUEDA, no se sustituye: es la lista CURADA, en el
    // orden en que el jugador la coloco, y por eso sigue siendo la que llena los
    // huecos por defecto. Lo que se anade detras es el resto, para que se pueda
    // elegir sin tener que entrar con el personaje a recolocarle la barra.
    //
    // `Active` HACE EL TRABAJO DE FILTRAR RANGOS y lo dice el propio nucleo en
    // su comentario (`Player.h:130`): *"lower rank of a spell are not useable,
    // but learnt"*. O sea que preguntando por `Active` sale el rango bueno y
    // nada mas, sin recorrer cadenas de hechizos a mano -- que seria escribir
    // una segunda version de una regla que el nucleo ya tiene.
    for (auto const& kv : bot->GetSpellMap())
    {
        uint32 const spellId = kv.first;
        PlayerSpell const* ps = kv.second;
        if (!ps || ps->State == PLAYERSPELL_REMOVED || !ps->Active)
            continue;
        if (seen.count(spellId))
            continue;

        SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
        if (!info || info->IsPassive())
            continue;

        // Sin nombre no hay boton que ensenar, y hay entradas internas que no
        // lo tienen.
        if (!info->SpellName[0] || !*info->SpellName[0])
            continue;

        // Un oficio abre la ventana de fabricar, y un idioma no hace nada
        // visible. Los dos saldrian como botones que no responden.
        uint32 const eff = info->Effects[0].Effect;
        if (eff == SPELL_EFFECT_TRADE_SKILL || eff == SPELL_EFFECT_LANGUAGE)
            continue;

        // Y SOLO LO QUE EL LIBRO ENSENARIA. Ver `InSpellBook` arriba: es lo que
        // quita el "Duelo", el "Objetivo sin honor" y los tres "Cerrando".
        //
        // Se aplica AQUI y no a la barra de acciones de arriba a proposito: esa
        // es la lista CURADA por el jugador, y si el puso ahi "Atacar
        // automaticamente" es porque lo quiere. Filtrar lo que uno mismo
        // coloco seria decidir por el.
        if (!InSpellBook(spellId))
            continue;

        if (pet && pet->HasSpell(spellId))
            continue;

        seen.insert(spellId);
        extra.push_back(BarSpell{ spellId, ClassifySpell(info), BaseCooldownMs(info) });
    }

    // Por nombre, que es como se busca en una lista larga. La barra de arriba
    // conserva SU orden, que es el que el jugador eligio.
    std::sort(extra.begin(), extra.end(), [](BarSpell const& a, BarSpell const& b)
    {
        SpellInfo const* ia = sSpellMgr->GetSpellInfo(a.id);
        SpellInfo const* ib = sSpellMgr->GetSpellInfo(b.id);
        char const* na = (ia && ia->SpellName[0]) ? ia->SpellName[0] : "";
        char const* nb = (ib && ib->SpellName[0]) ? ib->SpellName[0] : "";
        return std::strcmp(na, nb) < 0;
    });

    out.insert(out.end(), extra.begin(), extra.end());
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
    //
    // SOLTAR EL ANTERIOR VA **ANTES** DE COGER LA REFERENCIA, Y ESE ORDEN ERA EL
    // CRASH DEL SERVIDOR DEL 2026-09-05.
    //
    // `Release` hace `g_borrowed.erase(it)`. La version anterior tenia cogida
    // una referencia a ESE nodo (`Borrowed& b = g_borrowed[...]`) y la seguia
    // usando despues: cuatro escrituras -- el guid, `suppressed`, los dos
    // `wasPassive*` de `Suppress` y `sinceLastCast` -- sobre memoria ya
    // liberada. O sea que lanzar un hechizo por un bot DISTINTO del anterior
    // pisaba el monton, y el servidor se caia mas tarde, en cualquier sitio.
    //
    // Los dos volcados lo dicen igual: `ACCESS_VIOLATION` dentro de
    // `std::string::_Tidy_deallocate` (RVA 0x14B462), con la capacidad a
    // 0x100000000 y el puntero valiendo texto suelto ("log", "guild de") -- la
    // firma de un `std::string` que nadie corrompio, sino cuyo bloque se reuso
    // despues de que alguien escribiera en el ya liberado. El sintoma no tiene
    // NADA que ver con la causa, que es lo caro de esta clase de fallo: se
    // reporto como "pulso hechizos un rato y se cuelga".
    //
    // La regla que lo evita, y que este proyecto ya paga en otros sitios: una
    // referencia a un nodo de un contenedor no sobrevive a una llamada que
    // pueda tocar ese contenedor. Se suelta primero, se coge despues.
    {
        auto prev = g_borrowed.find(master->GetGUID());
        if (prev != g_borrowed.end() && prev->second.bot && prev->second.bot != bot->GetGUID())
            Release(master, "");   // invalida `prev` a proposito
    }

    Borrowed& b = g_borrowed[master->GetGUID()];
    if (b.bot != bot->GetGUID())
    {
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

    // Y LO QUE TUVIERA EN MENTE, CANCELADO: un hechizo que mandas tu manda
    // sobre lo que el bot estuviera rumiando, igual que las ordenes del raton.
    // Va justo antes del lanzamiento y no antes de las comprobaciones, para no
    // interrumpirle nada si la orden iba a fallar de todas formas.
    rts::bots::Preempt(bot);

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

    // Y AHORA QUE SE CALLE SU IA HASTA QUE TERMINE, que es la otra mitad del
    // arreglo de arriba y la que faltaba (`PRUEBAS-23` C6).
    //
    // `StopMoving` corta el paso que lleva EN ESTE INSTANTE. No puede impedir
    // que su motor le mande otro medio segundo despues -- y se lo manda, porque
    // `passive` permite "follow" a proposito. El resultado es el sintoma
    // reportado al pie de la letra: la animacion arranca y se corta sola.
    //
    // El plazo es el tiempo de lanzamiento mas un margen. Un instantaneo no
    // necesita nada, asi que no se le calla: callar a un bot que no lo necesita
    // es quitarle medio segundo de pelea por nada.
    if (SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId))
    {
        uint32 const cast = info->CalcCastTime(bot);
        if (cast > 0)
            rts::bots::HoldAi(bot, std::min<uint32>(cast + 300, 10000));
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
    // A ROLE IS A WORD FOR THE PLAYER. A STRATEGY IS A WORD FOR PLAYERBOTS.
    // THEY ARE ONLY THE SAME WORD FOR SOME CLASSES, and this file used to
    // assume they always were -- which is why a level 9 priest read as having
    // no role at all while she was standing there healing.
    //
    // Every class context registers its own combat vocabulary and
    // `AiFactory::AddDefaultCombatStrategies` switches on the spec tab to pick
    // one of them. Only the paladin uses the three generic words throughout:
    //
    //     warrior   prot -> tank      arms -> arms        fury -> fury
    //     paladin   prot -> tank      holy -> heal        ret  -> dps
    //     priest    disc -> heal      holy -> holy heal   shadow -> see below
    //     druid     feral-> bear/cat  balance -> balance  resto -> resto
    //     shaman    resto-> resto     ele  -> ele         enh  -> enh
    //     dk        blood-> blood     frost-> frost       unholy -> unholy
    //     mage      arcane/fire/frostfire/frost      hunter   bm/mm/surv
    //     rogue     melee/dps                        warlock  affli/demo/destro
    //
    // AND THE STORED NAME IS NOT ALWAYS THE NAME YOU ASK FOR. Engine::addStrategy
    // keys the engine by `strategy->getName()` (Engine.cpp:353-364), while
    // HasStrategy and removeStrategy are exact lookups on that key. So asking a
    // priest for `+dps` builds ShadowPriestStrategy, which calls itself
    // `shadow` -- and `HasStrategy("dps")` is then FALSE on a bot that is
    // running the dps strategy you just switched on. The same aliasing is in
    // the shaman (`dps` -> `enh`, `heal` -> `resto`, `caster` -> `ele`), the
    // druid (`dps` -> `cat`, `tank` -> `bear`) and the dk (`tank` -> `blood`).
    //
    // So each role carries EVERY name it can go by -- the ones you can ask for
    // and the ones it ends up stored under -- and the three uses of that list
    // are three different questions:
    //
    //     CAN IT      any of the names is in GetSupportedStrategies()
    //     IS IT ON    any of the names answers HasStrategy (the stored one)
    //     TURN IT ON  the first SUPPORTED name, which is an alias by definition
    //
    // The order inside a role only matters for the last one, and it puts the
    // generic word first so that a class which has it uses it.
    struct RoleDef
    {
        char const* role;
        std::vector<char const*> names;
    };

    std::vector<RoleDef> const& RoleTable()
    {
        static std::vector<RoleDef> const table = {
            { "tank", { "tank", "bear", "blood" } },
            { "dps",  { "dps", "arms", "fury", "shadow", "holy dps",
                        "cat", "balance", "melee", "caster", "ele", "enh",
                        "bm", "mm", "surv", "arcane", "fire", "frostfire",
                        "frost", "affli", "demo", "destro", "unholy" } },
            { "heal", { "heal", "holy heal", "resto" } },
            // These two are exact: one name each, registered generically, and
            // they mean the same thing for every class.
            { "cc",      { "cc" } },
            { "passive", { "passive" } },
        };
        return table;
    }

    RoleDef const* FindRole(std::string const& role)
    {
        for (RoleDef const& d : RoleTable())
            if (role == d.role)
                return &d;
        return nullptr;
    }

    // Turning one of these on turns the other two off. They are what the bot
    // does in a fight -- hold the line, deal damage, keep people up -- and
    // having two at once is not a configuration, it is a bug you would spend a
    // fight diagnosing.
    bool IsStance(std::string const& name)
    {
        return name == "tank" || name == "dps" || name == "heal";
    }

    // WHICH NAME OF A ROLE THIS BOT IS ACTUALLY RUNNING, or empty. It is also
    // the only name that can switch it OFF: removeStrategy is an exact lookup
    // on the stored name, so `-dps` on a priest running `shadow` removes
    // nothing at all and leaves her doing two jobs at once.
    std::string RunningName(Player* bot, RoleDef const& def)
    {
        for (char const* n : def.names)
            if (rts::bots::Has(bot, n, rts::bots::COMBAT))
                return n;
        return std::string();
    }

    // WHAT WE TOOK OFF, SO THAT IT CAN GO BACK ON AS IT WAS. bot -> role -> name.
    //
    // Without it, cycling away from a holy priest and back turns her into a
    // discipline one: both are `heal`, and "the first supported name" cannot
    // tell them apart. It is the capture-and-restore rule `Suppress` above
    // already follows with `passive`, for the same reason -- an explicit
    // setting undone as a side effect of another is the kind of change nobody
    // connects back to what they pressed.
    //
    // Session-lived and tiny: one entry per bot actually cycled. It is not
    // persistence -- playerbots saves the strategies themselves.
    std::unordered_map<ObjectGuid, std::unordered_map<std::string, std::string>> g_lastOf;
}

// TU PROPIO PERSONAJE CUENTA AQUI, y es la excepcion de `SpellSubject` otra vez.
//
// `ResolveBot` rechaza a proposito que te resuelvas a ti mismo, para que nadie
// se mande ordenes de bot a su propio personaje -- y ahi esta bien. Pero un ROL
// no es una orden que se le da a otro: es leer y escribir el motor de combate de
// quien lo tenga, y con el selfbot puesto (`.playerbots bot self`) el tuyo tiene
// uno igual que los demas. Rechazarlo era decir "tu heroe no puede tener rol"
// cuando lo que pasaba es que no se le preguntaba.
//
// SIN SELFBOT NO CAMBIA NADA: `Driven` es falso dos lineas mas abajo y la
// respuesta sigue siendo la lista vacia.
static Player* RoleSubject(Player* master, std::string const& name)
{
    if (!master)
        return nullptr;
    if (name.empty() || name == master->GetName())
        return master;
    return rts::bots::Resolve(master, name);
}

std::vector<rts::command::Role> rts::command::Roles(Player* master, std::string const& botName)
{
    std::vector<Role> out;

    Player* bot = RoleSubject(master, botName);
    if (!rts::bots::Driven(bot))
        return out;

    std::set<std::string> const supported = rts::bots::Supported(bot);
    if (supported.empty())
        return out;

    for (RoleDef const& def : RoleTable())
    {
        bool can = false;
        for (char const* n : def.names)
            if (supported.count(n))
            {
                can = true;
                break;
            }

        std::string const running = RunningName(bot, def);

        // `passive` cuenta como puesto si lo esta en CUALQUIERA de los dos
        // estados: es lo que hace que un bot dejado pasivo por `Hold` se vea
        // encendido en la fila y se pueda apagar desde ahi.
        bool on = !running.empty();
        if (!on && std::string(def.role) == "passive")
            on = rts::bots::Has(bot, "passive", rts::bots::IDLE);

        // ON BUT NOT LISTED IS STILL ON, and it gets reported. The two answers
        // come from different places -- what the class can build against what
        // the engine is holding right now -- and dropping a role the bot is
        // visibly running because the other list did not mention it is the
        // exact failure this whole table exists to undo.
        if (!can && !on)
            continue;

        Role r;
        r.name = def.role;
        r.active = on;
        out.push_back(r);
    }

    return out;
}

std::string rts::command::ActiveRole(Player* bot)
{
    if (!bot)
        return std::string();

    for (RoleDef const& def : RoleTable())
    {
        // Solo las tres posturas. `cc` y `passive` cabalgan encima de ellas y
        // no son un papel en una mazmorra.
        if (!IsStance(def.role))
            continue;
        if (!RunningName(bot, def).empty())
            return def.role;
    }
    return std::string();
}

bool rts::command::SetRole(Player* master, std::string const& botName,
                           std::string const& role, bool on)
{
    Player* bot = RoleSubject(master, botName);
    if (!rts::bots::Driven(bot) || role.empty())
        return false;

    RoleDef const* def = FindRole(role);
    if (!def)
        return false;

    std::set<std::string> const supported = rts::bots::Supported(bot);

    // The other two go first, and by their RUNNING name: see `RunningName`.
    if (on && IsStance(role))
    {
        for (RoleDef const& other : RoleTable())
        {
            if (role == other.role || !IsStance(other.role))
                continue;

            std::string const running = RunningName(bot, other);
            if (running.empty())
                continue;

            g_lastOf[bot->GetGUID()][other.role] = running;
            rts::bots::Change(bot, "-" + running, rts::bots::COMBAT);
        }
    }

    if (on)
    {
        // Already running it: re-assert the very same name instead of picking
        // another of its aliases, which would swap the spec for no reason.
        std::string wanted = RunningName(bot, *def);

        if (wanted.empty())
        {
            auto const bank = g_lastOf.find(bot->GetGUID());
            if (bank != g_lastOf.end())
            {
                auto const seen = bank->second.find(role);
                if (seen != bank->second.end() && supported.count(seen->second))
                    wanted = seen->second;
            }
        }

        if (wanted.empty())
            for (char const* n : def->names)
                if (supported.count(n))
                {
                    wanted = n;
                    break;
                }

        if (wanted.empty())
            return false;

        rts::bots::Change(bot, "+" + wanted, rts::bots::COMBAT);
    }
    else
    {
        std::string const running = RunningName(bot, *def);
        if (!running.empty())
        {
            g_lastOf[bot->GetGUID()][role] = running;
            rts::bots::Change(bot, "-" + running, rts::bots::COMBAT);
        }
    }

    // `passive` VA EN LOS DOS ESTADOS, y las demas no. Las tres posturas
    // (tank/dps/heal) solo significan algo en combate, pero "esperar" significa
    // "no hagas nada", y un bot con `passive` puesto solo en el estado de
    // combate sigue yendo a por cosas fuera de el.
    //
    // Y la mitad que importa es la de APAGARLO. `Suppress` -- tomar prestado el
    // bot para lanzar por el -- pone `+passive` en LOS DOS estados y lo quita de
    // los dos al soltar. Pero si ese soltar no llega a correr (el bot se va del
    // grupo, el maestro se desconecta, el jugador cambia de bot), el `+passive`
    // del estado NO combate se queda. (El segundo sitio que hacia esto era
    // `PossessBot`, borrado en 0.49.0 con la posesion entera.)
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
    // SOBRE UNA COPIA DE LAS CLAVES, no sobre el mapa. `Suppress` entra en
    // mod-playerbots (`ChangeStrategy`), y un iterador sobre un `unordered_map`
    // no sobrevive a que alguien inserte o borre por debajo.
    //
    // Hoy nada de ese camino vuelve aqui, asi que esto no arregla ningun fallo
    // conocido -- se pone porque es la MISMA forma que el crash del 2026-09-05
    // (una referencia a un nodo que sobrevive a una llamada que puede tocar el
    // contenedor), y `queue::Update` y `swap::Update` ya la llevan escrita por
    // haberla pagado. Cuesta seis lineas.
    std::vector<ObjectGuid> masters;
    masters.reserve(g_borrowed.size());
    for (auto const& kv : g_borrowed)
        masters.push_back(kv.first);

    for (ObjectGuid const& mg : masters)
    {
        auto it = g_borrowed.find(mg);
        if (it == g_borrowed.end())
            continue;

        it->second.sinceLastCast += diff;
        if (it->second.sinceLastCast < kIdleReleaseMs)
            continue;

        if (it->second.suppressed)
        {
            if (Player* bot = ObjectAccessor::FindPlayer(it->second.bot))
                Suppress(bot, it->second, false);
        }

        // Se vuelve a buscar: `Suppress` acaba de llamar a codigo ajeno.
        it = g_borrowed.find(mg);
        if (it != g_borrowed.end())
            g_borrowed.erase(it);
    }
}
