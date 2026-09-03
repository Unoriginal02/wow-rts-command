#ifndef MOD_RTS_ORDERS_H
#define MOD_RTS_ORDERS_H

#include "ObjectGuid.h"

#include <string>

class Player;
class WorldObject;

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

        // Todo a cero: estrategias de fabrica, sin anclajes, siguiendote.
        //
        // Es lo unico que arregla un bot con un rol viejo pegado, porque las
        // estrategias sobreviven al relogueo y no se ven desde el cliente. Ver
        // `rts::bots::Reset`.
        bool ResetBot(Player* master, std::string const& botName);

        // Every bot in the master's group loots everything, greys included --
        // or back to the default "only what it can use".
        //
        // This is the loot STRATEGY (what a bot bothers to pick up), which is
        // not the same thing as the group's loot METHOD (who is allowed to).
        // Both were needed and they fought each other: see the note next to
        // AiPlayerbot.FreeMethodLoot in playerbots.conf.
        //
        // Returns the number of bots changed.
        int SetGroupLoot(Player* master, bool everything);

        // Where every bot in the master's group is, right now.
        //
        // The addon can normally read this from rts_core, but only for units
        // the CLIENT can see -- and a bot walking a long route leaves the
        // visibility bubble, at which point the addon stops being able to tell
        // whether it arrived. A route then advances only on its 40-second
        // timeout, which in game looks exactly like "the bot forgot it was
        // walking".
        //
        // The server never loses track. One string, all bots, so a route can
        // poll it a couple of times a second for the price of one packet:
        //
        //   "name,x,y,z;name,x,y,z"
        std::string GroupPositions(Player* master);

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

        // Soltar lo que sea que este poseyendo, sin saber su nombre ni mirar el
        // grupo. Para las salidas del nucleo (logout, cambio de mapa): un charm
        // sin aura que llegue a `Player::RemoveFromWorld` MATA EL WORLDSERVER
        // con un ABORT. El porque, entero, en el .cpp.
        bool ReleaseAnyPossession(Player* master);
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

        // Baja una Z al suelo que `who` tiene permitido pisar. UN SOLO SITIO lo
        // decide, y lo usan tanto las ordenes como los marcadores de ruta: si el
        // marcador y el destino no usaran la misma cuenta, el bot se pararia en
        // un sitio distinto del que la marca ensena, que es peor que no tener
        // marca.
        void GroundZ(WorldObject const* who, float x, float y, float& z);

        // DONDE CORTA EL SUELO EL RAYO DEL CURSOR, decidido con los mapas del
        // SERVIDOR y no con lo que el cliente cree ver.
        //
        // El addon sabe dos cosas exactas -- el pixel del cursor (se lo dice
        // Lua) y la base de la camara (se la publica rts_core) -- y con ellas
        // arma un rayo que es correcto por construccion. Lo que NO puede es
        // cortarlo contra el terreno: en Lua no hay mapa, asi que hasta ahora
        // se cortaba contra un PLANO horizontal, y un plano no es una colina.
        // De ahi el fallo que se veia en juego: pinchar en la cara de un
        // monticulo y que el punto acabara detras de el y bajo tierra.
        //
        // Aqui si hay mapa. Se anda el rayo contra la altura del terreno y
        // contra los modelos de colision (WMO y doodads), se coge el corte mas
        // cercano, y ese es el sitio. Ademas es el suelo que el bot va a pisar,
        // que es la unica definicion de "ahi" que importa.
        bool GroundRay(Player const* who,
                       float ox, float oy, float oz,
                       float dx, float dy, float dz,
                       float maxDist,
                       float& hx, float& hy, float& hz);

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

        // ¿Ese bot esta en "Esperar" (la estrategia `passive` de playerbots)?
        //
        // EXISTE PARA QUE UNA ORDEN IGNORADA NO SEA SILENCIOSA. `AttackBot`
        // dispara la accion de ataque del propio bot y eso funciona aunque este
        // pasivo -- pero lo que SOSTIENE la pelea son sus estrategias, y
        // `passive` las anula todas. Asi que el bot sale, llega, y se queda
        // parado: la orden reporto exito y en pantalla no paso nada. Es
        // indistinguible de "la orden no llego", y en PRUEBAS-18 se reporto
        // justo asi ("no se el motivo, puede ser que no tenga los bots en modo
        // de que ataquen a mi orden"). No se corrige por nuestra cuenta -- el
        // rol lo puso el jugador -- se DICE.
        bool IsPassive(Player* master, std::string const& botName);

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

        // Cast one of the player's OWN spells, from the console's skill row.
        //
        // WHY THE SERVER AND NOT THE CLIENT. `CastSpellByName` is protected in
        // 3.3.5a, and the usual way round that -- a secure action button -- does
        // not fit here: the row's contents change with the selection, and
        // changing a secure button's attributes is blocked IN COMBAT, which is
        // exactly when the row is used. The bots' half of the row already goes
        // through the server (CastAs), so this makes both halves the same shape
        // rather than adding a second mechanism.
        //
        // `targetGuid` may be empty, in which case the player's own selection is
        // used, and a friendly-or-missing target falls back to a self-cast the
        // same way CastAs does.
        bool SelfCast(Player* player, uint32 spellId, ObjectGuid targetGuid,
                      std::string* why = nullptr);
        // Walks into range first when the target is too far, and completes the
        // interaction on arrival -- a right-click on a distant NPC should mean
        // "go and talk to it", not nothing at all.
        bool SelfInteract(Player* player, ObjectGuid targetGuid);

        // Finishes interactions that had to walk. Called from the world tick.
        void UpdatePending(uint32 diff);
    }
}

#endif  // MOD_RTS_ORDERS_H
