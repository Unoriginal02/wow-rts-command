# -*- coding: utf-8 -*-
"""
click_len.py -- ¿cabe la orden de click en un mensaje de addon?

Un mensaje de addon de 3.3.5a viaja dentro de un mensaje de chat de 255
caracteres: `prefijo` + tabulador + cuerpo. Con "RTS" delante quedan 251, y
`Link.lua` usa 250. Pasarse NO DA ERROR -- el cliente no manda nada, o manda un
trozo -- y en juego eso se lee como "la orden no llego".

ESTE GUION EXISTE POR UN FALLO CONCRETO. `PRUEBAS-24`: *"selecciono al grupo
entero y mando atacar y no atacan; si quito a Kirinah, atacan"*. No era Kirinah:
con cinco unidades, un guid de criatura (16 dígitos hex, sin ceros a la
izquierda que quitar) y el rayo detrás, `CLICK` medía 258 caracteres. Quitar a
CUALQUIERA de los cinco lo bajaba de 255 -- se probó con ella, así que pareció
suya la culpa.

Se comprueba aquí y no en juego porque es aritmética pura: nombres, formatos y
un tope. Correrlo cuesta un segundo; descubrirlo en juego costó una ronda.

    python sim/click_len.py
"""

LIMIT = 250          # ns.Link.LIMIT

# El grupo real de la partida, que es el caso que fallo.
PARTY = ["Neferite", "Avy", "Kirinah", "Secretaria", "Bob"]

# Y el peor caso razonable: cinco nombres del maximo que permite WoW.
WORST = ["Xxxxxxxxxxxx"] * 5

# Teldrassil. Cuatro digitos enteros en X y Z, cuatro en Y: el caso mas largo
# sin signo. Un mapa con coordenadas negativas suma un caracter por numero.
POS = (9944.53, 1071.42, 1327.19)

CREATURE_GUID = "F13000106C000123"   # 16, y ningun cero a la izquierda que quitar
GROUND_GUID = "0"                    # un click al suelo no lleva victima


def fmt(v, dec):
    return ("%." + str(dec) + "f") % v


def click_len(names, dec_pos, dec_dir, guid, with_ray=True, negative=False):
    """El largo exacto del cuerpo que arma Orders:Click."""
    x, y, z = POS
    if negative:
        x, y = -x, -y

    parts = []
    for n in names:
        # "%s %.Nf %.Nf %.Nf" -- el punto de cada unidad, ya con su hueco de
        # formacion sumado (que no cambia el numero de digitos).
        parts.append("%s %s %s %s" % (n, fmt(x, dec_pos), fmt(y, dec_pos), fmt(z, dec_pos)))

    if with_ray:
        # "@ %d %.Nf %.Nf %.Nf %.Mf %.Mf %.Mf %.Nf %.Nf %.Nf"
        parts.append("@ %d %s %s %s %s %s %s %s %s %s" % (
            999,
            fmt(x, dec_pos), fmt(y, dec_pos), fmt(z + 40, dec_pos),
            fmt(-0.98765, dec_dir), fmt(0.12345, dec_dir), fmt(-0.54321, dec_dir),
            fmt(x, dec_pos), fmt(y, dec_pos), fmt(z, dec_pos)))

    return len("CLICK %s %s" % (guid, ";".join(parts)))


def main():
    fails = []

    def check(label, n, ok_expected=True):
        ok = n <= LIMIT
        mark = "OK   " if ok == ok_expected else "FALLA"
        if ok != ok_expected:
            fails.append(label)
        print("  %s %-58s %3d / %d" % (mark, label, n, LIMIT))

    print("=== el formato VIEJO (%.2f / %.5f): es el fallo, tiene que NO caber ===")
    check("5 del grupo + ataque + rayo", click_len(PARTY, 2, 5, CREATURE_GUID), False)
    check("4 (sin Kirinah) + ataque + rayo",
          click_len([n for n in PARTY if n != "Kirinah"], 2, 5, CREATURE_GUID), True)
    check("5 + click al suelo + rayo", click_len(PARTY, 2, 5, GROUND_GUID), True)

    print()
    print("=== el formato NUEVO (%.1f / %.4f) ===")
    check("5 del grupo + ataque + rayo", click_len(PARTY, 1, 4, CREATURE_GUID))
    check("5 + click al suelo + rayo", click_len(PARTY, 1, 4, GROUND_GUID))
    check("5 en mapa de coordenadas negativas",
          click_len(PARTY, 1, 4, CREATURE_GUID, negative=True))
    check("5 nombres de 12 letras + ataque + rayo",
          click_len(WORST, 1, 4, CREATURE_GUID), False)
    check("5 nombres de 12 letras, SIN rayo (la degradacion)",
          click_len(WORST, 1, 4, CREATURE_GUID, with_ray=False), True)

    print()
    if fails:
        print("!! %d comprobacion(es) no salieron como se espera:" % len(fails))
        for f in fails:
            print("   - " + f)
        raise SystemExit(1)
    print("todo cuadra. El caso que fallaba no cabia; con el formato nuevo cabe,")
    print("y el peor caso razonable se apana soltando el rayo.")


if __name__ == "__main__":
    main()
