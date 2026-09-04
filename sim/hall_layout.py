"""El reparto de la SALA: columna de personajes + zona de contenido.

Reproduce fuera del juego la aritmetica de `Hall.lua`, que es la unica parte
del panel que es aritmetica pura, y le pasa los casos que en juego cuestan una
ronda de pruebas cada uno:

  * los cinco `grow` (la sala mide 710..2758 de ancho),
  * los dos estados: A (uno seleccionado) y B (2..5 columnas),
  * y la pregunta de §9.2 del brief: ¿caben las columnas?

Se comprueba que nada se sale del area, que nada se solapa y que ninguna celda
sale de tamano absurdo -- los tres fallos que son invisibles hasta que se ven en
pantalla, y que entonces parecen fallos de anclaje.

=== SEGUNDA VERSION, 2026-09-04 (tarde): EL BOCETO ========================

El boceto a mano cambia cuatro cosas de la primera version, y las cuatro son de
forma, no de ajuste:

  * ESTADO A: **diez** huecos de hechizo en una fila, no cuatro.
  * LOS BOTONES DE ACCION SON **MACROS**: barras anchas con su nombre escrito,
    no iconos cuadrados. Un macro necesita leerse, no reconocerse.
  * ESTADO B: por columna, **2x2 de hechizos y 2 macros**, no una fila.
  * Una LINEA DIVISORIA bajo los marcos, y el marco de objetivo-del-objetivo
    mas pequeno que el del objetivo.

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
GUTTER   = 12

ROW_N    = 5      # heroe + cuatro companeros
ROW_GAP  = 4
NAME_H   = 24     # el nombre va ENCIMA de la barra (§3), no dentro
NAME_GAP = 2
POWER_H  = 6      # "linea muy fina, 2-4 px" de pantalla -> 6 de dibujo = 3,4 px
POWER_GAP = 2

TOP_H    = 96     # los marcos de unidad: "el minimo espacio vertical posible"
DIV_GAP  = 10     # aire a cada lado de la linea divisoria
DIV_H    = 2

SLOT_GAP = 8
SLOT_MAX = 112    # un hueco mas grande que esto se ve como un cartel
SLOT_MIN = 40     # y mas pequeno que esto no se distingue el icono

SPELL_N  = 10     # "10x Spells" del boceto, en UNA fila
MACRO_N  = 4      # los cuatro macros del estado A
MACRO_H  = 56     # 31 px de pantalla: cabe el texto a fuente 22 de dibujo
MACRO_GAP = 8
VGAP     = 14     # entre la fila de hechizos y la de macros

# --- el estado B, por columna ---------------------------------------------
HEAD_H    = 26    # la cabecera con el nombre
HEAD_GAP  = 6
B_COLS    = 2     # el 2x2
B_ROWS    = 2
B_MACRO_N = 2
B_MACRO_H = 42
B_MACRO_GAP = 4
B_MID_GAP = 10    # entre el bloque de hechizos y el de macros


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


def state_a(grow):
    """Uno seleccionado: marcos, raya, diez hechizos, cuatro macros."""
    cx, cy, cw, ch = content_rect(grow)
    top = dict(x=cx, y=cy, w=cw, h=TOP_H)
    div_y = TOP_H + DIV_GAP
    by = div_y + DIV_H + DIV_GAP
    bh = ch - by

    side = fit_across(cw, SPELL_N, SLOT_GAP)
    # El alto tambien manda: la fila de hechizos y la de macros comparten banda.
    room = bh - VGAP - MACRO_H
    if side > room:
        side = room
    if FIT_GUARD and side < SLOT_MIN:
        side = 0

    spell_w = side * SPELL_N + SLOT_GAP * (SPELL_N - 1) if side else 0

    # LOS MACROS SE ALINEAN CON LA FILA DE HECHIZOS, y ese es todo su ancho.
    # Derivarlo en vez de escribirlo es lo que hace que cambiar el numero de
    # huecos no descuadre la fila de abajo -- la misma regla que Bar.lua aplica
    # a las posiciones de sus piezas.
    macro_w = (spell_w - MACRO_GAP * (MACRO_N - 1)) // MACRO_N if spell_w else 0

    return dict(top=top,
                div=dict(x=cx, y=div_y, w=cw, h=DIV_H),
                spells=dict(x=cx, y=by, side=side, n=SPELL_N, w=spell_w),
                macros=dict(x=cx, y=by + side + VGAP if side else by,
                            w=macro_w, h=MACRO_H, n=MACRO_N),
                band=dict(y=by, h=bh))


def state_b(grow, ncols):
    """Dos o mas: una columna por personaje, 2x2 de hechizos y 2 macros."""
    cx, cy, cw, ch = content_rect(grow)
    col_w = (cw - GUTTER * (ncols - 1)) // ncols if ncols else 0

    # El alto es el que manda casi siempre, asi que se calcula primero y el
    # ancho solo puede empeorarlo.
    room = ch - HEAD_H - HEAD_GAP - B_MID_GAP \
           - (B_MACRO_H * B_MACRO_N + B_MACRO_GAP * (B_MACRO_N - 1)) \
           - SLOT_GAP * (B_ROWS - 1)
    by_height = room // B_ROWS

    side = fit_across(col_w, B_COLS, SLOT_GAP)
    if side > by_height:
        side = by_height
    if FIT_GUARD and side < SLOT_MIN:
        side = 0

    grid_w = side * B_COLS + SLOT_GAP * (B_COLS - 1) if side else 0
    cols = [dict(x=cx + i * (col_w + GUTTER), w=col_w) for i in range(ncols)]

    # LOS MACROS DEL ESTADO B OCUPAN LA COLUMNA ENTERA, y eso es una desviacion
    # del boceto dicha a proposito. Alli tienen el ancho del bloque 2x2, pero
    # las proporciones reales no son las del papel: con `grow` 4 y cinco
    # columnas el bloque mide 216 dentro de una columna de 385, o sea 169 px de
    # hueco muerto a los lados por columna. Un macro es una barra de TEXTO --
    # cuanto mas ancha, mejor se lee -- asi que llenar la columna no cuesta nada
    # y el bloque 2x2 se centra encima.
    return dict(cols=cols, col_w=col_w, side=side, grid_w=grid_w,
                macro_w=col_w, macro_h=B_MACRO_H,
                total_h=HEAD_H + HEAD_GAP + side * B_ROWS + SLOT_GAP * (B_ROWS - 1)
                        + B_MID_GAP + B_MACRO_H * B_MACRO_N
                        + B_MACRO_GAP * (B_MACRO_N - 1) if side else 0)


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
    for grow in (1, 4):
        print("  con grow %d la columna es el %.0f%% de la sala"
              % (grow, 100.0 * LIST_W / hall_w(grow)))
    fails += not check("estrecha con el grow que sale solo (4)",
                       LIST_W < hall_w(4) * 0.20, "%d de %d" % (LIST_W, hall_w(4)))

    print()
    print("=== estado A: diez hechizos y cuatro macros (boceto) ===")
    for grow in range(1, 6):
        a = state_a(grow)
        cx, _, cw, ch = content_rect(grow)
        sp, mc = a["spells"], a["macros"]
        right = max(cx + sp["w"], cx + mc["w"] * MACRO_N + MACRO_GAP * (MACRO_N - 1))
        bottom = (mc["y"] + mc["h"]) if sp["side"] else a["band"]["y"]
        fits = right <= cx + cw and bottom <= ch
        print("  grow %d  hueco %3s (fila %4d)  macro %4dx%d  borde %5d/%5d  fondo %3d/%3d %s"
              % (grow, sp["side"] or "-", sp["w"], mc["w"], mc["h"],
                 right, cx + cw, bottom, ch, "" if fits else "  <-- SE SALE"))
        fails += not check("  cabe entero", fits)
        if sp["side"]:
            fails += not check("  los macros se alinean con los hechizos",
                               abs((mc["w"] * MACRO_N + MACRO_GAP * (MACRO_N - 1)) - sp["w"]) <= 3,
                               "%d vs %d" % (mc["w"] * MACRO_N + MACRO_GAP * (MACRO_N - 1), sp["w"]))
            fails += not check("  la fila de macros no pisa la de hechizos",
                               sp["y"] + sp["side"] <= mc["y"])

    print()
    print("=== estado B: 2x2 + 2 macros por columna (boceto) ===")
    for grow in range(1, 6):
        line = "  grow %d (sala %4d):" % (grow, hall_w(grow))
        for ncols in (2, 3, 4, 5):
            b = state_b(grow, ncols)
            line += "  %dcol=%s" % (ncols, b["side"] if b["side"] else "NO")
        print(line)

    print()
    print("  el detalle de la columna:")
    for grow in range(1, 6):
        b = state_b(grow, 5)
        print("    grow %d -> columna %4d, hueco %s, bloque %s, macro %dx%d, alto usado %s/%d"
              % (grow, b["col_w"], b["side"] or "NO CABE", b["grid_w"] or "-",
                 b["macro_w"], b["macro_h"], b["total_h"] or "-", HALL_H))
        if b["side"]:
            fails += not check("    grow %d: la columna no desborda de alto" % grow,
                               b["total_h"] <= HALL_H,
                               "%d <= %d" % (b["total_h"], HALL_H))
            fails += not check("    grow %d: el bloque 2x2 cabe de ancho" % grow,
                               b["grid_w"] <= b["col_w"],
                               "%d <= %d" % (b["grid_w"], b["col_w"]))

    # AUTOGROW ES 4 en 2560x1440 a pantalla completa, que es donde se juega.
    b = state_b(4, 5)
    fails += not check("5 columnas con grow 4 (el que sale solo)",
                       b["side"] >= SLOT_MIN, "hueco %d" % b["side"])

    # LA GUARDA TIENE QUE RECHAZAR LO QUE NO CABE, y esta es la comprobacion que
    # le da dientes: con `grow` 1 la sala mide 710 y una columna de cinco sale a
    # 78, o sea huecos de 35 px de dibujo -- veinte de pantalla. Sin la guarda no
    # falla nada: salen, diminutos, y en juego se lee como arte roto.
    fails += not check("5 columnas se RECHAZAN con grow 1 (no se recortan)",
                       state_b(1, 5)["side"] == 0,
                       "hueco %d" % state_b(1, 5)["side"])

    print()
    print("  grow minimo por numero de columnas (lo que dice /rts hall):")
    for ncols in (2, 3, 4, 5):
        need = next((gw for gw in range(1, 9) if state_b(gw, ncols)["side"]), None)
        print("    %d columnas -> grow %s" % (ncols, need or ">8"))

    print()
    print("=== solapes ===")
    for grow in range(1, 6):
        a = state_a(grow)
        cx, _, cw, _ = content_rect(grow)
        fails += not check("grow %d: la columna no pisa el contenido" % grow,
                           LIST_W <= cx, "%d <= %d" % (LIST_W, cx))
        fails += not check("grow %d: la raya va bajo los marcos" % grow,
                           a["div"]["y"] >= TOP_H)
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
