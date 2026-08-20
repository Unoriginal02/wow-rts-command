--[[
	Bar.lua -- la barra inferior, con el arte de verdad.

	CUATRO PIEZAS, SIETE PANELES. La exportacion de 2026-08-20 dejo de dibujar
	cada panel por separado: ahora hay cuatro dibujos y dos de ellos se usan DOS
	VECES, uno espejado. La barra, de izquierda a derecha:

	  left-bar 128 | 16 | minimap 512 | ramp 128 |
	  middle 512 xN |
	  ramp' 128 | minimap 512 | 16 | left-bar' 128

	(`'` = espejada horizontalmente con SetTexCoord)

	POR QUE ESPEJAR EN VEZ DE EXPORTAR MAS PIEZAS. Un espejo cuesta cuatro
	numeros en una llamada y no puede desincronizarse del original; dos ficheros
	dibujados a mano que deberian ser iguales, si. Y baja el arte de 7 TGA
	(4,2 MB) a 4 (2,6 MB). El precio es que el hueco util de una pieza espejada
	no esta donde dice el escaneo, sino en su reflejo -- por eso los huecos estan
	en la tabla `HOLE` medidos UNA vez y con las dos variantes escritas.

	LO QUE ES CADA PANEL, que es lo que decide donde va cada cosa:

	  rail izq    los botones del minimapa (mapa, rastreo, zoom, calendario)
	  minimapa    el minimapa de verdad, cuadrado
	  ramp        el hombro: baja del alto completo al alto de la sala
	  sala        retrato 3D + barras del heroe | grupo | enemigos / acciones
	  ramp'       el hombro de vuelta
	  ordenes     rejilla 3x3 de ordenes globales; la ultima casilla SALE del modo
	  rail der    los iconos del juego (ficha, talentos, misiones, bolsas)

	EL ARTE ES 2x Y SE DIBUJA REDUCIDO, ~x0.56 en 2560x1440. Las piezas de 256
	se quedaban cortas al lado de las texturas del propio cliente, que son
	bastante mayores. Los numeros de este fichero son los del DIBUJO (512 de
	alto) y la escala de pantalla los baja. Reducir sale nitido; lo que emborrona
	es ampliar, y esta barra ya no amplia nunca.

	EL ALTO LO PONE `share` Y EL ANCHO LO LLENA `grow`. Son dos mandos para dos
	cosas distintas, y la clave es que `grow` NO es continuo: repetir el panel
	central cambia la proporcion del dibujo, que es un grado de libertad de
	verdad y no una segunda forma de pedir lo mismo.

	  1. `share` = 0.20 del alto de pantalla  -> sale la ESCALA
	  2. con esa escala, cuantas copias del central hacen falta para dejar
	     `side` = 0.10 de margen a cada lado  -> sale `grow`

	`grow` ES DISCRETO, asi que el margen casi nunca cae en el 10% clavado: se
	elige la cuenta que mas se acerca, con un suelo por debajo del cual no se
	deja bajar. El margen que sale se imprime, no se supone.

	LOS DOS HUECOS DE 16 SON LA UNICA SEPARACION QUE HAY. Los railes de botones
	de los extremos flotan sueltos; todo lo del centro se toca.

	`middle` SE REPITE, y es la unica pieza que puede: su dibujo llega de borde a
	borde, asi que dos copias seguidas no dejan costura. `/rts bar grow <n>`.

	TODA POSICION SE DERIVA, NINGUNA SE ESCRIBE. Cada hueco dice a QUE PIEZA
	pertenece y con que margen, y su x sale de donde acabo la anterior. Es lo que
	hace que repetir el panel central N veces no obligue a tocar un solo numero
	de los demas. Un hueco que ABARCA varias piezas -- la sala -- se declara con
	`toPiece`/`toDx`.

	LAS MEDIDAS DE LOS HUECOS ESTAN MEDIDAS, NO ELEGIDAS. Salen de escanear los
	PNG de `art-src` buscando, desde el centro de cada pieza hacia fuera, el
	primer pixel de bisel claro. Cuando el arte cambie se vuelven a escanear.

	LO QUE HAY DENTRO DE UN HUECO NO ESTA EN EL ARTE, asi que no se mide: se
	reparte. La rejilla de un hueco se declara con `cell` y se CENTRA sola en el
	area medida, o se alinea a un lado con `align`. `fill` significa "tantas
	columnas como quepan", que es la unica forma honesta de contarlas cuando el
	ancho depende de `grow`.

	QUIEN DIBUJA LO DE DENTRO NO ES ESTE FICHERO. Aqui estan el arte, las areas
	y las celdas; el contenido lo ponen Portrait, Vitals, Roster, Foes, Card,
	Panel y Rails, cada uno pidiendo su area con `B:SlotFrame(key)` y sus celdas
	con `B:Cells(key)`, y volviendose a colocar cuando `B:OnLayout` avisa.

	POR QUE NO PASA POR Skin.lua. Skin viste con `SetBackdrop`, cuyo `edgeFile`
	es una hoja con los ocho trozos del borde en una disposicion que nadie aqui
	ha verificado. Estas piezas son cada una un dibujo entero, asi que se colocan
	como TEXTURAS EXPLICITAS y se ancla cada una a mano.

	EL ARTE NO TOCA EL RATON. `EnableMouse(false)` en la barra y en las areas:
	una barra que se come los clicks rompe la caja de seleccion por esa zona
	(prueba B6). Los BOTONES si lo cogen, pero solo sobre su propio rectangulo.
]]

local ADDON, ns = ...

local B = {}
ns.Bar = B

B.active = false

local ART = "Interface\\AddOns\\RTSCommand\\art\\"

-- El alto del DIBUJO. La escala de pantalla lo baja.
local BAR_H = 512

-- La separacion de los railes. Un solo numero, en un solo sitio.
local GAP = 16

--- Las piezas -------------------------------------------------------------
--
-- `id` es unico y es lo que usan los huecos; `art` es el fichero, que se puede
-- repetir. `flip` lo dibuja espejado. `gap` es el hueco QUE VA ANTES.
-- `grow` marca la unica pieza que se repite.

local HALL = "hall"

local PIECES = {
	{ id = "rail-left",  art = "left-bar", w = 128 },
	{ id = "map",        art = "minimap",  w = 512, gap = GAP },
	{ id = "ramp-left",  art = "ramp",     w = 128 },
	{ id = HALL,         art = "middle",   w = 512, grow = true },
	{ id = "ramp-right", art = "ramp",     w = 128, flip = true },
	{ id = "orders",     art = "minimap",  w = 512 },
	{ id = "rail-right", art = "left-bar", w = 128, gap = GAP, flip = true },
}

--- Los huecos del arte, medidos -------------------------------------------
--
-- Reproducible: por cada PNG de `art-src`, desde el centro hacia fuera hasta el
-- primer pixel con luminancia > 70 (el bisel) o alfa 0. Lo que queda dentro es
-- el hueco util, en pixeles de dibujo y relativo a SU pieza.
--
-- `railF` y `rampR` son los reflejos de `rail` y `rampL`: espejar una pieza de
-- ancho W manda el hueco [x, x+w) a [W-x-w, W-x). Escrito, no recalculado a
-- mano cada vez que hace falta.

local HOLE = {
	rail  = { x = 29, w = 78,  y = 30,  h = 452 },   -- left-bar
	railF = { x = 21, w = 78,  y = 30,  h = 452 },   -- left-bar espejada
	map   = { x = 19, w = 474, y = 30,  h = 452 },   -- minimap
	rampL = { x = 21, w = 107, y = 122, h = 360 },   -- ramp
	rampR = { x = 0,  w = 107, y = 122, h = 360 },   -- ramp espejada
	mid   = { x = 0,  w = 512, y = 122, h = 360 },   -- middle, de borde a borde
}

--- El reparto de la sala --------------------------------------------------
--
-- Lo unico de este fichero que es una DECISION y no una medida. La sala mide
-- 360 de alto y `214 + 512*grow` de ancho, y hay que meter cinco cosas:
--
--   retrato 3D  /  barras del heroe debajo   -- bloque del heroe, ancho fijo
--   grupo                                    -- 4 filas, ancho fijo
--   enemigos / divisor / acciones            -- todo lo que sobre
--
-- Los dos primeros son de ancho fijo a proposito: un retrato que crece con la
-- resolucion se ve mal, y una barra de vida de 900 px no dice mas que una de
-- 440. Lo que se estira es lo que gana con el sitio -- cuantos enemigos caben y
-- cuantas acciones -- y eso sale de `fill`.

local PAD = 8      -- margen interior de la sala
local COL = 16     -- separacion entre bloques

local HERO_W  = 256
local PARTY_W = 440

-- `HALL_Y1` es el borde de ABAJO, exclusivo: `h = HALL_Y1 - y`. Escrito asi
-- porque la primera version le quitaba un pixel de mas ("la ultima fila es la
-- 481") y las cuatro filas del grupo salian un pixel mas altas que su hueco --
-- invisible, pero es la clase de descuadre que luego se busca en el sitio
-- equivocado. El hueco ocupa las filas 122..481, o sea [122, 482).
local HALL_Y0 = HOLE.rampL.y + PAD                        -- 130
local HALL_Y1 = HOLE.rampL.y + HOLE.rampL.h - PAD         -- 474

local PORTRAIT_H = 256
local VITALS_Y   = HALL_Y0 + PORTRAIT_H + PAD             -- 394
local FOES_H     = 110
local RULE_Y     = HALL_Y0 + FOES_H + PAD                 -- 248
local CARD_Y     = RULE_Y + 3 + PAD                       -- 259

-- La x de cada bloque, relativa a la pieza `ramp-left`, que es donde empieza el
-- hueco de la sala.
local HALL_X  = HOLE.rampL.x                              -- 21
local HERO_X  = HALL_X + PAD                              -- 29
local PARTY_X = HERO_X + HERO_W + COL                     -- 301
local RIGHT_X = PARTY_X + PARTY_W + COL                   -- 757

-- Donde acaba la sala: dentro de la rampa espejada, dejando su margen.
local HALL_END = HOLE.rampR.w - PAD                       -- 99

--- Los huecos --------------------------------------------------------------
--
-- `piece`/`dx`/`dy`/`w`/`h` es el AREA. Si lleva `toPiece`/`toDx`, el ancho
-- llega hasta ese punto de esa otra pieza, y entonces sigue bien se repita el
-- panel central lo que se repita.
--
-- `cell` es la rejilla de dentro: tamano de celda y paso. Se centra en el area,
-- o se pega a un lado con `align`. `cols`/`rows` la cuentan; `fill = "cols"`
-- pone tantas columnas como quepan.
--
-- `host = true` -> ademas del rectangulo, un Frame de verdad donde otro modulo
-- mete lo suyo. `line = true` -> una raya, que es todo lo que es el divisor.
--
-- El NIVEL importa: las piezas son OPACAS donde esta el hueco, asi que lo
-- alojado va POR ENCIMA del panel o no se ve. Es el tropiezo que costo el
-- minimapa la primera vez.

local SLOTS = {
	{ key = "rail-left", piece = "rail-left", label = "rail mapa",
	  dx = HOLE.rail.x, dy = HOLE.rail.y, w = HOLE.rail.w, h = HOLE.rail.h,
	  cell = { w = 68, h = 68, px = 76, py = 76 }, cols = 1, rows = 6,
	  host = true },

	{ key = "minimap", piece = "map", label = "minimapa",
	  dx = HOLE.map.x, dy = HOLE.map.y, w = HOLE.map.w, h = HOLE.map.h,
	  cell = { w = 452, h = 452 }, cols = 1, rows = 1,
	  host = true },

	{ key = "portrait", piece = "ramp-left", label = "retrato",
	  dx = HERO_X, dy = HALL_Y0, w = HERO_W, h = PORTRAIT_H,
	  host = true },

	{ key = "vitals", piece = "ramp-left", label = "vida/poder/exp",
	  dx = HERO_X, dy = VITALS_Y, w = HERO_W, h = HALL_Y1 - VITALS_Y,
	  host = true },

	{ key = "party", piece = "ramp-left", label = "grupo",
	  dx = PARTY_X, dy = HALL_Y0, w = PARTY_W, h = HALL_Y1 - HALL_Y0,
	  cell = { w = PARTY_W, h = 80, py = 88 }, cols = 1, rows = 4,
	  align = "top", host = true },

	{ key = "foes", piece = "ramp-left", label = "enemigos",
	  dx = RIGHT_X, dy = HALL_Y0, h = FOES_H,
	  toPiece = "ramp-right", toDx = HALL_END,
	  cell = { w = 96, h = FOES_H, px = 104 }, rows = 1, fill = "cols",
	  align = "left", host = true },

	{ key = "rule", piece = "ramp-left", label = "divisor",
	  dx = RIGHT_X, dy = RULE_Y, h = 3,
	  toPiece = "ramp-right", toDx = HALL_END,
	  line = true },

	{ key = "card", piece = "ramp-left", label = "acciones",
	  dx = RIGHT_X, dy = CARD_Y, h = HALL_Y1 - CARD_Y,
	  toPiece = "ramp-right", toDx = HALL_END,
	  cell = { w = 103, h = 103, px = 111, py = 111 }, rows = 2, fill = "cols",
	  align = "topleft", host = true },

	{ key = "orders", piece = "orders", label = "ordenes 3x3",
	  dx = HOLE.map.x, dy = HOLE.map.y, w = HOLE.map.w, h = HOLE.map.h,
	  cell = { w = 144, h = 144, px = 154, py = 154 }, cols = 3, rows = 3,
	  host = true },

	{ key = "rail-right", piece = "rail-right", label = "rail juego",
	  dx = HOLE.railF.x, dy = HOLE.railF.y, w = HOLE.railF.w, h = HOLE.railF.h,
	  cell = { w = 68, h = 68, px = 76, py = 76 }, cols = 1, rows = 6,
	  host = true },
}

local bar, guides, miniSlot
local hosts = {}     -- key de hueco -> Frame anfitrion
local lines = {}     -- key de hueco -> textura de raya
local tex = {}       -- id de pieza -> lista de texturas (la repetida usa varias)
local place = {}     -- id de pieza -> { x = primera x, right = donde acaba }
local order = {}     -- la lista plana, ya con las repeticiones dentro
local listeners = {}
local BAR_W = 0

-- `share` da la ESCALA: la fraccion del alto de pantalla que ocupa la barra.
-- 0.20 sale de la referencia, no del gusto -- la consola de WC3 ocupa ~25% del
-- alto y la de SC2 ~22%.
--
-- `side` da el GROW: el margen que se querria a cada lado, en fraccion del
-- ancho. No recorta nada; decide cuantas copias del panel central se dibujan.
--
-- `minSide` es el suelo, y existe porque `grow` es discreto: entre dos cuentas,
-- la de arriba puede llegar a pegar el arte al borde.
--
-- `side` en fraccion y `pad` en pixeles a proposito: `pad` es la separacion al
-- SUELO y no tiene nada que ver con el ancho.
B.cfg = { pad = 22, side = 0.10, minSide = 0.045, share = 0.20, scale = 1, grow = 1 }

-- Derivar la escala del alto, y la cuenta de copias del ancho. Fijar cualquiera
-- de los dos a mano apaga SOLO ese.
B.autoShare = true
B.autoGrow = true

-- LO GUARDADO SE ACOTA AL LEERLO, NO SOLO AL ESCRIBIRLO. Un fichero de
-- SavedVariables no olvida nunca: guarda cualquier clave que se haya escrito
-- alguna vez y sobrevive a la version del addon que la escribio. Este ya traia
-- un `grow = 688` de una version anterior -- que como numero de copias no
-- significa nada -- y sin acotarlo al cargar habria salido una barra de ocho
-- paneles diminuta, sin nada que dijera por que.
--
-- Acotar solo dentro de los `Set*` no vale: esos solo corren cuando el jugador
-- escribe el comando, y el problema entra por el otro lado.
--
-- `strict` es la diferencia entre un knob continuo y una cuenta. Pasarse en
-- `share` es una intencion que se puede recortar; un `grow` de 688 es basura y
-- vuelve al valor de fabrica.
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
	if n < LIMITS.grow[1] then n = LIMITS.grow[1] end
	if n > LIMITS.grow[2] then n = LIMITS.grow[2] end

	order = {}
	for _, p in ipairs(PIECES) do
		local veces = p.grow and n or 1
		for i = 1, veces do
			table.insert(order, {
				id = p.id, art = p.art, w = p.w, flip = p.flip,
				-- el hueco va solo antes de la PRIMERA copia
				gap = (i == 1) and (p.gap or 0) or 0,
			})
		end
	end
end

--- Piezas ------------------------------------------------------------------

-- Las texturas se crean bajo demanda y no se destruyen: bajar `grow` esconde
-- las sobrantes en vez de borrarlas, para que volver a subirlo no cree nada.
local function TextureFor(p, i)
	tex[p.id] = tex[p.id] or {}
	local t = tex[p.id][i]
	if not t then
		t = bar:CreateTexture(nil, "ARTWORK")
		t:SetTexture(ART .. p.art)
		t:SetHeight(BAR_H)
		-- El espejo, y el unico sitio donde ocurre.
		if p.flip then t:SetTexCoord(1, 0, 0, 1) end
		tex[p.id][i] = t
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

		usadas[p.id] = (usadas[p.id] or 0) + 1
		local t = TextureFor(p, usadas[p.id])
		t:ClearAllPoints()
		t:SetWidth(p.w)
		t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
		t:Show()

		place[p.id] = place[p.id] or { x = x }
		x = x + p.w
		place[p.id].right = x
	end

	-- Las copias que ya no hacen falta.
	for id, lista in pairs(tex) do
		for i = (usadas[id] or 0) + 1, #lista do lista[i]:Hide() end
	end

	BAR_W = x
	bar:SetWidth(BAR_W)
end

--- Areas y celdas ---------------------------------------------------------

-- Donde cae un area, en coordenadas de la barra (y hacia abajo). Sale de su
-- pieza, asi que sigue bien cuando lo de su izquierda cambia de numero.
local function SlotArea(s)
	local rec = place[s.piece]
	if not rec then return 0, 0, 0, 0 end
	local x = rec.x + s.dx
	local w = s.w
	if s.toPiece then
		local hasta = place[s.toPiece]
		if hasta then w = (hasta.x + s.toDx) - x end
	end
	return x, s.dy, w or 0, s.h or 0
end

-- Cuantas columnas y filas. `fill` las cuenta contra el area, que es la unica
-- forma honesta de hacerlo cuando el ancho depende de `grow`.
local function SlotGrid(s)
	local cell = s.cell
	if not cell then return 1, 1 end
	local _, _, w, h = SlotArea(s)

	-- UN AREA QUE NO CABE NO TIENE CELDAS, y decirlo aqui es lo que evita el
	-- unico caso feo del reparto: con `grow` a 1 la sala mide 726 y el bloque de
	-- la derecha empieza en el 757, asi que su ancho sale NEGATIVO. Devolviendo
	-- cero, `Cells` devuelve una lista vacia, los paneles esconden sus botones y
	-- no queda ninguno flotando sobre la rampa. La barra se ve pequena, que es
	-- exactamente lo que se pidio.
	if w <= 0 or h <= 0 then return 0, 0 end

	local cols, rows = s.cols or 1, s.rows or 1
	if s.fill == "cols" or s.fill == "both" then
		local px = cell.px or cell.w
		cols = (px > 0) and (math.floor((w - cell.w) / px) + 1) or 1
		if cols < 1 then cols = 1 end
	end
	if s.fill == "rows" or s.fill == "both" then
		local py = cell.py or cell.h
		rows = (py > 0) and (math.floor((h - cell.h) / py) + 1) or 1
		if rows < 1 then rows = 1 end
	end
	return cols, rows
end

-- La celda i, en coordenadas de la barra. Sin rejilla, i=1 es el area entera.
--
-- LA REJILLA SE CENTRA SOLA en el area medida. Es lo que permite que `dx`/`dy`
-- sigan siendo el hueco del arte tal cual salio del escaneo, en vez de un
-- numero ajustado a mano que ya no se puede comprobar contra el PNG.
local function SlotCell(s, i)
	local x, y, w, h = SlotArea(s)
	local cell = s.cell
	if not cell then return x, y, w, h end

	local cols, rows = SlotGrid(s)
	local px = cell.px or cell.w
	local py = cell.py or cell.h
	local gw = (cols - 1) * px + cell.w
	local gh = (rows - 1) * py + cell.h

	local align = s.align or ""
	local ox = string.find(align, "left") and 0
		or (string.find(align, "right") and (w - gw) or math.floor((w - gw) / 2))
	local oy = string.find(align, "top") and 0
		or (string.find(align, "bottom") and (h - gh) or math.floor((h - gh) / 2))

	local c = (i - 1) % cols
	local r = math.floor((i - 1) / cols)
	return x + ox + c * px, y + oy + r * py, cell.w, cell.h
end

local function SlotCount(s)
	local cols, rows = SlotGrid(s)
	return cols * rows
end

local function SlotByKey(key)
	for _, s in ipairs(SLOTS) do
		if s.key == key then return s end
	end
end

-- EL MINIMAPA ES CUADRADO Y SU HUECO NO. El hueco medido de la pieza es 474x452,
-- asi que escalar el mapa al ANCHO del hueco lo saca 22 px por arriba y por
-- abajo -- y un frame hijo no se recorta en 3.3.5a, asi que se comeria el borde
-- del arte por los dos lados. Lo que se le pasa es el lado de la CELDA, que es
-- el cuadrado ya centrado dentro del hueco.
local function MiniBox()
	local s = SlotByKey("minimap")
	if s and s.cell then return math.min(s.cell.w, s.cell.h) end
	return miniSlot and miniSlot:GetWidth() or 0
end

--- La interfaz que usan los modulos de contenido --------------------------

-- El marco de un area. Es el padre de todo lo que se dibuje ahi dentro.
function B:SlotFrame(key)
	self:Create()
	return hosts[key]
end

-- Las celdas de un area, EN COORDENADAS DEL MARCO (x hacia la derecha, y hacia
-- abajo, desde su esquina de arriba a la izquierda). Asi el que las usa hace
-- SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y) y no necesita saber nada de
-- la barra ni de `grow`.
function B:Cells(key)
	self:Create()
	local s = SlotByKey(key)
	if not s then return {} end
	local ax, ay = SlotArea(s)
	local out = {}
	for i = 1, SlotCount(s) do
		local cx, cy, cw, ch = SlotCell(s, i)
		out[i] = { x = cx - ax, y = cy - ay, w = cw, h = ch }
	end
	return out
end

function B:SlotSize(key)
	self:Create()
	local s = SlotByKey(key)
	if not s then return 0, 0 end
	local _, _, w, h = SlotArea(s)
	return w, h
end

-- Avisar cuando la barra se ha vuelto a distribuir. Cambiar `grow`, `share` o
-- la resolucion cambia el NUMERO de celdas, no solo su tamano, asi que el
-- contenido no puede colocarse una vez y olvidarse.
function B:OnLayout(fn)
	table.insert(listeners, fn)
	if bar then fn() end
end

local function Announce()
	for _, fn in ipairs(listeners) do
		-- Un modulo que falle no puede llevarse por delante a los demas ni
		-- dejar la barra a medio colocar.
		local ok, err = pcall(fn)
		if not ok then ns.Print("|cffff0000barra:|r " .. tostring(err)) end
	end
end

--- Los huecos con marco ----------------------------------------------------

local function BuildSlotFrames()
	for _, s in ipairs(SLOTS) do
		if s.host then
			local f = CreateFrame("Frame", "RTSBarSlot_" .. s.key, bar)
			f:SetFrameLevel(bar:GetFrameLevel() + 2)
			f:EnableMouse(false)
			hosts[s.key] = f
		end
		if s.line then
			local t = bar:CreateTexture(nil, "OVERLAY")
			t:SetTexture(0.55, 0.58, 0.66, 0.55)
			lines[s.key] = t
		end
	end
	miniSlot = hosts.minimap
end

local function LayoutSlotFrames()
	for _, s in ipairs(SLOTS) do
		local x, y, w, h = SlotArea(s)
		local f = hosts[s.key]
		if f then
			f:SetWidth(w > 0 and w or 1)
			f:SetHeight(h > 0 and h or 1)
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
		end
		local t = lines[s.key]
		if t then
			t:SetWidth(w > 0 and w or 1)
			t:SetHeight(h > 0 and h or 1)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -y)
		end
	end
end

--- Guias -------------------------------------------------------------------
--
-- Donde acaba cada pieza, donde estan los huecos y cada una de sus celdas, y un
-- cuadrado de 64 px para comprobar el 1:1 de un vistazo. Se CREAN una vez y se
-- COLOCAN en cada distribucion, por lo mismo que las piezas.

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
	guides:SetFrameLevel(bar:GetFrameLevel() + 9)
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

-- Las divisiones son tantas como piezas DIBUJADAS, y eso cambia con `grow`, asi
-- que se agrupan bajo demanda igual que las texturas.
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
		lbl:SetText(("%s %d%s"):format(p.id, p.w, p.flip and " '" or ""))
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
		rec = rec or SlotGuide(i, 1)
		for c = total + 1, #rec.cells do
			for e = 1, 4 do rec.cells[c][e]:Hide() end
		end

		local sx, sy, sw, sh = SlotArea(s)
		local cols, rows = SlotGrid(s)
		rec.label:ClearAllPoints()
		rec.label:SetPoint("TOPLEFT", guides, "TOPLEFT", sx + 3, -(sy + 3))
		rec.label:SetText(("%s\n%dx%d%s"):format(s.label, sw, sh,
			total > 1 and (" %dx%d"):format(cols, rows) or ""))
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
-- calcular ANTES de decidir cuantas copias hay -- que es lo que rompe el pez que
-- se muerde la cola entre escala y `grow`.
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
		w = w + (p.gap or 0) + p.w * (p.grow and n or 1)
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
		ns.HUD:HostMinimap(miniSlot, MiniBox())
		if ns.Portrait then ns.Portrait:Relayout() end
	end
	-- Y lo demas, que puede haber cambiado de NUMERO de celdas, no solo de
	-- tamano: `fill` cuenta columnas contra un ancho que depende de `grow`.
	Announce()
end

--- Entrar y salir ----------------------------------------------------------

-- Los paneles de contenido, en el orden en que se leen de izquierda a derecha.
-- Una lista y no siete llamadas sueltas: anadir un panel no deberia obligar a
-- tocar `Enter` y `Leave` por separado y descubrir un mes despues que uno de los
-- dos se quedo sin la linea.
local function Panels()
	return { ns.Rails, ns.Vitals, ns.Roster, ns.Foes, ns.Card, ns.Panel }
end

--- Los paneles flotantes de antes -----------------------------------------
--
-- `UnitBar` (retratos del grupo), `CommandCard` (rejilla 4x3) y `Targets`
-- (lista de objetivos) dicen ahora lo mismo que la sala de la barra: grupo,
-- acciones y enemigos. Dejarlos encima seria la misma informacion dos veces, y
-- ademas flotando sobre el arte.
--
-- SE APARTAN, NO SE BORRAN. Siguen siendo la interfaz cuando la barra esta
-- apagada (`/rts bar`), que es como se prueba media cosa.
--
-- Y SE DEVUELVEN AL ESTADO EN QUE ESTABAN, no con un `Show()` a ciegas: si el
-- jugador tenia la carta escondida con `/rts toggle`, tiene que seguir
-- escondida al salir. Es la misma regla dura que Chrome aplica a los frames de
-- Blizzard y Camera a sus CVars, y las dos veces que se rompio fue por
-- suponer el estado anterior en vez de guardarlo.
local floatWas

local function ParkFloating(park)
	local list = { ns.UnitBar, ns.CommandCard, ns.Targets }

	if park then
		if floatWas then return end        -- ya apartados
		floatWas = {}
		for i, m in ipairs(list) do
			local f = m and m.frame
			if f then
				floatWas[i] = f:IsShown()
				f:Hide()
			end
		end
		return
	end

	if not floatWas then return end
	for i, m in ipairs(list) do
		local f = m and m.frame
		if f and floatWas[i] then f:Show() end
	end
	floatWas = nil
end

-- Sin retorno temprano a proposito: todo lo de dentro se puede repetir sin dano
-- y hace falta poder repetirlo. Si /rts bar se enciende ANTES de entrar en modo
-- RTS, el HUD todavia no existe, asi que esconder la huella y alojar el mapa no
-- tienen efecto; al entrar hay que volver a aplicarlo.
function B:Enter()
	self:Create()
	self.active = true

	-- La huella de HUD.lua era el sustituto provisional de esto, asi que se
	-- aparta. La LINEA DE MENSAJES se queda: con el chat escondido por
	-- Chrome.lua es el unico canal de diagnostico que hay.
	ns.HUD:ShowFootprint(false)
	ns.HUD:HostMinimap(miniSlot, MiniBox())
	-- Se pregunta por `ns.X` en vez de guardarlo arriba porque Bar.lua carga
	-- antes que los paneles: al CARGAR no existen todavia, al ENTRAR si.
	if ns.Portrait then ns.Portrait:Host(hosts.portrait) end
	for _, m in ipairs(Panels()) do
		if m and m.Enter then m:Enter() end
	end
	ParkFloating(true)

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
	for _, m in ipairs(Panels()) do
		if m and m.Leave then m:Leave() end
	end
	ParkFloating(false)
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

-- El alto, en % de la pantalla. Acepta 20 o 0.20. Es la escala, y como `grow` se
-- elige DESPUES con esa escala, cambiar el alto puede cambiar la cuenta de
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

-- Cuantas copias de la pieza central. `auto` devuelve la eleccion al reparto
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

	-- Cuantas celdas han salido en lo que se estira. Es la consecuencia de
	-- `grow` que se ve en pantalla, y la que no se deduce del margen.
	local foes, card = SlotByKey("foes"), SlotByKey("card")
	if foes and card then
		local fc = SlotGrid(foes)
		local cc, cr = SlotGrid(card)
		ns.Print(("sala: |cffffff00%d|r enemigos  |cffffff00%dx%d|r acciones")
			:format(fc, cc, cr))
	end
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
-- suele meter un panel mas, subirlo quitarlo, y el salto es de 512 px de arte de
-- golpe -- por eso el margen que sale casi nunca es el pedido, y por eso se
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

	-- Las que faltan son FICHEROS, no paneles: dos paneles comparten dibujo, y
	-- decir "no carga minimap" dos veces no ayuda a nadie.
	local vistos, files, missing = {}, 0, {}
	for _, p in ipairs(PIECES) do
		if not vistos[p.art] then
			vistos[p.art] = true
			files = files + 1
			local lista = tex[p.id]
			if not lista or not lista[1] or not lista[1]:GetTexture() then
				table.insert(missing, p.art)
			end
		end
	end

	local s = self:ArtScale()
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
		ns.Print(("las |cff00ff00%d piezas|r cargaron (7 paneles, 2 espejados)")
			:format(files))
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
