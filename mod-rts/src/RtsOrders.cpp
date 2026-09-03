#include "RtsOrders.h"

#include "RtsBotApi.h"   // la unica puerta a mod-playerbots
#include "RtsCommandMode.h"   // ActionBarSpells, para la barra de posesion

#include "CharmInfo.h"   // CHARM_TYPE_POSSESS -- Unit.h only forward-declares CharmType
#include "SpellInfo.h"
#include "Creature.h"
#include "LootMgr.h"
#include "ObjectDefines.h"   // INTERACTION_DISTANCE
#include "Group.h"
#include "Log.h"
#include "Map.h"
#include "MapCollisionData.h"
#include "MotionMaster.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <unordered_map>

namespace
{
    // La resolucion del bot y la comprobacion de que esta en tu grupo viven en
    // `RtsBotApi`. Esto es un alias local para que el resto del fichero se siga
    // leyendo igual -- y el nombre largo se queda ahi a proposito: la
    // comprobacion de pertenencia al grupo no es un adorno, es lo unico que
    // impide que cualquiera mande los bots de otro sabiendo su nombre.
    Player* ResolveBot(Player* master, std::string const& name)
    {
        return rts::bots::Resolve(master, name);
    }
}

// NADIE CAMINA POR EL AIRE, Y EL CLIENTE NO ES QUIEN DECIDE DONDE ESTA EL SUELO.
//
// La Z de un click viene del cliente, y por buena que sea es su idea del
// terreno, no la del servidor -- que es quien tiene los vmaps y quien manda.
// Cuando las dos no coinciden el destino queda flotando, y un bot mandado a un
// destino flotante acaba flotando: se le vio en juego a media altura sobre un
// arbol.
//
// UpdateAllowedPositionZ es la funcion que el propio nucleo usa para esto, y se
// le pide a la UNIDAD que va a ir -- no al mapa a secas -- porque la respuesta
// depende de quien pregunta: quien puede nadar tiene permitido el agua, quien
// vuela tiene permitido el aire.
void rts::orders::GroundZ(WorldObject const* who, float x, float y, float& z)
{
    if (!who)
        return;

    float const before = z;
    who->UpdateAllowedPositionZ(x, y, z);
    if (std::fabs(z - before) > 0.5f)
        LOG_DEBUG("module.rts", "RTS: Z snapped {:.2f} -> {:.2f} at {:.1f} {:.1f}",
                  before, z, x, y);
}

namespace
{
    // Un paso de una yarda a lo largo del rayo. La colina mas estrecha que
    // importa mide bastante mas que eso, y el corte se afina despues con una
    // biseccion -- que es donde se gana la precision, no en el paso.
    constexpr float kRayStep = 1.0f;
    constexpr int   kRayBisect = 14;

    // Por debajo de esto la casilla no tiene datos de altura (INVALID_HEIGHT es
    // -100000 y el valor real de "no se" es -200000).
    constexpr float kNoHeight = -50000.0f;
}

bool rts::orders::GroundRay(Player const* who,
                            float ox, float oy, float oz,
                            float dx, float dy, float dz,
                            float maxDist,
                            float& hx, float& hy, float& hz)
{
    if (!who || !who->IsInWorld())
        return false;

    Map* map = who->GetMap();
    if (!map)
        return false;

    float const len = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 1e-4f)
        return false;
    dx /= len; dy /= len; dz /= len;

    if (maxDist < 1.0f || maxDist > 1000.0f)
        maxDist = 500.0f;

    // 1) Los MODELOS: edificios, puentes, arboles con colision. Esto si es una
    // interseccion de verdad, la misma que usa el nucleo para la linea de
    // vision, asi que no hay nada que aproximar.
    float vdist = maxDist + 1.0f;
    float vx = 0.0f, vy = 0.0f, vz = 0.0f;
    {
        float const ex = ox + dx * maxDist;
        float const ey = oy + dy * maxDist;
        float const ez = oz + dz * maxDist;

        float rx = 0.0f, ry = 0.0f, rz = 0.0f;
        if (map->GetMapCollisionData().GetStaticTree().GetObjectHitPos(
                ox, oy, oz, ex, ey, ez, rx, ry, rz, 0.0f))
        {
            vx = rx; vy = ry; vz = rz;
            vdist = std::sqrt((rx - ox) * (rx - ox) + (ry - oy) * (ry - oy) + (rz - oz) * (rz - oz));
        }

        // Y los objetos del mundo que se mueven (puertas, ascensores, un puente
        // que aparece). Se queda el mas cercano de los dos.
        rx = ry = rz = 0.0f;
        if (map->GetMapCollisionData().GetDynamicTree().GetObjectHitPos(
                who->GetPhaseMask(), ox, oy, oz, ex, ey, ez, rx, ry, rz, 0.0f))
        {
            float const d = std::sqrt((rx - ox) * (rx - ox) + (ry - oy) * (ry - oy) + (rz - oz) * (rz - oz));
            if (d < vdist)
            {
                vx = rx; vy = ry; vz = rz;
                vdist = d;
            }
        }
    }

    // 2) EL TERRENO, que no es un modelo y no se puede intersecar: es un campo
    // de alturas, asi que se anda el rayo hasta que deja de estar por encima.
    // El limite del paseo es el corte con los modelos, porque lo que hay detras
    // de una pared no se ha pinchado.
    float const walk = std::min(maxDist, vdist);
    float prev = 0.0f;
    bool crossed = false;
    float hit = 0.0f;

    for (float t = kRayStep; t <= walk; t += kRayStep)
    {
        float const px = ox + dx * t;
        float const py = oy + dy * t;
        float const pz = oz + dz * t;

        float const g = map->GetGridHeight(px, py);
        if (g < kNoHeight)
        {
            prev = t;       // sin datos ahi: no se puede decir que se haya cruzado
            continue;
        }

        if (pz <= g)
        {
            crossed = true;
            hit = t;
            break;
        }
        prev = t;
    }

    if (crossed)
    {
        // La biseccion es la que da la precision. Catorce vueltas dejan el corte
        // en menos de un milimetro de la yarda del paso.
        float lo = prev, hiT = hit;
        for (int i = 0; i < kRayBisect; ++i)
        {
            float const m = (lo + hiT) * 0.5f;
            float const px = ox + dx * m;
            float const py = oy + dy * m;
            float const pz = oz + dz * m;
            float const g = map->GetGridHeight(px, py);
            if (g >= kNoHeight && pz <= g)
                hiT = m;
            else
                lo = m;
        }

        hx = ox + dx * hiT;
        hy = oy + dy * hiT;
        hz = map->GetGridHeight(hx, hy);
        if (hz < kNoHeight)
            hz = oz + dz * hiT;
        return true;
    }

    if (vdist <= maxDist)
    {
        hx = vx; hy = vy; hz = vz;
        return true;
    }

    // El rayo se fue al cielo. Mejor no contestar que contestar cualquier cosa:
    // el addon se queda con su estimacion, que al menos esta delante.
    return false;
}

bool rts::orders::MoveBot(Player* master, std::string const& botName, float x, float y, float z)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    // The same strategy flip StayChatShortcutAction performs, minus the
    // TellMaster that made the bot stop and mime a conversation first.
    // Al suelo ANTES de anotar el destino, no despues: playerbots guarda esta
    // posicion y la reutiliza en cada tick de la estrategia `stay`, asi que una
    // Z mala se queda dentro y no hay donde corregirla luego.
    GroundZ(bot, x, y, z);

    rts::bots::Change(bot, "+stay,-passive,-move from group", rts::bots::IDLE);
    rts::bots::Change(bot, "+stay,-follow,-passive,-move from group", rts::bots::COMBAT);

    // "return" is where the bot drifts back to between actions; "stay" is the
    // anchor StayStrategy walks it to. Both have to be the destination, or the
    // two pull against each other.
    rts::bots::SetAnchor(bot, "return", x, y, z, bot->GetMapId());
    rts::bots::SetAnchor(bot, "stay", x, y, z, bot->GetMapId());

    // Let it abandon the path it is already on.
    //
    // StopMoving() alone does NOT do this, which is why re-clicking appeared to
    // be ignored: the bot stopped, and then its AI refused to issue a new path.
    // MovementAction::MoveTo bails at IsWaitingForLastMove
    // (MovementActions.cpp:183), which blocks any new movement until the delay
    // recorded for the PREVIOUS move has elapsed -- and that delay is computed
    // from the full distance of the old trip. Clearing that record is what
    // actually lets a fresh click take effect immediately.
    rts::bots::ForgetLastMove(bot);

    bot->StopMoving();
    bot->GetMotionMaster()->Clear();

    return true;
}

bool rts::orders::IsPassive(Player* master, std::string const& botName)
{
    return rts::bots::Has(ResolveBot(master, botName), "passive", rts::bots::BOTH);
}

bool rts::orders::AttackBot(Player* master, std::string const& botName, ObjectGuid targetGuid)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot) || !targetGuid)
        return false;

    Unit* victim = ObjectAccessor::GetUnit(*bot, targetGuid);
    if (!victim || !victim->IsAlive() || !bot->IsValidAttackTarget(victim))
        return false;

    // A bot pinned to an anchor cannot close on anything, so an attack order
    // releases the hold -- which is what ordering an attack means in an RTS.
    rts::bots::Change(bot, "-stay", rts::bots::BOTH);
    rts::bots::ClearAnchor(bot, "stay");
    rts::bots::ClearAnchor(bot, "return");

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

    // `DoAction` es silenciosa -- no TellMaster, asi que no hay giro ni mimo de
    // conversacion antes de moverse.
    rts::bots::DoAction(bot, "attack my target");

    rts::bots::ForgetLastMove(bot);
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
    rts::bots::Change(ResolveBot(master, botName), "+grind", rts::bots::IDLE);

    return true;
}

namespace
{
    // QUIEN ESTA POSEIDO Y COMO ESTABA ANTES.
    //
    // El comentario que habia aqui decia: *"esto pone passive a ciegas y
    // `ReleaseBot` lo quita a ciegas (...) se deja asi A PROPOSITO porque el
    // verbo POSSESS no lo manda nadie. Si POSSESS vuelve a usarse, la version
    // correcta esta escrita en `Suppress`"*.
    //
    // POSSESS tiene llamante desde hoy, asi que se hace lo que aquel comentario
    // mandaba: capturar antes del primer cambio y devolver a lo capturado. Sin
    // esto, tomar el mando de un bot al que le habias puesto "Esperar" a mano se
    // lo quitaba al soltarlo, en silencio.
    struct Possessed
    {
        ObjectGuid bot;
        bool wasPassiveCombat = false;
        bool wasPassiveIdle = false;
    };

    std::unordered_map<ObjectGuid, Possessed> g_possessed;

    // Los diez huecos de la barra de posesion, rellenos con la barra de acciones
    // DEL PROPIO BOT.
    //
    // POSEER A UN `Player` DA UNA BARRA VACIA, y hay que saberlo: el nucleo
    // rellena la barra de posesion desde `m_spells` de la CRIATURA
    // (`CharmInfo::InitPossessCreateSpells`, CharmInfo.cpp:79), y para cualquier
    // otra cosa hace `InitEmptyActionBar()`. O sea que sin esto tomas el mando
    // del mago y te encuentras moviendote sin un solo hechizo -- que se leeria
    // como que la posesion esta a medias.
    //
    // La fuente es la misma que usa la fila de habilidades: la barra guardada
    // del bot, que son los hechizos que TU le pusiste jugandolo.
    void FillPossessBar(Player* master, Player* bot)
    {
        CharmInfo* info = bot->GetCharmInfo();
        if (!info)
            return;

        auto const spells = rts::command::ActionBarSpells(master, bot->GetName());

        uint32 slot = 0;
        for (uint32 id : spells)
        {
            if (slot >= MAX_UNIT_ACTION_BAR_INDEX)
                break;
            if (SpellInfo const* si = sSpellMgr->GetSpellInfo(id))
            {
                if (info->AddSpellToActionBar(si, ACT_PASSIVE, slot))
                    ++slot;
            }
        }

        // Y se le manda al cliente. `SetCharmedBy` ya llamo a
        // `PossessSpellInitialize` ANTES de que rellenaramos nada, asi que sin
        // esta segunda llamada el jugador ve la barra vacia que se envio
        // entonces -- los huecos estarian puestos en el servidor y no en la
        // pantalla, que es la peor forma de estar a medias.
        master->PossessSpellInitialize();
    }
}

bool rts::orders::PossessBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    if (bot->GetCharmerGUID())
        return false;   // already possessed by someone

    // Y NOSOTROS TAMPOCO PODEMOS ESTAR CHARMANDO YA. `Unit::SetCharm` avisa con
    // un LOG_FATAL si el charmer ya tiene charm y sigue adelante pisando el
    // anterior -- o sea que el primero se queda charmado para siempre, y el
    // primero puede ser la CRIATURA DE LA CAMARA. La comprobacion cuesta una
    // linea y evita quedarse con dos posesiones de las que solo una se suelta.
    if (master->GetCharmGUID())
        return false;

    Possessed p;
    p.bot = bot->GetGUID();
    p.wasPassiveCombat = rts::bots::Has(bot, "passive", rts::bots::COMBAT);
    p.wasPassiveIdle   = rts::bots::Has(bot, "passive", rts::bots::IDLE);

    // La IA se sienta. Un bot corriendo sus estrategias mientras tu le llevas
    // pelearia contigo por los mandos en cada tick.
    rts::bots::Change(bot, "+passive", rts::bots::BOTH);

    // Y SE LE SUELTA EL ANCLA. Un bot en `stay` poseido camina a donde le
    // lleves y su estrategia lo devuelve -- exactamente el "va y vuelve" que
    // `PRUEBAS-20` 0.3 reporto sobre el personaje del jugador. Mismo mecanismo,
    // misma cura, y esta vez aplicada a los dos caminos a la vez.
    rts::bots::Change(bot, "-stay", rts::bots::BOTH);
    rts::bots::ClearAnchor(bot, "stay");
    rts::bots::ClearAnchor(bot, "return");
    rts::bots::ForgetLastMove(bot);

    if (!bot->SetCharmedBy(master, CHARM_TYPE_POSSESS))
    {
        if (!p.wasPassiveIdle)
            rts::bots::Change(bot, "-passive", rts::bots::IDLE);
        if (!p.wasPassiveCombat)
            rts::bots::Change(bot, "-passive", rts::bots::COMBAT);
        return false;
    }

    g_possessed[master->GetGUID()] = p;
    FillPossessBar(master, bot);
    return true;
}

bool rts::orders::ReleaseBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!bot)
        return false;

    if (bot->GetCharmerGUID() == master->GetGUID())
        bot->RemoveCharmedBy(master);

    // DEVUELTO A COMO ESTABA, no a "no pasivo". Ver `g_possessed` arriba.
    auto it = g_possessed.find(master->GetGUID());
    if (it != g_possessed.end() && it->second.bot == bot->GetGUID())
    {
        if (!it->second.wasPassiveIdle)
            rts::bots::Change(bot, "-passive", rts::bots::IDLE);
        if (!it->second.wasPassiveCombat)
            rts::bots::Change(bot, "-passive", rts::bots::COMBAT);
        g_possessed.erase(it);
    }
    else
    {
        // Sin nota de como estaba (reinicio del servidor a mitad, o alguien
        // llamo por otro camino) se hace lo unico razonable: dejarlo activo. Es
        // la suposicion que el bloque de arriba evita, y aqui es preferible a
        // dejar un bot pasivo para siempre sin que nada lo explique.
        rts::bots::Change(bot, "-passive", rts::bots::BOTH);
    }

    // La barra de posesion se va con el mando. Si no, el cliente se queda
    // dibujando los diez hechizos de un bot que ya no llevas.
    master->SendRemoveControlBar();

    // The viewpoint has to go the same way it does for the camera, or the
    // client is left seeing through a character it no longer drives.
    if (WorldObject* seen = master->GetViewpoint())
        master->SetViewpoint(seen, false);

    return true;
}

bool rts::orders::ReleaseAnyPossession(Player* master)
{
    // EL SEGURO QUE FALTABA, Y COSTO EL SERVIDOR ENTERO.
    //
    // `PossessBot` hace `SetCharmedBy` a pelo, sin aura. `Player::RemoveFromWorld`
    // llama a `StopCastingCharm`, que deshace un charm QUITANDO SUS AURAS -- y
    // aqui no hay ninguna que quitar. Asi que el charm sigue puesto, cae en el
    // `LOG_FATAL` de `Player.cpp:9551`, ve que el charmado tiene charmer y hace
    // **`ABORT()`**: el worldserver se muere. Visto el 2026-09-03, con volcado.
    //
    // Es EL MISMO fallo que tuvo la camara y que se arreglo haciendola un
    // Puppet (ver `kPuppetProps` en `RtsCamera.cpp`), y esa salida aqui no
    // sirve: un Puppet es una criatura invocada y esto es un `Player` que ya
    // existe. Lo que queda es soltar por el camino bueno -- `RemoveCharmedBy`,
    // que es lo que `SetCharmedBy` sabe deshacer -- ANTES de que el nucleo
    // llegue a `RemoveFromWorld`.
    //
    // Se mira `GetCharmGUID()` y no la lista del grupo a proposito: un bot que
    // se fue del grupo mientras lo llevabas seguiria charmado y no aparecería
    // en el recorrido. La pregunta correcta es "¿estoy charmando algo?", y esa
    // solo tiene una fuente.
    //
    // SOLO SI ES UN `Player`. La camara tambien charma, y esa se suelta por su
    // propio camino (`camera::Abandon`), que ademas devuelve la criatura al
    // mapa en vez de dejarla huerfana.
    if (!master)
        return false;

    ObjectGuid const charmed = master->GetCharmGUID();
    if (!charmed || !charmed.IsPlayer())
        return false;

    Player* bot = ObjectAccessor::FindPlayer(charmed);
    if (!bot)
        return false;

    return ReleaseBot(master, bot->GetName());
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

    // TU PERSONAJE PUEDE SER UN BOT, Y SI LO ES HAY QUE SOLTARLE EL ANCLA.
    //
    // Reportado en `PRUEBAS-20` 0.3: *"he puesto stay a todos los pj incluido el
    // principal (...) el pj principal no lo puedo mandar a otra localizacion,
    // intenta ir a donde esta el punto y se vuelve al origen donde le configure
    // el stay"*.
    //
    // La causa es que el selfbot le engancha una IA de playerbots a tu propio
    // personaje, asi que el `stay` que mandas al grupo TAMBIEN le llega: se
    // ancla, y a partir de ahi `MovePoint` lo lleva al destino y su estrategia
    // `stay` lo trae de vuelta al ancla. Las dos ordenes son correctas y se
    // pelean, que es por lo que el sintoma es "va y vuelve" y no "no se mueve".
    //
    // `MoveBot` ya hace esto para los bots -- la diferencia era que tu personaje
    // no pasa por `MoveBot`, porque `ResolveBot` rechaza a proposito que te
    // ordenes a ti mismo por esa via. Es el patron de la etapa 5h una vez mas:
    // dos caminos para la misma cosa y el arreglo aplicado solo a uno.
    //
    // Sin IA (sin selfbot) `Driven` es falso y aqui no pasa nada.
    if (rts::bots::Driven(player))
    {
        rts::bots::Change(player, "-stay,-passive", rts::bots::BOTH);
        rts::bots::ClearAnchor(player, "stay");
        rts::bots::ClearAnchor(player, "return");
        rts::bots::ForgetLastMove(player);
    }

    // Al suelo tambien aqui: la Z del click vale lo mismo para tu personaje que
    // para un bot, y un MovePoint a una Z flotante te deja flotando igual.
    GroundZ(player, x, y, z);

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

    // A corpse you can loot is neither scenery nor a conversation -- it is its
    // own thing, and it used to fall through to a move order. That is why
    // right-clicking a body in RTS mode did nothing at all: the click was read
    // as "walk over there", which it also silently did.
    //
    // The reason this cannot be left to the client, the way it is in normal
    // play, is possession. While the RTS camera holds client control the player
    // is not the active mover, so the client works its interactions out against
    // the camera creature -- which is why no loot cursor appears on hover
    // either. The server has to do it.
    if (!unit->IsAlive())
    {
        Creature* corpse = unit->ToCreature();
        if (corpse && master->isAllowedToLoot(corpse))
            return CLICK_INTERACT;
        return CLICK_MOVE;
    }

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
        if (!rts::bots::Driven(bot))
            return false;

        master->SetSelection(creature->GetGUID());
        bot->SetSelection(creature->GetGUID());
        bot->SetFacingToObject(creature);

        // `DoAction` es silenciosa: no TellMaster, asi que no hay giro ni mimo
        // antes de hablar.
        return rts::bots::DoAction(bot, "gossip hello");
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
    if (!rts::bots::Driven(bot) || !targetGuid)
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

bool rts::orders::SelfCast(Player* player, uint32 spellId, ObjectGuid targetGuid,
                           std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    if (!player || !spellId)
        return fail("no spell");

    if (!player->HasSpell(spellId))
        return fail("no conoces ese hechizo");

    SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
    if (!info)
        return fail("ese hechizo no existe en este servidor");

    Unit* target = nullptr;
    if (targetGuid)
    {
        target = ObjectAccessor::GetUnit(*player, targetGuid);
        // An explicit target that cannot be found is an ERROR, not a fallback.
        // Silently turning "heal the tank" into "heal myself" is the kind of
        // helpfulness that costs a wipe and reads as the button being broken.
        if (!target)
            return fail("no veo ese objetivo");
    }
    else if (ObjectGuid const own = player->GetTarget())
    {
        target = ObjectAccessor::GetUnit(*player, own);
    }

    if (!target)
        target = player;

    // A hostile spell at a friend, or a friendly spell at an enemy, is a mistake
    // the client would have caught before sending anything. Here it would go out
    // as a cast that fails deep in the spell system with no explanation, so it
    // is checked where it can still be explained.
    bool const hostileSpell = !info->IsPositive();
    if (target != player && hostileSpell != player->IsValidAttackTarget(target))
        return fail("ese hechizo no va contra ese objetivo");

    player->CastSpell(target, spellId, false);
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

// Every bot in the master's group picks up EVERYTHING, greys included.
//
// This used to be the chat command `ll all`, broadcast to the party on entering
// RTS mode and again on every roster change. It worked, and it was wrong in two
// ways at once: the player saw a bot command scroll past in their own chat
// every time, and it had to be re-sent by hand because nothing on the server
// remembered it.
//
// The bot's loot strategy is an ordinary value in its AI context
// (`LootStrategyValue`, default `normal`, which runs items through ItemUsage
// and leaves greys on the ground). mod-rts already reaches into that context to
// move bots and read their targets, so setting it here costs one line and no
// chat at all -- the same reasoning that took every other order off the chat
// channel in the first place. There is no config option for it in playerbots;
// this is the closest thing to a default that does not mean forking the module.
//
// Returns how many bots were changed, so the addon can say so instead of
// assuming.
int rts::orders::SetGroupLoot(Player* master, bool everything)
{
    if (!master)
        return 0;

    Group* group = master->GetGroup();
    if (!group)
        return 0;

    int changed = 0;

    for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
    {
        Player* member = ref->GetSource();
        if (!member || member == master)
            continue;

        if (!rts::bots::SetLootAll(member, everything))
            continue;

        ++changed;
    }

    return changed;
}

std::string rts::orders::GroupPositions(Player* master)
{
    std::ostringstream out;
    if (!master)
        return out.str();

    Group* group = master->GetGroup();
    if (!group)
        return out.str();

    bool first = true;
    for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
    {
        Player* member = ref->GetSource();
        if (!member || member == master || !member->IsInWorld())
            continue;

        if (!first)
            out << ';';
        first = false;

        // Two decimals is a centimetre. The addon compares this against a
        // three-yard arrival radius, so anything finer is bytes for nothing.
        out << member->GetName() << ','
            << std::fixed << std::setprecision(2)
            << member->GetPositionX() << ','
            << member->GetPositionY() << ','
            << member->GetPositionZ();
    }

    return out.str();
}

bool rts::orders::ResetBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    // El orden importa: primero se olvidan las estrategias, y DESPUES se le
    // devuelve el seguimiento. Al reves, `ResetStrategies` se llevaria por
    // delante el `+follow` que acabamos de poner y el bot se quedaria plantado
    // -- que es justo el sintoma del que se viene huyendo.
    rts::bots::Reset(bot);

    rts::bots::ClearAnchor(bot, "stay");
    rts::bots::ClearAnchor(bot, "return");
    rts::bots::ForgetLastMove(bot);

    return FollowBot(master, botName);
}

bool rts::orders::FollowBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    rts::bots::Change(bot, "+follow,-passive,-grind,-move from group", rts::bots::IDLE);
    rts::bots::Change(bot, "-stay,-follow,-passive,-grind,-move from group", rts::bots::COMBAT);

    rts::bots::ClearAnchor(bot, "return");
    rts::bots::ClearAnchor(bot, "stay");

    return true;
}
