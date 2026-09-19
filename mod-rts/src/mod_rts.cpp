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
#include "GameObject.h"   // el nodo de recoleccion del click derecho
#include "Group.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Opcodes.h"
#include "Player.h"
#include "PlayerScript.h"
#include "RBAC.h"
#include "RtsBags.h"
#include "RtsBotApi.h"
#include "RtsQuests.h"
#include "RtsQueue.h"
#include "RtsSwap.h"
#include "RtsTrain.h"
#include "RtsCamera.h"
#include "RtsChain.h"
#include "RtsCommandMode.h"
#include "RtsMarks.h"
#include "RtsNpc.h"
#include "RtsOrders.h"
#include "RtsLfg.h"
#include "RtsPets.h"
#include "RtsTalents.h"
#include "RtsXp.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "WorldPacket.h"
#include "WorldScript.h"
#include "WorldSession.h"

#include <cctype>
#include <cstdlib>
#include <vector>

#include <iomanip>
#include <map>
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
    // 0.64.0 = la propuesta de mazmorra se ve por `OnPlayerbotPacketSent` y no
    // por `CanPacketSend`: un bot no tiene socket y `WorldSession::SendPacket`
    // se vuelve antes de llegar al segundo, asi que por ahi no pasa ni un
    // paquete suyo. Con el gancho bueno, los dos que se quedaban sin aceptar la
    // pantalla de "listos" aceptan.
    // 0.63.0 = en la comprobacion de funciones ya no se calla nadie: si no se
    // puede decir que esta haciendo un bot por su estrategia, se contesta por
    // su especializacion. Callarse dejaba su interrogante puesto y el grupo sin
    // encolar, sin nada en pantalla que lo explicara. Y ahora se escribe en el
    // chat del jefe que rol se ha mandado por cada uno.
    // 0.62.0 = la propuesta de mazmorra la aceptamos nosotros por los bots
    // (playerbots manda un NO si el bot esta en combate o muerto, y un solo NO
    // deja al grupo entero fuera), y `LFGCLEAR` les quita el castigo de
    // desertor y los restos de cola.
    // 0.61.0 = la comprobacion de funciones del buscador de mazmorras la
    // contestamos nosotros por los bots, con el rol que les tienes puesto. Sin
    // esto todos elegian TANQUE -- el mago tambien -- y el chat se quedaba en
    // bucle: playerbots contesta desde un manejador colgado del paquete que el
    // nucleo manda a TODO el grupo cada vez que alguien contesta. Ver
    // `RtsLfg.h`.
    // 0.60.0 = el catalogo de hechizos (`BARS`) lleva un tercer campo: el
    // enfriamiento base de cada uno, en milisegundos. El cliente no puede
    // saberlo de un hechizo que no esta en TU libro, y sin el la rueda que la
    // barra dibuja al pulsar solo podia durar lo mismo para todos. Campo
    // opcional: se manda solo cuando el hechizo tiene enfriamiento propio, y un
    // addon anterior lo ignora.
    // 0.59.0 = `BAGSELL` y `EQUIP`, y un objeto que entra en la bolsa de un bot
    // por `BAGMOVE` le dispara `equip upgrade` en el acto -- el bot ya se lo
    // ponia, pero en su siguiente vuelta de pensamiento, y desde fuera eso se
    // ve como que darle una espada no sirve de nada.
    // 0.58.0 = `UNTALENT <pestana> <fila> <columna>`: quitar UN punto de
    // talento, que el juego no deja -- en 3.3.5 solo existe el reseteo entero y
    // pagado. Por dentro es un reseteo gratis y volver a aprender la build
    // menos ese punto, que es lo unico que deja bien `m_usedTalentCount`; la
    // razon larga esta en `RtsTalents.h`.
    // 0.57.0 = `XP UP|DOWN|?`, el dial de experiencia del mundo en tantos por
    // ciento, de cincuenta en cincuenta. Es un MULTIPLICADOR sobre lo que diga `worldserver.conf`, no un
    // valor que lo pise, y se guarda en `worldstates` para que un reinicio no
    // lo devuelva a su sitio en silencio. El addon debe pedir
    // `ServerAtLeast(57)`: un verbo que el servidor no conoce no da error, no
    // contesta, y eso se ve como un boton roto.
    // 0.56.0 = la felicidad de las mascotas de cazador se queda en el maximo
    // (`RtsPets`, `RTS.Pet.Happy`). Era una correa que no ata a nadie: baja
    // sola, morir cuesta un tercio de la barra de golpe, y solo la sube dar de
    // comer -- que es un hechizo del duenno, asi que a la mascota de un bot no
    // se la sube nadie. Sin verbo nuevo: el addon no tiene que preguntar nada.
    // 0.52.0 = `HOLD` y `SUMMON`. Quieto y traer eran las dos ultimas ordenes
    // de uso diario que viajaban como texto por el chat del grupo: se las comia
    // la cola del cliente si mandabas varias seguidas, y el bot no las veia
    // hasta su siguiente vuelta de pensamiento. Ahora van por aqui, como mover.
    // 0.51.0 = las ordenes que das con el raton despiertan la IA del bot en el
    // acto (`SetNextCheckDelay(0)`). Este modulo no camina al bot: le pone el
    // ancla y borra su camino, y andar es cosa de su IA -- que estaba dormida
    // lo que le durara su propia espera. La orden llegaba al instante y el bot
    // tardaba en salir, que es lo que se veia.
    // 0.50.0 = un click derecho sobre un nodo de recoleccion deja de ser una
    // orden de movimiento. Recoger una hierba es un LANZAMIENTO y `MoveSelf` lo
    // cancelaba, asi que el arreglo es apartarse: a tiro no se manda nada y
    // recoge el cliente; lejos, te lleva andando. Acuse nuevo: `DID GATHER`.
    // 0.49.0 = LA POSESION SE VA ENTERA. El verbo `POSSESS`, `PossessBot`,
    // `ReleaseBot`, `ReleaseAnyPossession` y `ReleaseAll` (la de `orders`) estan
    // borrados: el jugador la retiro el 2026-09-11 -- *"posees raro, eso
    // quitalo"* -- y no habia forma de arreglarla, porque cambia quien te MUEVE
    // y no quien ERES (los manejadores de interaccion del nucleo trabajan sobre
    // `_player`). Con ella se van los dos seguros del `ABORT()` de
    // `StopCastingCharm`: ya nada de este modulo charma a un `Player`, asi que
    // eran guardas que no podian dispararse -- y peor, la de `OnPlayerLogout`
    // habria pisado un Control Mental de sacerdote, que el nucleo ya deshace
    // solo. La camara NO usaba nada de esto: es un Puppet y se suelta por
    // `camera::Abandon`.
    // 0.48.0 = el servidor deja de poner `PLAYER_FLAGS_UBER`: el nucleo prohibe
    // atacar a quien lo lleva (`Unit.cpp:10762`). Ese bit pasa a escribirlo
    // `rts_core` en la memoria del cliente, asi que la camara libre necesita el
    // DLL inyectado.
    // 0.47.0 = `CAM CTRL <0|1>`, y el control del cuerpo deja de quitarsele al
    // cliente de fabrica -- quitarselo le apaga la espada y el click derecho.
    // 0.46.0 = vuelve la camara de espectador (`CAM SPEC` / `CAM SPECARM`) y la
    // tercera condicion de `MoveSelf`. El addon debe pedir `ServerAtLeast(46)`
    // antes de usar esos verbos: un verbo que el servidor no conoce NO da error,
    // no contesta, asi que un worldserver sin reiniciar se lee como un addon roto.
    constexpr char const* kModVersion = "0.64.0";

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

    // El volcado de misiones de un NPC. Lo mandan DOS caminos -- la consulta y
    // la respuesta a aceptar/entregar -- y estaba escrito dos veces; el titulo
    // al final de su propia linea es lo delicado de esto (ver el verbo NPCQ) y
    // tenerlo en dos sitios es tenerlo mal en uno de los dos tarde o temprano.
    void SendQuestList(Player* player, std::string const& guidHex,
                       std::vector<rts::quests::Offer> const& offers)
    {
        for (auto const& o : offers)
        {
            // EL TITULO VA EL ULTIMO Y TODO LO DEMAS DELANTE. Es lo que hace
            // que no haya nada que escapar: el titulo lleva espacios y comas, y
            // el resto de la linea es el titulo por definicion. Cualquier campo
            // nuevo va ANTES, nunca detras.
            std::ostringstream q;
            q << "NPCQ " << guidHex << " Q " << o.questId << ' ' << o.flags
              << ' ' << o.level << ' ';
            if (o.choices.empty())
            {
                q << '-';
            }
            else
            {
                for (std::size_t c = 0; c < o.choices.size(); ++c)
                    q << (c ? "," : "") << o.choices[c];
            }
            q << ' ' << o.title;
            SendAddon(player, q.str());

            std::ostringstream s;
            s << "NPCQ " << guidHex << " S " << o.questId << ' ';
            bool first = true;
            for (auto const& m : o.members)
            {
                if (!first)
                    s << ',';
                first = false;
                s << m.name << ':' << uint32(m.status);
            }
            SendAddon(player, s.str());
        }

        SendAddon(player, "NPCQEND " + guidHex + " " + std::to_string(offers.size()));
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
    // EL DESTINO QUE SE PIDE Y EL SITIO AL QUE VA NO SON EL MISMO, y desde que
    // `MoveBot` parte los viajes largos en tramos sobre el navmesh hay que
    // decirlo: el addon mide la llegada, dibuja la ruta y detecta atascos contra
    // el punto al que CREE que va el bot. Si eso es el waypoint final mientras el
    // bot anda hacia un punto intermedio, nunca llega, y a los cuarenta segundos
    // el plazo se salta el tramo -- un bot que no obedece, otra vez, por medir
    // contra lo que se pidio en vez de contra lo que pasa.
    //
    // `MOVEAT <nombre> <x> <y> <z> <tipo>`, uno por bot. 0 = el punto entero,
    // 1 = un trozo (hay que volver a pedir al llegar), 2 = no hay camino.
    bool DispatchMove(Player* player, std::string const& rest)
    {
        std::size_t start = 0;
        int moved = 0;
        int lost = 0;

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
                if (in >> name >> x >> y >> z)
                {
                    float lx = x, ly = y, lz = z;
                    int kind = rts::orders::LEG_FULL;
                    if (rts::orders::MoveBot(player, name, x, y, z, &lx, &ly, &lz, &kind))
                        ++moved;
                    else if (kind == rts::orders::LEG_NONE)
                        ++lost;

                    std::ostringstream out;
                    out << "MOVEAT " << name << ' ' << std::fixed << std::setprecision(2)
                        << lx << ' ' << ly << ' ' << lz << ' ' << kind;
                    SendAddon(player, out.str());
                }
            }

            if (end == std::string::npos)
                break;
            start = end + 1;
        }

        // UNA LINEA POR ORDEN, NO UNA POR BOT. Y se dice, porque el fallo que
        // esto sustituye era mudo: el bot salia volando por la montana y llegaba
        // -- mal, atravesandola -- asi que no habia nada que contar. Ahora no
        // sale, y un bot quieto sin explicacion es justo la clase de silencio
        // que ha costado rondas de pruebas en este mismo gesto.
        if (lost > 0)
            Reply(player, "RTS: " + std::to_string(lost) +
                  " sin camino andando hasta ahi -- no van. Prueba un punto mas cerca "
                  "o rodeando.");

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

    // QUE EL BOT SE PONGA LO QUE ACABA DE RECIBIR.
    //
    // `equip upgrade` es una accion de playerbots, no nuestra: recorre sus
    // bolsas y se pone lo que su propia valoracion (`item upgrade`) considera
    // mejor que lo que lleva. Nosotros solo la disparamos en el momento en que
    // el objeto ENTRA, que es lo que faltaba -- el bot ya lo hacia, pero en su
    // siguiente vuelta de pensamiento, y eso desde fuera se ve como que darle
    // una espada no sirve de nada.
    //
    // EN COMBATE NO. Cambiarse de arma peleando es lo que el juego no deja y lo
    // que a un bot le costaria el golpe que estaba a medias; el objeto sigue en
    // la bolsa y `/rts equip` esta ahi para cuando acabe.
    void AskToEquip(Player* bot)
    {
        if (!bot || !rts::bots::Driven(bot) || bot->IsInCombat())
            return;
        rts::bots::DoAction(bot, "equip upgrade");
    }

    bool Dispatch(Player* player, std::string const& body)
    {
        std::string verb, rest;
        Split(body, verb, rest);

        // --- bolsas compartidas -------------------------------------------
        //
        // "BAGS <nombre>" -> el contenido de las bolsas de ese personaje, que
        // puede ser un bot del grupo o tu mismo.
        //
        // El volcado lleva DOS clases de linea y se distinguen por su primera
        // letra, no por su posicion ni por el orden de llegada:
        //
        //     B<bag>,<huecos>
        //     I<bag>,<hueco>,<guidHex>,<itemId>,<cuantos>,<calidad>,<flags>
        //
        // Van mezcladas en el mismo tren de trozos a proposito. La alternativa
        // -- primero todos los contenedores, luego todos los objetos -- obliga
        // al cliente a saber que la primera mitad ya termino, y eso solo se
        // sabe con un marcador mas o contando; con la letra delante, cada trozo
        // se entiende solo y da igual en que orden lleguen.
        if (verb == "BAGS")
        {
            std::vector<rts::bags::Container> conts;
            std::vector<rts::bags::Entry> items;
            uint32 copper = 0, freeSlots = 0;

            if (!rts::bags::Dump(player, rest, conts, items, copper, freeSlots))
            {
                SendAddon(player, "BAGS " + rest + " -");
                SendAddon(player, "BAGEND " + rest + " 0 0");
                return true;
            }

            std::vector<std::string> pieces;
            for (auto const& c : conts)
                pieces.push_back("B" + std::to_string(c.bag) + "," + std::to_string(c.size));

            for (auto const& e : items)
            {
                std::ostringstream p;
                p << "I" << uint32(e.bag) << ',' << uint32(e.slot) << ','
                  << std::hex << e.guid.GetRawValue() << std::dec << ','
                  << e.itemId << ',' << e.count << ',' << e.quality << ',' << e.flags;
                pieces.push_back(p.str());
            }

            std::string chunk;
            for (std::string const& piece : pieces)
            {
                if (chunk.size() + piece.size() + 2 > 200)
                {
                    SendAddon(player, "BAGS " + rest + " " + chunk);
                    chunk.clear();
                }
                if (!chunk.empty())
                    chunk += ";";
                chunk += piece;
            }
            if (!chunk.empty())
                SendAddon(player, "BAGS " + rest + " " + chunk);

            // El terminador lleva el dinero y los huecos libres. Van AQUI y no
            // en una linea suya porque son datos del personaje entero, no de un
            // trozo: en el terminador se leen una vez y no hay que decidir cual
            // de los trozos traia el bueno.
            SendAddon(player, "BAGEND " + rest + " " + std::to_string(copper) +
                              " " + std::to_string(freeSlots));
            return true;
        }

        // "BAGMOVE <de> <a> <guidHex>" -- una pila entera, de uno a otro.
        //
        // La respuesta NO describe lo que cambio: dice que salio bien y quienes
        // son los dos afectados, y el addon les vuelve a pedir las bolsas. Es a
        // proposito. La alternativa -- mandar el hueco nuevo y que el cliente
        // aplique el cambio el solo -- obliga al addon a simular el
        // almacenamiento del nucleo (pilas que se juntan, bolsas de tipo, el
        // hueco que elige `CanStoreItem`), y en cuanto se equivoca una vez se
        // queda ensenando algo que no existe hasta el siguiente refresco.
        if (verb == "BAGMOVE")
        {
            std::istringstream in(rest);
            std::string from, to, guidHex;
            if (!(in >> from >> to >> guidHex))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            std::string why;
            if (rts::bags::Move(player, from, to, ObjectGuid(raw), &why))
            {
                // El objeto ya esta dentro: que mire si le sirve AHORA.
                AskToEquip(rts::bots::Resolve(player, to));
                SendAddon(player, "BAGOK " + from + " " + to);
            }
            else
                SendAddon(player, "BAGERR " + from + " " + to + " " + why);
            return true;
        }

        // "BAGSELL <quien> <objetoHex> <npcHex>" -- vender UN objeto de las
        // bolsas de cualquiera de los tuyos al vendedor que tengas abierto.
        //
        // El objeto viaja por GUID y no por bolsa/hueco, igual que en
        // `BAGMOVE`: entre que el cliente dibujo la casilla y llega esto, el
        // bot ha podido recoger algo y correrlo todo un hueco.
        if (verb == "BAGSELL")
        {
            std::istringstream in(rest);
            std::string who, itemHex, npcHex;
            if (!(in >> who >> itemHex >> npcHex))
                return false;

            uint64 rawItem = 0, rawNpc = 0;
            { std::istringstream hx(itemHex); hx >> std::hex >> rawItem; }
            { std::istringstream hx(npcHex);  hx >> std::hex >> rawNpc; }
            if (!rawItem || !rawNpc)
                return false;

            uint32 itemId = 0, count = 0, earned = 0;
            std::string why;
            if (!rts::npc::SellItem(player, who, ObjectGuid(rawNpc), ObjectGuid(rawItem),
                                    itemId, count, earned, &why))
                SendAddon(player, "NPCERR " + why);
            else
                SendAddon(player, "SOLDONE " + who + " " + std::to_string(itemId) + " " +
                                  std::to_string(count) + " " + std::to_string(earned));
            return true;
        }

        // "EQUIP <nombre;nombre>" -- que revisen sus bolsas y se pongan lo que
        // sea mejor. Existe porque un objeto llega de mas sitios que de esta
        // ventana: botin, un intercambio, la recompensa de una mision.
        if (verb == "EQUIP")
        {
            int told = 0;
            for (std::string const& name : SplitList(rest, ';'))
            {
                Player* bot = rts::bots::Resolve(player, name);
                if (!bot || !rts::bots::Driven(bot))
                    continue;
                if (bot->IsInCombat())
                    continue;
                rts::bots::DoAction(bot, "equip upgrade");
                ++told;
            }
            SendAddon(player, "EQUIPPED " + std::to_string(told));
            return true;
        }

        // --- actuar como el bot: entrenador y vendedor ----------------------
        //
        // Todo esto es API PUBLICA del nucleo tomando un `Player*` cualquiera --
        // ver `RtsNpc.h`, que cuenta por que el plan lo daba por imposible y por
        // que no lo es. Aqui solo hay transporte.
        //
        // "TRAINER <bot> <npcGuidHex>"      -> lista troceada + TRAINEND
        // "TRAIN <bot> <npcGuidHex> <id|0>" -> 0 = todo lo que pueda
        // "VENDOR <bot> <npcGuidHex>"       -> lista troceada + VENDEND
        // "BUY <bot> <npcGuidHex> <slot> <n>"
        // "SELLJUNK <bot> <npcGuidHex>"
        // "REPAIR <bot> <npcGuidHex>"
        if (verb == "TRAINER" || verb == "VENDOR")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            if (!(in >> bot >> guidHex))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            bool const trainer = (verb == "TRAINER");
            char const* head = trainer ? "TRAINER " : "VENDOR ";
            char const* tail = trainer ? "TRAINEND " : "VENDEND ";

            uint32 copper = 0;
            std::string why;
            std::vector<std::string> pieces;

            if (trainer)
            {
                std::vector<rts::npc::TrainSpell> spells;
                if (!rts::npc::TrainerList(player, bot, ObjectGuid(raw), spells, copper, &why))
                {
                    SendAddon(player, "NPCERR " + why);
                    return true;
                }
                for (auto const& s : spells)
                {
                    std::ostringstream p;
                    p << s.spellId << ',' << s.cost << ',' << s.state << ',' << s.reqLevel;
                    pieces.push_back(p.str());
                }
            }
            else
            {
                std::vector<rts::npc::VendorEntry> items;
                if (!rts::npc::Vendor(player, bot, ObjectGuid(raw), items, copper, &why))
                {
                    SendAddon(player, "NPCERR " + why);
                    return true;
                }
                for (auto const& e : items)
                {
                    std::ostringstream p;
                    p << e.slot << ',' << e.itemId << ',' << e.price << ','
                      << e.left << ',' << e.extendedCost;
                    pieces.push_back(p.str());
                }
            }

            std::string chunk;
            for (std::string const& piece : pieces)
            {
                if (chunk.size() + piece.size() + 2 > 200)
                {
                    SendAddon(player, head + bot + " " + chunk);
                    chunk.clear();
                }
                if (!chunk.empty())
                    chunk += ";";
                chunk += piece;
            }
            if (!chunk.empty())
                SendAddon(player, head + bot + " " + chunk);

            SendAddon(player, tail + bot + " " + std::to_string(copper));
            return true;
        }

        if (verb == "TRAIN")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            uint32 spellId = 0;
            if (!(in >> bot >> guidHex >> spellId))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            int learned = 0;
            uint32 spent = 0;
            std::string why;
            if (!rts::npc::Train(player, bot, ObjectGuid(raw), spellId, learned, spent, &why))
            {
                SendAddon(player, "NPCERR " + why);
                return true;
            }

            SendAddon(player, "TRAINED " + bot + " " + std::to_string(learned) +
                              " " + std::to_string(spent));
            return true;
        }

        if (verb == "BUY")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            uint32 slot = 0, count = 1;
            if (!(in >> bot >> guidHex >> slot))
                return false;
            in >> count;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            std::string why;
            if (!rts::npc::Buy(player, bot, ObjectGuid(raw), slot, count, &why))
                SendAddon(player, "NPCERR " + why);
            else
                SendAddon(player, "BOUGHT " + bot);
            return true;
        }

        if (verb == "SELLJUNK")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            if (!(in >> bot >> guidHex))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            int sold = 0;
            uint32 earned = 0;
            std::string why;
            if (!rts::npc::SellJunk(player, bot, ObjectGuid(raw), sold, earned, &why))
                SendAddon(player, "NPCERR " + why);
            else
                SendAddon(player, "SOLD " + bot + " " + std::to_string(sold) +
                                  " " + std::to_string(earned));
            return true;
        }

        if (verb == "REPAIR")
        {
            std::istringstream in(rest);
            std::string bot, guidHex;
            if (!(in >> bot >> guidHex))
                return false;

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            uint32 cost = 0;
            std::string why;
            if (!rts::npc::Repair(player, bot, ObjectGuid(raw), cost, &why))
                SendAddon(player, "NPCERR " + why);
            else
                SendAddon(player, "REPAIRED " + bot + " " + std::to_string(cost));
            return true;
        }

        // --- questeo multiple ----------------------------------------------
        //
        // "NPCQ <npcGuidHex>" -> todas las misiones de ese NPC y, por cada una,
        // el estado de cada miembro del grupo.
        //
        // DOS MENSAJES POR MISION, y NO troceado como `BAGS`. El motivo es el
        // TITULO: lleva espacios, comas y a veces punto y coma, asi que meterlo
        // en un tren de trozos separados por `;` con campos separados por `,`
        // seria fabricar el fallo. Un titulo que parte una linea en dos no da
        // error: deja media mision en la lista y la otra media perdida, que es
        // el fallo silencioso de siempre. Con el titulo AL FINAL de su propio
        // mensaje, el resto de la linea es el titulo por definicion y no hay
        // nada que escapar.
        //
        //     NPCQ <npc> Q <questId> <flags> <nivel> <titulo con lo que sea>
        //     NPCQ <npc> S <questId> <nombre>:<estado>,<nombre>:<estado>
        //     NPCQEND <npc> <cuantas>
        //
        // Un NPC tiene un punado de misiones, asi que dos mensajes por mision no
        // es trafico: es menos que un solo refresco de bolsas.
        if (verb == "NPCQ")
        {
            uint64 raw = 0;
            { std::istringstream hx(rest); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            ObjectGuid const npc(raw);
            std::vector<rts::quests::Offer> offers;
            if (!rts::quests::Look(player, npc, offers))
            {
                SendAddon(player, "NPCQEND " + rest + " 0");
                return true;
            }

            SendQuestList(player, rest, offers);
            return true;
        }

        // "QWHO <questId>" -> quien del grupo lleva ESA mision.
        //
        //     peticion:   QWHO <questId>
        //     respuesta:  QWHO <questId> <nombre>:<estado>,<nombre>:<estado>
        //
        // EL DISCRIMINANTE DE LOS DOS SENTIDOS ES EL NUMERO DE CAMPOS, igual
        // que en `BAGS`: la peticion trae uno y la respuesta dos. Cada verbo de
        // doble sentido tiene que traer el suyo escrito, porque el generico --
        // "casa con un manejador" -- vale para los dos lados por construccion.
        if (verb == "QWHO")
        {
            std::istringstream in(rest);
            uint32 questId = 0;
            std::string extra;
            if (!(in >> questId))
                return false;
            if (in >> extra)
                return true;   // dos campos: es nuestro propio eco

            std::vector<rts::quests::Member> who;
            if (!rts::quests::Holders(player, questId, who))
                return true;

            std::string list;
            for (auto const& m : who)
            {
                if (!list.empty())
                    list += ",";
                list += m.name + ":" + std::to_string(uint32(m.status));
            }

            SendAddon(player, "QWHO " + std::to_string(questId) + " " +
                              (list.empty() ? std::string("-") : list));
            return true;
        }

        // "QSHARE <questId> <nombre;nombre>" -> darles una de MIS misiones,
        // poniendoles al dia la cadena por el camino. Un solo sentido.
        // "QLOG" -> el registro de misiones de TODO el grupo.
        //
        //     peticion:   QLOG
        //     respuesta:  QLOGZ <zid> <nombre de zona>
        //                 QLOG <nombre> <questId> <estado> <clase> <zid> <titulo>
        //                 QLOGEND <n>
        //
        // === POR QUE LAS ZONAS VAN EN SUS PROPIAS LINEAS ====================
        //
        // La regla de este canal es que el campo de TEXTO LIBRE va el ultimo y
        // todo lo demas delante, que es lo que hace que no haya nada que
        // escapar (ver `SendQuestList`). Una fila de misiones tiene DOS textos
        // libres -- la zona y el titulo -- y dos no caben en un solo sitio.
        //
        // Asi que la zona sale antes, una vez cada una, con un numero corto que
        // la nombra; la fila lleva el numero y el titulo se queda de ultimo
        // como en todo lo demas. De paso el nombre de una zona viaja una vez en
        // vez de quince.
        //
        // `zid` 0 es "sin zona", que en la practica son las de CLASE: van a su
        // propio grupo por peticion, y ademas varias no traen zona en los datos.
        if (verb == "QLOG")
        {
            std::vector<rts::quests::Entry> entries;
            if (!rts::quests::Registry(player, entries))
            {
                SendAddon(player, "QLOGEND 0");
                return true;
            }

            // Los nombres de zona, deduplicados y numerados en el orden en que
            // aparecen. Un `map` por nombre y no por id de area porque el id no
            // sale de aqui: lo unico que el cliente necesita es poder agrupar.
            std::map<std::string, uint32> zoneIds;
            for (auto const& e : entries)
            {
                if (e.zone.empty() || zoneIds.count(e.zone))
                    continue;

                uint32 const zid = static_cast<uint32>(zoneIds.size()) + 1;
                zoneIds[e.zone] = zid;
                SendAddon(player, "QLOGZ " + std::to_string(zid) + " " + e.zone);
            }

            for (auto const& e : entries)
            {
                auto const it = zoneIds.find(e.zone);
                uint32 const zid = (it == zoneIds.end()) ? 0 : it->second;

                std::ostringstream q;
                q << "QLOG " << e.name << ' ' << e.questId << ' ' << uint32(e.status)
                  << ' ' << (e.classQuest ? 1 : 0) << ' ' << zid << ' ' << e.title;
                SendAddon(player, q.str());
            }

            SendAddon(player, "QLOGEND " + std::to_string(entries.size()));
            return true;
        }

        // "QFORCE <questId> <nombre;nombre>" -> darla por hecha y cobrada.
        //
        // Misma forma que `QSHARE` a proposito, incluida la lista de nombres
        // aunque la ventana mande siempre uno: el verbo no tiene por que saber
        // como esta dibujada la fila que lo dispara.
        if (verb == "QFORCE")
        {
            std::istringstream in(rest);
            uint32 questId = 0;
            std::string names;
            if (!(in >> questId >> names))
                return false;

            int ok = 0, bad = 0;
            std::string why;
            std::vector<std::string> notes;

            if (!rts::quests::ForceFinish(player, questId, SplitList(names, ';'),
                                          ok, bad, notes, &why))
            {
                SendAddon(player, "QERR " + std::to_string(questId) + " " + why);
                return true;
            }

            for (std::string const& n : notes)
                Reply(player, "RTS: " + n);

            SendAddon(player, "QDONE F " + std::to_string(questId) + " " +
                              std::to_string(ok) + " " + std::to_string(bad));
            return true;
        }

        if (verb == "QSHARE")
        {
            std::istringstream in(rest);
            uint32 questId = 0;
            std::string names;
            if (!(in >> questId >> names))
                return false;

            int ok = 0, bad = 0;
            std::string why;
            std::vector<std::string> notes;

            if (!rts::quests::Share(player, questId, SplitList(names, ';'), ok, bad, notes, &why))
            {
                SendAddon(player, "QERR " + std::to_string(questId) + " " + why);
                return true;
            }

            for (std::string const& n : notes)
                Reply(player, "RTS: " + n);

            SendAddon(player, "QDONE S " + std::to_string(questId) + " " +
                              std::to_string(ok) + " " + std::to_string(bad));

            // Y los estados NUEVOS de esa mision, sin que nadie los pida. El
            // cliente no puede deducirlos: sabe a quien se le mando, no a quien
            // le entro -- eso depende de nivel, clase y hueco de registro, que
            // solo se ven aqui.
            std::vector<rts::quests::Member> who;
            if (rts::quests::Holders(player, questId, who))
            {
                std::string list;
                for (auto const& m : who)
                {
                    if (!list.empty())
                        list += ",";
                    list += m.name + ":" + std::to_string(uint32(m.status));
                }
                SendAddon(player, "QWHO " + std::to_string(questId) + " " +
                                  (list.empty() ? std::string("-") : list));
            }
            return true;
        }

        // "QACCEPT <npcGuidHex> <questId> <nombre;nombre>"
        // "QTURN   <npcGuidHex> <questId> <recompensa> <nombre;nombre> [1]"
        // QCATCH comparte el analisis con QACCEPT: mismos tres campos y el
        // mismo guid de PNJ. Separar la rama habria duplicado el unico trozo
        // delicado -- el hex de 64 bits -- por un `if` de una linea.
        //
        // EL `1` FINAL DE `QTURN` ES "FORZAR", Y VA DETRAS A PROPOSITO. La
        // regla de este canal es que los campos nuevos van DELANTE, pero esa
        // regla protege al TITULO de una mision, que lleva espacios y es el
        // resto de la linea por definicion. Aqui el ultimo campo es la lista de
        // nombres separados por `;`, sin un solo espacio, asi que `>>` la corta
        // entera y deja el flag detras.
        //
        // Y detras es donde tiene que ir para que las dos direcciones degraden:
        // un addon viejo no lo manda y el servidor lee `force = false`, que es
        // el comportamiento de siempre. Delante, un mensaje viejo habria metido
        // los NOMBRES en el flag.
        if (verb == "QACCEPT" || verb == "QTURN" || verb == "QCATCH")
        {
            std::istringstream in(rest);
            std::string guidHex;
            uint32 questId = 0, reward = 0;
            std::string names;
            int forceFlag = 0;

            if (!(in >> guidHex >> questId))
                return false;
            if (verb == "QTURN" && !(in >> reward))
                return false;
            if (!(in >> names))
                return false;
            if (verb == "QTURN")
                in >> forceFlag;   // opcional: ver arriba

            uint64 raw = 0;
            { std::istringstream hx(guidHex); hx >> std::hex >> raw; }
            if (!raw)
                return false;

            std::vector<std::string> const list = SplitList(names, ';');
            int ok = 0, bad = 0;
            std::string why;
            bool ran;

            std::vector<std::string> notes;

            if (verb == "QACCEPT")
                ran = rts::quests::Accept(player, ObjectGuid(raw), questId, list, ok, bad, &why);
            else if (verb == "QCATCH")
                ran = rts::quests::CatchUp(player, ObjectGuid(raw), questId, list, ok, bad, notes, &why);
            else
                ran = rts::quests::TurnIn(player, ObjectGuid(raw), questId, reward, list,
                                          ok, bad, notes, forceFlag != 0, &why);

            if (!ran)
            {
                SendAddon(player, "QERR " + std::to_string(questId) + " " + why);
                return true;
            }

            // UNA LINEA POR COMPANERO, y no un recuento. "2 bien, 1 mal" no
            // dice cual ni por que, y aqui el por que es la mitad del valor: a
            // uno le puede faltar la cadena (que esto arregla) y a otro el
            // nivel (que no). Van por `Reply` y no por el canal de addon porque
            // son para leer, no para dibujar.
            for (std::string const& n : notes)
                Reply(player, "RTS: " + n);

            SendAddon(player, "QDONE " +
                              std::string(verb == "QACCEPT" ? "A" : verb == "QCATCH" ? "C" : "T") + " " +
                              std::to_string(questId) + " " + std::to_string(ok) + " " +
                              std::to_string(bad));

            // La lista se vuelve a mandar sola. Es el mismo razonamiento que en
            // `BAGOK`: el estado de una mision despues de aceptarla lo sabe el
            // servidor exactamente y el cliente solo aproximadamente -- una
            // cadena de misiones puede desbloquear la siguiente, que ahora
            // aparece en el mismo NPC.
            std::vector<rts::quests::Offer> offers;
            rts::quests::Look(player, ObjectGuid(raw), offers);
            SendQuestList(player, guidHex, offers);
            return true;
        }

        // --- command mode -------------------------------------------------
        // "CDQ <nombre> <id,id,...>" -> "CD <nombre> <id:queda:total,...>".
        //
        // Los enfriamientos de los hechizos que la consola tiene PUESTOS ahora
        // mismo. El cliente no puede saberlos: `GetSpellCooldown` es de tu
        // libro, y estos son de un bot.
        //
        // SOLO VUELVEN LOS QUE ESTAN ENFRIANDO, que casi siempre son ninguno o
        // uno. Contestar los veinte cada vez seria mandar diecinueve ceros dos
        // veces por segundo para siempre.
        //
        // Y SE CONTESTA AUNQUE LA LISTA SALGA VACIA, con un "-". Sin eso el
        // addon no puede distinguir "nada enfriando" de "la pregunta se perdio",
        // y la diferencia importa: en el primer caso hay que APAGAR las ruedas
        // que hubiera puestas.
        if (verb == "CDQ")
        {
            std::istringstream in(rest);
            std::string name, list;
            if (!(in >> name))
                return false;
            in >> list;

            std::vector<uint32> ids;
            {
                std::istringstream ls(list);
                std::string one;
                while (std::getline(ls, one, ','))
                {
                    uint32 const id = static_cast<uint32>(std::atoi(one.c_str()));
                    if (id)
                        ids.push_back(id);
                }
            }

            auto const cds = rts::command::Cooldowns(player, name, ids);

            std::string chunk;
            for (auto const& cd : cds)
            {
                std::string const piece = std::to_string(cd.id) + ':' +
                                          std::to_string(cd.remainMs) + ':' +
                                          std::to_string(cd.totalMs);
                if (chunk.size() + piece.size() + 2 > 200)
                {
                    SendAddon(player, "CD " + name + " " + chunk);
                    chunk.clear();
                }
                if (!chunk.empty())
                    chunk += ",";
                chunk += piece;
            }
            SendAddon(player, "CD " + name + " " + (chunk.empty() ? "-" : chunk));
            return true;
        }

        // "BARS <nombre>" -> el catalogo de hechizos de ese personaje: primero
        // su barra de acciones (lo que TU colocaste jugandolo) y detras todo lo
        // demas que sepa, por nombre.
        //
        // ACEPTA TU PROPIO NOMBRE desde 0.37.0. Antes no, y por eso tu heroe
        // salia sin hechizos: ver `SpellSubject` en `RtsCommandMode.cpp`.
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
            //
            // CADA HECHIZO VA COMO `id:letra`. La letra es el TIPO, y la decide
            // este lado porque el cliente no puede: `IsHarmfulSpell` toma un
            // nombre o un indice de TU libro, y el bot conoce hechizos que tu
            // no. Ver `docs/HECHIZOS-COLA.md` §1.
            //
            // Un addon anterior lee `id:letra` con su `tonumber` y se queda con
            // el numero, asi que anadir la letra no rompe a nadie; y un mod-rts
            // anterior manda solo el numero, que el addon nuevo trata como el
            // tipo seguro. Las dos direcciones degradan a lo de antes en vez de
            // quedarse mudas.
            // Y DETRAS, SU ENFRIAMIENTO en milisegundos, solo cuando tiene
            // uno propio: `id:letra` sigue siendo lo que se manda de la mayoria
            // de los hechizos, que no enfrian por su cuenta. El addon lee el
            // tercer campo si esta y se queda con el global si no, asi que un
            // addon anterior -- que corta en el segundo `:` -- no se entera, y
            // un mod-rts anterior deja al addon nuevo como estaba.
            std::string chunk;
            for (auto const& sp : spells)
            {
                std::string piece = std::to_string(sp.id) + ':' + sp.type;
                if (sp.cooldownMs)
                    piece += ':' + std::to_string(sp.cooldownMs);
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

        // "CASTQ <bot> <spellid> [targetGuidHex]" -- como CAST, pero si el hueco
        // esta ocupado ESPERA en vez de fallar.
        //
        // Es el mismo mensaje que `CAST` con una letra mas, a proposito: el
        // addon elige uno u otro segun la version del servidor que tenga
        // delante, y sin cola sigue funcionando todo como antes.
        if (verb == "CASTQ")
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

            rts::queue::Push(player, bot, spellId, target);
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

        // "AUTO <0|1>" -- tu propio personaje con IA de playerbots, o sin ella.
        //
        // Lo manda el addon al ENTRAR y al SALIR del modo RTS, que es lo que
        // pidio el jugador el 2026-09-17: *"en modo normal EVIDENTEMENTE no
        // quiero que se comporte como un bot, porque estoy moviendo yo al
        // personaje. PERO EN MODO RTS si debe comportarse como un bot"*.
        //
        // Con IA tu heroe pelea solo y tiene rol como los demas; sin ella lo
        // llevas tu y su rol vuelve a ser la postura. La IA vive en memoria del
        // worldserver, asi que un reinicio la borra -- y por eso esto va atado
        // al modo y no a un comando que hay que acordarse de escribir.
        //
        // LA RESPUESTA LLEVA TRES CAMPOS Y LA PETICION DOS, que es como se
        // distingue del eco: el canal nos devuelve lo que mandamos (ver
        // `Link.lua`), y un "AUTO 1" nuestro no puede leerse como la
        // confirmacion del servidor. Y dice el estado REAL, no el pedido: si la
        // config del servidor lo prohibe, el addon tiene que enterarse.
        if (verb == "AUTO")
        {
            int want = 0;
            std::istringstream in(rest);
            if (!(in >> want))
                return false;

            std::string why;
            if (!rts::bots::SelfDrive(player, want != 0, &why))
                Reply(player, "RTS: " + why + ".");

            SendAddon(player, std::string("AUTO ") +
                      (rts::bots::Driven(player) ? "1" : "0") + " ok");
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

        // "UNTALENT <pestana> <fila> <columna>", los tres en base 1 -- que es
        // como los cuenta `GetTalentInfo` en el cliente.
        //
        // SE MANDA EL SITIO, NO EL IDENTIFICADOR. El addon tiene a mano el
        // numero de talento (`GetTalentLink` lo lleva dentro), y aun asi viaja
        // la casilla: fila y columna son lo que el jugador esta mirando y
        // significan lo mismo en las dos puntas, mientras que un identificador
        // del cliente obliga a que las dos listas esten ordenadas igual -- que
        // hoy lo estan y no hay nada que lo garantice.
        if (verb == "UNTALENT")
        {
            std::string tab, rest2, row, col;
            Split(rest, tab, rest2);
            Split(rest2, row, col);

            std::string code, detail;
            rts::talents::Remove(player,
                                 uint32(std::atoi(tab.c_str())),
                                 uint32(std::atoi(row.c_str())),
                                 uint32(std::atoi(col.c_str())),
                                 code, detail);

            SendAddon(player, "TALENT " + code + (detail.empty() ? "" : (" " + detail)));
            return true;
        }

        // "LFGCLEAR" -- quitarle a todo el grupo lo que le impide entrar en una
        // mazmorra: el castigo de desertor y cualquier resto de una cola
        // anterior. Deja el grupo como si no hubiera pedido nada.
        if (verb == "LFGCLEAR")
        {
            int deserters = 0, queues = 0;
            int const people = rts::dungeon::Clear(player, deserters, queues);
            SendAddon(player, "LFGCLEAR " + std::to_string(people) + " " +
                              std::to_string(deserters) + " " + std::to_string(queues));
            return true;
        }

        // "XP UP" / "XP DOWN" / "XP" -- el dial de experiencia del mundo.
        //
        // EL VERBO LLEVA LA DIRECCION, NO EL NUMERO. Cuanto vale un paso y
        // hasta donde se puede llegar se deciden aqui, que es donde esta el
        // dial: un "XP +10" desde el cliente seria un addon editado -- o un
        // `/rtscmd` a mano -- capaz de dejar el mundo al 0% de experiencia sin
        // que nada de este lado tenga ocasion de decir que no.
        //
        // Siempre contesta con el % que ha quedado, tambien cuando no ha
        // cambiado nada: quien pregunta necesita el numero para escribirlo, y
        // "no contesto" ya significa otra cosa (mod-rts viejo).
        if (verb == "XP")
        {
            // DE CINCUENTA EN CINCUENTA. Empezo en diez y con las tasas del
            // fichero a 1 -- o sea, con el dial leyendose como el multiplicador
            // entero -- pasar de x1 a x2 costaba diez pulsaciones. Un paso de
            // cincuenta pone el doble a dos clicks y deja la escalera en
            // numeros redondos: 50, 100, 150, 200.
            constexpr int kStep = 50;

            std::string const arg = Upper(rest);
            int pct;
            if (arg == "UP")
                pct = rts::xp::Step(+kStep);
            else if (arg == "DOWN")
                pct = rts::xp::Step(-kStep);
            else
                pct = rts::xp::Percent();

            SendAddon(player, "XP " + std::to_string(pct));
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

            // === UNA HIERBA NO ES SUELO ==============================
            //
            // Antes de tratar el click como un movimiento se mira si donde se
            // pincho hay un nodo de recoleccion. Si lo hay, el click NO es una
            // orden de movimiento para nadie -- y ese "para nadie" es el
            // arreglo entero.
            //
            // Una hierba se recoge con un LANZAMIENTO, y `MoveSelf` es
            // `StopMoving` + `MovePoint`: moverse cancela el lanzamiento que el
            // cliente acaba de empezar con ese mismo click. Medido el
            // 2026-09-13 con la prueba de siempre -- sin nada seleccionado la
            // hierba se recoge, con el grupo cogido no -- que es la misma que
            // cerro el parpadeo del botin del cadaver.
            //
            // Se busca contra el punto del RAYO cuando lo hay. El punto de un
            // destino no vale: lleva ya el desplazamiento de la formacion, asi
            // que apunta al sitio del bot y no a donde pincho el jugador.
            if (intent == rts::orders::CLICK_MOVE)
            {
                float nx = gx, ny = gy, nz = gz;
                if (!fixed)
                {
                    // Sin rayo resuelto -- DLL viejo, o el rayo no corto -- se
                    // usa el destino del propio jugador. Es menos exacto por el
                    // desplazamiento de la formacion, pero con el radio de dos
                    // yardas todavia acierta un nodo que tienes a los pies, que
                    // es el caso que importa.
                    bool have = false;
                    for (Dest const& d : dests)
                        if (d.name == selfName)
                        {
                            nx = d.x; ny = d.y; nz = d.z;
                            have = true;
                            break;
                        }
                    if (!have && !dests.empty())
                    {
                        nx = dests.front().x;
                        ny = dests.front().y;
                        nz = dests.front().z;
                        have = true;
                    }
                    if (!have)
                        nx = ny = nz = 0.0f;
                }

                if (GameObject* node = rts::orders::NodeAt(player, nx, ny, nz))
                {
                    // Los bots se quedan al margen, igual que con el cadaver:
                    // un nodo lo recoge UNO, y el que tiene la profesion y las
                    // bolsas eres tu. Mandar a cinco bots a pisarlo no recoge
                    // nada y deshace la formacion.
                    bool const reach = rts::orders::SelfGather(player, node);

                    // Y SE DICE SIEMPRE, porque este es el unico click del modo
                    // que puede acabar sin mover a nadie: sin una linea, "el
                    // grupo no se mueve" y "el click se perdio" se ven igual.
                    SendAddon(player, std::string("DID GATHER ") +
                        (reach ? "1 " : "0 ") + node->GetName());
                    return true;
                }
            }

            int moved = 0;
            int lost = 0;
            for (Dest const& d : dests)
            {
                if (d.name == selfName)
                {
                    moved += rts::orders::MoveSelf(player, d.x, d.y, d.z) ? 1 : 0;
                    continue;
                }

                // El mismo troceo sobre el navmesh que el camino de la ruta, y
                // por el mismo sitio: un click lejos o al otro lado de un monte
                // es el caso de todos los dias. Ver `orders::NextLeg`.
                float lx = d.x, ly = d.y, lz = d.z;
                int kind = rts::orders::LEG_FULL;
                if (rts::orders::MoveBot(player, d.name, d.x, d.y, d.z, &lx, &ly, &lz, &kind))
                    ++moved;
                else if (kind == rts::orders::LEG_NONE)
                    ++lost;

                std::ostringstream out;
                out << "MOVEAT " << d.name << ' ' << std::fixed << std::setprecision(2)
                    << lx << ' ' << ly << ' ' << lz << ' ' << kind;
                SendAddon(player, out.str());
            }

            if (lost > 0)
                Reply(player, "RTS: " + std::to_string(lost) +
                      " sin camino andando hasta ahi -- no van. Prueba un punto mas cerca "
                      "o rodeando.");

            SendAddon(player, "DID MOVE " + std::to_string(moved));
            return true;
        }

        if (verb == "MOVE")
            return DispatchMove(player, rest);

        if (verb == "FOLLOW")
            return DispatchFollow(player, rest);

        // "HOLD Bot;Otro" -- quieto donde este cada uno.
        // "SUMMON Bot;Otro" -- a tu lado, ya.
        //
        // Las dos tienen la misma forma que FOLLOW -- una lista de nombres y
        // nada mas -- y las dos sustituyen a una linea de chat que el bot solo
        // leia cuando le tocaba pensar.
        if (verb == "HOLD" || verb == "SUMMON")
        {
            bool const hold = (verb == "HOLD");
            int done = 0;
            for (std::string const& name : SplitList(rest, ';'))
            {
                if (hold ? rts::orders::HoldBot(player, name)
                         : rts::orders::SummonBot(player, name))
                    ++done;
            }
            SendAddon(player, "DID " + verb + " " + std::to_string(done));
            return true;
        }

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

        // "QAI 0|1" -- apagar (0) o devolver (1) la maquinaria de misiones de la
        // IA de cada bot. El porque entero, con las lineas de mod-playerbots,
        // esta en `RtsQuests.h`: en una palabra, la estrategia `quest` entrega
        // sola al ABRIR la ventana del PNJ, y lo que se pidio es que espere a
        // que pulses.
        //
        // Va por el mismo camino que `LOOT` y por el mismo motivo: es estado de
        // la IA de cada bot, vive en su memoria, y hay que reponerlo cuando el
        // grupo cambia porque el que entra nace con la de fabrica.
        // "QDROP <questId> <nombre;nombre>" -- abandonarla por el grupo. Un solo
        // sentido. Va aqui y no en la familia de `QACCEPT` porque no lleva PNJ:
        // tirar una mision no se hace delante de nadie.
        if (verb == "QDROP")
        {
            std::istringstream in(rest);
            uint32 questId = 0;
            std::string names;
            if (!(in >> questId >> names))
                return false;

            int ok = 0, bad = 0;
            std::string why;
            std::vector<std::string> notes;

            if (!rts::quests::Drop(player, questId, SplitList(names, ';'), ok, bad, notes, &why))
            {
                SendAddon(player, "QERR " + std::to_string(questId) + " " + why);
                return true;
            }

            for (std::string const& n : notes)
                Reply(player, "RTS: " + n);

            SendAddon(player, "QDONE D " + std::to_string(questId) + " " +
                              std::to_string(ok) + " " + std::to_string(bad));
            return true;
        }

        if (verb == "QAI")
        {
            bool const on = !rest.empty() && rest[0] == '1';
            int const n = rts::quests::SetGroupAI(player, on);
            SendAddon(player, "DID QAI " + std::to_string(n) + (on ? " 1" : " 0"));
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

        // "PORTED" -- el cliente avisa de que ya recargo el mundo.
        //
        // Es la mitad de cliente de la recarga del cambio de personaje. El
        // acuse que manda el propio cliente (`MSG_MOVE_WORLDPORT_ACK`) no se
        // puede ver desde un modulo -- ver `RtsSwap.h` -- asi que lo dice el
        // addon desde `PLAYER_ENTERING_WORLD`, que es el momento exacto en que
        // su mundo vuelve a estar en pie.
        //
        // No contesta nada: llega en cualquier entrada al mundo, incluidas las
        // que no son un cambio, y `ClientPorted` ya devuelve false cuando no hay
        // ninguno esperando. Un "no era para ti" por cada login seria ruido.
        if (verb == "PORTED")
        {
            rts::swap::ClientPorted(player);
            return true;
        }

        // "REBARS" -- vuelve a mandarme las barras, que ya estoy listo.
        //
        // EL CLIENTE TIRA LA ACTUALIZACION SI TODAVIA NO SE SABE QUIEN ES, y eso
        // es lo que rompia las barras del cambio de personaje. Desensamblado su
        // manejador de `SMSG_ACTION_BUTTONS` (`0x006D8750`):
        //
        //     006D876D  call 0x4D3790     ; ¿quien es el jugador activo?
        //     006D8780  call 0x4D4DB0     ; su objeto
        //     006D8788  cmp esi, 2        ; estado 2 -> marca y sale
        //     ...                         ; estados 0 y 1 -> leer 144 dwords
        //     006D87D3  cmp [ebp-0xC], 1  ; ¿estado 1?
        //     006D87D7  jne 0x6D8863      ;   si no, no valida ni refresca
        //     006D87E0  cmp eax, edi      ; ¿hay objeto de jugador? (edi vale 0)
        //     006D87E2  je  0x6D8863      ;   si NO -> se salta todo el repaso
        //
        // O sea que la rafaga de login llega **antes** de que el cliente haya
        // adoptado su identidad nueva -- el objeto propio viaja en esa misma
        // rafaga -- y en ese instante `eax` es nulo: los datos entran en el array
        // pero **no se validan ni se repintan**, y el estado 2 ni siquiera llega
        // a marcar nada. De ahi que las barras se quedaran con lo anterior y que
        // un `/reload` a veces lo arreglara (repinta desde el array) y a veces
        // no (cuando el array tampoco se habia llenado).
        //
        // No se puede adivinar cuando esta listo el cliente, asi que lo dice el:
        // el addon manda esto **despues** de comprobar que su guid coincide con
        // el que el servidor le dijo.
        if (verb == "REBARS")
        {
            player->SendActionButtons(2);
            player->SendInitialActionButtons();
            return true;
        }

        // "MYBARS" -- que tiene el SERVIDOR en las doce primeras casillas.
        //
        // Diagnostico, y existe porque "las barras no son las del personaje"
        // tiene dos causas con arreglos opuestos y desde el cliente se ven
        // igual: o el servidor manda otra cosa (transporte), o manda justo eso
        // y lo que hay guardado en `character_action` no es lo que el jugador
        // recuerda haber puesto (datos). Comparando esta linea con lo que pinta
        // el cliente se sabe cual de las dos en un vistazo.
        //
        // No sirve el verbo `BARS` que ya existe: pasa por `ResolveBot`, que
        // rechaza a proposito que te resuelvas a ti mismo.
        if (verb == "MYBARS")
        {
            std::string out;
            for (uint8 slot = 0; slot < 12; ++slot)
            {
                ActionButton const* b = player->GetActionButton(slot);
                if (!out.empty())
                    out += " ";
                if (!b || !b->GetAction())
                    out += "-";
                else
                    out += std::to_string(uint32(b->GetType())) + ":" +
                           std::to_string(b->GetAction());
            }
            SendAddon(player, "MYBARS " + out);
            return true;
        }

        // "WHOAMI" -- ¿como se llama el personaje que tengo en la sesion?
        //
        // NO ES REDUNDANTE CON `UnitName("player")`, y ese es justo el punto:
        // en el cliente esa llamada NO mira el objeto. `UnitName` (`0x0060E740`)
        // compara la unidad con "player" y, si lo es, devuelve un buffer
        // estatico (`0x00C79D18` via `0x006B1060`) que solo rellena la pantalla
        // de seleccion de personaje -- el paso que el cambio se salta. Asi que
        // despues de un cambio el cliente se llama a si mismo por el nombre
        // anterior, y quien sabe la verdad es el servidor.
        //
        // Contesta `IAM` y no `SWAPPED` A PROPOSITO: `SWAPPED` significa
        // "acabas de cambiar" y el addon recarga la interfaz con el; `IAM` es
        // solo una respuesta y no dispara nada. Un mismo verbo para las dos
        // cosas haria que preguntar quien eres recargara la interfaz.
        if (verb == "WHOAMI")
        {
            // CON EL GUID DETRAS, y no por gusto: el nombre por si solo no deja
            // COMPROBAR nada. Si el cliente no llego a cambiar de identidad, un
            // `IAM Bob` le hace ensenar "Bob" siendo todavia Avy -- o sea que el
            // aviso taparia el fallo en vez de destaparlo. Con el guid, el addon
            // contrasta contra `UnitGUID("player")`, que es la unica identidad
            // del cliente que no miente, y canta si no cuadran.
            SendAddon(player, "IAM " + player->GetName() + " " +
                      std::to_string(player->GetGUID().GetRawValue()));
            return true;
        }

        // "SWAP <nombre>" -- cambiar de personaje pasando por la lista.
        //
        // CON PANTALLA DE CARGA, y no por pereza: el login sin ella reventaba el
        // cliente con ERROR #132. Ver `RtsSwap.h`. El servidor te saca a la
        // lista de personajes y hace las dos partes que a mano no se pueden
        // hacer en el orden correcto; entrar lo pulsas tu.
        if (verb == "SWAP")
        {
            std::string why;
            if (!rts::swap::To(player, rest, &why))
                Reply(player, "RTS: no puedo cambiar -- " + why + ".");
            return true;
        }

        // "RESET Nombre;Otro" -- estrategias de fabrica y a seguirte.
        if (verb == "RESET")
        {
            int done = 0;
            for (std::string const& n : SplitList(rest, ';'))
            {
                if (rts::orders::ResetBot(player, n))
                    ++done;
            }
            if (done > 0)
                Reply(player, "RTS: " + std::to_string(done) +
                              " devuelto(s) a su comportamiento de fabrica.");
            return done > 0;
        }

        if (verb == "ATTACK")
            return DispatchAttack(player, rest);

        // "CHAIN <g1;g2;g3> <Nombre;Otro>" -- ataque encadenado.
        // "CHAINOFF"                       -- parar.
        //
        // La lista llega ENTERA cada vez, incluso al anadir uno solo. Ver
        // `RtsChain.h`: un protocolo incremental necesita que las dos partes
        // esten de acuerdo sobre el estado, y aqui hay tres cosas que lo mueven
        // sin avisar (el enemigo muere, huye, o lo mata otro).
        if (verb == "CHAINOFF")
        {
            rts::chain::Stop(player);
            SendAddon(player, "CHAINEND");
            return true;
        }

        if (verb == "CHAIN")
        {
            std::istringstream in(rest);
            std::string guids, names;
            if (!(in >> guids >> names))
                return false;

            std::vector<ObjectGuid> targets;
            for (std::string const& g : SplitList(guids, ';'))
            {
                uint64 raw = 0;
                { std::istringstream hx(g); hx >> std::hex >> raw; }
                if (raw)
                    targets.push_back(ObjectGuid(raw));
            }

            if (!rts::chain::Set(player, targets, SplitList(names, ';')))
            {
                SendAddon(player, "CHAINEND");
                return true;
            }

            ObjectGuid cur;
            int done = 0, total = 0;
            if (rts::chain::Current(player, cur, done, total))
            {
                std::ostringstream out;
                out << "CHAINAT " << done << ' ' << total << ' '
                    << std::hex << cur.GetRawValue();
                SendAddon(player, out.str());
            }
            return true;
        }

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

        // "PATHQ x y z Nombre;Otro" -- QUE DICE LA MALLA SOBRE ESTE VIAJE.
        //
        // El diagnostico de `/rts path`, y existe por la misma razon que
        // `/rts aim`: "sigue cruzando la montana" y "no hay camino y nadie lo
        // dice" se ven igual en pantalla. Contesta por el chat, una linea por
        // unidad, con las banderas de `PathGenerator` por su nombre.
        //
        // Sin nombres contesta por TI, que es el caso que mas se mira.
        if (verb == "PATHQ")
        {
            std::istringstream in(rest);
            float x = 0.0f, y = 0.0f, z = 0.0f;
            if (!(in >> x >> y >> z))
                return false;

            std::string names;
            in >> names;

            Reply(player, "RTS: camino hacia " +
                  std::to_string(int(x)) + " " + std::to_string(int(y)) + " " +
                  std::to_string(int(z)));

            bool any = false;
            for (std::string const& n : SplitList(names, ';'))
            {
                if (n.empty())
                    continue;
                Player* who = (n == player->GetName())
                            ? player : rts::bots::Resolve(player, n);
                if (!who)
                    continue;
                any = true;
                Reply(player, "RTS:   " + n + ": " +
                      rts::orders::PathReport(who, x, y, z));
            }

            if (!any)
                Reply(player, "RTS:   " + player->GetName() + ": " +
                      rts::orders::PathReport(player, x, y, z));
            return true;
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

        // EL VERBO `POSSESS` SE BORRO EN 0.49.0 con la posesion entera. Un
        // verbo que el servidor no conoce no da error: no contesta -- asi que
        // un addon viejo contra este servidor se queda esperando y el jugador
        // ve "no pasa nada", que es el modo de fallo de siempre. Por eso la
        // version del modulo sube: el addon 1.14.0 ya no lo manda.

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
                // "CAM SPEC <0|1>" -- EL SONDEO de la camara libre del cliente.
                //
                // Pone los dos flags de jugador que abren la API de
                // comentarista y manda el SMSG_COMMENTATOR_STATE_CHANGED que
                // enciende el modo. Todo el porque -- con las direcciones
                // desensambladas de este Wow.exe y las lineas del nucleo --
                // esta en la cabecera de `RtsCamera.h`, en `Spectate`.
                //
                // NO TOCA la camara de siempre: el Puppet sigue igual, asi que
                // esto se puede probar sin arriesgar nada de lo que ya funciona.
                if (sub == "SPEC")
                {
                    bool const on = (value == "1" || value == "on" || value == "ON");
                    if (!rts::camera::Spectate(player, on))
                    {
                        Reply(player, "RTS spec: no se pudo (sin sesion).");
                        return true;
                    }
                    // Contesta por el canal del addon y no por el chat, porque
                    // el sondeo NECESITA secuenciar: el paquete que enciende el
                    // modo tiene que haber llegado antes de que Lua llame a
                    // `CommentatorSetCamera`. Una linea de chat no le dice al
                    // addon cuando puede seguir.
                    SendAddon(player, on ? "SPEC 1" : "SPEC 0");
                    return true;
                }
                // "CAM SPECARM <0|1>" -- la SEGUNDA mitad del sondeo: mete la
                // camara en el modo libre (6) o la devuelve al normal (1).
                //
                // Va aparte de `SPEC` porque los flags tardan un tick en llegar
                // al cliente y el paquete sale ya. Quien decide que ya se puede
                // armar es el cliente, no un retraso adivinado: el addon sondea
                // `CommentatorGetCamera()` y pide esto cuando contesta. El
                // porque entero esta en `RtsCamera.h`.
                if (sub == "SPECARM")
                {
                    bool const on = (value == "1" || value == "on" || value == "ON");
                    if (!rts::camera::Arm(player, on))
                    {
                        Reply(player, "RTS spec: no se pudo armar (sin sesion).");
                        return true;
                    }
                    SendAddon(player, on ? "SPECARM 1" : "SPECARM 0");
                    return true;
                }
                // "CAM CTRL <0|1>" -- QUIEN CONDUCE TU CUERPO.
                //
                // 1 = el servidor (lo que hacia falta para que `MoveSelf`
                // mueva tu propio heroe), y a cambio el cliente se queda sin
                // espada y sin click derecho. 0 = el cliente, que es lo de
                // fabrica desde 0.47.0. El porque entero, con las direcciones,
                // en `RtsCamera.cpp` (`Arm`).
                if (sub == "CTRL" || sub == "CONTROL")
                {
                    bool const on = (value == "1" || value == "on" || value == "ON");
                    rts::camera::HoldControl(player, on);
                    SendAddon(player, on ? "CTRL 1" : "CTRL 0");
                    Reply(player, on
                        ? "RTS: conduce el SERVIDOR -- sin espada ni click derecho."
                        : "RTS: conduce el CLIENTE -- raton normal.");
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

// EL UNICO PAQUETE QUE ESTE MODULO LE ESCONDE AL CLIENTE.
//
// `WorldSession::SendPacket` pregunta a `CanPacketSend` por cada paquete que
// sale (`WorldSession.cpp:356`), asi que desde aqui se puede descartar uno. Se
// usa para exactamente una cosa: el `SMSG_LOGOUT_COMPLETE` del cambio de
// personaje, que es lo que mandaria al cliente a la pantalla de seleccion --
// donde su tabla de eventos pasa de 722 entradas a 41 y la rafaga de login que
// viene detras lo mata con ERROR #132. Ver `RtsSwap.h`.
//
// LA DECISION ES QUE EL FILTRO NO VIVE AQUI. Este gancho solo pregunta, y
// `rts::swap` contesta que si unicamente durante la llamada a `LogoutPlayer` de
// la sesion que esta cambiando. Un filtro con su propia idea de cuando actuar
// es un filtro que algun dia se traga el logout de alguien que si queria salir.
//
// Corre para TODO paquete saliente del servidor, asi que la comprobacion barata
// va primero y la cara -- buscar la sesion -- ni se llega a hacer si no hay
// ningun cambio en curso.
class RtsPacketScript : public ServerScript
{
public:
    RtsPacketScript() : ServerScript("RtsPacketScript", {
        SERVERHOOK_CAN_PACKET_SEND
    }) { }

    bool CanPacketSend(WorldSession* session, WorldPacket const& packet) override
    {
        return !rts::swap::SuppressOutgoing(session, packet.GetOpcode());
    }

    // HUBO AQUI UN `CanPacketReceive` PARA VER EL ACUSE DE RECARGA DEL CLIENTE,
    // y esta borrado porque **no podia dispararse nunca**. El
    // `MSG_MOVE_WORLDPORT_ACK` es `STATUS_TRANSFER`, y el nucleo solo procesa
    // esa clase de paquete cuando el jugador NO esta en el mundo
    // (`WorldSession.cpp:497`); durante el cambio el heroe sigue dentro, asi que
    // el acuse se tira antes de llegar a ningun gancho. Lo manda el addon en su
    // lugar (`PORTED`).
};

// LO QUE LE MANDAN A UN BOT. Es el unico gancho por el que se ve: sus sesiones
// no tienen socket y `WorldSession::SendPacket` se vuelve antes de llegar al
// gancho de envio normal. Ver `RtsLfg.h`.
class RtsBotPacketScript : public PlayerbotScript
{
public:
    RtsBotPacketScript() : PlayerbotScript("RtsBotPacketScript") { }

    void OnPlayerbotPacketSent(Player* player, WorldPacket const* packet) override
    {
        if (packet && packet->GetOpcode() == SMSG_LFG_PROPOSAL_UPDATE)
            rts::dungeon::NoteProposal(player, packet);
    }
};

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
        // La camara, que si se queda: dejarla corriendo en un logout deja una
        // criatura huerfana y un cliente cuyo mover ya no existe.
        rts::camera::Abandon(player);

        // AQUI HABIA UN SEGURO CONTRA UN `ABORT()`, y se fue en 0.49.0 con la
        // posesion. Un `Player` charmado sin aura llegaba a
        // `Player::RemoveFromWorld` -> `StopCastingCharm`, que solo sabe quitar
        // auras, no encontraba ninguna y respondia con `ABORT()`
        // (`Player.cpp:9556`) -- el worldserver muerto, visto el 2026-09-03.
        //
        // Lo unico de este modulo que charmaba a un `Player` era `PossessBot`.
        // Sin el, la guarda no podia dispararse nunca, y una comprobacion que
        // no puede dispararse es peor que no tenerla: parece cubrir un caso que
        // en realidad esta descubierto. Ademas habria pisado el unico charm de
        // `Player` que queda en el juego -- el Control Mental de un sacerdote --
        // que lleva aura de verdad y el nucleo deshace solo.
        rts::orders::ForgetPlayer(player);
        rts::command::ReleaseAll(player);
        // Y LA COLA. Un hechizo esperando su hueco guarda el guid del maestro;
        // sin esto seguiria reintentando ocho segundos sobre alguien que ya no
        // esta -- `Update` lo resolveria a nulo y lo tiraria, pero decirlo aqui
        // es lo que hace que el caso no dependa de que el otro lado se acuerde.
        rts::queue::Drop(player);
        // The dynobjects are already gone by now (the core drops every one when
        // the player leaves the map); this only clears our slot bookkeeping so
        // the next login does not start with a table of dead guids.
        rts::marks::ForgetPlayer(player);
        rts::chain::ForgetPlayer(player);
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

        // Aqui habia una segunda llamada a `ReleaseAnyPossession`, y esta SI
        // era load-bearing mientras la posesion existio: un cambio de mapa pasa
        // por `RemoveFromWorld` igual que un logout. Se va con ella en 0.49.0,
        // y con las dos se va tambien el camino que quedaba sin cubrir --
        // `Player::ActivateTaxiPathTo` (`Player.cpp:10481`) llama a
        // `StopCastingCharm` y no tiene gancho.
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

// PONER AL DIA A UN PERSONAJE: lo que venderia su entrenador, y la mision de
// clase que le toque.
//
// === LOS DOS MOMENTOS, Y POR QUE SON DOS =================================
//
// SUBIR DE NIVEL es el unico instante en que cambia QUE puede aprender un
// personaje y QUE misiones de clase alcanza. Preguntarlo en cualquier otro
// momento seria preguntar por algo que no ha cambiado, y por eso no hay tick.
//
// ENTRAR AL MUNDO es el otro, y no sobra: un personaje puede haber llegado a
// nivel 40 antes de que esto existiera, o con esto apagado, o -- el caso que lo
// pidio -- puede ser un alt que acabas de meter con `.playerbots bot add`. Ese
// alt no va a subir de nivel en el momento de entrar, asi que sin esta segunda
// puerta se quedaria atrasado hasta la siguiente subida.
//
// LAS DOS LLAMAN A LO MISMO, y eso es lo que hace que "si ya esta al dia, no
// tocar nada" salga gratis en vez de ser una comprobacion aparte: las dos
// mitades ya preguntan antes de actuar. `Learn` se apoya en `CanTeachSpell`,
// que contesta `Known` de todo lo que ya sabe, y `GrantClassQuest` lo primero
// que hace es mirar el registro. Con todo al dia las dos devuelven cero y no se
// escribe ni se dice nada.
//
// === Y POR QUE LOS BOTS ALEATORIOS SE QUEDAN FUERA AL ENTRAR ==============
//
// Solo en la puerta de ENTRAR, y solo ellos. Hoy no hay ninguno
// (`RandomBotAutologin = 0`), pero `MinRandomBots` son quinientos, y el dia que
// se enciendan entrarian quinientos personajes a la vez: quinientos barridos del
// entrenador y, peor, quinientas misiones de clase escritas en quinientos
// personajes que no juega nadie. Al subir de nivel no se filtra, porque ahi
// entran de uno en uno y cuando de verdad les toca.
//
// LO QUE NO HACE NINGUNA DE LAS DOS: tocar la entrega. La mision se entrega en
// el entrenador como siempre.
class RtsProgressScript : public PlayerScript
{
public:
    RtsProgressScript() : PlayerScript("RtsProgressScript", {
        PLAYERHOOK_ON_LEVEL_CHANGED,
        PLAYERHOOK_ON_LOGIN
    }) { }

    void OnPlayerLevelChanged(Player* player, uint8 oldLevel) override
    {
        // BAJAR DE NIVEL TAMBIEN PASA POR AQUI. El gancho se llama "cambio de
        // nivel" y no "subida": `.levelup -5` y el castigo de resurreccion del
        // nucleo entran por el mismo sitio. Aprender hechizos ahi seria darle a
        // un personaje de nivel 20 lo que ya tenia de 25.
        if (!player || player->GetLevel() <= oldLevel)
            return;

        CatchUp(player);
    }

    // Sale de `WorldSession::HandlePlayerLoginFromDB` (`CharacterHandler.cpp:1116`),
    // con el personaje ya metido en el mapa desde la linea 899 -- asi que
    // `IsInWorld` ya es cierto, que es lo primero que miran las dos mitades.
    //
    // Y VALE PARA UN BOT porque playerbots no tiene camino de entrada propio:
    // `PlayerbotHolder::HandlePlayerBotLoginCallback` llama a ese mismo
    // `HandlePlayerLoginFromDB` (`PlayerbotMgr.cpp:208`). O sea que `.playerbots
    // bot add Neferite` pasa por aqui sin enganchar nada suyo.
    void OnPlayerLogin(Player* player) override
    {
        if (!player)
            return;

        // La puerta de los aleatorios. Ver arriba: un bot sin maestro es uno de
        // los que pasea el servidor, no un alt que acabas de meter.
        if (rts::bots::Driven(player) && !rts::bots::MasterOf(player))
            return;

        CatchUp(player);
    }

private:
    static void CatchUp(Player* who)
    {
        if (sConfigMgr->GetOption<bool>("RTS.CatchUp.Train", true))
        {
            if (int const learned = rts::train::Learn(who))
                Announce(who, std::to_string(learned) +
                              (learned == 1 ? " habilidad nueva" : " habilidades nuevas"));
        }

        if (sConfigMgr->GetOption<bool>("RTS.CatchUp.ClassQuest", true))
        {
            if (uint32 const questId = rts::quests::GrantClassQuest(who))
            {
                Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
                Announce(who, "mision de clase: " +
                              (quest ? quest->GetTitle() : std::to_string(questId)));
            }
        }
    }

    // A QUIEN SE LE CUENTA.
    //
    // Un bot tiene sesion pero no tiene socket, asi que un mensaje a su ventana
    // de chat no sale del servidor: se escribe y se tira. El que quiere leerlo
    // es su maestro.
    //
    // Y se le pregunta a playerbots por el maestro en vez de mirar el lider del
    // grupo, que es lo que habia y era casi siempre lo mismo. CASI: un bot
    // recien metido con `.playerbots bot add` aun no esta en tu grupo cuando
    // entra al mundo, asi que por el camino del grupo el aviso del unico caso
    // que pidio esto se habria perdido siempre.
    static void Announce(Player* who, std::string const& what)
    {
        if (!rts::bots::Driven(who))
        {
            Reply(who, what);
            return;
        }

        if (Player* const master = rts::bots::MasterOf(who))
            Reply(master, who->GetName() + ": " + what);
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
    RtsWorldScript() : WorldScript("RtsWorldScript",
        { WORLDHOOK_ON_UPDATE, WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP }) { }

    // LA BASE DEL DIAL DE EXPERIENCIA SE ANOTA AQUI Y EN NINGUN OTRO SITIO:
    // este es el unico instante en que las tasas del nucleo son las del
    // fichero. Un momento despues ya llevan nuestro multiplicador encima, y
    // anotarlas entonces guardaria como base lo que ya estaba multiplicado --
    // o sea que cada recarga subiria la experiencia otra vez.
    void OnAfterConfigLoad(bool reload) override
    {
        rts::xp::CaptureBaseline();

        // Al arrancar NO se aplica todavia: los `worldstates` se leen mas
        // tarde, asi que aqui el % guardado seria 0 y saldria un 100% que no
        // es el que el jugador dejo puesto. De eso se encarga `OnStartup`.
        if (reload)
            rts::xp::Apply();
    }

    void OnStartup() override
    {
        rts::xp::Apply();
    }

    void OnUpdate(uint32 diff) override
    {
        rts::command::Update(diff);
        rts::queue::Update(diff);
        rts::chain::Update(diff);
        // EL CANAL DEL ADDON SIGUE VIVIENDO SOLO AQUI. `rts::swap` no sabe hablar
        // con el cliente y no hace falta que aprenda: devuelve a quien acaba de
        // entrar en su personaje nuevo y el aviso se manda desde el unico sitio
        // que conoce el prefijo y el formato.
        std::vector<Player*> justSwapped;
        rts::swap::Update(diff, &justSwapped);
        for (Player* swapped : justSwapped)
            SendAddon(swapped, "SWAPPED " + swapped->GetName() + " " +
                      std::to_string(swapped->GetGUID().GetRawValue()));
        rts::orders::UpdatePending(diff);
        rts::camera::Update(diff);
        rts::pets::Update(diff);
        rts::dungeon::Update(diff);
    }
};

void AddSC_mod_rts()
{
    // EL SUMIDERO DE LA COLA. Habla en su propio tick, asi que no puede esperar
    // a que alguien le pregunte; y el transporte es de este fichero y solo de
    // este, que es la separacion que este modulo si tiene bien hecha. Se le pasa
    // la funcion una vez, al cargar.
    rts::queue::SetSink([](Player* player, std::string const& body)
    {
        SendAddon(player, body);
    });

    new RtsPacketScript();
    new RtsBotPacketScript();
    new RtsChannelScript();
    new RtsProgressScript();
    new RtsCommandScript();
    new RtsWorldScript();
}
