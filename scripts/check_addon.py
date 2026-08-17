#!/usr/bin/env python3
"""Comprueba el addon RTSCommand antes de darlo por bueno.

Dos cosas, y la segunda es la que importa.

1. SINTAXIS. Que los ficheros parseen.

2. LOCALES USADAS ANTES DE DECLARARSE. Este es el fallo que ya ha costado dos
   rondas de pruebas, las dos veces igual:

       function C:OnState(on)  ...  ReleaseCamera()  ...  end   -- linea 305
       local function ReleaseCamera() ... end                   -- linea 325

   En Lua eso NO es un aviso ni un error de carga. El nombre se compila como una
   busqueda de GLOBAL, encuentra nil, y revienta la primera vez que se ejecuta
   esa rama -- normalmente en mitad de una secuencia, dejandola a medias. La
   primera vez dejo la camara sin soltar; la segunda impidio salir del modo RTS.
   Y como WoW esconde los errores de Lua salvo que actives scriptErrors, el
   sintoma no se parece en nada a la causa.

   El parser no lo detecta porque el fichero es sintacticamente valido. Por eso
   hace falta esto.

Uso:  python check_addon.py
"""

import glob
import os
import re
import sys

# El ORIGINAL, no la copia desplegada en el WoW. Si revisara la copia diria que
# todo esta bien mientras el fichero que acabas de editar esta roto.
ADDON = r"C:\Server\rts-project\addon"

# `local function NAME(`
DECL = re.compile(r"^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
# `local NAME = function(`  -- la otra forma de lo mismo
DECL2 = re.compile(r"^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(")


def strip_comment(line: str) -> str:
    """Quita comentarios de linea. No entiende bloques --[[ ]], que es
    suficiente: una llamada real no vive dentro de uno."""
    i = line.find("--")
    return line if i < 0 else line[:i]


def check_file(path: str):
    problems = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()

    decls = {}
    for n, raw in enumerate(lines, 1):
        line = strip_comment(raw)
        m = DECL.match(line) or DECL2.match(line)
        if m and m.group(1) not in decls:
            decls[m.group(1)] = n

    for name, decl_line in decls.items():
        call = re.compile(r"\b" + re.escape(name) + r"\s*\(")
        for n, raw in enumerate(lines[: decl_line - 1], 1):
            line = strip_comment(raw)
            if call.search(line):
                problems.append(
                    f"  linea {n}: se usa '{name}()' pero se declara como local "
                    f"en la linea {decl_line}\n"
                    f"      -> en tiempo de ejecucion sera un global nil y "
                    f"petara al llamarlo.\n"
                    f"      -> mueve la declaracion por encima de la linea {n}."
                )
                break

    return problems


def main() -> int:
    if not os.path.isdir(ADDON):
        print(f"no encuentro el addon en {ADDON}")
        return 2

    try:
        from luaparser import ast
    except ImportError:
        ast = None
        print("(luaparser no instalado: me salto la comprobacion de sintaxis)")

    files = sorted(glob.glob(os.path.join(ADDON, "*.lua")))
    bad = 0

    for path in files:
        name = os.path.basename(path)

        if ast is not None:
            try:
                ast.parse(open(path, encoding="utf-8").read())
            except Exception as exc:  # noqa: BLE001 - queremos ver cualquiera
                print(f"[SINTAXIS] {name}: {str(exc)[:200]}")
                bad += 1
                continue

        problems = check_file(path)
        if problems:
            bad += 1
            print(f"[ORDEN] {name}")
            for p in problems:
                print(p)

    print()
    if bad:
        print(f"{bad} fichero(s) con problemas de {len(files)}.")
        return 1

    print(f"los {len(files)} ficheros del addon estan bien.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
