#include "RtsPets.h"

#include "Config.h"
#include "Pet.h"
#include "Player.h"
#include "SharedDefines.h"
#include "WorldSessionMgr.h"

namespace
{
    // Un segundo. La caida son 670 cada 7,5 s, o sea que lo peor que puede
    // pasar entre dos barridos es que la mascota pase un instante 670 por
    // debajo del maximo -- de 1.050.000, y con la barra partida en tres
    // tramos de 333.000. No se ve. Bajarlo mas seria pagar por nada.
    constexpr uint32_t kTickMs = 1000;

    uint32_t g_acc = 0;
}

void rts::pets::Update(uint32_t diff)
{
    g_acc += diff;
    if (g_acc < kTickMs)
        return;
    g_acc = 0;

    // Se pregunta cada vuelta y no al cargar: asi `.reload config` lo apaga y
    // lo enciende sin reiniciar el mundo, que es como se comportan las demas
    // opciones de este modulo.
    if (!sConfigMgr->GetOption<bool>("RTS.Pet.Happy", true))
        return;

    // EL RECORRIDO ES EL DEL NUCLEO y no un bucle propio sobre
    // `ObjectAccessor::GetPlayers()`: ese mapa se toca tambien desde los hilos
    // de actualizacion de mapa -- un jugador entra al mundo alli -- asi que
    // leerlo sin el cerrojo compartido es una carrera que no se ve fallar hasta
    // el dia que falla. `DoForAllOnlinePlayers` coge el cerrojo y ademas se
    // salta a quien todavia no esta en el mundo.
    sWorldSessionMgr->DoForAllOnlinePlayers([](Player* player)
    {
        Pet* pet = player->GetPet();
        if (!pet || pet->getPetType() != HUNTER_PET)
            return;

        // EL MAXIMO SE PREGUNTA, NO SE ESCRIBE AQUI. Lo pone el nucleo al
        // cargar la mascota (`GetCreatePowers`, hoy 1.050.000), y un numero
        // copiado en este fichero seria uno que se queda viejo en silencio el
        // dia que cambie -- con el sintoma de una barra que casi llega.
        pet->SetPower(POWER_HAPPINESS, pet->GetMaxPower(POWER_HAPPINESS));
    });
}
