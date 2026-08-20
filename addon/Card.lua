--[[
	Card.lua -- las dos filas de acciones, bajo el divisor de la sala.

	Cambia con la seleccion, que es lo que la hace una carta de comandos y no
	otra barra de accion:

	  fila 1   las ordenes de la seleccion: mover, aguantar, seguir, atacar...
	  fila 2   las ocho marcas, y detras los hechizos de la clase del bot que
	           tengas seleccionado -- si tienes uno solo

	Cuantas columnas hay lo decide el ancho de la sala, o sea `grow`. Si no caben
	las nueve ordenes se dicen las que se quedaron fuera: un recorte silencioso
	se lee como "esa orden no existe".

	=== las marcas, que es la peticion que parecia mas rara ==================

	"Pedirle al mago que convierta en oveja al bicho con la luna" no necesita
	nada nuevo: playerbots ya tiene DOS marcas por bot, comprobado en su fuente
	(`RtiValue.cpp`) -- `rti`, la de matar, que viene en craneo, y `rti cc`, la de
	controlar, que viene en LUNA. La IA de cada clase ya sabe que el objetivo de
	`rti cc` es el que hay que dejar fuera de combate.

	Asi que un boton de marca hace las dos mitades del gesto de un RTS:

	  click            pone el icono en TU objetivo (para que se vea) y le dice
	                   a la seleccion `rti <marca>`  -> id a por ese
	  click derecho    lo mismo con `rti cc <marca>` -> a ese controladlo

	Los nombres que acepta son star circle diamond triangle moon square cross
	skull, en ese orden, y coinciden uno a uno con los iconos 1..8 del cliente.
	Leido de `RtiTargetValue.h`, no supuesto.

	=== los iconos son por CATEGORIA, y es a proposito ======================

	Cincuenta hechizos serian cincuenta rutas de textura escritas de memoria, y
	una ruta que no existe NO DA ERROR: dibuja nada. Con cincuenta, la lista de
	rutas es la parte que se rompe en silencio, y encima parece un fallo de
	anclaje. Aqui hay DIEZ rutas, todas de iconos de toda la vida, y cada hechizo
	dice a que categoria pertenece -- controlar, interrumpir, curar, escudo...
	Debajo de cada boton va la etiqueta, asi que incluso si una ruta fallara el
	boton sigue diciendo lo que hace.

	=== por que no pasa por el chat visible ================================

	Las ordenes salen por `ns.Orders`, que susurra al bot. No es el chat que se
	escribe con Intro: no hay que abrir la ventana, no hay que soltar el raton, y
	funciona en combate -- que es lo que se pidio. `SendChatMessage` no esta
	protegida en 3.3.5a; lo que esta protegido es `CastSpellByName` y por eso el
	heroe no tiene botones de lanzar hechizos aqui.
]]

local ADDON, ns = ...

local C = {}
ns.Card = C

C.active = false

local host, buttons = nil, {}

--- Iconos, diez y ni uno mas ----------------------------------------------

local I = {
	move   = "Interface\\Icons\\Ability_Warrior_Charge",
	hold   = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	follow = "Interface\\Icons\\Ability_Rogue_Sprint",
	attack = "Interface\\Icons\\Ability_Warrior_Cleave",
	pull   = "Interface\\Icons\\Ability_Marksmanship",
	taunt  = "Interface\\Icons\\Ability_Defend",
	rage   = "Interface\\Icons\\Ability_Warrior_InnerRage",
	flee   = "Interface\\Icons\\Ability_Rogue_Feint",
	grind  = "Interface\\Icons\\INV_Sword_04",
	cc     = "Interface\\Icons\\Spell_Nature_Polymorph",
	stop   = "Interface\\Icons\\Spell_Frost_IceShock",
	heal   = "Interface\\Icons\\Spell_Holy_Heal",
	shield = "Interface\\Icons\\Spell_Holy_PowerWordShield",
	buff   = "Interface\\Icons\\Spell_Holy_WordFortitude",
	dot    = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
	nuke   = "Interface\\Icons\\Spell_Fire_FlameBolt",
	slow   = "Interface\\Icons\\Spell_Frost_FrostNova",
}

--- Fila 1: las ordenes de la seleccion ------------------------------------

local ORDERS = {
	{ short = "Mover",  icon = I.move,   tip = "Mover a la posicion del cursor.",
	  fn = function() ns.Orders:MoveToCursor() end },
	{ short = "Quieto", icon = I.hold,   tip = "Aguantar la posicion. Dejan de seguirte.",
	  fn = function() ns.Orders:Hold() end },
	{ short = "Seguir", icon = I.follow, tip = "Volver a seguirte.",
	  fn = function() ns.Orders:Follow() end },
	{ short = "Atacar", icon = I.attack, tip = "Atacar tu objetivo.",
	  fn = function() ns.Orders:Attack() end },
	{ short = "Traer",  icon = I.pull,   tip = "Traer tu objetivo hasta el grupo.",
	  fn = function() ns.Orders:Pull() end },
	{ short = "Tanque", icon = I.taunt,  tip = "Que los tanques cojan tu objetivo.",
	  fn = function() ns.Orders:TankAttack() end },
	{ short = "A saco", icon = I.rage,   tip = "Quemar cooldowns.",
	  fn = function() ns.Orders:MaxDPS() end },
	{ short = "Huir",   icon = I.flee,   tip = "Romper el combate y huir.",
	  fn = function() ns.Orders:Flee() end },
	{ short = "Cazar",  icon = I.grind,  tip = "Campar bichos por la zona.",
	  fn = function() ns.Orders:Grind() end },
}

--- Las ocho marcas --------------------------------------------------------
--
-- El orden es el de playerbots, que es el del cliente: star..skull = 1..8.

local MARKS = {
	{ key = "star",     short = "Estr",  index = 1 },
	{ key = "circle",   short = "Circ",  index = 2 },
	{ key = "diamond",  short = "Diam",  index = 3 },
	{ key = "triangle", short = "Tri",   index = 4 },
	{ key = "moon",     short = "Luna",  index = 5 },
	{ key = "square",   short = "Cuad",  index = 6 },
	{ key = "cross",    short = "Cruz",  index = 7 },
	{ key = "skull",    short = "Crane", index = 8 },
}

-- `SetRaidTarget` es el nombre en 3.3.5a; hay clientes y wikis que hablan de
-- `SetRaidTargetIcon`. Se coge la que exista de verdad en ESTE cliente en vez de
-- elegir una y descubrir que no esta cuando el boton no haga nada.
local function PutIcon(index)
	local f = SetRaidTarget or SetRaidTargetIcon
	if not f then return false end
	if not UnitExists("target") then return false end
	f("target", index)
	return true
end

-- Un bot en la seleccion es lo que hace que una orden tenga sentido: susurrarse
-- a uno mismo no manda a nadie.
local function HasBots()
	local yo = UnitName("player")
	for _, name in ipairs(ns.Selection:Get()) do
		if name ~= yo then return true end
	end
	return false
end

local function MarkAction(m, cc)
	local puesto = PutIcon(m.index)
	if HasBots() then
		ns.Orders:Send((cc and "rti cc " or "rti ") .. m.key,
			(cc and "controlar: " or "objetivo: ") .. m.short)
	elseif puesto then
		ns.Print(("marca |cffffff00%s|r puesta"):format(m.short))
	else
		ns.Print("nada seleccionado y sin objetivo: la marca no va a ningun sitio.")
	end
end

--- Fila 2: los hechizos de la clase --------------------------------------
--
-- Cinco por clase, los que se piden a mano en una pelea. Todos existen en
-- 3.3.5a: nada de poder sagrado, ni Hex, ni fragmentos como pips -- eso es de
-- Cataclysm en adelante y pedirlo aqui seria un `cast` que el bot ignora.

local SPELLS = {
	WARRIOR = {
		{ "Taunt", "Provocar", I.taunt },
		{ "Shield Wall", "Muro", I.shield },
		{ "Thunder Clap", "Trueno", I.slow },
		{ "Intimidating Shout", "Grito", I.cc },
		{ "Charge", "Carga", I.move },
	},
	PALADIN = {
		{ "Holy Light", "Luz", I.heal },
		{ "Divine Shield", "Escudo", I.shield },
		{ "Hammer of Justice", "Martillo", I.cc },
		{ "Consecration", "Consagr", I.nuke },
		{ "Hand of Protection", "Mano", I.buff },
	},
	HUNTER = {
		{ "Hunter's Mark", "Marca", I.buff },
		{ "Freezing Trap", "Trampa", I.cc },
		{ "Misdirection", "Desvio", I.taunt },
		{ "Feign Death", "Fingir", I.flee },
		{ "Bestial Wrath", "Furia", I.nuke },
	},
	ROGUE = {
		{ "Sap", "Golpear", I.cc },
		{ "Kick", "Patada", I.stop },
		{ "Blind", "Ciego", I.cc },
		{ "Evasion", "Evasion", I.shield },
		{ "Sprint", "Esprint", I.follow },
	},
	PRIEST = {
		{ "Power Word: Shield", "Escudo", I.shield },
		{ "Renew", "Renovar", I.heal },
		{ "Dispel Magic", "Disipar", I.buff },
		{ "Shackle Undead", "Grilletes", I.cc },
		{ "Shadow Word: Pain", "Dolor", I.dot },
	},
	SHAMAN = {
		{ "Chain Heal", "Cadena", I.heal },
		{ "Purge", "Purgar", I.stop },
		{ "Earth Shield", "Tierra", I.shield },
		{ "Earth Shock", "Choque", I.stop },
		{ "Heroism", "Heroismo", I.buff },
	},
	MAGE = {
		{ "Polymorph", "Oveja", I.cc },
		{ "Counterspell", "Contra", I.stop },
		{ "Frost Nova", "Nova", I.slow },
		{ "Ice Block", "Hielo", I.shield },
		{ "Blink", "Parpadeo", I.follow },
	},
	WARLOCK = {
		{ "Fear", "Miedo", I.cc },
		{ "Banish", "Destierro", I.cc },
		{ "Corruption", "Corrupc", I.dot },
		{ "Death Coil", "Espiral", I.cc },
		{ "Immolate", "Inmolar", I.nuke },
	},
	DRUID = {
		{ "Rejuvenation", "Rejuv", I.heal },
		{ "Innervate", "Inervar", I.buff },
		{ "Entangling Roots", "Raices", I.slow },
		{ "Hibernate", "Hibernar", I.cc },
		{ "Barkskin", "Corteza", I.shield },
	},
	DEATHKNIGHT = {
		{ "Death Grip", "Agarre", I.taunt },
		{ "Icebound Fortitude", "Fortal", I.shield },
		{ "Chains of Ice", "Cadenas", I.slow },
		{ "Mind Freeze", "Congelar", I.stop },
		{ "Death and Decay", "Muerte", I.nuke },
	},
}

-- Los hechizos que toca ensenar: solo con UN bot seleccionado. Con dos, "lanza
-- Oveja" iria a los dos y el segundo no la tiene.
local function SpellsForSelection()
	if ns.Selection:Count() ~= 1 then return nil, nil end
	local name = ns.Selection:Single()
	if name == UnitName("player") then return nil, nil end
	local unit = ns.Selection:UnitFor(name)
	if not unit then return nil, nil end
	local _, class = UnitClass(unit)
	return SPELLS[class], class
end

--- La lista que se dibuja -------------------------------------------------

-- Devuelve dos filas ya recortadas al ancho, y lo que se quedo fuera.
local function Rows(cols)
	local uno, dos, fuera = {}, {}, {}

	for i, o in ipairs(ORDERS) do
		if i <= cols then
			table.insert(uno, {
				short = o.short, icon = o.icon, tip = o.tip,
				fn = o.fn, needs = true,
			})
		else
			table.insert(fuera, o.short)
		end
	end

	for _, m in ipairs(MARKS) do
		if #dos < cols then
			table.insert(dos, {
				short = m.short,
				icon = ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"):format(m.index),
				raw = true,   -- el icono de marca no lleva el recorte de los de hechizo
				tip = "Click: marcar tu objetivo y que la seleccion vaya a por el." ..
				      "\nDerecho: marcarlo como el que hay que controlar (rti cc).",
				fn = function(_, button)
					MarkAction(m, button == "RightButton")
				end,
			})
		else
			table.insert(fuera, m.short)
		end
	end

	local list = SpellsForSelection()
	if list then
		for _, s in ipairs(list) do
			if #dos < cols then
				local spell, short, icon = s[1], s[2], s[3]
				table.insert(dos, {
					short = short, icon = icon, needs = true,
					tip = ("Lanzar |cffffff00%s|r."):format(spell),
					fn = function() ns.Orders:Cast(spell) end,
				})
			else
				table.insert(fuera, s[2])
			end
		end
	end

	return uno, dos, fuera
end

--- Botones ----------------------------------------------------------------

local function GetButton(i, size)
	local b = buttons[i]
	if not b then
		b = ns.W:Button(host, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if self.act and self.act.fn then self.act.fn(self, button) end
		end)
		buttons[i] = b
	end
	return b
end

--- Distribucion -----------------------------------------------------------

function C:Layout()
	if not host then return end
	local cells = ns.Bar:Cells("card")

	for i, c in ipairs(cells) do
		local b = GetButton(i, c.w)
		b:SetWidth(c.w)
		b:SetHeight(c.h)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)
	end
	for i = #cells + 1, #buttons do buttons[i]:Hide() end

	self.cols = #cells > 0 and math.max(1, math.floor(#cells / 2)) or 0
	self.slots = #cells
	self:Refresh()
end

--- Refresco ---------------------------------------------------------------

function C:Refresh()
	if not self.active or not host then return end

	local cols = self.cols or 0
	if cols < 1 then return end

	local uno, dos, fuera = Rows(cols)
	local hayBots = HasBots()

	-- Las dos filas se escriben en las celdas en el orden de la rejilla: las
	-- `cols` primeras son la de arriba.
	for i = 1, self.slots or 0 do
		local b = buttons[i]
		local fila = (i <= cols) and uno or dos
		local act = fila[((i - 1) % cols) + 1]

		b.act = act
		if not act then
			b:Hide()
		else
			b:Show()
			b.icon:SetTexture(act.icon)
			-- El recorte quita el borde que traen los iconos de hechizo. Los de
			-- marca son un dibujo entero y recortarlos les come la punta.
			if act.raw then
				b.icon:SetTexCoord(0, 1, 0, 1)
			else
				b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			end
			b.label:SetText(act.short)
			ns.W:Tip(b, act.short, act.tip)
			ns.W:Enable(b, (not act.needs) or hayBots)
		end
	end

	-- Lo que no cupo, dicho una sola vez por distribucion. Nunca en silencio.
	if #fuera > 0 and self.warned ~= #fuera then
		self.warned = #fuera
		ns.Print(("|cffff8800carta:|r no caben %d acciones (%s). " ..
			"Sube |cffffff00/rts bar grow|r."):format(#fuera,
			table.concat(fuera, ", ")))
	elseif #fuera == 0 then
		self.warned = nil
	end
end

--- Entrar y salir ---------------------------------------------------------

function C:Enter()
	host = ns.Bar:SlotFrame("card")
	if not host then return end
	self.active = true
	self:Layout()
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() C:Layout() end)
		ns.Selection:Subscribe(function() C:Refresh() end)
	end
end

function C:Leave()
	self.active = false
	if host then host:Hide() end
end
