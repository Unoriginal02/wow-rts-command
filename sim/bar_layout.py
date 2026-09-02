import math

GAP = 0
PIECES = [("rail-left", 128, 0, False), ("map", 512, GAP, False), ("ramp-left", 128, 0, False),
          ("hall", 512, 0, True), ("ramp-right", 128, 0, False), ("orders", 512, 0, False),
          ("rail-right", 128, GAP, False)]
HOLE = {"rail": (29, 78, 30, 452), "railF": (21, 78, 30, 452), "map": (19, 474, 30, 452),
        "rampL": (21, 107, 122, 360), "rampR": (0, 107, 122, 360)}
# LA SALA ESTA VACIA desde 2026-09-02. El reparto interior que habia aqui --
# HERO_W, PARTY_W, las cuatro bandas del bloque derecho -- se fue con los siete
# modulos que lo llenaban (Portrait, Vitals, Roster, Foes, Skills, Roles,
# Targets). Lo que queda es el AREA UTIL, que es el numero que hace falta para
# decidir que va dentro, y este guion la imprime para cada `grow`.
PAD = 8
HALL_Y0 = HOLE["rampL"][2] + PAD
HALL_Y1 = HOLE["rampL"][2] + HOLE["rampL"][3] - PAD
HALL_X = HOLE["rampL"][0] + PAD
HALL_END = HOLE["rampR"][1] - PAD
RAIL_PAD, RAIL_ROWS = 2, 6
RAIL_PY = (HOLE["rail"][3] - RAIL_PAD * 2) // RAIL_ROWS
RAIL_CH = RAIL_PY
print("RAIL_PY", RAIL_PY, "RAIL_CH", RAIL_CH)
print("sala: HALL_Y0", HALL_Y0, "HALL_Y1", HALL_Y1, "alto", HALL_Y1 - HALL_Y0,
      "HALL_X", HALL_X, "HALL_END", HALL_END)

SLOTS = [
    dict(key="minimap", piece="map", dx=19, dy=30, w=474, h=452,
         cell=(452, 452, 452, 452), cols=1, rows=1),
    dict(key="hall", piece="ramp-left", dx=HALL_X, dy=HALL_Y0,
         h=HALL_Y1 - HALL_Y0, toPiece="ramp-right", toDx=HALL_END),
    dict(key="railL", piece="rail-left",
         dx=HOLE["rail"][0], dy=HOLE["rail"][2] + RAIL_PAD,
         w=HOLE["rail"][1], h=HOLE["rail"][3] - RAIL_PAD * 2,
         cell=(HOLE["rail"][1], RAIL_CH, HOLE["rail"][1], RAIL_PY),
         cols=1, rows=RAIL_ROWS),
    dict(key="railR", piece="rail-right",
         dx=HOLE["railF"][0], dy=HOLE["railF"][2] + RAIL_PAD,
         w=HOLE["railF"][1], h=HOLE["railF"][3] - RAIL_PAD * 2,
         cell=(HOLE["railF"][1], RAIL_CH, HOLE["railF"][1], RAIL_PY),
         cols=1, rows=RAIL_ROWS),
    dict(key="orders", piece="orders", dx=19, dy=30, w=474, h=452,
         cell=(105, 105, 113, 113), cols=4, rows=4),
]


def layout(n):
    place = {}
    x = 0
    for pid, w, gap, grow in PIECES:
        x += gap
        veces = n if grow else 1
        place.setdefault(pid, {"x": x})
        x += w * veces
        place[pid]["right"] = x
    return place, x


def area(s, place):
    rec = place[s["piece"]]
    x = rec["x"] + s["dx"]
    w = s.get("w")
    if s.get("toPiece"):
        w = (place[s["toPiece"]]["x"] + s["toDx"]) - x
    return x, s["dy"], w or 0, s.get("h", 0)


def grid(s, place):
    if "cell" not in s:
        return 1, 1
    _, _, w, h = area(s, place)
    if w <= 0 or h <= 0:
        return 0, 0
    cw, ch, px, py = s["cell"]
    cols, rows = s.get("cols", 1), s.get("rows", 1)
    if s.get("fill") in ("cols", "both"):
        cols = math.floor((w - cw) / px) + 1
        if cols < 1:
            return 0, 0
    if (cols - 1) * px + cw > w or (rows - 1) * py + ch > h:
        return 0, 0
    return cols, rows


for n in (1, 2, 3, 4, 5):
    place, BAR_W = layout(n)
    print("--- grow %d  BAR_W %d" % (n, BAR_W))
    for s in SLOTS:
        x, y, w, h = area(s, place)
        c, r = grid(s, place)
        msg = ""
        if "cell" in s and c > 0:
            cw, ch, px, py = s["cell"]
            gw = (c - 1) * px + cw
            gh = (r - 1) * py + ch
            if gw > w or gh > h:
                msg = "  !! grid %dx%d > area %dx%d" % (gw, gh, w, h)
        if w < 0:
            msg += "  !! NEGATIVE"
        print("   %-9s x=%5d y=%3d w=%5d h=%3d  %dx%d%s" % (s["key"], x, y, w, h, c, r, msg))

# what scale/grow gets chosen on the two screens
BAR_H = 512
for label, sw, sh in (("2560x1440 completa", 2560, 1440), ("ventana ~2560x1392", 2560, 1392)):
    scale = 0.20 * sh / BAR_H
    best, bd = None, None
    for n in range(1, 9):
        _, w = layout(n)
        margin = (sw - w * scale) / 2 / sw
        if margin >= 0.045:
            d = abs(margin - 0.10)
            if bd is None or d < bd - 0.0001:
                best, bd = n, d
    _, w = layout(best)
    print("%s -> escala %.3f  grow %d  barra %d x %d px  margen %.1f%%" % (
        label, scale, best, w * scale, BAR_H * scale,
        (sw - w * scale) / 2 / sw * 100))


# --- los botones de los railes: cabe el numero, y a que tamano de pantalla ---
#
# Un boton de menu del cliente mide 28x58 unidades de interfaz. La escala sale
# de la celda por el lado que peor va, que aqui es SIEMPRE el alto. Se compara
# contra la rejilla 4x4 de la ronda anterior, donde el tamano ya se dio por
# bueno, para que el 18% de merma sea un numero y no una impresion.
BTN_W, BTN_H = 28, 58
for label, sw, sh in (("2560x1440 completa", 2560, 1440), ("ventana ~2560x1392", 2560, 1392)):
    scale = 0.20 * sh / BAR_H
    k = min(HOLE["rail"][1] / BTN_W, RAIL_CH / BTN_H)
    print("%s: rail celda %dx%d dibujo -> k=%.2f -> boton %.0fx%.0f dibujo = %.0fx%.0f px"
          % (label, HOLE["rail"][1], RAIL_CH, k, BTN_W * k, BTN_H * k,
             BTN_W * k * scale, BTN_H * k * scale))
    kold = min(105 / BTN_W, (105 - 20) / BTN_H)   # la 4x4 con su franja de etiqueta
    print("   la 4x4 de antes daba k=%.2f = %.0fx%.0f px  (merma %.0f%%)"
          % (kold, BTN_W * kold * scale, BTN_H * kold * scale, (1 - k / kold) * 100))
    # y el rail nunca puede desbordar su hueco de 78
    assert BTN_W * k <= HOLE["rail"][1] + 0.01, "el boton se sale del rail"
    assert RAIL_ROWS * RAIL_PY <= HOLE["rail"][3] - RAIL_PAD, "las filas no caben"
print("railes: caben y no desbordan.")


# --- el recorte del glifo: que los cinco micro-botones salgan como la bolsa ---
#
# El problema de PRUEBAS-16 A2 en numeros: el arte del micro-boton es 28x58, o
# sea 1:2, y la celda es 78x74, o sea casi cuadrada. Respetar la proporcion topa
# con el ALTO y deja 50 unidades de ancho sin usar -- la mitad que la bolsa, que
# es cuadrada y llena.
#
# LA VENTANA CAMBIO DE LADO EL 2026-08-27. La primera version recortaba por
# ARRIBA, deducido de que el `HitRectInsets` del cliente declara 19 de 58 no
# pulsables abajo. En juego (PRUEBAS-18 A1) esos recortes salieron
# TRANSPARENTES, o sea que arriba no hay pixeles: `HitRectInsets` dice donde se
# PULSA, no donde esta el DIBUJO, y encadenar las dos cosas era razonar por
# analogia sobre el cliente.
#
# Lo que este bloque comprueba no cambia: que el trozo recortado entra en la
# celda por los dos lados, y que la ventana 1 sale del MISMO tamano que la
# bolsa. La ultima sigue siendo "sin recortar" a proposito, porque REPRODUCE EL
# FALLO (48% del ancho de la bolsa) -- una prueba que no falla nunca no prueba
# nada.
BAG = 36.0                      # MainMenuBarBackpackButton, cuadrado
CROPS = [
    (0.517, 1.000, "cuadrado desde ABAJO"),
    (0.422, 0.905, "cuadrado un poco mas arriba"),
    (0.328, 1.000, "abajo, mas alto que ancho (1,4:1)"),
    (0.259, 0.741, "cuadrado centrado en el arte"),
    (0.000, 1.000, "sin recortar (el 1:2 de siempre)"),
    (0.000, 0.483, "cuadrado desde arriba (el que salio vacio)"),
    (0.000, 0.672, "arriba sin el tercio de abajo"),
]

cw, ch = HOLE["rail"][1], RAIL_CH
kbag = min(cw / BAG, ch / BAG)
bag_w, bag_h = BAG * kbag, BAG * kbag
print("bolsa: %.0fx%.0f dibujo (k=%.2f) -- la referencia" % (bag_w, bag_h, kbag))

for i, (t, b, why) in enumerate(CROPS, 1):
    sw_, sh_ = BTN_W * 1.0, BTN_H * (b - t)
    k = min(cw / sw_, ch / sh_)
    w_, h_ = sw_ * k, sh_ * k
    print("  %d %-34s -> %.0fx%.0f dibujo  (%.0f%% del ancho de la bolsa)"
          % (i, why, w_, h_, w_ / bag_w * 100))
    # NO DESBORDA LA CELDA. Es la unica cosa que puede romper el arte del rail:
    # un frame hijo no se recorta en 3.3.5a, asi que lo que sobresale se ve.
    assert w_ <= cw + 0.01, "la ventana %d se sale de ancho" % i
    assert h_ <= ch + 0.01, "la ventana %d se sale de alto" % i

# La 1 es la apuesta y tiene que ser INDISTINGUIBLE de la bolsa: si no lo es, la
# cuenta esta mal y el ajuste en juego seria perseguir un fallo de aritmetica.
t, b, _ = CROPS[0]
k = min(cw / BTN_W, ch / (BTN_H * (b - t)))
assert abs(BTN_W * k - bag_w) < 1.5 and abs(BTN_H * (b - t) * k - bag_h) < 1.5, \
    "la ventana 1 no sale como la bolsa"
print("recorte: las siete ventanas caben y la 1 sale como la bolsa.")


# --- la sala: lo unico que se puede comprobar de un hueco vacio -------------
#
# El reparto de la fila de roles vivia aqui y se fue con `Roles.lua` el
# 2026-09-02, igual que los anchos del heroe y del grupo. De la sala solo queda
# el AREA, asi que lo unico comprobable es que existe y crece con `grow` -- pero
# eso ya es util: es el presupuesto con el que se va a redisenar, y tenerlo
# impreso evita empezar a repartir sobre una medida recordada.
#
# CUANDO LA SALA SE VUELVA A LLENAR, LAS COMPROBACIONES VUELVEN AQUI. Las tres
# que tenia y que valen para cualquier contenido:
#
#   * que la rejilla de cada banda quepa en su area por los dos lados
#   * que las bandas sumen EXACTAMENTE el alto del hueco (eran 130+8+3+8+111+8+76
#     = 344), para que tocar una se vea inmediatamente en la de al lado
#   * que un area demasiado estrecha devuelva CERO celdas y no una celda que se
#     sale -- el caso que cazo el sim en la etapa 5l y que el juego no habria
#     ensenado hasta tener la barra en su ancho minimo
hall = [s2 for s2 in SLOTS if s2["key"] == "hall"][0]
print("--- la sala, vacia: el presupuesto del rediseno")
for grow in (1, 2, 3, 4, 5):
    place, _ = layout(grow)
    _, _, w, h = area(hall, place)
    assert h == HALL_Y1 - HALL_Y0, "el alto de la sala no puede depender de grow"
    assert w > 0, "la sala sale negativa con grow %d" % grow
    scale = 0.20 * 1440 / BAR_H
    print("   grow %d -> %d x %d dibujo  (%d x %d px en 2560x1440)"
          % (grow, w, h, w * scale, h * scale))
print("sala: existe, crece con grow y su alto es fijo en %d." % (HALL_Y1 - HALL_Y0))
