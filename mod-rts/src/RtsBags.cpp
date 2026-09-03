#include "RtsBags.h"

#include "RtsBotApi.h"   // solo por `Resolve` -- ver la cabecera

#include "Bag.h"
#include "DatabaseEnv.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "ObjectAccessor.h"
#include "Player.h"

namespace
{
    // El jugador tambien es un destino valido: sus propias bolsas salen en la
    // ventana igual que las de los bots, porque "pasarle esto al mago" y
    // "quitarselo al mago" son el mismo gesto en direcciones distintas.
    Player* Who(Player* master, std::string const& name)
    {
        if (!master || name.empty())
            return nullptr;
        if (name == master->GetName())
            return master;
        return rts::bots::Resolve(master, name);
    }

    uint32 FlagsOf(Item* item)
    {
        uint32 f = 0;

        // Vinculado al alma: no hay forma de moverlo y el cliente lo apaga en
        // vez de dejar intentarlo. `IsBoundAccountWide` NO cuenta: eso son los
        // objetos de cuenta, que si viajan entre personajes.
        if (item->IsSoulBound() && !item->IsBoundAccountWide())
            f |= rts::bags::FLAG_BOUND;

        if (item->ToBag())
            f |= rts::bags::FLAG_CONTAINER;

        return f;
    }

    void Push(std::vector<rts::bags::Entry>& out, uint8 bag, uint8 slot, Item* item)
    {
        rts::bags::Entry e;
        e.bag   = bag;
        e.slot  = slot;
        e.guid  = item->GetGUID();
        e.itemId = item->GetEntry();
        e.count = item->GetCount();
        e.quality = item->GetTemplate() ? item->GetTemplate()->Quality : 0;
        e.flags = FlagsOf(item);
        out.push_back(e);
    }
}

// EL LLAVERO NO SALE, Y ES UNA DECISION.
//
// `KEYRING_SLOT_START..END` son treinta y dos huecos que en la practica llevan
// llaves, y una llave esta vinculada: saldrian treinta y dos casillas
// permanentemente apagadas empujando hacia abajo lo unico que se puede mover.
// Si algun dia hace falta, es un bucle mas aqui y un contenedor mas en el
// volcado; el cliente no cambia porque ya dibuja los contenedores que le digan.
bool rts::bags::Dump(Player* master, std::string const& name,
                     std::vector<Container>& bagsOut,
                     std::vector<Entry>& itemsOut,
                     uint32& copper, uint32& freeSlots)
{
    Player* who = Who(master, name);
    if (!who)
        return false;

    copper = who->GetMoney();
    freeSlots = 0;

    // La mochila. `INVENTORY_SLOT_BAG_0` es 255 y NO es una bolsa equipada: es
    // el contenedor implicito del personaje, y sus huecos utiles van de
    // INVENTORY_SLOT_ITEM_START a INVENTORY_SLOT_ITEM_END. Los numeros de hueco
    // se mandan tal cual y no renumerados desde cero, para que el cliente pueda
    // devolvernos el par (bag, slot) sin que nadie tenga que traducir en medio
    // -- una traduccion en un lado y no en el otro es como se mueven objetos al
    // sitio equivocado.
    {
        Container c;
        c.bag  = INVENTORY_SLOT_BAG_0;
        c.size = INVENTORY_SLOT_ITEM_END - INVENTORY_SLOT_ITEM_START;
        bagsOut.push_back(c);

        for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        {
            if (Item* item = who->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                Push(itemsOut, INVENTORY_SLOT_BAG_0, slot, item);
            else
                ++freeSlots;
        }
    }

    // Las bolsas equipadas.
    for (uint8 bag = INVENTORY_SLOT_BAG_START; bag < INVENTORY_SLOT_BAG_END; ++bag)
    {
        Bag* container = who->GetBagByPos(bag);
        if (!container)
            continue;

        Container c;
        c.bag  = bag;
        c.size = static_cast<uint8>(container->GetBagSize());
        bagsOut.push_back(c);

        for (uint8 slot = 0; slot < c.size; ++slot)
        {
            if (Item* item = who->GetItemByPos(bag, slot))
                Push(itemsOut, bag, slot, item);
            else
                ++freeSlots;
        }
    }

    return true;
}

bool rts::bags::Move(Player* master, std::string const& from, std::string const& to,
                     ObjectGuid itemGuid, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* src = Who(master, from);
    Player* dst = Who(master, to);
    if (!src)
        return fail("ese personaje no es de los tuyos");
    if (!dst)
        return fail("ese destino no es de los tuyos");
    if (src == dst)
        return fail("origen y destino son el mismo");

    Item* item = src->GetItemByGuid(itemGuid);
    if (!item)
        return fail("ya no tiene ese objeto");

    // Equipado: mover una espada de la mano seria desequipar por la puerta de
    // atras, sin las comprobaciones de equipo. Se dice y no se hace.
    if (item->IsEquipped())
        return fail("esta equipado");

    if (item->IsSoulBound() && !item->IsBoundAccountWide())
        return fail("esta vinculado al alma");

    // Un objeto vinculado a OTRO -- botin todavia repartible, un objeto de
    // cuenta de otra cuenta. `IsBindedNotWith` es la pregunta exacta y la unica
    // que conoce esos casos.
    if (item->IsBindedNotWith(dst))
        return fail("esta vinculado a otro personaje");

    if (Bag* asBag = item->ToBag())
    {
        if (!asBag->IsEmpty())
            return fail("es una bolsa con cosas dentro");
    }

    // ¿Le cabe al destino? El nucleo lo contesta, y hay que HACERLE CASO: sin
    // esto el objeto sale del origen y no entra en ningun sitio.
    ItemPosCountVec dest;
    InventoryResult const res = dst->CanStoreItem(NULL_BAG, NULL_SLOT, dest, item, false);
    if (res != EQUIP_ERR_OK)
    {
        if (res == EQUIP_ERR_INVENTORY_FULL)
            return fail("no le queda hueco");
        return fail("no puede llevarlo");
    }

    uint8 const bag  = item->GetBagSlot();
    uint8 const slot = item->GetSlot();

    // La secuencia del intercambio del nucleo (TradeHandler.cpp:134,150). El
    // `true` del final es `in_characterInventoryDB`: la fila de
    // `character_inventory` YA existe -- `RemoveItem` saca el objeto del
    // almacenamiento sin tocar el objeto -- asi que se ACTUALIZA
    // (`ITEM_CHANGED`), no se crea. Ver la cabecera.
    src->MoveItemFromInventory(bag, slot, true);
    dst->MoveItemToInventory(dest, item, true, true);

    // Los dos personajes se guardan en el acto, EN UNA SOLA TRANSACCION.
    //
    // Sin guardar, un cierre a lo bruto del servidor deja el objeto en las dos
    // bolsas o en ninguna segun a quien le tocara guardarse antes -- y este
    // servidor se cierra a lo bruto lo bastante a menudo como para que no sea
    // teorico: hay un apartado entero de CLAUDE.md sobre el bit de realm que se
    // queda pegado justo por eso.
    //
    // Y la transaccion no es adorno: el propio nucleo avisa, en el intercambio,
    // de que *"SaveInventoryAndGoldToDB() not have own transaction guards"*
    // (TradeHandler.cpp:577). Guardar los dos por separado es exactamente la
    // ventana en la que se duplica o se pierde un objeto.
    CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
    src->SaveInventoryAndGoldToDB(trans);
    dst->SaveInventoryAndGoldToDB(trans);
    CharacterDatabase.CommitTransaction(trans);

    return true;
}
