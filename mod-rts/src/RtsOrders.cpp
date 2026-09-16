#include "RtsOrders.h"

#include "RtsCamera.h"   // camera::IsSpectating, para la guarda de MoveSelf

#include "RtsBotApi.h"   // la unica puerta a mod-playerbots

#include "SpellInfo.h"
#include "CellImpl.h"
#include "Creature.h"
#include "GameObject.h"
#include "GridNotifiers.h"
#include "GridNotifiersImpl.h"
#include "LootMgr.h"
#include "ObjectDefines.h"   // INTERACTION_DISTANCE
#include "Group.h"
#include "Log.h"
#include "Map.h"
#include "MapCollisionData.h"
#include "MotionMaster.h"
#include "PathGenerator.h"
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

    // DESPERTARLE LA IA AHORA MISMO. Es la diferencia entre "el bot tarda en
    // reaccionar" y "el bot sale disparado", y hace falta porque este modulo NO
    // camina al bot: le pone el ancla y le borra el camino que llevaba, y quien
    // le hace andar hasta ahi es su propia IA en su siguiente vuelta.
    //
    // Esa vuelta no es inmediata. Playerbots se pone a si mismo una espera
    // (`nextAICheckDelay`) despues de cada pensamiento -- el `reactDelay` de su
    // configuracion, mas lo que le anadan las acciones -- y mientras corre, el
    // bot es sordo. La orden ya habia llegado al servidor; lo que faltaba era
    // que le tocara pensar. De ahi el sintoma: pones el punto y pasa un rato.
    //
    // `SetNextCheckDelay(0)` pone esa espera a cero, asi que piensa en el tick
    // siguiente. No se le salta ningun turno a nadie ni se toca su motor: es el
    // mismo mando que playerbots usa consigo mismo, puesto del otro lado.
    //
    // SOLO EN LAS ORDENES QUE DAS TU con el raton. Una orden del jugador es
    // exactamente lo que tiene que adelantarse a lo que el bot estuviera
    // rumiando; ponerlo en todo lo demas seria quitarle la espera que reparte
    // su carga, que existe por algo.
    void WakeAi(Player* bot)
    {
        rts::bots::HoldAi(bot, 0);
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

    // Cuanto por debajo del campo de alturas hay que estar para dar por hecho
    // que se esta DEBAJO del terreno y no rozandolo. Una yarda y media: una
    // camara de RTS vuela muy por encima del suelo, asi que no hay caso normal
    // que caiga aqui por accidente.
    constexpr float kUnderSlack = 1.5f;
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
    //
    // PERO SOLO SI EL RAYO EMPIEZA POR ENCIMA DEL CAMPO DE ALTURAS. Dentro de
    // una cueva no lo esta: el suelo de la cueva es un MODELO y el campo de
    // alturas sigue describiendo la ladera que tienes ENCIMA. Con la camara
    // dentro, `pz <= g` da cierto en el primer paso -- estas debajo del monte
    // desde el metro uno -- asi que el paseo cortaba a una yarda de la camara y
    // devolvia la altura del terreno de fuera.
    //
    // En pantalla eso era exactamente lo reportado: *"no puedo clicar dentro de
    // cuevas, el punto se imprime en el terreno por encima y los bots van
    // alli"*. No fallaba el rayo: fallaba pedirle una respuesta a un campo de
    // alturas desde debajo de el, donde no significa nada.
    //
    // Bajo tierra manda el modelo, que es una interseccion de verdad y ya esta
    // calculada arriba. La holgura es para no confundir "dentro de una cueva"
    // con "la camara roza el suelo en una hondonada".
    float const groundAtEye = map->GetGridHeight(ox, oy);
    bool const underTerrain = (groundAtEye > kNoHeight) && (oz < groundAtEye - kUnderSlack);

    float const walk = underTerrain ? 0.0f : std::min(maxDist, vdist);
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

namespace
{
    // CUANTO SE LE MANDA DE UNA VEZ, en yardas de camino.
    //
    // El tope duro lo pone la IA del bot: un ancla a mas de `ReactDistance` no
    // es util para `MoveToPositionAction` y el bot ni arranca. El margen de un
    // tercio no es prudencia: la distancia que esa comprobacion mide es EN LINEA
    // RECTA desde donde el bot este cuando le toque pensar, y un tramo de camino
    // que rodea una loma tiene mas camino que recta. Un presupuesto pegado al
    // limite deja el arranque a suerte.
    float LegBudget()
    {
        float const react = rts::bots::ReactDistance();
        float budget = react * 0.66f;
        if (budget < 30.0f)
            budget = 30.0f;
        if (budget > 200.0f)
            budget = 200.0f;
        return budget;
    }

    // ESTAS CUATRO BANDERAS QUIEREN DECIR "EL NUCLEO VA A IR EN LINEA RECTA".
    //
    //   NOPATH         -- no hay camino, y lo que queda es el atajo de dos puntos
    //   SHORTCUT       -- el atajo, dicho con todas las letras
    //   NOT_USING_PATH -- destino fuera de la malla (o sin mmap): atajo, y ademas
    //                     se presenta como NORMAL. Ver la nota de `NextLeg`.
    //   SHORT          -- habia camino, pero pasa de 74 puntos y lo han tirado
    //
    // Ninguna de las cuatro sirve para andar. `PATHFIND_INCOMPLETE` SI sirve y no
    // esta aqui a proposito: es un camino de verdad que se queda corto, o sea
    // justo lo que un tramo quiere.
    constexpr int kPathUnusable = PATHFIND_NOPATH | PATHFIND_SHORTCUT |
                                  PATHFIND_NOT_USING_PATH | PATHFIND_SHORT;

    // Andar la polilinea de la malla hasta gastar el presupuesto. El punto que
    // sale esta SOBRE ella, asi que es andable por construccion -- que es la
    // diferencia entera con cortar la recta.
    //
    // Devuelve false si el camino entero cabe: entonces el destino es el punto.
    bool CutAt(Movement::PointsArray const& pts, float budget,
               float& tx, float& ty, float& tz)
    {
        float used = 0.0f;
        for (std::size_t i = 1; i < pts.size(); ++i)
        {
            float const dx = pts[i].x - pts[i - 1].x;
            float const dy = pts[i].y - pts[i - 1].y;
            float const dz = pts[i].z - pts[i - 1].z;
            float const seg = std::sqrt(dx * dx + dy * dy + dz * dz);
            if (seg < 1e-4f)
                continue;

            if (used + seg >= budget)
            {
                float const f = (budget - used) / seg;
                tx = pts[i - 1].x + dx * f;
                ty = pts[i - 1].y + dy * f;
                tz = pts[i - 1].z + dz * f;
                return true;
            }
            used += seg;
        }
        return false;
    }
}

bool rts::orders::NextLeg(Player* bot, float fx, float fy, float fz,
                          float& tx, float& ty, float& tz, int& kind)
{
    tx = fx; ty = fy; tz = fz;
    kind = LEG_NONE;

    if (!bot || !bot->IsInWorld())
        return false;

    float const budget = LegBudget();

    // 1. EL CAMINO ENTERO HASTA EL PUNTO. Lo normal, y lo unico que hace falta
    //    mientras el destino este en la malla y no quede demasiado lejos.
    {
        PathGenerator gen(bot);
        gen.CalculatePath(fx, fy, fz);
        int const type = gen.GetPathType();

        if (!(type & kPathUnusable))
        {
            Movement::PointsArray const& pts = gen.GetPath();
            if (pts.size() >= 2)
            {
                if (CutAt(pts, budget, tx, ty, tz))
                {
                    kind = LEG_PARTIAL;
                    return true;
                }

                // Cabe entero. Si el camino se queda corto del objetivo
                // (`INCOMPLETE`), el final de la polilinea es lo mas cerca que
                // la malla llega: se anda hasta ahi y se vuelve a preguntar
                // desde el sitio nuevo, que es donde puede haber mas camino.
                tx = pts.back().x; ty = pts.back().y; tz = pts.back().z;
                kind = (type & PATHFIND_INCOMPLETE) ? LEG_PARTIAL : LEG_FULL;
                return true;
            }
        }
    }

    // 2. NO SE PUDO VER EL CAMINO ENTERO, QUE NO ES LO MISMO QUE NO HABERLO.
    //
    //    `PATHFIND_SHORT` es literalmente "hay camino y son mas de 74 puntos":
    //    un viaje de varios cientos de yardas lo da siempre, y ahi el nucleo
    //    tira el camino bueno y deja el atajo. Asi que se pregunta por un punto
    //    MAS CERCA -- a un presupuesto de distancia sobre la recta -- que es una
    //    pregunta que la malla si sabe contestar.
    //
    //    Y ESTE SONDEO NO SE USA A CIEGAS, que es lo que hacia el addon y lo que
    //    metia al bot en la montana: solo vale si la malla enruta HASTA EL. Si
    //    el sondeo tambien cae fuera -- porque lo que hay en medio es una pared
    //    -- no hay tramo, y eso se dice en vez de mandarle a volar.
    {
        float const dx = fx - bot->GetPositionX();
        float const dy = fy - bot->GetPositionY();
        float const flat = std::sqrt(dx * dx + dy * dy);
        if (flat < 1.0f)
            return false;

        float const f = budget / flat;
        float px = bot->GetPositionX() + dx * f;
        float py = bot->GetPositionY() + dy * f;
        float pz = bot->GetPositionZ() + (fz - bot->GetPositionZ()) * f;
        bot->UpdateAllowedPositionZ(px, py, pz);

        PathGenerator gen(bot);
        gen.CalculatePath(px, py, pz);
        int const type = gen.GetPathType();
        if (type & kPathUnusable)
            return false;

        Movement::PointsArray const& pts = gen.GetPath();
        if (pts.size() < 2)
            return false;

        if (!CutAt(pts, budget, tx, ty, tz))
        {
            tx = pts.back().x; ty = pts.back().y; tz = pts.back().z;
        }
        kind = LEG_PARTIAL;
        return true;
    }
}

bool rts::orders::MoveBot(Player* master, std::string const& botName, float x, float y, float z,
                          float* legX, float* legY, float* legZ, int* legKind)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    // EL TRAMO, ANTES DE ANCLAR NADA. Un punto lejos, o al otro lado de un
    // monte, no se manda tal cual: se manda hasta donde la malla llega, y al
    // llegar el addon vuelve a pedir. Ver `NextLeg`.
    int kind = LEG_FULL;
    float tx = x, ty = y, tz = z;
    bool const routed = NextLeg(bot, x, y, z, tx, ty, tz, kind);

    if (legKind)
        *legKind = kind;

    // SIN CAMINO NO SE MUEVE, y esa es la mitad que faltaba. Anclarle igual era
    // exactamente lo que le hacia atravesar la montana flotando: el nucleo no se
    // niega, sustituye el camino por una recta de dos puntos y la anda. Mejor no
    // ir que ir por el aire, y quien llama lo dice.
    if (!routed)
    {
        if (legX) *legX = x;
        if (legY) *legY = y;
        if (legZ) *legZ = z;
        return false;
    }

    x = tx; y = ty; z = tz;

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

    WakeAi(bot);

    if (legX) *legX = x;
    if (legY) *legY = y;
    if (legZ) *legZ = z;
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
    WakeAi(bot);
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
    Player* const bot = ResolveBot(master, botName);
    rts::bots::Change(bot, "+grind", rts::bots::IDLE);

    // Otra vez DESPUES del cambio de estrategia, no solo el de `MoveBot`: si
    // despierta antes de tener `grind` puesto, la vuelta que se ha ganado la
    // piensa con la configuracion vieja.
    WakeAi(bot);
    return true;
}

// AQUI VIVIA LA POSESION, Y SE FUE ENTERA EL 2026-09-11 (mod-rts 0.49.0).
//
// Eran `PossessBot`, `ReleaseBot`, `ReleaseAnyPossession`, `ReleaseAll`, la
// barra de posesion (`FillPossessBar`) y la tabla `g_possessed` que devolvia
// cada bot a como estaba. Unas doscientas lineas.
//
// La quito el jugador: *"posees raro, eso quitalo"*. Y no tenia arreglo por
// este camino -- lo decia la cabecera del `Possess.lua` del addon desde el
// primer dia: la posesion cambia quien te MUEVE, no quien ERES, y los
// manejadores de interaccion del nucleo (`HandleGossipHelloOpcode`, el
// vendedor, el entrenador, el botin, las misiones) trabajan sobre `_player`.
// Asi que hablar con un PNJ iba por tu personaje, parado en otro sitio, y
// fallaba por distancia. Lo que hace de verdad lo que esto prometia es `SWAP`.
//
// SE BORRA, NO SE APARTA. La vez anterior se dejo escrita sin llamante "por si
// vuelve" y volvio -- y con ella volvio el `ABORT()` del worldserver que ya
// habia costado un dia. Esta vez no queda nada que resucitar por accidente; si
// alguna vez se quiere otra vez, el codigo esta en git y la cura de raiz esta
// escrita: que la posesion lleve un aura de verdad (`SPELL_AURA_MOD_POSSESS`),
// que es lo que `Player::StopCastingCharm` sabe deshacer.

bool rts::orders::MoveSelf(Player* player, float x, float y, float z, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    if (!player || !player->IsInWorld())
        return fail("not in world");

    // Only while something else holds client control -- the RTS camera. If the
    // client is still driving this character, a server-side move would be
    // yanked straight back by the next movement packet it sends.
    //
    // LA TERCERA CONDICION ES LA CAMARA LIBRE, y faltaba. Las dos primeras
    // preguntan por una POSESION, que es como el Puppet cumplia esto; la camara
    // de comentarista no posee nada, asi que le quita el control al cliente por
    // el otro camino (`camera::Spectate` -> `SetClientControl(player, false)`).
    // Sin esta linea, jubilar el Puppet dejaba a tu propio heroe inordenable.
    if (!player->GetCharm() && !player->GetViewpoint() &&
        !rts::camera::IsSpectating(player))
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

    // EL HEROE TAMBIEN VA POR TRAMOS, y esto es lo que faltaba.
    //
    // `MoveBot` se arreglo y tu propio personaje no, porque no pasa por el
    // (`ResolveBot` rechaza a proposito que te ordenes a ti mismo por esa via).
    // Es el patron de la etapa 5h otra vez: dos caminos para la misma cosa y el
    // arreglo puesto solo en uno -- y el que quedaba es el que se ve, porque tu
    // heroe es el que miras.
    int kind = LEG_FULL;
    float tx = x, ty = y, tz = z;
    if (!NextLeg(player, x, y, z, tx, ty, tz, kind))
        return fail("no walking path from here");
    x = tx; y = ty; z = tz;

    // Al suelo tambien aqui: la Z del click vale lo mismo para tu personaje que
    // para un bot, y un MovePoint a una Z flotante te deja flotando igual.
    GroundZ(player, x, y, z);

    player->StopMoving();
    player->GetMotionMaster()->Clear();

    // `forceDestination` A FALSO, Y ES LA MITAD QUE DE VERDAD VOLABA.
    //
    // `MotionMaster::MovePoint` lo trae a CIERTO por defecto, y con el puesto
    // `PathGenerator` hace esto al final (`PathGenerator.cpp`):
    //
    //     if (_forceDestination && (!(_type & PATHFIND_NORMAL) ||
    //                               !InRange(end, actualEnd, 1.0f, 1.0f)))
    //     {   ... SetActualEndPosition(GetEndPosition()); BuildShortcut(); ...
    //         _type = PathType(PATHFIND_NORMAL | PATHFIND_NOT_USING_PATH);   }
    //
    // O sea: si el camino bueno no aterriza EXACTAMENTE en el punto pedido --
    // que es el caso normal al pinchar una ladera o al otro lado de un monte --
    // **tira el camino y pone la recta**. No es que la malla fallara: es que se
    // le pide que ignore lo que la malla dijo.
    //
    // playerbots ya lo pasa a falso en su `DoMovePoint`, asi que los bots nunca
    // tuvieron esta mitad y tu heroe si. De ahi que el sintoma se viera en el
    // personaje que uno mira todo el rato.
    player->GetMotionMaster()->MovePoint(0, x, y, z, FORCED_MOVEMENT_NONE,
                                         0.0f, 0.0f, /*generatePath*/ true,
                                         /*forceDestination*/ false);

    if (why)
        *why = (kind == LEG_PARTIAL) ? "ordered (leg)" : "ordered";
    return true;
}

std::string rts::orders::PathReport(Player* who, float x, float y, float z)
{
    if (!who || !who->IsInWorld())
        return "no esta en el mundo";

    PathGenerator gen(who);
    gen.CalculatePath(x, y, z);
    int const type = gen.GetPathType();

    std::ostringstream out;
    out << std::fixed << std::setprecision(1);
    out << "tipo=0x" << std::hex << type << std::dec;

    // Las banderas por su nombre: el numero solo obliga a ir a mirar la cabecera.
    if (type & PATHFIND_NORMAL)            out << " NORMAL";
    if (type & PATHFIND_SHORTCUT)          out << " SHORTCUT";
    if (type & PATHFIND_INCOMPLETE)        out << " INCOMPLETE";
    if (type & PATHFIND_NOPATH)            out << " NOPATH";
    if (type & PATHFIND_NOT_USING_PATH)    out << " NOT_USING_PATH";
    if (type & PATHFIND_SHORT)             out << " SHORT";
    if (type & PATHFIND_FARFROMPOLY_START) out << " FAR_START";
    if (type & PATHFIND_FARFROMPOLY_END)   out << " FAR_END";

    out << " pts=" << gen.GetPath().size()
        << " largo=" << gen.getPathLength()
        << " recta=" << who->GetExactDist(x, y, z);

    float tx, ty, tz;
    int kind = LEG_NONE;
    if (NextLeg(who, x, y, z, tx, ty, tz, kind))
    {
        out << " -> tramo " << ((kind == LEG_FULL) ? "ENTERO" : "TROZO")
            << " a " << who->GetExactDist(tx, ty, tz) << " yd";
    }
    else
    {
        out << " -> SIN TRAMO (no se manda)";
    }
    return out.str();
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

            // UN BOTIN QUE YA ESTA ABIERTO NO SE VUELVE A ABRIR: REABRIRLO ES
            // CERRARLO. `Player::SendLoot` empieza soltando el botin anterior
            // (Player.cpp:7985), asi que la segunda apertura manda
            // `SMSG_LOOT_RELEASE_RESPONSE` -- y eso, en el cliente, es
            // `LOOT_CLOSED` y la ventana escondida.
            //
            // Ese era el parpadeo de 2026-09-12: *"me sale un frame el loot del
            // bicho y al instante se esconde"*. Medido con la sonda de
            // `Loot.lua`: una apertura, un cierre en el MISMO frame, cero
            // huecos recogidos y el cliente viendote a metro y medio del
            // cuerpo. Y la prueba que lo cerro: sin nada seleccionado -- o sea
            // sin que el addon mande la orden -- la ventana se abre y SE QUEDA.
            if (player->GetLootGUID() == creature->GetGUID())
                return true;

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

    // UN CADAVER A TIRO ES DEL CLIENTE, Y AQUI NO SE TOCA NADA.
    //
    // El mismo click derecho que nos manda esta orden ha hecho que el cliente
    // mande su `CMSG_LOOT` por su cuenta, y ese camino funciona: probado
    // 2026-09-12 deseleccionando todo -- sin orden nuestra la ventana se abre y
    // se queda. Lo que la rompia era llegar detras a hacer lo mismo: dos
    // aperturas del mismo botin, y la segunda suelta la primera.
    //
    // La razon por la que esto existia sigue siendo verdad A DISTANCIA: fuera
    // de alcance el cliente no lootea nada, y "ve hasta el cuerpo y lootealo"
    // solo lo puede hacer el servidor. Asi que el reparto es por alcance, que
    // es justo donde cambia quien puede: a tiro, el cliente; lejos, nosotros
    // -- y para entonces su click ya se perdio y no hay con quien chocar.
    //
    // OJO CON LA POSESION SI ALGUN DIA VUELVE. Esto da por hecho que el cliente
    // conduce tu cuerpo, que es como esta el modo RTS de fabrica desde
    // 2026-09-11 (ver `camera::Arm`). Si el cliente deja de ser el mover, deja
    // tambien de mandar el `CMSG_LOOT` y este atajo se lleva el botin por
    // delante; el sitio donde mirarlo es `IsSpectating` + `HoldsControl`.
    if (!creature->IsAlive() && player->IsWithinDistInMap(creature, INTERACTION_DISTANCE))
        return true;

    // Out of reach: walk there, and remember what it was for.
    if (WalkToInteract(player, player, creature))
    {
        Remember(player, player, targetGuid);
        return true;
    }

    return DoInteract(player, creature);
}

namespace
{
    // A CUANTO DEL PUNTO PINCHADO CUENTA COMO "HAS PINCHADO ESE NODO".
    //
    // No es un radio de gusto, sale de por donde viene el punto. El addon manda
    // el corte del rayo del cursor, que segun el modelo cae EN la planta o en el
    // suelo justo debajo de ella -- el rayo del cliente no siempre lleva los
    // doodads pequenos -- asi que la horquilla real es de una yarda larga. Dos
    // la cubren.
    //
    // Y no mas: cada yarda de mas es una yarda en la que un click al SUELO deja
    // de mover al grupo, que es el precio de este arreglo y hay que tenerlo
    // corto. En un prado lleno de hierbas eso se nota enseguida.
    constexpr float kNodeRadius = 2.0f;

    // LO QUE CUENTA COMO NODO, y es a proposito la lista mas corta que sirve.
    //
    // Solo COFRE (type 3): hierbas, vetas y cofres. Es lo que se pidio y es
    // ademas lo unico cuyo click se puede robar sin romper nada -- una puerta,
    // una silla o un buzon tambien son GameObjects, y hacer que se traguen la
    // orden de movimiento del grupo por estar cerca seria cambiar el modo RTS
    // entero por un arreglo de recoleccion.
    struct NodeCheck
    {
        float x, y, z;

        bool operator()(GameObject* go) const
        {
            if (!go || !go->IsInWorld())
                return false;
            if (go->GetGoType() != GAMEOBJECT_TYPE_CHEST)
                return false;
            // Lo que el propio nucleo exige para poder usarlo. Un nodo ya
            // recogido sigue en el mapa hasta que reaparece, y ese no es un
            // nodo: es paisaje, y su click tiene que volver a ser un movimiento.
            if (!go->isSpawned() || go->GetGoState() != GO_STATE_READY)
                return false;
            if (go->HasGameObjectFlag(GO_FLAG_NOT_SELECTABLE))
                return false;
            return go->IsWithinDist3d(x, y, z, kNodeRadius);
        }
    };
}

GameObject* rts::orders::NodeAt(Player* master, float x, float y, float z)
{
    if (!master || !master->IsInWorld())
        return nullptr;

    std::list<GameObject*> found;
    NodeCheck check{x, y, z};
    Acore::GameObjectListSearcher<NodeCheck> searcher(master, found, check);
    // Se visita alrededor del PUNTO, no del jugador: el click puede caer lejos
    // y las celdas que se recorren tienen que ser las de alli.
    Cell::VisitObjects(x, y, master->GetMap(), searcher, kNodeRadius);

    GameObject* best = nullptr;
    float bestDist = 0.0f;
    for (GameObject* go : found)
    {
        float const d = go->GetExactDist(x, y, z);
        if (!best || d < bestDist)
        {
            best = go;
            bestDist = d;
        }
    }
    return best;
}

bool rts::orders::SelfGather(Player* player, GameObject* node)
{
    if (!player || !node)
        return false;

    // A TIRO NO SE TOCA NADA. Es literalmente todo el arreglo: el mismo click
    // derecho ya ha hecho que el cliente lance el hechizo de profesion, y lo
    // unico que hacia falta era no mandarle detras una orden de movimiento que
    // lo cancela. Misma regla y mismo reparto que el cadaver de `SelfInteract`:
    // a tiro, el cliente; lejos, nosotros.
    if (player->IsWithinDistInMap(node, node->GetInteractionDistance()))
        return true;

    // Lejos: el cliente no ha podido hacer nada -- su propia comprobacion de
    // alcance lo paro antes de mandar nada -- asi que aqui no hay ningun
    // lanzamiento que respetar y andar es lo correcto.
    float gx, gy, gz;
    node->GetContactPoint(player, gx, gy, gz, kStandOff);
    rts::orders::MoveSelf(player, gx, gy, gz);
    return false;
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

    // Y ya esta: la posesion, que era lo otro que se soltaba aqui, no existe.
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

// QUIETO, SIN DESTINO. Lo mismo que `MoveBot` pero con las anclas puestas en
// donde el bot ya esta, que es lo que significa "hold position" en un RTS.
//
// La posicion se lee DEL BOT, no del jugador: mandar "quieto" a cuatro bots
// desde aqui tiene que dejar a cada uno en su sitio, no juntarlos.
bool rts::orders::HoldBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    float x = bot->GetPositionX();
    float y = bot->GetPositionY();
    float z = bot->GetPositionZ();

    rts::bots::Change(bot, "+stay,-passive,-move from group", rts::bots::IDLE);
    rts::bots::Change(bot, "+stay,-follow,-passive,-move from group", rts::bots::COMBAT);

    rts::bots::SetAnchor(bot, "return", x, y, z, bot->GetMapId());
    rts::bots::SetAnchor(bot, "stay", x, y, z, bot->GetMapId());

    rts::bots::ForgetLastMove(bot);
    bot->StopMoving();
    bot->GetMotionMaster()->Clear();

    WakeAi(bot);
    return true;
}

// TRAERLO, POR SU PROPIA ACCION Y NO POR EL CHAT.
//
// `summon` es una accion de playerbots (`SummonAction`) y lo unico que hacia
// falta para dispararla era el chat del grupo: el bot leia "summon" y en su
// siguiente vuelta se teleportaba. `DoSpecificAction` la llama directamente, o
// sea sin linea de chat, sin cola de susurros y sin esperar a que le toque
// pensar.
//
// NO SE REIMPLEMENTA EL TELEPORT. La accion suya comprueba vehiculo, linea de
// vision, combate (`allowSummonInCombat`) y reparacion al llegar; copiar eso
// aqui seria heredar cuatro reglas que ellos ya mantienen.
bool rts::orders::SummonBot(Player* master, std::string const& botName)
{
    Player* bot = ResolveBot(master, botName);
    if (!rts::bots::Driven(bot))
        return false;

    if (!rts::bots::DoAction(bot, "summon"))
        return false;

    WakeAi(bot);
    return true;
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

    WakeAi(bot);
    return true;
}
