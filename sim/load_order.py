# -*- coding: utf-8 -*-
"""
load_order.py -- que el orden del .toc aguante lo que se ejecuta AL CARGAR.

POR QUE EXISTE
==============

Casi todo en este addon corre dentro de una funcion, asi que el orden del `.toc`
da igual: cuando alguien llama a `ns.Camera:On()`, `ns.Camera` lleva rato
existiendo. Pero unas pocas lineas corren EN EL MOMENTO DE CARGAR el fichero, y
esas si dependen del orden:

    ns.Bar:Register(P)              -- Panel.lua, ambito de fichero
    ns.Link:On("DID", function ...) -- Orders.lua, ambito de fichero

Si el `.toc` carga `Panel.lua` antes que `Bar.lua`, eso es un `nil` y el addon
se cae al cargar -- llevandose por delante TODO lo que viniera detras, no solo
ese modulo.

Este guion apareció el 2026-09-02, al hacer que los paneles **se apunten solos**
en vez de estar escritos en una lista dentro de `Bar.lua` (§4 de la revision de
arquitectura). Ese cambio quita un acoplamiento y a cambio crea una dependencia
de ORDEN, que es justo lo que aqui se comprueba: el registro se paga con esto.

LO QUE NO VE `check_addon.py`
=============================

Aquello mira cada fichero por separado -- sintaxis, cadenas sin cerrar, escapes
raros, locales usadas antes de declararse. Esto mira los 24 EN EL ORDEN EN QUE
LOS CARGA EL JUEGO, que es una pregunta distinta y que ningun fichero puede
contestar solo.

Y falla igual de callado que los demas fallos que persigue este proyecto: WoW
esconde los errores de Lua salvo que `scriptErrors` este a 1, asi que un orden
roto se ve como "el modo RTS no hace nada".

LA PARTE FINA: EL CUERPO DE UNA FUNCION NO CUENTA
=================================================

`ns.Print(...)` dentro de `function(rest) ... end` no corre al cargar, corre
cuando llegue el mensaje. La primera version de este guion no lo distinguia y
daba cinco falsos positivos en `Orders.lua` -- todos dentro del manejador de
`DID`. Por eso `scope_nodes` NO baja al cuerpo de ninguna funcion, anonima
incluida.

Un falso positivo aqui seria peor que no tener guion: se aprende a ignorarlo.

TIENE DIENTES
=============

Comprobado moviendo `Panel.lua` delante de `Bar.lua`: dice
`Panel.lua -> ns.Bar no existe todavia`. Una prueba que pasa con el codigo roto
no es una prueba.
"""

import io
import os
import sys

from luaparser import ast, astnodes

ADDON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addon")

FUNCS = (astnodes.Function, astnodes.LocalFunction, astnodes.Method,
         astnodes.AnonymousFunction)


def scope_nodes(stmt):
    """Los nodos que de verdad se ejecutan al cargar el fichero.

    Todo menos el CUERPO de una funcion: al definirla se evalua su nombre y sus
    argumentos por defecto, no lo de dentro.
    """
    out = []

    def walk(node):
        if isinstance(node, FUNCS):
            return
        out.append(node)
        for child in node.__dict__.values():
            if isinstance(child, astnodes.Node):
                walk(child)
            elif isinstance(child, list):
                for item in child:
                    if isinstance(item, astnodes.Node):
                        walk(item)

    walk(stmt)
    return out


def ns_index(node):
    """`ns.Algo` -> "Algo", o None."""
    if (isinstance(node, astnodes.Index)
            and isinstance(node.value, astnodes.Name)
            and node.value.id == "ns"
            and isinstance(node.idx, astnodes.Name)):
        return node.idx.id
    return None


def main():
    toc_path = os.path.join(ADDON, "RTSCommand.toc")
    with io.open(toc_path, encoding="utf-8-sig") as fh:
        files = [line.strip() for line in fh if line.strip().endswith(".lua")]

    defined = set()
    problems = []
    checked = 0

    for name in files:
        path = os.path.join(ADDON, name)
        with io.open(path, encoding="utf-8") as fh:
            tree = ast.parse(fh.read())

        # `ns.X = ...` en cualquier parte del fichero define X para los de
        # detras. En cualquier parte y no solo en el ambito de fichero porque en
        # la practica todos lo hacen arriba del todo, y ser estricto aqui solo
        # daria falsos positivos.
        for node in ast.walk(tree):
            if isinstance(node, astnodes.Assign):
                for target in node.targets:
                    key = ns_index(target)
                    if key:
                        defined.add(key)

        # Y ahora lo que se USA al cargar.
        for stmt in tree.body.body:
            if isinstance(stmt, FUNCS):
                continue
            for node in scope_nodes(stmt):
                key = ns_index(node)
                if key:
                    checked += 1
                    if key not in defined:
                        problems.append((name, key))

    print("%d ficheros del .toc, %d usos de ns.X en ambito de fichero"
          % (len(files), checked))

    if problems:
        for name, key in problems:
            print("  !! %s usa ns.%s antes de que exista" % (name, key))
        print("\nArreglo: mover ese fichero mas abajo en RTSCommand.toc, o el "
              "que define ns.%s mas arriba." % problems[0][1])
        return 1

    print("el orden del .toc aguanta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
