#ifndef MOD_RTS_ORDERS_H
#define MOD_RTS_ORDERS_H

#include "ObjectGuid.h"

#include <string>

class Player;

namespace rts
{
    // Orders issued straight into a bot's AI, instead of through chat.
    //
    // Every order used to be a whispered playerbots command, which cost three
    // things the RTS layer cannot afford:
    //
    //   * an EMOTE. PlayerbotAI::TellMaster turns the bot to face you and plays
    //     EMOTE_ONESHOT_TALK before it does anything (PlayerbotAI.cpp:3066), and
    //     both halves of a move order -- `stay` and `position` -- reply. So every
    //     click made the bot stop, turn, and mime a conversation first.
    //   * LATENCY. Outgoing chat is spaced 0.15s per message or the client's own
    //     throttle silently eats some, so a four-bot order took most of a second
    //     to leave the client.
    //   * PRECISION. `position` parses its coordinates with atoi, so anchors
    //     landed on whole yards.
    //
    // Setting the same state directly costs none of those. This is only possible
    // because every module compiles into one `modules` target with a shared
    // include path, so mod-rts can reach mod-playerbots' own API.
    namespace orders
    {
        // Anchor a bot at a world position: switch on its stay strategy and put
        // the stay position where we want it. The bot then walks there under its
        // own "return to stay position" behaviour and holds, so nothing drags it
        // home afterwards.
        //
        // `master` is the commanding player; the bot must be in their group.
        bool MoveBot(Player* master, std::string const& botName, float x, float y, float z);

        // Release a bot back to following its master.
        bool FollowBot(Player* master, std::string const& botName);

        // Send a bot at one specific unit.
        //
        // The `attack` chat command cannot do this: it resolves as "attack my
        // target" and reads the MASTER's current target (AttackAction.cpp:39),
        // so right-clicking an enemy only ever worked if that enemy already
        // happened to be your target. Naming the victim explicitly is the whole
        // point of clicking on it.
        bool AttackBot(Player* master, std::string const& botName, ObjectGuid targetGuid);

        // Advance to a point, engaging things met on the way. There is no
        // attack-move verb in playerbots, so this is an approximation: the
        // destination anchor plus `grind`, which makes a bot pick fights near
        // it. Honest about its failure mode -- a bot can be distracted onto
        // something off the path and the anchor then pulls it back.
        bool AttackMoveBot(Player* master, std::string const& botName, float x, float y, float z);

        // Take direct control of a bot: stand its AI down and hand the client
        // the reins. The same possession the RTS camera uses, pointed at a
        // Player instead of an invisible creature (Unit.cpp:14610 permits it).
        bool PossessBot(Player* master, std::string const& botName);
        bool ReleaseBot(Player* master, std::string const& botName);
        bool ReleaseAll(Player* master);

        // Move the commanding player's OWN character.
        //
        // Only possible while the RTS camera holds client control: the body is
        // then just another server-driven unit, so it takes ordinary creature
        // movement. Without the camera the client owns the character and the
        // server moving it would fight the player's own input.
        // `why` receives a short reason on failure, so a silent no-op in game
        // can be diagnosed from the chat frame instead of guessed at.
        bool MoveSelf(Player* player, float x, float y, float z, std::string* why = nullptr);

        // Undo everything this module did to a player's bots. For logout.
        void ForgetPlayer(Player* master);

        // What a right-click on `targetGuid` should mean.
        //
        // The addon cannot work this out in RTS mode. Its mouse-catcher frame
        // swallows the mouse, so the client never sets "mouseover" and Lua has
        // no way to ask whether an arbitrary GUID is hostile -- a GUID only
        // becomes a unit token if it is already your target, mouseover, or in
        // your party. Confirmed in game: the cursor halo colours correctly
        // OUTSIDE RTS mode and never inside it.
        //
        // The server has always known. So the click is sent here undecided and
        // classified with real information.
        enum ClickIntent
        {
            CLICK_MOVE = 0,       // nothing clickable -- go to the point
            CLICK_ATTACK = 1,
            CLICK_INTERACT = 2,   // friendly NPC
        };

        ClickIntent ClassifyClick(Player* master, ObjectGuid targetGuid);

        // Send a bot to talk to an NPC. Same shape as AttackBot, and it failed
        // for the same reason before: GossipHelloAction reads the MASTER's
        // target (GossipHelloAction.cpp:22), which was never set, so `talk`
        // arrived and found nobody to talk to.
        bool TalkBot(Player* master, std::string const& botName, ObjectGuid targetGuid);

        // The commanding player's OWN character doing the same things. In RTS
        // mode you are a unit like the others, so a click has to mean the same
        // for you -- but your body is server-driven while the camera holds
        // client control, so it cannot use the normal client paths.
        bool SelfAttack(Player* player, ObjectGuid targetGuid);
        // Walks into range first when the target is too far, and completes the
        // interaction on arrival -- a right-click on a distant NPC should mean
        // "go and talk to it", not nothing at all.
        bool SelfInteract(Player* player, ObjectGuid targetGuid);

        // Finishes interactions that had to walk. Called from the world tick.
        void UpdatePending(uint32 diff);
    }
}

#endif  // MOD_RTS_ORDERS_H
