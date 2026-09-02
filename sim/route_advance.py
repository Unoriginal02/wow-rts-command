"""Simula el avance de Route.lua fuera del juego.

Reimplementa SOLO la maquina de estados -- indice por unidad, `sent`, troceo de
tramos largos, llegada al 95%, deteccion de bot parado y plazo -- con las mismas
reglas que el Lua, y le pasa los escenarios que en juego cuestan una ronda de
pruebas cada uno. No mira dibujo ni proyeccion: mira que nadie se salte un punto
y que la ruta termine SIEMPRE.

Ha encontrado dos fallos reales antes de que llegaran al juego. Ver LEEME.md.
"""

ARRIVE = 3.0
NEAR = 0.05
TIMEOUT = 40.0
MAXLEG = 100.0
STALL = 5.0
RETRIES = 3

# Interruptores para volver al codigo de ANTES y comprobar que las pruebas
# tienen dientes. Una prueba que pasa con el codigo roto no es una prueba.
SENT_GUARD = True     # False = sin `u.sent`: se saltan puntos anadidos tarde
SPLIT_LEGS = True     # False = sin trocear: un tramo > reactDistance no arranca
GIVE_UP = True        # False = sin tope de reintentos: un atascado cuelga la ruta

# Lo que hace playerbots: un ancla mas lejos que esto NO es util y el bot ni
# arranca (MoveToPositionAction::isUseful con AiPlayerbot.ReactDistance = 150).
REACT_DISTANCE = 150.0


def dist(ax, ay, bx, by):
    return ((ax - bx) ** 2 + (ay - by) ** 2) ** 0.5


class Unit:
    def __init__(self, name, x, y, speed=7.0):
        self.name, self.x, self.y, self.speed = name, x, y, speed
        self.stuck = False

    def step(self, dt, tx, ty):
        """Se mueve hacia el objetivo. Si esta MAS LEJOS que reactDistance no se
        mueve nada, que es lo que hace la IA de verdad."""
        if self.stuck or tx is None:
            return
        d = dist(self.x, self.y, tx, ty)
        if d < 1e-6 or d > REACT_DISTANCE:
            return
        m = min(self.speed * dt, d)
        self.x += (tx - self.x) / d * m
        self.y += (ty - self.y) / d * m


class Route:
    def __init__(self, units, pt, now, issued):
        self.units = list(units)
        self.pts = [pt]
        self.u = {}
        for n in units:
            self.u[n] = dict(idx=1, at=now, since=now, stalls=0,
                             tx=pt[0], ty=pt[1], fx=pt[0], fy=pt[1],
                             partial=False, arm=1, sent=1 if issued else None,
                             d0=None, px=None, py=None, pat=now)

    def add(self, pt):
        self.pts.append(pt)


def issue(route, mover, world, now, log):
    for name in mover:
        u = route.u[name]
        if u["idx"] > len(route.pts):
            continue
        p = route.pts[u["idx"] - 1]
        w = world[name]
        fx, fy = p[0], p[1]
        tx, ty = fx, fy

        d = dist(w.x, w.y, fx, fy)
        if SPLIT_LEGS and d > MAXLEG:
            f = MAXLEG / d
            tx = w.x + (fx - w.x) * f
            ty = w.y + (fy - w.y) * f

        u["at"] = now
        # El reloj y el contador son del PUNTO DE RUTA, no del envio: `arm` es
        # el indice para el que ya se armaron. Sin esto cada reenvio los ponia a
        # cero y ni el plazo ni el tope de reintentos llegaban nunca.
        if u["arm"] != u["idx"]:
            u["since"] = now
            u["stalls"] = 0
            u["arm"] = u["idx"]
        u["fx"], u["fy"] = fx, fy
        u["tx"], u["ty"] = tx, ty
        u["partial"] = (tx != fx or ty != fy)
        u["sent"] = u["idx"]
        u["d0"] = dist(w.x, w.y, tx, ty)
        u["px"], u["py"], u["pat"] = w.x, w.y, now
        log.append((now, name, "trozo" if u["partial"] else "punto", u["idx"]))


def advance(route, world, now, log):
    mover, vivas = [], 0
    for name in route.units:
        u = route.u[name]
        armado = (u["sent"] == u["idx"]) if SENT_GUARD else True

        if u["idx"] <= len(route.pts) and armado:
            llego = repetir = rendirse = False
            w = world.get(name)
            x, y = (w.x, w.y) if w else (None, None)

            if u["tx"] is not None and x is not None:
                umbral = ARRIVE
                if u["d0"]:
                    umbral = max(umbral, u["d0"] * NEAR)
                llego = dist(x, y, u["tx"], u["ty"]) <= umbral

            if not llego and x is not None:
                if u["px"] is not None and dist(x, y, u["px"], u["py"]) > 1.0:
                    u["px"], u["py"], u["pat"] = x, y, now
                    u["stalls"] = 0
                elif now - u["pat"] > STALL:
                    u["stalls"] += 1
                    if GIVE_UP and u["stalls"] >= RETRIES:
                        rendirse = True
                        log.append((now, name, "SE RINDE en", u["idx"]))
                    else:
                        repetir = True

            if x is None and now - u["since"] > TIMEOUT:
                rendirse = True
                log.append((now, name, "PLAZO sin posicion en", u["idx"]))

            if rendirse:
                u["idx"] += 1
            elif llego:
                if u["partial"]:
                    repetir = True
                else:
                    u["idx"] += 1

            if repetir:
                u["sent"] = None

        if u["idx"] <= len(route.pts):
            vivas += 1
            if u["sent"] != u["idx"]:
                mover.append(name)

    if mover:
        issue(route, mover, world, now, log)
    return vivas


def run(scenario, units, first, adds=(), stuck=(), issued=True, limit=300.0):
    """adds = [(t, punto)] -- cuando se hace shift+clic en cada punto."""
    world = {u.name: u for u in units}
    for u in units:
        if u.name in stuck:
            u.stuck = True

    now, log = 0.0, []
    route = Route([u.name for u in units], first, now, issued)
    if not issued:
        issue(route, route.units, world, now, log)

    pending, dt, dead = list(adds), 0.2, None
    while now < limit:
        now += dt
        while pending and pending[0][0] <= now:
            route.add(pending.pop(0)[1])
            log.append((now, "-", "shift: punto", len(route.pts)))
        for u in units:
            st = route.u[u.name]
            if st["sent"] == st["idx"]:
                u.step(dt, st["tx"], st["ty"])
        if advance(route, world, now, log) == 0:
            dead = now
            break

    print("=== %s ===" % scenario)
    for t, who, what, k in log:
        print("  %6.1fs  %-8s %s %d" % (t, who, what, k))
    print("  ruta terminada en %s"
          % ("%.1fs" % dead if dead else "NUNCA (colgada)"))

    ok = dead is not None
    if not ok:
        print("  !! la ruta no termina: eso es un cuelgue")

    # Cada unidad tiene que haber ATENDIDO cada punto de ruta al menos una vez.
    # Se cuentan los puntos atendidos, no las ordenes: un tramo largo se manda
    # en varios trozos y un bot parado recibe la suya repetida, y ninguna de las
    # dos cosas es saltarse un punto.
    for u in units:
        seen = set()
        if issued:
            seen.add(1)
        for t, who, what, k in log:
            if who == u.name and what in ("punto", "trozo", "SE RINDE en",
                                          "PLAZO sin posicion en"):
                seen.add(k)
        falta = [k for k in range(1, len(route.pts) + 1) if k not in seen]
        if falta:
            print("  !! %s se salto el/los punto(s) %s" % (u.name, falta))
            ok = False

    # Y ATENDER NO ES LLEGAR. Sin esta segunda comprobacion, "se rinde y pasa al
    # siguiente" contaba como haber recorrido la ruta -- y con eso el escenario
    # del tramo de 400 yardas pasaba INCLUSO con el troceo apagado, porque el
    # bot se quedaba quieto, agotaba los reintentos y la ruta terminaba sola.
    # Terminar no es lo que se le pide a una ruta: lo que se le pide es que las
    # unidades acaben donde apuntaba.
    ultimo = route.pts[-1]
    for u in units:
        if u.name in stuck:
            continue      # este no puede llegar y no se le exige
        d = dist(u.x, u.y, ultimo[0], ultimo[1])
        if d > ARRIVE * 2:
            print("  !! %s acabo a %.0f yardas del ultimo punto, no llego"
                  % (u.name, d))
            ok = False

    print("  %s\n" % ("OK" if ok else "FALLO"))
    return ok


todo = True

todo &= run("tres puntos seguidos",
            [Unit("Ana", 0, 0), Unit("Bea", 2, 0)],
            (50, 0, 0), [(0.4, (100, 0, 0)), (0.6, (150, 0, 0))])

# Uno rapido llega y se para; el lento sigue, asi que la ruta vive. Y ENTONCES
# se anade un punto. Sin `u.sent`, el rapido se lo salta entero.
todo &= run("punto anadido con uno ya parado en el anterior",
            [Unit("Rapido", 0, 0, speed=9.0), Unit("Lento", 0, 6, speed=1.5)],
            (30, 0, 0), [(8.0, (70, 0, 0))])

todo &= run("uno lento, no se esperan",
            [Unit("Ana", 0, 0, speed=7.0), Unit("Lento", 0, 5, speed=2.0)],
            (40, 0, 0), [(0.4, (80, 0, 0))])

# Mas lejos que reactDistance: sin trocear, la IA ni arranca.
todo &= run("tramo de 400 yardas (mas que reactDistance)",
            [Unit("Ana", 0, 0)], (400, 0, 0), limit=400.0)

# Atascado de verdad. Tiene que RENDIRSE, no colgar la ruta para siempre.
todo &= run("uno encallado: se rinde y la ruta acaba",
            [Unit("Ana", 0, 0), Unit("Roca", 0, 5)],
            (40, 0, 0), [(0.4, (80, 0, 0))], stuck=("Roca",))

print("TODO OK" if todo else "HAY FALLOS")
