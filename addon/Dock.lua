--[[
	Dock.lua -- el reparto de la parte de abajo.

	Sustituye a `Bar.lua` (el arte de la consola) y a `Hall.lua` (el reparto de
	su sala), los dos borrados el 2026-09-13. La consola de una pieza con el
	minimapa dentro se descarta entera: el minimapa vuelve a su sitio de
	siempre, los marcos de jugador, objetivo y grupo son los del juego, y lo
	unico que el addon dibuja abajo son BARRAS DE ACCION.

	  +---------------------------------------------------------------+
	  |                                                               |
	  |              Bob  (dps)                                       |
	  |        [1][2][3][4][5][6][7][8][9][0]    [M][M][M][M]         |
	  |                                          [M][M][M][M]         |
	  |                                          [bolsas]             |
	  |                                          [ficha][talentos]... |
	  +---------------------------------------------------------------+

	EN MEDIO: LA UNIDAD, o las unidades. A LA DERECHA: LO TUYO -- los macros de
	mando, las bolsas y los botones del juego. La division no es estetica: lo
	del centro CAMBIA con cada click de seleccion y lo de la derecha no se mueve
	nunca. Mezclarlos obligaria al ojo a comprobar cada vez si el boton que
	busca sigue donde estaba.

	Y por eso el que se centra es el del centro: lo que cambia de ancho se
	recoloca solo alrededor del mismo eje, y lo que no cambia se queda clavado a
	su esquina.

	=== DOS ESTADOS, Y LOS DECIDE LA SELECCION ==============================

	  A  ninguno o uno    el nombre y DIEZ huecos
	  B  dos o mas        una columna por cabeza: nombre y 2x2 de CUATRO

	Y SOLO EL NOMBRE. Hubo un rotulo de POSTURA al lado, que ensenaba el rol de
	playerbots (tank/dps/heal) y dejaba cambiarlo. Se borro entero el mismo dia
	que nacio, por dos razones que van juntas:

	  - No era lo que se pidio. "La postura de combate" de un guerrero es armas,
	    defensiva o berserker; el rol de playerbots es otra cosa y ponerlo ahi
	    con ese nombre era contestar otra pregunta.
	  - Y lo que se pedia NO NECESITA INTERFAZ. Una postura es un HECHIZO: la
	    tuya cabe en un macro (`/cast Postura defensiva`) que se arrastra a la
	    bandeja, y la de un bot sale en su lista de hechizos, asi que se pone en
	    uno de sus diez huecos con click derecho. Un boton propio para eso seria
	    una tercera forma de hacer lo que ya hacen dos.

	El rol de los bots lo decide playerbots, que es de quien es.

	SIN NADA SELECCIONADO SALES TU, y esto es lo contrario de lo que hacia la
	sala. Alli el centro se vaciaba al soltar la seleccion, porque dibujar los
	huecos de alguien sin tenerlo cogido se leia como que seguia cogido. Aqui no
	hay esa ambiguedad: sin seleccion el dueno eres TU, con tu nombre escrito
	encima, que es exactamente lo que ensena una barra de accion normal cuando
	no estas mandando a nadie.

	=== LOS CUATRO DEL ESTADO B NO SON LOS CUATRO PRIMEROS DE LOS DIEZ =======

	Y este SI es un cambio deliberado respecto a la sala, pedido el 2026-09-13.
	Antes el 2x2 ensenaba los huecos 1..4 de la misma fila, con el argumento de
	que dos listas son dos sitios donde configurar lo mismo. El argumento en
	contra es mas fuerte: con cuatro cogidos no quieres los cuatro primeros
	hechizos de cada uno, quieres LO QUE SE MANDA EN GRUPO -- el aturdimiento,
	la curacion de emergencia, el escudo -- que casi nunca son los mismos que
	usas cuando llevas a uno solo.

	Son dos juegos guardados por personaje (`Skills`: `main` y `group`) y el
	tamano de cada uno es fijo: diez y cuatro. Se configuran igual, con click
	derecho, asi que no hay dos gestos que aprender.

	=== TODO EN PIXELES FISICOS =============================================

	El Dock cuelga de `ns.Pixels:Host()`, que lleva la escala 768/altoFisico: de
	sus hijos para dentro, una unidad es un pixel. Se queda esa convencion --
	que es la que ya usan `Widgets` y las ventanas propias -- aunque hoy no haya
	arte que lo justifique, porque el dia que lo haya se justifica solo y
	mientras tanto el LADO DEL HUECO SALE MEDIDO del propio cliente
	(`Pixels:ActionButtonPixels`): un hueco de esta barra mide exactamente lo
	que un boton de la barra de acciones del juego.

	=== QUIEN DIBUJA NO ES ESTE FICHERO =====================================

	Mismo contrato que tenian `Bar` y `Hall`, que es lo mejor que tiene el
	addon: aqui estan las AREAS y el ESTADO, y el contenido lo ponen `Cast`
	(los huecos) y `Tray` (los macros y los botones del juego), que se apuntan
	solos con `Dock:Register(m)` y piden su marco con `Dock:Host(key)`.
]]

local ADDON, ns = ...

local D = {}
ns.Dock = D

D.active = false

--- Las medidas, en pixeles fisicos ----------------------------------------

-- El margen contra el borde de la pantalla. El mismo a los dos lados y abajo:
-- dos bloques que arrancan a distinta altura se leen como descuadrados.
local MARGIN = 30

-- El lado del hueco SALE MEDIDO, con techo y suelo por si la medida no se
-- puede hacer (sin barra de acciones cargada devuelve el 36 de fabrica).
local SLOT_MIN, SLOT_MAX = 38, 84
local GAP = 7

local MAIN_N = 10       -- los huecos del estado A
local B_SLOTS = 4       -- el 2x2 del estado B
local B_COLS, B_ROWS = 2, 2

local HEAD_H   = 32     -- la cabecera del estado A: el nombre
local HEAD_GAP = 8
local B_HEAD_H = 26
local B_HEAD_GAP = 6
local COL_GAP  = 30     -- entre columnas del estado B

local MACRO_COLS, MACRO_ROWS = 4, 2

D.MAIN_N  = MAIN_N
D.B_SLOTS = B_SLOTS
D.MACRO_N = MACRO_COLS * MACRO_ROWS

--- Estado interno ---------------------------------------------------------

local host                -- el contenedor de escala de pixel
local left, right         -- los dos marcos raiz (`left` es el centrado)
local rightFoot = 0       -- lo que `Tray` reserva debajo para los botones del juego
local frames = {}         -- key -> Frame
local rects  = {}         -- key -> { x, y, w, h } dentro de SU raiz
local panels = {}
local listeners = {}

local function Slot()
	local px = ns.Pixels:ActionButtonPixels() or 58
	px = math.floor(px + 0.5)
	if px < SLOT_MIN then px = SLOT_MIN elseif px > SLOT_MAX then px = SLOT_MAX end
	return px
end

--- Registro ---------------------------------------------------------------

-- `m` necesita `Enter`/`Leave`, los dos opcionales. Con la guarda de doble
-- registro de siempre: dos `Enter` son botones duplicados encima de los suyos,
-- y un `/reload` no deberia poder provocarlo.
function D:Register(m)
	if not m then return end
	for _, other in ipairs(panels) do
		if other == m then return end
	end
	table.insert(panels, m)
	if self.active and m.Enter then m:Enter() end
end

function D:OnLayout(fn)
	table.insert(listeners, fn)
	if self.active then pcall(fn) end
end

local function Announce()
	for _, fn in ipairs(listeners) do
		-- Un modulo que falle no puede dejar la barra a medio colocar ni
		-- llevarse por delante a los demas.
		local ok, err = pcall(fn)
		if not ok then ns.Print("|cffff0000dock:|r " .. tostring(err)) end
	end
end

--- El estado --------------------------------------------------------------

function D:State()
	return (ns.Selection:Count() >= 2) and "B" or "A"
end

-- De quien es la fila de huecos en el estado A. El unico seleccionado, y si no
-- hay ninguno, TU: ver la cabecera.
function D:Subject()
	return ns.Selection:Single() or ns.MyName()
end

-- Los personajes cuyas columnas se dibujan en el estado B, en el orden del
-- grupo con el heroe primero -- que es el orden que el jugador tiene delante en
-- los marcos del juego.
function D:Columns()
	local out = {}
	for _, m in ipairs(ns.Selection:GetRosterHeroFirst()) do
		if ns.Selection:IsSelected(m.name) then
			table.insert(out, m)
		end
	end
	return out
end

--- El reparto -------------------------------------------------------------

local function Rect(key, x, y, w, h)
	rects[key] = { x = x, y = y, w = w, h = h }
end

local function Recompute()
	rects = {}
	local s = Slot()
	D.slot = s

	--- IZQUIERDA ---------------------------------------------------------
	if D:State() == "A" then
		local w = MAIN_N * s + GAP * (MAIN_N - 1)
		D.leftW = w
		D.leftH = HEAD_H + HEAD_GAP + s
		Rect("head",   0, 0, w, HEAD_H)
		Rect("spells", 0, HEAD_H + HEAD_GAP, w, s)
		D.cols = 0
	else
		local cols = #D:Columns()
		local colW = B_COLS * s + GAP * (B_COLS - 1)
		local colH = B_HEAD_H + B_HEAD_GAP + B_ROWS * s + GAP * (B_ROWS - 1)
		D.colW, D.colH = colW, colH
		D.cols = cols
		D.leftW = cols * colW + COL_GAP * math.max(cols - 1, 0)
		D.leftH = colH
		for i = 1, cols do
			Rect("col" .. i, (i - 1) * (colW + COL_GAP), 0, colW, colH)
		end
	end

	--- DERECHA -----------------------------------------------------------
	--
	-- El bloque de macros manda el ancho; la fila de botones del juego cuelga
	-- por debajo y la mide `Tray`, que es quien sabe lo que ocupan los
	-- micro-botones del cliente (son suyos y tienen su propio tamano).
	local mw = MACRO_COLS * s + GAP * (MACRO_COLS - 1)
	local mh = MACRO_ROWS * s + GAP * (MACRO_ROWS - 1)
	D.rightW, D.rightH = mw, mh
	Rect("macros", 0, 0, mw, mh)
end

--- Lo que usan los modulos de contenido -----------------------------------

function D:Get(key) return rects[key] end

local function RootFor(key)
	if key == "macros" then return right end
	return left
end

local function Place(key, f)
	local r = rects[key]
	local root = RootFor(key)
	if r and root and r.w > 0 and r.h > 0 then
		f:SetParent(root)
		f:SetWidth(r.w)
		f:SetHeight(r.h)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", root, "TOPLEFT", r.x, -r.y)
		f:Show()
	else
		f:Hide()
	end
end

-- El marco de un area. Se crean bajo demanda y no se destruyen -- pasar del
-- estado B al A esconde las columnas en vez de borrarlas.
--
-- SE COLOCA AL CREARLO, y eso no es un detalle: `Layout` reparte sobre los
-- marcos QUE YA EXISTEN y avisa DESPUES, pero los de columna solo los pide el
-- contenido, que corre dentro de ese aviso. Sin colocarlos aqui, la primera vez
-- que se cogen varios nacen de 0x0 y sin anclar y no sale ni una columna. Es un
-- fallo que ya se pago una vez en `Hall.lua`.
function D:Host(key)
	local root = RootFor(key)
	if not root then return nil end
	local f = frames[key]
	if not f then
		f = CreateFrame("Frame", "RTSDock_" .. key, root)
		f:SetFrameLevel(root:GetFrameLevel() + 2)
		f:EnableMouse(false)
		frames[key] = f
		Place(key, f)
	end
	return f
end

--- Las celdas, en coordenadas de SU marco ---------------------------------

function D:SpellCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	for i = 1, MAIN_N do
		out[i] = { x = (i - 1) * (s + GAP), y = 0, w = s, h = s }
	end
	return out
end

function D:ColumnSpellCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	local y0 = B_HEAD_H + B_HEAD_GAP
	for i = 1, B_SLOTS do
		local c = (i - 1) % B_COLS
		local r = math.floor((i - 1) / B_COLS)
		out[i] = { x = c * (s + GAP), y = y0 + r * (s + GAP), w = s, h = s }
	end
	return out
end

function D:MacroCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	for i = 1, MACRO_COLS * MACRO_ROWS do
		local c = (i - 1) % MACRO_COLS
		local r = math.floor((i - 1) / MACRO_COLS)
		out[i] = { x = c * (s + GAP), y = r * (s + GAP), w = s, h = s }
	end
	return out
end

function D:HeadHeight()  return HEAD_H end
function D:BHeadHeight() return B_HEAD_H end
function D:ColWidth()    return self.colW or 0 end
function D:Margin()      return MARGIN end

-- LO QUE `Tray` RESERVA DEBAJO para la fila de botones del juego, en pixeles.
-- No lo decide este fichero porque no puede: los micro-botones son del cliente
-- y miden lo que ellos midan. Se pide aqui en vez de anclar la fila al suelo y
-- los macros encima, porque asi el bloque de macros no se mueve cada vez que el
-- cliente ensena u oculta uno de sus botones.
function D:SetRightFoot(px)
	rightFoot = px or 0
	if not (right and host) then return end
	right:ClearAllPoints()
	right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -MARGIN, MARGIN + rightFoot)
end

--- Distribuir -------------------------------------------------------------

function D:Layout()
	if not left then return end
	Recompute()

	left:SetWidth(math.max(self.leftW or 1, 1))
	left:SetHeight(math.max(self.leftH or 1, 1))
	right:SetWidth(math.max(self.rightW or 1, 1))
	right:SetHeight(math.max(self.rightH or 1, 1))

	-- Un area que este reparto no produjo se ESCONDE en vez de quedarse donde
	-- estaba: pasar de B a A dejaria cinco columnas dibujadas sobre la fila.
	for key, f in pairs(frames) do
		Place(key, f)
	end

	Announce()
end

--- Entrar y salir ---------------------------------------------------------

function D:Enter()
	if not left then
		host = ns.Pixels:Host()
		if not host then return end

		-- CENTRADA, y por eso se ancla por el BOTTOM y no por una esquina: el
		-- bloque cambia de ancho con cada seleccion -- diez huecos con uno
		-- cogido, cinco columnas con cinco -- y anclado por el centro se
		-- recoloca solo sin una sola cuenta. Con una esquina habria que
		-- recalcular la x en cada cambio de estado, que es la clase de numero
		-- que se olvida en el tercer sitio.
		left = CreateFrame("Frame", "RTSDockLeft", host)
		left:SetPoint("BOTTOM", host, "BOTTOM", 0, MARGIN)
		left:EnableMouse(false)

		-- LA DERECHA SE ANCLA POR ABAJO IGUAL QUE LA IZQUIERDA, y encima suyo
		-- se pone `Tray` su fila de botones del juego. Al reves -- la fila
		-- anclada al suelo y los macros encima -- el bloque entero se movia
		-- cada vez que el cliente ensena u oculta un micro-boton.
		right = CreateFrame("Frame", "RTSDockRight", host)
		right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -MARGIN, MARGIN + rightFoot)
		right:EnableMouse(false)
	end

	self.active = true
	left:Show()
	right:Show()

	for _, m in ipairs(panels) do
		if m.Enter then m:Enter() end
	end

	self:Layout()

	if not self.wired then
		self.wired = true

		-- EL CAMBIO DE SELECCION REDISTRIBUYE, no solo repinta. Pasar de uno a
		-- dos cambia el NUMERO de areas. Solo cuando cambia la FORMA -- si no,
		-- cada click movería veinte botones para dejarlos donde estaban.
		ns.Selection:Subscribe(function()
			if not D.active then return end
			local st = D:State()
			local n = (st == "B") and #D:Columns() or 0
			local subj = D:Subject()
			if st ~= D.lastState or n ~= D.lastCols then
				D.lastState, D.lastCols, D.lastSubject = st, n, subj
				D:Layout()
			elseif subj ~= D.lastSubject then
				-- Mismo reparto, otro dueno: basta con avisar.
				D.lastSubject = subj
				Announce()
			end
		end)
	end
end

function D:Leave()
	self.active = false
	for _, m in ipairs(panels) do
		if m.Leave then m:Leave() end
	end
	if left then left:Hide() end
	if right then right:Hide() end
end

function D:Report()
	if not self.active then
		ns.Print("|cff888888dock:|r no esta puesto. Se pone al entrar en modo RTS.")
		return
	end
	ns.Print(("|cffffff00dock|r estado |cff33ccff%s|r, hueco de %d px (un boton de accion)"):format(
		self:State(), self.slot or 0))
	if self:State() == "A" then
		ns.Print(("  %s: %d huecos"):format(tostring(self:Subject()), MAIN_N))
	else
		ns.Print(("  %d columnas de %d huecos"):format(self.cols or 0, B_SLOTS))
	end
	ns.Print(("  macros: %dx%d"):format(MACRO_COLS, MACRO_ROWS))
end
