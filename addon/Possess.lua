--[[
	Possess.lua -- jugar como uno de tus bots.

	`PRUEBAS-20` D, y es una correccion de rumbo: *"controlar al bot se refiere a
	poner la camara a ese bot y controlarlo como si estuvieramos en modo de juego
	normal, con WASD para moverlo, click derecho para interactuar"*.

	Sales del modo RTS y tomas el mando del bot. La camara se pone detras de el,
	WASD lo mueve, y sus hechizos salen en la barra de posesion. Una tecla te
	devuelve a donde estabas.

	=== LA MAQUINARIA YA ESTABA, Y LLEVABA UN ANO SIN LLAMANTE ==============

	`rts::orders::PossessBot` existe desde la etapa 6: es
	`Unit::SetCharmedBy(charmer, CHARM_TYPE_POSSESS)`, la misma llamada con la
	que la camara RTS toma su criatura invisible, apuntada a un `Player` en vez
	de a una criatura (`Unit.cpp:14610` lo permite explicitamente).

	El primer plano se descarto el 2026-08-16 y la maquinaria se quedo escrita
	"por si vuelve". Ha vuelto. Es la unica vez en este proyecto que dejar codigo
	sin llamante ha salido a cuenta, y salio a cuenta porque estaba DOCUMENTADO
	por que se dejaba -- no escondido detras de un interruptor.

	=== EL ORDEN IMPORTA, Y ES LA PARTE QUE PUEDE ROMPER EL CLIENTE =========

	La camara RTS **tambien** posee (su criatura invisible), y un cliente no
	puede estar poseyendo dos cosas. Asi que primero se suelta el modo RTS
	entero -- que devuelve el control a tu personaje -- y solo entonces se toma
	el bot.

	Hacerlo al reves deja el `PLAYER_FARSIGHT` apuntando a algo que se despawnea,
	y eso es exactamente el ERROR #134 de la etapa 6: *"must immediately set seer
	back otherwise may crash"*, avisado dos veces por el propio nucleo.

	=== LO QUE ESTO **NO** DA, DICHO POR DELANTE ===========================

	La posesion cambia quien te MUEVE, no quien ERES. Los manejadores de
	interaccion del nucleo trabajan sobre `_player` -- tu personaje -- y no sobre
	el `m_mover`:

	  * `HandleGossipHelloOpcode` -> `GetPlayer()->GetNPCIfCanInteractWith(...)`
	  * lo mismo el vendedor, el entrenador, el botin y las misiones.

	O sea que **click derecho sobre un PNJ mientras posees habla con TU
	personaje**, que esta parado en otro sitio, y falla por distancia. Moverse,
	pelear y lanzar los hechizos del bot SI funcionan, porque eso va por el
	mover.

	Para la otra mitad estan las ventanas que ya existen (`/rts npc`,
	`/rts quests`), que hacen la interaccion en nombre del bot desde el servidor.
	No es casualidad que no se borraran.

	La unica forma de tener las dos mitades de verdad es el cambio de personaje
	de sesion sin pantalla de carga, que es un modulo de servidor entero y otra
	conversacion.
]]

local ADDON, ns = ...

local P = {}
ns.Possess = P

P.who = nil          -- nombre del bot que llevas, segun el SERVIDOR
P.returnToRTS = false

--- Tomar y soltar ----------------------------------------------------------

function P:Take(name)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800jugar como:|r hace falta mod-rts.")
		return
	end

	name = name or ns.Selection:GetPrimary()
	if not name or name == "" or name == ns.MyName() then
		ns.Print("|cffff8800jugar como:|r elige un compañero primero " ..
		         "(pinchale, o |cffffff00/rts play <nombre>|r).")
		return
	end

	if self.who then
		ns.Print("|cffff8800jugar como:|r ya llevas a " .. self.who ..
		         "; suelta primero (|cffffff00/rts play|r).")
		return
	end

	-- EL MODO RTS SE SUELTA ENTERO Y PRIMERO. Ver la cabecera: dos posesiones a
	-- la vez es como se llega al ERROR #134.
	self.returnToRTS = ns.RTSMode.active and true or false
	if ns.RTSMode.active then ns.RTSMode:Toggle() end

	-- LO QUE GARANTIZA EL ORDEN ES EL CANAL, NO UN RETRASO.
	--
	-- Soltar el modo apaga la camara pidiendoselo al servidor (`CAM OFF`), y
	-- esta orden tiene que llegar DETRAS de esa: si se cruzaran, el servidor
	-- poseeria el bot y acto seguido devolveria el control al apagar la camara.
	--
	-- No hace falta esperar a nada. Los dos mensajes van por el mismo canal de
	-- addon, en orden, y el servidor los procesa en orden. Un `WhenServer` aqui
	-- se ejecutaria EN EL ACTO -- el servidor ya ha contestado hace rato -- asi
	-- que no aplazaria nada y solo pareceria que si, que es peor que no tenerlo.
	ns.SendServer("POSSESS " .. name)
end

function P:Release()
	if not self.who then
		ns.Print("jugar como: no llevas a nadie.")
		return
	end
	ns.SendServer("POSSESS")
end

function P:Toggle(name)
	if self.who then self:Release() else self:Take(name) end
end

--- Lo que dice el servidor -------------------------------------------------

function P:OnState(on, name)
	if on then
		self.who = name
		ns.Print(("|cff00ff00Llevas a %s.|r WASD lo mueve, sus hechizos estan en la " ..
		          "barra de posesion. |cffffff00/rts play|r para soltarlo."):format(name))
		ns.Print("|cff888888Hablar con PNJs sigue yendo por tu personaje: usa " ..
		         "/rts npc y /rts quests para eso.|r")
		return
	end

	local was = self.who
	self.who = nil
	if was then
		ns.Print(("|cff00ff00Sueltas a %s.|r"):format(was))
	end

	-- Se vuelve a donde estabas. Si entraste desde el modo RTS, vuelves al modo
	-- RTS; si no, te quedas donde estas. Devolver siempre al RTS seria decidir
	-- por el jugador, y devolver nunca haria que la tecla no sea reversible.
	if self.returnToRTS then
		self.returnToRTS = false
		if not ns.RTSMode.active then ns.RTSMode:Toggle() end
	end
end

function P:Create()
	if self.created then return end
	self.created = true

	ns.Link:On("POSSESS", function(rest)
		-- DOS SENTIDOS: mandamos "POSSESS" o "POSSESS <nombre>" y nos lo oimos
		-- de vuelta. La respuesta SIEMPRE empieza por 0 o 1, y nuestra peticion
		-- nunca -- un nombre de personaje no puede ser un digito suelto.
		local flag, name = rest:match("^([01])%s*(.*)$")
		if not flag then return end
		P:OnState(flag == "1", name ~= "" and name or nil)
	end)
end

function P:Report()
	if self.who then
		ns.Print(("jugar como: llevas a |cff33ccff%s|r."):format(self.who))
	else
		ns.Print("jugar como: nadie. |cffffff00/rts play <nombre>|r, o selecciona " ..
		         "a uno y |cffffff00/rts play|r.")
	end
end
