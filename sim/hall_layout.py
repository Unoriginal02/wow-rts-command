"""El reparto de la SALA: columna de personajes + zona de contenido.

Reproduce fuera del juego la aritmetica de `Hall.lua`, que es la unica parte
del panel que es aritmetica pura, y le pasa los casos que en juego cuestan una
ronda de pruebas cada uno:

  * los cinco `grow` (la sala mide 710..2758 de ancho),
  * los dos estados: A (uno seleccionado) y B (2..5 columnas),
  * 4 y 6 huecos por columna, que es el "ampliable a 6" del brief,
  * y la pregunta de §9.2 del brief: ¿caben cinco columnas de cuatro?

Se comprueba lo mismo que comprobo `bar_layout.py` en su dia -- que nada se
sale del area, que nada se solapa y que ninguna celda sale de tamano absurdo --
porque los tres fallos que caza son invisibles hasta que se ven en pantalla, y
entonces parecen fallos de anclaje.

TIENE DIENTES: `FIT_GUARD = False` vuelve al comportamiento ingenuo (repartir
sin comprobar que quepa) y las pruebas tienen que fallar. Un test que pasa con
el codigo roto no es un test.
"""

FIT_GUARD = True

# --- lo que Bar.lua da (medido, no elegido) --------------------------------
HALL_H = 344
def hall_w(grow):
    return 710 + 512 * (grow - 1)

# --- las medidas del reparto, en pixeles de DIBUJO -------------------------
#
# El arte es 2x y se dibuja a ~x0.562 en 2560x1440, asi que todo lo de aqui se
# ve a algo mas de la mitad. Es la misma convencion que Bar.lua y Widgets.lua,
# y el sitio donde se olvido costo las guias ilegibles de la etapa 5l.

LIST_W   = 260    # la columna de personajes: estrecha, pero el nombre cabe
GUTTER   = 12     # entre la columna y la zona de contenido

ROW_N    = 5      # heroe + cuatro companeros
ROW_GAP  = 4
NAME_H   = 24     # el nombre va ENCIMA de la barra (§3), no dentro
NAME_GAP = 2
POWER_H  = 6      # "linea muy fina, 2-4 px" de pantalla -> 6 de dibujo = 3,4 px
POWER_GAP = 2

TOP_H    = 96     # los marcos de unidad: "el minimo espacio vertical posible"
TOP_GAP  = 10

SLOT_GAP = 8
SLOT_MAX = 112    # un hueco mas grande que esto se ve como un cartel
SLOT_MIN = 40     # y mas pequeno que esto no se distingue el icono

ACT_N    = 4      # los cuatro botones de accion configurables (§4.1)
ACT_GAP  = 14     # entre la fila de hechizos y la de acciones
ACT_MAX  = 96     # las acciones van algo mas pequenas: son la fila secundaria

# LAS ACCIONES VAN DEBAJO DE LOS HECHIZOS, NO AL LADO, y esa es una correccion
# que hizo este mismo guion antes de escribir una linea de Lua.
#
# El primer reparto las ponia a la derecha de la fila de hechizos, compitiendo
# por el ANCHO. Con `grow` 1 la zona de contenido mide 438 y no cabian: cero
# botones, y justo los cuatro que el brief llama "caso de uso prioritario"
# (curar en focus). Con `grow` 2 salian a 73 contra 96 de los hechizos, o sea
# encogidas por una razon que no tiene nada que ver con lo que son.
#
# Apiladas compiten por el ALTO, que es fijo (238 en la banda de abajo) y da de
# sobra para dos filas. Y ademas se leen mejor: una fila de hechizos y una fila
# de acciones son dos cosas distintas, y ponerlas en la misma linea las hacia
# parecer la misma.

HEAD_H   = 26     # la cabecera con el nombre, en las columnas del estado B


def row_layout():
    """Una fila de la columna izquierda: nombre encima, vida, linea de poder."""
    row_h = (HALL_H - ROW_GAP * (ROW_N - 1)) // ROW_N
    hp = row_h - NAME_H - NAME_GAP - POWER_GAP - POWER_H
    return row_h, dict(name=(0, NAME_H),
                       health=(NAME_H + NAME_GAP, hp),
                       power=(NAME_H + NAME_GAP + hp + POWER_GAP, POWER_H))


def content_rect(grow):
    """La zona derecha: lo que queda de la sala tras la columna."""
    x = LIST_W + GUTTER
    return x, 0, hall_w(grow) - x, HALL_H


def fit_across(width, n, gap, hi=SLOT_MAX, lo=SLOT_MIN):
    """El lado de n cuadrados en fila dentro de `width`. 0 si no caben.

    ES LA FUNCION QUE DECIDE si una fila se dibuja o se esconde, y devolver 0
    en vez de recortar es deliberado: es la leccion de `SlotGrid` en Bar.lua --
    "no cabe" significa que no cabe UNA celda, y meterla a la fuerza pone un
    boton de 103 px en un hueco de 48.
    """
    if n <= 0 or width <= 0:
        return 0
    side = (width - gap * (n - 1)) // n
    if side > hi:
        side = hi
    if FIT_GUARD and side < lo:
        return 0
    return side


def state_a(grow, nslots):
    """Uno seleccionado: marcos arriba, hechizos y acciones APILADOS abajo."""
    cx, cy, cw, ch = content_rect(grow)
    top = dict(x=cx, y=cy, w=cw, h=TOP_H)

    by = cy + TOP_H + TOP_GAP
    bh = ch - TOP_H - TOP_GAP

    # Cada fila se lleva todo el ancho; el alto se reparte entre las dos.
    room = (bh - ACT_GAP) // 2

    spell_side = fit_across(cw, nslots, SLOT_GAP)
    if spell_side > room:
        spell_side = room

    act_side = fit_across(cw, ACT_N, SLOT_GAP, hi=ACT_MAX)
    if act_side > room:
        act_side = room

    # UNA FILA QUE NO CABE NO SE DIBUJA, y devolver 0 en vez de recortar es la
    # misma decision que `SlotGrid` en Bar.lua: meter un boton a la fuerza en un
    # hueco menor deja algo flotando sobre el arte.
    if FIT_GUARD and spell_side < SLOT_MIN:
        spell_side = 0
    if FIT_GUARD and act_side < SLOT_MIN:
        act_side = 0

    ay = by + (spell_side + ACT_GAP if spell_side else 0)

    return dict(top=top,
                spells=dict(x=cx, y=by, side=spell_side, n=nslots),
                actions=dict(x=cx, y=ay, side=act_side, n=ACT_N),
                band=dict(y=by, h=bh))


def state_b(grow, ncols, nslots):
    """Dos o mas: una columna por personaje, toda la zona derecha."""
    cx, cy, cw, ch = content_rect(grow)
    col_w = (cw - GUTTER * (ncols - 1)) // ncols if ncols else 0
    side = fit_across(col_w, nslots, SLOT_GAP)
    room = ch - HEAD_H - SLOT_GAP
    if side > room:
        side = room
    if FIT_GUARD and side and side < SLOT_MIN:
        side = 0
    cols = [dict(x=cx + i * (col_w + GUTTER), w=col_w) for i in range(ncols)]
    return dict(cols=cols, col_w=col_w, side=side, n=nslots)


# --- comprobaciones --------------------------------------------------------

def check(name, ok, detail=""):
    print(("  OK   " if ok else "  FALLA") + " " + name + ("  " + detail if detail else ""))
    return ok


def main():
    fails = 0

    print("=== la columna de personajes (§3) ===")
    row_h, parts = row_layout()
    print("  fila %d de alto  ->  nombre %d, vida %d, poder %d"
          % (row_h, parts["name"][1], parts["health"][1], parts["power"][1]))
    total = row_h * ROW_N + ROW_GAP * (ROW_N - 1)
    fails += not check("las cinco filas caben en la sala",
                       total <= HALL_H, "%d <= %d" % (total, HALL_H))
    fails += not check("la barra de vida es la pieza dominante",
                       parts["health"][1] > parts["name"][1] and parts["health"][1] > POWER_H * 3,
                       "vida %d" % parts["health"][1])
    fails += not check("la linea de poder cae en 2-4 px de PANTALLA",
                       2 <= round(POWER_H * 0.562) <= 4,
                       "%d dibujo -> %.1f px" % (POWER_H, POWER_H * 0.562))
    # "Estrecha" se mide contra la sala QUE SE USA, no contra la mas pequena.
    # `autoGrow` elige 4 en 2560x1440 a pantalla completa, que es donde se
    # juega; con `grow` 1 la sala entera mide 710 y ahi no hay reparto que
    # parezca estrecho.
    for grow in (1, 4):
        pct = 100.0 * LIST_W / hall_w(grow)
        print("  con grow %d la columna es el %.0f%% de la sala" % (grow, pct))
    fails += not check("estrecha con el grow que sale solo (4)",
                       LIST_W < hall_w(4) * 0.20,
                       "%d de %d" % (LIST_W, hall_w(4)))

    print()
    print("=== estado A: uno seleccionado (§4.1) ===")
    for grow in range(1, 6):
        for n in (4, 6):
            a = state_a(grow, n)
            sp, ac = a["spells"], a["actions"]
            cx, _, cw, ch = content_rect(grow)

            def right_of(b):
                if not b["side"]:
                    return cx
                return b["x"] + b["side"] * b["n"] + SLOT_GAP * (b["n"] - 1)

            right = max(right_of(sp), right_of(ac))
            bottom = ac["y"] + ac["side"] if ac["side"] else sp["y"] + sp["side"]
            fits = right <= cx + cw and bottom <= ch
            print("  grow %d  %d huecos -> hechizo %3s, accion %3s, "
                  "borde %5d/%5d, fondo %3d/%3d %s"
                  % (grow, n, sp["side"] or "-", ac["side"] or "-",
                     right, cx + cw, bottom, ch, "" if fits else "  <-- SE SALE"))
            fails += not check("  cabe entero", fits)

    print()
    print("=== estado B: columnas por personaje (§4.2, §9.2) ===")
    for grow in range(1, 6):
        line = "  grow %d (sala %4d):" % (grow, hall_w(grow))
        for ncols in (2, 3, 4, 5):
            b = state_b(grow, ncols, 4)
            line += "  %dcol=%s" % (ncols, b["side"] if b["side"] else "NO")
        print(line)

    print()
    print("  la pregunta del brief: 5 columnas x 4 huecos")
    for grow in range(1, 6):
        b4 = state_b(grow, 5, 4)
        b6 = state_b(grow, 5, 6)
        print("    grow %d -> columna %4d, hueco de 4: %s, de 6: %s"
              % (grow, b4["col_w"],
                 b4["side"] or "NO CABE", b6["side"] or "NO CABE"))

    # AUTOGROW ES 4 en 2560x1440 a pantalla completa, que es donde se juega.
    b = state_b(4, 5, 4)
    fails += not check("5 columnas x 4 huecos con grow 4 (el que sale solo)",
                       b["side"] >= SLOT_MIN, "hueco %d" % b["side"])
    b6 = state_b(4, 5, 6)
    fails += not check("y ampliadas a 6, que es el techo del brief",
                       b6["side"] >= SLOT_MIN, "hueco %d" % b6["side"])

    # LA GUARDA TIENE QUE RECHAZAR LO QUE NO CABE, y esta es la comprobacion que
    # le da dientes: con `grow` 1 la sala mide 710 y una columna de cinco sale a
    # 78, o sea huecos de 17 px de dibujo -- diez de pantalla. Sin la guarda no
    # falla nada: salen, diminutos, y en juego se lee como arte roto.
    fails += not check("5 columnas se RECHAZAN con grow 1 (no se recortan)",
                       state_b(1, 5, 4)["side"] == 0,
                       "hueco %d" % state_b(1, 5, 4)["side"])

    # Y EL MENSAJE QUE EL MODULO TIENE QUE DAR. Cuando no caben, la salida no es
    # esconderlas en silencio: es decir cuanto hay que ensanchar. Es justo lo
    # que el brief propone en §9.2 ("si no, ensanchar barra"), y `grow` ya lo
    # hace desde 2026-08-19.
    print()
    print("  grow minimo por numero de columnas (lo que dice /rts hall):")
    for ncols in (2, 3, 4, 5):
        need = next((gw for gw in range(1, 9) if state_b(gw, ncols, 4)["side"]), None)
        need6 = next((gw for gw in range(1, 9) if state_b(gw, ncols, 6)["side"]), None)
        print("    %d columnas -> grow %s (con 6 huecos, %s)"
              % (ncols, need or ">8", need6 or ">8"))

    print()
    print("=== solapes: ninguna banda pisa a la de al lado ===")
    for grow in range(1, 6):
        a = state_a(grow, 6)
        cx, _, cw, _ = content_rect(grow)
        sp, ac = a["spells"], a["actions"]
        if sp["side"] and ac["side"]:
            fails += not check("grow %d: las dos filas no se pisan" % grow,
                               sp["y"] + sp["side"] <= ac["y"],
                               "%d <= %d" % (sp["y"] + sp["side"], ac["y"]))
        fails += not check("grow %d: la columna no pisa el contenido" % grow,
                           LIST_W <= cx, "%d <= %d" % (LIST_W, cx))
        fails += not check("grow %d: la banda de abajo cabe" % grow,
                           a["band"]["y"] + a["band"]["h"] <= HALL_H)

    print()
    if fails:
        print("%d COMPROBACIONES FALLIDAS" % fails)
    else:
        print("todo cuadra." if FIT_GUARD else
              "todo cuadra CON LA GUARDA QUITADA -- la prueba no tiene dientes.")
    return fails


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)
