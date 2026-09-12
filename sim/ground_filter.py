"""Simula el filtro de altura de FreeCam.lua fuera del juego.

Reimplementa SOLO la aritmetica de la altura -- el filtro de velocidad limitada
sobre la senal de suelo, el suavizado exponencial detras y el suelo duro -- con
las mismas formulas que el Lua, y le pasa los cuatro perfiles de suelo que en
juego cuestan una ronda de pruebas cada uno:

    el cartel   un escalon de 6 yd que dura 0.15 s      -> NO debe levantar
    la cuesta   45 grados sostenidos a toda velocidad   -> SI debe seguirse
    el tejado   15 yd que no se acaban nunca            -> se sube esperando
    la repisa   un escalon de 20 yd, mas bajo que el vuelo -> se sube sin tiron
    el borde    un acantilado de 60, mas alto que el vuelo  -> sube, pero se ve
    la mezcla   una repisa y detras una cuesta larga        -> el retraso no crece
    la boca     +80 de golpe, con dos offsets distintos     -> NUNCA un salto

La pregunta que contesta es la unica que importa aqui: SI LAS DOS COSAS CABEN A
LA VEZ. Un filtro que ignore el cartel puede perfectamente dejar la camara
enterrada en la cuesta, y eso en juego se ve como "ahora la camara se hunde",
que no se parece en nada a lo que se toco.
"""

import math

# --- los ajustes, iguales que en `D` de FreeCam.lua -----------------------
CLIMB = 60.0     # yd/s con diferencia minima
SOFT = 2.5       # yardas, el codo
SLOW = 6.0       # yd/s, el suelo de la velocidad
SMOOTH_Z = 8.0   # k del suavizado exponencial de detras
CLEAR = 2.0      # margen duro
OFFSET = 30.0    # altura sobre el suelo
PUSH = 40.0      # yd/s, lo mas deprisa que el suelo duro puede empujar
SPEED = 30.0     # yd/s en el plano, para convertir cuestas en yd/s verticales

DT = 1.0 / 60.0

# Interruptores para volver al codigo de ANTES y comprobar que las pruebas
# tienen dientes. Una prueba que pasa con el codigo roto no es una prueba.
RATE_FILTER = True    # False = el suelo crudo va directo al objetivo (lo de antes)
PENDIENTE = True      # False = el freno se decide con lo que QUEDA del escalon en
                      # vez de con su tamano; asi estaba escrito primero y el
                      # final de cada subida daba un latigazo
LAG_CAP = True        # False = sin tope de retraso: un escalon seguido de cuesta
                      # deja la camara enterrada hasta que el suelo duro la saca
PUSH_LIMIT = True     # False = el suelo duro y el tope de retraso escriben de
                      # golpe, como estaban hasta el 2026-09-12. Es EL fallo de
                      # las cuevas: un salto de 80 yardas en un frame


def follow(state, ground, dt, offset=None):
    """El suelo filtrado persigue al medido con la velocidad limitada.

    `state` es (gz, pend): el suelo filtrado y el mayor desnivel visto desde la
    ultima vez que se puso al dia. Devuelve el estado nuevo."""
    if offset is None:
        offset = OFFSET
    gz, pend = state
    if not RATE_FILTER or gz is None:
        return (ground, 0.0)
    d = ground - gz
    ad = abs(d)
    pend = max(pend, ad)
    q = (pend if PENDIENTE else ad) / SOFT
    v = max(SLOW, CLIMB / (1.0 + q * q))
    step = v * dt
    if ad <= step:
        return (ground, 0.0)
    gz = gz + step if d > 0 else gz - step
    if LAG_CAP and d > 0:
        cap = max(1.0, offset - CLEAR)
        want = ground - cap
        if want > gz:
            if PUSH_LIMIT:
                lim = PUSH * dt
                gz = gz + lim if want - gz > lim else want
            else:
                gz = want
    return (gz, pend)


def run(profile, seconds, dt=DT, offset=None):
    """Devuelve (t, suelo crudo, suelo filtrado, z de camara) por frame.

    `offset` se puede pasar porque EL VALOR IMPORTA y no es cosmetico: el tope
    de retraso es `offset - clear`, asi que con el offset de fabrica (30) son 28
    yardas y casi nada lo dispara, y con el offset bajado a mano -- 6.4 medido
    en juego el 2026-09-12 -- son 4.4 y lo dispara TODO. Este simulador corrio
    siempre a 30 y por eso aprobo el codigo que teletransportaba la camara."""
    if offset is None:
        offset = OFFSET
    g0 = profile(0.0)
    st = (g0, 0.0)
    z = g0 + offset
    out = []
    t = 0.0
    n = int(seconds / dt)
    for _ in range(n):
        ground = profile(t)
        st = follow(st, ground, dt, offset)
        gz = st[0]
        target = gz + offset
        z += (target - z) * (1.0 - math.exp(-SMOOTH_Z * dt))
        if z < ground + CLEAR:
            want = ground + CLEAR
            if PUSH_LIMIT:
                lim = PUSH * dt
                z = z + lim if want - z > lim else want
            else:
                z = want
        out.append((t, ground, gz, z))
        t += dt
    return out


# --- los cuatro perfiles -------------------------------------------------

def cartel(t):
    """Un poste de 6 yd que se cruza en 0.15 s, a 1 s de empezar."""
    return 6.0 if 1.0 <= t < 1.15 else 0.0


def cuesta(t):
    """45 grados a toda velocidad: el suelo sube a SPEED yd/s desde 1 s."""
    return 0.0 if t < 1.0 else SPEED * (t - 1.0)


def tejado(t):
    """15 yd que empiezan a 1 s y no se acaban: te has parado sobre la casa."""
    return 0.0 if t < 1.0 else 15.0


def escalon(t):
    """20 yd de golpe a 1 s: una repisa, mas baja que la altura de vuelo."""
    return 0.0 if t < 1.0 else 20.0


def acantilado(t):
    """60 yd de golpe a 1 s: MAS ALTO que la altura de vuelo (30)."""
    return 0.0 if t < 1.0 else 60.0


def repisa_y_cuesta(t):
    """Una repisa de 6 yd y, medio segundo despues, una cuesta larga.

    Es el caso que el freno por escalon se come solo: `pend` se queda en 6, la
    velocidad de seguimiento en ~9 yd/s, y la cuesta sube a 30 -- o sea que el
    filtro no puede alcanzarla y se queda cada vez mas atras. Sin el tope de
    retraso el desnivel crece sin final y la camara acaba rescatada por el suelo
    duro, pegada al terreno, durante todo el rato que dure la cuesta y bastante
    despues."""
    if t < 1.0:
        return 0.0
    if t < 1.5:
        return 6.0
    return 6.0 + SPEED * (t - 1.5)


def boca(t):
    """LA BOCA DE LA CUEVA: el suelo medido salta 80 yd de golpe y se queda.

    No es un acantilado que se sube: es que la XY de la camara ha cruzado bajo
    la silueta de la montana y el rayo pasa a medir OTRA superficie. Desde la
    aritmetica los dos son el mismo escalon -- por eso este perfil vale para los
    dos -- y lo unico que se le puede exigir es que la camara no se mueva mas
    deprisa de lo que el jugador puede ver."""
    return 0.0 if t < 1.0 else 80.0


def retraso_max(rows, t0=1.0):
    """El mayor desnivel entre el suelo real y el filtrado, hacia arriba."""
    return max((ground - gz) for t, ground, gz, _ in rows if t >= t0)


def levantada(rows, hasta=None):
    """Cuanto ha subido la camara respecto a donde empezo."""
    base = rows[0][3]
    peak = 0.0
    for t, _, _, z in rows:
        if hasta is not None and t > hasta:
            break
        peak = max(peak, z - base)
    return peak


def vmax(rows, dt=DT):
    """La velocidad vertical mas alta de la CAMARA, en yd/s.

    Es la medida honesta de "me ha catapultado": el jugador no siente yardas,
    siente el tiron. Y sirve para los cuatro perfiles por igual, que es mas de
    lo que se puede decir de un umbral de altura inventado para cada uno -- el
    primero que escribi daba MAL en el tejado por pedirle a un escalon de 15
    yardas que en un segundo hubiera subido menos que su propia velocidad
    minima de seguimiento. El numero estaba mal, no el codigo."""
    v = 0.0
    for i in range(1, len(rows)):
        v = max(v, (rows[i][3] - rows[i - 1][3]) / dt)
    return v


def tarda_en_salir(rows, t0=1.0):
    """Segundos que la camara pasa por DEBAJO del suelo real a partir de t0.

    Sustituye a exigir `separacion >= CLEAR` en los perfiles de escalon grande,
    y el cambio no es cosmetico: con el suelo duro limitado la camara SI entra
    en la roca un momento, y eso es la decision, no el fallo. Es lo que pidio el
    jugador con sus palabras -- *"que no siga al suelo y simplemente clipee"* --
    y ademas la camara ya atraviesa todo (`noclip`), asi que un segundo de roca
    es barato y un salto de 80 yardas no.

    Lo que si hay que exigir es que SALGA, y en cuanto: una camara que se queda
    dentro es el fallo de siempre con otro nombre."""
    dentro = 0.0
    for t, ground, _, z in rows:
        if t >= t0 and z < ground + CLEAR - 0.01:
            dentro += DT
    return dentro


def separacion_min(rows, t0=1.0):
    """La separacion mas pequena entre la camara y el suelo REAL despues de t0.

    Es la mitad que se olvida: un filtro lento de mas deja la camara dentro de
    la loma, y eso no aparece mirando solo si el cartel levanta o no."""
    m = 1e9
    for t, ground, _, z in rows:
        if t >= t0:
            m = min(m, z - ground)
    return m


# El tope de tiron. `lift` son 14 yd/s subiendo a mano con ESPACIO, asi que
# cualquier cosa por encima de eso es la camara moviendose mas deprisa de lo que
# el jugador puede pedirle: eso es exactamente lo que se siente como un salto.
V_TIRON = 14.0

# Y EL TOPE DEL EMPUJE, que es otro numero porque es otra pregunta. `V_TIRON`
# mide "esto no deberia haberse notado"; esto mide "esto tenia que subir, pero a
# una velocidad que se pueda ver". Sale de `PUSH` con un margen para el
# suavizado exponencial, que empuja un poco por su cuenta en el mismo frame.
V_EMPUJE = PUSH * 1.25


def informe():
    print("ajustes: climb=%.0f soft=%.1f slow=%.0f smoothZ=%.0f offset=%.0f clear=%.0f"
          % (CLIMB, SOFT, SLOW, SMOOTH_Z, OFFSET, CLEAR))
    print("         filtro=%s  freno por escalon=%s  tope de retraso=%s"
          % ("SI" if RATE_FILTER else "NO",
             "SI" if PENDIENTE else "NO",
             "SI" if LAG_CAP else "NO"))
    print()
    fallos = []

    r = run(cartel, 3.0)
    lev, v = levantada(r), vmax(r)
    ok = lev <= 1.5 and v <= V_TIRON
    print("  cartel 6 yd / 0.15 s   sube %5.2f yd, tiron %6.1f yd/s   %s"
          % (lev, v, "ok" if ok else "MAL"))
    print("                         (<= 1.50 yd y <= %.0f yd/s)" % V_TIRON)
    if not ok:
        fallos.append("el cartel catapulta la camara")

    r = run(cuesta, 4.0)
    sep = separacion_min(r, 1.2)
    ok = sep >= 12.0
    print("  cuesta 45 grados       separacion minima %5.1f yd   %s (>= 12.0)"
          % (sep, "ok" if ok else "MAL"))
    if not ok:
        fallos.append("la cuesta entierra la camara")

    r = run(tejado, 6.0)
    v, llega = vmax(r), levantada(r)
    ok = v <= V_TIRON and llega >= 14.0
    print("  tejado 15 yd parado    tiron %6.1f yd/s, acaba subiendo %5.2f yd   %s"
          % (v, llega, "ok" if ok else "MAL"))
    print("                         (<= %.0f yd/s y >= 14.00 yd esperando 6 s)" % V_TIRON)
    if not ok:
        fallos.append("el tejado, o da un tiron o no se sube nunca")

    r = run(escalon, 8.0)
    v, llega = vmax(r), levantada(r)
    ok = v <= V_TIRON and llega >= 19.0
    print("  repisa 20 yd           tiron %6.1f yd/s, sube %5.2f yd   %s"
          % (v, llega, "ok" if ok else "MAL"))
    print("                         (<= %.0f yd/s y >= 19.00 yd en 7 s)" % V_TIRON)
    if not ok:
        fallos.append("una repisa mas baja que el vuelo catapulta o no se sube")

    # EL CASO QUE SI DA UN SALTO, Y NO ES UN FALLO.
    #
    # Un escalon MAS ALTO que la altura de vuelo deja a la camara DENTRO de la
    # roca en el frame en que se cruza el borde -- el rayo solo mira hacia
    # abajo, asi que el acantilado no se ve venir, se descubre estando dentro.
    # Ahi no hay filtro que valga: o sube ya, o se ve negro. Se prueba lo unico
    # que se le puede pedir, que es que NO se quede dentro; pedirle ademas que
    # no diera el tiron seria pedirle que hiciera lo imposible, y una prueba que
    # exige lo imposible acaba tumbandose a si misma.
    #
    # Y "INEVITABLE" ERA FALSO, que es lo que costo la ronda de las cuevas.
    # Inevitable es que la camara TENGA que subir; lo que no tiene nada de
    # inevitable es que suba las sesenta yardas EN UN FRAME. Este parrafo
    # bendijo durante tres rondas el unico teletransporte del fichero, y como la
    # prueba no lo miraba, el simulador aprobaba el codigo roto.
    r = run(acantilado, 20.0)
    dentro = tarda_en_salir(r, 1.0)
    llega = levantada(r)
    v = vmax(r)
    ok = dentro <= 2.5 and llega >= 55.0 and v <= V_EMPUJE
    print("  acantilado 60 yd       %4.2f s dentro, sube %5.2f yd, tiron %6.1f   %s"
          % (dentro, llega, v, "ok" if ok else "MAL"))
    print("                         (<= 2.50 s dentro y el tiron <= %.0f yd/s)" % V_EMPUJE)
    if not ok:
        fallos.append("el acantilado, o deja la camara dentro o la catapulta")

    r = run(repisa_y_cuesta, 6.0)
    lag = retraso_max(r)
    sep = separacion_min(r, 1.0)
    tope = OFFSET - CLEAR
    ok = lag <= tope + 1.0 and sep >= CLEAR - 0.01
    print("  repisa + cuesta larga  retraso maximo %5.1f yd, separacion %4.2f   %s"
          % (lag, sep, "ok" if ok else "MAL"))
    print("                         (<= %.0f yd: el tope sale de offset - clear)" % tope)
    if not ok:
        fallos.append("el retraso crece sin final y la camara acaba pegada al suelo")

    # LA BOCA DE LA CUEVA, LAS DOS VECES, Y LA SEGUNDA ES LA QUE VALE.
    #
    # A offset 30 el tope de retraso son 28 yardas y casi nada lo dispara; a 6.4
    # -- leido de `/rts fc` en juego el 2026-09-12, con la camara atascada dentro
    # de la montana -- son 4.4, o sea que el filtro de escalon no filtra nada y
    # todo pasa por el camino instantaneo. Correr el mismo perfil con los dos
    # offsets es lo que separa "pasa la prueba" de "pasa la prueba en la unica
    # configuracion que probe".
    for off, etiqueta in ((OFFSET, "offset 30 "), (6.4, "offset 6.4")):
        r = run(boca, 20.0, offset=off)
        v = vmax(r)
        llega = levantada(r)
        ok = v <= V_EMPUJE and llega >= 70.0
        print("  boca de cueva +80 %s tiron %7.1f yd/s, sube %5.2f yd   %s"
              % (etiqueta, v, llega, "ok" if ok else "MAL"))
        print("                         (<= %.0f yd/s y >= 70.00 yd en 19 s)" % V_EMPUJE)
        if not ok:
            fallos.append("la boca de cueva teletransporta la camara (%s)" % etiqueta.strip())

    # LA BAJADA, que es la mitad que no duele y por eso se olvida de probar.
    # Un filtro simetrico deja la camara flotando cuando el suelo cae, y eso se
    # ve como "la camara se ha quedado alta" -- otro sintoma, misma aritmetica.
    r = run(lambda t: 0.0 if t < 1.0 else -60.0, 20.0)
    baja = r[0][3] - min(z for _, _, _, z in r)
    ok = baja >= 55.0
    print("  se acaba el suelo -60  baja %5.2f yd   %s (>= 55.00 en 19 s)"
          % (baja, "ok" if ok else "MAL"))
    if not ok:
        fallos.append("la camara se queda flotando cuando el suelo cae")

    print()
    if fallos:
        print("FALLA: " + "; ".join(fallos))
    else:
        print("los nueve perfiles pasan")
    return not fallos


if __name__ == "__main__":
    import sys
    if "--sin-filtro" in sys.argv:
        RATE_FILTER = False
    if "--sin-pendiente" in sys.argv:
        PENDIENTE = False
    if "--sin-tope" in sys.argv:
        LAG_CAP = False
    if "--sin-empuje" in sys.argv:
        PUSH_LIMIT = False
    raise SystemExit(0 if informe() else 1)
