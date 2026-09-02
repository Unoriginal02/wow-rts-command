#ifndef MOD_RTS_COMMAND_MODE_H
#define MOD_RTS_COMMAND_MODE_H

#include "Define.h"
#include "ObjectGuid.h"

#include <string>
#include <vector>

class Player;

namespace rts
{
    // Command mode -- borrowing one bot's spellbook for a few seconds.
    //
    // NOT possession. Nothing is charmed, no client control changes hands, and
    // the camera therefore never moves: you stay exactly where you were, in RTS
    // mode, looking at the battle. That is the whole point. Full possession is
    // a heavyweight handoff and the wrong shape for "overheal the tank, then
    // get back to directing".
    //
    // The bar you get is the bot's OWN action bar, out of character_action --
    // the bars you set up when you last played that character. That is better
    // than anything this module could generate: you curate them by playing, and
    // the order is one you chose. Note that mod-playerbots never reads action
    // bars to decide what to cast (verified: only shaman totems touch them, and
    // only as storage), so arranging them changes nothing about the bot's own
    // behaviour -- they exist purely as a record of your preference.
    //
    // Suppression is deliberately lazy. Selecting a bot does NOT stop it;
    // casting through it does, and only until you stop. You take the wheel by
    // using it, and let go by not.
    namespace command
    {
        // Spell ids off the bot's action bars, in bar order, duplicates removed.
        // Only ids -- the client turns them into names and icons itself with
        // GetSpellInfo, so nothing but numbers has to cross the wire.
        std::vector<uint32> ActionBarSpells(Player* master, std::string const& botName);

        // Cast one of the bot's spells. `targetGuid` may be empty, in which case
        // the bot's own current target is used.
        bool CastAs(Player* master, std::string const& botName, uint32 spellId,
                    ObjectGuid targetGuid, std::string* why = nullptr);

        // Who the commanded bot currently has selected -- what it is hitting or
        // healing. Empty when it has nobody.
        std::string CurrentTargetName(Player* master, std::string const& botName);

        // Everything the group is currently pointed at, deduplicated, with how
        // many of your units are on each.
        //
        // This is the whole fight in one list: enemies being attacked, and
        // allies being healed, because "who is my healer looking after" is the
        // same question as "who is my warrior hitting" and the answer lives in
        // the same field. Friendly entries are how a heal target gets picked.
        struct Engaged
        {
            ObjectGuid guid;
            std::string name;
            int count = 0;       // how many of your units are on it
            uint8 healthPct = 0;
            bool hostile = false;
            bool isPlayer = false;
        };

        std::vector<Engaged> GroupTargets(Player* master);

        // Point one bot at something. Used when you click an entry in that
        // list: the bot selects it, and your casts then go to it.
        //
        // This is the PUNCTUAL half of the right-click gesture: the bot's own
        // selection is what an explicitly targeted CastAs overrides for one
        // cast, so nothing here has to be undone -- the bot's next AI tick
        // picks its own target again and the rotation carries on. "Goes back to
        // what it was doing" is the default, not a thing we implement.
        bool Aim(Player* master, std::string const& botName, ObjectGuid targetGuid);

        // === roles ==========================================================
        //
        // A role is a playerbots COMBAT STRATEGY, not something this module
        // invents: `tank`, `dps`, `heal` and `cc` are registered per class in
        // mod-playerbots' own class contexts (DruidAiObjectContext.cpp:34,
        // PaladinAiObjectContext.cpp:93-95, and so on), and `passive` is the
        // one the borrow-a-bot path above already uses to stand a bot down.
        //
        // WHICH ONES A BOT HAS IS ASKED, NOT ASSUMED. A warrior has no `heal`
        // and a mage no `tank`, and writing that table by class in the addon
        // would be fifty names from memory -- the mistake this project keeps
        // paying for. `AiObjectContext::GetSupportedStrategies()` answers it
        // for the bot in front of us, so the addon draws what exists.
        struct Role
        {
            std::string name;      // the playerbots strategy name
            bool active = false;   // on right now, in BOT_STATE_COMBAT
        };

        std::vector<Role> Roles(Player* master, std::string const& botName);

        // Turn one on or off. `tank`, `dps` and `heal` are mutually exclusive --
        // they are the class's combat stance and playerbots' own `co` command
        // treats them the same way -- while `cc` and `passive` are independent
        // toggles that ride on top.
        bool SetRole(Player* master, std::string const& botName,
                     std::string const& role, bool on);

        // === persistent focus ===============================================
        //
        // The other half of the right-click gesture: this target is what the
        // bot works on until told otherwise, rather than for one cast.
        //
        // BOTH DIRECTIONS ARE PLAYERBOTS' OWN MACHINERY, which is why this is
        // twenty lines and not a scheduler:
        //
        //   hostile  -> orders::AttackBot, the bot's own `attack my target`
        //               action. Sticky by construction: the AI keeps at it.
        //   friendly -> the `focus heal targets` value plus the strategy of the
        //               same name (TargetValue.h:161, StrategyContext.h:132).
        //               That is exactly "look after this one", and it already
        //               exists because `focus heal` is a chat command.
        //
        // Re-asserting SetSelection on a tick was the obvious alternative and
        // would have fought the bot's own targeting every tick to a draw.
        //
        // `hostile` reports which of the two paths was taken, so the addon can
        // say so instead of the player guessing why a healer did not charge.
        bool SetFocus(Player* master, std::string const& botName,
                      ObjectGuid targetGuid, bool* hostile = nullptr);

        // Drop a persistent focus. Only the friendly half needs undoing: an
        // attack order finishes by itself when the victim dies.
        bool ClearFocus(Player* master, std::string const& botName);

        // Hand the bot back to its own AI. Safe to call when it never took over.
        void Release(Player* master, std::string const& botName);
        void ReleaseAll(Player* master);

        // Drives the idle timeout.
        void Update(uint32 diff);
    }
}

#endif  // MOD_RTS_COMMAND_MODE_H
