--[[
	Hall.lua -- el reparto de la sala, y nada mas.

	La sala se vacio el 2026-09-02 para redisenarla y `Bar.lua` la dejo como UN
	rectangulo sin rejilla: 344 de alto por `710 + 512*(grow-1)` de ancho. Este
	fichero es lo que vuelve a partirla, siguiendo el boceto de
	`brief-barra-control-grupo.md`:

	  ESTADO A -- uno seleccionado (o ninguno):

	    +------+-----------------------------------------------------+
	    |LISTA |  (o)[====]  (o)[===]  (o)[==]                       | marcos
	    | x5   |  --------------------------------------------------- raya
	    |      |  [1][2][3][4][5][6][7][8][9][10][11][12][13][14]    | hechizos
	    |      |  [  macro 1  ][  macro 2  ][  macro 3  ][  macro 4 ]| macros
	    +------+-----------------------------------------------------+

	  ESTADO B -- dos o mas, con una raya vertical entre cada dos:

	    +------+------------+|+------------+|+------------+|+--------+
	    |LISTA |    Bob     ||    Avy      ||   Kirinah   ||  ...    |
	    | x5   |  [1] [2]   ||  [1] [2]    ||  [1] [2]    ||         |
	    |      |  [3] [4]   ||  [3] [4]    ||  [3] [4]    ||         |
	    |      | [ macro 1 ]|| [ macro 1 ] || [ macro 1 ] ||         |
	    |      | [ macro 2 ]|| [ macro 2 ] || [ macro 2 ] ||         |
	    +------+------------+|+------------+|+------------+|+--------+

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

	SIN NADA SELECCIONADO EL CENTRO SE VACIA, y eso es la vuelta atras del
	2026-09-05. Hasta hoy caia al PRIMARIO, con el argumento de que una consola
	que se vacia al soltar la seleccion parpadea. En pantalla no se lee asi: se
	lee como que sigue habiendo alguien cogido, porque lo dibujado es
	exactamente lo mismo que cuando lo hay. Un dato correcto puesto donde
	significa otra cosa es el modo de fallo de siempre.

	Se vacia el CENTRO, no la sala: la columna de la izquierda es el grupo y no
	depende de la seleccion. Y el PRIMARIO sigue existiendo -- las teclas de
	habilidad y `/rts skills` caen a el -- lo que deja de hacer es llenar la
	sala el solo.

	=== LOS QUE QUEPAN EN A, CUATRO EN B, Y SON LOS MISMOS ==================

	El estado A ensena **los huecos que quepan a lo ancho** (catorce con la
	barra que sale sola) y el B ensena 2x2. **No son dos configuraciones**: el
	2x2 son los huecos 1..4 de esa misma fila. Con cuatro personajes cogidos no
	caben catorce de cada uno -- serian cincuenta y seis botones -- asi que se
	ensenan los cuatro primeros, que son los que el jugador puso primero.

	Guardar dos listas por personaje habria sido peor de la forma tipica: dos
	sitios donde configurar lo mismo, y el jugador descubriendo en combate que
	el hueco 2 no dice lo mismo segun cuantos lleve cogidos.

	=== LAS MEDIDAS SALEN DE `sim/hall_layout.py` ============================

	No estan elegidas a ojo: el guion reparte la sala para los cinco `grow` y
	los dos estados, y comprueba que nada se sale, nada se solapa y ningun hueco
	sale de tamano absurdo. Cazo dos fallos antes de que existiera este fichero.

	Y SIGUE CAZANDO. Al pasar la fila a "los que quepan" encontro que con `grow`
	5 el TOPE (20) es el que manda y sobran 424 de dibujo -- que es correcto y no
	un fallo, pero la comprobacion de "llena el ancho" lo daba por malo. Sin esa
	distincion escrita, la unica decision deliberada del reparto salia en rojo.

	Lo que no cabe no se recorta: se esconde, y `/rts hall` dice por que. Es la
	misma decision que `SlotGrid` toma en `Bar.lua` -- meter una celda a la
	fuerza deja un boton flotando sobre el arte.

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

-- LA COLUMNA DE PERSONAJES Y EL AIRE QUE LA SEPARA DEL RESTO.
--
-- MEDIDOS SOBRE EL BOCETO RETOCADO del 2026-09-05, no elegidos: la columna sale
-- a 168 px de pantalla y el contenido empieza 216 px despues del borde de la
-- sala, que a la escala de esa captura son 272 y 350 de dibujo.
--
-- LA COLUMNA BAJA DE 440 A 272 Y ESO NO CONTRADICE "los player frames muy
-- pequenos". Lo que se pidio era que se LEYERAN, y lo que no se leia era el
-- texto -- que subio de tamano en la 0.77.0 y ahi se queda. Ensanchar ademas la
-- columna no hizo la letra mas grande: dejo "Secretaria  3 134" (114 px de
-- texto) flotando en 276 px de fila, con la mitad vacia. A 168 px el mismo texto
-- llena su sitio, se lee igual de bien, y los 168 px que sobran se los queda el
-- centro, que es donde hacian falta.
--
-- El tope de la columna lo pone `sim/hall_layout.py`: menos del 20% de la sala
-- con el `grow` que sale solo, o deja de ser una columna y pasa a ser la mitad
-- de la consola.
local LIST_W   = 272
local GUTTER   = 78

local ROW_N    = 5      -- heroe + cuatro companeros
local ROW_GAP  = 4

-- LOS MARCOS DE UNIDAD. El brief pedia "el minimo espacio vertical posible"
-- (§2) y 96 lo cumplia demasiado bien: 54 px de pantalla para un marco con
-- retrato, nombre, vida, poder y mascota. `PRUEBAS-23` lo llamo "muy pequenos"
-- y tiene razon -- el marco de jugador del propio cliente mide 100 px de alto.
--
-- Los tres numeros de aqui salen de MEDIR la raya en el boceto retocado: cae a
-- 154 de dibujo del borde de arriba, que es exactamente `TOP_H + DIV_GAP`. Con
-- los 128+10 de la 0.77.0 el bloque de abajo acababa 25 px antes del suelo de
-- la sala, y ese hueco muerto es lo que hacia que la consola se viera corta por
-- abajo.
local TOP_H    = 140
local DIV_GAP  = 14
local DIV_H    = 2

-- LA SEPARACION ENTRE ICONOS, medida tambien sobre el boceto: 9 px de pantalla
-- contra los 5 de antes. Con la fila llena de lado a lado, 5 px hacian que los
-- diez iconos se leyeran como UNA pieza larga en vez de como diez botones.
local SLOT_GAP = 16

-- EL TOPE DEL ICONO DE HECHIZO. 112 de dibujo son 63 px de pantalla, o sea
-- EXACTAMENTE un boton de accion del cliente -- que suena bien y en pantalla no
-- lo era: al lado de unas filas de grupo de 36 px y unos marcos de 54, el icono
-- era la pieza mas grande de la consola. Reportado como *"los iconos son puto
-- enormes"*.
--
-- 84 son 47 px: se sigue reconociendo el dibujo (que es todo lo que un icono
-- tiene que hacer) y deja de mandar sobre lo que hay alrededor.
local SLOT_MAX = 84
local SLOT_MIN = 40

-- CUANTOS HUECOS DE HECHIZO, Y AQUI CAMBIA LA REGLA.
--
-- Hasta la 0.77.0 eran DIEZ fijos y el tamano se calculaba para que cupieran.
-- El boceto retocado da la vuelta a las dos mitades: **el tamano es fijo y la
-- CUENTA es la que se calcula**, hasta llenar el ancho. En esa captura salen
-- trece; con la barra mas ancha salen mas y con una mas estrecha menos.
--
-- Es lo unico que llena el hueco sin romper otra cosa. Con diez fijos solo hay
-- dos formas de llegar al borde derecho: estirar los huecos (que es lo que se
-- acaba de quitar por "iconos enormes") o estirar la separacion, que a `grow` 3
-- serian 37 px entre iconos de 47 -- una fila de sellos sueltos.
--
-- EL PRECIO, dicho por delante: la cuenta depende del ancho de la barra, asi que
-- estrechar la barra esconde los ultimos huecos. Lo guardado NO se pierde -- la
-- configuracion es por indice y vuelve al ensanchar -- y `/rts hall` imprime
-- siempre cuantos hay. `SPELL_CAP` es el techo de lo que se guarda; `H.slots`
-- es el tope que el jugador puede bajar con `/rts hall slots <n>`.
local SPELL_CAP = 20
local MACRO_N   = 4
local MACRO_H   = 56    -- 31 px de pantalla: cabe el texto a fuente 22 de dibujo

-- LOS MACROS SE SEPARAN MAS QUE LOS ICONOS, y tambien sale del boceto: 18 px
-- contra 9. Un icono se reconoce por el dibujo aunque este pegado al de al lado;
-- una barra de texto pegada a otra barra de texto se lee como una tabla.
local MACRO_GAP = 28

-- Y NINGUNO POR DEBAJO DE ESTO. Con la barra muy estrecha la fila de hechizos
-- se queda en tres o cuatro huecos, y cuatro macros dentro de ese ancho salen a
-- 31 px: no cabe "Sigueme". Se esconden y `/rts hall` dice por que, que es la
-- misma decision que toma `SlotGrid` en `Bar.lua`.
local MACRO_MIN = 110

local VGAP      = 18

-- El estado B, por columna
local HEAD_H      = 26
local HEAD_GAP    = 6
local B_COLS      = 2
local B_ROWS      = 2
local B_MACRO_N   = 2
local B_MACRO_H   = 42

-- LOS TRES QUE BAJAN Y SEPARAN LA COLUMNA DEL ESTADO B, pedidos mirandola:
-- el nombre iba pegado al borde de arriba, el bloque 2x2 pegado a los macros y
-- los dos macros pegados entre si. Cuatro cosas apiladas sin aire se leen como
-- una sola.
--
-- EL PRECIO ESTA EN EL ICONO, y es donde tenia que estar: el alto de la sala es
-- fijo, asi que los 46 de aire salen del cuadrado, que baja de 84 a 78 (de 47 a
-- 44 px). Un icono se reconoce igual; cuatro bloques pegados no se separan solos.
local B_MACRO_GAP = 12
local B_MID_GAP   = 26
local B_TOP_PAD   = 18

-- Cuanto se queda corta la raya vertical por arriba y por abajo. Llegar de
-- borde a borde la convierte en parte del arte; dejarla corta la deja como lo
-- que es, una separacion entre dos cosas.
local VDIV_PAD    = 18

H.SLOT_MIN  = SLOT_MIN
H.MACRO_N   = MACRO_N
H.B_MACRO_N = B_MACRO_N
H.B_SLOTS   = B_COLS * B_ROWS     -- los cuatro del 2x2
H.ROW_N     = ROW_N
H.MAX_SPELLS = SPELL_CAP
H.SPELL_CAP = SPELL_CAP

-- El TOPE que el jugador pone. Por defecto el maximo, o sea "los que quepan".
H.slots = SPELL_CAP

-- Y los que de verdad se dibujan, que es lo que mira el contenido. Lo calcula
-- `Recompute`; nunca se escribe a mano.
H.shown = 0

--- Los sitios donde se apunta el contenido --------------------------------

local host                -- el marco de la sala, de Bar
local frames = {}         -- key -> Frame
local divider             -- la raya bajo los marcos
local vdivs  = {}         -- las rayas verticales entre columnas (estado B)
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

-- De quien es la fila de hechizos en el estado A: el UNICO seleccionado, y nil
-- si no hay ninguno. Sin dueno no hay marcos, ni huecos, ni macros, ni raya --
-- `Recompute` no produce esas areas y `Layout` esconde sus marcos, que es el
-- mismo camino por el que ya desaparecen al pasar al estado B.
--
-- NO CAE AL PRIMARIO, y ese es el cambio. `GetPrimary` se queda para las teclas
-- y para `/rts skills`, que preguntan "de quien, si no lo dices" -- una
-- pregunta distinta de "quien esta cogido ahora mismo", que es la que contesta
-- la sala.
function H:Subject()
	return ns.Selection:Single()
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
	-- `shown` Y `spellRowW` TAMBIEN. Se escribian solo mas abajo, asi que una
	-- salida temprana los dejaba con los del reparto ANTERIOR: trece huecos
	-- declarados sobre un area que ya no existe. Hoy no lo pinta nadie porque
	-- el marco esta escondido, y ese "hoy" es justo lo que envejece mal.
	H.shown, H.spellRowW = 0, 0
	if w <= 0 or h <= 0 then return end

	Rect("list", 0, 0, LIST_W, h)

	-- EL MISMO AIRE A LOS DOS LADOS. Hasta la 0.78.0 la zona llegaba al borde
	-- del arte y, con la fila llena, el ultimo hueco y el ultimo macro acababan
	-- pegados al marco -- se veia como recortado, no como ajustado.
	--
	-- Se le quita `GUTTER` por la derecha, que es literalmente lo que se pidio:
	-- *"igual del que hay entre las barras pequenas y la seccion de hechizos"*.
	-- Y sale un numero bonito de regalo: con la barra que sale sola la fila pasa
	-- a ser de TRECE huecos, que es exactamente lo que tenia el boceto retocado.
	local cx = LIST_W + GUTTER
	local cw = w - cx - GUTTER
	Rect("content", cx, 0, cw, h)

	-- SIN NADIE COGIDO NO SE PRODUCE NI UN AREA DEL CENTRO, y con eso se vacia
	-- solo: `Layout` esconde todo marco que este reparto no haya producido. No
	-- hay que apagar nada a mano, que es lo que haria falta si cada panel
	-- decidiera por su cuenta cuando esconderse -- y entonces el que se olvide
	-- se queda dibujado encima de nada.
	if H:State() == "A" and not H:Subject() then return end

	if H:State() == "B" then
		-- TODA la zona derecha son columnas. No hay banda de marcos: con varios
		-- seleccionados no hay un "el seleccionado" del que ensenar el marco, y
		-- cinco marcos no caben ni dirian nada que la columna izquierda no diga.
		local n = #H:Columns()
		local colw = (n > 0) and math.floor((cw - GUTTER * (n - 1)) / n) or 0

		-- EL ALTO MANDA CASI SIEMPRE y por eso se calcula primero: el ancho solo
		-- puede empeorarlo. Con la columna a 385 caben cuadrados de 188, pero el
		-- alto de la sala solo da para 103.
		local room = h - B_TOP_PAD - HEAD_H - HEAD_GAP - B_MID_GAP
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
			-- UNA RAYA VERTICAL ENTRE CADA DOS SELECCIONADOS, en el centro del
			-- hueco que ya los separaba. Sin ella, cinco columnas de botones son
			-- una rejilla de veinte y hay que contar para saber donde acaba uno
			-- y empieza el siguiente; con ella son cinco fichas.
			--
			-- Va DENTRO del hueco y no pegada a una columna a proposito: si se
			-- ancla a un lado, el ojo la lee como el borde de esa columna y la
			-- asimetria se nota.
			if i > 1 then
				Rect("vdiv" .. (i - 1),
				     cx + (i - 1) * colw + (i - 1) * GUTTER - math.floor(GUTTER / 2) - 1,
				     VDIV_PAD, 2, h - VDIV_PAD * 2)
			end
		end
		return
	end

	Rect("top", cx, 0, cw, TOP_H)

	local by = TOP_H + DIV_GAP + DIV_H + DIV_GAP
	local bh = h - by

	-- EL LADO ES FIJO Y LA CUENTA SE CALCULA, que es la vuelta que da el
	-- boceto retocado. El alto sigue mandando cuando aprieta: la fila de
	-- hechizos y la de macros comparten banda.
	local side = SLOT_MAX
	local room = bh - VGAP - MACRO_H
	if side > room then side = room end
	if side > cw then side = cw end
	if side < SLOT_MIN then side = 0 end

	local n = 0
	if side > 0 then
		-- `+ SLOT_GAP` porque el ultimo hueco no lleva separacion detras.
		n = math.floor((cw + SLOT_GAP) / (side + SLOT_GAP))
		if n > H.slots then n = H.slots end
		if n < 1 then side, n = 0, 0 end
	end

	H.slotSide = side
	H.shown = n
	local rowW = (side > 0) and (side * n + SLOT_GAP * (n - 1)) or 0
	H.spellRowW = rowW

	-- LOS MACROS SE ALINEAN CON LA FILA DE HECHIZOS, y ese es todo su ancho.
	-- Derivarlo en vez de escribirlo es lo que hace que cambiar el numero de
	-- huecos no descuadre la fila de abajo -- la misma regla que `Bar.lua`
	-- aplica a las posiciones de sus piezas: toda posicion se deriva, ninguna
	-- se escribe.
	H.macroW = (rowW > 0) and math.floor((rowW - MACRO_GAP * (MACRO_N - 1)) / MACRO_N) or 0
	if H.macroW < MACRO_MIN then H.macroW = 0 end
	local macroTotal = (H.macroW > 0) and (H.macroW * MACRO_N + MACRO_GAP * (MACRO_N - 1)) or 0

	-- TODO PEGADO A LA IZQUIERDA, que es lo que cambia respecto de la 0.77.0.
	--
	-- Aquella version centraba el bloque porque la fila de diez dejaba 846 de
	-- dibujo vacios a un lado. Ahora la fila llena el ancho, asi que no hay nada
	-- que repartir: el borde izquierdo de los marcos, el de la raya, el de la
	-- fila de hechizos y el de la de macros son EL MISMO, y esa columna de
	-- bordes alineados es lo que hace que la zona se lea como un bloque.
	--
	-- Centrar y alinear a la izquierda daban lo mismo mientras el bloque no
	-- llenaba; en cuanto llena, centrar solo puede descuadrarlo.
	Rect("spells", cx, by, rowW, side)
	Rect("macros", cx, by + (side > 0 and (side + VGAP) or 0), macroTotal, MACRO_H)

	-- LA RAYA MIDE LO QUE EL BLOQUE, no lo que la zona. Tambien del boceto: alli
	-- empieza y acaba exactamente donde la fila de hechizos. Una raya que
	-- sobresale por la derecha de todo lo que separa se lee como un borde suelto.
	--
	-- Y SIN BLOQUE NO HAY RAYA. Se declara aqui y no arriba a proposito: con la
	-- barra tan estrecha que no cabe ni un hueco, una raya suelta separaria los
	-- marcos de nada.
	local rule = math.max(rowW, macroTotal)
	if rule > 0 then
		Rect("div", cx, TOP_H + DIV_GAP, rule, DIV_H)
	end
end

--- Lo que usan los modulos de contenido -----------------------------------

function H:Get(key)
	return rects[key]
end

-- Colocar UN marco donde diga el reparto, o esconderlo si el reparto no lo
-- produjo. Sale de `Layout` para que `Host` pueda llamarlo tambien; ver ahi por
-- que hace falta.
local function Place(key, f)
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

-- El marco de un area. Se crean bajo demanda y no se destruyen -- pasar del
-- estado B al A esconde las columnas en vez de borrarlas, para que volver no
-- cree nada. Misma politica que las texturas repetidas de `Bar`.
--
-- SE COLOCA AL CREARLO, Y ESO ERA UN FALLO DE VERDAD. `Layout` reparte sobre
-- los marcos QUE YA EXISTEN y avisa DESPUES; los de columna (`col1`..) solo los
-- pide `Cast:LayoutB`, que corre dentro de ese aviso. O sea que la PRIMERA vez
-- que se cogian varios, sus marcos nacian de 0x0 y sin anclar, con el reparto
-- ya pasado: los botones colgaban de un marco sin sitio y no salia ni una
-- columna. A la segunda ya existian y salia todo bien.
--
-- El sintoma era exactamente ese -- "la primera vez no se cargan; si cancelo y
-- selecciono de nuevo, entonces si" -- y no se parecia a su causa: parece un
-- refresco que falta, cuando lo que faltaba era el propio marco.
function H:Host(key)
	if not host then return nil end
	local f = frames[key]
	if not f then
		f = CreateFrame("Frame", "RTSHall_" .. key, host)
		f:SetFrameLevel(host:GetFrameLevel() + 2)
		f:EnableMouse(false)
		frames[key] = f
		Place(key, f)
	end
	return f
end

--- Las celdas, en coordenadas de SU marco ---------------------------------

-- La fila de hechizos del estado A.
function H:SpellCells()
	local out = {}
	local side = self.slotSide or 0
	if side <= 0 then return out end
	for i = 1, (self.shown or 0) do
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
	local y0 = B_TOP_PAD + HEAD_H + HEAD_GAP
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
	local y0 = B_TOP_PAD + HEAD_H + HEAD_GAP + side * B_ROWS
	         + SLOT_GAP * (B_ROWS - 1) + B_MID_GAP
	for i = 1, B_MACRO_N do
		out[i] = { x = 0, y = y0 + (i - 1) * (B_MACRO_H + B_MACRO_GAP),
		           w = self.colW or 0, h = B_MACRO_H }
	end
	return out
end

function H:HeadHeight() return HEAD_H end
function H:HeadTop()    return B_TOP_PAD end

--- Distribuir -------------------------------------------------------------

function H:Layout()
	if not host then return end
	Recompute()

	-- Los marcos se colocan aqui y su contenido se coloca en el aviso. Un area
	-- que este reparto no produjo se ESCONDE en vez de quedarse donde estaba:
	-- pasar de B a A dejaria cinco columnas dibujadas encima de los marcos.
	for key, f in pairs(frames) do
		Place(key, f)
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

	-- Y LAS VERTICALES DEL ESTADO B. Se crean bajo demanda y se esconden las que
	-- sobren, igual que los marcos de area: pasar de cinco columnas a dos no
	-- puede dejar tres rayas dibujadas sobre nada.
	for i = 1, (H.ROW_N - 1) do
		local r = rects["vdiv" .. i]
		local t = vdivs[i]
		if r then
			if not t then
				t = host:CreateTexture(nil, "OVERLAY")
				t:SetTexture(0.55, 0.58, 0.66, 0.45)
				vdivs[i] = t
			end
			t:SetWidth(r.w)
			t:SetHeight(r.h)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", host, "TOPLEFT", r.x, -r.y)
			t:Show()
		elseif t then
			t:Hide()
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
		-- -- si no, cada click en un bot moveria veinte botones para dejarlos
		-- donde estaban.
		ns.Selection:Subscribe(function()
			local st = H:State()
			local n = (st == "B") and #H:Columns() or 0
			local subj = H:Subject()
			-- HABER O NO HABER DUENO CAMBIA EL REPARTO, no solo el contenido:
			-- sin nadie cogido el centro no produce areas. Sin esta tercera
			-- comparacion, soltar la seleccion se quedaba en un aviso y las
			-- areas seguian puestas con lo de antes dibujado dentro -- que es
			-- justo el sintoma que se reporto.
			local has = (subj ~= nil)
			if st ~= H.lastState or n ~= H.lastCols or has ~= H.lastHas then
				H.lastState, H.lastCols, H.lastHas = st, n, has
				H.lastSubject = subj
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
	if not n or n < 1 or n > SPELL_CAP then
		ns.Print(("|cffff8800sala:|r los huecos van de 1 a %d. Es un TOPE: si " ..
		          "caben menos, salen menos."):format(SPELL_CAP))
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
	-- Y AQUI EL RANGO CAMBIO DE SIGNIFICADO DOS VECES: el 2026-09-04 el tope
	-- paso de 6 a 10, y el 09-05 la clave dejo de significar "cuantos hay" para
	-- significar "como mucho cuantos". Un valor guardado sigue siendo valido en
	-- rango, pero **un 10 guardado ahora TOPA una fila que podria ensenar
	-- catorce** -- y eso no da error, solo deja la fila corta sin motivo
	-- visible. Por eso un valor que venga del tope viejo se descarta: quien lo
	-- quiera lo vuelve a poner, y quien no se entere ve la fila llena.
	local n = tonumber(db.slots)
	if n == 10 or n == 6 then
		ns.Print(("|cff888888sala: descartado slots=%d, que era el tope viejo; " ..
		          "ahora la fila llena el ancho.|r"):format(n))
		db.slots = nil
	elseif n and n >= 1 and n <= SPELL_CAP then
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

	if not self:Subject() then
		ns.Print("  |cff888888nadie cogido: el centro esta vacio a proposito. " ..
		         "Pincha a uno en la lista.|r")
		return
	end

	ns.Print(("  de |cff33ccff%s|r: %d huecos de %d (tope %d), fila de %d"):format(
		tostring(self:Subject()), self.shown or 0, self.slotSide or 0,
		self.slots, self.spellRowW or 0))
	if (self.macroW or 0) > 0 then
		ns.Print(("  %d macros de %dx%d"):format(MACRO_N, self.macroW, self.macroH or 0))
	else
		ns.Print(("  |cffff8800los macros no caben|r: %d de ancho para %d que " ..
		          "necesitan. Ensancha con |cffffff00/rts bar grow|r."):format(
			math.floor(((self.spellRowW or 0) - MACRO_GAP * (MACRO_N - 1)) / MACRO_N),
			MACRO_MIN))
	end
	if (self.shown or 0) == 0 then
		ns.Print("  |cffff8800no cabe ni un hueco|r: ensancha con " ..
		         "|cffffff00/rts bar grow|r.")
	elseif (self.slots or 0) < SPELL_CAP and self.shown == self.slots then
		ns.Print(("  |cff888888el tope los esta limitando; sube con " ..
		          "/rts hall slots %d.|r"):format(SPELL_CAP))
	end
end

-- SE APUNTA SOLO en la barra, igual que `Panel` y `Rails`. `Bar.lua` no nombra
-- a ninguno desde 2026-09-02 y esto no lo cambia.
ns.Bar:Register(H)
