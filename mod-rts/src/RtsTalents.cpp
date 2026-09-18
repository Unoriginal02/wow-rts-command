#include "RtsTalents.h"

#include "DBCStores.h"
#include "Pet.h"
#include "Player.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <algorithm>
#include <map>
#include <vector>

namespace
{
    // Una build: talento -> rango EN BASE 1 (1..5). El cero no se guarda, se
    // borra la entrada: asi "no tiene puntos" es una sola cosa y no dos.
    using Build = std::map<uint32, uint32>;

    // Cinco puntos por fila, que es la regla del juego: para poner algo en la
    // fila N hacen falta 5*N puntos en ese arbol (la fila de arriba es la 0).
    constexpr uint32 kPerRow = 5;

    // El nombre de un talento, para poder decir CUAL estorba. Sale del hechizo
    // de su primer rango y en el idioma de la sesion: un aviso que dice
    // "talento 1234" no lo entiende nadie.
    std::string TalentName(Player* player, TalentEntry const* talent)
    {
        if (!talent)
            return "?";

        for (uint8 rank = 0; rank < MAX_TALENT_RANK; ++rank)
        {
            if (!talent->RankID[rank])
                continue;
            if (SpellInfo const* info = sSpellMgr->GetSpellInfo(talent->RankID[rank]))
            {
                LocaleConstant const locale = player->GetSession()
                    ? player->GetSession()->GetSessionDbcLocale() : DEFAULT_LOCALE;

                // EL DBC DEJA HUECOS. Un idioma sin traducir no trae cadena
                // vacia: trae puntero nulo, y construir un `std::string` con
                // el es comportamiento indefinido -- o sea, un servidor que se
                // cae al avisar de algo, que es el peor sitio posible.
                char const* name = info->SpellName[locale];
                if (!name || !*name)
                    name = info->SpellName[DEFAULT_LOCALE];
                if (name && *name)
                    return name;
            }
        }
        return "?";
    }

    // La pestana numero `tab` (1..3) de ESTA clase. El cliente las numera por
    // `tabpage`, que es el orden en que las dibuja, asi que aqui se busca por
    // eso mismo en vez de fiarse del orden del DBC.
    TalentTabEntry const* TabOf(Player* player, uint32 tab)
    {
        if (tab < 1 || tab > 3)
            return nullptr;

        uint32 const classMask = player->getClassMask();
        for (uint32 i = 0; i < sTalentTabStore.GetNumRows(); ++i)
        {
            TalentTabEntry const* entry = sTalentTabStore.LookupEntry(i);
            if (!entry || !(entry->ClassMask & classMask))
                continue;
            if (entry->petTalentMask)          // las de mascota no son de aqui
                continue;
            if (entry->tabpage == tab - 1)
                return entry;
        }
        return nullptr;
    }

    TalentEntry const* TalentAt(uint32 tabId, uint32 row, uint32 col)
    {
        for (uint32 i = 0; i < sTalentStore.GetNumRows(); ++i)
        {
            TalentEntry const* entry = sTalentStore.LookupEntry(i);
            if (entry && entry->TalentTab == tabId && entry->Row == row && entry->Col == col)
                return entry;
        }
        return nullptr;
    }

    // Lo que el jugador tiene puesto AHORA en la especializacion activa. La otra
    // no se mira ni se toca: `resetTalents` tampoco la toca, asi que meterla
    // aqui seria fotografiar algo que luego no se reconstruye.
    Build Snapshot(Player* player)
    {
        Build build;
        uint8 const specMask = player->GetActiveSpecMask();

        for (auto const& it : player->GetTalentMap())
        {
            PlayerTalent const* talent = it.second;
            if (!talent || talent->State == PLAYERSPELL_REMOVED)
                continue;
            if (!(talent->specMask & specMask))
                continue;

            TalentSpellPos const* pos = GetTalentSpellPos(it.first);
            if (!pos)
                continue;

            uint32& rank = build[pos->talent_id];
            rank = std::max<uint32>(rank, uint32(pos->rank) + 1);
        }
        return build;
    }

    // Que la build se pueda montar desde cero. Son las dos mismas preguntas que
    // hace `Player::LearnTalent` al subir un punto, hechas sobre el resultado:
    // si la build nueva pasa por aqui, volver a aprenderla fila por fila no se
    // puede atascar a la mitad.
    bool Legal(Player* player, Build const& build, std::string& code, std::string& detail)
    {
        // Lo que depende de algo: el padre tiene que seguir teniendo rango.
        for (auto const& it : build)
        {
            TalentEntry const* talent = sTalentStore.LookupEntry(it.first);
            if (!talent || !talent->DependsOn)
                continue;

            auto const parent = build.find(talent->DependsOn);
            uint32 const parentRank = (parent == build.end()) ? 0 : parent->second;
            if (parentRank < talent->DependsOnRank + 1)
            {
                code = "DEP";
                detail = TalentName(player, talent);
                return false;
            }
        }

        // Y las filas: los puntos gastados en cada arbol tienen que llegar para
        // la fila mas profunda que tenga algo. Mirar solo la mas profunda basta
        // -- si llega para esa, llega para todas las de encima.
        std::map<uint32, uint32> spent, deepest;
        for (auto const& it : build)
        {
            TalentEntry const* talent = sTalentStore.LookupEntry(it.first);
            if (!talent)
                continue;
            spent[talent->TalentTab] += it.second;
            uint32& row = deepest[talent->TalentTab];
            row = std::max(row, talent->Row);
        }

        for (auto const& it : deepest)
        {
            if (spent[it.first] < it.second * kPerRow)
            {
                code = "ROW";
                detail = std::to_string(it.second + 1);   // en base 1, como se ve
                return false;
            }
        }

        return true;
    }

    // Aprender la build entera, de arriba abajo. EL ORDEN ES LA MITAD DEL
    // TRUCO: `LearnTalent` exige los puntos de las filas de encima ya gastados,
    // asi que por filas cada paso se cumple solo. Al reves fallaria todo lo
    // profundo y el jugador se quedaria con los puntos sueltos.
    void Relearn(Player* player, Build const& build)
    {
        struct Step { uint32 tab, row, col, talent, rank; };
        std::vector<Step> steps;

        for (auto const& it : build)
        {
            TalentEntry const* talent = sTalentStore.LookupEntry(it.first);
            if (!talent)
                continue;
            steps.push_back({ talent->TalentTab, talent->Row, talent->Col, it.first, it.second });
        }

        std::sort(steps.begin(), steps.end(), [](Step const& a, Step const& b)
        {
            if (a.row != b.row) return a.row < b.row;
            if (a.tab != b.tab) return a.tab < b.tab;
            return a.col < b.col;
        });

        for (Step const& step : steps)
            player->LearnTalent(step.talent, step.rank - 1);
    }
}

bool rts::talents::Remove(Player* player, uint32_t tab, uint32_t tier, uint32_t col,
                          std::string& code, std::string& detail)
{
    code.clear();
    detail.clear();

    if (!player)
    {
        code = "BAD";
        return false;
    }

    TalentTabEntry const* tabInfo = TabOf(player, tab);
    if (!tabInfo || tier < 1 || col < 1)
    {
        code = "BAD";
        return false;
    }

    TalentEntry const* target = TalentAt(tabInfo->TalentTabID, tier - 1, col - 1);
    if (!target)
    {
        code = "BAD";
        return false;
    }

    Build build = Snapshot(player);

    auto const current = build.find(target->TalentID);
    if (current == build.end() || current->second == 0)
    {
        code = "NONE";
        return false;
    }

    uint32 const left = current->second - 1;
    if (left == 0)
        build.erase(current);
    else
        current->second = left;

    if (!Legal(player, build, code, detail))
        return false;

    // A PARTIR DE AQUI YA NO HAY VUELTA ATRAS, y por eso no hay ni una
    // comprobacion mas: todo lo que podia decir que no ya lo ha dicho.

    // LA MASCOTA SE VA CON EL RESETEO (`resetTalents` la despide) y vuelve al
    // acabar. Sin esto, cada click derecho en un talento le quitaria el lobo al
    // cazador -- que es lo que hace el juego al resetear, pero el juego no
    // resetea veinte veces seguidas.
    uint32 petNumber = 0;
    if (Pet* pet = player->GetPet())
        if (pet->getPetType() == HUNTER_PET && pet->GetCharmInfo())
            petNumber = pet->GetCharmInfo()->GetPetNumber();

    player->resetTalents(true);
    Relearn(player, build);
    player->SendTalentsInfoData(false);

    if (petNumber && !player->GetPet())
    {
        Pet* pet = new Pet(player, HUNTER_PET);
        if (!pet->LoadPetFromDB(player, 0, petNumber, false))
            delete pet;
    }

    code = "OK";
    detail = std::to_string(left);
    return true;
}
