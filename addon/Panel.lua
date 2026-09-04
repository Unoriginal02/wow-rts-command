--[[
	Panel.lua -- la rejilla de ordenes, a la derecha de la sala.

	Rejilla 4x4: quince ordenes AL GRUPO ENTERO y, en la casilla doce, salir
	del modo RTS.
	Celda 105, paso 113.

	LA CUARTA FILA HA SIDO DOS COSAS Y AHORA ES LA BUENA. Durante una ronda
	fueron los botones pequenos del cliente: funcionaban (PRUEBAS-13 A3/A4/A6) y
	aun asi era el sitio equivocado, y se fueron a los railes verticales con toda
	su maquinaria detras (Rails.lua). Lo que la ocupa ahora son cuatro ordenes
	mas -- que es para lo que la rejilla crecio.

	SALIR NO SE MUEVE DE LA CASILLA DOCE. Sigue al final de la tercera fila,
	donde ha estado desde que existe, aunque ahora tenga una fila debajo: lo que
	ya esta aprendido no cambia de sitio por crecer la rejilla. Es la misma regla
	que se aplico cuando la cuarta fila eran los botones del cliente.

	LAS CUATRO NUEVAS SON LAS DEL GRUPO ENTERO DE LO QUE LA CARTA HACE POR
	SELECCION, y no son inventadas: `tank attack`, `drink`, `rti` y `rti cc` son
	verbos de playerbots que ya usa Card.lua. Las dos marcas son las que
	sustituyeron a la fila de ocho -- craneo para matar, luna para controlar --
	y en el panel tienen MAS sentido que en la carta, porque `rti` es del grupo
	por naturaleza: la marca dice a quien va todo el mundo.

	SIEMPRE AL GRUPO ENTERO, DESDE 2026-09-04, Y ESO DESHACE UNA DECISION.

	Del 24 de agosto al 4 de septiembre esta rejilla tuvo DOS ALCANCES: con algo
	seleccionado la orden iba a lo seleccionado, sin nada al grupo. Estaba
	pensado y estaba senalizado -- las ordenes que respetaban la seleccion
	sacaban su etiqueta en azul y decian a cuantos iban en el tooltip.

	El brief de la barra de control lo cierra en el otro sentido (§6 y §8):
	*"la rejilla afecta siempre a todo el grupo, con independencia de que
	personajes esten seleccionados"*. Y tiene sentido con la consola nueva
	delante, que es lo que ha cambiado: **ahora hay un sitio donde mandar a UNO**
	-- los cuatro botones de accion de la sala, que aplican solo al personaje
	seleccionado. Antes no lo habia, y por eso esta rejilla hacia las dos cosas.

	Un boton que hace dos cosas segun un estado que esta en otra parte de la
	pantalla es ambiguo aunque se senalice; que la rejilla sea LO GLOBAL y la
	sala LO PARTICULAR es una regla que se dice en una frase y no hay que leer
	en un color.

	CINCO CASILLAS NO SON ORDENES Y SE QUEDAN COMO ESTAN. Formar abre una lista,
	Salir sale del modo, Control cambia o posee a UN personaje -- por definicion
	uno -- y las dos marcas ponen un icono en TU objetivo. Ninguna manda una
	orden al grupo, asi que "siempre al grupo" no les dice nada.

	SALIR ES UN BOTON Y NO UNA TECLA MAS porque el modo RTS esconde la interfaz
	de Blizzard: si algo va mal, "donde estaba la tecla" es justo lo que no se
	recuerda. Un boton en una esquina fija se encuentra mirando.

	LA FORMACION ABRE UNA LISTA porque es la unica orden con nueve variantes
	(`Orders.FORMATIONS`, que sale de la fuente de playerbots). Nueve casillas
	mas no caben, y elegir tres de las nueve a mano seria decidir por el jugador.

	LA LISTA CUELGA DEL PANEL, no de UIParent, para que herede su escala: un
	desplegable a escala de UIParent al lado de arte a escala de pixel se ve como
	de otro juego. Y no hay recorte que la corte -- en 3.3.5a un frame hijo puede
	salirse de su padre sin mas.
]]

local ADDON, ns = ...

local P = {}
ns.Panel = P

P.active = false

local host, buttons, flyout = nil, {}, nil

local I = {
	follow = "Interface\\Icons\\Ability_Rogue_Sprint",
	taunt  = "Interface\\Icons\\Ability_Defend",
	drink  = "Interface\\Icons\\INV_Drink_07",
	hold   = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	attack = "Interface\\Icons\\Ability_Warrior_Cleave",
	reset  = "Interface\\Icons\\Spell_Nature_TimeStop",
	control= "Interface\\Icons\\Spell_Shadow_Possession",
	form   = "Interface\\Icons\\Ability_Warrior_BattleShout",
	rally  = "Interface\\Icons\\Ability_Warrior_Charge",
	rage   = "Interface\\Icons\\Ability_Warrior_InnerRage",
	grind  = "Interface\\Icons\\INV_Sword_04",
	loot   = "Interface\\Icons\\INV_Misc_Bag_10",
	revive = "Interface\\Icons\\Spell_Holy_Resurrection",
	exit   = "Interface\\Icons\\Spell_ChargeNegative",
}

--- Las marcas de banda ----------------------------------------------------
--
-- El icono de marca es un dibujo entero, no un icono con borde: se dibuja sin
-- recortar o se le come la punta.
local function MarkIcon(index)
	return ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"):format(index)
end

-- `SetRaidTarget` es el nombre en 3.3.5a; hay wikis que hablan de
-- `SetRaidTargetIcon`. Se coge la que exista de verdad en ESTE cliente en vez de
-- elegir una y descubrir que no esta cuando el boton no haga nada.
local function PutIcon(index)
	local f = SetRaidTarget or SetRaidTargetIcon
	if not f then return false end
	if not UnitExists("target") then return false end
	f("target", index)
	return true
end

-- Las dos mitades del gesto: el icono en tu objetivo, y la orden al grupo. En el
-- panel va por `Broadcast` y no por `Send` -- una marca que solo obedece la
-- seleccion no es una marca, es una orden mas.
local function MarkAction(cc)
	local key   = cc and "moon" or "skull"
	local index = cc and 5 or 8
	local puesto = PutIcon(index)

	ns.Orders:Broadcast((cc and "rti cc " or "rti ") .. key,
		cc and "controlar: luna" or "objetivo: craneo")

	if not puesto then
		ns.Print("sin objetivo: la marca no se ha puesto en nadie.")
	end
end

--- El alcance --------------------------------------------------------------
--
-- UNA orden, UN destino: el grupo entero. Ver la cabecera -- el alcance doble
-- se fue el 2026-09-04 porque la sala ya tiene los botones que mandan a uno.
--
-- Se queda como funcion de una linea y no se llama a `Broadcast` directamente
-- desde las quince casillas: si algun dia vuelve a haber matices de alcance, el
-- sitio donde ponerlos es este y no quince.
local function Dispatch(command, label)
	return ns.Orders:Broadcast(command, label)
end

--- Las dieciseis casillas -------------------------------------------------
--
-- En orden de rejilla: 1..4 la primera fila, 5..8 la segunda, 9..12 la tercera,
-- 13..16 la cuarta.
--
-- La 12 es la de SALIR y esta ahi y no al final por lo que dice la cabecera:
-- final de la tercera fila, columna derecha, donde ha estado siempre.

local CELLS = {
	{ short = "Seguir",  icon = I.follow, tip = "Vuelven a seguirte.",
	  fn = function() Dispatch("follow", "Te siguen") end },

	{ short = "Quieto",  icon = I.hold,   tip = "Aguantan donde estan.",
	  fn = function() Dispatch("stay", "Aguantan") end },

	{ short = "Reunir",  icon = I.rally,  global = true,
	  tip = "Todo el grupo viene a donde estas.",
	  fn = function() ns.Orders:MoveToMe() end },

	{ short = "Atacar",  icon = I.attack, tip = "Atacan tu objetivo.",
	  fn = function() Dispatch("attack", "Atacan") end },

	-- CONTROLAR A ESE COMPAÑERO. Dos formas, y la de mas peso va en el click
	-- normal porque es la que pediste: control NATIVO.
	--
	--   izquierdo -> `/rts swap`: cambias de personaje de verdad. Sales del modo
	--     RTS y pasas a SER ese personaje: sus barras de accion reales, su
	--     libro, sus bolsas, hablar con PNJs, vendedor, entrenador, botin. Sin
	--     pantalla de seleccion. Solo con personajes de TU cuenta.
	--   derecho -> `/rts play`: posesion. Instantaneo y sin carga, pero solo
	--     cambia quien te MUEVE: hablar con PNJs sigue yendo por tu heroe.
	--
	-- SUSTITUYE A "TRAER" por el mismo argumento con el que "Huir" dejo su
	-- sitio: `pull` es una variante estrecha de atacar -- el bot va, pega, y el
	-- bicho vuelve con el al grupo igual -- asi que costaba una casilla y no
	-- daba una capacidad distinta.
	{ short = "Control", icon = I.control, rmb = true,
	  tip = "Click: te CONVIERTES en ese personaje. Su equipo, sus\n" ..
	        "hechizos, sus bolsas. El que dejas se queda de bot.\n" ..
	        "Click derecho: le posees (al momento, pero sin hablar con PNJs).\n" ..
	        "Hace falta tener UNO solo seleccionado.",
	  fn = function(_, button)
		-- Uno y solo uno. Con varios seleccionados no hay respuesta correcta, y
		-- elegir el primero de la lista seria elegir por el jugador algo que no
		-- se puede deshacer sin otra carga.
		local sel = ns.Selection:Get()
		local who
		if #sel == 1 then
			who = sel[1]
		else
			who = ns.Selection:GetPrimary()
			if #sel > 1 then
				ns.Print("|cffff8800control:|r hay " .. #sel ..
				         " seleccionados; usando el primario (" .. tostring(who) .. ").")
			end
		end

		if not who or who == ns.MyName() then
			ns.Print("|cffff8800control:|r selecciona a un compañero primero.")
			return
		end

		-- EL IZQUIERDO ES EL CAMBIO, como se penso desde el principio, y desde
		-- la tarde del 2026-09-03 ya no pasa por la lista de personajes: el
		-- servidor esconde el `SMSG_LOGOUT_COMPLETE` y el cliente se cambia de
		-- identidad sin salir del mundo. Ver `/rts swap` en `Core.lua`.
		if button == "RightButton" then
			ns.Possess:Take(who)
		else
			if ns.RTSMode.active then ns.RTSMode:Toggle() end
			ns.SendServer("SWAP " .. who)
		end
	  end },

	{ short = "A saco",  icon = I.rage,   tip = "Queman cooldowns.",
	  fn = function() Dispatch("max dps", "A saco") end },

	{ short = "Cazar",   icon = I.grind,  tip = "Campan bichos por la zona.",
	  fn = function() Dispatch("grind", "A cazar") end },

	-- HUIR SE FUE Y ESTE OCUPA SU SITIO. `PRUEBAS-20` 0.2: un bot con un rol
	-- viejo pegado deja de atacar y no hay nada en pantalla que lo explique --
	-- las estrategias de playerbots se guardan con el bot y sobreviven al
	-- relogueo. Sin un boton de "olvida todo", la salida era adivinar cual de
	-- las diez estaba de mas.
	--
	-- `flee` era el candidato a sustituir porque romper el combate ya se
	-- consigue con "Quieto" o alejandolos, y porque en la practica un grupo que
	-- huye a la vez se dispersa y hay que reagruparlo -- o sea que costaba mas
	-- de lo que arreglaba.
	{ short = "Reset",   icon = I.reset,
	  tip = "Les devuelve el comportamiento de fabrica y vuelven a seguirte.\n" ..
	        "Para un compañero que se ha quedado con un rol viejo puesto.",
	  fn = function()
		-- AL GRUPO ENTERO, como todo lo de esta rejilla. Tomaba la seleccion y se
		-- plantaba con "Nadie seleccionado", que con la regla nueva la dejaria
		-- como la unica casilla que pide algo que las otras catorce no piden.
		local names = {}
		for _, m in ipairs(ns.Selection:GetRoster()) do
			table.insert(names, m.name)
		end
		if #names == 0 then ns.Print("No hay grupo.") return end
		if ns.Orders:HasServer() then
			ns.SendServer("RESET " .. table.concat(names, ";"))
		else
			-- Sin mod-rts no hay verbo que mandar, y `reset` no es un comando de
			-- chat de playerbots. Lo mas cerca es devolverlos a seguir.
			ns.Orders:Broadcast("follow", "Vuelven a seguirte")
		end
	  end },

	-- BOTIN: `ll all` es la estrategia de botin "all" de playerbots
	-- (LootStrategyValue.cpp), o sea recoger TODO, grises incluidos. Es un
	-- ajuste por bot que vive en memoria del servidor, asi que hay que
	-- repetirlo cuando entra un bot nuevo -- de eso se encarga RTSMode. Este
	-- boton es el manual, para cuando se quiera forzar.
	{ short = "Botin",   icon = I.loot,   global = true,
	  tip = "Que todos recojan TODO, grises incluidos (`ll all`).\n" ..
	        "Se aplica solo al entrar en modo RTS; esto lo repite.",
	  fn = function() ns.RTSMode:ApplyLootAll() end },

	{ short = "Revivir", icon = I.revive, global = true,
	  tip = "Los muertos van al sanador de espiritus.",
	  fn = function() ns.Orders:Broadcast("revive", "Al sanador de espiritus") end },

	{ short = "Formar",  icon = I.form,   global = true,
	  tip = "Elegir la formacion del grupo.",
	  fn = function(self) P:ToggleFlyout(self) end },

	{ short = "Salir",   icon = I.exit,   global = true,
	  tip = "Salir del modo RTS y devolver la interfaz.",
	  exit = true,
	  fn = function() ns.RTSMode:Toggle() end },

	-- --- cuarta fila -----------------------------------------------------

	{ short = "Tanque",  icon = I.taunt,  tip = "Que los tanques cojan tu objetivo.",
	  fn = function() Dispatch("tank attack", "Tanques al objetivo") end },

	{ short = "Matar",   icon = MarkIcon(8), raw = true, global = true,
	  tip = "Poner el CRANEO en tu objetivo y mandar `rti`:\n" ..
	        "todo el grupo va a por el.",
	  fn = function() MarkAction(false) end },

	{ short = "Contro",  icon = MarkIcon(5), raw = true, global = true,
	  tip = "Poner la LUNA en tu objetivo y mandar `rti cc`:\n" ..
	        "la IA lo deja fuera de combate cuando toque (oveja, miedo...).",
	  fn = function() MarkAction(true) end },

	{ short = "Beber",   icon = I.drink,  tip = "Se sientan a comer y beber.",
	  fn = function() Dispatch("drink", "A recuperar") end },
}

--- Estado ----------------------------------------------------------------

function P:Status()
	local cells = ns.Bar:Cells("orders")
	ns.Print(("panel 4x4: %d ordenes en %d celdas."):format(#CELLS, #cells))
	ns.Print("Los botones pequenos del cliente ya NO estan aqui: van a los " ..
		"railes. |cffffff00/rts rails|r.")
end

--- La lista de formaciones ------------------------------------------------

local ROW_H = 34

function P:BuildFlyout()
	flyout = CreateFrame("Frame", "RTSPanelFormations", host)
	flyout:SetFrameStrata("DIALOG")
	flyout:EnableMouse(true)
	flyout:Hide()

	local bg = flyout:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(0, 0, 0, 0.9)

	local list = ns.Orders.FORMATIONS
	local w = 0
	local prev

	for i, name in ipairs(list) do
		local b = CreateFrame("Button", nil, flyout)
		b:SetHeight(ROW_H)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

		-- Un Button sin plantilla no trae FontString, asi que SetText no
		-- dibujaria nada. Se crea a mano, como en el resto del addon.
		local fs = ns.W:Text(b, ns.W.FONT.normal)
		fs:SetPoint("LEFT", b, "LEFT", 10, 0)
		fs:SetText(name)

		if prev then
			b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
			b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -2)
		else
			b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -6)
			b:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -6)
		end

		b:SetScript("OnClick", function()
			ns.Orders:Formation(name)
			flyout:Hide()
		end)

		prev = b
		w = math.max(w, 180)
	end

	flyout:SetWidth(w)
	flyout:SetHeight(#list * (ROW_H + 2) + 12)
end

function P:ToggleFlyout(anchor)
	if not flyout then self:BuildFlyout() end
	if flyout:IsShown() then
		flyout:Hide()
	else
		flyout:ClearAllPoints()
		flyout:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
		flyout:Show()
	end
end

--- Distribucion -----------------------------------------------------------

-- Declarada aqui y definida debajo. `LayoutOrder` la llama, asi que definirla
-- despues sin este aviso la convertiria en una busqueda de global que devuelve
-- nil -- el fallo que `check_addon.py` existe para cazar y que ya ha costado
-- dos rondas de pruebas.
local Paint

-- Una casilla de orden: boton nuestro, icono, etiqueta y tooltip.
local function LayoutOrder(i, c)
	local spec = CELLS[i]
	local b = buttons[i]
	if not b then
		b = ns.W:Button(host, c.w, spec and spec.icon)
		-- EL DERECHO SOLO CUENTA SI LA CELDA LO PIDE (`rmb = true`).
		--
		-- Los botones se reutilizan entre distribuciones, asi que registrar los
		-- clicks por celda no vale: se registran los dos SIEMPRE y se descarta
		-- el derecho en el manejador si esa orden no lo usa. Sin ese descarte,
		-- click derecho sobre "Atacar" atacaria -- y catorce ordenes ganarian un
		-- gesto que nadie decidio darles.
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			local act = self.act
			if not act or not act.fn then return end
			if button == "RightButton" and not act.rmb then return end
			act.fn(self, button)
		end)
		buttons[i] = b
	end

	b:SetWidth(c.w)
	b:SetHeight(c.h)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)

	b.act = spec
	if not spec then
		b:Hide()
		return
	end

	b.icon:SetTexture(spec.icon)

	-- El recorte de W:Button quita el borde que traen los iconos de hechizo. Los
	-- de marca de banda son un dibujo entero y recortarlos les come la punta,
	-- asi que van sin recortar. Mismo caso que en Card.lua.
	if spec.raw then
		b.icon:SetTexCoord(0, 1, 0, 1)
	else
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end

	b.label:SetText(spec.short)
	ns.W:Tip(b, spec.short, spec.tip)

	Paint(b, spec)
	b:Show()
end

-- El color de una casilla: rojo la de salir, AZUL las que ahora mismo irian a
-- la seleccion, blanco las demas. Sacado de `LayoutOrder` porque tambien corre
-- al cambiar la seleccion, que pasa mucho mas a menudo que una redistribucion.
--
-- Con `else` en las tres ramas y no solo `if`: el boton de una casilla se
-- reutiliza, asi que sin devolver el color un dia cualquiera amanece media
-- rejilla en rojo y nadie sabe por que. Ese fallo ya estaba escrito aqui antes
-- de que hubiera tres colores; con tres es mas facil de provocar.
function Paint(b, spec)
	if spec.exit then
		b.icon:SetVertexColor(1, 0.6, 0.6)
		b.label:SetTextColor(1, 0.5, 0.5)
		return
	end

	b.icon:SetVertexColor(1, 1, 1)
	b.label:SetTextColor(1, 1, 1)

	-- Y EL TOOLTIP LO SIGUE DICIENDO, aunque ya no haya dos colores. "Todo el
	-- grupo" escrito es lo que hace que no haya que acordarse de la regla, y lo
	-- que separa esta rejilla de los cuatro botones de accion de la sala, que
	-- dicen "-> Kirinah" en el suyo.
	ns.W:Tip(b, spec.short, spec.tip ..
		(spec.global and "" or "\n|cff999999-> todo el grupo|r"))
end

function P:Layout()
	if not host then return end
	local cells = ns.Bar:Cells("orders")

	for i, c in ipairs(cells) do
		LayoutOrder(i, c)
	end

	for i = #cells + 1, #buttons do buttons[i]:Hide() end
end

-- Solo el color y el tooltip. Corre en cada cambio de seleccion, que es varias
-- veces por combate, y rehacer la distribucion entera ahi seria mover dieciseis
-- botones para no cambiar ninguno de sitio.
function P:Refresh()
	if not self.active then return end
	for i, b in ipairs(buttons) do
		local spec = CELLS[i]
		if spec and b:IsShown() then Paint(b, spec) end
	end
end

--- Entrar y salir ---------------------------------------------------------

function P:Enter()
	host = ns.Bar:SlotFrame("orders")
	if not host then return end
	self.active = true
	self:Layout()
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() P:Layout() end)
		ns.Selection:Subscribe(function() P:Refresh() end)
	end
end

function P:Leave()
	self.active = false
	if flyout then flyout:Hide() end

	if host then host:Hide() end
end

-- SE APUNTA SOLO. `Bar` no nombra a ningun panel desde 2026-09-02: llama a
-- `Enter`/`Leave` sobre los que se hayan registrado, asi que anadir uno nuevo
-- ya no obliga a editar el fichero del arte. Ver `Bar:Register`.
ns.Bar:Register(P)

