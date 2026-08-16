#include "RtsOrders.h"

#include "CharmInfo.h"   // CHARM_TYPE_POSSESS -- Unit.h only forward-declares CharmType
#include "Creature.h"
#include "LootMgr.h"
#include "ObjectDefines.h"   // INTERACTION_DISTANCE
#include "Group.h"
#include "Log.h"
#include "MotionMaster.h"
#include "ObjectAccessor.h"
#include "Player.h"

// AiObjectContext is only forward-declared by PlayerbotAI.h, and GetValue is a
// template on it, so the full definition has to be here.
#include "AiObjectContext.h"
#include "LastMovementValue.h"
#include "PlayerbotAI.h"
#include "PlayerbotMgr.h"
#include "PositionValue.h"

#include <unordered_map>

namespace
{
    // The bot must be someone the commanding player actually commands. Without
    // this, any player could anchor any other player's bot by name.
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

    void SetPosition(PlayerbotAI* ai, char const* key, float x, float y, float z, uint32 mapId)
    {
        PositionMap& posMap = ai->GetAiObjectContext()->GetValue<PositionMap&>("position")->Get();
        PositionInfo pos = posMap[key];
        pos.Set(x, y, z, mapId);
        posMap[key] = pos;
    }

    void ResetPosition(PlayerbotAI* ai, char const* key)
    {
        PositionMap& posMap = ai->GetAiObjectContext()->GetValue<PositionMap&>("position")->Get();
        PositionInfo pos = posMap[key];
        pos.Reset();
        posMap[key] = pos;
    }
}

bool rts::orders::MoveBot(Player* master, std::string const& botName, float x, float y, float z)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    // The same strategy flip StayChatShortcutAction performs, minus the
    // TellMaster that made the bot stop and mime a conversation first.
    ai->ChangeStrategy("+stay,-passive,-move from group", BOT_STATE_NON_COMBAT);
    ai->ChangeStrategy("+stay,-follow,-passive,-move from group", BOT_STATE_COMBAT);

    // "return" is where the bot drifts back to between actions; "stay" is the
    // anchor StayStrategy walks it to. Both have to be the destination, or the
    // two pull against each other.
    SetPosition(ai, "return", x, y, z, bot->GetMapId());
    SetPosition(ai, "stay", x, y, z, bot->GetMapId());

    // Let it abandon the path it is already on.
    //
    // StopMoving() alone does NOT do this, which is why re-clicking appeared to
    // be ignored: the bot stopped, and then its AI refused to issue a new path.
    // MovementAction::MoveTo bails at IsWaitingForLastMove
    // (MovementActions.cpp:183), which blocks any new movement until the delay
    // recorded for the PREVIOUS move has elapsed -- and that delay is computed
    // from the full distance of the old trip. Clearing that record is what
    // actually lets a fresh click take effect immediately.
    ai->GetAiObjectContext()->GetValue<LastMovement&>("last movement")->Get().clear();

    bot->StopMoving();
    bot->GetMotionMaster()->Clear();

    return true;
}

bool rts::orders::AttackBot(Player* master, std::string const& botName, ObjectGuid targetGuid)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai || !targetGuid)
        return false;

    Unit* victim = ObjectAccessor::GetUnit(*bot, targetGuid);
    if (!victim || !victim->IsAlive() || !bot->IsValidAttackTarget(victim))
        return false;

    // A bot pinned to an anchor cannot close on anything, so an attack order
    // releases the hold -- which is what ordering an attack means in an RTS.
    ai->ChangeStrategy("-stay", BOT_STATE_NON_COMBAT);
    ai->ChangeStrategy("-stay", BOT_STATE_COMBAT);
    ResetPosition(ai, "stay");
    ResetPosition(ai, "return");

    // Run the bot's OWN attack action rather than reimplementing it.
    //
    // The first attempt set "prioritized targets" and called Unit::Attack
    // directly, and in game the bots simply did not go. AttackAction::Attack
    // does more than start a swing -- it stops what the bot was doing and gets
    // it moving -- and the engine expects to have driven the whole thing.
    //
    // "attack my target" reads the MASTER's target (AttackAction.cpp:39), so
    // the victim is named by setting that first.
    //
    // SetSelection, NOT SetTarget. Player::SetTarget is an empty function --
    // `void SetTarget(ObjectGuid) override { }` at Player.h:1660, commented
    // "does not apply to players", because a player's target normally arrives
    // from their client. Calling it compiled, ran, and did nothing, so every
    // bot answered "you have no target" while the order itself reported
    // success. SetSelection on the next line of that header is the one that
    // writes the field.
    master->SetSelection(targetGuid);

    // silent = true: no TellMaster, so no turn-and-mime emote before it moves.
    ai->DoSpecificAction("attack my target", Event(), true);

    ai->GetAiObjectContext()->GetValue<LastMovement&>("last movement")->Get().clear();
    return true;
}

bool rts::orders::AttackMoveBot(Player* master, std::string const& botName, float x, float y, float z)
{
    if (!MoveBot(master, botName, x, y, z))
        return false;

    // `grind` is the nearest thing playerbots has to "engage what you meet".
    // It is genuinely an approximation: it makes the bot pick fights near it
    // rather than along a corridor, so it can be pulled off the path -- the
    // anchor is what drags it back on afterwards.
    if (PlayerbotAI* ai = AiFor(ResolveBot(master, botName)))
        ai->ChangeStrategy("+grind", BOT_STATE_NON_COMBAT);

    return true;
}

bool rts::orders::PossessBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    if (bot->GetCharmerGUID())
        return false;   // already possessed by someone

    // Stand the AI down first. A bot still running its own strategies while
    // you steer it would be fighting you for the controls every tick.
    ai->ChangeStrategy("+passive", BOT_STATE_NON_COMBAT);
    ai->ChangeStrategy("+passive", BOT_STATE_COMBAT);

    if (!bot->SetCharmedBy(master, CHARM_TYPE_POSSESS))
    {
        ai->ChangeStrategy("-passive", BOT_STATE_NON_COMBAT);
        ai->ChangeStrategy("-passive", BOT_STATE_COMBAT);
        return false;
    }

    return true;
}

bool rts::orders::ReleaseBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!bot)
        return false;

    if (bot->GetCharmerGUID() == master->GetGUID())
        bot->RemoveCharmedBy(master);

    if (PlayerbotAI* ai = AiFor(bot))
    {
        ai->ChangeStrategy("-passive", BOT_STATE_NON_COMBAT);
        ai->ChangeStrategy("-passive", BOT_STATE_COMBAT);
    }

    // The viewpoint has to go the same way it does for the camera, or the
    // client is left seeing through a character it no longer drives.
    if (WorldObject* seen = master->GetViewpoint())
        master->SetViewpoint(seen, false);

    return true;
}

bool rts::orders::ReleaseAll(Player* master)
{
    if (!master)
        return false;

    Group* group = master->GetGroup();
    if (!group)
        return false;

    bool any = false;
    for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
    {
        Player* member = ref->GetSource();
        if (member && member != master && member->GetCharmerGUID() == master->GetGUID())
            any = ReleaseBot(master, member->GetName()) || any;
    }
    return any;
}

bool rts::orders::MoveSelf(Player* player, float x, float y, float z, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    if (!player || !player->IsInWorld())
        return fail("not in world");

    // Only while something else holds client control -- the RTS camera. If the
    // client is still driving this character, a server-side move would be
    // yanked straight back by the next movement packet it sends.
    if (!player->GetCharm() && !player->GetViewpoint())
        return fail("the RTS camera is not holding control");

    // UNIT_FLAG_DISABLE_MOVE has to come off, and this is the fix for the body
    // that would not walk.
    //
    // Possession sets it on the CHARMER (Unit.cpp, the CHARM_TYPE_POSSESS
    // branch) to tell the client "you may not steer this". The order was
    // arriving, MoveSelf was returning true and the spline was being generated
    // -- confirmed from the channel log, which showed SELFMOVE going out with
    // no error coming back -- and the character still stood there, because the
    // client will not animate a unit it has been told is immobilised.
    //
    // Taking it off is safe here: the client is not driving this body anyway,
    // the CAMERA is its mover. RemoveCharmedBy puts the flag back when the
    // camera is released, so nothing leaks.
    if (player->HasUnitFlag(UNIT_FLAG_DISABLE_MOVE))
        player->RemoveUnitFlag(UNIT_FLAG_DISABLE_MOVE);

    if (player->HasUnitState(UNIT_STATE_ROOT))
        player->SetControlled(false, UNIT_STATE_ROOT);

    player->StopMoving();
    player->GetMotionMaster()->Clear();
    player->GetMotionMaster()->MovePoint(0, x, y, z);

    if (why)
        *why = "ordered";
    return true;
}

rts::orders::ClickIntent rts::orders::ClassifyClick(Player* master, ObjectGuid targetGuid)
{
    if (!master || !targetGuid)
        return CLICK_MOVE;

    Unit* unit = ObjectAccessor::GetUnit(*master, targetGuid);
    if (!unit || !unit->IsInWorld())
        return CLICK_MOVE;

    // Dead things are scenery for these purposes -- a corpse is neither a fight
    // nor a conversation, and treating it as either just eats the click.
    if (!unit->IsAlive())
        return CLICK_MOVE;

    if (master->IsValidAttackTarget(unit))
        return CLICK_ATTACK;

    // Friendly and talkable. A creature with no gossip or quests is scenery
    // too, so ordering a walk is the better answer than a failed conversation.
    if (Creature* creature = unit->ToCreature())
    {
        if (creature->HasNpcFlag(UNIT_NPC_FLAG_GOSSIP) ||
            creature->HasNpcFlag(UNIT_NPC_FLAG_QUESTGIVER) ||
            creature->HasNpcFlag(UNIT_NPC_FLAG_VENDOR))
            return CLICK_INTERACT;
    }

    return CLICK_MOVE;
}

namespace
{
    // A right-click on something out of reach has to mean "go there and do it",
    // not "fail silently". Ordering the walk and then forgetting about it is
    // what a move order is; remembering WHY you walked is what makes it an
    // interaction. So the intent is parked here and completed on arrival.
    //
    // BOTS GO THROUGH THIS TOO, and that is the fix for "the bot stops short of
    // the NPC and nobody ever speaks". TalkBot used to order the walk and then
    // fire `gossip hello` in the SAME TICK, with the bot still standing where it
    // was. That action lands in Player::GetNPCIfCanInteractWith, whose last test
    // is a range check against INTERACTION_DISTANCE; it returns nullptr, and
    // playerbots reads a nullptr there as "nothing to talk to" and returns
    // quietly. So the order reported success, the bot walked, and the
    // conversation had already been thrown away before it set off.
    //
    // It also explains the odd half-working symptom -- walking up to the NPC by
    // hand and clicking again DID work. By then the range check passed. Neither
    // the walk nor the gossip was broken; they were issued in the wrong order,
    // half a walk apart.
    struct Pending
    {
        ObjectGuid master;   // who ordered it, and whose selection names the NPC
        ObjectGuid actor;    // who is walking: the master, or one of their bots
        ObjectGuid target;
        uint32 age = 0;
    };

    // Keyed by ACTOR, so the master and each of their bots can each be walking
    // to something of their own at the same time.
    std::unordered_map<ObjectGuid, Pending> g_pendingInteract;

    // Long enough to cross a courtyard, short enough that a walk you abandoned
    // does not pop a gossip window minutes later.
    constexpr uint32 kPendingTimeoutMs = 20000;

    // How far clear of the NPC the walker is sent.
    //
    // This is a MARGIN, not a distance. The gate that has to pass on arrival is
    // IsWithinDistInMap(creature, INTERACTION_DISTANCE), which adds BOTH
    // parties' combat reaches to the 5.5 -- and GetContactPoint adds the very
    // same two reaches to the point it returns. The reaches cancel, so what is
    // actually left over is (5.5 - kStandOff) yards of slack for the path to be
    // imprecise in. The old value of 4.5 left one yard of that, which mmap
    // snapping to walkable ground eats without trying; 2.0 leaves three and a
    // half, and still puts the bot close enough to read as talking to the NPC
    // rather than shouting at it.
    constexpr float kStandOff = 2.0f;

    // Send a walker to conversational range of an NPC. False if it is already
    // there and should just get on with it.
    bool WalkToInteract(Player* master, Player* actor, Creature* creature)
    {
        if (actor->IsWithinDistInMap(creature, INTERACTION_DISTANCE))
            return false;

        float x, y, z;
        creature->GetContactPoint(actor, x, y, z, kStandOff);

        if (actor == master)
            rts::orders::MoveSelf(master, x, y, z);
        else
            rts::orders::MoveBot(master, actor->GetName(), x, y, z);

        return true;
    }

    bool DoInteract(Player* player, Creature* creature)
    {
        if (!player || !creature)
            return false;

        player->SetSelection(creature->GetGUID());

        // A dead creature you may loot is a corpse, not a conversation.
        if (!creature->IsAlive())
        {
            if (!player->isAllowedToLoot(creature))
                return false;
            player->SendLoot(creature->GetGUID(), LOOT_CORPSE);
            return true;
        }

        if (creature->HasNpcFlag(UNIT_NPC_FLAG_GOSSIP) ||
            creature->HasNpcFlag(UNIT_NPC_FLAG_QUESTGIVER) ||
            creature->HasNpcFlag(UNIT_NPC_FLAG_VENDOR))
        {
            player->PrepareGossipMenu(creature, creature->GetCreatureTemplate()->GossipMenuId, true);
            player->SendPreparedGossip(creature);
            return true;
        }

        return false;
    }

    // Have a bot open the conversation itself.
    //
    // Same trap as the attack order: the action reads the MASTER's target, and
    // Player::SetTarget is an empty function, so SetSelection is the one that
    // actually names the NPC.
    bool BotInteract(Player* master, Player* bot, Creature* creature)
    {
        PlayerbotAI* ai = AiFor(bot);
        if (!ai)
            return false;

        master->SetSelection(creature->GetGUID());
        bot->SetSelection(creature->GetGUID());
        bot->SetFacingToObject(creature);

        // silent = true: no TellMaster, so no turn-and-mime before it speaks.
        return ai->DoSpecificAction("gossip hello", Event(), true);
    }

    // Park the walk so UpdatePending can finish it when the walker arrives.
    void Remember(Player* master, Player* actor, ObjectGuid target)
    {
        Pending p;
        p.master = master->GetGUID();
        p.actor  = actor->GetGUID();
        p.target = target;
        g_pendingInteract[actor->GetGUID()] = p;
    }
}

bool rts::orders::TalkBot(Player* master, std::string const& botName, ObjectGuid targetGuid)
{
    Player* bot = ResolveBot(master, botName);
    if (!bot || !AiFor(bot) || !targetGuid)
        return false;

    Unit* unit = ObjectAccessor::GetUnit(*master, targetGuid);
    Creature* creature = unit ? unit->ToCreature() : nullptr;
    if (!creature)
        return false;

    // Walk right up to the NPC first. Working out where "right up to it" is, is
    // the server's job precisely because it is the only side that knows both
    // positions exactly -- the addon used to send a bare `talk` and hope.
    if (WalkToInteract(master, bot, creature))
    {
        Remember(master, bot, targetGuid);
        return true;
    }

    return BotInteract(master, bot, creature);
}

bool rts::orders::SelfAttack(Player* player, ObjectGuid targetGuid)
{
    if (!player || !targetGuid)
        return false;

    Unit* victim = ObjectAccessor::GetUnit(*player, targetGuid);
    if (!victim || !victim->IsAlive() || !player->IsValidAttackTarget(victim))
        return false;

    player->SetSelection(targetGuid);
    player->Attack(victim, true);

    // Auto-attack alone leaves you swinging at thin air from range. The body is
    // server-driven while the camera has client control, so it has to be walked
    // into reach the same way a creature would be.
    player->GetMotionMaster()->MoveChase(victim);
    return true;
}

bool rts::orders::SelfInteract(Player* player, ObjectGuid targetGuid)
{
    if (!player || !targetGuid)
        return false;

    Unit* unit = ObjectAccessor::GetUnit(*player, targetGuid);
    Creature* creature = unit ? unit->ToCreature() : nullptr;
    if (!creature)
        return false;

    // Out of reach: walk there, and remember what it was for.
    if (WalkToInteract(player, player, creature))
    {
        Remember(player, player, targetGuid);
        return true;
    }

    return DoInteract(player, creature);
}

void rts::orders::UpdatePending(uint32 diff)
{
    for (auto it = g_pendingInteract.begin(); it != g_pendingInteract.end();)
    {
        Pending& p = it->second;
        p.age += diff;

        Player* master = ObjectAccessor::FindPlayer(p.master);
        Player* actor  = (p.actor == p.master) ? master : ObjectAccessor::FindPlayer(p.actor);

        if (!master || !actor || !actor->IsInWorld() || p.age > kPendingTimeoutMs)
        {
            it = g_pendingInteract.erase(it);
            continue;
        }

        Unit* unit = ObjectAccessor::GetUnit(*actor, p.target);
        Creature* creature = unit ? unit->ToCreature() : nullptr;
        if (!creature)
        {
            it = g_pendingInteract.erase(it);
            continue;
        }

        if (!actor->IsWithinDistInMap(creature, INTERACTION_DISTANCE))
        {
            ++it;
            continue;   // still walking
        }

        if (actor == master)
            DoInteract(master, creature);
        else
            BotInteract(master, actor, creature);

        it = g_pendingInteract.erase(it);
    }
}

void rts::orders::ForgetPlayer(Player* master)
{
    if (!master)
        return;

    // Anything this player parked has to go with them, or a bot left behind
    // would walk up to an NPC and open a conversation for a master who has
    // logged out.
    for (auto it = g_pendingInteract.begin(); it != g_pendingInteract.end();)
    {
        if (it->second.master == master->GetGUID())
            it = g_pendingInteract.erase(it);
        else
            ++it;
    }

    ReleaseAll(master);
}

bool rts::orders::FollowBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    PlayerbotAI* ai = AiFor(bot);
    if (!ai)
        return false;

    ai->ChangeStrategy("+follow,-passive,-grind,-move from group", BOT_STATE_NON_COMBAT);
    ai->ChangeStrategy("-stay,-follow,-passive,-grind,-move from group", BOT_STATE_COMBAT);

    ResetPosition(ai, "return");
    ResetPosition(ai, "stay");

    return true;
}
