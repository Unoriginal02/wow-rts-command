--[[
	Bar.lua -- la barra inferior, con el arte de verdad.

	Siete piezas TGA dibujadas una al lado de otra, de izquierda a derecha:

	  left-bar 128 | 16 | left-map 512 | left-hero-portrait 512 |
	  middle-grow 512 xN | right-embellishment 128 | right-bot-actions 512 |
	  16 | right-bar 128                                    -- 2464 x 512

	EL ARTE ES 2x Y SE DIBUJA REDUCIDO, ~x0.83 en 2560. La primera exportacion
	era de 256 de alto y se quedaba corta al lado de las texturas del propio
	juego, que son bastante mayores; doblarla hace que las piezas del cliente
	encajen. Los numeros de este fichero son los del DIBUJO, y la escala de
	pantalla los baja. Reducir es barato y sale nitido -- lo que emborrona es
	ampliar, y esta barra ya no amplia nunca.

	EL ALTO LO PONE `share` Y EL ANCHO LO LLENA `grow`. Son dos mandos para dos
	cosas distintas, y la clave es que `grow` NO es continuo: repetir el panel
	central cambia la proporcion del dibujo, que es un grado de libertad de
	verdad y no una segunda forma de pedir lo mismo.

	  1. `share` = 0.20 del alto de pantalla  -> sale la ESCALA
	  2. con esa escala, cuantas copias del central hacen falta para dejar
	     `side` = 0.10 de margen a cada lado  -> sale `grow`

	Este es el reparto que faltaba. Un intento anterior fijaba el ancho con
	`side` y dejaba el alto de consecuencia: como la barra es de proporcion fija
	y `grow` estaba a mano, el alto salia al 30% de la pantalla y crecer la
	ENCOGIA. El error no era el knob, era pedirle a la escala que hiciera el
	trabajo del ancho.

	`grow` ES DISCRETO, asi que el margen casi nunca cae en el 10% clavado: se
	elige la cuenta de copias que mas se acerca, con un suelo por debajo del
	cual no se deja bajar. El margen que sale se imprime, no se supone.

	LOS DOS HUECOS DE 16 SON LA UNICA SEPARACION QUE HAY. Los railes de botones
	de los extremos flotan sueltos; todo lo del centro se toca. Es la regla del
	boceto, y esta escrita como `gap` en la tabla de piezas en vez de sumada a
	mano en las coordenadas, para que se pueda ver y cambiar en un sitio.

	`middle-grow` SE REPITE, y es la unica pieza que puede. Su dibujo llega de
	borde a borde -- el gris ocupa los 256 de ancho y las bandas turquesa de
	arriba y abajo cruzan enteras -- asi que dos copias seguidas no dejan
	costura. La barra crece por ahi y solo por ahi: `/rts bar grow <n>`.

	POR QUE NO PASA POR Skin.lua. Skin viste con `SetBackdrop`, cuyo `edgeFile`
	es una hoja con los ocho trozos del borde en una disposicion interna que
	nadie aqui ha verificado. Estas piezas son cada una un dibujo entero, asi
	que se colocan como TEXTURAS EXPLICITAS y se ancla cada una a mano.

	TODA POSICION SE DERIVA, NINGUNA SE ESCRIBE. La primera version tenia las
	coordenadas de los huecos en absoluto (`card` en x=1040) y eso deja de valer
	en cuanto una pieza anterior cambia de ancho. Ahora cada hueco dice a QUE
	PIEZA pertenece y con que margen, y su x sale de donde acabo la anterior. Es
	lo que hace que cambiar una pieza de ancho -- o repetir `middle-grow` N
	veces -- no obligue a tocar un solo numero de los demas.

	LAS MEDIDAS DE LOS HUECOS ESTAN MEDIDAS, NO ELEGIDAS. Salen de escanear el
	relleno gris de los PNG de `art-src`, pieza por pieza. Cuando el arte
	cambie se vuelven a escanear: son un reflejo del dibujo, no una decision
	aparte que haya que mantener sincronizada a ojo.

	EL TAMANO EN PANTALLA sale de `share`, la fraccion del alto de pantalla que
	debe ocupar la barra, no de un multiplicador. "x1.18" solo significa algo en
	esta pantalla; "20% del alto" significa lo mismo en todas. Mismo motivo por
	el que HUD:Fit() calca el boton de la barra de acciones.

	NO TOCA EL RATON. `EnableMouse(false)` en todo: una barra que se come los
	clicks rompe la caja de seleccion por esa zona (prueba B6).
]]

local ADDON, ns = ...

local B = {}
ns.Bar = B

B.active = false

local ART = "Interface\\AddOns\\RTSCommand\\art\\"

-- EL ARTE ES 2x, Y SE DIBUJA REDUCIDO. La primera exportacion era de 256 de
-- alto y quedaba pequena al lado de las texturas del propio juego, que son
-- bastante mas grandes; al doblar el arte, las piezas del cliente encajan.
-- Asi que las medidas de aqui son las del DIBUJO (512 de alto) y la escala de
-- pantalla las baja. Reducir es barato y sale nitido; ampliar es lo que
-- emborrona, y esta barra ya no amplia nunca.
local BAR_H = 512

-- La separacion de los railes. Un solo numero, en un solo sitio.
local GAP = 16

-- La pieza que se repite para que la barra crezca.
local GROW = "middle-grow"

-- Las piezas en orden de izquierda a derecha. `gap` es el hueco QUE VA ANTES
-- de la pieza.
local PIECES = {
	{ key = "left-bar",            w = 128 },
	{ key = "left-map",            w = 512, gap = GAP },
	{ key = "left-hero-portrait",  w = 512 },
	{ key = GROW,                  w = 512 },
	{ key = "right-embellishment", w = 128 },
	{ key = "right-bot-actions",   w = 512 },
	{ key = "right-bar",           w = 128, gap = GAP },
}

-- Huecos utiles, medidos del arte escaneando el relleno gris de los PNG.
-- Relativos A SU PIEZA, nunca a la barra.
--
-- `cols`/`rows`/`pitch` describen una rejilla: la celda de arriba a la
-- izquierda es dx,dy,w,h y las demas salen del paso. Asi la carta de comandos
-- y los railes son la misma clase de cosa que un hueco suelto, y las guias no
-- necesitan un caso especial para cada uno.
--
-- `toPiece`/`toDx` es un hueco que ABARCA varias piezas: su ancho llega hasta
-- ese punto de esa otra pieza, se repita `middle-grow` las veces que se repita.
local SLOTS = {
	-- `host = true` -> ademas del rectangulo medido, un Frame de verdad donde
	-- otro modulo puede meter algo. El minimapa y el retrato son los dos que lo
	-- necesitan; los demas huecos son solo coordenadas.
	{ key = "minimap",    piece = "left-map",
	  dx = 32, dy = 32, w = 448, h = 448, host = true,
	  label = "minimapa" },

	{ key = "portrait",   piece = "left-hero-portrait",
	  dx = 32, dy = 128, w = 256, h = 256, host = true,
	  label = "retrato" },

	{ key = "info",       piece = "left-hero-portrait",
	  dx = 320, dy = 128, w = 192, h = 352,
	  label = "datos" },

	{ key = "vitals",     piece = "left-hero-portrait",
	  dx = 32, dy = 400, w = 256, h = 16, rows = 3, pitch = 32,
	  label = "barras" },

	{ key = "party",      piece = GROW,
	  dx = 0, dy = 128, h = 352,
	  toPiece = "right-embellishment", toDx = 96,
	  label = "grupo (crece)" },

	{ key = "card",       piece = "right-bot-actions",
	  dx = 32, dy = 32, w = 112, h = 112, cols = 4, rows = 4, pitch = 112,
	  label = "carta 4x4" },

	{ key = "rail-left",  piece = "left-bar",
	  dx = 32, dy = 44, w = 64, h = 64, rows = 6, pitch = 72,
	  label = "rail izq" },

	{ key = "rail-right", piece = "right-bar",
	  dx = 32, dy = 44, w = 64, h = 64, rows = 6, pitch = 72,
	  label = "rail der" },
}

local bar, guides, miniSlot
local hosts = {}   -- key de hueco -> Frame anfitrion
local tex = {}      -- key -> lista de texturas (una pieza repetida usa varias)
local place = {}    -- key -> { x = primera x, right = donde acaba la ultima }
local order = {}    -- la lista plana, ya con las repeticiones dentro
local BAR_W = 0

-- `share` da la ESCALA: la fraccion del alto de pantalla que ocupa la barra.
-- 0.20 sale de la referencia, no del gusto -- la consola de WC3 ocupa ~25% del
-- alto y la de SC2 ~22%.
--
-- `side` da el GROW: el margen que se querria a cada lado, en fraccion del
-- ancho de pantalla. No recorta nada; decide cuantas copias del panel central
-- se dibujan para acercarse a el.
--
-- `minSide` es el suelo. Existe porque `grow` es discreto: entre dos cuentas de
-- copias, la de abajo deja mucho margen y la de arriba poco, y sin un suelo la
-- de arriba puede llegar a pegar el arte al borde. Por debajo de esto no se
-- elige una cuenta aunque sea la que mas se acerca.
--
-- `side` en fraccion y `pad` en pixeles a proposito. `pad` es la separacion al
-- SUELO y no tiene nada que ver con el ancho; `side` quiere decir lo mismo en
-- cualquier resolucion y "256 px" solo en esta.
B.cfg = { pad = 22, side = 0.10, minSide = 0.045, share = 0.20, scale = 1, grow = 1 }

-- Derivar la escala del alto, y la cuenta de copias del ancho. Fijar cualquiera
-- de los dos a mano apaga SOLO ese: elegir cuantos paneles quieres no deberia
-- congelar tambien el tamano.
B.autoShare = true
B.autoGrow = true

-- LO GUARDADO SE ACOTA AL LEERLO, NO SOLO AL ESCRIBIRLO. Un fichero de
-- SavedVariables no olvida nunca: guarda cualquier clave que se haya escrito
-- alguna vez y sobrevive a la version del addon que la escribio. Este ya
-- traia un `grow = 688` de una version anterior -- que como numero de copias
-- del panel central no significa nada -- y sin acotarlo al cargar habria
-- salido una barra de ocho paneles diminuta, sin nada que dijera por que.
--
-- Acotar solo dentro de los `Set*` no vale: esos solo corren cuando el jugador
-- escribe el comando, y el problema entra por el otro lado.
-- `strict` es la diferencia entre un knob continuo y una cuenta. Pasarse de la
-- raya en `share` o `side` es una intencion que se puede recortar: pediste el
-- 70% del alto, te doy el 60%. Un `grow` de 688 no es una intencion exagerada,
-- es basura -- y recortarla al maximo daria ocho paneles, que se ve mal y
-- ademas parece deliberado. Ahi lo correcto es volver al valor de fabrica.
local LIMITS = {
	grow    = { 1, 8, strict = true },
	side    = { 0, 0.40 },
	minSide = { 0, 0.40 },
	share   = { 0.02, 0.60 },
	scale   = { 0.05, 16 },
	pad     = { -200, 800 },
}

local descartados = {}

local function Clamp(k, v)
	local lim = LIMITS[k]
	if not lim or type(v) ~= "number" then return v end
	if v ~= v or v < lim[1] or v > lim[2] then    -- v ~= v es nan
		table.insert(descartados, ("%s=%s"):format(k, tostring(v)))
		if lim.strict or v ~= v then return B.cfg[k] end
		return (v < lim[1]) and lim[1] or lim[2]
	end
	return v
end

--- El orden de las piezas --------------------------------------------------

-- La lista plana. Se rehace en cada distribucion porque cuesta siete vueltas y
-- asi no hay dos sitios donde `grow` tenga que estar al dia.
local function BuildOrder()
	local n = math.floor(B.cfg.grow or 1)
	if n < 1 then n = 1 end
	if n > 8 then n = 8 end

	order = {}
	for _, p in ipairs(PIECES) do
		local veces = (p.key == GROW) and n or 1
		for i = 1, veces do
			table.insert(order, {
				key = p.key,
				w = p.w,
				-- el hueco va solo antes de la PRIMERA copia
				gap = (i == 1) and (p.gap or 0) or 0,
			})
		end
	end
end

--- Piezas ------------------------------------------------------------------

-- Las texturas se crean bajo demanda y no se destruyen: bajar `grow` esconde
-- las sobrantes en vez de borrarlas, para que volver a subirlo no tenga que
-- crear nada.
local function TextureFor(key, i)
	tex[key] = tex[key] or {}
	local t = tex[key][i]
	if not t then
		t = bar:CreateTexture(nil, "ARTWORK")
		t:SetTexture(ART .. key)
		t:SetHeight(BAR_H)
		tex[key][i] = t
	end
	return t
end

local function LayoutPieces()
	BuildOrder()

	local usadas = {}
	local x = 0
	place = {}

	for _, p in ipairs(order) do
		x = x + (p.gap or 0)

		usadas[p.key] = (usadas[p.key] or 0) + 1
		local t = TextureFor(p.key, usadas[p.key])
		t:ClearAllPoints()
		t:SetWidth(p.w)
		t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
		t:Show()

		place[p.key] = place[p.key] or { x = x }
		x = x + p.w
		place[p.key].right = x
	end

	-- Las copias que ya no hacen falta.
	for key, lista in pairs(tex) do
		for i = (usadas[key] or 0) + 1, #lista do lista[i]:Hide() end
	end

	BAR_W = x
	bar:SetWidth(BAR_W)
end

-- Donde cae un hueco, en coordenadas de la barra. Sale de su pieza, asi que
-- sigue bien cuando las piezas de su izquierda cambian de ancho o de numero.
local function SlotRect(s)
	local rec = place[s.piece]
	if not rec then return 0, 0, s.w or 0, s.h or 0 end
	local x = rec.x + s.dx
	local w = s.w
	if s.toPiece then
		local hasta = place[s.toPiece]
		if hasta then w = (hasta.x + s.toDx) - x end
	end
	return x, s.dy, w or 0, s.h or 0
end

-- La celda i de un hueco con rejilla. Sin rejilla, i=1 es el hueco entero.
local function SlotCell(s, i)
	local x, y, w, h = SlotRect(s)
	local cols, rows = s.cols or 1, s.rows or 1
	if cols == 1 and rows == 1 then return x, y, w, h end
	local c = (i - 1) % cols
	local r = math.floor((i - 1) / cols)
	return x + c * s.pitch, y + r * s.pitch, s.w, s.h
end

local function SlotCount(s)
	return (s.cols or 1) * (s.rows or 1)
end

--- Los huecos con marco ----------------------------------------------------
--
-- Frames de verdad para que otro modulo pueda alojar algo dentro: el `Minimap`
-- de Blizzard en uno, el modelo 3D del heroe en el otro. No dibujan nada: son
-- solo un sitio con coordenadas que se mueve y se reescala con la barra.
--
-- El NIVEL importa: las piezas son OPACAS donde esta el hueco (alfa 255 en
-- todos sus pixeles, medido), asi que lo alojado tiene que ir POR ENCIMA del
-- panel o no se ve. Es el mismo tropiezo que costo el minimapa la primera vez.

local function BuildSlotFrames()
	for _, s in ipairs(SLOTS) do
		if s.host then
			local f = CreateFrame("Frame", "RTSBarSlot_" .. s.key, bar)
			f:SetFrameLevel(bar:GetFrameLevel() + 2)
			f:EnableMouse(false)
			hosts[s.key] = f
		end
	end
	miniSlot = hosts.minimap
end

local function LayoutSlotFrames()
	for _, s in ipairs(SLOTS) do
		local f = hosts[s.key]
		if f then
			local x, y, w, h = SlotRect(s)
			f:SetWidth(w)
			f:SetHeight(h)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
		end
	end
end

-- El marco de un hueco, para quien quiera meter algo dentro.
function B:SlotFrame(key)
	self:Create()
	return hosts[key]
end

--- Guias -------------------------------------------------------------------
--
-- Donde acaba cada pieza, donde estan los huecos y cada una de sus celdas, y
-- un cuadrado de 64 px para comprobar el 1:1 de un vistazo. Se CREAN una vez y
-- se COLOCAN en cada distribucion, por lo mismo que las piezas.

local function Line(parent, r, g, b, a)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture(r, g, b, a or 1)
	return t
end

local function Text(parent, size, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(GameFontNormal:GetFont(), size, "OUTLINE")
	fs:SetTextColor(r or 1, g or 0.85, b or 0.4)
	return fs
end

local g = { div = {}, lbl = {}, slot = {} }

local function BuildGuides()
	guides = CreateFrame("Frame", "RTSBarGuides", bar)
	guides:SetAllPoints(bar)
	guides:EnableMouse(false)
	guides:Hide()

	g.ref = Line(guides, 1, 1, 1, 0.25)
	g.ref:SetWidth(64)
	g.ref:SetHeight(64)
	g.refLabel = Text(guides, 11, 1, 1, 1)
	g.refLabel:SetText("64 px 1:1")
end

local function Box(edges, x, y, w, h)
	local spec = {
		{ w, 1, 0, 0 }, { w, 1, 0, h - 1 },
		{ 1, h, 0, 0 }, { 1, h, w - 1, 0 },
	}
	for e = 1, 4 do
		local d = spec[e]
		edges[e]:SetWidth(d[1] > 0 and d[1] or 1)
		edges[e]:SetHeight(d[2] > 0 and d[2] or 1)
		edges[e]:ClearAllPoints()
		edges[e]:SetPoint("TOPLEFT", guides, "TOPLEFT", x + d[3], -(y + d[4]))
		edges[e]:Show()
	end
end

-- Las divisiones son tantas como piezas DIBUJADAS, y eso cambia con `grow`,
-- asi que se agrupan bajo demanda igual que las texturas.
local function Divider(i)
	if not g.div[i] then
		g.div[i] = Line(guides, 1, 0.2, 0.2, 0.85)
		g.div[i]:SetWidth(1)
		g.div[i]:SetHeight(BAR_H)
		g.lbl[i] = Text(guides, 10, 1, 0.35, 0.35)
	end
	return g.div[i], g.lbl[i]
end

local function SlotGuide(i, cell)
	g.slot[i] = g.slot[i] or { cells = {}, label = Text(guides, 11, 0.4, 1, 0.5) }
	local rec = g.slot[i]
	if not rec.cells[cell] then
		rec.cells[cell] = {}
		for e = 1, 4 do
			rec.cells[cell][e] = Line(guides, 0.3, 1, 0.4, 0.9)
		end
	end
	return rec
end

local function LayoutGuides()
	local x = 0
	local n = 0
	for _, p in ipairs(order) do
		x = x + (p.gap or 0)
		n = n + 1
		local div, lbl = Divider(n)
		div:ClearAllPoints()
		div:SetPoint("TOPLEFT", guides, "TOPLEFT", x, 0)
		div:Show()
		lbl:ClearAllPoints()
		lbl:SetPoint("BOTTOMLEFT", guides, "TOPLEFT", x + 2, 2)
		lbl:SetText(("%s %d"):format(p.key, p.w))
		lbl:Show()
		x = x + p.w
	end

	n = n + 1
	local div, lbl = Divider(n)
	div:ClearAllPoints()
	div:SetPoint("TOPLEFT", guides, "TOPLEFT", x - 1, 0)
	div:Show()
	lbl:SetText("")

	for i = n + 1, #g.div do g.div[i]:Hide(); g.lbl[i]:Hide() end

	for i, s in ipairs(SLOTS) do
		local total = SlotCount(s)
		local rec
		for c = 1, total do
			rec = SlotGuide(i, c)
			local cx, cy, cw, ch = SlotCell(s, c)
			Box(rec.cells[c], cx, cy, cw, ch)
		end
		for c = total + 1, #rec.cells do
			for e = 1, 4 do rec.cells[c][e]:Hide() end
		end

		local sx, sy, sw, sh = SlotRect(s)
		rec.label:ClearAllPoints()
		rec.label:SetPoint("TOPLEFT", guides, "TOPLEFT", sx + 3, -(sy + 3))
		rec.label:SetText(("%s\n%dx%d%s"):format(s.label, sw, sh,
			total > 1 and (" x%d"):format(total) or ""))
	end

	g.ref:ClearAllPoints()
	g.ref:SetPoint("BOTTOMLEFT", guides, "TOPLEFT", 0, 16)
	g.refLabel:ClearAllPoints()
	g.refLabel:SetPoint("LEFT", g.ref, "RIGHT", 4, 0)
end

--- Crear -------------------------------------------------------------------

function B:Create()
	if bar then return end

	bar = CreateFrame("Frame", "RTSBar", UIParent)
	bar:SetHeight(BAR_H)
	bar:SetFrameStrata("MEDIUM")
	bar:EnableMouse(false)
	bar:Hide()

	if type(RTSCommandDB.bar) == "table" then
		for _, k in ipairs({ "pad", "side", "minSide", "share", "scale", "grow" }) do
			local v = tonumber(RTSCommandDB.bar[k])
			if v then self.cfg[k] = Clamp(k, v) end
		end
		if type(RTSCommandDB.bar.auto) == "boolean" then
			self.autoShare = RTSCommandDB.bar.auto
		end
		if type(RTSCommandDB.bar.autogrow) == "boolean" then
			self.autoGrow = RTSCommandDB.bar.autogrow
		end
		if type(RTSCommandDB.bar.guides) == "boolean" then
			self.showGuides = RTSCommandDB.bar.guides
		end
		-- Que se vea. Un ajuste guardado que se ignora en silencio es
		-- exactamente el fallo que este aviso existe para no repetir.
		if #descartados > 0 then
			ns.Print(("|cffff8800barra:|r ignorado lo guardado fuera de rango " ..
				"(%s) - vuelve a los valores de fabrica en esas claves.")
				:format(table.concat(descartados, ", ")))
		end
	end

	BuildSlotFrames()
	BuildGuides()
	self:Place()

	local ev = CreateFrame("Frame", "RTSBarEvents")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:SetScript("OnEvent", function() B:Place() end)
end

--- Tamano ------------------------------------------------------------------

-- El ancho fisico de la pantalla. `HUD.screenW` solo esta puesto si el HUD ya
-- corrio su ApplyScale, y /rts bar se puede usar sin entrar en modo RTS, asi
-- que hay respaldo: el alto fisico por la relacion de aspecto de UIParent, que
-- es la de la ventana real.
local function ScreenWidth()
	local w = ns.HUD.screenW
	if w and w > 0 then return w end
	local h = ns.HUD.pixels
	local sw, sh = GetScreenWidth(), GetScreenHeight()
	if h and h > 0 and sw and sh and sh > 0 then return h * (sw / sh) end
	return nil
end

-- La escala a la que el arte de HOY llega justo al suelo del margen. Es el
-- techo: por encima de esto la barra se come el margen y acaba cortada.
function B:MaxScale()
	local w = ScreenWidth()
	if not w or w <= 0 then return 1 end
	if BAR_W <= 0 then return 1 end
	local libre = w - w * (self.cfg.minSide or 0) * 2
	if libre <= 0 then return 1 end
	return libre / BAR_W
end

-- La escala que pide el alto. NO depende del ancho del arte, y por eso se puede
-- calcular ANTES de decidir cuantas copias hay -- que es lo que rompe el pez
-- que se muerde la cola entre escala y `grow`.
function B:ShareScale()
	local h = ns.HUD.pixels
	if not h or h <= 0 then return nil end
	return (self.cfg.share * h) / BAR_H
end

function B:ArtScale()
	local s
	if self.autoShare then s = self:ShareScale() end
	s = s or self.cfg.scale or 1
	local cap = self:MaxScale()
	if cap > 0 and s > cap then s = cap end
	return s
end

function B:ArtHeight()
	return BAR_H * self:ArtScale()
end

--- Cuantas copias del panel central --------------------------------------

-- El ancho de la barra con n copias, en pixeles de DIBUJO.
local function WidthFor(n)
	local w = 0
	for _, p in ipairs(PIECES) do
		w = w + (p.gap or 0) + p.w * ((p.key == GROW) and n or 1)
	end
	return w
end

-- Elegir la cuenta que deja el margen mas cerca del pedido.
--
-- SE ELIGE POR EL MARGEN QUE SALE, no por el ancho que falta, y no es lo mismo:
-- el suelo `minSide` es una condicion sobre el margen, asi que medir en esa
-- misma unidad deja el descarte en una linea en vez de en una conversion.
--
-- Empatar hacia ABAJO a proposito. Entre dos cuentas igual de cerca, la de
-- menos copias deja mas mundo visible, y pasarse de ancho es el unico error de
-- los dos que se ve como arte cortado.
function B:BestGrow()
	local w = ScreenWidth()
	local s = self.autoShare and self:ShareScale() or (self.cfg.scale or 1)
	if not w or w <= 0 or not s or s <= 0 then return self.cfg.grow or 1 end

	local mejor, dist = nil, nil
	for n = LIMITS.grow[1], LIMITS.grow[2] do
		local margen = (w - WidthFor(n) * s) / 2 / w
		if margen >= (self.cfg.minSide or 0) then
			local d = math.abs(margen - (self.cfg.side or 0))
			if not dist or d < dist - 0.0001 then mejor, dist = n, d end
		end
	end
	-- Ninguna cabe: la mas estrecha, y el tope de `ArtScale` la encoge.
	return mejor or LIMITS.grow[1]
end

-- Se resuelve al principio de cada distribucion, antes de colocar nada. El
-- orden importa: la escala sale del alto (no mira el ancho), luego `grow` sale
-- de la escala, y solo entonces se conoce `BAR_W`.
function B:ResolveGrow()
	if self.autoGrow then self.cfg.grow = self:BestGrow() end
end

function B:Place()
	if not bar then return end
	self:ResolveGrow()
	LayoutPieces()
	LayoutSlotFrames()
	LayoutGuides()
	ns.HUD:ScaleFrame(bar)
	bar:SetScale(bar:GetScale() * self:ArtScale())
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, self.cfg.pad)
	-- El mapa se reescala con la barra: su hueco puede haber cambiado de tamano.
	if self.active then
		ns.HUD:HostMinimap(miniSlot, miniSlot:GetWidth())
		if ns.Portrait then ns.Portrait:Relayout() end
	end
end

--- Entrar y salir ----------------------------------------------------------

-- Sin retorno temprano a proposito: todo lo de dentro se puede repetir sin dano
-- y hace falta poder repetirlo. Si /rts bar se enciende ANTES de entrar en modo
-- RTS, el HUD todavia no existe, asi que esconder la huella y alojar el mapa no
-- tienen efecto; al entrar hay que volver a aplicarlo. Con un
-- `if self.active then return end` esa segunda pasada se perdia y la huella
-- reaparecia debajo del arte.
function B:Enter()
	self:Create()
	self.active = true

	-- La huella de HUD.lua era el sustituto provisional de esto, asi que se
	-- aparta. La LINEA DE MENSAJES se queda: con el chat escondido por
	-- Chrome.lua es el unico canal de diagnostico que hay.
	ns.HUD:ShowFootprint(false)
	ns.HUD:HostMinimap(miniSlot, miniSlot:GetWidth())
	-- Guardado porque Bar.lua carga antes que Portrait.lua: al CARGAR no existe
	-- todavia, al ENTRAR si.
	if ns.Portrait then ns.Portrait:Host(hosts.portrait) end

	self:Place()
	if self.showGuides then guides:Show() else guides:Hide() end
	bar:Show()
end

function B:Leave()
	if not self.active then return end
	self.active = false
	if bar then bar:Hide() end
	-- Devolver el mapa ANTES de ensenar la huella, para que no haya un instante
	-- con el panel visible y vacio.
	ns.HUD:HostMinimap(nil)
	if ns.Portrait then ns.Portrait:Host(nil) end
	ns.HUD:ShowFootprint(true)
end

function B:Toggle()
	if self.active then self:Leave() else self:Enter() end
	ns.Print("barra de arte " ..
		(self.active and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

function B:ToggleGuides()
	self:Create()
	self.showGuides = not self.showGuides
	RTSCommandDB.bar = RTSCommandDB.bar or {}
	RTSCommandDB.bar.guides = self.showGuides
	if self.active then
		if self.showGuides then guides:Show() else guides:Hide() end
	end
	ns.Print("guias de la barra " ..
		(self.showGuides and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

--- Ajustes -----------------------------------------------------------------

local function Save(k, v)
	RTSCommandDB.bar = RTSCommandDB.bar or {}
	RTSCommandDB.bar[k] = v
end

-- El alto, en % de la pantalla. Acepta 20 o 0.20. Es la escala, y como `grow`
-- se elige DESPUES con esa escala, cambiar el alto puede cambiar la cuenta de
-- paneles -- que es justo lo que tiene que pasar.
function B:SetShare(v)
	self:Create()
	local n = tonumber(v)
	if not n or n <= 0 then return false end
	if n > 1 then n = n / 100 end
	n = Clamp("share", n)

	self.cfg.share = n
	self.autoShare = true
	Save("share", n)
	Save("auto", true)
	self:Place()
	self:PrintFit()
	return true
end

-- Cuantas copias de `middle-grow`. `auto` devuelve la eleccion al reparto
-- normal; un numero la fija y deja de seguir a `side`.
function B:SetGrow(v)
	self:Create()
	local txt = tostring(v or ""):lower()
	if txt == "auto" or txt == "" then
		self.autoGrow = true
		Save("autogrow", true)
		self:Place()
		ns.Print("copias del panel central: |cff00ff00automatico|r")
		self:PrintFit()
		return true
	end

	local n = tonumber(v)
	if not n then return false end
	n = math.floor(n)
	if n < LIMITS.grow[1] then n = LIMITS.grow[1] end
	if n > LIMITS.grow[2] then n = LIMITS.grow[2] end

	self.cfg.grow = n
	self.autoGrow = false
	Save("grow", n)
	Save("autogrow", false)
	self:Place()
	ns.Print(("copias del panel central: |cffffff00%d|r (a mano)"):format(n))
	self:PrintFit()
	return true
end

-- El renglon que contesta "como ha quedado". Sale de cada cambio de medida
-- porque con `grow` discreto el margen NUNCA es el pedido clavado, y suponerlo
-- es la unica forma de llevarse una sorpresa.
function B:PrintFit()
	local s = self:ArtScale()
	local w = ScreenWidth() or 0
	local ancho = BAR_W * s
	local hueco = (w - ancho) / 2
	local h = ns.HUD.pixels
	ns.Print(("|cffffff00%d|r panel(es) -> |cffffff00%d x %d px|r  " ..
		"alto |cffffff00%.1f%%|r (pedido %.0f%%)  " ..
		"margen |cffffff00%.1f%%|r (pedido %.0f%%, %d px)  escala x%.3f"):format(
		math.floor(self.cfg.grow or 1), math.floor(ancho + 0.5),
		math.floor(BAR_H * s + 0.5),
		(h and h > 0) and (BAR_H * s / h * 100) or 0, (self.cfg.share or 0) * 100,
		w > 0 and hueco / w * 100 or 0, (self.cfg.side or 0) * 100,
		math.floor(hueco + 0.5), s))
end

-- Multiplicador a mano, o alto en pixeles. Se distinguen por el valor: nadie
-- quiere una barra de 2 px ni una escala de 512. Apaga el derivado del alto.
function B:SetScale(v)
	self:Create()
	local n = tonumber(v)
	if not n or n <= 0 then return false end
	if n > 16 then n = n / BAR_H end

	self.cfg.scale = Clamp("scale", n)
	self.autoShare = false
	Save("scale", self.cfg.scale)
	Save("auto", false)
	self:Place()

	local s = self:ArtScale()
	if s < self.cfg.scale - 0.0001 then
		ns.Print(("|cffff8800tope:|r a mas de x%.3f la barra se come el margen")
			:format(s))
	end
	self:PrintFit()
	return true
end

-- La separacion al SUELO, en pixeles. Ya no toca los lados.
function B:SetPad(v)
	local n = tonumber(v)
	if not n then return false end
	self.cfg.pad = n
	Save("pad", n)
	self:Place()
	return true
end

-- El margen que se querria a cada lado, en % del ancho. Acepta 10 o 0.10.
--
-- NO RECORTA NADA: elige cuantas copias del panel central se dibujan. Bajarlo
-- suele meter un panel mas, subirlo quitarlo, y el salto es de 512 px de arte
-- de golpe -- por eso el margen que sale casi nunca es el pedido, y por eso se
-- imprime.
function B:SetSide(v)
	self:Create()
	local n = tonumber(v)
	if not n or n < 0 then return false end
	if n > 1 then n = n / 100 end
	n = Clamp("side", n)

	self.cfg.side = n
	Save("side", n)
	self:Place()
	self:PrintFit()
	return true
end

function B:Reset()
	self.cfg.pad, self.cfg.scale = 22, 1
	self.cfg.side, self.cfg.minSide = 0.10, 0.045
	self.cfg.share = 0.20
	self.cfg.grow = 1
	self.autoShare, self.autoGrow = true, true
	RTSCommandDB.bar = nil
	self:Place()
	ns.Print("medidas de la barra devueltas a las de fabrica.")
	self:PrintFit()
end

--- Informe -----------------------------------------------------------------

function B:Report()
	self:Create()
	local missing = {}
	for _, p in ipairs(PIECES) do
		local lista = tex[p.key]
		if not lista or not lista[1] or not lista[1]:GetTexture() then
			table.insert(missing, p.key)
		end
	end

	local s = self:ArtScale()
	local w = BAR_W * s
	ns.Print(("arte |cffffff00%d x %d|r   escala |cffffff00x%.3f|r %s  %s   " ..
		"separacion de los railes %d px"):format(
		BAR_W, BAR_H, s,
		self.autoShare and "(del alto)" or "(a mano)",
		s < 0.999 and "|cff00ff00(reducido)|r"
		           or (s > 1.001 and "|cffff8800(AMPLIADO)|r" or "|cff00ff00(1:1)|r"),
		GAP))

	self:PrintFit()

	-- Que hay a un panel de distancia, en las dos direcciones. Con `grow`
	-- discreto es la pregunta que se hace uno al ver el margen que salio, y
	-- contestarla aqui evita tener que probar a ciegas.
	local sw = ScreenWidth() or 0
	local n = math.floor(self.cfg.grow or 1)
	local vecinos = {}
	for _, d in ipairs({ -1, 1 }) do
		local m = n + d
		if m >= LIMITS.grow[1] and m <= LIMITS.grow[2] and sw > 0 then
			local margen = (sw - WidthFor(m) * s) / 2 / sw
			table.insert(vecinos, ("%d -> margen %.1f%%%s"):format(
				m, margen * 100,
				margen < (self.cfg.minSide or 0) and " |cffff0000(no cabe)|r" or ""))
		end
	end
	if #vecinos > 0 then
		ns.Print(("paneles: |cff888888%s|r   (%s)"):format(
			table.concat(vecinos, "   "),
			self.autoGrow and "automatico" or "fijado a mano"))
	end

	if self.cfg.pad ~= 22 then
		ns.Print(("suelo |cffffff00%d px|r"):format(self.cfg.pad))
	end
	if #missing == 0 then
		ns.Print("las |cff00ff007 piezas|r cargaron.")
	else
		ns.Print(("|cffff0000NO cargan: %s|r"):format(table.concat(missing, ", ")))
	end

	ns.Print("|cffffff00/rts bar share <%>|r alto  " ..
		"|cffffff00side <%>|r margen  |cffffff00grow <n|auto>|r paneles  " ..
		"|cffffff00scale <n>|r  |cffffff00guides|r  |cffffff00pad <px>|r  " ..
		"|cffffff00default|r")
end

-- "Todo lo ancho que quepa" es pedir el margen minimo. No hay una escala
-- especial detras: es el mismo reparto con otro numero.
function B:FitWidth()
	return self:SetSide(self.cfg.minSide or 0)
end
