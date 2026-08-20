--[[
	Panel.lua -- las nueve ordenes globales, en el panel cuadrado de la derecha.

	Rejilla 3x3. Ocho ordenes para TODO el grupo y, en la casilla de abajo a la
	derecha, salir del modo RTS -- que es donde se pidio y donde tiene sentido:
	la esquina de la que uno se acuerda.

	GLOBAL QUIERE DECIR `Broadcast`, NO `Send`. Es la unica diferencia con la
	fila de ordenes de la carta y es toda la diferencia: la carta manda a lo que
	tengas SELECCIONADO, esto manda al grupo entero pase lo que pase. Sin eso,
	dos rejillas con los mismos iconos serian dos formas de hacer lo mismo, y la
	de arriba sobraria.

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
	hold   = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	attack = "Interface\\Icons\\Ability_Warrior_Cleave",
	pull   = "Interface\\Icons\\Ability_Marksmanship",
	flee   = "Interface\\Icons\\Ability_Rogue_Feint",
	form   = "Interface\\Icons\\Ability_Warrior_BattleShout",
	rally  = "Interface\\Icons\\Ability_Warrior_Charge",
	rage   = "Interface\\Icons\\Ability_Warrior_InnerRage",
	exit   = "Interface\\Icons\\Spell_ChargeNegative",
}

--- Las nueve casillas -----------------------------------------------------
--
-- En orden de rejilla: 1..3 arriba, 4..6 en medio, 7..9 abajo. La 9 es la de
-- salir y esta escrita ultima a proposito, para que se vea que la esquina no es
-- casualidad.

local CELLS = {
	{ short = "Seguir",  icon = I.follow, tip = "Todo el grupo vuelve a seguirte.",
	  fn = function() ns.Orders:Broadcast("follow", "El grupo te sigue") end },

	{ short = "Quieto",  icon = I.hold,   tip = "Todo el grupo aguanta donde esta.",
	  fn = function() ns.Orders:Broadcast("stay", "El grupo aguanta") end },

	{ short = "Reunir",  icon = I.rally,  tip = "Todo el grupo viene a donde estas.",
	  fn = function() ns.Orders:MoveToMe() end },

	{ short = "Atacar",  icon = I.attack, tip = "Todo el grupo ataca tu objetivo.",
	  fn = function() ns.Orders:Broadcast("attack", "El grupo ataca") end },

	{ short = "Traer",   icon = I.pull,   tip = "Traer tu objetivo hasta el grupo.",
	  fn = function() ns.Orders:Broadcast("pull", "Trayendo") end },

	{ short = "A saco",  icon = I.rage,   tip = "Todo el grupo quema cooldowns.",
	  fn = function() ns.Orders:Broadcast("max dps", "A saco") end },

	{ short = "Huir",    icon = I.flee,   tip = "Todo el grupo rompe el combate.",
	  fn = function() ns.Orders:Broadcast("flee", "Huyendo") end },

	{ short = "Formar",  icon = I.form,   tip = "Elegir la formacion del grupo.",
	  fn = function(self) P:ToggleFlyout(self) end },

	{ short = "Salir",   icon = I.exit,   tip = "Salir del modo RTS y devolver la interfaz.",
	  exit = true,
	  fn = function() ns.RTSMode:Toggle() end },
}

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

function P:Layout()
	if not host then return end
	local cells = ns.Bar:Cells("orders")

	for i, c in ipairs(cells) do
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
		if spec then
			b.icon:SetTexture(spec.icon)
			b.label:SetText(spec.short)
			ns.W:Tip(b, spec.short, spec.tip)
			-- La de salir en rojo. Es la unica que no es una orden y no deberia
			-- pulsarse por inercia buscando otra.
			if spec.exit then
				b.icon:SetVertexColor(1, 0.6, 0.6)
				b.label:SetTextColor(1, 0.5, 0.5)
			end
			b:Show()
		else
			b:Hide()
		end
	end

	for i = #cells + 1, #buttons do buttons[i]:Hide() end
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
	end
end

function P:Leave()
	self.active = false
	if flyout then flyout:Hide() end
	if host then host:Hide() end
end
