#include "RtsSwap.h"

#include "RtsBotApi.h"

#include "CharacterCache.h"
#include "DatabaseEnv.h"
#include "Opcodes.h"
#include "WorldPacket.h"
#include "World.h"
#include "Chat.h"
#include "Group.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "WorldSession.h"
#include "WorldSessionMgr.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{
    // Cuanto se espera a que el bot de destino salga del mundo antes de rendirse.
    constexpr uint32 kBotOutMs = 8000;

    // Cuanto se espera a que la consulta del personaje de destino vuelva de la
    // base de datos. Es una consulta local: si tarda mas de esto, algo va mal de
    // verdad y seguir esperando no lo arregla.
    constexpr uint32 kPreloadMs = 15000;

    // Y cuanto se insiste en rehacer el grupo antes de rendirse. No es una
    // espera: es un REINTENTO por vuelta, porque meter un bot es una carga
    // asincrona y los que salieron con el logout no vuelven todos a la vez.
    constexpr uint32 kRegroupMs = 30000;

    // Y cuanto se espera a que el cliente confirme que recargo el mundo. Lo
    // normal es que lo diga el addon en cuanto entra (`ClientPorted`), asi que
    // esto es el RESPALDO para un cliente sin addon -- y por eso son 12 s y no
    // 30: cuando se agotan es la primera senal de que el aviso no llega, y
    // treinta segundos de espera en silencio se leen como que el cambio se ha
    // colgado. Si vence se sigue igual, porque dejar al jugador mirando una
    // pantalla de carga es peor que arriesgarse.
    constexpr uint32 kPortMs = 12000;

    enum Phase
    {
        WAIT_BOT_OUT,   // pidiendo que el personaje de destino deje de ser bot
        PRELOAD,        // consulta lanzada; esperando la ficha del destino
        WAIT_PORT,      // mandada la recarga de mundo; esperando al cliente
        WAIT_REGROUP,   // dentro; rehaciendo el grupo bot a bot
    };

    struct Pending
    {
        uint32     accountId = 0;
        ObjectGuid target;      // a quien vas
        ObjectGuid leaving;     // a quien dejas, para volver a meterlo de bot
        std::string targetName;
        Phase      phase = WAIT_BOT_OUT;
        uint32     acc = 0;

        // EL GRUPO ENTERO, capturado ANTES del logout.
        //
        // Es el punto del cambio, no un extra: al salir tu del mundo,
        // mod-playerbots saca a TODOS tus bots -- no solo al que dejas -- y el
        // grupo se deshace con ellos. Sin esta lista entras con el compañero y
        // te encuentras solo, que es exactamente lo que no se pedia.
        //
        // Se guardan GUIDs y no punteros: entre la captura y el reintento hay
        // un logout, un login y varias vueltas del mundo, y cada uno de esos
        // `Player*` deja de existir por el camino.
        //
        // El que dejas va DENTRO de la lista y el primero, para que no haya dos
        // caminos que meter de bot -- uno para el heroe y otro para los demas --
        // que es como se acaba arreglando la mitad de un fallo.
        std::vector<ObjectGuid> roster;

        // EL PSEUDO-LOGIN A MEDIAS. La ficha del personaje de destino, leida de
        // la base de datos y esperando. Ver la cabecera: es lo unico que tardaba
        // y por eso es lo unico que se precarga -- el `Player` no hace falta
        // precargarlo porque ya existe, es uno de tus bots.
        std::shared_ptr<LoginQueryHolder> holder;
        bool holderReady = false;
        bool holderFailed = false;

        // DONDE ESTA EL DESTINO, capturado mientras seguia en el mundo de bot.
        // Es lo que se le manda al cliente para que recargue: si se le manda un
        // mapa que no es el suyo, recarga ese y luego la rafaga de login le hace
        // recargar otra vez -- funciona, pero son dos pantallas de carga.
        uint32 portMap = 0;
        float  portX = 0.f, portY = 0.f, portZ = 0.f, portO = 0.f;

        // Lo pone `ClientPorted` cuando el cliente contesta que ya recargo.
        bool ported = false;

        // Para no repetir el aviso de "el gestor de bots no esta listo" en cada
        // vuelta del mundo, que serian cinco por segundo.
        bool warnedNoMgr = false;
    };

    // Por CUENTA y no por guid de jugador: el guid cambia a mitad de la
    // operacion -- esa es literalmente la operacion -- asi que usarlo como clave
    // seria perder la entrada justo cuando hace falta.
    std::unordered_map<uint32, Pending> g_pending;

    // La cuenta cuyo `SMSG_LOGOUT_COMPLETE` se esta tragando AHORA MISMO. Vale
    // cero salvo durante la llamada a `LogoutPlayer`, tres lineas mas abajo de
    // donde se pone. Un solo entero y no un conjunto: el cambio pasa entero en
    // una vuelta del mundo, asi que no puede haber dos a la vez ni aunque haya
    // dos jugadores cambiando -- se procesan uno detras de otro.
    uint32 g_swallowLogoutFor = 0;

    void Tell(uint32 accountId, std::string const& text)
    {
        if (WorldSession* s = sWorldSessionMgr->FindSession(accountId))
            ChatHandler(s).SendSysMessage(text.c_str());
    }

    // LANZAR LA CONSULTA DEL DESTINO SIN USARLA TODAVIA -- el pseudo-login de
    // la cabecera. Copiado de `PlayerbotMgr.cpp:148`, que es como playerbots
    // mete cada bot en el mundo, con una sola diferencia: la respuesta no se
    // consume aqui. Se guarda y se marca lista, y quien la usa es `Update`, en
    // la vuelta del mundo, junto al logout.
    //
    // La sesion se busca POR CUENTA dentro de la lambda y no se captura el
    // puntero: entre que se pide la consulta y llega la respuesta el jugador
    // puede haberse desconectado, y un `WorldSession*` guardado seria un
    // puntero muerto.
    bool StartPreload(Pending& p)
    {
        auto holder = std::make_shared<LoginQueryHolder>(p.accountId, p.target);
        if (!holder->Initialize())
            return false;

        p.holder = holder;
        p.holderReady = false;
        p.holderFailed = false;

        uint32 const accountId = p.accountId;
        sWorld->AddQueryHolderCallback(CharacterDatabase.DelayQueryHolder(holder))
            .AfterComplete([accountId](SQLQueryHolderBase const& /*qh*/)
            {
                // NO SE HACE EL LOGIN AQUI, y esa es la decision. El holder que
                // llega es el mismo objeto que guardamos -- `DelayQueryHolder`
                // rellena el que se le pasa -- asi que basta con levantar la
                // bandera y dejar que el tick del mundo haga logout y login
                // pegados. Hacerlo aqui los separaria por una consulta.
                auto it = g_pending.find(accountId);
                if (it != g_pending.end())
                    it->second.holderReady = true;
            });

        return true;
    }
}

bool rts::swap::To(Player* master, std::string const& name, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    if (!master || !master->GetSession())
        return fail("no estas en el mundo");

    uint32 const accountId = master->GetSession()->GetAccountId();

    if (g_pending.count(accountId))
        return fail("ya hay un cambio en curso");

    ObjectGuid const target = sCharacterCache->GetCharacterGuidByName(name);
    if (!target)
        return fail("no existe ningun personaje con ese nombre");

    if (target == master->GetGUID())
        return fail("ya eres ese");

    // LA REGLA DURA. Ver la cabecera: `HandlePlayerLoginFromDB` no comprueba la
    // cuenta porque quien lo hace es el manejador del opcode, que aqui no se
    // pasa. Si esto no estuviera, `/rts swap <cualquiera>` metería el personaje
    // de otro en tu sesion.
    if (sCharacterCache->GetCharacterAccountIdByGuid(target) != accountId)
        return fail("ese personaje no es de tu cuenta");

    // EN COMBATE NO. El logout guarda y borra el `Player`, y hacerlo con el
    // combate abierto deja auras, amenaza y un grupo apuntando a algo que ya no
    // esta. Es la clase de estado roto que no se ve hasta tres peleas despues.
    if (master->IsInCombat())
        return fail("no en combate");

    Pending p;
    p.accountId  = accountId;
    p.target     = target;
    p.leaving    = master->GetGUID();
    p.targetName = name;
    p.phase      = WAIT_BOT_OUT;

    // EL GRUPO SE FOTOGRAFIA AQUI, que es el ultimo instante en que existe.
    // Detras viene el logout, y con el se van los bots y el grupo con ellos.
    //
    // El heroe que dejas va el PRIMERO: es el que crea el grupo nuevo al
    // entrar, y ademas es el que el jugador espera ver aparecer.
    p.roster.push_back(p.leaving);
    if (Group* group = master->GetGroup())
    {
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* member = ref->GetSource();
            if (!member)
                continue;

            ObjectGuid const g = member->GetGUID();

            // Ni tu (ya esta el primero) ni aquel al que vas -- ese entra como
            // JUGADOR, y meterlo tambien de bot es pedirle al servidor que la
            // misma fila de personaje este en dos sesiones a la vez.
            if (g == p.leaving || g == target)
                continue;

            // NI LO QUE NO SE PUEDE VOLVER A METER, y se dice en el momento.
            //
            // `PlayerbotHolder::AddPlayerBot` solo acepta un personaje de TU
            // cuenta, de tu hermandad, o un bot aleatorio del servidor
            // (`PlayerbotMgr.cpp:104-114`). Un bot aleatorio que estuviera en tu
            // grupo NO vuelve: se pidio con tu cuenta, y con una cuenta detras
            // deja de contar como aleatorio.
            //
            // Meterlo en la lista igual seria prometer algo que no va a pasar y
            // ademas taparlo: el reintento correria treinta segundos y acabaria
            // diciendo "uno no volvio" sin decir por que. Se avisa AHORA, que es
            // cuando el jugador puede decidir si le importa.
            if (sCharacterCache->GetCharacterAccountIdByGuid(g) != accountId)
            {
                Tell(accountId, "RTS: " + member->GetName() +
                     " no es de tu cuenta, asi que no puedo devolverlo al grupo. "
                     "Se queda fuera.");
                continue;
            }

            p.roster.push_back(g);
        }
    }

    // POR DEFECTO, DONDE ESTAS TU. Sirve para cualquier caso raro (el destino
    // no esta en el mundo) y es siempre un sitio valido, que es lo unico que la
    // recarga del cliente necesita.
    p.portMap = master->GetMapId();
    p.portX   = master->GetPositionX();
    p.portY   = master->GetPositionY();
    p.portZ   = master->GetPositionZ();
    p.portO   = master->GetOrientation();

    // Si el destino esta en el mundo como bot, hay que sacarlo ANTES: dos
    // sesiones no pueden tener el mismo personaje, y el login fallaria con un
    // "duplicate character" que no dice nada.
    if (Player* asBot = ObjectAccessor::FindPlayer(target))
    {
        // SU SITIO SE ANOTA AHORA, que es la ultima vez que se puede preguntar.
        // Un momento despues es una fila de base de datos y sacarla de ahi seria
        // volver a parsear el holder para algo que aqui esta a mano.
        p.portMap = asBot->GetMapId();
        p.portX   = asBot->GetPositionX();
        p.portY   = asBot->GetPositionY();
        p.portZ   = asBot->GetPositionZ();
        p.portO   = asBot->GetOrientation();

        if (!rts::bots::Remove(master, target))
            return fail("ese personaje esta en el mundo y no es bot tuyo");
    }

    // SE DICEN LOS NOMBRES, no la cuenta. "1 para el grupo" no distingue entre
    // "solo habia uno" y "los demas no se recogieron", que son dos fallos
    // distintos con dos arreglos distintos -- y decidir cual es era justo lo que
    // costaba una ronda de pruebas.
    std::string list;
    for (ObjectGuid const& g : p.roster)
    {
        std::string n;
        sCharacterCache->GetCharacterNameByGuid(g, n);
        if (!list.empty())
            list += ", ";
        list += n.empty() ? g.ToString() : n;
    }

    g_pending[accountId] = p;
    Tell(accountId, "RTS: cambiando a " + name + ". Vuelven de bot: " + list);
    return true;
}

bool rts::swap::ClientPorted(Player* master)
{
    if (!master || !master->GetSession())
        return false;

    auto it = g_pending.find(master->GetSession()->GetAccountId());
    if (it == g_pending.end() || it->second.phase != WAIT_PORT)
        return false;

    it->second.ported = true;
    return true;
}

bool rts::swap::SuppressOutgoing(WorldSession* session, uint16 opcode)
{
    return session
        && g_swallowLogoutFor != 0
        && opcode == SMSG_LOGOUT_COMPLETE
        && session->GetAccountId() == g_swallowLogoutFor;
}

void rts::swap::Update(uint32 diff, std::vector<Player*>* justSwapped)
{
    // SE RECORRE UNA COPIA DE LAS CLAVES, no el mapa. La fase del cambio llama a
    // `LogoutPlayer`, que dispara `OnPlayerLogout` de forma sincrona y con el
    // medio modulo -- y aunque hoy nadie de ahi toca `g_pending`, un iterador
    // sobre un `unordered_map` no sobrevive a que alguien inserte. Recorrer las
    // claves y volver a buscar cuesta nada y quita la clase de fallo entera.
    std::vector<uint32> accounts;
    accounts.reserve(g_pending.size());
    for (auto const& kv : g_pending)
        accounts.push_back(kv.first);

    for (uint32 accountId : accounts)
    {
        auto it = g_pending.find(accountId);
        if (it == g_pending.end())
            continue;

        Pending& p = it->second;
        p.acc += diff;

        WorldSession* session = sWorldSessionMgr->FindSession(accountId);
        if (!session)
        {
            // Se desconecto a mitad. No hay nada que arreglar desde aqui y el
            // personaje ya esta guardado: se olvida.
            g_pending.erase(it);
            continue;
        }

        // === FASE 1: que el destino salga del mundo =========================
        if (p.phase == WAIT_BOT_OUT)
        {
            if (ObjectAccessor::FindPlayer(p.target))
            {
                if (p.acc > kBotOutMs)
                {
                    Tell(accountId, "RTS: " + p.targetName +
                         " no acaba de salir del mundo; cambio cancelado.");
                    g_pending.erase(it);
                }
                continue;
            }

            // YA NO ESTA, Y AHORA ES CUANDO SE PIDE SU FICHA -- no antes. Si se
            // pidiera con el bot todavia dentro se leerian sus filas ANTES de
            // que `LogoutPlayerBot` las guardara, o sea el personaje de hace un
            // rato: sin lo que hubiera looteado, matado o gastado. Es la misma
            // razon por la que el logout del heroe guarda.
            if (!StartPreload(p))
            {
                Tell(accountId, "RTS: no pude leer la ficha de " + p.targetName + ".");
                g_pending.erase(it);
                continue;
            }

            p.phase = PRELOAD;
            p.acc = 0;
            continue;
        }

        // === FASE 2: ficha lista -> tirar el mundo del cliente ==============
        if (p.phase == PRELOAD)
        {
            if (!p.holderReady)
            {
                if (p.acc > kPreloadMs)
                {
                    Tell(accountId, "RTS: la base de datos no contesto con la ficha de " +
                         p.targetName + "; cambio cancelado. Sigues como estabas.");
                    g_pending.erase(it);
                }
                continue;
            }

            Player* leaving = session->GetPlayer();
            if (!leaving)
            {
                // Se fue del mundo por su cuenta entre una vuelta y otra. No hay
                // heroe que soltar ni a quien contarselo.
                g_pending.erase(it);
                continue;
            }

            // ULTIMA COMPROBACION DE COMBATE. La primera se hizo al pedir el
            // cambio y desde entonces han pasado la salida de un bot y una
            // consulta: sobra tiempo para que te ataque algo. Soltar el
            // personaje en combate deja auras y amenaza apuntando a algo que ya
            // no existe.
            if (leaving->IsInCombat())
            {
                Tell(accountId, "RTS: te han metido en combate; cambio cancelado. "
                     "Vuelve a pedirlo al salir.");
                g_pending.erase(it);
                continue;
            }

            // === LA RECARGA DEL MUNDO, QUE ES LO QUE HACE QUE FUNCIONE ====
            //
            // La primera version mandaba la rafaga de login y ya esta. Llegaba
            // entera, el servidor decia "eres Avy" y el cliente seguia siendo
            // Neferite. La causa esta en `0x004D6C00`, el manejador de creacion
            // de objeto: **lo primero que hace es buscar el guid entre los que
            // ya tiene**, y si lo encuentra se va por la rama de ACTUALIZAR --
            // donde el `UPDATEFLAG_SELF` ni se mira. Solo la rama de CREAR
            // escribe el guid activo. Un `SMSG_DESTROY_OBJECT` del destino no
            // basto, asi que el objeto que estorba no es solo ese.
            //
            // La respuesta es tirar el mundo entero del cliente y dejar que se
            // reconstruya. Y la herramienta es `SMSG_NEW_WORLD`, no
            // `SMSG_LOGIN_VERIFY_WORLD`: desensamblados los dos, el de login
            // (`0x00403DE0`) **compara el mapa con el que ya tienes y si es el
            // mismo se va sin hacer nada** (`je 0x403EAB`), mientras que el de
            // NEW_WORLD (`0x00403D10`) **no compara nada** -- lee mapa y
            // posicion y va directo a `0x00403B70`, la carga del mundo. Por eso
            // el mismo mapa no es un problema para este y si lo era para aquel.
            //
            // Se manda con la forma que usa el nucleo en un teleport lejano
            // (`Player.cpp:1607-1633`): primero `SMSG_TRANSFER_PENDING`, que es
            // lo que pinta la pantalla de carga, y luego `SMSG_NEW_WORLD`.
            {
                WorldPacket pending(SMSG_TRANSFER_PENDING, 4);
                pending << uint32(p.portMap);
                session->SendPacket(&pending);

                WorldPacket nw(SMSG_NEW_WORLD, 4 + 4 + 4 + 4 + 4);
                nw << uint32(p.portMap);
                nw << p.portX << p.portY << p.portZ << p.portO;
                session->SendPacket(&nw);
            }

            // Y NO SE SUELTA EL HEROE TODAVIA. El nucleo lo dice en su propio
            // comentario del teleport: *"move packet sent by client always after
            // far teleport"*. Hasta que el cliente conteste sigue tirando el
            // mundo abajo, y una rafaga de login que aterrice a mitad de eso se
            // pierde con lo demas -- que es justo el fallo que esto viene a
            // arreglar, repetido un tick mas tarde.
            p.phase = WAIT_PORT;
            p.acc = 0;
            continue;
        }

        // === FASE 3: el cliente recargo -> soltar y entrar, sin pausa =======
        if (p.phase == WAIT_PORT)
        {
            if (!p.ported && p.acc <= kPortMs)
                continue;

            if (!p.ported)
            {
                // SE SIGUE IGUAL. El cliente esta en una pantalla de carga
                // esperando algo, y lo unico que puede sacarle de ahi es
                // precisamente la rafaga que viene detras. Abortar aqui seria
                // dejarle mirando el mapa para siempre.
                Tell(accountId, "RTS: tu cliente no confirmo la recarga (¿addon viejo?); "
                     "sigo igual.");
            }

            WorldSession* s2 = sWorldSessionMgr->FindSession(accountId);
            if (!s2)
            {
                g_pending.erase(it);
                continue;
            }
            session = s2;

            Player* leaving = session->GetPlayer();
            if (!leaving)
            {
                g_pending.erase(it);
                continue;
            }

            // TODO LO QUE HAGA FALTA DESPUES DEL LOGOUT, COPIADO ANTES. `p` es
            // una referencia dentro de `g_pending` y `LogoutPlayer` reentra en
            // medio modulo: si alguien inserta ahi, la referencia deja de valer
            // y `p.target` seria memoria de nadie. Es la misma razon por la que
            // el bucle recorre una copia de las claves.
            ObjectGuid const targetGuid = p.target;
            std::shared_ptr<LoginQueryHolder> holder = p.holder;
            p.holder.reset();

            // Y AQUI ES DONDE EL CLIENTE NO SE ENTERA. La bandera se pone justo
            // antes y se quita justo despues: fuera de estas tres lineas el
            // filtro no descarta nada, para que un cambio que falle a mitad no
            // deje a nadie sin poder salir del juego.
            g_swallowLogoutFor = accountId;
            session->LogoutPlayer(true);
            g_swallowLogoutFor = 0;

            // Y UN DESTROY DEL DESTINO ENCIMA, que ya no es el mecanismo pero
            // sigue costando nada. La recarga del mundo se lleva por delante
            // todo lo que el cliente tuviera, asi que esto no deberia hacer
            // falta; se queda porque el fallo que arregla -- una copia vieja del
            // destino que manda la creacion por la rama de "actualizar" -- es
            // silencioso, y el precio de prevenirlo son nueve bytes en el cable.
            // El cliente ignora un destroy de algo que no tiene, que es lo que
            // hace con cada bicho que se aleja.
            {
                WorldPacket destroy(SMSG_DESTROY_OBJECT, 8 + 1);
                destroy << targetGuid;
                destroy << uint8(0);   // onDeath
                session->SendPacket(&destroy);
            }

            // Sin espera en medio: la ficha ya estaba leida. `SendInitSelf`, que
            // va dentro de esto, es lo que manda el objeto con `UPDATEFLAG_SELF`
            // y hace que el cliente se cambie de identidad. Ver la cabecera.
            session->HandlePlayerLoginFromDB(*holder);

            // Y SE AVISA AQUI, QUE ES CUANDO DE VERDAD ERES OTRO.
            //
            // Estaba al final del regrupamiento, y eso ataba el aviso -- y con
            // el la recarga de interfaz del addon -- a que volviera el ultimo
            // bot. Si un compañero tardaba o no volvia, el aviso llegaba treinta
            // segundos tarde o no llegaba, **y entonces las barras de accion se
            // quedaban con los hechizos del personaje anterior**: dos cosas sin
            // relacion aparente pegadas por una dependencia que no tenia motivo
            // de existir. Quien eres no depende de cuantos bots hayan cargado.
            if (Player* fresh = session->GetPlayer())
            {
                // LAS BARRAS DE ACCION NO SE VACIAN SOLAS, Y HAY QUE PEDIRLO.
                //
                // `SendInitialActionButtons()` manda el paquete con **estado 1**,
                // y el propio nucleo documenta lo que significa cada estado
                // (`Player.cpp:5726-5731`):
                //
                //     1 - Used in any SMSG_ACTION_BUTTONS packet with button data
                //     2 - Clears the action bars client sided. This is sent during
                //         spec swap before unlearning and before sending the new
                //         buttons
                //
                // Con el 1 el cliente **no vacia** las casillas que llegan a
                // cero: se queda con lo que tenia. En un login normal da igual
                // porque el cliente viene de la pantalla de seleccion y sus
                // barras estan vacias; aqui no, y las de cada personaje se van
                // **acumulando**. Reportado en juego con la prueba mas clara
                // posible: la misma barra con hechizos de sacerdote y de
                // paladin, o sea de dos personajes distintos a la vez.
                //
                // El cambio de especializacion es exactamente el mismo problema
                // y el nucleo ya lo resuelve asi. Se hace lo que hace el: vaciar
                // primero, mandar despues.
                fresh->SendActionButtons(2);
                fresh->SendInitialActionButtons();

                if (justSwapped)
                    justSwapped->push_back(fresh);
            }

            // `LogoutPlayer` pudo reentrar y tocar el mapa, asi que la entrada
            // se vuelve a buscar en vez de seguir usando `p`.
            auto it2 = g_pending.find(accountId);
            if (it2 == g_pending.end())
                continue;

            it2->second.phase = WAIT_REGROUP;
            it2->second.acc = 0;
            continue;
        }

        // === FASE 4: rehacer el grupo =======================================
        Player* now = session->GetPlayer();
        if (!now)
        {
            // Sin personaje a estas alturas solo puede significar que se ha ido.
            // No es un plazo agotado y no se le da uno: no hay a quien
            // contarselo ni a quien meter de bot.
            g_pending.erase(it);
            continue;
        }

        if (now->GetGUID() != p.target)
        {
            Tell(accountId, "RTS: en la sesion hay otro personaje; dejo el cambio "
                 "como esta y no rehago el grupo.");
            g_pending.erase(it);
            continue;
        }

        // REINTENTAR, NO ESPERAR.
        //
        // `AddPlayerBot` es asincrono (encola una consulta y vuelve) y ademas es
        // IDEMPOTENTE: se planta si el guid ya esta cargando (`botLoading`) o si
        // el bot ya esta en el mundo. Comprobado en `PlayerbotMgr.cpp:87-93`,
        // que es lo que hace seguro llamarlo cada vuelta en vez de tener que
        // llevar la cuenta de quien va por donde.
        //
        // Y hay que insistir porque los bots que salieron con tu logout NO
        // vuelven todos a la vez: mientras uno sigue saliendo del mundo, su
        // `Add` se descarta en silencio. Un solo intento dejaria un grupo a
        // medias sin decir nada, que es peor que no rehacerlo.
        Group* group = now->GetGroup();
        std::string missing;
        int missingCount = 0;
        for (ObjectGuid const& g : p.roster)
        {
            if (group && group->IsMember(g))
                continue;

            ++missingCount;

            // SI NI SIQUIERA SE PUEDE PEDIR, SE DICE UNA VEZ. `bots::Add`
            // devuelve false cuando el gestor de bots del maestro todavia no
            // existe -- puede pasar en la primera vuelta despues del login -- y
            // tambien cuando no existira nunca. Sin esto los dos casos se ven
            // igual: un grupo que no vuelve y ningun motivo.
            if (!rts::bots::Add(now, g) && !p.warnedNoMgr)
            {
                p.warnedNoMgr = true;
                Tell(accountId, "RTS: todavia no puedo pedir bots (el gestor no "
                     "esta listo); sigo intentandolo.");
            }

            if (missingCount <= 8)
            {
                std::string n;
                sCharacterCache->GetCharacterNameByGuid(g, n);
                if (!missing.empty())
                    missing += ", ";
                missing += n.empty() ? g.ToString() : n;
            }
        }

        if (missingCount == 0)
        {
            // Y SE LE VUELVEN A ENSENAR. Los marcos del grupo salian con el
            // nombre puesto y las barras vacias -- que es exactamente como se ve
            // un compañero del que el cliente no tiene datos.
            //
            // Es coherente con lo que hace el nucleo en su propio camino de
            // "entrar en un personaje que ya esta en el mundo"
            // (`CharacterHandler.cpp:1193`): limpiar las referencias de
            // visibilidad y forzar una vuelta, para que el cliente reciba la
            // lista entera otra vez en vez de la diferencia. Aqui hace falta por
            // lo mismo y un paso mas tarde: los bots se anaden DESPUES del
            // login, asi que la vuelta que hizo el login no los incluia.
            now->GetObjectVisibilityContainer().CleanVisibilityReferences();
            now->UpdateObjectVisibility(true);

            Tell(accountId, "RTS: listo. Eres " + p.targetName +
                 " y tu grupo esta entero (" + std::to_string(p.roster.size()) + ").");

            g_pending.erase(it);
            continue;
        }

        if (p.acc > kRegroupMs)
        {
            // SE DICEN LOS NOMBRES, no "hubo un problema" ni un numero. El
            // jugador puede meterlos a mano, pero solo si sabe cuales -- y el
            // nombre es ademas lo unico que permite ver si el que falta es
            // siempre el mismo.
            Tell(accountId, "RTS: eres " + p.targetName + ", pero no volvieron al "
                 "grupo: " + missing + ". Metelos con .playerbots bot add <nombre>.");

            g_pending.erase(it);
        }
    }
}
