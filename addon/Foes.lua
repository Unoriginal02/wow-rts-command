--[[
	Foes.lua -- los enemigos del combate, sobre el divisor de la sala.

	Un cuadrado por enemigo, con su barrita de vida debajo y, si mas de uno de
	los tuyos esta encima, un "x2" en la esquina. Cuantos caben lo decide el
	ancho de la sala, que depende de `grow`: `fill` los cuenta, nadie los
	escribe.

	DE DONDE SALEN. Del mismo `TGTS` que ya trae `Targets.lua` del servidor: la
	lista de lo que cada unidad del grupo tiene apuntado, con guid, vida y cuantos
	van a por el. Aqui se filtran los HOSTILES -- los amigos de esa lista son
	objetivos de curacion y su sitio son las barras del grupo, no una fila de
	enemigos.

	MAS EL TUYO, QUE EL SERVIDOR NO SABE QUE IMPORTA. El objetivo del jugador
	entra aunque nadie del grupo lo tenga apuntado: es lo primero que se marca al
	entrar en combate y no verlo ahi se lee como que el panel no funciona. Es
	client-side y gratis, asi que se anade y se ordena primero.

	POR QUE NO HAY CARAS. `SetPortraitTexture` necesita un TOKEN de unidad, y un
	guid solo se convierte en token si ya es tu objetivo, tu mouseover o alguien
	de tu grupo. Un lobo a veinte metros no tiene token, asi que llevaria un
	interrogante -- y una fila de interrogantes iguales es peor que un icono
	honesto por tipo. El que SI tiene token (tu objetivo, tu mouseover) lleva su
	cara de verdad, que es lo que hace que el primer cuadrado se reconozca.

	SIN MODULO DE SERVIDOR ESTO SE QUEDA EN UNO. `TGTS` es la unica fuente que
	ve mas alla de lo que el cliente tiene a mano; si mod-rts no esta cargado,
	aqui sale tu objetivo y nada mas. No es un fallo del panel, es todo lo que
	el cliente sabe.
]]

local ADDON, ns = ...

local F = {}
ns.Foes = F

F.active = false

local BAR_H = 10        -- la barrita de vida, bajo el cuadrado
local GAP   = 4

local host, cells = nil, {}

local ICON_UNKNOWN = "Interface\\Icons\\Ability_DualWield"

--- Casillas ---------------------------------------------------------------

local function GetCell(i)
	if cells[i] then return cells[i] end

	local c = CreateFrame("Button", "RTSFoe" .. i, host)

	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	c.ring = c:CreateTexture(nil, "BACKGROUND")
	c.ring:SetTexture(0, 0, 0, 0.6)

	c.health = ns.W:Bar(c, false)
	c.health:SetStatusBarColor(0.75, 0.15, 0.15)

	-- Cuantos de los tuyos van a por el. Es el numero que dice de un vistazo si
	-- algo se esta quedando sin atender, que es la mitad del valor del panel.
	c.count = ns.W:Text(c, ns.W.FONT.small)
	c.count:SetPoint("TOPRIGHT", c, "TOPRIGHT", -2, -2)

	c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	c:SetScript("OnClick", function(self, button)
		if not self.guid then return end
		if button == "RightButton" then
			-- En modo mando, apuntar al bot que llevas. Es lo que ya hacia la
			-- lista de objetivos, y aqui es el mismo gesto.
			ns.Targets:Aim(self.guid, self.name or "?")
		else
			ns.Orders:AttackGuid(self.guid, self.name or "objetivo")
		end
	end)

	cells[i] = c
	return c
end

--- Datos ------------------------------------------------------------------

-- La lista que se dibuja: los hostiles que reporto el servidor, con tu objetivo
-- delante si no venia ya.
local function Build()
	local out, seen = {}, {}

	local tgt = "target"
	if UnitExists(tgt) and UnitCanAttack("player", tgt) and not UnitIsDead(tgt) then
		local guid = UnitGUID(tgt)
		if guid then
			seen[guid:lower()] = true
			local max = UnitHealthMax(tgt)
			table.insert(out, {
				guid = guid,
				name = UnitName(tgt) or "?",
				hp = (max and max > 0) and math.floor(UnitHealth(tgt) / max * 100) or 100,
				count = 0,
				token = tgt,
			})
		end
	end

	for _, e in ipairs(ns.Targets:Entries()) do
		if e.hostile and not seen[tostring(e.guid):lower()] then
			seen[tostring(e.guid):lower()] = true
			table.insert(out, {
				guid = e.guid, name = e.name, hp = e.hp, count = e.count,
				token = nil,
			})
		end
	end

	return out
end

-- Un token de unidad para este guid, si el cliente tiene alguno. Es lo unico
-- que permite ensenar una cara de verdad.
local function TokenFor(guid)
	for _, t in ipairs({ "target", "mouseover", "focus" }) do
		if UnitExists(t) and UnitGUID(t) == guid then return t end
	end
	return nil
end

--- Distribucion -----------------------------------------------------------

function F:Layout()
	if not host then return end
	local list = ns.Bar:Cells("foes")

	for i, c in ipairs(list) do
		local cell = GetCell(i)
		local side = math.min(c.w, c.h - BAR_H - GAP)
		if side < 8 then side = 8 end

		cell:ClearAllPoints()
		cell:SetWidth(c.w)
		cell:SetHeight(c.h)
		cell:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)

		cell.icon:ClearAllPoints()
		cell.icon:SetWidth(side)
		cell.icon:SetHeight(side)
		cell.icon:SetPoint("TOP", cell, "TOP", 0, 0)

		cell.ring:ClearAllPoints()
		cell.ring:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -2, 2)
		cell.ring:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 2, -2)

		cell.health:ClearAllPoints()
		cell.health:SetWidth(side)
		cell.health:SetHeight(BAR_H)
		cell.health:SetPoint("TOP", cell.icon, "BOTTOM", 0, -GAP)
	end

	for i = #list + 1, #cells do cells[i]:Hide() end
	self.slots = #list
	self:Refresh()
end

--- Refresco ---------------------------------------------------------------

function F:Refresh()
	if not self.active or not host then return end

	local list = Build()
	local n = math.min(#list, self.slots or 0)

	for i = 1, self.slots or 0 do
		local cell = cells[i]
		local e = list[i]
		if not e then
			cell.guid, cell.name = nil, nil
			cell:Hide()
		else
			cell.guid, cell.name = e.guid, e.name
			cell:Show()

			local token = e.token or TokenFor(e.guid)
			if token then
				SetPortraitTexture(cell.icon, token)
				cell.icon:SetTexCoord(0, 1, 0, 1)
			else
				cell.icon:SetTexture(ICON_UNKNOWN)
				cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			end

			cell.health:SetValue((e.hp or 100) / 100)
			cell.count:SetText((e.count or 0) > 1
				and ("|cffffff00%d|r"):format(e.count) or "")

			ns.W:Tip(cell, e.name,
				"Click: la seleccion ataca\nDerecho: apuntar el mando aqui")
		end
	end

	-- Cuantos se han quedado fuera. Silenciar un desborde es exactamente el
	-- fallo que la regla "no silent caps" existe para no repetir; aqui se guarda
	-- en el modulo y lo imprime `/rts bar status`.
	self.dropped = math.max(0, #list - n)
end

--- Entrar y salir ---------------------------------------------------------

function F:Enter()
	host = ns.Bar:SlotFrame("foes")
	if not host then return end
	self.active = true
	self:Layout()
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() F:Layout() end)
		ns.W:Every(function() F:Refresh() end)
	end
end

function F:Leave()
	self.active = false
	if host then host:Hide() end
end
