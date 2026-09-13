--[[
	Tray.lua -- la bandeja de la derecha: ocho macros, las bolsas y los botones
	del juego.

	  [M][M][M][M]
	  [M][M][M][M]
	  [llavero][bolsa][bolsa][bolsa][bolsa][mochila]
	  [ficha][hechizos][talentos][misiones][social][pvp][lfg][menu][ayuda]

	=== SON MACROS DE VERDAD, Y ESO ES EL PUNTO ============================

	La rejilla 4x4 de `Panel.lua` llevaba dieciseis ordenes ESCRITAS EN EL
	CODIGO: cada casilla era un boton nuestro con su comando de playerbots
	dentro. Se borro el 2026-09-13 y esto la sustituye, con la diferencia que se
	pidio: aqui no hay ninguna orden escrita. Hay ocho huecos y el jugador
	arrastra a ellos SUS macros, los que `/rts macros` le crea o los que se haya
	hecho el.

	El precio es una vuelta de configuracion la primera vez. Lo que se gana es
	que las ordenes dejan de ser una lista cerrada que hay que venir a tocar
	aqui cada vez que playerbots anada un verbo.

	=== POR QUE EL BOTON ES SEGURO Y LA CASILLA GUARDA EL NOMBRE ===========

	`RunMacro` esta PROTEGIDA en 3.3.5a igual que `CastSpellByName`, asi que un
	boton corriente no puede lanzar un macro por mucho que sepa cual es. Lo que
	si puede es un `SecureActionButtonTemplate` con `type="macro"`: el cliente
	lo lanza por su cuenta y no hay funcion protegida que llamar.

	Y aqui SI vale, al reves que en los huecos de hechizo. La objecion de
	`Skills.lua` -- "un boton seguro no sirve porque su contenido cambia con la
	seleccion y los atributos no se pueden cambiar en combate" -- no aplica:
	estas ocho casillas NO cambian con la seleccion. Se configuran una vez,
	fuera de combate, arrastrando. Lo unico que hace falta es no tocar los
	atributos en combate, y eso esta guardado en cada camino.

	SE GUARDA EL NOMBRE, NO EL INDICE, y es la leccion de `Macros.lua` al
	reves: una barra de accion del juego guarda el indice, asi que borrar y
	recrear los macros recoloca los indices y los botones acaban apuntando a
	otro. Aqui se guarda el nombre, que es lo que el jugador reconoce y lo que
	`/rts macros` respeta al actualizar.

	=== LOS BOTONES DEL JUEGO SON LOS DEL JUEGO ============================

	`Rails.lua` lo intento con botones propios que llamaban a
	`ToggleTalentFrame`, `ToggleWorldMap`, `ToggleGameMenu`... y en juego
	(PRUEBAS-10 G2/G4/G5) el mapa no abria, los talentos no abrian y el menu
	saltaba con "blocked from an action only available to the Blizzard UI".
	Esas funciones estan protegidas y da igual que el boton sea nuestro.

	Asi que aqui no se reimplementan: se MUEVEN los suyos. `CharacterMicroButton`
	y sus hermanos se reparentan a una fila nuestra y se devuelven al salir. Son
	sus botones, con sus manejadores, asi que abren lo que tienen que abrir.

	LAS BOLSAS VAN POR EL MISMO CAMINO Y POR LA MISMA RAZON. La mochila y las
	cuatro bolsas son hijas de `MainMenuBarArtFrame`, o sea que esconder la barra
	principal se las llevaba por delante y en modo RTS no habia bolsas. Son
	botones de objeto del cliente -- aceptan arrastrar, ensenan su cuenta de
	huecos libres, abren con su tecla -- y nada de eso se puede reproducir con un
	boton propio que llame a `ToggleBag`.

	Tres cosas que eso trae y hay que respetar:

	  - Son frames PROTEGIDOS: reparentarlos en combate esta prohibido. Se
	    aplaza a `PLAYER_REGEN_ENABLED`, igual que hace `Chrome`.
	  - `MoveMicroButtons` los recoloca por su cuenta (entrar en un vehiculo, la
	    barra de mascota). Se engancha y se vuelven a poner.
	  - Van a ESCALA NORMAL, no a la de pixel: la fila cuelga de UIParent y se
	    ancla al bloque de macros. Un micro-boton dentro del contenedor de pixel
	    se ve al 62% y parece roto.
]]

local ADDON, ns = ...

local T = {}
ns.Tray = T

T.active = false

local btn = {}            -- i -> boton seguro
local microHooked = false   -- el gancho de MoveMicroButtons, una sola vez
local pendingMicro        -- "in" | "out" mientras se espera a salir de combate

--- Lo guardado ------------------------------------------------------------
--
-- Por CUENTA, igual que los macros que guarda: una orden a un bot no depende de
-- que personaje lleves, y el jugador que configura la bandeja con el guerrero
-- no quiere volver a hacerlo con el mago.

local function Store()
	if not RTSCommandDB then return {} end
	RTSCommandDB.tray = RTSCommandDB.tray or {}
	return RTSCommandDB.tray
end

function T:Get(i)
	local v = Store()[i]
	return type(v) == "string" and v or nil
end

-- Guardar Y APLICAR van juntos a proposito: un atributo seguro puesto sin
-- guardar se pierde al recargar, y uno guardado sin poner es una casilla que se
-- ve llena y no hace nada. Los dos fallos se ven igual desde fuera.
function T:Set(i, name)
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no se puede cambiar un boton seguro.")
		return false
	end
	Store()[i] = name
	local b = btn[i]
	if b then
		b:SetAttribute("macro", name)
		self:Paint(i)
	end
	return true
end

--- El macro de una casilla ------------------------------------------------
--
-- Se resuelve CADA VEZ que se pinta y no se cachea: el jugador puede renombrar
-- o borrar un macro con la bandeja puesta, y una casilla que ensena el icono de
-- algo que ya no existe es peor que una vacia.
local function MacroInfo(name)
	if not name then return nil end
	local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
	if not idx or idx == 0 then return nil end
	local n, tex, body = GetMacroInfo(idx)
	return { index = idx, name = n or name, texture = tex, body = body }
end

--- Dibujar ----------------------------------------------------------------

function T:Paint(i)
	local b = btn[i]
	if not b then return end
	local name = self:Get(i)
	local info = MacroInfo(name)

	if not info then
		b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
		b.icon:SetTexCoord(0, 1, 0, 1)
		b.icon:SetVertexColor(0.35, 0.35, 0.4)
		b.icon:SetAlpha(0.8)
		b.label:SetText("")
		if name then
			-- UN MACRO BORRADO NO SE TIRA DE LA CASILLA. Puede estar renombrado
			-- o puede ser otro personaje con otros macros; borrar la
			-- configuracion del jugador por eso seria perderla sin avisar.
			ns.W:Tip(b, "|cffff8800" .. name .. "|r",
				"Ese macro ya no existe.\nArrastra otro encima, o vuelve a crearlo con |cffffff00/rts macros|r.")
		else
			ns.W:Tip(b, "Casilla " .. i .. " vacia",
				"Arrastra aqui un macro desde la ventana de macros del juego.\n" ..
				"|cffffff00/rts macros|r te crea los de mando a los bots.")
		end
		return
	end

	b.icon:SetTexture(info.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetVertexColor(1, 1, 1)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	local body = (info.body or ""):gsub("^%s+", ""):gsub("%s+$", "")
	ns.W:Tip(b, info.name, (body ~= "" and (body .. "\n") or "") ..
		"|cff888888Arrastra fuera para quitarlo.|r")
end

function T:PaintAll()
	for i = 1, ns.Dock.MACRO_N do self:Paint(i) end
end

--- Coger y soltar ---------------------------------------------------------

-- Lo que lleve el cursor, si es un macro. `GetCursorInfo` devuelve
-- "macro", indice.
local function CursorMacro()
	local kind, a = GetCursorInfo()
	if kind ~= "macro" then return nil end
	local n = GetMacroInfo(a)
	return n
end

local function Slot(i, parent, size)
	local b = btn[i]
	if not b then
		b = ns.W:Button(parent, size, nil, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyUp")
		b:RegisterForDrag("LeftButton")
		b:SetAttribute("type", "macro")
		b.slot = i

		-- SOLTAR ARRASTRANDO.
		b:SetScript("OnReceiveDrag", function(self)
			local name = CursorMacro()
			if not name then return end
			if T:Set(self.slot, name) then ClearCursor() end
		end)

		-- Y SOLTAR HACIENDO CLICK, que es como lo hace todo el mundo en una
		-- barra de accion. El problema es que este boton es seguro: el click
		-- que suelta el macro tambien lo LANZARIA. Asi que si el cursor lleva
		-- uno, se apaga el tipo antes del click y se vuelve a encender despues.
		-- Sin esto, poner un macro de mando lo ejecuta de propina.
		b:SetScript("PreClick", function(self)
			if not CursorMacro() then return end
			-- EN COMBATE NO HAY NADA QUE HACER SALVO DECIRLO. Los atributos de
			-- un boton seguro estan bloqueados, asi que ni se puede apagar el
			-- tipo ni poner el macro: el click va a LANZAR el que ya hubiera.
			-- Callarse dejaria al jugador viendo como su bot hace algo que el
			-- no ha pedido, sin relacion visible con haber arrastrado un macro.
			if InCombatLockdown() then
				ns.Print("|cffff8800bandeja:|r en combate no se puede cambiar una " ..
					"casilla; el click lanza lo que ya tenia.")
				return
			end
			self:SetAttribute("type", "")
		end)
		b:SetScript("PostClick", function(self)
			if InCombatLockdown() then return end
			local name = CursorMacro()
			if name then
				if T:Set(self.slot, name) then ClearCursor() end
			end
			self:SetAttribute("type", "macro")
		end)

		-- COGER ARRASTRANDO. Deja el macro en el cursor -- se puede soltar en
		-- otra casilla o en el vacio -- y vacia esta.
		b:SetScript("OnDragStart", function(self)
			local name = T:Get(self.slot)
			if not name then return end
			local info = MacroInfo(name)
			if info then PickupMacro(info.index) end
			T:Set(self.slot, nil)
		end)

		btn[i] = b
	end
	b:SetAttribute("macro", T:Get(i))
	return b
end

--- LAS DOS FILAS PRESTADAS: las bolsas y los botones del juego -------------
--
-- Las dos son botones DEL CLIENTE que se toman prestados y se devuelven. Ver la
-- cabecera para el porque de no reimplementarlos.
--
-- De arriba abajo: macros, BOLSAS, botones del juego. Las bolsas van pegadas a
-- los macros porque se usan jugando y el menu de juego casi nunca; y van encima
-- del menu, no debajo, porque el menu es el suelo de todo el bloque -- si se
-- mueve el ultimo, se mueve lo de arriba con el.

local MICRO = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
	"PVPMicroButton", "LFDMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

-- EN EL ORDEN DEL JUEGO, que es el que los dedos tienen aprendido: el llavero a
-- la izquierda, las cuatro bolsas de derecha a izquierda y la mochila al final.
-- Invertirlo "para que se lea de 1 a 4" seria cambiar de sitio la mochila, que
-- es la unica que se pulsa sin mirar.
local BAGS = {
	"KeyRingButton",
	"CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot",
	"CharacterBag0Slot", "MainMenuBarBackpackButton",
}

-- Los micro-botones se solapan a proposito en la barra de Blizzard: su arte
-- lleva el borde compartido dentro, asi que separarlos deja diez botones
-- sueltos y mal cortados. Las bolsas no: son cuadros independientes.
local ROWS = {
	{ key = "bags",  names = BAGS,  gap = 2  },
	{ key = "micro", names = MICRO, gap = -3 },
}

local ROW_GAP = 4     -- entre las dos filas, en unidades de pantalla

local rowOf = {}      -- key -> { frame = , was = {} }

local function RowNames(r)
	-- Para los micro-botones el cliente tiene su propia lista (`MainMenuBar.lua`)
	-- y esa es mejor que la nuestra: sabe cuales existen en ESTA version. La
	-- nuestra es el respaldo.
	if r.key == "micro" and type(_G.MICRO_BUTTONS) == "table"
	   and #_G.MICRO_BUTTONS > 0 then
		return _G.MICRO_BUTTONS
	end
	return r.names
end

local function RowButtons(r)
	local out = {}
	for _, name in ipairs(RowNames(r)) do
		local f = _G[name]
		if f then table.insert(out, f) end
	end
	return out
end

-- Colocar una fila y devolver su alto. A escala NORMAL: la fila cuelga de
-- UIParent (ver la cabecera).
local function PlaceRow(r)
	local hold = rowOf[r.key]
	if not (hold and hold.frame) then return 0 end
	local x, h = 0, 0
	for _, f in ipairs(RowButtons(r)) do
		f:SetParent(hold.frame)
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", hold.frame, "BOTTOMLEFT", x, 0)
		f:Show()
		x = x + f:GetWidth() + r.gap
		if f:GetHeight() > h then h = f:GetHeight() end
	end
	hold.frame:SetWidth(math.max(x - r.gap, 1))
	hold.frame:SetHeight(math.max(h, 1))
	return h
end

-- Lo que `Dock` tiene que reservar debajo del bloque de macros, EN PIXELES: las
-- filas estan a escala normal y el Dock mide en pixeles fisicos, asi que hay que
-- pasar de una a otra o el hueco sale corto en una pantalla y largo en otra.
local function ReserveFoot(total)
	local host = ns.Pixels:Host()
	local k = (host and host:GetEffectiveScale() or 1)
	if k <= 0 then k = 1 end
	local row = rowOf.micro and rowOf.micro.frame
	local rs = row and row:GetEffectiveScale() or 1
	ns.Dock:SetRightFoot(math.floor(total * (rs / k) + 0.5) + 8)
end

local function PlaceBorrowed()
	local total = 0
	for _, r in ipairs(ROWS) do
		local h = PlaceRow(r)
		if h > 0 then total = total + h + ROW_GAP end
	end
	ReserveFoot(total)
end

local function GrabBorrowed()
	if InCombatLockdown() then
		pendingMicro = "in"
		return
	end
	pendingMicro = nil

	for _, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold then
			for _, f in ipairs(RowButtons(r)) do
				local name = f:GetName()
				if name and not hold.was[name] then
					local pts = {}
					for i = 1, f:GetNumPoints() do
						pts[i] = { f:GetPoint(i) }
					end
					hold.was[name] = { parent = f:GetParent(), points = pts }
				end
			end
		end
	end

	PlaceBorrowed()

	if not microHooked and type(_G.MoveMicroButtons) == "function" then
		microHooked = true
		-- El cliente los recoloca solo (vehiculo, barra de mascota). No se
		-- pelea con el evento que lo provoca: se vuelve a poner despues.
		hooksecurefunc("MoveMicroButtons", function()
			if T.active and not InCombatLockdown() then PlaceBorrowed() end
		end)
	end
end

-- Devuelve si se ha podido: en combate no, y quien llama tiene que saberlo
-- para no esconder las filas con los botones del cliente todavia dentro.
local function ReleaseBorrowed()
	if InCombatLockdown() then
		pendingMicro = "out"
		return false
	end
	pendingMicro = nil

	for _, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold then
			for name, was in pairs(hold.was) do
				local f = _G[name]
				if f then
					f:SetParent(was.parent or MainMenuBarArtFrame or UIParent)
					f:ClearAllPoints()
					for _, p in ipairs(was.points) do
						f:SetPoint(unpack(p))
					end
				end
			end
			hold.was = {}
		end
	end
	return true
end

--- Distribuir -------------------------------------------------------------

function T:Layout()
	if not self.active then return end
	local hostF = ns.Dock:Host("macros")
	if not hostF then return end

	local cells = ns.Dock:MacroCells()
	for i = 1, ns.Dock.MACRO_N do
		local c = cells[i]
		if c then
			local b = Slot(i, hostF, c.w)
			b:SetParent(hostF)
			b:SetWidth(c.w)
			b:SetHeight(c.h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", hostF, "TOPLEFT", c.x, -c.y)
			b:Show()
			self:Paint(i)
		elseif btn[i] then
			btn[i]:Hide()
		end
	end

	-- LAS DOS FILAS PRESTADAS, COLGANDO UNA DE OTRA. Cada una se ancla a lo que
	-- tiene ENCIMA, asi que si una crece o desaparece la de abajo la sigue sin
	-- un solo numero mas.
	local above = hostF
	local point = "BOTTOMRIGHT"
	for _, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold and hold.frame then
			hold.frame:ClearAllPoints()
			hold.frame:SetPoint("TOPRIGHT", above, point, 0, -ROW_GAP)
			above, point = hold.frame, "BOTTOMRIGHT"
		end
	end
end

--- Entrar y salir ---------------------------------------------------------

function T:Enter()
	self.active = true

	for _, r in ipairs(ROWS) do
		if not rowOf[r.key] then
			-- DE UIParent, no del contenedor de pixel: ver la cabecera.
			local f = CreateFrame("Frame", "RTSTray_" .. r.key, UIParent)
			f:SetFrameStrata("MEDIUM")
			f:SetWidth(1)
			f:SetHeight(1)
			rowOf[r.key] = { frame = f, was = {} }
		end
		rowOf[r.key].frame:Show()
	end

	if not self.wired then
		self.wired = true
		ns.Dock:OnLayout(function() T:Layout() end)

		local ev = CreateFrame("Frame", "RTSTrayEvents")
		ev:RegisterEvent("UPDATE_MACROS")
		ev:RegisterEvent("PLAYER_REGEN_ENABLED")
		ev:SetScript("OnEvent", function(_, event)
			if event == "UPDATE_MACROS" then
				if T.active then T:PaintAll() end
				return
			end
			-- Salir de combate: lo que quedo aplazado.
			if pendingMicro == "in" and T.active then
				GrabBorrowed()
			elseif pendingMicro == "out" and not T.active then
				ReleaseBorrowed()
			end
			if T.active then
				for i = 1, ns.Dock.MACRO_N do
					local b = btn[i]
					if b then b:SetAttribute("macro", T:Get(i)) end
				end
			end
		end)
	end

	GrabBorrowed()
	self:Layout()
end

function T:Leave()
	self.active = false
	for _, b in pairs(btn) do b:Hide() end
	-- LAS FILAS SOLO SE ESCONDEN SI SE HAN PODIDO DEVOLVER. En combate no se
	-- pueden (son frames protegidos), y esconderlas con los botones dentro es la
	-- forma de quedarse sin bolsas y sin menu hasta que acabe la pelea.
	if ReleaseBorrowed() then
		for _, r in ipairs(ROWS) do
			local hold = rowOf[r.key]
			if hold and hold.frame then hold.frame:Hide() end
		end
	end
end

function T:Report()
	ns.Print("|cffffff00bandeja|r -- ocho casillas de macro:")
	for i = 1, ns.Dock.MACRO_N do
		local name = self:Get(i)
		local info = MacroInfo(name)
		ns.Print(("  %d. %s"):format(i,
			info and ("|cff33ccff" .. info.name .. "|r")
			or (name and ("|cffff8800" .. name .. "|r (ya no existe)")
			or "|cff666666vacia|r")))
	end
	ns.Print("Se llenan |cffffff00arrastrando|r macros desde la ventana del juego.")
end

function T:Clear()
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no, son botones seguros.")
		return
	end
	for i = 1, ns.Dock.MACRO_N do self:Set(i, nil) end
	ns.Print("bandeja: las ocho casillas vacias.")
end

ns.Dock:Register(T)
