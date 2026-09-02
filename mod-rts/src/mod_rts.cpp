/*
 * mod-rts -- server side of the RTS command layer.
 *
 * The client half of this project is an addon (RTSCommand) plus an injected
 * DLL (rts_core). Those two can do everything that is purely client-local --
 * selection UI, world->screen projection, model tints -- and nothing that
 * requires authority. This module is the authority half.
 *
 * === the channel =========================================================
 *
 * The addon talks to us with ordinary addon messages:
 *
 *     SendAddonMessage("RTS", "CAM ON", "WHISPER", UnitName("player"))
 *
 * which arrive here as a whisper carrying LANG_ADDON, with the payload packed
 * as "PREFIX\tBODY". We swallow ours and let everything else through.
 *
 * This replaces nothing on the client side: model tints still come back over
 * rts_core's CVar channel, because that one is client-local and the server has
 * no business in it. What this buys is real bandwidth in the direction that was
 * previously a 30-bit integer squeezed through a PvP toggle.
 */

#include "Chat.h"
#include "CommandScript.h"
#include "Config.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "PlayerScript.h"
#include "RBAC.h"
#include "RtsCamera.h"
#include "RtsCommandMode.h"
#include "RtsMarks.h"
#include "RtsOrders.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldScript.h"
#include "WorldSession.h"

#include <cctype>
#include <cstdlib>
#include <vector>

#include <iomanip>
#include <sstream>
#include <string>

using namespace Acore::ChatCommands;

namespace
{
    constexpr char const* kPrefix = "RTS";

    // Bumped whenever this module changes. There are three separately-built
    // pieces in this project -- the DLL, this module, and the addon -- and only
    // the DLL had a version you could see, which made a server-side fix look
    // like nothing had happened. All three now report.
    constexpr char const* kModVersion = "0.15.0";

    std::string Upper(std::string s)
    {
        for (char& c : s)
            c = static_cast<char>(::toupper(static_cast<unsigned char>(c)));
        return s;
    }

    // "CAM ON" -> verb "CAM", rest "ON". Case-insensitive on the verb so the
    // addon does not have to care.
    void Split(std::string const& body, std::string& verb, std::string& rest)
    {
        std::size_t const sp = body.find(' ');
        if (sp == std::string::npos)
        {
            verb = Upper(body);
            rest.clear();
            return;
        }
        verb = Upper(body.substr(0, sp));
        rest = body.substr(sp + 1);
    }

    // Human-readable, straight to the chat frame.
    void Reply(Player* player, std::string const& text)
    {
        if (!player)
            return;
        ChatHandler(player->GetSession()).SendSysMessage(text.c_str());
    }

    // Machine-readable, back down the same addon channel. The addon must not
    // assume its request succeeded -- enabling the camera can legitimately fail
    // -- and it has real work to do on the transition (the turn keys), so it
    // needs the true state rather than an optimistic guess.
    void SendAddon(Player* player, std::string const& body)
    {
        if (!player || !player->GetSession())
            return;

        WorldPacket data;
        ChatHandler::BuildChatPacket(
            data, CHAT_MSG_WHISPER, std::string(kPrefix) + "\t" + body,
            LANG_ADDON, CHAT_TAG_NONE,
            player->GetGUID(), player->GetName(),
            player->GetGUID(), player->GetName());
        player->GetSession()->SendPacket(&data);
    }

    void ReportCamera(Player* player)
    {
        SendAddon(player, rts::camera::IsActive(player) ? "CAM 1" : "CAM 0");
    }

    std::vector<std::string> SplitList(std::string const& s, char sep)
    {
        std::vector<std::string> out;
        std::size_t start = 0;
        while (start <= s.size())
        {
            std::size_t const end = s.find(sep, start);
            std::string const part = s.substr(start, end == std::string::npos
                                                     ? std::string::npos : end - start);
            if (!part.empty())
                out.push_back(part);
            if (end == std::string::npos)
                break;
            start = end + 1;
        }
        return out;
    }

    // "MOVE Bot 12.3 45.6 7.8;Other 1.0 2.0 3.0"
    //
    // The whole group's order rides in ONE message. Through chat this was one
    // whisper per bot at 0.15s apart, so a four-bot order took most of a second
    // to leave the client; here it is a single packet and the bots turn at the
    // same instant, which is most of what makes an RTS feel responsive.
    bool DispatchMove(Player* player, std::string const& rest)
    {
        std::size_t start = 0;
        int moved = 0;

        while (start <= rest.size())
        {
            std::size_t const end = rest.find(';', start);
            std::string const entry = rest.substr(start, end == std::string::npos
                                                        ? std::string::npos : end - start);
            if (!entry.empty())
            {
                std::istringstream in(entry);
                std::string name;
                float x = 0.0f, y = 0.0f, z = 0.0f;
                if ((in >> name >> x >> y >> z) && rts::orders::MoveBot(player, name, x, y, z))
                    ++moved;
            }

            if (end == std::string::npos)
                break;
            start = end + 1;
        }

        return moved > 0;
    }

    // "ATTACK <guid-hex> Name;Other" -- everyone selected goes for the same
    // named victim, which is what right-clicking an enemy should mean.
    bool DispatchAttack(Player* player, std::string const& rest)
    {
        std::istringstream in(rest);
        std::string guidHex, names;
        if (!(in >> guidHex >> names))
            return false;

        uint64 raw = 0;
        {
            std::istringstream hex(guidHex);
            hex >> std::hex >> raw;
        }
        if (!raw)
            return false;

        ObjectGuid const target(raw);
        int hit = 0, idle = 0;
        for (std::string const& n : SplitList(names, ';'))
        {
            if (rts::orders::AttackBot(player, n, target))
                ++hit;
            if (rts::orders::IsPassive(player, n))
                ++idle;
        }
        if (idle > 0)
            Reply(player, "RTS: " + std::to_string(idle) +
                  " en Esperar (passive) -- van, pero no pelean solos.");
        return hit > 0;
    }

    bool DispatchFollow(Player* player, std::string const& rest)
    {
        std::size_t start = 0;
        int done = 0;

        while (start <= rest.size())
        {
            std::size_t const end = rest.find(';', start);
            std::string const name = rest.substr(start, end == std::string::npos
                                                       ? std::string::npos : end - start);
            if (!name.empty() && rts::orders::FollowBot(player, name))
                ++done;

            if (end == std::string::npos)
                break;
            start = end + 1;
        }

        return done > 0;
    }

    bool Dispatch(Player* player, std::string const& body)
    {
        std::string verb, rest;
        Split(body, verb, rest);

        // --- command mode -------------------------------------------------
        // "BARS <bot>" -> the bot's own action-bar spell ids, so the addon can
        // build a bar from what YOU arranged when you last played it.
        if (verb == "BARS")
        {
            auto const spells = rts::command::ActionBarSpells(player, rest);
            if (spells.empty())
            {
                SendAddon(player, "BARS " + rest + " -");
                return true;
            }

            // Chunked: an addon message caps at 255 characters and a full bar
            // of six-digit ids does not fit in one.
            std::string chunk;
            for (uint32 id : spells)
            {
                std::string const piece = std::to_string(id);
                if (chunk.size() + piece.size() + 2 > 200)
                {
                    SendAddon(player, "BARS " + rest + " " + chunk);
                    chunk.clear();
                }
                if (!chunk.empty())
                    chunk += ",";
                chunk += piece;
            }
            if (!chunk.empty())
                SendAddon(player, "BARS " + rest + " " + chunk);
            SendAddon(player, "BARSEND " + rest);
            return true;
        }

        // "CAST <bot> <spellid> [targetGuidHex]"
        if (verb == "CAST")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            uint32 spellId = 0;
            if (!(in >> bot >> spellId))
                return false;

            ObjectGuid target;
            if (in >> guidHex)
            {
                uint64 raw = 0;
                std::istringstream hx(guidHex);
                hx >> std::hex >> raw;
                if (raw)
                    target = ObjectGuid(raw);
            }

            std::string why;
            if (!rts::command::CastAs(player, bot, spellId, target, &why))
                Reply(player, "RTS: " + why + ".");
            return true;
        }

        // "TGTS" -- everything the group is engaged with, for the targets panel.
        // Chunked, because a busy fight will not fit in one addon message.
        if (verb == "TGTS")
        {
            auto const list = rts::command::GroupTargets(player);
            std::string chunk;

            for (auto const& e : list)
            {
                std::ostringstream one;
                one << std::hex << e.guid.GetRawValue() << std::dec
                    << ',' << e.count
                    << ',' << static_cast<int>(e.healthPct)
                    << ',' << (e.hostile ? 1 : 0)
                    << ',' << (e.isPlayer ? 1 : 0)
                    << ',' << e.name;

                std::string const piece = one.str();
                if (chunk.size() + piece.size() + 2 > 200)
                {
                    SendAddon(player, "TGTS " + chunk);
                    chunk.clear();
                }
                if (!chunk.empty())
                    chunk += ";";
                chunk += piece;
            }

            if (!chunk.empty())
                SendAddon(player, "TGTS " + chunk);
            SendAddon(player, "TGTEND");
            return true;
        }

        // "AIM <bot> <guid-hex>" -- point a bot at something you clicked in the
        // targets panel, so your casts then go to it.
        if (verb == "AIM")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            if (!(in >> bot >> guidHex))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (raw)
                rts::command::Aim(player, bot, ObjectGuid(raw));
            return true;
        }

        // "SELFCAST <spellId> [guid-hex]" -- the console's skill row, aimed at
        // the player's own character. See RtsOrders.h for why this is not the
        // client's job.
        if (verb == "SELFCAST")
        {
            std::istringstream in(rest);
            uint32 spellId = 0;
            std::string guidHex;
            if (!(in >> spellId))
                return false;

            ObjectGuid target;
            if (in >> guidHex)
            {
                uint64 raw = 0;
                std::istringstream hx(guidHex);
                hx >> std::hex >> raw;
                if (raw)
                    target = ObjectGuid(raw);
            }

            // SE CONTESTA TAMBIEN CUANDO SALE BIEN, y no es ruido: un
            // lanzamiento del servidor sobre tu propio cuerpo puede no producir
            // ninguna senal visible en el cliente -- ni animacion, ni barra de
            // lanzamiento -- asi que "no ha pasado nada" y "no ha llegado la
            // orden" se veian igual. PRUEBAS-18 C10 se reporto sin poder
            // distinguir cual de las dos era.
            std::string why;
            if (!rts::orders::SelfCast(player, spellId, target, &why))
                Reply(player, "RTS: " + why + ".");
            else
                SendAddon(player, "DID SELFCAST " + std::to_string(spellId));
            return true;
        }

        // "ROLES <bot>" -- which of the five roles that bot's CLASS actually
        // has, and which are on. Asked, never assumed: see RtsCommandMode.h.
        //
        // Reply "ROLES <bot> name:0,name:1,..." or "ROLES <bot> -" when the bot
        // has none we recognise. The empty answer is SENT rather than skipped:
        // a row that never draws because no reply came looks identical to a row
        // that never draws because the class has no roles, and only one of
        // those is a bug.
        if (verb == "ROLES")
        {
            auto const roles = rts::command::Roles(player, rest);
            std::string list;
            for (auto const& r : roles)
            {
                if (!list.empty())
                    list += ",";
                list += r.name + ":" + (r.active ? "1" : "0");
            }
            SendAddon(player, "ROLES " + rest + " " + (list.empty() ? std::string("-") : list));
            return true;
        }

        // "ROLE <bot> <name> <0|1>" -- set one. Answers with a fresh ROLES, so
        // the addon draws what the server ended up with instead of what it
        // asked for: turning on a stance turns two others off, and a button
        // that lit up on its own request would hide that.
        if (verb == "ROLE")
        {
            std::istringstream in(rest);
            std::string bot, role;
            int on = 0;
            if (!(in >> bot >> role >> on))
                return false;

            if (!rts::command::SetRole(player, bot, role, on != 0))
                Reply(player, "RTS: no pude cambiar el rol " + role + ".");

            auto const roles = rts::command::Roles(player, bot);
            std::string list;
            for (auto const& r : roles)
            {
                if (!list.empty())
                    list += ",";
                list += r.name + ":" + (r.active ? "1" : "0");
            }
            SendAddon(player, "ROLES " + bot + " " + (list.empty() ? std::string("-") : list));
            return true;
        }

        // "PFOCUS <bot> <guid-hex>" -- persistent focus, the double-right-click
        // half of the gesture. "PFOCUS <bot> -" drops it.
        if (verb == "PFOCUS")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            if (!(in >> bot >> guidHex))
                return false;

            if (guidHex == "-")
            {
                rts::command::ClearFocus(player, bot);
                SendAddon(player, "PFOCUS " + bot + " - 0");
                return true;
            }

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return true;

            bool hostile = false;
            if (rts::command::SetFocus(player, bot, ObjectGuid(raw), &hostile))
                SendAddon(player, "PFOCUS " + bot + " " + guidHex + " " + (hostile ? "1" : "0"));
            else
                Reply(player, "RTS: no pude fijar ese foco.");
            return true;
        }

        // "FOCUS <bot>" -- what that bot is currently pointed at.
        if (verb == "FOCUS")
        {
            std::string const name = rts::command::CurrentTargetName(player, rest);
            SendAddon(player, "FOCUS " + (name.empty() ? std::string("-") : name));
            return true;
        }

        if (verb == "UNCOMMAND")
        {
            rts::command::ReleaseAll(player);
            return true;
        }

        // "WHAT <guid-hex>" -- is this thing hostile, talkable, or scenery?
        //
        // The cursor halo colours itself from the client's own mouseover, which
        // does not exist in RTS mode (the catcher frame eats it), so the halo
        // stayed green over everything. Same answer as the click: ask the side
        // that knows. The addon caches per guid, so a cursor resting on a wolf
        // costs one round trip, not one per frame.
        if (verb == "WHAT")
        {
            uint64 raw = 0;
            { std::istringstream hx(rest); hx >> std::hex >> raw; }
            if (!raw)
                return true;

            auto const intent = rts::orders::ClassifyClick(player, ObjectGuid(raw));
            SendAddon(player, "WHAT " + rest + " " + std::to_string(static_cast<int>(intent)));
            return true;
        }

        // "GROUND <id> <ox> <oy> <oz> <dx> <dy> <dz>" -- donde corta el suelo
        // este rayo. Lo pregunta el addon cada vez que convierte un click en un
        // punto del mundo sin mandar orden (shift + click derecho encadena un
        // punto de ruta y no manda nada todavia), y contesta con el mismo id
        // para que el punto que se corrige sea el que se pregunto y no el que
        // este de moda cuando llegue la respuesta.
        if (verb == "GROUND")
        {
            std::istringstream in(rest);
            uint32 id = 0;
            float ox, oy, oz, dx, dy, dz;
            if (!(in >> id >> ox >> oy >> oz >> dx >> dy >> dz))
                return false;

            float gx, gy, gz;
            if (rts::orders::GroundRay(player, ox, oy, oz, dx, dy, dz, 500.0f, gx, gy, gz))
            {
                // Sin el '1' del final: aqui no se ha mandado ninguna orden, asi
                // que si alguien iba hacia ese punto hay que remandarselo.
                std::ostringstream out;
                out << "GROUNDAT " << id << ' ' << std::fixed << std::setprecision(2)
                    << gx << ' ' << gy << ' ' << gz << " 0";
                SendAddon(player, out.str());
            }
            else
            {
                SendAddon(player, "GROUNDNO " + std::to_string(id));
            }
            return true;
        }

        if (verb == "VERSION")
        {
            SendAddon(player, std::string("VER ") + kModVersion);
            return true;
        }

        // "CLICK <guid-hex|0> <x> <y> <z> Name;Other"
        //
        // A right-click, sent undecided. The addon cannot classify the target
        // in RTS mode -- its catcher frame swallows mouseover, so the client
        // never tells it whether that thing is hostile. Here it can just be
        // looked up. See RtsOrders::ClassifyClick.
        // "CLICK <guid-hex|0> <Name x y z;Other x y z>"
        //
        // A right-click, sent undecided, with a DESTINATION PER UNIT. The addon
        // cannot classify the target in RTS mode -- its catcher frame swallows
        // mouseover, so the client never says whether that thing is hostile --
        // but it CAN work out where each unit should stand, and it must, or a
        // group order piles everyone onto one coordinate. That is exactly what
        // happened when this verb first carried a single point.
        if (verb == "CLICK")
        {
            std::istringstream in(rest);
            std::string guidHex, list;
            if (!(in >> guidHex))
                return false;
            std::getline(in, list);

            uint64 raw = 0;
            { std::istringstream hex(guidHex); hex >> std::hex >> raw; }
            ObjectGuid const target(raw);

            auto const intent = rts::orders::ClassifyClick(player, target);

            struct Dest { std::string name; float x, y, z; };
            std::vector<Dest> dests;

            // EL RAYO VIAJA CON EL CLICK, y es lo que hace que el destino sea el
            // suelo de verdad y no el corte con un plano.
            //
            // El addon manda los puntos que el calcula porque necesita dibujar
            // algo AHORA, y ademas es quien sabe donde va cada unidad dentro de
            // la formacion. Pero su punto base sale de cortar el rayo del cursor
            // contra un plano horizontal, que en una cuesta cae detras de la
            // cuesta y bajo tierra. Aqui hay mapas: se corta el mismo rayo
            // contra el terreno y los modelos, y todos los destinos se desplazan
            // en bloque por la diferencia -- asi la formacion se conserva entera
            // y solo se corrige de donde cuelga.
            //
            // Va en un tramo final marcado con '@' en vez de delante para que la
            // parte de siempre se lea igual que antes y un mensaje sin rayo siga
            // valiendo.
            uint32 rayId = 0;
            bool haveRay = false, fixed = false;
            float sx = 0.0f, sy = 0.0f, sz = 0.0f;   // el desplazamiento
            float gx = 0.0f, gy = 0.0f, gz = 0.0f;   // el suelo resuelto

            for (std::string const& entry : SplitList(list, ';'))
            {
                std::istringstream e(entry);
                std::string head;
                if (!(e >> head))
                    continue;

                if (head == "@")
                {
                    float ox, oy, oz, dx, dy, dz, bx, by, bz;
                    if (!(e >> rayId >> ox >> oy >> oz >> dx >> dy >> dz >> bx >> by >> bz))
                        continue;
                    haveRay = true;
                    if (rts::orders::GroundRay(player, ox, oy, oz, dx, dy, dz, 500.0f, gx, gy, gz))
                    {
                        fixed = true;
                        sx = gx - bx;
                        sy = gy - by;
                        sz = gz - bz;
                    }
                    continue;
                }

                Dest d;
                d.name = head;
                if (e >> d.x >> d.y >> d.z)
                    dests.push_back(d);
            }

            if (fixed)
            {
                for (Dest& d : dests)
                {
                    d.x += sx;
                    d.y += sy;
                    d.z += sz;
                }

                // Y al addon, para que el aro y el numero de la ruta se pongan
                // donde de verdad esta el punto en vez de donde se supuso.
                //
                // El '1' del final dice "la orden YA salio con esto". Sin el, el
                // addon volveria a mandar el tramo al corregir el dibujo, o sea
                // una segunda orden 100 ms despues de cada click: el bot para,
                // recalcula el camino y arranca otra vez. Corregir un dibujo no
                // es motivo para reordenar a nadie.
                std::ostringstream g;
                g << "GROUNDAT " << rayId << ' ' << std::fixed << std::setprecision(2)
                  << gx << ' ' << gy << ' ' << gz << " 1";
                SendAddon(player, g.str());
            }
            else if (haveRay)
            {
                SendAddon(player, "GROUNDNO " + std::to_string(rayId));
            }

            // Your own character is in this list too, under its own name. In
            // RTS mode you are a unit like the others, so a click has to mean
            // the same thing for you -- but your body is server-driven while
            // the camera holds control, so it takes a different route.
            std::string const selfName = player->GetName();

            if (intent == rts::orders::CLICK_ATTACK)
            {
                int hit = 0;
                int idle = 0;
                for (Dest const& d : dests)
                {
                    if (d.name == selfName)
                    {
                        hit += rts::orders::SelfAttack(player, target) ? 1 : 0;
                        continue;
                    }
                    if (rts::orders::AttackBot(player, d.name, target))
                        ++hit;
                    // La accion de ataque se dispara igual estando pasivo, pero
                    // nada la sostiene: el bot llega y se para. Se cuenta y se
                    // avisa, porque el rol lo puso el jugador y corregirlo por
                    // nuestra cuenta seria desobedecerle en silencio -- que es
                    // el mismo error, del otro lado.
                    if (rts::orders::IsPassive(player, d.name))
                        ++idle;
                }

                if (idle > 0)
                    Reply(player, "RTS: " + std::to_string(idle) +
                          " en Esperar (passive) -- van, pero no pelean solos. "
                          "Quitales ese rol en la fila de roles.");

                // The victim's NAME goes back too. The server cannot set the
                // player's client-side target -- Player::SetSelection writes
                // the field playerbots reads, but the target frame is driven by
                // the client's own CMSG_SET_SELECTION and there is no packet to
                // force it. So the addon shows what the group is fighting in
                // its own panel instead.
                std::string label;
                if (Unit* victim = ObjectAccessor::GetUnit(*player, target))
                    label = victim->GetName();

                SendAddon(player, "DID ATTACK " + std::to_string(hit) + " " + label);
                return true;
            }

            if (intent == rts::orders::CLICK_INTERACT)
            {
                // Done here rather than by the addon sending `talk`. That
                // command routes to GossipHelloAction, which reads the MASTER's
                // target (GossipHelloAction.cpp:22) -- never set, so nobody
                // talked to anybody. Naming the NPC is the whole fix, same as
                // it was for attack.
                // UN CADAVER NO ES UNA CONVERSACION.
                //
                // Reportado asi: "click derecho sobre el muerto lo interpretan
                // como talk, y no quiero hablar con el muerto sino lootearlo".
                // Y era literal: TalkBot dispara `gossip hello` sin mirar si el
                // objetivo esta vivo, asi que los bots seleccionados intentaban
                // darle conversacion al cuerpo.
                //
                // Con un muerto, el unico que actua es TU personaje, y lo que
                // hace es lootear -- SelfInteract acaba en DoInteract, que ya
                // distingue "muerto que puedes lootear" de "PNJ con el que se
                // habla". Los bots se quedan al margen: recogen por su cuenta
                // cuando les toca, que es como quisiste dejarlo.
                Unit* victim = ObjectAccessor::GetUnit(*player, target);
                bool const corpse = victim && !victim->IsAlive();

                int hit = 0;
                for (Dest const& d : dests)
                {
                    if (d.name == selfName)
                        hit += rts::orders::SelfInteract(player, target) ? 1 : 0;
                    else if (!corpse && rts::orders::TalkBot(player, d.name, target))
                        ++hit;
                }
                SendAddon(player, "DID INTERACT " + std::to_string(hit));
                return true;
            }

            int moved = 0;
            for (Dest const& d : dests)
            {
                if (d.name == selfName)
                    moved += rts::orders::MoveSelf(player, d.x, d.y, d.z) ? 1 : 0;
                else if (rts::orders::MoveBot(player, d.name, d.x, d.y, d.z))
                    ++moved;
            }
            SendAddon(player, "DID MOVE " + std::to_string(moved));
            return true;
        }

        if (verb == "MOVE")
            return DispatchMove(player, rest);

        if (verb == "FOLLOW")
            return DispatchFollow(player, rest);

        // "LOOT 1" / "LOOT 0" -- que los bots del grupo recojan TODO, o solo lo
        // util. Sustituye al `ll all` que el addon soltaba por el chat de grupo
        // cada vez que entrabas en modo RTS o cambiaba el grupo: mismo efecto,
        // sin una linea de chat y sin depender de que la orden llegue.
        // "POS" -- donde esta cada bot del grupo, ahora mismo.
        //
        // El addon lo pide un par de veces por segundo mientras hay una ruta
        // en marcha. Podria leerlo de rts_core, pero solo para lo que el
        // CLIENTE ve, y un bot que se aleja sale de la burbuja de visibilidad:
        // a partir de ahi el addon no sabe si ha llegado y la ruta solo avanza
        // por su plazo de 40 s, que en juego se lee como "el bot se ha olvidado
        // de que iba andando". El servidor nunca lo pierde de vista.
        if (verb == "POS")
        {
            std::string const list = rts::orders::GroupPositions(player);
            if (!list.empty())
                SendAddon(player, "POS " + list);
            return true;
        }

        if (verb == "LOOT")
        {
            bool const all = rest.empty() || rest[0] != '0';
            int const n = rts::orders::SetGroupLoot(player, all);
            SendAddon(player, "DID LOOT " + std::to_string(n) + (all ? " 1" : " 0"));
            return true;
        }

        // --- route markers -----------------------------------------------
        //
        // "MARK <slot> <x> <y> <z>" -- put a ground marker at a waypoint. The
        // LOOK is not in the message on purpose: it is per-player server state
        // (MARKSET), so stepping through visuals re-places every marker already
        // down instead of only changing the next one.
        if (verb == "MARK")
        {
            std::istringstream in(rest);
            uint32 slot = 0;
            float x = 0.0f, y = 0.0f, z = 0.0f;
            if (!(in >> slot >> x >> y >> z))
                return false;

            Position const pos(x, y, z, 0.0f);
            if (!rts::marks::Place(player, slot, pos))
                SendAddon(player, "MARKERR " + std::to_string(slot));
            return true;
        }

        // "MARKOFF <slot>", 0 = all of them.
        if (verb == "MARKOFF")
        {
            uint32 slot = 0;
            std::istringstream in(rest);
            in >> slot;
            rts::marks::Remove(player, slot);
            return true;
        }

        // "MARKSET <spell|size|scale|obj|mode|next|prev|find> [value]" -- the tuning tool.
        // Always answers with the full state, so the addon never has to guess
        // what its request did.
        if (verb == "MARKSET")
        {
            std::string sub, value;
            Split(rest, sub, value);

            if (sub == "SPELL")
                rts::marks::SetSpell(player, static_cast<uint32>(std::atoi(value.c_str())));
            else if (sub == "SIZE")
                rts::marks::SetRadius(player, static_cast<float>(std::atof(value.c_str())));
            else if (sub == "SCALE")
                rts::marks::SetScale(player, static_cast<float>(std::atof(value.c_str())));
            else if (sub == "OBJ")
                rts::marks::SetObjScale(player, static_cast<float>(std::atof(value.c_str())));
            else if (sub == "MODE")
                rts::marks::SetMode(player, value.empty() || value[0] == '0' ? 0 : 1);
            else if (sub == "NEXT")
                rts::marks::Step(player, value.empty() ? 1 : std::atoi(value.c_str()));
            else if (sub == "PREV")
                rts::marks::Step(player, value.empty() ? -1 : -std::atoi(value.c_str()));
            else if (sub == "FIND")
            {
                if (!rts::marks::Find(player, value))
                    SendAddon(player, "MARKNO " + value);
            }

            rts::marks::Look const& look = rts::marks::Get(player);
            uint32 const spell = look.spell ? look.spell
                : (rts::marks::Candidates().empty() ? 0 : rts::marks::Candidates().front().id);

            // The radius REPORTED is the effective one, not the stored one:
            // stored 0 means "a tenth of the spell's own", and printing 0 would
            // read as "no size" -- which is how a working automatic default
            // starts looking like a bug. The spell's own radius goes out too,
            // because a yard figure only means something next to it.
            std::ostringstream out;
            out << "MARKAT " << look.index
                << ' ' << rts::marks::Candidates().size()
                << ' ' << spell
                << ' ' << std::fixed << std::setprecision(2)
                << rts::marks::EffectiveRadius(look)
                << ' ' << static_cast<int>(look.mode)
                << ' ' << rts::marks::Count(player)
                << ' ' << rts::marks::SpellRadius(spell)
                << ' ' << look.obj
                << ' ' << rts::marks::NameOf(spell);
            SendAddon(player, out.str());
            return true;
        }

        // "MARKQ <from> <count>" -- a page of the candidate list, for browsing.
        // Chunked because an addon message caps at 255 characters, and each
        // chunk carries its OWN starting index so the addon does not depend on
        // them arriving in order.
        if (verb == "MARKQ")
        {
            auto const& cands = rts::marks::Candidates();
            std::istringstream in(rest);
            std::size_t from = 0;
            int count = 20;
            in >> from;
            in >> count;
            if (count <= 0 || count > 100)
                count = 20;

            std::string chunk;
            std::size_t chunkFrom = from;
            std::size_t i = from;
            for (; i < cands.size() && i < from + static_cast<std::size_t>(count); ++i)
            {
                std::string const piece =
                    std::to_string(cands[i].id) + "|" + cands[i].name;
                if (chunk.size() + piece.size() + 2 > 180)
                {
                    SendAddon(player, "MARKQ " + std::to_string(cands.size()) + " " +
                                      std::to_string(chunkFrom) + " " + chunk);
                    chunk.clear();
                    chunkFrom = i;
                }
                if (!chunk.empty())
                    chunk += ";";
                chunk += piece;
            }
            if (!chunk.empty())
                SendAddon(player, "MARKQ " + std::to_string(cands.size()) + " " +
                                  std::to_string(chunkFrom) + " " + chunk);
            return true;
        }

        if (verb == "ATTACK")
            return DispatchAttack(player, rest);

        // "AMOVE Bot x y z;Other x y z[;@ id ray base]" -- same shape as MOVE,
        // y con el mismo tramo '@' opcional que CLICK: el avance con ataque
        // tambien sale del cursor, asi que sufre exactamente el mismo error de
        // plano y se corrige igual. Se recogen los destinos primero porque el
        // desplazamiento no se conoce hasta haber leido el tramo del rayo, que
        // va al final.
        if (verb == "AMOVE")
        {
            struct AD { std::string name; float x, y, z; };
            std::vector<AD> dests;
            bool fixed = false;
            float sx = 0.0f, sy = 0.0f, sz = 0.0f;

            for (std::string const& entry : SplitList(rest, ';'))
            {
                std::istringstream in(entry);
                std::string head;
                if (!(in >> head))
                    continue;

                if (head == "@")
                {
                    uint32 id = 0;
                    float ox, oy, oz, dx, dy, dz, bx, by, bz;
                    if (!(in >> id >> ox >> oy >> oz >> dx >> dy >> dz >> bx >> by >> bz))
                        continue;
                    float gx, gy, gz;
                    if (rts::orders::GroundRay(player, ox, oy, oz, dx, dy, dz, 500.0f, gx, gy, gz))
                    {
                        fixed = true;
                        sx = gx - bx; sy = gy - by; sz = gz - bz;
                    }
                    continue;
                }

                AD d;
                d.name = head;
                if (in >> d.x >> d.y >> d.z)
                    dests.push_back(d);
            }

            int moved = 0;
            for (AD& d : dests)
            {
                if (fixed) { d.x += sx; d.y += sy; d.z += sz; }
                if (rts::orders::AttackMoveBot(player, d.name, d.x, d.y, d.z))
                    ++moved;
            }
            return moved > 0;
        }

        // "SELFMOVE x y z" -- the commanding player's own character, which is
        // only movable while the camera holds client control.
        if (verb == "SELFMOVE")
        {
            std::istringstream in(rest);
            float x = 0.0f, y = 0.0f, z = 0.0f;
            if (!(in >> x >> y >> z))
                return false;
            std::string why;
            if (!rts::orders::MoveSelf(player, x, y, z, &why))
                Reply(player, "RTS: cannot order your character -- " + why + ".");
            return true;
        }

        // "POSSESS Bot" / "POSSESS" to let go.
        if (verb == "POSSESS")
        {
            if (rest.empty())
            {
                rts::orders::ReleaseAll(player);
                SendAddon(player, "POSSESS 0");
                return true;
            }

            rts::orders::ReleaseAll(player);
            if (rts::orders::PossessBot(player, rest))
                SendAddon(player, "POSSESS 1 " + rest);
            else
                Reply(player, "RTS: cannot take control of " + rest + ".");
            return true;
        }

        if (verb == "CAM")
        {
            std::string const arg = Upper(rest);

            if (arg == "ON" || arg == "OFF" || arg == "TOGGLE" || arg.empty())
            {
                bool const wantOn = (arg == "ON") ||
                                    ((arg == "TOGGLE" || arg.empty()) && !rts::camera::IsActive(player));

                if (wantOn)
                {
                    if (!rts::camera::Enable(player))
                        Reply(player, "RTS camera: cannot start here (dead, in flight or in a vehicle?).");
                }
                else
                {
                    rts::camera::Disable(player);
                }

                ReportCamera(player);
                return true;
            }
            if (arg == "STATUS")
            {
                ReportCamera(player);
                return true;
            }
            if (arg == "HERE" || arg == "RECENTER")
            {
                rts::camera::Recenter(player);
                return true;
            }
            // "CAM POS" -- read back where the camera is sitting right now, so
            // the addon can save it as the framing to return to.
            if (arg == "POS")
            {
                float back = 0.0f, up = 0.0f;
                if (rts::camera::MeasureOffset(player, back, up))
                {
                    std::ostringstream out;
                    out << "CAMPOS " << std::fixed << std::setprecision(2) << back << " " << up;
                    SendAddon(player, out.str());
                }
                else
                    Reply(player, "RTS camera: turn the camera on first.");
                return true;
            }

            if (!rest.empty())
            {
                // "CAM SPEED <n>"
                std::string sub, value;
                Split(rest, sub, value);
                if (sub == "SPEED")
                {
                    float speed = 0.0f;
                    std::istringstream stream(value);
                    stream >> speed;
                    if (!rts::camera::SetSpeed(player, speed))
                        Reply(player, "RTS camera: speed must be 0.5-50 and the camera must be on.");
                    return true;
                }
                // "CAM OFFSET <back> <up>" -- where the camera sits relative to
                // the character. Sent by the addon before every enable, since
                // the addon is where the setting is persisted.
                if (sub == "OFFSET")
                {
                    float back = 0.0f, up = 0.0f;
                    std::istringstream stream(value);
                    stream >> back >> up;
                    rts::camera::SetOffset(player, back, up);
                    return true;
                }
                // "CAM ZV <-1|0|1>" -- a height key going down or coming up.
                // Sent on key transitions only, never per frame; the server
                // holds the direction and moves the camera on its own tick.
                if (sub == "ZV")
                {
                    int dir = 0;
                    std::istringstream stream(value);
                    stream >> dir;
                    rts::camera::SetVertical(player, dir);
                    return true;
                }
                // "CAM PV <-1|0|1>" -- a pivot key going down or coming up.
                // Same shape as ZV and for the same reason: the addon reports
                // only the key transitions and the server orbits on its own
                // tick, so a held key costs two messages rather than one per
                // frame.
                if (sub == "PV")
                {
                    int dir = 0;
                    std::istringstream stream(value);
                    stream >> dir;
                    rts::camera::SetPivot(player, dir);
                    return true;
                }
                // "CAM FLY <0|1>" -- decides whether forward follows the view
                // vector or runs flat across the map. Switchable live so the
                // two can be compared without a restart.
                if (sub == "FLY")
                {
                    bool const fly = (value == "1" || value == "on" || value == "ON");
                    if (!rts::camera::SetFly(player, fly))
                        Reply(player, "RTS camera: turn the camera on first.");
                    else
                        Reply(player, fly
                            ? "RTS camera: flight ON - forward follows where you look."
                            : "RTS camera: flight OFF - forward runs flat, tilt only changes the view.");
                    return true;
                }
            }
            return true;
        }

        return false;   // not ours after all
    }
}

class RtsChannelScript : public PlayerScript
{
public:
    RtsChannelScript() : PlayerScript("RtsChannelScript", {
        PLAYERHOOK_ON_BEFORE_SEND_CHAT_MESSAGE,
        PLAYERHOOK_ON_LOGOUT,
        PLAYERHOOK_ON_UPDATE_ZONE,
        PLAYERHOOK_ON_BEFORE_TELEPORT,
        PLAYERHOOK_ON_MAP_CHANGED
    }) { }

    // Fires at ChatHandler.cpp:367, BEFORE the per-type switch, so it sees every
    // chat type -- including a LANG_ADDON whisper.
    //
    // This is deliberately not OnPlayerCanUseChat(..., Player* receiver). That
    // overload looks like the obvious fit and is never actually called for
    // whispers: the whisper branch runs straight into Player::Whisper without
    // consulting it (ChatHandler.cpp:451). The hook enum exists, the call site
    // does not.
    //
    // The addon whispers ITSELF, which keeps this working solo. Party and guild
    // would both have been hooked, but party chat is where mod-playerbots reads
    // its own commands, and a character need not be in a guild.
    void OnPlayerBeforeSendChatMessage(Player* player, uint32& /*type*/, uint32& lang,
                                       std::string& msg) override
    {
        if (!player || lang != LANG_ADDON)
            return;

        // Addon payloads arrive packed as "PREFIX\tBODY".
        std::size_t const tab = msg.find('\t');
        if (tab == std::string::npos || msg.compare(0, tab, kPrefix) != 0)
            return;

        Dispatch(player, msg.substr(tab + 1));

        // The message is left to travel on. It cannot be suppressed from here
        // -- this hook returns void -- but an addon message is never rendered
        // in the chat window, so the only consequence is that the addon hears
        // its own request come back, which it can treat as an ack.
    }

    // A camera left running across a logout would leave an orphan creature and
    // a client whose mover is gone. Drop it on the way out.
    void OnPlayerLogout(Player* player) override
    {
        // Camera first, then anything possessed. Leaving a bot charmed by a
        // player who has gone would strand it: passive, uncommandable, and
        // still pointing at a charmer that no longer exists.
        rts::camera::Abandon(player);
        rts::orders::ForgetPlayer(player);
        rts::command::ReleaseAll(player);
        // The dynobjects are already gone by now (the core drops every one when
        // the player leaves the map); this only clears our slot bookkeeping so
        // the next login does not start with a table of dead guids.
        rts::marks::ForgetPlayer(player);
    }

    // Zoning while flying the camera would strand it on the old map.
    void OnPlayerUpdateZone(Player* player, uint32 /*newZone*/, uint32 /*newArea*/) override
    {
        if (rts::camera::IsActive(player) && !player->IsInWorld())
            rts::camera::Abandon(player);
    }

    // AN ORDERLY EXIT, NOT A FUSE. These two used to be the only thing keeping
    // the server alive across a map change, back when the camera was possessed
    // with a bare SetCharmedBy that Player::StopCastingCharm could not unwind
    // and answered with ABORT(). That is fixed at the root now -- the camera is
    // a Puppet, which the core knows how to take apart (see kPuppetProps in
    // RtsCamera.cpp), and it would survive these paths without any help.
    //
    // They stay because tearing the camera down HERE is tidier than letting it
    // be yanked: the creature is released on the map it belongs to, and the
    // addon hears the state change instead of discovering it. What they are no
    // longer is load-bearing, so there is nothing to keep adding to when a new
    // path turns up.
    //
    // A third one was written the same afternoon -- a lethal-damage hook to
    // catch dying, since Player::setDeathState has no hook of its own -- and is
    // DELETED. It was a workaround for the thing the Puppet fixes, and this
    // project has been bitten four times by compensation that outlived its
    // cause. It was also a hook on the hottest path on the server.
    bool OnPlayerBeforeTeleport(Player* player, uint32 /*mapid*/, float /*x*/, float /*y*/,
                                float /*z*/, float /*o*/, uint32 /*options*/,
                                Unit* /*target*/) override
    {
        // Fires at Player::TeleportTo:1496, well before the cleanup at 1591.
        // Covers portals, hearthstone, dungeon entrances, GM teleports and the
        // end of a flight path.
        rts::camera::Abandon(player);
        return true;
    }

    void OnPlayerMapChanged(Player* player) override
    {
        // Fires on every world entry, login included (Map::AddPlayerToMap), so
        // it is where the rescue belongs: whatever state a previous session or
        // an ugly teardown left behind, this is the first moment we can see it
        // and the last moment before the player notices it as a character
        // falling through the floor.
        // Our own camera first, so the orderly path gets the chance: anything
        // that moved the player to another map without going through TeleportTo
        // leaves the camera behind on the old one.
        rts::camera::Abandon(player);

        // Then the mop: whatever a previous session or an ugly teardown left
        // behind, this is the first moment we can see it and the last moment
        // before the player meets it as a character falling through the floor.
        rts::camera::Rescue(player);
    }
};

// Manual fallback so the camera can be tested without the addon loaded --
// ".rts cam" typed into chat does the same thing the addon message does.
class RtsCommandScript : public CommandScript
{
public:
    RtsCommandScript() : CommandScript("RtsCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable rtsCommandTable =
        {
            { "cam", HandleRtsCamCommand, rbac::RBAC_PERM_COMMAND_GM, Console::No },
        };
        static ChatCommandTable commandTable =
        {
            { "rts", rtsCommandTable },
        };
        return commandTable;
    }

    // Tail rather than a single token, so ".rts cam speed 6" arrives whole.
    static bool HandleRtsCamCommand(ChatHandler* handler, Tail arg)
    {
        Player* player = handler->GetSession() ? handler->GetSession()->GetPlayer() : nullptr;
        if (!player)
            return false;

        std::string const rest(arg);
        Dispatch(player, "CAM " + (rest.empty() ? std::string("TOGGLE") : rest));
        return true;
    }
};

// Drives the command-mode idle release. Nothing else needs a tick: the camera
// is flown by the client and orders are one-shot.
class RtsWorldScript : public WorldScript
{
public:
    RtsWorldScript() : WorldScript("RtsWorldScript", { WORLDHOOK_ON_UPDATE }) { }

    void OnUpdate(uint32 diff) override
    {
        rts::command::Update(diff);
        rts::orders::UpdatePending(diff);
        rts::camera::Update(diff);
    }
};

void AddSC_mod_rts()
{
    new RtsChannelScript();
    new RtsCommandScript();
    new RtsWorldScript();
}
