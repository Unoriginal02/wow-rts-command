#ifndef MOD_RTS_XP_H
#define MOD_RTS_XP_H

#include <cstdint>

namespace rts
{
    // El dial de experiencia del mundo, en tantos por ciento.
    //
    // === ES UN MULTIPLICADOR, NO UN VALOR ==================================
    //
    // 100 no quiere decir "x1": quiere decir *lo que ponga la configuracion*.
    // Si `worldserver.conf` trae `Rate.XP.Kill = 5` y `Rate.XP.Quest = 2`, al
    // 110% eso pasa a 5,5 y 2,2 -- las dos suben una decima parte y la relacion
    // entre ellas no se toca.
    //
    // La alternativa -- que el dial ESCRIBA la tasa -- suena mas simple y borra
    // lo que el jugador tenga configurado la primera vez que se pulsa el boton,
    // sin decirlo y sin vuelta atras: el valor viejo ya no esta en ningun sitio
    // porque el nucleo solo guarda el actual.
    //
    // === Y SE GUARDA, PORQUE UN DIAL QUE SE OLVIDA ES UNA TRAMPA ===========
    //
    // `sWorld->setRate` solo vive en memoria: un reinicio -- y en este proyecto
    // se reinicia el mundo cada vez que se recompila el modulo -- devolveria la
    // tasa del fichero sin avisar, y lo que se ve entonces es que los bichos
    // dan menos de lo que daban ayer. El tanto por ciento se guarda en
    // `worldstates` (tabla del nucleo, escritura inmediata) y se vuelve a
    // aplicar al arrancar.
    namespace xp
    {
        // El % actual. 100 si nunca se ha tocado.
        int Percent();

        // Suma `delta` (hoy +50 o -50, y quien lo decide es el verbo `XP`),
        // lo guarda y lo aplica. Devuelve el % que ha quedado, ya recortado
        // a [50, 1000].
        int Step(int delta);

        // Anota las tasas del fichero como base. Del gancho de configuracion,
        // que es el unico momento en que las tasas del nucleo SON las del
        // fichero -- despues ya llevan nuestro multiplicador encima.
        void CaptureBaseline();

        // Aplica el % guardado sobre esa base. Del arranque (`OnStartup`, con
        // los `worldstates` ya cargados) y de cada `.reload config`.
        void Apply();
    }
}

#endif  // MOD_RTS_XP_H
