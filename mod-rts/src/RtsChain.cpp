#include "RtsChain.h"

#include "RtsOrders.h"

#include "ObjectAccessor.h"
#include "Player.h"
#include "Unit.h"

#include <unordered_map>

namespace
{
    // Medio segundo. El unico evento que importa es "se murio el de turno", y
    // medio segundo de retraso en pasar al siguiente no se nota -- mientras que
    // mirar esto en cada tick del mundo por cada jugador si se notaria.
    constexpr uint32 kTickMs = 500;

    struct Chain
    {
        std::vector<ObjectGuid>  targets;
        std::vector<std::string> names;
        ObjectGuid ordered;      // a quien se le mando ya la orden
        uint32     acc = 0;
    };

    std::unordered_map<ObjectGuid, Chain> g_chains;

    // El primero de la lista que sigue vivo y visible. Vacio si no queda
    // ninguno, que es como termina una cadena.
    ObjectGuid FirstAlive(Player* master, Chain const& c)
    {
        for (ObjectGuid const& g : c.targets)
        {
            Unit* u = ObjectAccessor::GetUnit(*master, g);
            if (u && u->IsInWorld() && u->IsAlive())
                return g;
        }
        return ObjectGuid::Empty;
    }

    void Order(Player* master, Chain& c, ObjectGuid target)
    {
        for (std::string const& n : c.names)
            rts::orders::AttackBot(master, n, target);
        c.ordered = target;
    }
}

bool rts::chain::Set(Player* master, std::vector<ObjectGuid> const& targets,
                     std::vector<std::string> const& names)
{
    if (!master)
        return false;

    if (targets.empty() || names.empty())
    {
        Stop(master);
        return true;
    }

    Chain& c = g_chains[master->GetGUID()];
    c.targets = targets;
    c.names   = names;
    c.acc     = 0;

    ObjectGuid const now = FirstAlive(master, c);
    if (!now)
    {
        g_chains.erase(master->GetGUID());
        return false;
    }

    // SE REORDENA SOLO SI CAMBIO EL DE TURNO. Anadir un quinto enemigo a la cola
    // mientras el grupo pega al primero no tiene que interrumpir nada: la lista
    // llega entera cada vez, asi que sin esta comprobacion cada click de mas
    // reiniciaria el ataque en curso.
    if (now != c.ordered)
        Order(master, c, now);

    return true;
}

void rts::chain::Stop(Player* master)
{
    if (master)
        g_chains.erase(master->GetGUID());
}

void rts::chain::ForgetPlayer(Player* master)
{
    Stop(master);
}

void rts::chain::Update(uint32 diff)
{
    for (auto it = g_chains.begin(); it != g_chains.end();)
    {
        Chain& c = it->second;
        c.acc += diff;
        if (c.acc < kTickMs)
        {
            ++it;
            continue;
        }
        c.acc = 0;

        Player* master = ObjectAccessor::FindPlayer(it->first);
        if (!master || !master->IsInWorld())
        {
            it = g_chains.erase(it);
            continue;
        }

        ObjectGuid const now = FirstAlive(master, c);
        if (!now)
        {
            // Se acabo la lista. Se borra en vez de quedarse vacia: una cadena
            // terminada que sigue existiendo volveria a arrancar sola si algo
            // de la lista reapareciera (un cadaver que se levanta, un bicho que
            // vuelve a la vista), y eso seria una orden que nadie dio.
            it = g_chains.erase(it);
            continue;
        }

        if (now != c.ordered)
            Order(master, c, now);

        ++it;
    }
}

bool rts::chain::Current(Player* master, ObjectGuid& guid, int& done, int& total)
{
    if (!master)
        return false;

    auto it = g_chains.find(master->GetGUID());
    if (it == g_chains.end())
        return false;

    Chain const& c = it->second;
    guid  = FirstAlive(master, c);
    total = static_cast<int>(c.targets.size());

    done = 0;
    for (ObjectGuid const& g : c.targets)
    {
        if (g == guid)
            break;
        ++done;
    }

    return guid ? true : false;
}
