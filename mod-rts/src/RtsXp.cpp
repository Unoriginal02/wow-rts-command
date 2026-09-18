#include "RtsXp.h"

#include "World.h"
#include "WorldState.h"

namespace
{
    // NUESTRO HUECO EN `worldstates`, lejos de los del nucleo: los suyos
    // (`WORLD_STATE_CUSTOM_*`) van del 20001 al 20008 y crecen de uno en uno.
    // Un numero pegado a los suyos es el que un dia se convierte en "la
    // experiencia se reinicia sola los martes".
    constexpr uint32 kState = 20500;

    // Suelo y techo. El suelo NO es cero a proposito: al 0% no se sube de
    // nivel, y un boton que puede dejar el mundo sin experiencia sin decir
    // nada es un boton que alguien pulsa dos veces de mas y luego busca el
    // fallo en otra parte.
    //
    // Y ES UN PASO ENTERO (50), no un numero suelto: bajando desde el 100 se
    // llega justo a el, y la escalera se queda en 50, 100, 150... Un suelo de
    // 10 con pasos de 50 dejaria un ultimo escalon corto y torcido -- 60, 10 --
    // que no se parece a ninguno de los otros.
    constexpr int kMin = 50;
    constexpr int kMax = 1000;

    // LAS CINCO TASAS QUE SIGNIFICAN "LO QUE GANAS JUGANDO". Matar, misiones
    // (las normales y las de mazmorra) y explorar son las tres formas de subir
    // que hay aqui; la de la mascota va con ellas porque si no, el lobo del
    // cazador se queda atras en cuanto el dial pasa del 100% -- y eso se ve
    // como que la mascota esta rota, no como que el dial no la cubria.
    //
    // Las de campo de batalla se quedan fuera: en este servidor no hay, y
    // meterlas seria escribir tasas que nadie ha mirado nunca.
    constexpr ServerConfigs kRates[] = {
        RATE_XP_KILL,
        RATE_XP_QUEST,
        RATE_XP_QUEST_DF,
        RATE_XP_EXPLORE,
        RATE_XP_PET,
    };

    constexpr int kCount = static_cast<int>(sizeof(kRates) / sizeof(kRates[0]));

    float g_base[kCount] = {};
    bool  g_haveBase = false;
}

int rts::xp::Percent()
{
    uint64 const saved = sWorldState->getWorldState(kState);
    if (!saved)
        return 100;

    int p = static_cast<int>(saved);
    if (p < kMin) p = kMin;
    if (p > kMax) p = kMax;
    return p;
}

void rts::xp::CaptureBaseline()
{
    for (int i = 0; i < kCount; ++i)
        g_base[i] = sWorld->getRate(kRates[i]);

    g_haveBase = true;
}

void rts::xp::Apply()
{
    // Sin base no se escribe NADA. Pasa si alguien llama a esto antes de que
    // el mundo haya leido su configuracion, y multiplicar por una base de
    // ceros deja el servidor sin experiencia -- un estado del que no se sale
    // mirando el fichero, porque el fichero esta bien.
    if (!g_haveBase)
        return;

    float const k = static_cast<float>(Percent()) / 100.0f;
    for (int i = 0; i < kCount; ++i)
        sWorld->setRate(kRates[i], g_base[i] * k);
}

int rts::xp::Step(int delta)
{
    int p = Percent() + delta;
    if (p < kMin) p = kMin;
    if (p > kMax) p = kMax;

    sWorldState->setWorldState(kState, static_cast<uint64>(p));
    Apply();
    return p;
}
