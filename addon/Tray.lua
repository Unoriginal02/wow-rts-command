--[[
	Tray.lua -- la bandeja de la derecha: diez casillas, las bolsas y los botones
	del juego.

	  [M][M][M][M][M]
	  [M][M][M][M][M]
	  [llavero][bolsa][bolsa][bolsa][bolsa][mochila]
	  [ficha][hechizos][talentos][misiones][social][pvp][lfg][menu][ayuda]

	=== UNA CASILLA ADMITE DOS COSAS, Y SON DISTINTAS =======================

	  CLIC DERECHO -> el desplegable de `Actions.lua`, con las ordenes del
	  addon y sus iconos. No son macros: no gastan ninguno de los 36 huecos de
	  la cuenta y pueden llevar arte nuestro, que es lo que los macros NO
	  pueden -- su icono sale por numero de una lista cerrada del cliente donde
	  no hay ni bolsas del grupo ni registro de misiones.

	  ARRASTRAR -> un macro del juego, como siempre. Sigue haciendo falta para
	  todo lo que lleve un verbo protegido dentro (`/cast`, `/use`, `/target`),
	  que desde Lua no se puede lanzar ni con el mejor boton.

	Lo guardado distingue los dos casos por su forma: una cadena es el nombre de
	un macro y una tabla `{ act = "id" }` es una orden del catalogo. Las
	casillas configuradas antes de esto eran cadenas, asi que siguen valiendo
	sin convertir nada.

	=== POR QUE EL BOTON ES SEGURO Y LA CASILLA GUARDA EL NOMBRE ===========

	`RunMacro` esta PROTEGIDA en 3.3.5a igual que `CastSpellByName`, asi que un
	boton corriente no puede lanzar un macro por mucho que sepa cual es. Lo que
	si puede es un `SecureActionButtonTemplate` con `type="macro"`: el cliente
	lo lanza por su cuenta y no hay funcion protegida que llamar.

	Y aqui SI vale, al reves que en los huecos de hechizo. La objecion de
	`Skills.lua` -- "un boton seguro no sirve porque su contenido cambia con la
	seleccion y los atributos no se pueden cambiar en combate" -- no aplica:
	estas casillas NO cambian con la seleccion. Se configuran una vez,
	fuera de combate, arrastrando. Lo unico que hace falta es no tocar los
	atributos en combate, y eso esta guardado en cada camino.

	EL CLIC DERECHO SE APAGA CON `type2 = ""`, y esa es la linea que lo deja
	libre para el desplegable. Un boton seguro busca primero el atributo del
	BOTON que has pulsado (`type2` para el derecho) y solo si no lo encuentra
	usa el general (`type`), asi que poner uno vacio ahi es decirle "con el
	derecho, nada" sin tocar lo que hace el izquierdo.

	Y SE HACE ASI, Y NO PONIENDO `type1` EN VEZ DE `type`, por como falla cada
	uno. Las dos formas dependen de lo mismo -- que el cliente mire el atributo
	por boton -- pero si eso no fuera cierto, con `type1` los macros no se
	lanzarian NUNCA, y asi lo peor que pasa es que el derecho lance el macro
	ademas de abrir el menu, que es lo que ya hacia ayer.

	Las ordenes del catalogo no necesitan nada de esto: se lanzan desde
	`PostClick`, que es codigo corriente, porque lo que hay dentro de ellas --
	`/rts ...` y `/rtscmd ...` -- no esta protegido.

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

-- El NOMBRE DEL MACRO de una casilla, si lo que lleva es un macro.
function T:Get(i)
	local v = Store()[i]
	return type(v) == "string" and v or nil
end

-- La ORDEN DEL CATALOGO de una casilla, si lo que lleva es una orden.
function T:Action(i)
	local v = Store()[i]
	if type(v) ~= "table" then return nil end
	return type(v.act) == "string" and v.act or nil
end

-- El atributo seguro que le toca a la casilla `i`. En un solo sitio porque lo
-- piden tres caminos (poner, redibujar y salir de combate) y un atributo a
-- medias es una casilla que se ve llena y no hace nada.
local function Apply(b, i)
	local macro = T:Get(i)
	b:SetAttribute("macro", macro)
	b:SetAttribute("type", macro and "macro" or nil)
	-- El derecho, apagado a mano y siempre: ver la cabecera.
	b:SetAttribute("type2", "")
end

-- Guardar Y APLICAR van juntos a proposito: un atributo seguro puesto sin
-- guardar se pierde al recargar, y uno guardado sin poner es una casilla que se
-- ve llena y no hace nada. Los dos fallos se ven igual desde fuera.
--
-- `value` es el nombre de un macro, `{ act = "id" }`, o nada para vaciarla.
function T:Set(i, value)
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no se puede cambiar un boton seguro.")
		return false
	end
	if value == false then value = nil end
	Store()[i] = value
	local b = btn[i]
	if b then
		Apply(b, i)
		self:Paint(i)
	end
	return true
end

--- Elegir una orden -------------------------------------------------------
--
-- El desplegable lo dibuja `Actions.lua`; aqui solo se dice sobre que casilla
-- se abre y que hacer con lo elegido.
function T:Choose(i)
	local b = btn[i]
	if not b then return end
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no se puede cambiar una casilla.")
		return
	end
	ns.Actions:Open(b, "Casilla " .. i, self:Action(i), function(id)
		T:Set(i, id and { act = id } or nil)
	end)
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

-- El pie de todos los tooltips de la bandeja: como se cambia una casilla. Va en
-- todos porque el clic derecho no se ve -- no hay nada en pantalla que lo
-- anuncie -- y una funcion escondida es una funcion que no existe.
local HINT = "|cff888888Clic derecho: elegir orden. Arrastra un macro para poner uno.|r"

local function Empty(b, tip, body)
	b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
	b.icon:SetTexCoord(0, 1, 0, 1)
	b.icon:SetVertexColor(0.35, 0.35, 0.4)
	b.icon:SetAlpha(0.8)
	b.label:SetText("")
	ns.W:Tip(b, tip, body)
end

function T:Paint(i)
	local b = btn[i]
	if not b then return end

	-- UNA ORDEN DEL CATALOGO. Va primero porque es lo que se pone con el clic
	-- derecho, que es la forma normal de llenar una casilla desde hoy.
	local id = self:Action(i)
	if id then
		local e = ns.Actions:Find(id)
		if e then
			ns.Actions:Paint(b.icon, e)
			b.label:SetText("")
			ns.W:Tip(b, e.name, (e.d or "") .. "\n" .. HINT)
		else
			-- Una orden que se quito del catalogo. No se borra la casilla sola:
			-- misma regla que con un macro renombrado, mas abajo.
			Empty(b, "|cffff8800" .. id .. "|r",
				"Esa orden ya no esta en el catalogo.\n" .. HINT)
		end
		return
	end

	local name = self:Get(i)
	local info = MacroInfo(name)

	if not info then
		if name then
			-- UN MACRO BORRADO NO SE TIRA DE LA CASILLA. Puede estar renombrado
			-- o puede ser otro personaje con otros macros; borrar la
			-- configuracion del jugador por eso seria perderla sin avisar.
			Empty(b, "|cffff8800" .. name .. "|r",
				"Ese macro ya no existe.\nVuelve a crearlo con |cffffff00/rts macros|r.\n" .. HINT)
		else
			Empty(b, "Casilla " .. i .. " vacia",
				"|cffffff00Clic derecho|r (o izquierdo) para elegir una orden.\n" ..
				"O arrastra aqui un macro de los del juego.")
		end
		return
	end

	b.icon:SetTexture(info.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetVertexColor(1, 1, 1)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	local body = (info.body or ""):gsub("^%s+", ""):gsub("%s+$", "")
	ns.W:Tip(b, info.name, (body ~= "" and (body .. "\n") or "") .. HINT)
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
			self:SetAttribute("type", nil)
		end)

		-- LO QUE PASA DESPUES DEL CLICK, EN ORDEN. El boton seguro ya ha hecho
		-- lo suyo (o nada, si la casilla no lleva un macro) y aqui se decide el
		-- resto: soltar lo que traiga el cursor, abrir el desplegable con el
		-- derecho, o lanzar la orden del catalogo con el izquierdo.
		b:SetScript("PostClick", function(self, button)
			if InCombatLockdown() then return end

			local dragged = CursorMacro()
			if dragged then
				if T:Set(self.slot, dragged) then ClearCursor() end
				return
			end
			-- Se restaura SIEMPRE, no solo cuando venia un macro en el cursor:
			-- `PreClick` lo apago antes de saber como iba a acabar esto.
			Apply(self, self.slot)

			if button == "RightButton" then
				T:Choose(self.slot)
				return
			end

			local id = T:Action(self.slot)
			if id then
				ns.Actions:Run(id)
			elseif not T:Get(self.slot) then
				-- UNA CASILLA VACIA SE OFRECE AL CLICK IZQUIERDO. No hace nada
				-- mas y el clic derecho no se ve en pantalla; sin esto, una
				-- bandeja recien puesta parece rota.
				T:Choose(self.slot)
			end
		end)

		-- COGER ARRASTRANDO. Deja el macro en el cursor -- se puede soltar en
		-- otra casilla o en el vacio -- y vacia esta.
		--
		-- SOLO VALE PARA LOS MACROS. Una orden del catalogo no existe fuera de
		-- este addon, asi que no hay nada que dejar en el cursor: arrastrarla se
		-- queda quieta a proposito, y se quita desde el desplegable.
		b:SetScript("OnDragStart", function(self)
			local name = T:Get(self.slot)
			if not name then return end
			local info = MacroInfo(name)
			if info then PickupMacro(info.index) end
			T:Set(self.slot, nil)
		end)

		btn[i] = b
	end
	Apply(b, i)
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

-- LOS DOS HUECOS NO SON EL MISMO. Entre las bolsas y el menu de juego basta con
-- separarlos; entre el bloque de macros y las bolsas hace falta MAS, porque ahi
-- cambia de que va la cosa -- arriba son ordenes a los bots y abajo son cosas
-- tuyas -- y con el mismo aire los diez macros y las seis bolsas se leen como
-- una sola rejilla de tres filas.
local TOP_GAP = 12    -- entre el bloque de macros y la primera fila prestada

-- Y ESTE ES NEGATIVO A PROPOSITO. Los micro-botones del cliente miden 58 de
-- alto y su dibujo no llega abajo del todo: el arte lleva aire dentro, que es
-- lo que en la barra de Blizzard queda tapado por el borde de la propia barra.
-- Aqui no hay barra que lo tape, asi que un hueco de 4 se ve como veinte
-- pixeles de nada entre las bolsas y el menu.
--
-- Se compensa subiendo la fila dentro de su hueco. El numero esta puesto A OJO
-- contra la pantalla -- el aire del dibujo no se puede medir desde Lua -- y por
-- eso esta aqui solo, con nombre, y no sumado dentro de otra cuenta.
local ROW_GAP = -14   -- entre las dos filas prestadas

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
	-- El respiro de debajo lo pone `Dock`, que es quien tiene que cuadrar el
	-- bloque del centro a la misma altura.
	ns.Dock:SetRightFoot(math.floor(total * (rs / k) + 0.5) + ns.Dock:FootPad())
end

-- El hueco que va ENCIMA de cada fila. El primero es mas grande: ver arriba.
local function GapBefore(i)
	return (i == 1) and TOP_GAP or ROW_GAP
end

local function PlaceBorrowed()
	local total = 0
	for i, r in ipairs(ROWS) do
		local h = PlaceRow(r)
		-- El hueco cuenta ANTES de la fila, igual que lo aplica el anclaje. Si
		-- aqui se sumara "detras" saldria el mismo numero por casualidad hoy y
		-- dejaria de salir en cuanto los dos huecos dejaran de ser iguales --
		-- que es justo lo que acaba de pasar.
		if h > 0 then total = total + GapBefore(i) + h end
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
	for i, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold and hold.frame then
			hold.frame:ClearAllPoints()
			hold.frame:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -GapBefore(i))
			above = hold.frame
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
					if b then Apply(b, i) end
				end
			end
		end)
	end

	GrabBorrowed()
	self:Layout()
end

function T:Leave()
	self.active = false
	-- EL DESPLEGABLE NO CUELGA DE LA BANDEJA, asi que esconder las casillas no
	-- se lo lleva por delante: quedaria un menu flotando sobre el mundo con el
	-- atrapa-clicks puesto, o sea la pantalla entera sin responder.
	ns.Actions:Close()
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
	ns.Print(("|cffffff00bandeja|r -- %d casillas:"):format(ns.Dock.MACRO_N))
	for i = 1, ns.Dock.MACRO_N do
		local what
		local id = self:Action(i)
		if id then
			local e = ns.Actions:Find(id)
			what = e and ("|cff33ccff" .. e.name .. "|r |cff888888(orden)|r")
				or ("|cffff8800" .. id .. "|r (ya no esta en el catalogo)")
		else
			local name = self:Get(i)
			local info = MacroInfo(name)
			what = info and ("|cff33ccff" .. info.name .. "|r |cff888888(macro)|r")
				or (name and ("|cffff8800" .. name .. "|r (ya no existe)")
				or "|cff666666vacia|r")
		end
		ns.Print(("  %d. %s"):format(i, what))
	end
	ns.Print("|cffffff00Clic derecho|r en una casilla para elegir orden; " ..
		"arrastra un macro para poner uno del juego.")
end

function T:Clear()
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no, son botones seguros.")
		return
	end
	for i = 1, ns.Dock.MACRO_N do self:Set(i, nil) end
	ns.Print(("bandeja: las %d casillas vacias."):format(ns.Dock.MACRO_N))
end

ns.Dock:Register(T)
