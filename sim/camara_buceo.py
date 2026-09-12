# -*- coding: utf-8 -*-
"""
camara_buceo.py -- el modelo de altura de la camara libre, fuera del juego.

`ground_filter.py` ya prueba la parte de seguir una ladera: escalones, cuestas,
carteles. Lo que NO sabia probar es lo que costo el 2026-09-12, porque no es una
cuenta sobre UNA senal de suelo sino sobre un MUNDO CON CAPAS -- el tejado de la
cueva, el suelo de las aranas debajo, el terreno fuera -- y sobre quien manda
cuando el jugador tiene una tecla pulsada.

Las cuatro averias de aquel dia, cada una con su prueba y su interruptor para
volver al codigo roto:

  la mentira    el rayo contesta "si" sin escribir donde  -> criba de segmento
  la franja     el rayo arrancaba en z+5: cinco yardas    -> arrancar en z
                ciegas al cruzar una superficie hacia abajo
  la escalera   dentro de la roca, el suelo duro sube y   -> presupuesto
                el rayo del frame siguiente arranca mas
                alto: se construye sola
  el veto       las teclas movian el OFFSET, que es una   -> mover la camara
                altura SOBRE algo, asi que el suelo
                discutia con el jugador

    python sim/camara_buceo.py
    python sim/camara_buceo.py --sin-criba      (vuelve el plop)
    python sim/camara_buceo.py --rayo-arriba    (vuelve la franja ciega)
    python sim/camara_buceo.py --offset-teclas  (vuelve el veto)
    python sim/camara_buceo.py --rayo-arriba --techo-es-suelo   (la escalera)
"""

import math
import sys

from ground_filter import follow

# --- los ajustes, iguales que en `D` de FreeCam.lua -----------------------
CLEAR = 2.0
PUSH = 40.0
LIFT = 14.0      # yd/s de las teclas
SMOOTH_Z = 8.0
MAXH = 300.0
MINH = 4.0       # el suelo del offset del modelo VIEJO
RAY_UP = 5.0
RAY_DOWN = 1000.0

DT = 1.0 / 60.0

# Interruptores para volver al codigo de antes. Una prueba que pasa con el
# codigo roto no es una prueba.
CRIBA = True             # False = se acepta el choque que el rayo no escribio
ARRANQUE_ARRIBA = False  # True = el rayo sale de z + RAY_UP, como el DLL viejo
TECLAS_OFFSET = False    # True = ESPACIO y C mueven el offset, con suelo `MINH`
TECHO_ES_SUELO = False   # True = una superficie POR ENCIMA de la camara cuenta
                         # como suelo, que es como estaba antes: ni presupuesto
                         # ni guarda en el anclaje


# --- el mundo, que es una lista de superficies ---------------------------

class Mundo(object):
    """Superficies horizontales, y si el rayo MIENTE en este sitio.

    `miente` reproduce lo medido en juego: donde el ADT esta agujereado a
    proposito -- dentro de una cueva -- `CGWorldFrame::Intersect` devolvia cierto
    sin escribir el punto, asi que el llamante se quedaba con su `out` recien
    inicializado a cero y publicaba un suelo de 0.0."""

    def __init__(self, capas, miente=False, solidas=None):
        self.capas = sorted(capas, reverse=True)
        self.miente = miente
        # Las capas que ve el rayo SOLIDO y no el de terreno: el tubo de la
        # cueva es geometria (WMO), no mapa de alturas.
        self.solidas = sorted(solidas if solidas is not None else capas,
                              reverse=True)

    def _tirar(self, capas, z, miente):
        arranque = z + RAY_UP if ARRANQUE_ARRIBA else z
        fin = z - RAY_DOWN
        crudo = None
        if miente:
            crudo = 0.0
        else:
            for s in capas:
                if s <= arranque:
                    crudo = s
                    break
        if crudo is None:
            return None
        # LA CRIBA: un choque tiene que caer DENTRO del segmento disparado. Es
        # la misma cuenta que `Cast` hace ahora en World.cpp, y la misma que
        # `RayHit` repite en el addon por si el DLL es viejo.
        if CRIBA and not (fin - 0.5 <= crudo <= arranque + 0.5):
            return None
        return crudo

    def rayo(self, z):
        """`GroundUnderCamera` con `floor = 1`: terreno, y si no, solido.

        Los DOS rayos hacen falta para que la criba signifique algo. El de
        terreno es el que miente dentro de la cueva; el solido devuelve el suelo
        de las aranas. Con la criba, la mentira se descarta y se cae al solido,
        que es exactamente lo que se ve en juego: `terreno descartado (0.0)`,
        `en uso: solido`. Sin ella, la camara se cree el cero."""
        land = self._tirar(self.capas, z, self.miente)
        if land is not None:
            return land
        return self._tirar(self.solidas, z, False)


# --- la camara, portada de FreeCam.lua -----------------------------------

class Camara(object):
    def __init__(self, z, offset):
        self.z = z
        self.offset = offset
        self.gz = None
        self.pend = 0.0
        self.buried = 0.0
        self.free = False


def tick(cam, mundo, tecla, dt=DT):
    """Un frame del controlador. `tecla` es +1 (ESPACIO), -1 (C) o 0."""
    ground = mundo.rayo(cam.z)

    # EL EMPUJE SE CANSA: presupuesto `offset + clear` mientras el suelo este
    # por encima, repuesto en cuanto vuelve a estar debajo.
    if ground is not None and ground > cam.z:
        cam.buried += PUSH * dt
        if cam.buried > cam.offset + CLEAR and not TECHO_ES_SUELO:
            ground = None
    else:
        cam.buried = 0.0

    if tecla != 0:
        if TECLAS_OFFSET:
            # EL MODELO VIEJO: la tecla mueve el offset y se para en `MINH`.
            if ground is not None:
                cam.offset = min(MAXH, max(MINH, cam.offset + tecla * LIFT * dt))
            else:
                cam.z += tecla * LIFT * dt
        else:
            cam.z += tecla * LIFT * dt
            cam.free = True
            cam.gz, cam.pend, cam.buried = None, 0.0, 0.0
            ground = None
    else:
        cam.free = False

    # EL ANCLAJE, y el vacio abisal con el.
    if ground is not None and cam.gz is None and not TECLAS_OFFSET:
        h = cam.z - ground
        if (h < 0.0 and not TECHO_ES_SUELO) or h > MAXH:
            ground = None
        else:
            cam.offset = h

    if ground is not None:
        cam.gz, cam.pend = follow((cam.gz, cam.pend), ground, dt, cam.offset)
        target = cam.gz + cam.offset
    else:
        target = cam.z
        cam.gz, cam.pend = None, 0.0

    cam.z += (target - cam.z) * (1.0 - math.exp(-SMOOTH_Z * dt))

    if ground is not None:
        viejo = TECLAS_OFFSET or TECHO_ES_SUELO
        want = ground + (CLEAR if viejo else min(CLEAR, cam.offset))
        if cam.z < want:
            lim = PUSH * dt
            cam.z = cam.z + lim if want - cam.z > lim else want

    return ground


def correr(cam, mundo, guion, dt=DT):
    """`guion` es una lista de (segundos, tecla). Devuelve la z por frame."""
    zs = [cam.z]
    for segundos, tecla in guion:
        for _ in range(int(segundos / dt)):
            tick(cam, mundo, tecla, dt)
            zs.append(cam.z)
    return zs


def salto_max(zs):
    """El mayor movimiento en UN frame. Es la unidad del `plop`."""
    return max(abs(b - a) for a, b in zip(zs, zs[1:]))


# --- los mundos que cuestan una ronda de pruebas cada uno ----------------

# La cueva medida en juego el 2026-09-12: el tubo tiene tejado y suelo, y el
# rayo de terreno MIENTE dentro porque el ADT esta agujereado.
TEJADO, SUELO_ARANAS = 1345.0, 1320.0
CUEVA = Mundo([TEJADO, SUELO_ARANAS])
CUEVA_MENTIROSA = Mundo([TEJADO, SUELO_ARANAS], miente=True)

# La roca de la montana, que es lo que el mundo de capas no sabia decir: no una
# superficie sino un MEDIO CONTINUO. Es el mundo donde la escalera del rayo que
# arranca en z+5 se puede construir, porque siempre hay otra cara ahi arriba.
MONTANA = Mundo([SUELO_ARANAS] + [1345.0 + i for i in range(0, 56)])

# Un edificio de tres plantas.
PISOS = Mundo([1360.0, 1350.0, 1340.0])

# El borde del mundo: terreno, y debajo nada hasta 400 yardas mas abajo.
ABISMO = Mundo([1300.0, 900.0])


def informe():
    print("ajustes: clear=%.0f push=%.0f lift=%.0f smoothZ=%.0f maxH=%.0f RAY_UP=%.0f"
          % (CLEAR, PUSH, LIFT, SMOOTH_Z, MAXH, RAY_UP))
    print("         criba=%s  arranque=%s  teclas=%s"
          % ("SI" if CRIBA else "NO",
             "z+5" if ARRANQUE_ARRIBA else "z",
             "offset" if TECLAS_OFFSET else "camara"))
    print()
    fallos = []

    # 1. LA MENTIRA. Dentro de la cueva el rayo de terreno contesta 0.0 sin
    #    haber chocado. Con la criba se descarta y se cae al solido -- el suelo
    #    de las aranas -- que es lo que se ve en juego. Sin ella, la camara se
    #    cree el cero: o se va al fondo del mundo, o se queda sin suelo.
    cam = Camara(SUELO_ARANAS + 8.0, 8.0)
    zs = correr(cam, CUEVA_MENTIROSA, [(2.0, 0)])
    s = salto_max(zs)
    ok = cam.gz is not None and abs(cam.gz - SUELO_ARANAS) <= 0.5 and s <= 1.0
    print("  el rayo miente (terreno 0.0)  suelo en uso %s, salto maximo %.2f yd/frame   %s"
          % ("%.1f" % cam.gz if cam.gz is not None else "NINGUNO", s,
             "ok" if ok else "MAL"))
    print("                                (el solido, %.0f, y sin saltos)" % SUELO_ARANAS)
    if not ok:
        fallos.append("el choque que el rayo no escribio le quita el suelo a la camara")

    # 2. BUCEAR. Aguantar C desde encima del tubo tiene que meterla dentro.
    cam = Camara(TEJADO + 10.0, 10.0)
    correr(cam, CUEVA, [(1.2, -1)])
    dentro = SUELO_ARANAS < cam.z < TEJADO
    print("  bucear 1.2 s con C            acaba en %.1f   %s"
          % (cam.z, "ok" if dentro else "MAL"))
    print("                                (entre el suelo de las aranas %.0f y el tejado %.0f)"
          % (SUELO_ARANAS, TEJADO))
    if not dentro:
        fallos.append("no se puede atravesar el tejado de la cueva")

    # 3. SOLTAR NO DA SALTO, y engancha al suelo de abajo.
    #    Y se suelta JUSTO debajo del tejado -- dos yardas -- porque ahi es
    #    donde la franja ciega se nota: el rayo que arranca en z+5 sigue viendo
    #    el tejado que se acaba de cruzar y no el suelo de abajo.
    cam = Camara(TEJADO + 10.0, 10.0)
    zs = correr(cam, CUEVA, [(0.9, -1), (1.5, 0)])
    n = int(0.9 / DT)
    s = salto_max(zs[n:])
    anclado = cam.gz is not None and abs(cam.gz - SUELO_ARANAS) <= 0.5
    ok = s <= 0.5 and anclado and abs(cam.offset - (cam.z - SUELO_ARANAS)) <= 0.5
    print("  soltar 2 yd bajo el tejado    suelo %s, salto %.2f yd/frame, offset %.1f   %s"
          % ("%.1f" % cam.gz if cam.gz is not None else "NINGUNO", s, cam.offset,
             "ok" if ok else "MAL"))
    print("                                (se ancla al %.0f, sin salto, y el offset lo mide)"
          % SUELO_ARANAS)
    if not ok:
        fallos.append("al soltar bajo una superficie no se ve la de abajo: franja ciega")

    # 4. ATRAVESAR PISOS SIN PARARSE EN NINGUNO.
    cam = Camara(1370.0, 10.0)
    correr(cam, PISOS, [(3.0, -1)])
    ok = cam.z < 1340.0
    print("  tres plantas seguidas con C   acaba en %.1f   %s"
          % (cam.z, "ok" if ok else "MAL"))
    print("                                (< 1340: las ha pasado las tres)")
    if not ok:
        fallos.append("cada planta para la bajada: el offset discute con la tecla")

    # 5. EL VACIO ABISAL. Debajo hay algo, pero a 400 yardas: no es un suelo.
    cam = Camara(1305.0, 5.0)
    correr(cam, ABISMO, [(1.0, -1)])
    z_soltando = cam.z
    correr(cam, ABISMO, [(1.0, 0)])
    flota = abs(cam.z - z_soltando) <= 0.5 and cam.z < 1300.0
    print("  vacio abisal (suelo a 400)    se queda en %.1f, solto en %.1f   %s"
          % (cam.z, z_soltando, "ok" if flota else "MAL"))
    print("                                (no se engancha a algo a mas de maxH=%.0f)" % MAXH)
    if not flota:
        fallos.append("la camara se engancha al fondo del mundo y cae")

    # 6. Y DEL VACIO SE SALE CON ESPACIO. Sin esto no hay ninguna tecla que
    #    saque, que es como se llega a "y ahora como salgo de aqui".
    antes = cam.z
    correr(cam, ABISMO, [(1.0, +1)])
    sube = cam.z > antes + 10.0
    print("  salir del vacio con ESPACIO   de %.1f a %.1f   %s"
          % (antes, cam.z, "ok" if sube else "MAL"))
    print("                                (sin suelo, las teclas mueven la camara)")
    if not sube:
        fallos.append("flotando en el vacio no hay ninguna tecla que suba")

    # 7. LA ESCALERA QUE SE CONSTRUYE SOLA. Metida en la roca y sin tocar nada,
    #    la camara no puede salir disparada hacia arriba.
    # Dos yardas por DEBAJO del tejado, que es la unica postura en la que el
    # rayo viejo -- arrancando en z+5 -- ve roca por encima y arranca a subir.
    cam = Camara(TEJADO - 2.0, 2.0)
    zs = correr(cam, MONTANA, [(3.0, 0)])
    subida = max(zs) - zs[0]
    ok = subida <= 10.0
    print("  quieta dentro de la roca 3 s  sube %.1f yd   %s" % (subida, "ok" if ok else "MAL"))
    print("                                (<= 10.00: el empuje tiene presupuesto)")
    if not ok:
        fallos.append("la camara se expulsa sola de donde el jugador la ha puesto")

    print()
    if fallos:
        for f in fallos:
            print("  MAL: " + f)
        return 1
    print("  las siete pruebas pasan")
    return 0


if __name__ == "__main__":
    if "--sin-criba" in sys.argv:
        CRIBA = False
    if "--rayo-arriba" in sys.argv:
        ARRANQUE_ARRIBA = True
    if "--offset-teclas" in sys.argv:
        TECLAS_OFFSET = True
    if "--techo-es-suelo" in sys.argv:
        TECHO_ES_SUELO = True
    sys.exit(informe())
