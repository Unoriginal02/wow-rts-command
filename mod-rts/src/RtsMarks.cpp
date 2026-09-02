#include "RtsMarks.h"

#include "DynamicObject.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "RtsOrders.h"   // GroundZ -- one place decides where the floor is
#include "SharedDefines.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include <algorithm>
#include <cctype>
#include <map>

namespace
{
    // Long enough that no route outlives it, short enough that a marker orphaned
    // by something we did not foresee tidies itself up instead of decorating the
    // world until the next restart.
    constexpr int32 kLifetimeMs = 30 * 60 * 1000;

    struct State
    {
        rts::marks::Look look;
        std::map<uint32, ObjectGuid> objs;   // waypoint slot -> dynobject
    };

    // std::map and not unordered: ObjectGuid has operator< and no std::hash.
    std::map<ObjectGuid, State> g_state;

    State& StateOf(Player* player)
    {
        return g_state[player->GetGUID()];
    }

    State* Peek(Player* player)
    {
        auto const it = g_state.find(player->GetGUID());
        return it == g_state.end() ? nullptr : &it->second;
    }

    // The spell actually used: the chosen one, or the first candidate when
    // nothing has been chosen yet, so a fresh install still shows something.
    uint32 EffectiveSpell(rts::marks::Look const& look)
    {
        if (look.spell)
            return look.spell;
        auto const& c = rts::marks::Candidates();
        return c.empty() ? 0 : c.front().id;
    }

    std::string Lower(std::string s)
    {
        for (char& ch : s)
            ch = static_cast<char>(::tolower(static_cast<unsigned char>(ch)));
        return s;
    }

    // The protocol back to the addon separates entries with ';' and fields with
    // '|'. No spell name carries either today, but a name that did would split
    // one entry into two and the addon would read a name as an id.
    std::string Clean(std::string s)
    {
        for (char& ch : s)
            if (ch == ';' || ch == '|')
                ch = ' ';
        return s;
    }

    // Put every existing marker back with the current look. This is what makes
    // stepping through visuals usable: the route already on the ground changes
    // under you instead of only the next one you place.
    void Refresh(Player* player)
    {
        State* st = Peek(player);
        if (!st || st->objs.empty())
            return;

        std::vector<std::pair<uint32, Position>> keep;
        keep.reserve(st->objs.size());
        for (auto const& kv : st->objs)
            if (DynamicObject* dyn = ObjectAccessor::GetDynamicObject(*player, kv.second))
                keep.emplace_back(kv.first, dyn->GetPosition());

        rts::marks::RemoveAll(player);
        for (auto const& e : keep)
            rts::marks::Place(player, e.first, e.second);
    }
}

namespace rts
{
    namespace marks
    {

// THE LIST IS NOT WRITTEN FROM MEMORY, and that is the whole point of it.
//
// Naming ground visuals by hand -- 26573 Consecration, 43265 Death and Decay --
// is a list of constants that this project keeps learning not to trust: a wrong
// spell id does not error, it draws NOTHING, which is indistinguishable from a
// marker that failed to spawn. So the candidates come out of the spell store
// the server has already loaded from this exact client's DBCs: every spell with
// a persistent-area-aura effect, which is precisely the set the client has a
// ground visual for. If a spell is in this list, the client knows how to draw it
// somewhere on the floor.
std::vector<Cand> const& Candidates()
{
    static std::vector<Cand> cands;
    static bool built = false;
    if (built)
        return cands;
    built = true;

    uint32 const size = sSpellMgr->GetSpellInfoStoreSize();
    for (uint32 id = 1; id < size; ++id)
    {
        SpellInfo const* info = sSpellMgr->GetSpellInfo(id);
        if (!info)
            continue;

        bool ground = false;
        for (auto const& eff : info->Effects)
            if (eff.Effect == SPELL_EFFECT_PERSISTENT_AREA_AURA)
            {
                ground = true;
                break;
            }
        if (!ground)
            continue;

        std::string name;
        for (char const* n : info->SpellName)
            if (n && *n)
            {
                name = n;
                break;
            }
        if (name.empty())
            continue;   // unnamed rows are test/placeholder spells

        cands.push_back({ id, Clean(name) });
    }

    LOG_INFO("module", "mod-rts: {} ground-visual candidates for route markers",
             cands.size());
    return cands;
}

std::string NameOf(uint32 spellId)
{
    SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
    if (!info)
        return "?";
    for (char const* n : info->SpellName)
        if (n && *n)
            return Clean(n);
    return "?";
}

Look const& Get(Player* player)
{
    return StateOf(player).look;
}

void SetSpell(Player* player, uint32 spellId)
{
    State& st = StateOf(player);
    st.look.spell = spellId;

    // Keep the step index pointing at whatever is on screen, so next/prev after
    // a direct pick carries on from there rather than from wherever the index
    // happened to be left.
    auto const& c = Candidates();
    for (std::size_t i = 0; i < c.size(); ++i)
        if (c[i].id == spellId)
        {
            st.look.index = i;
            break;
        }

    Refresh(player);
}

// THE SIZE KNOB DID NOTHING IN GAME, AND THE MODE IS WHY.
//
// With mode 1 (DYNAMIC_OBJECT_AREA_SPELL) the client OVERRIDES the radius for
// most ground-patch visuals and draws them at the size they were authored --
// the core says exactly that where it writes the field. So every /rts mark size
// was arriving, being stored, and then being ignored by the client. The default
// is now mode 0, where the client always uses DYNAMICOBJECT_RADIUS. That is the
// fix; the knob itself was never broken.
//
// ZERO MEANS AUTOMATIC and is not clamped away. A yard figure means nothing on
// its own -- it only makes sense next to the size the visual was drawn at -- so
// the resting state is a FRACTION of the spell's own radius, and changing spell
// re-derives it instead of leaving a number that fitted the previous one.
void SetRadius(Player* player, float radius)
{
    State& st = StateOf(player);
    st.look.radius = radius <= 0.0f ? 0.0f : std::max(0.05f, std::min(200.0f, radius));
    Refresh(player);
}

void SetScale(Player* player, float scale)
{
    State& st = StateOf(player);
    float const own = SpellRadius(EffectiveSpell(st.look));
    if (own <= 0.0f || scale <= 0.0f)
    {
        st.look.radius = 0.0f;      // back to automatic
    }
    else
    {
        st.look.radius = std::max(0.05f, std::min(200.0f, own * scale));
    }
    Refresh(player);
}

// The radius the spell itself was designed with. This is the "original" that a
// scale is a fraction of -- read out of the effect data rather than guessed,
// which is the same reason the candidate list is not a hand-written array.
float SpellRadius(uint32 spellId)
{
    SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
    if (!info)
        return 0.0f;

    for (auto const& eff : info->Effects)
        if (eff.Effect == SPELL_EFFECT_PERSISTENT_AREA_AURA)
        {
            float const r = eff.CalcRadius();
            if (r > 0.0f)
                return r;
        }

    // Some visuals carry their radius on a different effect; any radius beats
    // none, because a zero here would silently turn every scale into automatic.
    for (auto const& eff : info->Effects)
    {
        float const r = eff.CalcRadius();
        if (r > 0.0f)
            return r;
    }
    return 0.0f;
}

float EffectiveRadius(Look const& look)
{
    if (look.radius > 0.0f)
        return look.radius;

    float const own = SpellRadius(EffectiveSpell(look));
    return own > 0.0f ? own * kDefaultScale : 4.0f;
}

// mode 1 (DYNAMIC_OBJECT_AREA_SPELL) is what the client is sent for real
// spells, and with it the client OVERRIDES the radius for most ground-patch
// visuals -- the core says so where it writes the field, and it means the size
// dial does nothing for those. mode 0 makes the client honour DYNAMICOBJECT_
// RADIUS always, at the price of many visuals needing precompensation. Both are
// exposed because which one a given spell needs is a thing to look at, not to
// reason about.
// El otro mando del tamano, y el que no depende de que el visual quiera. Escala
// el MODELO (OBJECT_FIELD_SCALE_X), que es el mismo campo que hace grande o
// pequena a una criatura, asi que no pasa por la decision del cliente sobre si
// esta mancha de suelo se estira con su radio. Se pone despues de Create --
// donde el nucleo lo deja en 1 -- y antes de que el objeto llegue a nadie: el
// paquete de creacion se arma en la siguiente vuelta de visibilidad del
// jugador, asi que lo que sale ya lleva la escala puesta.
void SetObjScale(Player* player, float scale)
{
    State& st = StateOf(player);
    st.look.obj = scale <= 0.0f ? kDefaultObjScale : std::max(0.02f, std::min(20.0f, scale));
    Refresh(player);
}

void SetMode(Player* player, uint8 mode)
{
    State& st = StateOf(player);
    st.look.mode = mode ? 1 : 0;
    Refresh(player);
}

void Step(Player* player, int delta)
{
    auto const& c = Candidates();
    if (c.empty())
        return;

    State& st = StateOf(player);
    int const n = static_cast<int>(c.size());
    int i = static_cast<int>(st.look.index) + delta;
    while (i < 0)
        i += n;
    i %= n;

    st.look.index = static_cast<std::size_t>(i);
    st.look.spell = c[st.look.index].id;
    Refresh(player);
}

bool Find(Player* player, std::string const& text)
{
    auto const& c = Candidates();
    std::string const needle = Lower(text);
    if (needle.empty())
        return false;

    State& st = StateOf(player);
    // Start looking AFTER the current one, so repeating the same search walks
    // through the matches instead of sticking on the first.
    for (std::size_t k = 1; k <= c.size(); ++k)
    {
        std::size_t const i = (st.look.index + k) % c.size();
        if (Lower(c[i].name).find(needle) == std::string::npos)
            continue;

        st.look.index = i;
        st.look.spell = c[i].id;
        Refresh(player);
        return true;
    }
    return false;
}

bool Place(Player* player, uint32 slot, Position const& pos)
{
    if (!player || !player->IsInWorld() || !player->FindMap() || slot == 0)
        return false;

    State& st = StateOf(player);
    uint32 const spell = EffectiveSpell(st.look);
    if (!spell)
        return false;

    Remove(player, slot);

    // ON THE FLOOR, AND THE SAME FLOOR THE BOT WILL STAND ON. The Z arrives from
    // the client, which has its own idea of the terrain; the server has the
    // vmaps and the last word. If the two disagree the marker floats -- and,
    // worse, it floats somewhere DIFFERENT from where the bot stops, so the mark
    // stops meaning "here". Both go through rts::orders::GroundZ for exactly
    // that reason.
    Position ground(pos);
    float gz = ground.GetPositionZ();
    rts::orders::GroundZ(player, ground.GetPositionX(), ground.GetPositionY(), gz);
    ground.Relocate(ground.GetPositionX(), ground.GetPositionY(), gz, 0.0f);

    DynamicObject* dyn = new DynamicObject();
    if (!dyn->CreateDynamicObject(
            player->GetMap()->GenerateLowGuid<HighGuid::DynamicObject>(),
            player, spell, ground, EffectiveRadius(st.look),
            static_cast<DynamicObjectType>(st.look.mode)))
    {
        delete dyn;
        return false;
    }

    // WITHOUT THIS IT DIES ON THE NEXT TICK. A dynobject with no aura is kept
    // alive purely by its duration, and the duration starts at zero -- so the
    // marker would appear and vanish within one map update, which reads as "the
    // spell has no visual" rather than as a lifetime bug. The core sets it the
    // same way, after Create, in its own farsight path.
    dyn->SetDuration(kLifetimeMs);

    // Segundo mando del tamano, independiente del radio -- ver SetObjScale.
    // Solo se toca si no es 1, para que un marcador normal salga exactamente
    // igual que antes de que este mando existiera.
    if (st.look.obj != kDefaultObjScale)
        dyn->SetObjectScale(st.look.obj);

    st.objs[slot] = dyn->GetGUID();
    return true;
}

void Remove(Player* player, uint32 slot)
{
    if (!player)
        return;
    if (slot == 0)
    {
        RemoveAll(player);
        return;
    }

    State* st = Peek(player);
    if (!st)
        return;

    auto const it = st->objs.find(slot);
    if (it == st->objs.end())
        return;

    // The object may already be gone -- the core tears every dynobject down on
    // a map change -- so a missing one is normal, not an error.
    if (DynamicObject* dyn = ObjectAccessor::GetDynamicObject(*player, it->second))
        dyn->Remove();

    st->objs.erase(it);
}

void RemoveAll(Player* player)
{
    State* st = Peek(player);
    if (!st)
        return;

    for (auto const& kv : st->objs)
        if (DynamicObject* dyn = ObjectAccessor::GetDynamicObject(*player, kv.second))
            dyn->Remove();

    st->objs.clear();
}

std::size_t Count(Player* player)
{
    State* st = Peek(player);
    return st ? st->objs.size() : 0;
}

void ForgetPlayer(Player* player)
{
    if (!player)
        return;
    RemoveAll(player);
    g_state.erase(player->GetGUID());
}

    }  // namespace marks
}  // namespace rts
