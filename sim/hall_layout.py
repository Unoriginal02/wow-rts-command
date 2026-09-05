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

# TERCERA VERSION, 2026-09-05: LO QUE DIJO `PRUEBAS-23`.
#
#   * "los player frames muy pequenos"  -> la columna y los marcos suben
#   * "muy pegada a las barras de los 5 jugadores" -> el GUTTER de 12 a 48
#   * "los iconos son puto enormes"     -> SLOT_MAX de 112 a 84
#   * "administrar correctamente el espacio" -> el bloque central se CENTRA
#
# CUARTA VERSION, 2026-09-05 (tarde): EL BOCETO RETOCADO.
#
# Medido pixel a pixel sobre la captura retocada, no elegido:
#   * columna 168 px de pantalla   -> 272 de dibujo (era 440)
#   * contenido empieza a 216 px   -> GUTTER 78     (era 48)
#   * separacion entre iconos 9 px -> SLOT_GAP 16   (era 8)
#   * separacion entre macros 18px -> MACRO_GAP 28  (era 8)
#   * la fila de huecos LLENA el ancho: trece en esa captura, no diez
#   * todo pegado a la IZQUIERDA, y la raya mide lo que el bloque
LIST_W   = 272
GUTTER   = 78

ROW_N    = 5      # heroe + cuatro companeros
ROW_GAP  = 4
NAME_H   = 26     # el nombre va ENCIMA de la barra (§3), no dentro
NAME_GAP = 2
POWER_H  = 6      # "linea muy fina, 2-4 px" de pantalla -> 6 de dibujo = 3,4 px
POWER_GAP = 2

TOP_H    = 140    # medido: la raya cae a 154 = TOP_H + DIV_GAP en el boceto
DIV_GAP  = 14     # aire a cada lado de la linea divisoria
DIV_H    = 2

SLOT_GAP = 16
SLOT_MAX = 84     # 112 eran 63 px: un boton de accion entero, y mandaba
SLOT_MIN = 40     # y mas pequeno que esto no se distingue el icono

SPELL_CAP = 20    # el techo de lo que se guarda; la cuenta la decide el ancho
MACRO_N  = 4      # los cuatro macros del estado A
MACRO_H  = 56     # 31 px de pantalla: cabe el texto a fuente 22 de dibujo
MACRO_GAP = 28
MACRO_MIN = 110   # por debajo no cabe "Sigueme": la fila se esconde
VGAP     = 18     # entre la fila de hechizos y la de macros

# --- el estado B, por columna ---------------------------------------------
HEAD_H    = 26    # la cabecera con el nombre
HEAD_GAP  = 6
B_COLS    = 2     # el 2x2
B_ROWS    = 2
B_MACRO_N = 2
B_MACRO_H = 42
B_MACRO_GAP = 12  # entre los dos macros de la columna
B_MID_GAP = 26    # entre el bloque de hechizos y el de macros
B_TOP_PAD = 18    # cuanto baja la columna entera
VDIV_PAD  = 18    # cuanto se queda corta la raya vertical arriba y abajo


def row_layout():
    """Una fila de la columna izquierda: nombre encima, vida, linea de poder."""
    row_h = (HALL_H - ROW_GAP * (ROW_N - 1)) // ROW_N
    hp = row_h - NAME_H - NAME_GAP - POWER_GAP - POWER_H
    return row_h, dict(name=(0, NAME_H),
                       health=(NAME_H + NAME_GAP, hp),
                       power=(NAME_H + NAME_GAP + hp + POWER_GAP, POWER_H))


def content_rect(grow):
    """La zona derecha: lo que queda de la sala tras la columna, MENOS el mismo
    aire por la derecha. Hasta la 0.78.0 llegaba al borde del arte y con la fila
    llena el ultimo hueco acababa pegado al marco."""
    x = LIST_W + GUTTER
    return x, 0, hall_w(grow) - x - GUTTER, HALL_H


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


def state_a(grow, cap=SPELL_CAP):
    """Uno seleccionado: marcos, raya, la fila de huecos que quepa, macros."""
    cx, cy, cw, ch = content_rect(grow)
    top = dict(x=cx, y=cy, w=cw, h=TOP_H)
    div_y = TOP_H + DIV_GAP
    by = div_y + DIV_H + DIV_GAP
    bh = ch - by

    # EL LADO ES FIJO Y LA CUENTA SE CALCULA. Es la vuelta que da el boceto
    # retocado, y la unica forma de llenar el ancho sin agrandar los iconos
    # (que es lo que se acaba de quitar) ni separarlos 37 px.
    side = SLOT_MAX
    room = bh - VGAP - MACRO_H
    if side > room:
        side = room
    if side > cw:
        side = cw
    if FIT_GUARD and side < SLOT_MIN:
        side = 0

    n = 0
    if side:
        n = (cw + SLOT_GAP) // (side + SLOT_GAP)
        n = min(n, cap)
        if n < 1:
            side, n = 0, 0

    spell_w = side * n + SLOT_GAP * (n - 1) if n else 0

    # LOS MACROS SE ALINEAN CON LA FILA DE HECHIZOS, y ese es todo su ancho.
    macro_w = (spell_w - MACRO_GAP * (MACRO_N - 1)) // MACRO_N if spell_w else 0
    if FIT_GUARD and macro_w < MACRO_MIN:
        macro_w = 0
    macro_total = macro_w * MACRO_N + MACRO_GAP * (MACRO_N - 1) if macro_w else 0

    # TODO PEGADO A LA IZQUIERDA, y la raya mide lo que el bloque.
    rule = max(spell_w, macro_total)

    return dict(top=top,
                div=dict(x=cx, y=div_y, w=rule, h=DIV_H),
                spells=dict(x=cx, y=by, side=side, n=n, w=spell_w),
                macros=dict(x=cx, y=by + side + VGAP if side else by,
                            w=macro_w, h=MACRO_H, n=MACRO_N, total=macro_total),
                slack=cw - rule,
                band=dict(y=by, h=bh))


def state_b(grow, ncols):
    """Dos o mas: una columna por personaje, 2x2 de hechizos y 2 macros."""
    cx, cy, cw, ch = content_rect(grow)
    col_w = (cw - GUTTER * (ncols - 1)) // ncols if ncols else 0

    # El alto es el que manda casi siempre, asi que se calcula primero y el
    # ancho solo puede empeorarlo.
    room = ch - B_TOP_PAD - HEAD_H - HEAD_GAP - B_MID_GAP \
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

    # UNA RAYA VERTICAL EN EL CENTRO DE CADA HUECO ENTRE COLUMNAS. Pedida el
    # 2026-09-05: sin ella cinco columnas de botones son una rejilla de veinte.
    vdiv = [dict(x=cols[i]["x"] - GUTTER // 2 - 1, w=2,
                 y=VDIV_PAD, h=HALL_H - VDIV_PAD * 2)
            for i in range(1, ncols)]

    # LOS MACROS DEL ESTADO B OCUPAN LA COLUMNA ENTERA, y eso es una desviacion
    # del boceto dicha a proposito. Alli tienen el ancho del bloque 2x2, pero
    # las proporciones reales no son las del papel: con `grow` 4 y cinco
    # columnas el bloque mide 216 dentro de una columna de 385, o sea 169 px de
    # hueco muerto a los lados por columna. Un macro es una barra de TEXTO --
    # cuanto mas ancha, mejor se lee -- asi que llenar la columna no cuesta nada
    # y el bloque 2x2 se centra encima.
    return dict(cols=cols, col_w=col_w, side=side, grid_w=grid_w, vdiv=vdiv,
                macro_w=col_w, macro_h=B_MACRO_H,
                total_h=B_TOP_PAD + HEAD_H + HEAD_GAP + side * B_ROWS + SLOT_GAP * (B_ROWS - 1)
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
    # LA SEPARACION SE MIDE EN PIXELES DE PANTALLA, que es donde se vio el
    # fallo: 12 de dibujo son 7 px, y eso no separa nada.
    fails += not check("la columna respira contra el contenido",
                       round(GUTTER * 0.562) >= 20,
                       "%d dibujo -> %.0f px" % (GUTTER, GUTTER * 0.562))
    fails += not check("un icono de hechizo no es mayor que un boton de accion",
                       round(SLOT_MAX * 0.562) < 62,
                       "%d dibujo -> %.0f px" % (SLOT_MAX, SLOT_MAX * 0.562))

    print()
    print("=== estado A: la fila llena el ancho, cuatro macros ===")
    for grow in range(1, 6):
        a = state_a(grow)
        cx, _, cw, ch = content_rect(grow)
        sp, mc = a["spells"], a["macros"]
        right = max(sp["x"] + sp["w"], mc["x"] + mc["total"])
        bottom = (mc["y"] + mc["h"]) if sp["side"] else a["band"]["y"]
        fits = right <= cx + cw and bottom <= ch
        print("  grow %d  %2d huecos de %3s (fila %4d)  macro %4dx%d  "
              "sobra %3d  borde %5d/%5d  fondo %3d/%3d %s"
              % (grow, sp["n"], sp["side"] or "-", sp["w"], mc["w"], mc["h"],
                 a["slack"], right, cx + cw, bottom, ch,
                 "" if fits else "  <-- SE SALE"))
        fails += not check("  cabe entero", fits)
        if sp["side"]:
            # PEGADO A LA IZQUIERDA. Los cuatro bordes izquierdos de la zona --
            # marcos, raya, hechizos, macros -- son el MISMO, y eso es lo que
            # hace que se lea como un bloque. Un centrado a medias se ve igual
            # de bien en el `grow` que se mira y descuadrado en los otros.
            fails += not check("  la fila empieza en el borde de la zona",
                               sp["x"] == cx, "%d vs %d" % (sp["x"], cx))
            fails += not check("  hechizos, macros y raya comparten borde",
                               sp["x"] == mc["x"] == a["div"]["x"])
            # Y LLENA: lo que sobra no puede dar para otro hueco entero, o la
            # cuenta esta mal hecha y el hueco de la derecha es un fallo.
            #
            # SALVO QUE EL TOPE SEA EL QUE MANDA, que es un caso distinto y hay
            # que distinguirlo: con `grow` 5 caben veintitres y `SPELL_CAP` son
            # veinte, asi que sobran 424 A PROPOSITO. Sin esta rama la prueba
            # diria "falla" sobre la unica decision deliberada del reparto.
            capped = sp["n"] >= SPELL_CAP
            fails += not check("  llena el ancho (o le frena el tope)",
                               capped or a["slack"] < sp["side"] + SLOT_GAP,
                               "sobran %d, un hueco son %d%s" % (
                                   a["slack"], sp["side"] + SLOT_GAP,
                                   ", topado en %d" % SPELL_CAP if capped else ""))
            fails += not check("  los macros se alinean con los hechizos",
                               mc["total"] == 0 or abs(mc["total"] - sp["w"]) <= 3,
                               "%d vs %d" % (mc["total"], sp["w"]))
            fails += not check("  la raya mide lo que el bloque, no la zona",
                               a["div"]["w"] == max(sp["w"], mc["total"]))
            fails += not check("  la fila de macros no pisa la de hechizos",
                               sp["y"] + sp["side"] <= mc["y"])
            # EL MISMO AIRE A LOS DOS LADOS. Sin esto, la fila llena llega al
            # borde del arte y el ultimo hueco se ve recortado en vez de
            # ajustado -- que es como se vio en juego.
            derecha = hall_w(grow) - (sp["x"] + sp["w"])
            fails += not check("  queda aire a la derecha, como a la izquierda",
                               derecha >= GUTTER,
                               "%d a la derecha, %d a la izquierda" % (derecha, GUTTER))
            fails += not check("  o los macros caben, o no hay ninguno",
                               mc["w"] == 0 or mc["w"] >= MACRO_MIN,
                               "macro %d, minimo %d" % (mc["w"], MACRO_MIN))

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
            # LA COLUMNA BAJA. Pedido mirandola: el nombre iba pegado al borde.
            fails += not check("    grow %d: la columna arranca mas abajo del borde" % grow,
                               B_TOP_PAD >= 12, "%d de aire arriba" % B_TOP_PAD)
            # Y LOS TRES BLOQUES SE SEPARAN ENTRE SI. Cuatro cosas apiladas sin
            # aire se leen como una sola, que es lo que se reporto.
            fails += not check("    grow %d: el 2x2 no toca los macros" % grow,
                               B_MID_GAP >= SLOT_GAP, "%d >= %d" % (B_MID_GAP, SLOT_GAP))
            fails += not check("    grow %d: los dos macros no se tocan" % grow,
                               B_MACRO_GAP >= 8, "%d" % B_MACRO_GAP)
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
    print("  las rayas verticales entre seleccionados:")
    for grow in (2, 4):
        b = state_b(grow, 5)
        print("    grow %d -> %d rayas en x %s"
              % (grow, len(b["vdiv"]), [v["x"] for v in b["vdiv"]]))
        fails += not check("    grow %d: una raya menos que columnas" % grow,
                           len(b["vdiv"]) == len(b["cols"]) - 1)
        for k, v in enumerate(b["vdiv"]):
            izq = b["cols"][k]
            der = b["cols"][k + 1]
            # NI TOCA NI PISA. Una raya pegada a una columna se lee como su
            # borde, y la asimetria se nota antes que la raya.
            fails += not check("    grow %d: la raya %d va DENTRO del hueco" % (grow, k + 1),
                               izq["x"] + izq["w"] < v["x"] and v["x"] + v["w"] < der["x"],
                               "%d..%d entre %d y %d" % (v["x"], v["x"] + v["w"],
                                                         izq["x"] + izq["w"], der["x"]))
            centro = (izq["x"] + izq["w"] + der["x"]) // 2
            fails += not check("    grow %d: la raya %d esta centrada" % (grow, k + 1),
                               abs((v["x"] + v["w"] // 2) - centro) <= 2,
                               "%d vs %d" % (v["x"] + v["w"] // 2, centro))

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
