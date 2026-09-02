# -*- coding: utf-8 -*-
"""
ground_ray.py -- el corte del rayo del cursor contra el suelo, fuera del juego.

Reproduce las DOS cuentas que compiten y ensena por que una falla:

  * PLANO   -- lo unico que Lua puede hacer sin mapa: cortar el rayo contra un
               plano horizontal a una altura Z conocida. Es lo que habia.
  * MARCHA  -- lo que hace ahora mod-rts (rts::orders::GroundRay): andar el rayo
               un paso cada vez contra la altura del terreno y afinar el corte
               con una biseccion.

El caso que reporto el jugador -- "pincho en la cara de un monticulo y el punto
acaba DETRAS de el y bajo tierra" -- sale aqui con numeros, y no hace falta el
juego para verlo.

    python sim/ground_ray.py
"""

import math

STEP = 1.0        # kRayStep en RtsOrders.cpp
BISECT = 14       # kRayBisect
MAXDIST = 500.0


def terreno(x):
    """Perfil del suelo: llano con un monticulo de 20 yardas de alto en x=100."""
    if 70.0 <= x <= 130.0:
        return 20.0 * math.cos((x - 100.0) / 30.0 * (math.pi / 2.0)) ** 2
    return 0.0


def marcha(ox, oz, dx, dz):
    """El corte de verdad: primer sitio donde el rayo deja de estar por encima."""
    prev = 0.0
    for i in range(1, int(MAXDIST / STEP) + 1):
        t = i * STEP
        px, pz = ox + dx * t, oz + dz * t
        if pz <= terreno(px):
            lo, hi = prev, t
            for _ in range(BISECT):
                m = (lo + hi) / 2.0
                if oz + dz * m <= terreno(ox + dx * m):
                    hi = m
                else:
                    lo = m
            return ox + dx * hi, terreno(ox + dx * hi)
        prev = t
    return None


def plano(ox, oz, dx, dz, planez):
    """Lo de antes: cortar contra un plano horizontal a `planez`."""
    if abs(dz) < 1e-6:
        return None
    k = (planez - oz) / dz
    if k <= 0:
        return None
    return ox + dx * k, oz + dz * k


def caso(nombre, ox, oz, mira_x, planez):
    """La camara en (ox, oz) apuntando al punto del suelo (mira_x)."""
    dx, dz = mira_x - ox, terreno(mira_x) - oz
    n = math.hypot(dx, dz)
    dx, dz = dx / n, dz / n

    m = marcha(ox, oz, dx, dz)
    p = plano(ox, oz, dx, dz, planez)

    print("  %-28s" % nombre, end="")
    if m:
        print("marcha x=%7.2f z=%6.2f" % m, end="   ")
    else:
        print("marcha  --sin corte--", end="   ")
    if p:
        bajo = p[1] - terreno(p[0])
        print("plano x=%7.2f z=%6.2f  (%+.2f del suelo, error %.1f yardas)"
              % (p[0], p[1], bajo, abs(p[0] - m[0]) if m else 0.0))
    else:
        print("plano  --sin corte--")


print(__doc__.strip().splitlines()[0])
print()
print("Camara a 40 yardas de alto en x=0, plano anclado a z=0 (el suelo llano")
print("bajo el cursor, que es lo que devolvia el rayo del DLL):")
print()
caso("cara VISIBLE del monticulo", 0.0, 40.0, 80.0, 0.0)
caso("cima del monticulo", 0.0, 40.0, 100.0, 0.0)
caso("suelo llano de delante", 0.0, 40.0, 50.0, 0.0)
caso("suelo llano de detras", 0.0, 40.0, 160.0, 0.0)
print()
print("La fila de arriba es el fallo reportado: pinchando la cara visible a 80,")
print("el plano contesta un punto MAS ALLA del monticulo y por debajo de su")
print("ladera -- justo lo que se ve al acercarse. La marcha contesta 80.")
