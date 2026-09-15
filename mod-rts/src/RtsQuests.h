#ifndef MOD_RTS_QUESTS_H
#define MOD_RTS_QUESTS_H

#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Every quest an NPC has, and who in the group can take them or hand them
    // in. Accepting and turning in for several at once.
    //
    // === THIS DOES NOT TOUCH mod-playerbots =================================
    //
    // Not one call. A bot is a `Player`, and the core's quest functions take a
    // `Player`. The only thing asked of `RtsBotApi` is `Resolve`, which is pure
    // core.
    //
    // === DISTANCE: WHY THIS IS LEGAL ========================================
    //
    // The bit from the video -- *"you don't have to actually be next to it"* --
    // comes for free, and not by a trick: **none** of the core's domain
    // functions checks distance. Verified line by line in `PlayerQuest.cpp`:
    // `CanTakeQuest` (:252), `CanAddQuest` (:266), `AddQuest` (:520),
    // `CanRewardQuest` (:387/:471) and `RewardQuest` (:675) validate status,
    // level, reputation, bag room and quest log room -- and nothing else.
    //
    // The only distance gate is `Player::CanInteractWithQuestGiver`
    // (`Player.cpp:2095` -> `GetNPCIfCanInteractWith` -> `IsWithinDistInMap`),
    // and it is called ONLY by the opcode handlers (`QuestHandler.cpp:134, 270,
    // 368, 492`), commented by the core itself as *"some kind of WPE
    // protection"*. That is: it is a defence against a CLIENT that lies about
    // where it is, not a rule of the game. We do not come from a client.
    //
    // And this is not our own reading: **mod-playerbots already exploits it the
    // same way**. `QuestAction::AcceptQuest` (`QuestAction.cpp:244-248`) falls
    // through to `bot->AddQuest(quest, pObject)` directly when the bot is far
    // away, and `TalkToQuestGiverAction` (`:107-132`) calls
    // `CanRewardQuest`/`RewardQuest` without ever going through the handler.
    namespace quests
    {
        // The status of ONE quest for ONE character. Our own numbers and not
        // the core's: `QuestStatus` lumps together things that are drawn the
        // same here and separates things that are drawn differently here, and
        // the client needs exactly these five.
        enum Status
        {
            ST_NO      = 0,   // no good for them: level, race, class, chain, log full
            ST_CAN     = 1,   // can take it now
            ST_DOING   = 2,   // carrying it, unfinished
            ST_READY   = 3,   // carrying it and ready to hand in
            ST_DONE    = 4,   // already did it
        };

        enum Flag
        {
            FLAG_CHOICE = 1,   // has a reward to choose from
            FLAG_GIVES  = 2,   // this NPC GIVES it
            FLAG_TAKES  = 4,   // this NPC RECEIVES it
        };

        struct Member
        {
            std::string name;
            uint8       status = ST_NO;
        };

        struct Offer
        {
            uint32      questId = 0;
            uint32      flags = 0;
            uint32      level = 0;
            std::string title;
            std::vector<Member> members;

            // The items to choose between, if there are any. They go here and
            // are not asked for separately because the client needs them at the
            // very instant it draws the row: a quest marked "choose a reward"
            // with a hand-in button that offers nothing to choose is worse than
            // not marking it at all.
            std::vector<uint32> choices;
        };

        // Everything this NPC has to offer the group. Empty if the guid is not
        // a visible creature.
        bool Look(Player* master, ObjectGuid npcGuid, std::vector<Offer>& out);

        // WHO IN THE GROUP IS CARRYING ONE PARTICULAR QUEST.
        //
        // A single quest and not the 25 in the log, because the only consumer
        // is the tooltip of the share button in the NATIVE log: it asks about
        // whichever one is selected and about no other.
        //
        // `gives` goes to `true` when scoring: there is no NPC in front of us
        // here, so "can take it" means *"the core would give it to them"* and
        // not *"this NPC would give it to them"*. It is exactly the distinction
        // `PRUEBAS-20` B forced us to make in `Look`, and here it falls on the
        // other side for the same reason: the one giving it is us.
        //
        // The master does NOT appear in the list: the question is about their
        // companions, and their own quest is already on screen in front of
        // them.
        bool Holders(Player* master, uint32 questId, std::vector<Member>& out);

        // GIVING ONE OF MY QUESTS TO SOMEONE WHO IS NOT CARRYING IT.
        //
        // Same engine as `CatchUp` -- mark the earlier links of the chain and
        // then try to give it -- with the gate moved elsewhere, which is the
        // only thing that separates the two:
        //
        //   `CatchUp` requires that THE NPC IN FRONT OF YOU gives that quest.
        //   `Share`   requires that YOU ARE CARRYING IT.
        //
        // Both exist for the same reason: so the addon cannot ask for any old
        // chain in the game to be marked as done. And `Share`'s is the narrower
        // of the two, because your log is 25 quests and the ones an NPC gives
        // can be anybody's.
        //
        // The `questGiver` handed to the core is the MASTER, not null: for a
        // timed quest `Player::AddQuest` copies the time left from whoever is
        // sharing it (`PlayerQuest.cpp`, `questGiver->IsPlayer()`), which is
        // exactly the split the game's own quest sharing does.
        bool Share(Player* master, uint32 questId,
                   std::vector<std::string> const& names,
                   int& okOut, int& failOut,
                   std::vector<std::string>& notes, std::string* why = nullptr);

        // BRINGING THE CHAIN UP TO DATE, for the companion who fell behind.
        //
        // The case: you are halfway through a chain, a bot did not follow you,
        // and now it cannot take the one that is due because it is missing the
        // earlier ones. Without this that bot is cut off from the chain FOREVER
        // -- nobody where you are gives the earlier quests any more.
        //
        // === WHY THIS IS NOT A TRICK, AND WHY NO GM COMMANDS ARE NEEDED
        //
        // The chain requirement the core checks is literally
        // `IsQuestRewarded(prevId)` (`PlayerQuest.cpp:1039`), and there is a
        // public method that sets it: `Player::SetRewardedQuest(id)`, three
        // lines that insert into `m_RewardedQuests` and mark it to be saved. No
        // packet is forged, the database is not touched by hand, and there is
        // no need to select each bot to type it a `.quest complete`: the GM
        // commands call this same core, only one at a time and on your
        // selection.
        //
        // ONLY THE CHAIN IS FORCED. Level, class, race, reputation and a full
        // log are left as they are and are REPORTED: they are reasons other
        // than "it did not follow you", and covering them up would turn an
        // honest button into one that sometimes does something you do not
        // understand.
        //
        // The NEGATIVE links of `prevQuests` cannot be fixed this way -- they
        // ask for the quest to be ACTIVE, not rewarded (`:1071`) -- and that is
        // why they are reported instead of faked.
        bool CatchUp(Player* master, ObjectGuid npcGuid, uint32 questId,
                     std::vector<std::string> const& names,
                     int& okOut, int& failOut,
                     std::vector<std::string>& notes, std::string* why = nullptr);

        // Accept / hand in for a list of names (the player included). `okOut`
        // and `failOut` receive how many went well and how many did not, so the
        // client can say something concrete instead of "done".
        //
        // `why` receives the reason when the whole operation could not even be
        // attempted (the quest does not exist, the NPC does not give it...).
        bool Accept(Player* master, ObjectGuid npcGuid, uint32 questId,
                    std::vector<std::string> const& names,
                    int& okOut, int& failOut, std::string* why = nullptr);

        // `reward` = AUTO_REWARD means "you pick, for each of them". Asked for
        // by `PRUEBAS-20` B: *"if I do not select anything, the bot should pick
        // whichever works best for its stats / class"*.
        //
        // And it is not just convenience: it is what makes it possible to hand
        // in a quest with a choice automatically. Without this, the only safe
        // option was to skip those quests -- because picking the same item for
        // four different classes is getting it right for one and handing junk
        // to three, and that cannot be undone.
        //
        // 255 and not 0: 0 is a perfectly valid reward index.
        constexpr uint32 AUTO_REWARD = 255;

        // `force` = COMPLETE AND HAND IN even if they have not finished it.
        //
        // === AND ONLY OVER WHAT YOU YOURSELF ALREADY HANDED IN ==============
        //
        // The forcing is ignored if the MASTER has not been rewarded for that
        // quest. Without that gate the reach was far wider than what was asked
        // for: the trigger for the automatic hand-in is `QUEST_FINISHED`, which
        // in 3.3.5a means *"the dialogue was closed"* and nothing else -- it
        // carries no id at all, and Blizzard's handler only does `HideUIPanel`.
        // So closing the window on an NPC that receives three quests would have
        // completed all three, **including the ones the player is still
        // working on**.
        //
        // The gate is exact and does not need to guess which one you just
        // handed in: by the time this call arrives the core has already
        // rewarded you, so the one you just handed in qualifies, and the ones
        // you are halfway through do not.
        //
        // What it DOES still reach, deliberately: a quest you handed in a while
        // ago at that same NPC and that a bot is missing -- e.g. one that
        // joined the group later. Bringing it up to date is exactly what this
        // exists for.
        //
        // The same gate is also in the client, which filters before sending. It
        // is here because this is the side with authority: the client decides
        // what to ask for, the server decides what is legal.
        //
        // Without it, only whoever already has the quest at COMPLETE hands it
        // in, that is, whoever did the objectives. With it, every companion
        // ends up with the quest done and rewarded, and the path has THREE
        // steps because there are three different ways to fall behind:
        //
        //   1. NOT CARRYING IT    -> the chain is marked for them and it is
        //                            given (same engine as `Share`).
        //   2. MISSING ITEMS      -> they are put in the bag. See below.
        //   3. HALFWAY THROUGH IT -> `Player::CompleteQuest`, which sets the
        //                            status and the log slot.
        //
        // === THE ITEMS ARE NOT A DETAIL: WITHOUT THEM THE CORE REFUSES =======
        //
        // `CompleteQuest` sets the status and nothing else -- it does not
        // conjure the items.
        // And `CanRewardQuest` (`PlayerQuest.cpp`, the `QUEST_SPECIAL_FLAGS_DELIVER`
        // branch) counts what is in the bag again and returns false if anything
        // is missing. Which means forcing the status is NOT enough for a
        // gathering quest: the core would reject it anyway, silently and only
        // for those.
        //
        // So the stacks they are missing are topped up before handing in, and
        // `RewardQuest` destroys them immediately afterwards -- that last part
        // it already did (`DestroyItemCount` over `RequiredItemId` and over
        // `ItemDrop`), which is the other half of what was asked for: that quest
        // items disappear from the bags on hand-in.
        //
        // What is NOT skipped: the whole of `CanRewardQuest`. Bag room for the
        // reward, daily quests, and the money for the ones that COST gold
        // (`GetRewOrReqMoney() < 0`). Forcing the status is one thing; leaving a
        // bot in the red by skipping a check is another.
        //
        // `notes` receives one line per companion, just like `CatchUp`: "2 good
        // and 1 bad" says neither which nor why, and here the why is half the
        // value.
        bool TurnIn(Player* master, ObjectGuid npcGuid, uint32 questId, uint32 reward,
                    std::vector<std::string> const& names,
                    int& okOut, int& failOut,
                    std::vector<std::string>& notes,
                    bool force = false, std::string* why = nullptr);

        // SWITCHING OFF THE QUEST MACHINERY IN EVERY BOT'S AI. Returns how many
        // it reached.
        //
        // IT IS NOT A PREFERENCE: it is what makes "wait until I press it" true.
        // mod-playerbots' `quest` strategy (`QuestStrategies.cpp:27`) responds
        // to the "gossip hello" trigger, and that trigger is armed by the
        // `CMSG_GOSSIP_HELLO` / `CMSG_QUESTGIVER_HELLO` that YOUR client sends
        // when the conversation opens (`PlayerbotAI.cpp:164-165`). Which means
        // that **just by opening the NPC's window**, every bot runs
        // `TalkToQuestGiverAction` against the master's target and HANDS IN
        // right there everything it has completed, picking the reward on its
        // own.
        //
        // Worse: with `AiPlayerbot.SyncQuestWithPlayer = 1` that same action
        // first COMPLETES the bot's quest if yours is complete
        // (`TalkToQuestGiverAction.cpp:39-46`), so the bot does not even need to
        // have done the work.
        //
        // Reported exactly like this: *"i tried to turn a quest and bots auto
        // turned it automatically while i didnt even press the complete
        // button (...) any time i opened the npc's quest window the log said the
        // bots turned the quest"*.
        //
        // NOTHING IS LOST BY REMOVING IT, and that is the reason this is the
        // right way out and not a patch: everything that strategy provided is
        // already done by this module, and tied to a click of yours --
        // `Accept`/`Share` to give quests, `TurnIn` to hand them in. What goes
        // with it is only the path that fired BY ITSELF. Objective credit
        // (killing, gathering) does not go through here: that is the core, not
        // the AI.
        //
        // AND THERE CAN BE NO DOUBLE REWARD, neither before nor now, which was
        // the report's other fear: `Player::RewardQuest` only ever runs behind
        // `CanRewardQuest`, and a true `GetQuestRewardStatus` cuts it off.
        // `TalkToQuestGiverAction::TurnInQuest` itself starts with that same
        // guard. Being paid five times was not happening; what was happening is
        // that they were paid ONCE, without you asking.
        int SetGroupAI(Player* master, bool on);

        // ABANDONING ON BEHALF OF THE GROUP. The other half of "I want the same
        // quest log as them": accepting and handing in already went together,
        // and abandoning did not, so a quest you dropped stayed on all four bots
        // forever.
        //
        // THERE IS NOTHING IN mod-playerbots THAT DOES IT, and this was checked
        // before writing it: there is no handler for
        // `CMSG_QUESTLOG_REMOVE_QUEST` among the `masterIncomingPacketHandlers`
        // (`PlayerbotAI.cpp:160-220`), and the only place a bot drops a quest on
        // its own is `CleanQuestLogAction`, which throws away the GREY ones by
        // level and has nothing to do with anything you do.
        //
        // THE SEQUENCE IS THE CORE'S, COPIED FROM ITS OWN HANDLER
        // (`QuestHandler.cpp:396`, `HandleQuestLogRemoveQuest`) and not
        // invented: `TakeQuestSourceItem` -> `AbandonQuest` (which returns the
        // quest items) -> `RemoveActiveQuest` -> clear the log slot. It is the
        // same rule already followed with the bag swap: when the core has the
        // sequence written down, it is copied from there.
        //
        // `TakeQuestSourceItem` is respected, and it can say NO -- an equipped
        // quest item that cannot be taken off. The core aborts the player's
        // abandon right there, and so do we: leaving the quest half-removed
        // would be worse than not removing it.
        bool Drop(Player* master, uint32 questId,
                  std::vector<std::string> const& names,
                  int& okOut, int& failOut,
                  std::vector<std::string>& notes, std::string* why = nullptr);

        // THE CLASS QUEST THAT IS DUE, on levelling up. Returns the id of the
        // one given, or 0 if there was none or it could not be done.
        //
        // Works for a bot and for the player: the only things it looks at are
        // the quest log and the level, and neither of those knows who is driving
        // the character.
        //
        // === ONLY ONE IN THE LOG ============================================
        //
        // It is the rule that was asked for, and it is also what makes this
        // incapable of doing damage: the log is 25 slots, and a level 40
        // character using this for the first time meets the conditions of a
        // dozen class quests at once. Without the cap, the first level it gained
        // would fill the log in one go with quests scattered across half the
        // world.
        //
        // With the cap, the rhythm is: one on levelling up, you do it, you hand
        // it in at your trainer AS ALWAYS -- this does not touch the hand-in --
        // and the next one arrives on the next level up.
        //
        // === THE MISSING LINKS ARE DONE, NOT FAKED ==========================
        //
        // If the one that is due hangs off others they did not do, those are
        // done in full first: give it, complete it and CLAIM IT. The reason is
        // in the body, and in one line it is that the reward of a class quest is
        // usually a spell no trainer sells -- just marking them would leave a
        // warlock with no minions and a druid with no bear form.
        uint32 GrantClassQuest(Player* who);

        // ONE ROW OF SOMEBODY'S LOG. What the window needs to draw a line and
        // nothing more.
        struct Entry
        {
            std::string name;               // whose log it is
            uint32      questId = 0;
            std::string title;
            std::string zone;               // empty if it is a class quest or has none
            uint8       status = ST_DOING;  // only ST_DOING or ST_READY
            bool        classQuest = false;
        };

        // THE QUEST LOG OF THE WHOLE GROUP, THE MASTER INCLUDED.
        //
        // It is the one thing that could not be seen: your quests are already
        // drawn by the game's log, and your companions' are drawn by nobody.
        //
        // The 25 SLOTS are read and not `m_QuestStatus`, which is the difference
        // between "what they are carrying" and "what they have ever touched".
        // The why is in the body.
        //
        // The zone comes from `ZoneOrSort` when it is positive. Class quests go
        // with an empty zone ON PURPOSE: they are their own group, they were
        // asked for as their own group, and several of them do not even have a
        // zone in the data.
        bool Registry(Player* master, std::vector<Entry>& out);

        // CALLING IT DONE AND PAID, WITH NO NPC AND WITHOUT GOING ANYWHERE.
        //
        // === HOW IT DIFFERS FROM `TurnIn(force)` ============================
        //
        // `TurnIn` needs an NPC in front of you that receives that quest, and
        // besides it only forces what YOU already handed in -- a gate that
        // exists because its trigger is "the dialogue was closed", which does
        // not say which one (see the `TurnIn` note above).
        //
        // Here there is neither of those two things, and it is not an oversight:
        // the trigger is a button in a row that NAMES the quest and NAMES the
        // character. There is nothing to guess, so there is nothing to protect
        // against. It was the explicit decision when this window was asked for
        // -- *"completar y cobrar, ahi mismo"*.
        //
        // What is STILL not skipped is `CanRewardQuest`: bag room, dailies and
        // the gold for the ones that cost money. And any missing items are put
        // in first, because otherwise the core silently rejects the gathering
        // ones. Both things are explained in `TurnIn`.
        //
        // The reward to choose is set by `BestReward`, per character.
        bool ForceFinish(Player* master, uint32 questId,
                         std::vector<std::string> const& names,
                         int& okOut, int& failOut,
                         std::vector<std::string>& notes, std::string* why = nullptr);
    }
}

#endif  // MOD_RTS_QUESTS_H
