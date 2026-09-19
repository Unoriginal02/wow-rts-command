#include "RtsFight.h"

#include "RtsBotApi.h"

#include "Config.h"
#include "Group.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "WorldSessionMgr.h"

#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // Cuatro veces por segundo. Lo que se mira es si hay pelea, que no cambia
    // mas deprisa que eso, y cada cambio cuesta una reinicializacion del motor
    // del bot: hacerlo por fotograma seria pagarla veinte veces por segundo
    // para nada.
    constexpr uint32_t kTickMs = 250;

    // LA GRACIA DE DESPUES, pedida asi: *"ni en un plazo inferior a 3 4
    // segundos despues de salir de combate"*. Y no es un capricho -- entre un
    // bicho que cae y el siguiente que llega hay menos de eso, y sin la espera
    // el grupo entero se pondria a recoger justo en medio.
    constexpr uint32_t kGraceMs = 4000;

    uint32_t g_acc = 0;

    // A quien le hemos quitado nosotros la estrategia. Solo a esos se les
    // devuelve: si el jugador la tenia apagada, se queda apagada.
    std::unordered_set<uint64> g_held;

    // Cuando se vio pelear por ultima vez a cada grupo, en milisegundos de
    // nuestro propio reloj -- que es la suma de los `diff` del mundo. No hace
    // falta que sea la hora: solo se compara consigo mismo.
    std::unordered_map<uint64, uint32_t> g_lastFight;
    uint32_t g_now = 0;

    // Lo que se espera desde que se le ve muerto hasta revivirlo. Ver la
    // cabecera: ni en medio del trabajo del nucleo, ni tan tarde que parezca
    // que no va a pasar nada.
    constexpr uint32_t kDeadWaitMs = 2000;

    // Desde cuando se le ve muerto. Se borra en cuanto vuelve a estar vivo, asi
    // que una muerte nueva empieza a contar de cero.
    std::unordered_map<uint64, uint32_t> g_deadSince;

    bool GroupFighting(Player* bot)
    {
        Group* group = bot->GetGroup();
        if (!group)
            return bot->IsInCombat();

        for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
            if (Player* member = itr->GetSource())
                if (member->IsInCombat())
                    return true;

        return false;
    }
}

// LA PUERTA DE LA INSTANCIA, POR FUERA. Devuelve false si esto no es una
// instancia o si el nucleo no tiene salida apuntada para ese mapa -- y entonces
// no se toca a nadie: sacar a alguien a un sitio inventado es peor que dejarlo
// donde esta.
static bool ReviveAtDoor(Player* who)
{
    if (!who || who->IsAlive())
        return false;

    Map* map = who->GetMap();
    if (!map || !map->IsDungeon())
        return false;

    AreaTriggerTeleport const* door = sObjectMgr->GetGoBackTrigger(map->GetId());
    if (!door)
        return false;

    // EL ORDEN IMPORTA. Primero vivo, luego se le quita el cadaver, y al final
    // el viaje: teletransportar a un fantasma lo llevaria a la puerta SIGUIENDO
    // muerto, que es justo la mitad del problema que esto viene a quitar.
    who->ResurrectPlayer(1.0f);
    who->SpawnCorpseBones();
    who->TeleportTo(door->target_mapId, door->target_X, door->target_Y,
                    door->target_Z, door->target_Orientation);
    return true;
}

void rts::fight::Update(uint32_t diff)
{
    g_now += diff;

    g_acc += diff;
    if (g_acc < kTickMs)
        return;
    g_acc = 0;

    // Igual que en `RtsLfg`: se mira dentro del cerrojo del mapa de jugadores y
    // se actua fuera. Cambiar una estrategia reinicia el motor del bot, que es
    // mucho mas de lo que conviene hacer con ese cerrojo cogido.
    struct Change { Player* bot = nullptr; bool hold = false; };
    std::vector<Change> todo;
    std::vector<Player*> toRevive;

    bool const reviveOn = sConfigMgr->GetOption<bool>("RTS.Dungeon.ReviveAtDoor", true);

    sWorldSessionMgr->DoForAllOnlinePlayers([&todo, &toRevive, reviveOn](Player* player)
    {
        if (!player)
            return;

        // LOS MUERTOS PRIMERO, Y ESTE ES EL UNICO SITIO QUE MIRA TAMBIEN A LOS
        // JUGADORES DE VERDAD: la regla es "los bots y el heroe", y el heroe no
        // es un bot. Lo demas de este barrido es de bots.
        uint64 const key = player->GetGUID().GetRawValue();
        if (player->IsAlive())
        {
            g_deadSince.erase(key);
        }
        else if (reviveOn)
        {
            auto const since = g_deadSince.find(key);
            if (since == g_deadSince.end())
                g_deadSince[key] = g_now;
            else if (g_now - since->second >= kDeadWaitMs)
                toRevive.push_back(player);
        }

        if (!rts::bots::Driven(player))
            return;

        uint64 const group = player->GetGroup()
            ? player->GetGroup()->GetGUID().GetRawValue()
            : player->GetGUID().GetRawValue();

        if (GroupFighting(player))
            g_lastFight[group] = g_now;

        auto const seen = g_lastFight.find(group);
        bool const quiet = (seen == g_lastFight.end()) || (g_now - seen->second > kGraceMs);

        bool const held = g_held.count(key) != 0;

        if (!quiet && !held && rts::bots::Has(player, "loot", rts::bots::IDLE))
            todo.push_back({ player, true });
        else if (quiet && held)
            todo.push_back({ player, false });
    });

    // Fuera del cerrojo, como todo lo demas: revivir teletransporta, y un
    // teletransporte mueve al jugador de mapa -- o sea, toca las mismas listas
    // que se estan recorriendo.
    for (Player* dead : toRevive)
    {
        if (ReviveAtDoor(dead))
            g_deadSince.erase(dead->GetGUID().GetRawValue());
    }

    for (Change const& c : todo)
    {
        uint64 const key = c.bot->GetGUID().GetRawValue();
        if (c.hold)
        {
            if (rts::bots::Change(c.bot, "-loot", rts::bots::IDLE))
                g_held.insert(key);
        }
        else
        {
            rts::bots::Change(c.bot, "+loot", rts::bots::IDLE);
            g_held.erase(key);
        }
    }
}
