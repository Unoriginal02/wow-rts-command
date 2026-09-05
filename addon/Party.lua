--[[
	Party.lua -- la columna de personajes, a la izquierda de la sala.

	Cinco filas: TU EL PRIMERO y los cuatro companeros debajo. Por fila, lo que
	pide §3 del brief y nada mas:

	    Kirinah  62                 <- el nombre ENCIMA de la barra
	    [##################   ]     <- vida, PLANA, color de clase
	    [============         ]     <- recurso, una linea muy fina

	=== VIENE DE `Roster.lua`, QUE ESTABA BORRADO ============================

	Se recupera de git (`6fd4496^`) en vez de reescribirse: la mitad util --
	las filas, el marco de seleccion de cuatro rayas, el click, el latido -- ya
	estaba escrita y probada en juego. Lo que cambia es lo que el brief cambia:

	  * EL HEROE ENTRA EN LA LISTA Y VA EL PRIMERO. `Roster` lo excluia a
	    proposito porque tenia su retrato 3D aparte; ese retrato no existe y el
	    brief pide explicitamente que el heroe sea el primer item.
	  * EL NOMBRE VA ENCIMA, NO DENTRO. `Roster` lo metia dentro de la barra
	    para ahorrar doce pixeles por fila, con la columna de 440 de ancho. Aqui
	    la columna es de 260 y son cinco filas: un nombre dentro de una barra de
	    260 se come el numero de vida.
	  * LA BARRA ES PLANA. `W.BAR_TEX` es la textura del cliente, que lleva un
	    brillo suave arriba; el brief pide "plana, sin degradados". Se le pone
	    un color liso, que en 3.3.5a es `SetStatusBarTexture(r,g,b)` -- una
	    llamada que acepta color en vez de ruta y que no hace falta comprobar
	    porque la usa `W:Bar` para su fondo desde que existe.
	  * EL RECURSO ES UNA LINEA. Seis pixeles de dibujo, que a la escala de la
	    barra son 3,4 de pantalla -- dentro del "2-4 px" que pide el brief. Lo
	    comprueba `sim/hall_layout.py`.

	=== SIRVE PARA SELECCIONAR Y PARA APUNTAR ===============================

	Click selecciona (con doble click = todos y shift = sumar, que lo decide
	`Selection:Click` en un solo sitio para que la ventana del doble click sea
	comun a toda la consola).

	Y ADEMAS ES EL SEGUNDO CLICK DE UN HECHIZO ARMADO, que es lo que pide §5
	del brief: *"segundo clic sobre el objetivo, indistintamente en la lista de
	personajes o directamente sobre el jugador en el mundo 3D"*. Cuando hay algo
	armado, la fila NO cambia la seleccion -- entrega el objetivo y ya. Sin eso,
	curar al tanque te dejaria con el tanque cogido y el grupo suelto, que es la
	misma razon por la que `RTSMode:OnLeftClick` se come el click en el mundo.

	NO SE LLAMA A `TargetUnit`. Esta PROTEGIDO para una unidad arbitraria en
	3.3.5a (etapa 5h) y ademas no hace falta: seleccionar es cosa del addon.
]]

local ADDON, ns = ...

local P = {}
ns.Party = P

P.active = false

-- El reparto vertical de una fila. Sale de `sim/hall_layout.py`: con la sala
-- en 344 y cinco filas, la fila mide 65 y dentro caben 24 de nombre, 31 de
-- vida y 6 de linea de recurso.
-- EL NOMBRE SUBE DE 24 A 26 Y CAMBIA DE FUENTE, por `PRUEBAS-23` A2: *"texto
-- muy pequeno"*. La fuente era `small` (22 de dibujo = 12 px de pantalla) y el
-- nivel/vida iba en `tiny` (18 = 10 px), que es mas pequeno que cualquier cosa
-- que el cliente escriba.
--
-- 26 ES EL TOPE Y NO ES ARBITRARIO: la fila mide 65, y de ahi salen el nombre,
-- la vida y la linea de recurso. `sim/hall_layout.py` comprueba que la barra de
-- vida siga siendo la pieza dominante de la fila -- con 28 dejaria de serlo, y
-- entonces la fila se leeria como una etiqueta con una barra debajo en vez de
-- como un marco de unidad.
local NAME_H   = 26
local NAME_GAP = 2
local POWER_H  = 6
local POWER_GAP = 2

local host, rows = nil, {}

--- Piezas -----------------------------------------------------------------

local function Border(parent, r, g, b, a)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(r, g, b, a)
	return t
end

-- UNA BARRA PLANA. No usa `W:Bar` porque esa pone la textura del cliente, que
-- lleva degradado. El resto (fondo negro obligatorio, para que una barra vacia
-- no sea un agujero en el arte) se copia de alli por la misma razon que alli.
local function FlatBar(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	b:SetMinMaxValues(0, 1)
	b:SetValue(1)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(0, 0, 0, 0.7)
	return b
end

local function GetRow(i)
	if rows[i] then return rows[i] end

	local row = CreateFrame("Button", "RTSPartyRow" .. i, host)
	row.name   = ns.W:Text(row, ns.W.FONT.normal)
	row.hp     = ns.W:Text(row, ns.W.FONT.small)
	row.health = FlatBar(row)
	row.power  = FlatBar(row)

	row.name:SetJustifyH("LEFT")
	row.hp:SetJustifyH("RIGHT")

	-- El marco de "seleccionado": cuatro rayas, no una textura de brillo. Una
	-- fila de 260 con un `CheckButtonHilight` estirado se ve como un borron;
	-- cuatro rayas de un pixel se ven como un marco a cualquier tamano.
	row.mark = {}
	for e = 1, 4 do row.mark[e] = Border(row, ns.W.SELECT.r, ns.W.SELECT.g, ns.W.SELECT.b, ns.W.SELECT.a) end

	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self, button)
		if not self.unitName then return end

		-- UN HECHIZO ARMADO SE COME EL CLICK, y va lo primero. Ver la cabecera:
		-- es la mitad de §5 que ocurre dentro de la consola.
		if ns.Skills:Aiming() then
			if button == "RightButton" then
				ns.Skills:AimAt(nil)
			else
				ns.Skills:AimAt(UnitGUID(self.unit), self.unitName)
			end
			return
		end

		-- Y el foco pendiente del boton "Focus", con el mismo gesto. Esta es la
		-- boca que mas se va a usar: "que la sanadora cuide del tanque" es
		-- pulsar Focus con ella seleccionada y pinchar al tanque en esta lista.
		if ns.Cast:AimAt(button ~= "RightButton" and UnitGUID(self.unit) or nil,
		                 self.unitName) then
			return
		end

		-- EL CLICK DERECHO NO HACE NADA MAS, Y ESO ES LO QUE SE PIDIO.
		--
		-- Hasta la 0.76.0 hacia primario sin seleccionar -- el gesto del video,
		-- *"the command bar for the next person WITHOUT deselecting"*. En
		-- `PRUEBAS-23` A5 se marco `[!]`: *"¿para que iba a querer yo eso?"*.
		--
		-- Se quita el GESTO, no el CONCEPTO: el primario sigue existiendo porque
		-- es quien decide de quien son los hechizos de abajo, y ahora lo pone
		-- unicamente la seleccion -- seleccionar a uno le hace primario, y con
		-- nada seleccionado es tu personaje. Un concepto sin gesto propio es
		-- exactamente lo que ya paso con Tab en la 0.52.0.
		if button == "RightButton" then
			return
		end

		ns.Selection:Click(self.unitName)
	end)

	rows[i] = row
	return row
end

local function MarkBox(row, w, h, on)
	if not on then
		for e = 1, 4 do row.mark[e]:Hide() end
		return
	end
	local t = ns.W.SELECT.thick
	local spec = {
		{ w, t, 0, 0 }, { w, t, 0, h - t },
		{ t, h, 0, 0 }, { t, h, w - t, 0 },
	}
	for e = 1, 4 do
		local d = spec[e]
		local tex = row.mark[e]
		tex:SetWidth(d[1] > 0 and d[1] or 1)
		tex:SetHeight(d[2] > 0 and d[2] or 1)
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", row, "TOPLEFT", d[3], -d[4])
		tex:Show()
	end
end

--- Distribucion -----------------------------------------------------------

function P:Layout()
	if not host then return end
	local r = ns.Hall:Get("list")
	if not r then return end

	local rowH = ns.Hall:RowHeight()
	local gap  = ns.Hall:RowGap()
	local w    = r.w

	-- El alto de la vida es lo que sobra. Se calcula y no se escribe para que
	-- cambiar el alto de la sala no deje las filas descuadradas en silencio.
	local hpH = rowH - NAME_H - NAME_GAP - POWER_GAP - POWER_H
	if hpH < 8 then hpH = 8 end

	for i = 1, ns.Hall.ROW_N do
		local row = GetRow(i)
		row:ClearAllPoints()
		row:SetWidth(w)
		row:SetHeight(rowH)
		row:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -((i - 1) * (rowH + gap)))

		row.name:ClearAllPoints()
		row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
		-- LO QUE SE LE RESERVA AL NUMERO DE LA DERECHA, y sube de 60 a 88 con la
		-- columna estrechada. El numero es nivel + vida corta ("80 12k"), que a
		-- fuente 22 son unos 72 de dibujo; con 60 el nombre se le echaba encima.
		-- Y un `FontString` de ancho fijo en 3.3.5a NO recorta: parte en dos
		-- lineas y deja la segunda fuera del alto, asi que el sintoma habria
		-- sido "a veces falta media letra" en vez de un solape claro.
		row.name:SetWidth(w - 88)
		row.name:SetHeight(NAME_H)

		row.hp:ClearAllPoints()
		row.hp:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
		row.hp:SetHeight(NAME_H)

		row.health:ClearAllPoints()
		row.health:SetWidth(w)
		row.health:SetHeight(hpH)
		row.health:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(NAME_H + NAME_GAP))

		row.power:ClearAllPoints()
		row.power:SetWidth(w)
		row.power:SetHeight(POWER_H)
		row.power:SetPoint("TOPLEFT", row, "TOPLEFT", 0,
			-(NAME_H + NAME_GAP + hpH + POWER_GAP))

		row.cellW, row.cellH = w, rowH
	end

	-- Cuantas filas hay SITIO para, que no es lo mismo que cuantas se han
	-- creado alguna vez: `Refresh` no puede ensenar una que `Layout` escondio.
	self.slots = ns.Hall.ROW_N
	self:Refresh()
end

--- Refresco ---------------------------------------------------------------

function P:Refresh()
	if not self.active or not host then return end

	local roster = ns.Selection:GetRosterHeroFirst()
	local primary = ns.Selection:GetPrimary()

	for i = 1, self.slots or 0 do
		local row = rows[i]
		local m = roster[i]
		if not row then break end

		if not m then
			row.unitName, row.unit = nil, nil
			row:Hide()
		else
			row.unitName, row.unit = m.name, m.unit
			row:Show()

			local unit = m.unit
			local dead = UnitIsDeadOrGhost(unit)
			local off  = not UnitIsConnected(unit)

			local c = ns.W:ClassColor(unit)
			row.health:SetStatusBarColor(c.r, c.g, c.b)
			local pc = ns.W:PowerColor(unit)
			row.power:SetStatusBarColor(pc.r, pc.g, pc.b)

			ns.W:Fill(row.health, dead and 0 or UnitHealth(unit), UnitHealthMax(unit))
			ns.W:Fill(row.power, UnitMana(unit) or 0, UnitManaMax(unit) or 0)

			-- EL PRIMARIO SE MARCA EN EL NOMBRE, no con otro marco. Ya hay uno
			-- de seleccion, y dos marcos alrededor de la misma fila diciendo
			-- cosas distintas es lo que hace ilegible una consola. El primario
			-- es de quien son los hechizos de abajo, asi que se dice con el
			-- color del texto, que se lee de reojo sin contar bordes.
			local tag = m.isPlayer and "|cffffd100*|r " or ""
			row.name:SetText(tag .. m.name)
			if m.name == primary then
				row.name:SetTextColor(1, 0.82, 0.2)
			else
				row.name:SetTextColor(0.95, 0.95, 0.95)
			end

			if dead then
				row.hp:SetText("|cffff4444muerto|r")
			elseif off then
				row.hp:SetText("|cff888888fuera|r")
			else
				row.hp:SetText(("|cffaaaaaa%d|r %s"):format(
					UnitLevel(unit) or 0, ns.W:Short(UnitHealth(unit))))
			end

			MarkBox(row, row.cellW or 1, row.cellH or 1,
				ns.Selection:IsSelected(m.name))
		end
	end

	for i = (#roster + 1), (self.slots or 0) do
		if rows[i] then rows[i]:Hide() end
	end
end

--- Entrar y salir ---------------------------------------------------------

function P:Enter()
	host = ns.Hall:Host("list")
	if not host then return end
	self.active = true
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Hall:OnLayout(function() P:Layout() end)
		ns.W:Every(function() P:Refresh() end)
		ns.Selection:Subscribe(function() P:Refresh() end)
		ns.Skills:Subscribe(function() P:Refresh() end)
	end

	self:Layout()
end

function P:Leave()
	self.active = false
	if host then host:Hide() end
end

ns.Hall:Register(P)
