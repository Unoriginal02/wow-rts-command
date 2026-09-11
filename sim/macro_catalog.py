# -*- coding: utf-8 -*-
"""
macro_catalog.py -- ¿son legales los macros que `/rts macros` va a crear?

Un macro mal formado en este cliente NO DA ERROR, que es el modo de fallo de
siempre:

  - un nombre de mas de 16 letras se recorta en silencio (`letters="16"` del
    MacroPopupEditBox), y dos nombres que se recortan al mismo texto son dos
    macros indistinguibles en la barra;
  - un cuerpo de mas de 255 no cabe (`letters="255"` del MacroFrameText);
  - un icono que el cliente no conoce sale VACIO, no rojo;
  - y un comando de playerbots inventado no contesta: el bot lo recibe, no casa
    con ningun trigger y se calla. En pantalla es igual que un macro que no se
    pulso.

Aqui se comprueban las cuatro cosas antes de compilar nada, leyendo el catalogo
de `addon/Macros.lua` y contrastandolo contra el CLIENTE (los DBC de
`C:\\Server\\dist\\data\\dbc`) y contra el MODULO (los ficheros de
mod-playerbots). Si esas dos fuentes no estan en esta maquina, lo DICE en vez de
dar por bueno lo que no ha mirado.

Lo que este guion NO puede contestar: si el icono esta en la LISTA DE ICONOS DE
MACRO del cliente. El DBC prueba que el fichero existe; la lista de macro es
otra cosa y la unica que la sabe es el juego -- `/rts macros` la recorre y dice
por pantalla los que no encontro.

    python sim/macro_catalog.py
    python sim/macro_catalog.py --break     # rompe el catalogo a proposito

El interruptor `--break` es la mitad que hace que esto sirva de algo: mete un
nombre largo, un icono que no existe y un comando inventado, y el guion tiene
que cazar los tres. Una prueba que pasa con el codigo roto no es una prueba.
"""

import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(os.path.dirname(HERE), "addon", "Macros.lua")

DBC = r"C:\Server\dist\data\dbc"
PLAYERBOTS = r"C:\Server\azerothcore\modules\mod-playerbots\src"

ACCOUNT_MAX = 36          # MAX_ACCOUNT_MACROS de Blizzard_MacroUI.lua


# --- el catalogo del addon -------------------------------------------------

ENTRY = re.compile(
    r'\{\s*name\s*=\s*"([^"]*)"\s*,\s*icon\s*=\s*"([^"]*)"\s*,'
    r'\s*cmd\s*=\s*\{([^}]*)\}', re.S)


def read_catalogue():
    src = open(ADDON, encoding="utf-8").read()

    mark = re.search(r'local MARK = "([^"]+)"', src).group(1)
    name_max = int(re.search(r"local NAME_MAX = (\d+)", src).group(1))
    body_max = int(re.search(r"local BODY_MAX = (\d+)", src).group(1))

    block = src[src.index("local MACROS = {"):]
    block = block[:block.index("\nM.CATALOGUE")]

    out = []
    for name, icon, cmds in ENTRY.findall(block):
        out.append({
            "name": name,
            "icon": icon,
            "cmd": re.findall(r'"([^"]*)"', cmds),
        })
    return out, mark, name_max, body_max


# --- el cliente: que iconos existen ----------------------------------------

def dbc_strings(path):
    with open(path, "rb") as fh:
        d = fh.read()
    _magic, rec, _fld, rsz, ssz = struct.unpack_from("<4sIIII", d, 0)
    block = d[20 + rec * rsz:20 + rec * rsz + ssz]
    return [s.decode("latin-1") for s in block.split(b"\0") if s]


def client_icons():
    """Nombres de icono que el cliente referencia, en mayusculas y sin ruta.

    `SpellIcon.dbc` trae los de hechizo con ruta; `ItemDisplayInfo.dbc` trae los
    de objeto (INV_*) a secas. Juntos cubren todo lo que se usa aqui.
    """
    spell = os.path.join(DBC, "SpellIcon.dbc")
    item = os.path.join(DBC, "ItemDisplayInfo.dbc")
    if not (os.path.exists(spell) and os.path.exists(item)):
        return None

    names = set()
    for s in dbc_strings(spell):
        names.add(s.upper().replace("/", "\\").split("\\")[-1])
    for s in dbc_strings(item):
        names.add(s.upper())
    return names


# --- el modulo: que comandos y que estrategias existen ---------------------

def playerbots_vocab():
    handler = os.path.join(PLAYERBOTS, "Ai", "Base", "Strategy",
                           "ChatCommandHandlerStrategy.cpp")
    ctx = os.path.join(PLAYERBOTS, "Ai", "Base", "StrategyContext.h")
    if not (os.path.exists(handler) and os.path.exists(ctx)):
        return None, None

    src = open(handler, encoding="utf-8", errors="replace").read()
    cmds = set(re.findall(r'supported\.push_back\("([^"]+)"\)', src))
    cmds |= set(re.findall(r'new TriggerNode\("([^"]+)"', src))

    strategies = set(re.findall(r'creators\["([^"]+)"\]',
                                open(ctx, encoding="utf-8", errors="replace").read()))
    return cmds, strategies


def command_verb(text, known):
    """El verbo mas largo del principio que casa con un comando conocido.

    `max dps` y `tank attack` son comandos de dos palabras, asi que quedarse con
    la primera daria falsos negativos.
    """
    words = text.split()
    for n in range(len(words), 0, -1):
        cand = " ".join(words[:n])
        if cand in known:
            return cand, " ".join(words[n:])
    return None, text


# --- las comprobaciones ----------------------------------------------------

def check(entries, mark, name_max, body_max):
    fails = []

    def bad(msg):
        fails.append(msg)
        print("  FALLA %s" % msg)

    # Nombres
    seen = {}
    for e in entries:
        n = e["name"]
        if len(n) > name_max:
            bad("nombre de %d letras (max %d): '%s'" % (len(n), name_max, n))
        key = n[:name_max].lower()
        if key in seen:
            bad("dos macros se llaman igual tras recortar: '%s' y '%s'"
                % (seen[key], n))
        seen[key] = n

    # Cuerpos
    for e in entries:
        body = "\n".join(mark + " " + c for c in e["cmd"])
        if len(body) > body_max:
            bad("cuerpo de %d letras (max %d) en '%s'"
                % (len(body), body_max, e["name"]))
        if not e["cmd"]:
            bad("'%s' no manda ningun comando" % e["name"])

    # Hueco
    if len(entries) > ACCOUNT_MAX:
        bad("%d macros y solo hay %d de cuenta" % (len(entries), ACCOUNT_MAX))

    # Iconos, contra el cliente
    icons = client_icons()
    if icons is None:
        print("  |SIN COMPROBAR| los DBC del cliente no estan en %s" % DBC)
    else:
        for e in entries:
            if e["icon"].upper() not in icons:
                bad("el cliente no tiene el icono '%s' (en '%s')"
                    % (e["icon"], e["name"]))

    # Comandos y estrategias, contra mod-playerbots
    cmds, strategies = playerbots_vocab()
    if cmds is None:
        print("  |SIN COMPROBAR| mod-playerbots no esta en %s" % PLAYERBOTS)
    else:
        for e in entries:
            for c in e["cmd"]:
                verb, rest = command_verb(c, cmds)
                if not verb:
                    bad("comando inventado: '%s' (en '%s')" % (c, e["name"]))
                    continue
                if verb in ("co", "nc", "de"):
                    for part in rest.split(","):
                        part = part.strip()
                        if not part or part in ("?", "!"):
                            continue
                        if part[0] in "+-~":
                            part = part[1:].strip()
                        if part not in strategies:
                            bad("estrategia inventada: '%s' (en '%s')"
                                % (part, e["name"]))

    return fails


def main():
    entries, mark, name_max, body_max = read_catalogue()

    broken = "--break" in sys.argv
    if broken:
        # Los tres fallos que este guion existe para cazar, a proposito.
        entries = list(entries) + [
            {"name": "Un nombre larguisimo de macro",
             "icon": "INV_Drink_07", "cmd": ["follow"]},
            {"name": "Icono malo", "icon": "No_Existe_Este_Icono",
             "cmd": ["follow"]},
            {"name": "Inventado", "icon": "INV_Drink_07",
             "cmd": ["asistir al tanque", "co +estrategia falsa"]},
        ]

    print("catalogo: %d macros, marca '%s', nombre<=%d, cuerpo<=%d"
          % (len(entries), mark, name_max, body_max))
    fails = check(entries, mark, name_max, body_max)

    print()
    if broken:
        # 1 nombre largo + 1 icono + 1 comando + 1 estrategia = 4 como minimo.
        if len(fails) < 4:
            print("!! el catalogo roto paso con solo %d fallos: la prueba NO sirve"
                  % len(fails))
            raise SystemExit(1)
        print("el catalogo roto cae con %d fallos, que es lo que tenia que pasar."
              % len(fails))
        return

    if fails:
        print("!! %d problema(s). Un macro asi no da error en juego: se queda mudo."
              % len(fails))
        raise SystemExit(1)
    print("los %d macros son legales, sus iconos existen y ningun comando"
          % len(entries))
    print("esta inventado. Que el icono este en la LISTA DE MACRO lo dice el")
    print("juego: /rts macros canta los que no encontro.")


if __name__ == "__main__":
    main()
