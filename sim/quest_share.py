# -*- coding: utf-8 -*-
"""
quest_share.py -- la maquina de estados de Quests.lua, fuera del juego.

Existe porque identificar "que mision acaba de pasar" se ha hecho mal TRES
veces seguidas, y las tres se descubrieron en juego a una ronda cada una:

  1. por el INDICE de `QUEST_ACCEPTED` -- el registro que Lua consulta aun no
     esta escrito, asi que apunta a lo que hubiera antes en ese hueco;
  2. por el TITULO del panel leido dentro del gancho de `AcceptQuest` --
     `hooksecurefunc` corre DESPUES, con el dialogo ya cerrado;
  3. igual, en la entrega, dentro del gancho de `GetQuestReward`.

La version cuatro no lee nada que el cliente pueda haber cambiado ya: mira que
mision es NUEVA (o cual DESAPARECIO) en el registro. Esto lo comprueba.
"""

MANUAL_WINDOW = 2.0
ACCEPT_WINDOW = 10.0


class Addon:
    def __init__(self, log_ids):
        self.log = dict(log_ids)          # id -> titulo, el registro de verdad
        self.logSet = None
        self.shareUntil = None
        self.turnUntil = None
        self.questNpc = None
        self.lastManual = -999.0
        self.now = 0.0
        self.sent = []                    # ("QSHARE"|"QTURN", id)
        self.said = []

    # --- gestos del jugador -------------------------------------------------
    def press_accept(self):
        self.lastManual = self.now
        self.shareUntil = self.now + ACCEPT_WINDOW

    def press_reward(self):
        self.turnUntil = self.now + ACCEPT_WINDOW

    # --- eventos del cliente ------------------------------------------------
    def quest_frame(self, npc):
        self.questNpc = npc

    def quest_accepted(self, stale_title):
        if self.now - self.lastManual > MANUAL_WINDOW:
            self.shareUntil = None
            self.said.append("entro sola: " + str(stale_title))

    def log_update(self):
        now = dict(self.log)
        if self.logSet is None:
            self.logSet = now
            return
        fresh = {i: t for i, t in now.items() if i not in self.logSet}
        gone = {i: t for i, t in self.logSet.items() if i not in now}
        self.logSet = now

        if self.turnUntil and self.now <= self.turnUntil and gone:
            self.turnUntil = None
            if self.questNpc:
                for i in gone:
                    self.sent.append(("QTURN", i))

        if not self.shareUntil or self.now > self.shareUntil:
            return
        if not fresh:
            return
        self.shareUntil = None
        for i in fresh:
            self.sent.append(("QSHARE", i))


def case(name, fn):
    try:
        fn()
        print("  ok   " + name)
        return True
    except AssertionError as e:
        print("  FALLO " + name + ": " + str(e))
        return False


def t_accept_normal():
    a = Addon({12: "vieja"})
    a.log_update()                        # primera foto
    a.quest_frame("npc1")
    a.press_accept()
    a.quest_accepted("vieja")             # indice rancio: apunta a la de antes
    assert a.said == [], "no debe avisar de nada: la aceptaste tu"
    a.log[458] = "La protectora de los bosques"
    a.log_update()
    assert a.sent == [("QSHARE", 458)], a.sent


def t_indice_rancio_habria_fallado():
    # La version 1 mandaba lo que dijera el indice. Se reproduce aqui para que
    # la prueba tenga dientes: si alguien vuelve a ese camino, esto lo canta.
    a = Addon({12: "vieja"})
    a.log_update()
    a.press_accept()
    stale = 12                            # lo que el indice devolvia
    assert stale != 458, "el indice rancio da OTRA mision, que es el fallo"


def t_auto_accept_no_reparte():
    a = Addon({})
    a.log_update()
    a.now = 100.0                         # nadie ha pulsado nada
    a.log[999] = "entra sola"
    a.quest_accepted("entra sola")
    a.log_update()
    assert a.sent == [], a.sent
    assert len(a.said) == 1, a.said


def t_log_update_temprano_no_pierde_la_mision():
    # El refresco puede llegar ANTES de que el servidor haya metido la mision.
    a = Addon({12: "vieja"})
    a.log_update()
    a.press_accept()
    a.log_update()                        # todavia no esta: no hay nada nuevo
    assert a.sent == [], "no debe mandar nada aun"
    a.now += 0.5
    a.log[458] = "nueva"
    a.log_update()
    assert a.sent == [("QSHARE", 458)], a.sent


def t_entrega():
    a = Addon({458: "nueva"})
    a.log_update()
    a.quest_frame("npc1")
    a.press_reward()
    del a.log[458]
    a.log_update()
    assert a.sent == [("QTURN", 458)], a.sent


def t_abandonar_no_entrega():
    a = Addon({458: "nueva"})
    a.log_update()
    del a.log[458]                        # abandonada: nadie pulso Completar
    a.log_update()
    assert a.sent == [], a.sent


def t_plazo_vencido():
    a = Addon({})
    a.log_update()
    a.press_accept()
    a.now += ACCEPT_WINDOW + 1
    a.log[458] = "nueva"
    a.log_update()
    assert a.sent == [], "fuera de plazo no se reparte"


def t_primera_foto_no_reparte():
    a = Addon({1: "a", 2: "b", 3: "c"})
    a.press_accept()
    a.log_update()                        # sin foto previa: todo pareceria nuevo
    assert a.sent == [], a.sent


print("quest_share:")
ok = all([
    case("aceptar reparte la mision buena", t_accept_normal),
    case("el indice rancio apuntaba a otra", t_indice_rancio_habria_fallado),
    case("una que entra sola no se reparte", t_auto_accept_no_reparte),
    case("un refresco temprano no la pierde", t_log_update_temprano_no_pierde_la_mision),
    case("entregar manda QTURN", t_entrega),
    case("abandonar no entrega", t_abandonar_no_entrega),
    case("fuera de plazo no reparte", t_plazo_vencido),
    case("la primera foto no reparte", t_primera_foto_no_reparte),
])
print("todo bien" if ok else "HAY FALLOS")
