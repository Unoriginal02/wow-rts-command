--[[
	Roster.lua -- las barras del grupo, a la derecha del retrato.

	Una fila por companero: barra de vida con el nombre dentro y el color de su
	clase, y barra de poder debajo. Cuatro filas, que es el tamano del grupo que
	este servidor juega (uno a cuatro bots). Tu personaje NO sale aqui: tiene el
	retrato 3D y sus propias barras a la izquierda.

	ES PARA SELECCIONAR, no solo para mirar. Click selecciona, shift o control
	suma a la seleccion -- las mismas teclas que la caja de arrastre, porque son
	la misma seleccion. Ese es el motivo por el que se pidieron con nombre:
	"keeping track of them and being able to select them".

	POR QUE FILAS Y NO RETRATOS. `UnitBar.lua` ya hacia retratos flotantes y se
	queda como estaba, pero en la barra el sitio es ancho y bajo: una fila de
	440x80 dice el nombre completo, la vida y el poder de un vistazo, y cuatro
	filas caben en el alto de la sala. Cuatro retratos con su barrita debajo
	dirian menos ocupando lo mismo.

	NO SE LLAMA A `TargetUnit`. Era lo que hacia el click derecho del UnitBar y
	esta PROTEGIDO para una unidad arbitraria en 3.3.5a (etapa 5h): salta
	"blocked from an action only available to the Blizzard UI". Aqui no hace
	falta para nada -- seleccionar es cosa del addon, no del cliente.

	EL NOMBRE VA DENTRO DE LA BARRA, no encima. Es lo que hace HealBot y lo que
	se pidio, y tiene una razon de sitio: un texto encima de la barra son doce
	pixeles de dibujo mas por fila, que por cuatro filas es media fila entera.
]]

local ADDON, ns = ...

local R = {}
ns.Roster = R

R.active = false

-- El reparto vertical de una fila de 80. La vida se lleva casi todo porque es
-- lo que se mira; el poder solo tiene que decir "le queda mana o no".
local HP_H  = 56
local ROW_G = 4
local PP_H  = 16

local host, rows = nil, {}

--- Filas ------------------------------------------------------------------

local function Border(parent, r, g, b, a)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(r, g, b, a)
	return t
end

local function GetRow(i)
	if rows[i] then return rows[i] end

	local row = CreateFrame("Button", "RTSRosterRow" .. i, host)
	row.health = ns.W:Bar(row, true)
	row.power  = ns.W:Bar(row, false)

	-- El marco de "seleccionado": cuatro rayas, no una textura de brillo. Una
	-- fila de 440 px de ancho con un `CheckButtonHilight` estirado se ve como un
	-- borron; cuatro rayas de un pixel se ven como un marco a cualquier tamano.
	row.mark = {}
	for e = 1, 4 do row.mark[e] = Border(row, 1, 0.95, 0.5, 0.9) end

	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self)
		if not self.unitName then return end
		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.Selection:Toggle(self.unitName)
		else
			ns.Selection:SelectOnly(self.unitName)
		end
	end)

	rows[i] = row
	return row
end

local function MarkBox(row, w, h, on)
	if not on then
		for e = 1, 4 do row.mark[e]:Hide() end
		return
	end
	local spec = {
		{ w, 1, 0, 0 }, { w, 1, 0, h - 1 },
		{ 1, h, 0, 0 }, { 1, h, w - 1, 0 },
	}
	for e = 1, 4 do
		local d = spec[e]
		local t = row.mark[e]
		t:SetWidth(d[1])
		t:SetHeight(d[2])
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", row, "TOPLEFT", d[3], -d[4])
		t:Show()
	end
end

--- Distribucion -----------------------------------------------------------

function R:Layout()
	if not host then return end
	local cells = ns.Bar:Cells("party")

	for i, c in ipairs(cells) do
		local row = GetRow(i)
		row:ClearAllPoints()
		row:SetWidth(c.w)
		row:SetHeight(c.h)
		row:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)

		-- Dentro de la fila: vida arriba, poder abajo. Si la celda es mas baja
		-- de lo previsto se reparte igual en vez de salirse.
		local hp = HP_H
		local pp = PP_H
		if hp + ROW_G + pp > c.h then
			pp = math.max(6, math.floor(c.h * 0.2))
			hp = c.h - ROW_G - pp
		end

		row.health:ClearAllPoints()
		row.health:SetWidth(c.w)
		row.health:SetHeight(hp)
		row.health:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

		row.power:ClearAllPoints()
		row.power:SetWidth(c.w)
		row.power:SetHeight(pp)
		row.power:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(hp + ROW_G))

		row.cellW, row.cellH = c.w, c.h
	end

	for i = #cells + 1, #rows do rows[i]:Hide() end
	-- Cuantas filas hay SITIO para, que no es lo mismo que cuantas filas se han
	-- creado alguna vez: si la barra se encoge y el hueco desaparece, `Refresh`
	-- no puede volver a ensenar las que `Layout` acaba de esconder.
	self.slots = #cells
	self:Refresh()
end

--- Refresco ---------------------------------------------------------------

function R:Refresh()
	if not self.active or not host then return end

	local roster = ns.Selection:GetRoster()

	for i = 1, self.slots or 0 do
		local row = rows[i]
		local m = roster[i]

		if not m then
			row.unitName, row.unit = nil, nil
			row:Hide()
		else
			row.unitName, row.unit = m.name, m.unit
			row:Show()

			local c = ns.W:ClassColor(m.unit)
			ns.W:Color(row.health, c)
			ns.W:Color(row.power, ns.W:PowerColor(m.unit))

			local dead = UnitIsDeadOrGhost(m.unit)
			local off = not UnitIsConnected(m.unit)
			ns.W:Fill(row.health, dead and 0 or UnitHealth(m.unit), UnitHealthMax(m.unit))
			ns.W:Fill(row.power, UnitMana(m.unit) or 0, UnitManaMax(m.unit) or 0)

			-- El nombre lleva el nivel detras en gris. Con bots de nivel
			-- distinto al tuyo es la diferencia entre "va lento" y "le pega
			-- todo".
			row.health.text:SetText(("%s |cff999999%d|r"):format(
				m.name, UnitLevel(m.unit) or 0))

			if dead then
				row.health.right:SetText("|cffff4444muerto|r")
			elseif off then
				row.health.right:SetText("|cff888888fuera|r")
			else
				row.health.right:SetText(ns.W:Short(UnitHealth(m.unit)))
			end

			MarkBox(row, row.cellW or row:GetWidth(), row.cellH or row:GetHeight(),
				ns.Selection:IsSelected(m.name))
		end
	end
end

--- Entrar y salir ---------------------------------------------------------

function R:Enter()
	host = ns.Bar:SlotFrame("party")
	if not host then return end
	self.active = true
	self:Layout()
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() R:Layout() end)
		ns.W:Every(function() R:Refresh() end)
		ns.Selection:Subscribe(function() R:Refresh() end)
	end
end

function R:Leave()
	self.active = false
	if host then host:Hide() end
end
