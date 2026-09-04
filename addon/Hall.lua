--[[
	Hall.lua -- el reparto de la sala, y nada mas.

	La sala se vacio el 2026-09-02 para redisenarla y `Bar.lua` la dejo como UN
	rectangulo sin rejilla: 344 de alto por `710 + 512*(grow-1)` de ancho. Este
	fichero es lo que vuelve a partirla, siguiendo el boceto de
	`brief-barra-control-grupo.md`:

	  ESTADO A -- uno seleccionado (o ninguno):

	    +--------+------------------------------------------------+
	    | LISTA  |  (o) [==]    (o) [==]   (o)[=]                  |  marcos
	    |  x5    |  ---------------------------------------------- |  raya
	    |        |  [1][2][3][4][5][6][7][8][9][10]                |  hechizos
	    |        |  [ macro 1 ][ macro 2 ][ macro 3 ][ macro 4 ]   |  macros
	    +--------+------------------------------------------------+

	  ESTADO B -- dos o mas:

	    +--------+-------------+-------------+-------------+------+
	    | LISTA  |    Bob      |    Avy      |  Kirinah    | ...  |
	    |  x5    |  [1] [2]    |  [1] [2]    |  [1] [2]    |      |
	    |        |  [3] [4]    |  [3] [4]    |  [3] [4]    |      |
	    |        |  [ macro 1 ]|  [ macro 1 ]|  [ macro 1 ]|      |
	    |        |  [ macro 2 ]|  [ macro 2 ]|  [ macro 2 ]|      |
	    +--------+-------------+-------------+-------------+------+

	=== ESTE FICHERO NO DIBUJA NADA ==========================================

	Igual que `Bar.lua` no dibuja lo que va en sus huecos. Aqui estan las AREAS
	y el ESTADO; el contenido lo ponen `Party`, `Frames` y `Cast`, que se
	apuntan con `H:Register(m)` y piden su marco con `H:Host(key)`.

	Es el mismo contrato que la revision de arquitectura (§12) dice que es lo
	mejor que tiene el addon y que no hay que tocar. Se copia, no se inventa.

	=== DOS ESTADOS, Y LOS DECIDE LA SELECCION ===============================

	El estado se recalcula en cada cambio de seleccion, y eso cambia el NUMERO
	de areas, no solo su tamano -- que es exactamente por lo que `Bar:OnLayout`
	existe y por lo que aqui hay otro.

	SIN NADA SELECCIONADO LA SALA SE QUEDA EN EL ESTADO A, con el primario. No
	se apaga: una consola que se vacia al soltar la seleccion es una consola que
	parpadea, y el primario nunca es nil (`Selection:GetPrimary` cae a tu
	personaje).

	=== DIEZ EN A, CUATRO EN B, Y SON LOS MISMOS ============================

	El estado A ensena diez huecos y el B ensena 2x2. **No son dos
	configuraciones**: el 2x2 son los huecos 1..4 de esos mismos diez. Con
	cuatro personajes cogidos no caben diez de cada uno -- serian cuarenta
	botones -- asi que se ensenan los cuatro primeros, que son los que el
	jugador puso primero.

	Guardar dos listas por personaje habria sido peor de la forma tipica: dos
	sitios donde configurar lo mismo, y el jugador descubriendo en combate que
	el hueco 2 no dice lo mismo segun cuantos lleve cogidos.

	=== LAS MEDIDAS SALEN DE `sim/hall_layout.py` ============================

	No estan elegidas a ojo: el guion reparte la sala para los cinco `grow` y
	los dos estados, y comprueba que nada se sale, nada se solapa y ningun hueco
	sale de tamano absurdo. Cazo dos fallos antes de que existiera este fichero.

	Y CAZO UNO MAS AL PASAR A DIEZ HUECOS: **con `grow` 1 la fila de diez no
	cabe** (438 de ancho para 472 que hacen falta). No se recorta -- se esconde,
	y `/rts hall` dice por que. Es la misma decision que `SlotGrid` toma en
	`Bar.lua`: meter una celda a la fuerza deja un boton flotando sobre el arte.

	Si se cambia un numero de aqui, se cambia en el guion y se vuelve a correr.
	Son dos sitios a proposito: el guion es el que puede probarlo.

	=== TODO EN PIXELES DE DIBUJO ===========================================

	El arte es 2x y se dibuja a ~x0.56, asi que un 24 de aqui se ve como 13.
	Misma convencion que `Bar.lua` y `Widgets.lua`; el sitio donde se olvido
	costo las guias ilegibles de la etapa 5l.
]]

local ADDON, ns = ...

local H = {}
ns.Hall = H

H.active = false

--- Las medidas ------------------------------------------------------------
--
-- Espejo exacto de `sim/hall_layout.py`. Los nombres coinciden a proposito.

local LIST_W   = 260    -- la columna de personajes: estrecha, pero el nombre cabe
local GUTTER   = 12

local ROW_N    = 5      -- heroe + cuatro companeros
local ROW_GAP  = 4

local TOP_H    = 96     -- los marcos: "el minimo espacio vertical posible" (§2)
local DIV_GAP  = 10
local DIV_H    = 2

local SLOT_GAP = 8
local SLOT_MAX = 112
local SLOT_MIN = 40

local SPELL_N   = 10    -- "10x Spells" del boceto, en UNA fila
local MACRO_N   = 4
local MACRO_H   = 56    -- 31 px de pantalla: cabe el texto a fuente 22 de dibujo
local MACRO_GAP = 8
local VGAP      = 14

-- El estado B, por columna
local HEAD_H      = 26
local HEAD_GAP    = 6
local B_COLS      = 2
local B_ROWS      = 2
local B_MACRO_N   = 2
local B_MACRO_H   = 42
local B_MACRO_GAP = 4
local B_MID_GAP   = 10

H.SLOT_MIN  = SLOT_MIN
H.MACRO_N   = MACRO_N
H.B_MACRO_N = B_MACRO_N
H.B_SLOTS   = B_COLS * B_ROWS     -- los cuatro del 2x2
H.ROW_N     = ROW_N
H.MAX_SPELLS = SPELL_N

-- Cuantos huecos de hechizo en el estado A. Diez por defecto, que es lo que
-- pide el boceto; el knob existe para poder bajarlo sin recompilar nada, no
-- porque haya una respuesta mejor.
H.slots = SPELL_N

--- Los sitios donde se apunta el contenido --------------------------------

local host                -- el marco de la sala, de Bar
local frames = {}         -- key -> Frame
local divider             -- la raya bajo los marcos
local rects  = {}         -- key -> { x, y, w, h } en coordenadas del marco
local listeners = {}
local panels = {}

--- Registro ---------------------------------------------------------------

-- `m` necesita `Enter`/`Leave`; los dos opcionales. Copiado de `Bar:Register`,
-- incluida la guarda de doble registro: dos `Enter` son botones duplicados
-- encima de los suyos, y un `/reload` no deberia poder provocarlo.
function H:Register(m)
	if not m then return end
	for _, other in ipairs(panels) do
		if other == m then return end
	end
	table.insert(panels, m)
	if self.active and m.Enter then m:Enter() end
end

function H:OnLayout(fn)
	table.insert(listeners, fn)
	if self.active then pcall(fn) end
end

local function Announce()
	for _, fn in ipairs(listeners) do
		-- Un modulo que falle no puede dejar la sala a medio colocar ni
		-- llevarse por delante a los demas. Misma guarda que en `Bar`.
		local ok, err = pcall(fn)
		if not ok then ns.Print("|cffff0000sala:|r " .. tostring(err)) end
	end
end

--- El estado --------------------------------------------------------------

-- "A" con cero o uno seleccionado, "B" con dos o mas. Cero cuenta como A por
-- lo que dice la cabecera: la sala no se vacia al soltar la seleccion.
function H:State()
	return (ns.Selection:Count() >= 2) and "B" or "A"
end

-- De quien es la fila de hechizos en el estado A. Con uno seleccionado es ese;
-- sin nada, el primario -- que es el concepto que `Selection` separo justamente
-- para que mirar las habilidades de alguien no obligue a soltar al grupo.
function H:Subject()
	return ns.Selection:Single() or ns.Selection:GetPrimary()
end

-- Los personajes cuyas columnas se dibujan en el estado B, en el orden de la
-- lista de la izquierda -- que es el orden que el jugador tiene delante.
function H:Columns()
	local out = {}
	for _, m in ipairs(ns.Selection:GetRosterHeroFirst()) do
		if ns.Selection:IsSelected(m.name) then
			table.insert(out, m)
		end
	end
	return out
end

--- El reparto -------------------------------------------------------------

-- El lado de `n` cuadrados en fila dentro de `width`, o 0 si no caben.
--
-- DEVOLVER 0 EN VEZ DE RECORTAR es la decision, y es la misma que `SlotGrid`
-- toma en `Bar.lua`: "no cabe" significa que no cabe UNA celda, y meterla a la
-- fuerza deja un boton flotando sobre el arte.
local function FitAcross(width, n, gap, hi)
	if n <= 0 or width <= 0 then return 0 end
	local side = math.floor((width - gap * (n - 1)) / n)
	if side > (hi or SLOT_MAX) then side = hi or SLOT_MAX end
	if side < SLOT_MIN then return 0 end
	return side
end

local function Rect(key, x, y, w, h)
	rects[key] = { x = x, y = y, w = w, h = h }
end

-- LA FILA DE LA COLUMNA IZQUIERDA. Nombre encima de la barra de vida, y una
-- linea muy fina de recurso debajo -- lo que pide §3 del brief, literalmente.
-- El reparto interior lo hace `Party.lua`; aqui solo sale el alto de la fila.
function H:RowHeight()
	-- DEL ALTO DE VERDAD, no de un 344 escrito. El arte mide 344 hoy, pero
	-- escribirlo aqui es la clase de constante que sobrevive al cambio que la
	-- invalida y luego descuadra las filas sin decir por que -- que es
	-- exactamente lo que `Bar.lua` evita derivando toda posicion de las piezas.
	local _, h = ns.Bar:SlotSize("hall")
	if not h or h <= 0 then h = 344 end
	return math.floor((h - ROW_GAP * (ROW_N - 1)) / ROW_N)
end

function H:RowGap() return ROW_GAP end

local function Recompute()
	local w, h = ns.Bar:SlotSize("hall")
	rects = {}
	H.slotSide, H.macroW, H.macroH = 0, 0, MACRO_H
	H.colSide, H.colW, H.colGridW = 0, 0, 0
	H.cols = 0
	if w <= 0 or h <= 0 then return end

	Rect("list", 0, 0, LIST_W, h)

	local cx = LIST_W + GUTTER
	local cw = w - cx
	Rect("content", cx, 0, cw, h)

	if H:State() == "B" then
		-- TODA la zona derecha son columnas. No hay banda de marcos: con varios
		-- seleccionados no hay un "el seleccionado" del que ensenar el marco, y
		-- cinco marcos no caben ni dirian nada que la columna izquierda no diga.
		local n = #H:Columns()
		local colw = (n > 0) and math.floor((cw - GUTTER * (n - 1)) / n) or 0

		-- EL ALTO MANDA CASI SIEMPRE y por eso se calcula primero: el ancho solo
		-- puede empeorarlo. Con la columna a 385 caben cuadrados de 188, pero el
		-- alto de la sala solo da para 103.
		local room = h - HEAD_H - HEAD_GAP - B_MID_GAP
		           - (B_MACRO_H * B_MACRO_N + B_MACRO_GAP * (B_MACRO_N - 1))
		           - SLOT_GAP * (B_ROWS - 1)
		local byHeight = math.floor(room / B_ROWS)

		local side = FitAcross(colw, B_COLS, SLOT_GAP)
		if side > byHeight then side = byHeight end
		if side < SLOT_MIN then side = 0 end

		H.colSide = side
		H.colW = colw
		H.colGridW = (side > 0) and (side * B_COLS + SLOT_GAP * (B_COLS - 1)) or 0
		H.cols = n
		for i = 1, n do
			Rect("col" .. i, cx + (i - 1) * (colw + GUTTER), 0, colw, h)
		end
		return
	end

	Rect("top", cx, 0, cw, TOP_H)
	Rect("div", cx, TOP_H + DIV_GAP, cw, DIV_H)

	local by = TOP_H + DIV_GAP + DIV_H + DIV_GAP
	local bh = h - by

	local n = H.slots
	local side = FitAcross(cw, n, SLOT_GAP)
	local room = bh - VGAP - MACRO_H
	if side > room then side = room end
	if side < SLOT_MIN then side = 0 end

	H.slotSide = side
	local rowW = (side > 0) and (side * n + SLOT_GAP * (n - 1)) or 0
	H.spellRowW = rowW

	-- LOS MACROS SE ALINEAN CON LA FILA DE HECHIZOS, y ese es todo su ancho.
	-- Derivarlo en vez de escribirlo es lo que hace que cambiar el numero de
	-- huecos no descuadre la fila de abajo -- la misma regla que `Bar.lua`
	-- aplica a las posiciones de sus piezas: toda posicion se deriva, ninguna
	-- se escribe.
	H.macroW = (rowW > 0) and math.floor((rowW - MACRO_GAP * (MACRO_N - 1)) / MACRO_N) or 0

	Rect("spells", cx, by, rowW, side)
	Rect("macros", cx, by + (side > 0 and (side + VGAP) or 0),
	     (H.macroW > 0) and (H.macroW * MACRO_N + MACRO_GAP * (MACRO_N - 1)) or 0,
	     MACRO_H)
end

--- Lo que usan los modulos de contenido -----------------------------------

function H:Get(key)
	return rects[key]
end

-- El marco de un area. Se crean bajo demanda y no se destruyen -- pasar del
-- estado B al A esconde las columnas en vez de borrarlas, para que volver no
-- cree nada. Misma politica que las texturas repetidas de `Bar`.
function H:Host(key)
	if not host then return nil end
	local f = frames[key]
	if not f then
		f = CreateFrame("Frame", "RTSHall_" .. key, host)
		f:SetFrameLevel(host:GetFrameLevel() + 2)
		f:EnableMouse(false)
		frames[key] = f
	end
	return f
end

--- Las celdas, en coordenadas de SU marco ---------------------------------

-- La fila de hechizos del estado A.
function H:SpellCells()
	local out = {}
	local side = self.slotSide or 0
	if side <= 0 then return out end
	for i = 1, self.slots do
		out[i] = { x = (i - 1) * (side + SLOT_GAP), y = 0, w = side, h = side }
	end
	return out
end

-- Los cuatro macros del estado A.
function H:MacroCells()
	local out = {}
	local mw = self.macroW or 0
	if mw <= 0 then return out end
	for i = 1, MACRO_N do
		out[i] = { x = (i - 1) * (mw + MACRO_GAP), y = 0, w = mw, h = MACRO_H }
	end
	return out
end

-- El 2x2 de una columna del estado B. Centrado horizontalmente en la columna:
-- el bloque mide 214 dentro de 385, y pegarlo a un lado se leeria como que algo
-- se ha descolocado.
function H:ColumnSpellCells()
	local out = {}
	local side = self.colSide or 0
	if side <= 0 then return out end
	local ox = math.floor(((self.colW or 0) - self.colGridW) / 2)
	local y0 = HEAD_H + HEAD_GAP
	for i = 1, B_COLS * B_ROWS do
		local c = (i - 1) % B_COLS
		local r = math.floor((i - 1) / B_COLS)
		out[i] = { x = ox + c * (side + SLOT_GAP),
		           y = y0 + r * (side + SLOT_GAP),
		           w = side, h = side }
	end
	return out
end

-- Los dos macros de una columna.
--
-- OCUPAN LA COLUMNA ENTERA, y es una desviacion del boceto dicha a proposito.
-- Alli tienen el ancho del bloque 2x2, pero las proporciones reales no son las
-- del papel: con `grow` 4 y cinco columnas el bloque mide 214 dentro de 385, o
-- sea 171 px de hueco muerto por columna. Un macro es una barra de TEXTO --
-- cuanto mas ancha, mejor se lee -- asi que llenar la columna no cuesta nada.
function H:ColumnMacroCells()
	local out = {}
	local side = self.colSide or 0
	if side <= 0 then return out end
	local y0 = HEAD_H + HEAD_GAP + side * B_ROWS + SLOT_GAP * (B_ROWS - 1) + B_MID_GAP
	for i = 1, B_MACRO_N do
		out[i] = { x = 0, y = y0 + (i - 1) * (B_MACRO_H + B_MACRO_GAP),
		           w = self.colW or 0, h = B_MACRO_H }
	end
	return out
end

function H:HeadHeight() return HEAD_H end

--- Distribuir -------------------------------------------------------------

function H:Layout()
	if not host then return end
	Recompute()

	-- Los marcos se colocan aqui y su contenido se coloca en el aviso. Un area
	-- que este reparto no produjo se ESCONDE en vez de quedarse donde estaba:
	-- pasar de B a A dejaria cinco columnas dibujadas encima de los marcos.
	for key, f in pairs(frames) do
		local r = rects[key]
		if r and r.w > 0 and r.h > 0 then
			f:SetWidth(r.w)
			f:SetHeight(r.h)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", host, "TOPLEFT", r.x, -r.y)
			f:Show()
		else
			f:Hide()
		end
	end

	-- LA RAYA BAJO LOS MARCOS. Es del boceto y no es adorno: separa lo que se
	-- MIRA (los marcos) de lo que se PULSA (hechizos y macros), que son las dos
	-- mitades de la zona y se leen distinto.
	if not divider then
		divider = host:CreateTexture(nil, "OVERLAY")
		divider:SetTexture(0.55, 0.58, 0.66, 0.45)
	end
	local d = rects.div
	if d and d.w > 0 then
		divider:SetWidth(d.w)
		divider:SetHeight(d.h)
		divider:ClearAllPoints()
		divider:SetPoint("TOPLEFT", host, "TOPLEFT", d.x, -d.y)
		divider:Show()
	else
		divider:Hide()
	end

	Announce()
end

--- Entrar y salir ---------------------------------------------------------

function H:Enter()
	host = ns.Bar:SlotFrame("hall")
	if not host then return end
	self.active = true
	host:Show()

	for _, m in ipairs(panels) do
		if m.Enter then m:Enter() end
	end

	self:Layout()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() H:Layout() end)

		-- EL CAMBIO DE SELECCION REDISTRIBUYE, no solo repinta. Cambiar de uno
		-- a dos seleccionados cambia el NUMERO de areas, asi que no vale con
		-- avisar al contenido: hay que rehacer el reparto. Solo cuando el
		-- ESTADO o el numero de columnas cambia, que es lo que decide la forma
		-- -- si no, cada click en un bot moveria veinte botones para dejarlos
		-- donde estaban.
		ns.Selection:Subscribe(function()
			local st = H:State()
			local n = (st == "B") and #H:Columns() or 0
			local subj = H:Subject()
			if st ~= H.lastState or n ~= H.lastCols then
				H.lastState, H.lastCols, H.lastSubject = st, n, subj
				H:Layout()
			elseif subj ~= H.lastSubject then
				-- Mismo reparto, otro dueno: basta con avisar.
				H.lastSubject = subj
				Announce()
			end
		end)
	end
end

function H:Leave()
	self.active = false
	for _, m in ipairs(panels) do
		if m.Leave then m:Leave() end
	end
	if divider then divider:Hide() end
	if host then host:Hide() end
end

--- Ajustes ----------------------------------------------------------------

function H:SetSlots(n)
	n = tonumber(n)
	if not n or n < 1 or n > SPELL_N then
		ns.Print(("|cffff8800sala:|r los huecos van de 1 a %d."):format(SPELL_N))
		return
	end
	self.slots = math.floor(n)
	RTSCommandDB.hall = RTSCommandDB.hall or {}
	RTSCommandDB.hall.slots = self.slots
	self:Layout()
	self:Report()
end

function H:Load()
	local db = RTSCommandDB and RTSCommandDB.hall
	if type(db) ~= "table" then return end
	-- SE ACOTA AL LEER, no solo al escribir. Cuarta vez que hace falta en este
	-- addon (`grow = 688`, `camHold`, `railCropGen`): un fichero de
	-- SavedVariables no olvida ninguna clave y sobrevive a la version que la
	-- escribio, y los `Set*` solo corren cuando el jugador teclea.
	--
	-- Y AQUI EL RANGO CAMBIO DE SIGNIFICADO: hasta la tarde del 2026-09-04 el
	-- tope eran 6 y el defecto 4. Un 4 guardado sigue siendo valido, asi que no
	-- se tira -- pero quien tuviera 6 puestos ahora tiene diez disponibles y no
	-- se entera. Por eso `/rts hall` imprime siempre cuantos hay.
	local n = tonumber(db.slots)
	if n and n >= 1 and n <= SPELL_N then
		self.slots = math.floor(n)
	elseif db.slots ~= nil then
		ns.Print(("|cff888888sala: descartado slots=%s.|r"):format(tostring(db.slots)))
		db.slots = nil
	end
end

function H:Report()
	if not self.active then
		ns.Print("|cff888888sala:|r la barra no esta puesta. |cffffff00/rts bar|r")
		return
	end
	local w, h = ns.Bar:SlotSize("hall")
	ns.Print(("|cffffff00sala|r %dx%d dibujo, estado |cff33ccff%s|r"):format(
		w, h, self:State()))

	if self:State() == "B" then
		if (self.colSide or 0) > 0 then
			ns.Print(("  %d columnas de %d: 2x2 de %d y %d macros de %d de ancho"):format(
				self.cols or 0, self.colW or 0, self.colSide,
				self.B_MACRO_N, self.colW or 0))
		else
			-- NO CABEN: SE DICE Y SE DICE QUE HACER. Es la respuesta de §9.2 del
			-- brief ("si no, ensanchar barra"), y `grow` ya lo hace. Esconder las
			-- columnas en silencio dejaria media consola vacia sin motivo visible.
			ns.Print(("  |cffff8800no caben %d columnas|r en %d de ancho. " ..
			          "Ensancha con |cffffff00/rts bar grow|r."):format(
				self.cols or 0, self.colW or 0))
		end
		return
	end

	ns.Print(("  de |cff33ccff%s|r: %d huecos de %d, %d macros de %dx%d"):format(
		tostring(self:Subject()), self.slots, self.slotSide or 0,
		MACRO_N, self.macroW or 0, self.macroH or 0))
	if (self.slotSide or 0) == 0 then
		ns.Print(("  |cffff8800los %d huecos no caben|r: ensancha con " ..
		          "|cffffff00/rts bar grow|r o baja el numero con " ..
		          "|cffffff00/rts hall slots <n>|r."):format(self.slots))
	end
end

-- SE APUNTA SOLO en la barra, igual que `Panel` y `Rails`. `Bar.lua` no nombra
-- a ninguno desde 2026-09-02 y esto no lo cambia.
ns.Bar:Register(H)
