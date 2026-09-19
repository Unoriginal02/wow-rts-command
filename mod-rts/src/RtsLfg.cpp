#include "RtsLfg.h"

#include "RtsBotApi.h"
#include "RtsCommandMode.h"

#include "Chat.h"
#include "Group.h"
#include "LFGMgr.h"
#include "ObjectAccessor.h"
#include "ObjectGuid.h"
#include "Player.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include "WorldSessionMgr.h"

#include <cstring>

#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // Cinco veces por segundo. Lo que se vigila es un estado que dura lo que
    // tarde el grupo en contestar, y llegar un quinto de segundo tarde no se
    // nota; lo que si importa es llegar ANTES que la vuelta de pensamiento de
    // un bot, que es de medio segundo para arriba.
    constexpr uint32_t kTickMs = 200;

    // Lo que se les calla la IA. Sobra para que la comprobacion se cierre en la
    // misma vuelta, y si algo sale mal es una pausa de dos segundos en un bot,
    // no un bot parado.
    constexpr uint32_t kHoldMs = 2000;

    uint32_t g_acc = 0;

    // A quien ya hemos contestado en ESTA comprobacion. Se limpia en cuanto el
    // grupo deja de estar comprobando, que es lo que permite que la siguiente
    // vez se vuelva a contestar -- sin esto, pedir mazmorra dos veces seguidas
    // solo funcionaria la primera.
    std::unordered_set<uint64> g_answered;

    uint8 RoleBits(std::string const& role)
    {
        if (role == "tank")
            return ::lfg::PLAYER_ROLE_TANK;
        if (role == "heal")
            return ::lfg::PLAYER_ROLE_HEALER;
        return ::lfg::PLAYER_ROLE_DAMAGE;
    }

    struct Answer
    {
        Player* bot = nullptr;
        ObjectGuid group;
        uint8 roles = 0;
        std::string role;
    };

    // Lo que hay que contestar en el proximo tick: bot -> numero de propuesta.
    std::unordered_map<uint64, uint32> g_proposals;

    // El paquete de la propuesta, tal y como lo arma
    // `WorldSession::SendLfgUpdateProposal`:
    //
    //     uint32 mazmorra | uint8 estado | uint32 numero | ...
    //
    // O sea que el estado esta en el byte 4 y el numero en los cuatro
    // siguientes. Se lee a mano y con el tamano comprobado porque un
    // `WorldPacket` de salida no se puede leer con su propio lector sin mover
    // su posicion -- y esa posicion es la del nucleo, que todavia lo esta
    // usando.
    constexpr uint8 kProposalInitiating = 0;
    constexpr size_t kProposalHeader = 9;
}

void rts::dungeon::Update(uint32_t diff)
{
    g_acc += diff;
    if (g_acc < kTickMs)
        return;
    g_acc = 0;

    // SE MIRA DENTRO DEL CERROJO Y SE ACTUA FUERA. `UpdateRoleCheck` manda
    // paquetes, puede cerrar la comprobacion y mete al grupo en la cola -- o
    // sea, toca medio servidor -- y hacerlo con el mapa de jugadores cogido es
    // pedirle a un interbloqueo que aparezca el dia que haya prisa.
    std::vector<Answer> todo;

    sWorldSessionMgr->DoForAllOnlinePlayers([&todo](Player* player)
    {
        if (!player || !rts::bots::Driven(player))
            return;

        Group* group = player->GetGroup();
        if (!group)
            return;

        uint64 const key = player->GetGUID().GetRawValue();
        ObjectGuid const gguid = group->GetGUID();

        if (sLFGMgr->GetState(gguid) != ::lfg::LFG_STATE_ROLECHECK)
        {
            g_answered.erase(key);
            return;
        }

        if (g_answered.count(key))
            return;

        // EL ROL ES EL QUE TU LE TIENES PUESTO, leido de la estrategia que el
        // bot esta corriendo de verdad -- la misma que dibuja la fila de roles.
        //
        // Y SI NO SE PUEDE DECIR, SE CONTESTA IGUAL, por especializacion. Antes
        // aqui se callaba, y callarse es lo peor que se puede hacer en esta
        // ventana: el bot se queda con su interrogante, el grupo no llega a
        // ponerse en cola y no hay NADA en pantalla que explique por que -- que
        // es exactamente como se veia. Un rol aproximado se cambia en la fila
        // de roles; una comprobacion parada no se arregla desde ningun sitio.
        std::string role = rts::command::ActiveRole(player);
        if (role.empty())
            role = rts::bots::SpecRole(player);
        if (role.empty())
            role = "dps";

        Answer a;
        a.bot = player;
        a.group = gguid;
        a.roles = RoleBits(role);
        a.role = role;
        todo.push_back(a);
    });

    // LO QUE SE CONTESTA SE DICE, en una linea y en la del jefe del grupo. La
    // ventana de funciones solo pinta un interrogante mientras falta alguien, y
    // un interrogante no dice quien ni por que: esta linea es la diferencia
    // entre "no entro en la mazmorra" y "Bob va de dps".
    std::string said;
    Player* master = nullptr;

    for (Answer const& a : todo)
    {
        rts::bots::HoldAi(a.bot, kHoldMs);
        g_answered.insert(a.bot->GetGUID().GetRawValue());
        sLFGMgr->UpdateRoleCheck(a.group, a.bot->GetGUID(), a.roles);

        if (!master)
            master = rts::bots::MasterOf(a.bot);
        if (!said.empty())
            said += ", ";
        said += a.bot->GetName() + " " + a.role;
    }

    if (master && master->GetSession() && !said.empty())
        ChatHandler(master->GetSession()).PSendSysMessage("RTS: funciones -> %s.", said.c_str());

    // Y LAS PROPUESTAS QUE HAYAN LLEGADO: que si. Se vacia la lista al mismo
    // tiempo que se recorre una copia, para que una propuesta nueva que llegue
    // mientras contestamos no se pierda ni se conteste dos veces.
    if (!g_proposals.empty())
    {
        std::unordered_map<uint64, uint32> pending;
        pending.swap(g_proposals);

        for (auto const& it : pending)
        {
            ObjectGuid const guid(it.first);
            Player* bot = ObjectAccessor::FindPlayer(guid);
            if (!bot)
                continue;
            rts::bots::HoldAi(bot, kHoldMs);
            sLFGMgr->UpdateProposal(it.second, guid, true);
        }
    }
}

//--- La propuesta: "tu mazmorra esta lista" ---------------------------------

void rts::dungeon::NoteProposal(Player* bot, WorldPacket const* packet)
{
    if (!bot || !packet || !rts::bots::Driven(bot))
        return;

    if (packet->size() < kProposalHeader)
        return;

    uint8 const* raw = packet->contents();
    if (!raw || raw[4] != kProposalInitiating)
        return;

    uint32 id = 0;
    memcpy(&id, raw + 5, sizeof(id));
    if (!id)
        return;

    g_proposals[bot->GetGUID().GetRawValue()] = id;
}

int rts::dungeon::Clear(Player* master, int& deserters, int& queues)
{
    deserters = 0;
    queues = 0;
    if (!master)
        return 0;

    std::vector<Player*> people;
    if (Group* group = master->GetGroup())
    {
        for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
            if (Player* member = itr->GetSource())
                people.push_back(member);
    }
    else
        people.push_back(master);

    for (Player* member : people)
    {
        if (member->HasAura(::lfg::LFG_SPELL_DUNGEON_DESERTER))
        {
            member->RemoveAurasDueToSpell(::lfg::LFG_SPELL_DUNGEON_DESERTER);
            ++deserters;
        }

        if (sLFGMgr->GetState(member->GetGUID()) != ::lfg::LFG_STATE_NONE)
        {
            sLFGMgr->LeaveLfg(member->GetGUID());
            ++queues;
        }

        g_proposals.erase(member->GetGUID().GetRawValue());
        g_answered.erase(member->GetGUID().GetRawValue());
    }

    return int(people.size());
}
