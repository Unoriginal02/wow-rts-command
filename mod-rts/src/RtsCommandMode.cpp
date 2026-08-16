#include "RtsCommandMode.h"

#include "Group.h"
#include "GroupReference.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include "AiObjectContext.h"
#include "PlayerbotAI.h"
#include "PlayerbotMgr.h"

#include <algorithm>
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

    void Suppress(PlayerbotAI* ai, bool on)
    {
        if (!ai)
            return;
        ai->ChangeStrategy(on ? "+passive" : "-passive", BOT_STATE_NON_COMBAT);
        ai->ChangeStrategy(on ? "+passive" : "-passive", BOT_STATE_COMBAT);
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
        Suppress(ai, true);
        b.suppressed = true;
    }
    b.sinceLastCast = 0;

    // Routed through the bot's own AI rather than Unit::CastSpell, so range,
    // facing, cooldowns and the global cooldown are all respected exactly as
    // they are when the bot casts for itself.
    if (!ai->CastSpell(spellId, target))
        return fail("the cast did not go through (range, cooldown or line of sight)");

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
            Suppress(AiFor(bot), false);
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
                Suppress(AiFor(bot), false);
        }
        it = g_borrowed.erase(it);
    }
}
