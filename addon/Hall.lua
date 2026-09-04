--[[
	Hall.lua -- el reparto de la sala, y nada mas.

	La sala se vacio el 2026-09-02 para redisenarla y `Bar.lua` la dejo como UN
	rectangulo sin rejilla: 344 de alto por `710 + 512*(grow-1)` de ancho. Este
	fichero es lo que vuelve a partirla, siguiendo
	`Downloads/brief-barra-control-grupo.md`:

	    +----------+----------------------------------------+
	    |          |  ARRIBA   marcos de unidad (minimo)    |
	    |  LISTA   +----------------------------------------+
	    |  (x5)    |  ABAJO    hechizos                     |
	    |          |           acciones                     |
	    +----------+----------------------------------------+

	=== ESTE FICHERO NO DIBUJA NADA ==========================================

	Igual que `Bar.lua` no dibuja lo que va en sus huecos. Aqui estan las AREAS
	y el ESTADO; el contenido lo ponen `Party`, `Frames` y `Cast`, que se
	apuntan con `H:Register(m)` y piden su marco con `H:Host(key)`.

	Es el mismo contrato que la revision de arquitectura (§12) dice que es lo
	mejor que tiene el addon y que no hay que tocar. Se copia, no se inventa.

	=== DOS ESTADOS, Y LOS DECIDE LA SELECCION ===============================

	  A  un solo personaje seleccionado -> marcos arriba, sus hechizos y sus
	     cuatro acciones abajo
	  B  dos o mas                      -> toda la zona derecha son columnas,
	     una por personaje, con su nombre de cabecera

	El estado se recalcula en cada cambio de seleccion, y eso cambia el NUMERO
	de areas, no solo su tamano -- que es exactamente por lo que `Bar:OnLayout`
	existe y por lo que aqui hay otro.

	SIN NADA SELECCIONADO LA SALA SE QUEDA EN EL ESTADO A, con el primario. No
	se apaga: una consola que se vacia al soltar la seleccion es una consola que
	parpadea, y el primario nunca es nil (`Selection:GetPrimary` cae a tu
	personaje).

	=== LAS MEDIDAS SALEN DE `sim/hall_layout.py` ============================

	No estan elegidas a ojo: el guion reparte la sala para los cinco `grow`, los
	dos estados y 4 o 6 huecos, y comprueba que nada se sale, nada se solapa y
	ningun hueco sale de tamano absurdo. Cazo dos fallos antes de que existiera
	este fichero, y el mas caro es el que decidio la forma:

	  LAS ACCIONES VAN DEBAJO DE LOS HECHIZOS, NO AL LADO. Puestas a su derecha
	  competian por el ANCHO, y con la barra estrecha (`grow` 1) NO CABIA
	  NINGUNA -- justo los cuatro botones que el brief llama caso de uso
	  prioritario. Apiladas compiten por el ALTO, que es fijo y sobra.

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

local TOP_H    = 96     -- "el minimo espacio vertical posible" (§2 del brief)
local TOP_GAP  = 10

local SLOT_GAP = 8
local SLOT_MAX = 112
local SLOT_MIN = 40
local ACT_N    = 4
local ACT_GAP  = 14
local ACT_MAX  = 96
local HEAD_H   = 26     -- la cabecera con el nombre, en el estado B

H.SLOT_MIN = SLOT_MIN
H.ACT_N    = ACT_N
H.ROW_N    = ROW_N

-- Cuantos huecos de habilidad por personaje. Cuatro por defecto, ampliable a
-- seis "si el ancho lo permite" (§8 del brief). Es un ajuste del jugador y no
-- una derivacion: seis huecos pequenos y cuatro grandes son dos gustos
-- distintos, no uno mejor que otro.
H.slots = 4

--- Los sitios donde se apunta el contenido --------------------------------

local host                -- el marco de la sala, de Bar
local frames = {}         -- key -> Frame
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
-- fuerza deja un boton flotando sobre el arte. El sim comprueba justo esto --
-- con `grow` 1 cinco columnas darian huecos de 17 px de dibujo.
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
		local side = FitAcross(colw, H.slots, SLOT_GAP)
		local room = h - HEAD_H - SLOT_GAP
		if side > room then side = room end
		if side < SLOT_MIN then side = 0 end

		H.colSide = side
		H.colW = colw
		for i = 1, n do
			Rect("col" .. i, cx + (i - 1) * (colw + GUTTER), 0, colw, h)
		end
		H.cols = n
		return
	end

	H.cols = 0

	Rect("top", cx, 0, cw, TOP_H)

	local by = TOP_H + TOP_GAP
	local bh = h - by
	local room = math.floor((bh - ACT_GAP) / 2)

	local sside = FitAcross(cw, H.slots, SLOT_GAP)
	if sside > room then sside = room end
	if sside < SLOT_MIN then sside = 0 end

	local aside = FitAcross(cw, ACT_N, SLOT_GAP, ACT_MAX)
	if aside > room then aside = room end
	if aside < SLOT_MIN then aside = 0 end

	H.slotSide = sside
	H.actSide  = aside

	Rect("spells", cx, by, cw, sside)
	Rect("actions", cx, by + (sside > 0 and (sside + ACT_GAP) or 0), cw, aside)
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

-- Las celdas de una fila de cuadrados, en coordenadas del marco de esa fila.
-- `n` y el lado ya los decidio `Recompute`, asi que quien las pide no tiene
-- que saber nada de `grow`.
function H:Row(key, n, side)
	local r = rects[key]
	if not r or not side or side <= 0 then return {} end
	local out = {}
	for i = 1, n do
		out[i] = { x = (i - 1) * (side + SLOT_GAP), y = 0, w = side, h = side }
	end
	return out
end

function H:SpellCells() return self:Row("spells", self.slots, self.slotSide) end
function H:ActionCells() return self:Row("actions", ACT_N, self.actSide) end

function H:ColumnCells()
	local out = {}
	if not self.colSide or self.colSide <= 0 then return out end
	for i = 1, self.slots do
		out[i] = { x = (i - 1) * (self.colSide + SLOT_GAP), y = HEAD_H + SLOT_GAP,
		           w = self.colSide, h = self.colSide }
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
		-- -- si no, cada click en un bot movería veinte botones para dejarlos
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
	if host then host:Hide() end
end

--- Ajustes ----------------------------------------------------------------

function H:SetSlots(n)
	n = tonumber(n)
	if not n or n < 1 or n > 6 then
		ns.Print("|cffff8800sala:|r los huecos van de 1 a 6.")
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
	local n = tonumber(db.slots)
	if n and n >= 1 and n <= 6 then
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
	ns.Print(("|cffffff00sala|r %dx%d dibujo, estado |cff33ccff%s|r, %d huecos"):format(
		w, h, self:State(), self.slots))

	if self:State() == "B" then
		if self.colSide and self.colSide > 0 then
			ns.Print(("  %d columnas de %d, hueco %d"):format(
				self.cols or 0, self.colW or 0, self.colSide))
		else
			-- NO CABEN: SE DICE Y SE DICE QUE HACER. Es la respuesta de §9.2 del
			-- brief ("si no, ensanchar barra"), y `grow` ya lo hace. Esconder las
			-- columnas en silencio dejaria media consola vacia sin motivo visible.
			ns.Print(("  |cffff8800no caben %d columnas de %d huecos|r " ..
			          "en %d de ancho. Ensancha con |cffffff00/rts bar grow|r " ..
			          "o baja los huecos con |cffffff00/rts hall slots|r."):format(
				self.cols or 0, self.slots, self.colW or 0))
		end
	else
		ns.Print(("  de |cff33ccff%s|r; hechizo %d, accion %d"):format(
			tostring(self:Subject()), self.slotSide or 0, self.actSide or 0))
		if (self.slotSide or 0) == 0 then
			ns.Print("  |cffff8800los huecos no caben|r: ensancha con " ..
			         "|cffffff00/rts bar grow|r.")
		end
	end
end

-- SE APUNTA SOLO en la barra, igual que `Panel` y `Rails`. `Bar.lua` no nombra
-- a ninguno desde 2026-09-02 y esto no lo cambia.
ns.Bar:Register(H)
