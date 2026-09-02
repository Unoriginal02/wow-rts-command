--[[
	Panel.lua -- la rejilla de ordenes, a la derecha de la sala.

	Rejilla 4x4: quince ordenes y, en la casilla doce, salir del modo RTS.
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

	SELECCION O GRUPO, DESDE 2026-08-24, y antes eran dos rejillas. La fila de
	ordenes que habia bajo el divisor decia lo mismo que esta con `Send` en vez
	de `Broadcast`, y su banda hacia falta para los huecos de habilidad. Asi que
	las dos se juntan aqui: con algo seleccionado la orden va a lo seleccionado,
	sin nada seleccionado va al grupo entero.

	UN MISMO BOTON CON DOS ALCANCES ES AMBIGUO, Y POR ESO EL ALCANCE SE VE. Es
	el riesgo conocido de haberlas juntado, y se paga en pantalla y no en una
	ronda de pruebas: cuando hay seleccion las ordenes que la respetan salen con
	la etiqueta en AZUL y su tooltip dice a cuantos van. En blanco significa
	grupo entero. Sin esa senal, "por que solo se ha movido uno" seria una
	pregunta sin nada que mirar.

	Y SIETE DE LAS DIECISEIS NO CAMBIAN NUNCA. Reunir, Botin, Revivir, Formar,
	Salir y las dos marcas son globales por naturaleza -- una formacion de dos
	de los cuatro no es una formacion, y una marca que solo obedece a parte del
	grupo no es una marca. Van marcadas con `global` en la tabla y se quedan
	siempre en blanco, que es lo que hace legible la regla del resto.

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
	pull   = "Interface\\Icons\\Ability_Marksmanship",
	flee   = "Interface\\Icons\\Ability_Rogue_Feint",
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
-- UNA orden, DOS destinos, y la decision en un solo sitio. Con unidades cogidas
-- la orden es suya; sin nada cogido es del grupo. Se decide al PULSAR y no al
-- dibujar porque la seleccion puede cambiar entre una cosa y la otra -- y lo que
-- vale es la que habia cuando se dio la orden.

-- Cuantas unidades recibirian una orden con alcance de seleccion ahora mismo, o
-- 0 si iria al grupo entero.
local function Scoped()
	return ns.Selection:Count()
end

local function Dispatch(command, label)
	if Scoped() > 0 then
		return ns.Orders:Send(command, label)
	end
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

	{ short = "Traer",   icon = I.pull,   tip = "Traer tu objetivo hasta el grupo.",
	  fn = function() Dispatch("pull", "Trayendo") end },

	{ short = "A saco",  icon = I.rage,   tip = "Queman cooldowns.",
	  fn = function() Dispatch("max dps", "A saco") end },

	{ short = "Cazar",   icon = I.grind,  tip = "Campan bichos por la zona.",
	  fn = function() Dispatch("grind", "A cazar") end },

	{ short = "Huir",    icon = I.flee,   tip = "Rompen el combate.",
	  fn = function() Dispatch("flee", "Huyendo") end },

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
		b:SetScript("OnClick", function(self)
			if self.act and self.act.fn then self.act.fn(self) end
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

	local n = (not spec.global) and Scoped() or 0
	if n > 0 then
		b.label:SetTextColor(0.45, 0.8, 1)
		ns.W:Tip(b, spec.short,
			("%s\n|cff77ccff-> %d seleccionada(s)|r"):format(spec.tip, n))
	else
		b.label:SetTextColor(1, 1, 1)
		ns.W:Tip(b, spec.short, spec.tip ..
			(spec.global and "" or "\n|cff999999-> todo el grupo|r"))
	end
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

