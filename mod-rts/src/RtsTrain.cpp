#include "RtsTrain.h"

#include "ObjectMgr.h"
#include "Player.h"
#include "Trainer.h"

#include <stdexcept>
#include <vector>

namespace
{
    // LOS MAESTROS DE ARMAS, POR ENTRADA DE CRIATURA.
    //
    // Las habilidades de arma no salen en `GetClassTrainers`: ese indice solo
    // recoge los entrenadores de `trainer.Type = 0` (clase), y los maestros de
    // armas son `Type = 2` con `Requirement = 0` -- la misma casilla que los
    // ochenta entrenadores de profesion. O sea que no hay forma de distinguirlos
    // por tipo, y el nucleo no ofrece manera de recorrer la tabla entera: lo
    // unico publico es `GetTrainer(entrada de criatura)`.
    //
    // Asi que van los once por su entrada. Salen de esta consulta, y se puede
    // rehacer si algun dia el mundo cambia:
    //
    //     SELECT cdt.CreatureId, ct.name
    //     FROM creature_default_trainer cdt
    //     JOIN trainer t          ON t.Id = cdt.TrainerId
    //     JOIN creature_template ct ON ct.entry = cdt.CreatureId
    //     WHERE t.Type = 2 AND t.Requirement = 0
    //       AND ct.subname = 'Weapon Master';
    //
    // Entre los once cubren los CATORCE hechizos de arma del juego (comprobado
    // el 2026-09-13: son 196-202, 227, 264, 266, 1180, 2567, 5011 y 15590), asi
    // que la union vale para cualquier clase y raza. Quien filtra despues es
    // `CanTeachSpell` con `IsSpellFitByClassAndRace`, no esta lista: por eso da
    // igual a cual de los once se le pregunte.
    constexpr uint32 kWeaponMasters[] =
    {
        2704,   // Hanashi
        11865,  // Buliwyf Stonehand
        11866,  // Ilyenia Moonfire
        11867,  // Woo Ping
        11868,  // Sayoc
        11869,  // Ansekhwa
        11870,  // Archibald
        13084,  // Bixi Wobblebonk
        16621,  // Ileda
        16773,  // Handiir
        17005,  // Duelist Larenis
    };

    // EL TOPE DE VUELTAS, Y NO ES DECORACION.
    //
    // El bucle de abajo repite mientras aprenda algo, porque un rango solo se
    // deja aprender cuando ya tienes el anterior: la vuelta N desbloquea la N+1.
    // La cadena mas larga del juego ronda los dieciseis rangos, asi que treinta
    // y dos sobra de largo.
    //
    // Lo que corta de verdad es otra cosa: si algun dia un hechizo pasara
    // `CanTeachSpell` y despues NO quedara aprendido -- un dato del mundo mal
    // montado, un parche de terceros -- esto seria un bucle infinito EN EL HILO
    // DEL MUNDO, o sea el servidor colgado sin traza. El comando `.learn` del
    // nucleo tiene el mismo bucle sin tope y se lo puede permitir porque lo
    // escribe un humano de uno en uno; esto corre solo, en cada subida de nivel.
    constexpr int kMaxPasses = 32;

    int TeachFrom(Player* who, Trainer::Trainer const* trainer)
    {
        if (!trainer || !trainer->IsTrainerValidForPlayer(who))
            return 0;

        int learned = 0;
        for (Trainer::Spell const& spell : trainer->GetSpells())
        {
            if (!trainer->CanTeachSpell(who, &spell))
                continue;

            // La misma bifurcacion que `Trainer::TeachSpell` (`Trainer.cpp:108`)
            // y por el mismo motivo: los hechizos que ENSENAN otro hay que
            // lanzarlos para que el efecto corra, y los demas se aprenden
            // directos. Lo que no se copia de ahi es el cobro.
            //
            // LAS HABILIDADES DE ARMA CAEN POR LA RAMA DE `learnSpell`, y hay
            // que saber por que funcionan: no ensenan nada, aplican. En
            // `Spell.dbc` (comprobado el 2026-09-13) son efecto 60,
            // `SPELL_EFFECT_PROFICIENCY`, y son PASIVAS -- 196, 200, 201, 264,
            // 1180, 2567, 5011 y 15590 todas. `Player::addSpell` lanza los
            // pasivos al aprenderlos (`Player.cpp:3320`), y ahi es donde
            // `EffectProficiency` pone la competencia y la habilidad de verdad.
            // O sea que aprenderlas basta; no hay que tocar `SetSkill` a mano,
            // que es lo que hace la version de playerbots.
            if (spell.IsCastable())
                who->CastSpell(who, spell.SpellId, true);
            else
                who->learnSpell(spell.SpellId, false);

            ++learned;
        }

        return learned;
    }
}

int rts::train::Learn(Player* who)
{
    if (!who || !who->IsInWorld())
        return 0;

    // `GetClassTrainers` es un `at()` sobre un mapa: una clase sin ninguna fila
    // en `trainer` no devuelve lista vacia, LANZA. Hoy las diez clases tienen
    // entrenador, pero una base de datos a medio importar no es un caso
    // imposible, y una excepcion desde el gancho de subir de nivel se lleva por
    // delante al jugador que acaba de subir.
    std::vector<Trainer::Trainer const*> const* classTrainers = nullptr;
    try
    {
        classTrainers = &sObjectMgr->GetClassTrainers(who->getClass());
    }
    catch (std::out_of_range const&)
    {
        classTrainers = nullptr;
    }

    int learned = 0;

    for (int pass = 0; pass < kMaxPasses; ++pass)
    {
        int const before = learned;

        if (classTrainers)
            for (Trainer::Trainer const* trainer : *classTrainers)
                learned += TeachFrom(who, trainer);

        for (uint32 entry : kWeaponMasters)
            learned += TeachFrom(who, sObjectMgr->GetTrainer(entry));

        if (learned == before)
            break;
    }

    return learned;
}
