# -*- coding: utf-8 -*-
"""
dbc_spellbook.py -- ¿el filtro del libro de hechizos separa lo bueno de lo raro?

`mod-rts` manda al desplegable de la consola todo lo que el bot sabe, y
`GetSpellMap()` trae bastante mas de lo que el cliente dibuja en el libro. En un
sacerdote de nivel 3 salian *Duelo*, *Objetivo sin honor*, *Cerrando* (x3),
*Activar especializacion* y *Atacar automaticamente*.

`RtsCommandMode.cpp::InSpellBook` los descarta con esta regla:

    se descarta si TODAS sus lineas de SkillLineAbility son de la categoria
    SKILL_CATEGORY_GENERIC (12), que en SkillLineCategory.dbc se llama
    literalmente "Not Displayed"

Este guion la comprueba contra los DBC de verdad, que es de donde salio. Corre
fuera del juego y en un segundo; descubrirlo en juego cuesta una ronda.

DOS TRAMPAS QUE COSTARON TIEMPO Y CONVIENE NO REPETIR:

  * el `Spell.dbc` de `dist\\data\\dbc` esta en **ingles** aunque el cliente lo
    ensene en espanol -- son ficheros distintos, y buscar "Duelo" no encuentra
    nada;
  * el nombre esta en el campo **136** de 234.

    python sim/dbc_spellbook.py
"""

import os
import struct
import sys

DBC = r"C:\Server\dist\data\dbc"

# Lo que salia en la captura de PRUEBAS (nombres ingleses del DBC), y lo que
# tiene que sobrevivir. Si un dia el filtro cambia, esto es lo que decide.
JUNK = [
    "Duel", "Honorless Target", "Closing",
    "Activate Primary Spec", "Activate Secondary Spec", "Auto Attack",
]
KEEP = [
    "Smite", "Lesser Heal", "Shadowmeld", "Power Word: Fortitude",
    "Battle Shout", "Heroic Strike", "Arcane Intellect", "Mark of the Wild",
]

SKILL_CATEGORY_GENERIC = 12       # SharedDefines.h, y "Not Displayed" en el DBC
NAME_FIELD = 136                  # Spell.dbc, SpellName[0]


def read_dbc(name):
    path = os.path.join(DBC, name)
    if not os.path.exists(path):
        print("no encuentro %s -- ¿esta extraido el cliente?" % path)
        sys.exit(2)
    d = open(path, "rb").read()
    magic, rec, fields, recsize, _ = struct.unpack_from("<4sIIII", d, 0)
    if magic != b"WDBC":
        print("%s no es un DBC" % name)
        sys.exit(2)
    rows = [struct.unpack_from("<%dI" % fields, d, 20 + i * recsize) for i in range(rec)]
    return rows, d[20 + rec * recsize:]


def main():
    # categoria de cada linea de habilidad
    lines, _ = read_dbc("SkillLine.dbc")
    category = dict((r[0], r[1]) for r in lines)

    # spell -> lineas de las que cuelga
    sla_rows, _ = read_dbc("SkillLineAbility.dbc")
    hangs = {}
    for r in sla_rows:
        hangs.setdefault(r[2], []).append(r[1])

    # id -> nombre
    spells, blob = read_dbc("Spell.dbc")

    def text(off):
        if off <= 0 or off >= len(blob):
            return ""
        return blob[off:blob.index(b"\x00", off)].decode("utf-8", "replace")

    def in_book(spell_id):
        """El mismo predicado que InSpellBook en RtsCommandMode.cpp."""
        for line in hangs.get(spell_id, ()):
            if category.get(line) != SKILL_CATEGORY_GENERIC:
                return True
        return False

    by_name = {}
    for r in spells:
        nm = text(r[NAME_FIELD])
        if nm:
            by_name.setdefault(nm, []).append(r[0])

    fails = []

    def check(name, expect_in_book):
        ids = by_name.get(name)
        if not ids:
            print("  |    %-26s (no esta en este Spell.dbc)" % name)
            return
        # El id mas bajo es el del jugador; los altos son copias de criaturas.
        sid = min(ids)
        got = in_book(sid)
        ok = (got == expect_in_book)
        if not ok:
            fails.append(name)
        print("  %s %-26s id %-6d en el libro: %-3s (se esperaba %s)" % (
            "OK   " if ok else "FALLA", name, sid,
            "SI" if got else "no", "SI" if expect_in_book else "no"))

    print("=== lo que tiene que CAER (salia en el desplegable y no debia) ===")
    for n in JUNK:
        check(n, False)

    print()
    print("=== lo que tiene que QUEDARSE ===")
    for n in KEEP:
        check(n, True)

    print()
    total = len(hangs)
    hidden = sum(1 for s in hangs if not in_book(s))
    print("de %d hechizos con linea de habilidad, %d cuelgan SOLO de la oculta (%.1f%%)"
          % (total, hidden, 100.0 * hidden / max(1, total)))

    if fails:
        print()
        print("!! %d no salieron como se espera: %s" % (len(fails), ", ".join(fails)))
        raise SystemExit(1)
    print("la regla separa las dos listas.")


if __name__ == "__main__":
    main()
