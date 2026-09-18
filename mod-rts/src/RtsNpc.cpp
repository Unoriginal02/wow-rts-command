#include "RtsNpc.h"

#include "RtsBotApi.h"   // solo por `Resolve` -- ver la cabecera

#include "Bag.h"
#include "ObjectDefines.h"   // INTERACTION_DISTANCE
#include "Creature.h"
#include "CreatureData.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Trainer.h"

#include <algorithm>

namespace
{
    // Igual que en bolsas y misiones: tu propio personaje tambien vale. Un
    // vendedor delante y un boton de "vender la basura" no deberia servir solo
    // para los bots.
    Player* Who(Player* master, std::string const& name)
    {
        if (!master || name.empty())
            return nullptr;
        if (name == master->GetName())
            return master;
        return rts::bots::Resolve(master, name);
    }

    Creature* NpcOf(Player* master, ObjectGuid guid)
    {
        if (!master || !guid)
            return nullptr;
        return ObjectAccessor::GetCreature(*master, guid);
    }
}

// === entrenador =============================================================

bool rts::npc::TrainerList(Player* master, std::string const& botName, ObjectGuid npcGuid,
                       std::vector<TrainSpell>& out, uint32& copper, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    ::Trainer::Trainer const* trainer = sObjectMgr->GetTrainer(npc->GetEntry());
    if (!trainer)
        return fail("ese personaje no entrena");

    if (!trainer->IsTrainerValidForPlayer(bot))
        return fail("no entrena a los de su clase");

    copper = bot->GetMoney();

    // El descuento por reputacion es el MISMO calculo que hace el nucleo al
    // mandar la lista a un cliente (`Trainer.cpp:39`). Se repite aqui porque lo
    // que se dibuja tiene que ser lo que se va a cobrar: un precio en la ventana
    // distinto del que se cobra es peor que no ensenar precio.
    float const discount = bot->GetReputationPriceDiscount(npc);

    for (::Trainer::Spell const& s : trainer->GetSpells())
    {
        // Los que no le pegan a su clase o raza NO SALEN. El nucleo los filtra
        // igual antes de mandar la lista, y si no se filtraran, un guerrero
        // veria la lista entera del entrenador de armas en gris sin poder
        // aprender nada -- que se lee como que el boton no funciona.
        if (!bot->IsSpellFitByClassAndRace(s.SpellId))
            continue;

        TrainSpell t;
        t.spellId  = s.SpellId;
        t.cost     = uint32(s.MoneyCost * discount);
        t.reqLevel = s.ReqLevel;

        // Los tres estados, derivados de lo publico. `GetSpellState` es privada
        // -- ver la cabecera, costo una compilacion darlo por hecho.
        if (bot->HasSpell(s.SpellId))
            t.state = SP_KNOWN;
        else if (trainer->CanTeachSpell(bot, &s))
            t.state = SP_AVAILABLE;
        else
            t.state = SP_UNAVAILABLE;

        out.push_back(t);
    }

    return true;
}

bool rts::npc::Train(Player* master, std::string const& botName, ObjectGuid npcGuid,
                     uint32 spellId, int& learned, uint32& spent, std::string* why)
{
    learned = 0;
    spent = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    ::Trainer::Trainer* trainer = sObjectMgr->GetTrainer(npc->GetEntry());
    if (!trainer)
        return fail("ese personaje no entrena");

    if (!trainer->IsTrainerValidForPlayer(bot))
        return fail("no entrena a los de su clase");

    uint32 const before = bot->GetMoney();

    if (spellId)
    {
        ::Trainer::Spell const* s = trainer->GetSpell(spellId);
        if (!s)
            return fail("ese personaje no ensena eso");
        if (!trainer->CanTeachSpell(bot, s))
            return fail("todavia no puede aprenderlo");

        trainer->TeachSpell(npc, bot, spellId);
        learned = 1;
        spent = before > bot->GetMoney() ? before - bot->GetMoney() : 0;
        return true;
    }

    // TODO LO QUE PUEDA, DE MAS BARATO A MAS CARO. Ver la cabecera: el orden de
    // la tabla del entrenador no significa nada, y gastarse el oro en el primero
    // caro que aparezca es lo contrario de "todo lo que pueda".
    std::vector<::Trainer::Spell const*> can;
    for (::Trainer::Spell const& s : trainer->GetSpells())
    {
        if (bot->IsSpellFitByClassAndRace(s.SpellId) && trainer->CanTeachSpell(bot, &s))
            can.push_back(&s);
    }

    std::sort(can.begin(), can.end(),
              [](::Trainer::Spell const* a, ::Trainer::Spell const* b)
              { return a->MoneyCost < b->MoneyCost; });

    for (::Trainer::Spell const* s : can)
    {
        // SE VUELVE A PREGUNTAR EN CADA VUELTA, y no es paranoia: aprender un
        // hechizo puede desbloquear el siguiente rango, subir una habilidad y
        // dejar sin dinero. La lista se calculo antes de gastar nada, asi que
        // sin esta comprobacion se intentaria pagar lo que ya no se puede.
        if (!trainer->CanTeachSpell(bot, s))
            continue;

        uint32 const money = bot->GetMoney();
        trainer->TeachSpell(npc, bot, s->SpellId);

        // `TeachSpell` no dice si funciono. Que el dinero baje, o que ahora lo
        // sepa, es la unica prueba -- y con hechizos gratis (coste 0) la unica
        // buena es la segunda.
        if (bot->HasSpell(s->SpellId) || bot->GetMoney() < money)
            ++learned;
        else
            break;   // no pudo pagar: los siguientes son mas caros todavia
    }

    spent = before > bot->GetMoney() ? before - bot->GetMoney() : 0;
    return true;
}

// === vendedor ===============================================================

bool rts::npc::Vendor(Player* master, std::string const& botName, ObjectGuid npcGuid,
                      std::vector<VendorEntry>& out, uint32& copper, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    VendorItemData const* items = npc->GetVendorItems();
    if (!items || items->Empty())
        return fail("ese personaje no vende nada");

    copper = bot->GetMoney();
    float const discount = bot->GetReputationPriceDiscount(npc);

    for (uint32 i = 0; i < items->GetItemCount(); ++i)
    {
        VendorItem const* v = items->GetItem(i);
        if (!v)
            continue;

        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(v->item);
        if (!proto)
            continue;

        VendorEntry e;
        // EL INDICE ES EL QUE ESPERA `BuyItemFromVendorSlot`, sin renumerar. Un
        // hueco que se salte por falta de plantilla no tiene que correr los
        // demas, o comprar el quinto compraria el sexto.
        e.slot   = i;
        e.itemId = v->item;
        e.price  = v->IsGoldRequired(proto) ? uint32(proto->BuyPrice * discount) : 0;
        e.left   = v->maxcount ? int32(npc->GetVendorItemCurrentCount(v)) : -1;
        e.extendedCost = v->ExtendedCost;
        out.push_back(e);
    }

    return true;
}

bool rts::npc::Buy(Player* master, std::string const& botName, ObjectGuid npcGuid,
                   uint32 slot, uint32 count, std::string* why)
{
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    VendorItemData const* items = npc->GetVendorItems();
    VendorItem const* v = items ? items->GetItem(slot) : nullptr;
    if (!v)
        return fail("ese hueco del vendedor ya no existe");

    if (count < 1)
        count = 1;
    if (count > 255)
        count = 255;

    // COMPRAR SI EXIGE TENER EL VENDEDOR DELANTE, y se deja asi -- ver la
    // cabecera. `BuyItemFromVendorSlot` hace `GetNPCIfCanInteractWith` por
    // dentro, asi que un bot lejos falla aqui y hay que decirlo: si no, el boton
    // no hace nada y no se sabe por que.
    if (!bot->IsWithinDistInMap(npc, INTERACTION_DISTANCE))
        return fail("esta demasiado lejos del vendedor");

    if (!bot->BuyItemFromVendorSlot(npcGuid, slot, v->item, uint8(count), NULL_BAG, NULL_SLOT))
        return fail("no pudo comprarlo (dinero, hueco o requisitos)");

    return true;
}

bool rts::npc::SellJunk(Player* master, std::string const& botName, ObjectGuid npcGuid,
                        int& sold, uint32& earned, std::string* why)
{
    sold = 0;
    earned = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    if (!npc->HasNpcFlag(UNIT_NPC_FLAG_VENDOR))
        return fail("ese personaje no compra nada");

    if (!bot->IsWithinDistInMap(npc, INTERACTION_DISTANCE))
        return fail("esta demasiado lejos del vendedor");

    // Se recogen PRIMERO y se destruyen despues. Modificar las bolsas mientras
    // se recorren es la forma clasica de saltarse la mitad de los huecos, y aqui
    // saltarse uno solo significa "no vendio esa piedra" sin que nada lo diga.
    struct Junk { uint8 bag, slot; uint32 id, count, price; };
    std::vector<Junk> junk;

    auto consider = [&](uint8 bag, uint8 slot)
    {
        Item* item = bot->GetItemByPos(bag, slot);
        if (!item || item->IsEquipped())
            return;

        ItemTemplate const* proto = item->GetTemplate();
        if (!proto || proto->Quality != ITEM_QUALITY_POOR || proto->SellPrice == 0)
            return;

        // Una bolsa gris con cosas dentro se venderia con las cosas dentro.
        if (Bag const* asBag = item->ToBag())
        {
            if (!asBag->IsEmpty())
                return;
        }

        Junk j;
        j.bag = bag; j.slot = slot;
        j.id = item->GetEntry();
        j.count = item->GetCount();
        j.price = proto->SellPrice * item->GetCount();
        junk.push_back(j);
    };

    for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        consider(INVENTORY_SLOT_BAG_0, slot);

    for (uint8 bag = INVENTORY_SLOT_BAG_START; bag < INVENTORY_SLOT_BAG_END; ++bag)
    {
        Bag* container = bot->GetBagByPos(bag);
        if (!container)
            continue;
        for (uint8 slot = 0; slot < container->GetBagSize(); ++slot)
            consider(bag, slot);
    }

    for (Junk const& j : junk)
    {
        bot->DestroyItem(j.bag, j.slot, true);
        bot->ModifyMoney(int32(j.price));
        earned += j.price;
        ++sold;
    }

    return true;
}

bool rts::npc::Repair(Player* master, std::string const& botName, ObjectGuid npcGuid,
                      uint32& cost, std::string* why)
{
    cost = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* bot = Who(master, botName);
    if (!bot)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese personaje");

    if (!npc->HasNpcFlag(UNIT_NPC_FLAG_REPAIR))
        return fail("ese personaje no repara");

    if (!bot->IsWithinDistInMap(npc, INTERACTION_DISTANCE))
        return fail("esta demasiado lejos del reparador");

    uint32 const before = bot->GetMoney();
    bot->DurabilityRepairAll(true, bot->GetReputationPriceDiscount(npc), false);
    cost = before > bot->GetMoney() ? before - bot->GetMoney() : 0;
    return true;
}

bool rts::npc::SellItem(Player* master, std::string const& who, ObjectGuid npcGuid,
                        ObjectGuid itemGuid, uint32& itemId, uint32& count, uint32& earned,
                        std::string* why)
{
    itemId = 0;
    count = 0;
    earned = 0;
    auto fail = [why](char const* reason) { if (why) *why = reason; return false; };

    Player* owner = Who(master, who);
    if (!owner)
        return fail("ese personaje no es de los tuyos");

    Creature* npc = NpcOf(master, npcGuid);
    if (!npc)
        return fail("ya no veo a ese vendedor");

    if (!npc->HasNpcFlag(UNIT_NPC_FLAG_VENDOR))
        return fail("ese personaje no compra nada");

    // LA DISTANCIA ES LA DEL DUENNO, no la tuya. Vender es un trato entre el
    // vendedor y quien tiene el objeto, y el resto del fichero mide igual: tu
    // puedes estar pegado al tendero y el bot haberse quedado atras.
    if (!owner->IsWithinDistInMap(npc, INTERACTION_DISTANCE))
        return fail("ese personaje esta demasiado lejos del vendedor");

    Item* item = owner->GetItemByGuid(itemGuid);
    if (!item)
        return fail("ya no tiene ese objeto");

    if (item->IsEquipped())
        return fail("lo lleva puesto");

    ItemTemplate const* proto = item->GetTemplate();
    if (!proto)
        return fail("no reconozco ese objeto");

    if (proto->SellPrice == 0)
        return fail("el vendedor no lo quiere");

    // Una bolsa con cosas dentro se venderia con las cosas dentro, igual que en
    // `SellJunk`.
    if (Bag const* asBag = item->ToBag())
        if (!asBag->IsEmpty())
            return fail("es una bolsa con cosas dentro");

    itemId = item->GetEntry();
    count = item->GetCount();
    earned = proto->SellPrice * count;

    owner->DestroyItem(item->GetBagSlot(), item->GetSlot(), true);
    owner->ModifyMoney(int32(earned));
    return true;
}
