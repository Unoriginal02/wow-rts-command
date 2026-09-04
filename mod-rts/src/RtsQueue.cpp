#include "RtsQueue.h"

#include "RtsBotApi.h"
#include "RtsCommandMode.h"

#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{
    // LOS DOS PLAZOS, Y POR QUE SON DOS.
    //
    // Un hechizo que pide objetivo puede estar esperando a que el objetivo
    // vuelva a rango, y eso tarda: ocho segundos es algo mas que el global (1,5)
    // mas el casteo mas largo de una barra (~3) mas un margen para recolocarse.
    //
    // Uno que NO pide objetivo -- un grito, un aura, una postura -- solo puede
    // estar esperando un enfriamiento, y eso se resuelve en un par de segundos.
    // Esperar ocho seria tener el icono girando mucho despues de que la respuesta
    // ya se sepa.
    constexpr uint32 kDeadlineAimedMs = 8000;
    constexpr uint32 kDeadlinePlainMs = 3000;

    // CADA CUANTO SE REINTENTA. No cada vuelta del mundo: `CastAs` llama a
    // `StopMoving()` en cada intento (hace falta -- moverse cancela un casteo,
    // y `passive` permite `follow` a proposito), asi que reintentar veinte veces
    // por segundo seria clavar al bot en el sitio.
    constexpr uint32 kRetryMs = 400;

    struct Pending
    {
        std::string bot;
        uint32 spellId = 0;
        ObjectGuid target;
        uint32 waited = 0;
        uint32 sinceTry = 0;
        uint32 deadline = kDeadlineAimedMs;
        std::string lastWhy;
    };

    // master guid -> nombre de bot -> lo que espera.
    //
    // UNO POR PERSONAJE, y esa es la decision. Sin ella, cuatro clicks nerviosos
    // sobre el mismo bot son cuatro hechizos saliendo seguidos diez segundos mas
    // tarde -- que no es lo que nadie quiso decir al hacer el cuarto click.
    // Encolar otra cosa en el mismo bot sustituye lo que hubiera.
    std::unordered_map<ObjectGuid, std::unordered_map<std::string, Pending>> g_queue;

    rts::queue::Sink g_sink;

    void Say(Player* master, std::string const& bot, uint32 spellId,
             char const* state, std::string const& why)
    {
        if (!g_sink || !master)
            return;
        std::ostringstream out;
        out << "CASTQ " << bot << ' ' << spellId << ' ' << state;
        if (!why.empty())
            out << ' ' << why;
        g_sink(master, out.str());
    }

    // ¿ESTA EL OBJETIVO A TIRO? Y por que hace falta preguntarlo aqui.
    //
    // Sin esto habria un fallo construido a proposito: `CastAs` para al bot
    // antes de lanzar, asi que reintentar sobre un objetivo lejano lo pararia
    // cada 400 ms -- y el bot NUNCA PODRIA ACERCARSE. La cola convertiria
    // "espera a tenerlo a tiro" en "quedate quieto para siempre".
    //
    // Estando fuera de alcance no se intenta nada: se deja al bot moverse y se
    // vuelve a mirar. Es la unica comprobacion que la cola hace por su cuenta, y
    // existe porque es la unica que cambia lo que la cola HACE, no solo lo que
    // dice.
    bool InRange(Player* bot, Unit* target, SpellInfo const* info)
    {
        if (!bot || !target || !info)
            return true;
        if (bot == target)
            return true;

        float const max = info->GetMaxRange(info->IsPositive());
        if (max <= 0.0f)
            return true;

        // Un poco de margen: el bot y el objetivo se mueven entre que se mide y
        // que se lanza, y quedarse corto aqui solo cuesta un intento fallido.
        return bot->IsWithinDistInMap(target, max + 1.0f);
    }

    // Lo que se puede decir al vencer el plazo SIN reimplementar `CheckCast`.
    //
    // No pretende ser el motivo exacto -- para eso habria que duplicar la
    // maquina de comprobaciones del nucleo, que es justo lo que no se hace.
    // Pretende que el mensaje sea ACCIONABLE: "fuera de alcance" manda a
    // acercarse, "sin maná" a esperar, y "no encontro hueco" dice honestamente
    // que no se sabe.
    std::string GuessWhy(Player* master, Pending const& p)
    {
        Player* bot = rts::bots::Resolve(master, p.bot);
        if (!bot)
            return "ese personaje ya no esta";
        if (!bot->IsAlive())
            return "esta muerto";

        SpellInfo const* info = sSpellMgr->GetSpellInfo(p.spellId);

        if (p.target)
        {
            Unit* t = ObjectAccessor::GetUnit(*bot, p.target);
            if (!t || !t->IsInWorld())
                return "el objetivo desaparecio";
            if (!t->IsAlive() && info && !info->IsAllowingDeadTarget())
                return "el objetivo murio";
            if (!InRange(bot, t, info))
                return "fuera de alcance";
        }

        if (info && info->ManaCost > 0 &&
            bot->GetPower(Powers(info->PowerType)) < int32(info->ManaCost))
            return "sin recurso";

        if (!p.lastWhy.empty())
            return p.lastWhy;
        return "no encontro hueco a tiempo";
    }
}

void rts::queue::SetSink(Sink sink)
{
    g_sink = sink;
}

void rts::queue::Push(Player* master, std::string const& botName, uint32 spellId,
                      ObjectGuid target)
{
    if (!master || botName.empty() || !spellId)
        return;

    std::string why;
    bool retryable = false;

    // SE INTENTA YA. Lo normal es que salga a la primera y la cola no llegue a
    // existir; encolar siempre y esperar al siguiente tick metería 400 ms de
    // retraso a todos los lanzamientos para arreglar el caso raro.
    if (rts::command::CastAs(master, botName, spellId, target, &why, &retryable))
    {
        Say(master, botName, spellId, "ok", "");
        g_queue[master->GetGUID()].erase(botName);
        return;
    }

    if (!retryable)
    {
        Say(master, botName, spellId, "fail", why);
        g_queue[master->GetGUID()].erase(botName);
        return;
    }

    SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
    char const type = rts::command::ClassifySpell(info);
    bool const aimed = (type == 'A' || type == 'H' || type == 'G' || type == 'D');

    Pending p;
    p.bot = botName;
    p.spellId = spellId;
    p.target = target;
    p.deadline = aimed ? kDeadlineAimedMs : kDeadlinePlainMs;
    p.lastWhy = why;

    g_queue[master->GetGUID()][botName] = p;
    Say(master, botName, spellId, "wait", "");
}

void rts::queue::Drop(Player* master)
{
    if (master)
        g_queue.erase(master->GetGUID());
}

void rts::queue::Update(uint32 diff)
{
    if (g_queue.empty())
        return;

    // SOBRE UNA COPIA DE LAS CLAVES, no sobre el mapa. `CastAs` puede acabar
    // soltando un bot y eso dispara ganchos nuestros de forma sincrona; un
    // iterador sobre un `unordered_map` no sobrevive a que alguien inserte. Es
    // la misma guarda que `swap::Update` lleva escrita por haberlo pagado.
    std::vector<ObjectGuid> masters;
    masters.reserve(g_queue.size());
    for (auto const& kv : g_queue)
        masters.push_back(kv.first);

    for (ObjectGuid const& mg : masters)
    {
        auto it = g_queue.find(mg);
        if (it == g_queue.end())
            continue;

        Player* master = ObjectAccessor::FindPlayer(mg);
        if (!master || !master->IsInWorld())
        {
            g_queue.erase(it);
            continue;
        }

        std::vector<std::string> bots;
        bots.reserve(it->second.size());
        for (auto const& kv : it->second)
            bots.push_back(kv.first);

        for (std::string const& bn : bots)
        {
            auto pit = it->second.find(bn);
            if (pit == it->second.end())
                continue;
            Pending& p = pit->second;

            p.waited += diff;
            p.sinceTry += diff;

            if (p.waited >= p.deadline)
            {
                Say(master, p.bot, p.spellId, "timeout", GuessWhy(master, p));
                it->second.erase(pit);
                continue;
            }

            if (p.sinceTry < kRetryMs)
                continue;
            p.sinceTry = 0;

            // Fuera de alcance no se intenta: ver `InRange`. Dejar que el bot
            // se acerque es la diferencia entre una cola que espera y una que
            // ancla.
            if (p.target)
            {
                Player* bot = rts::bots::Resolve(master, p.bot);
                Unit* t = bot ? ObjectAccessor::GetUnit(*bot, p.target) : nullptr;
                SpellInfo const* info = sSpellMgr->GetSpellInfo(p.spellId);
                if (bot && t && !InRange(bot, t, info))
                {
                    p.lastWhy = "fuera de alcance";
                    continue;
                }
            }

            std::string why;
            bool retryable = false;
            if (rts::command::CastAs(master, p.bot, p.spellId, p.target, &why, &retryable))
            {
                Say(master, p.bot, p.spellId, "ok", "");
                it->second.erase(pit);
                continue;
            }

            p.lastWhy = why;
            if (!retryable)
            {
                Say(master, p.bot, p.spellId, "fail", why);
                it->second.erase(pit);
            }
        }

        if (it->second.empty())
            g_queue.erase(it);
    }
}
