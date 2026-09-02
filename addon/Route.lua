--[[
	Route.lua -- rutas de varios puntos, con shift + click derecho.

	El gesto de RTS que faltaba. Click derecho manda a la seleccion a un sitio;
	SHIFT + click derecho ENCADENA otro punto detras, y otro, y otro. Los puntos
	se ven en el suelo unidos por una linea de puntos, y las unidades los
	recorren en orden -- uno detras de otro, no todos a la vez.

	Con UNA sola unidad seleccionada, los puntos y la linea salen del COLOR DE SU
	CLASE. Con varias, en verde. Es lo que se pidio y ademas es informacion: de
	un vistazo se sabe de quien es cada camino cuando hay dos rutas puestas.

	=== por que se dibuja en la interfaz y no en el mundo ===================

	Se penso primero en pedirle al mundo que dibujase algo -- un objeto, un
	efecto de hechizo -- y es un callejon: pintar en el mundo desde el cliente
	necesita un SpellVisual que hay que adivinar, y desde el servidor un
	DynamicObject con un aura que lo mantenga vivo. Dos incognitas para algo que
	un puñado de texturas proyectadas resuelve.

	Y AQUI SI VALE PROYECTAR, que es lo contrario de lo que se decidio para los
	circulos de seleccion (etapa 5e). La diferencia es a que se pega el dibujo:
	un circulo bajo los pies de un modelo tiene que estar EXACTO o se lee como
	roto, porque el ojo lo compara con el modelo cada frame. Un punto en el suelo
	no se compara con nada -- no hay nada debajo -- asi que medio pixel de deriva
	al girar la camara no se ve. El precio conocido es que no tiene profundidad y
	se dibuja sobre la colina que deberia taparlo; a cambio se sabe siempre donde
	esta la ruta, que es justo para lo que sirve.

	=== como avanzan ========================================================

	No se le manda al bot la ruta entera: playerbots no tiene un verbo de ruta.
	Se le manda UN destino, se le mira, y cuando llega se le manda el siguiente.
	La llegada se comprueba contra las posiciones que publica rts_core, que es la
	unica fuente de coordenadas que hay en el cliente.

	CADA UNIDAD LLEVA SU PROPIO INDICE. La primera version tenia uno solo por
	ruta y no avanzaba hasta que llegaban todos; en juego eso se veia como
	lentitud, porque el grupo se paraba en cada punto a esperar al ultimo. Ahora
	el que llega sigue.

	Y "LLEGAR" NO ES TOCAR EL PUNTO: es estar a `arrive` yardas o haber hecho el
	95% del tramo, lo que sea mas generoso. Un radio fijo es demasiado exigente
	en un tramo largo -- los ultimos metros el bot los pasa frenando, rodeando
	una piedra y recolocandose, y eso es tiempo parado que se siente como
	desobediencia.

	CADA TRAMO LLEVA ADEMAS SU PROPIO PLAZO. Un bot se puede quedar encallado en
	una esquina, y sin plazo la ruta se quedaria ahi para siempre y se leeria
	como "la ruta no funciona". Pasado el plazo se pasa al siguiente punto
	igual: es mejor una ruta que se salta un tramo que una que se para.

	SIN rts_core NO HAY RUTAS, y se dice. La llegada necesita coordenadas y el
	dibujo necesita proyeccion; sin el DLL no hay ni una cosa ni la otra, y una
	ruta que no avanza sola es peor que no tenerla.
]]

local ADDON, ns = ...

local R = {}
ns.Route = R

R.enabled = true

-- Todo esto es TACTO y el tacto no se deduce: se mira y se ajusta. Por eso son
-- ajustables en vivo con `/rts route <clave> <valor>`.
R.cfg = {
	arrive  = 3.0,    -- yardas: a esta distancia del punto se da por llegado
	near    = 0.05,   -- ...o cuando queda esta fraccion del tramo ("al 95%")
	timeout = 40,     -- segundos como mucho por tramo antes de pasar al siguiente
	maxleg  = 100,    -- yardas: mas largo que esto se parte en trozos (ver abajo)
	stall   = 5,      -- segundos parado sin llegar antes de repetir la orden
	retries = 3,      -- ...y cuantas veces se repite antes de rendirse y pasar
	ring    = 2.20,   -- yardas de ancho del marcador de cada punto
	minpx   = 10,     -- pixeles minimos del marcador (de lejos no desaparece)
	maxpx   = 200,    -- ...y maximos (de cerca no llena la pantalla)
	num     = 15,     -- cuerpo del numero, en unidades de UIParent
}

-- EL TRAMO LARGO NO SE PUEDE MANDAR DE UNA, y esto es lo que hacia que un bot
-- "se olvidara de que iba caminando" con la ruta todavia pintada.
--
-- `MoveToPositionAction::isUseful()` de playerbots es, literalmente:
--
--     pos.isSet() && distance > followDistance && distance < reactDistance
--
-- y `AiPlayerbot.ReactDistance` vale 150. O sea que un ancla a mas de 150
-- yardas NO ES UTIL para la IA y el bot no arranca siquiera: se queda quieto,
-- la ruta sigue dibujada, y a los 40 s el plazo la pasa al punto siguiente --
-- que suele estar igual de lejos. Un bot que no se mueve nunca.
--
-- El camino viejo por chat SI lo sabia (`REACT_LIMIT = 140` en
-- `Orders:MoveUnitToViaChat`, con un `go X;Y;Z` explicito para cerrar el
-- hueco). Al mover la orden al servidor esa mitad se quedo atras. Es el mismo
-- patron que el botin: media funcion que sobrevive en el camino que ya no se
-- usa.
--
-- Aqui se arregla sin tocar playerbots: si el destino esta a mas de `maxleg`,
-- se apunta a un punto INTERMEDIO sobre la recta, y al llegar se vuelve a
-- apuntar. El indice del punto de ruta no avanza hasta pisar el punto de
-- verdad. Recalcular el intermedio desde la posicion ACTUAL en cada trozo tiene
-- un segundo efecto util: si al bot lo apartan de la ruta, el trozo siguiente
-- sale ya desde donde esta.

-- Verde cuando la ruta es de varios. Con uno solo se usa el color de su clase.
local MULTI = { r = 0.30, g = 1.00, b = 0.45 }

-- Una ruta:
--   units = { nombre... }          quienes la recorren
--   pts   = { {x,y,z}... }         los puntos, en orden
--   off   = { [nombre] = {dx,dy} } su hueco fijo en la formacion
--   u     = { [nombre] = { idx, at, tx, ty, d0 } }   por donde va cada una
--   col   = { r, g, b }            color de la ruta
local routes = {}
local byUnit = {}

-- CADA PUNTO NACE CON UN NUMERO PROPIO, y no es lo mismo que su sitio en la
-- ruta. El marcador de suelo del servidor se identifica por ese numero, asi que
-- si fuera "el tercero de los que quedan" pisar el primer punto renumeraria
-- todos los demas y habria que recolocar la ruta entera en cada llegada.
local nextId = 0
local function NewPoint(x, y, z)
	nextId = nextId + 1
	return { x, y, z, id = nextId }
end

--- Posiciones --------------------------------------------------------------

-- Donde esta esa unidad AHORA mismo, en coordenadas de mundo.
--
-- Se pregunta primero al mapa de guids que publica el DLL, que vale para
-- cualquiera, y solo si ahi no esta se tira del canal del jugador. Al reves
-- seria mas corto y peor: con la camara poseida no esta claro a que apunta
-- RTS_P*, y el guid nunca miente sobre de quien es la posicion.
-- Lo que contesto el servidor a la ultima peticion `POS`. Ver `R:OnPositions`.
local server = {}

local function PosOf(name)
	local unit = ns.Selection:UnitFor(name)
	local guid = unit and UnitGUID(unit)
	if guid then
		local x, y, z = ns.Markers:UnitWorld(guid)
		if x then return x, y, z end
	end
	if name == UnitName("player") then
		local x, y, z = ns.Bridge:GetPlayerWorldPosition()
		if x then return x, y, z end
	end
	-- EL SERVIDOR ES EL RESPALDO, y es el que salva el caso que importa: un bot
	-- que se ha alejado lo suficiente para salir de la burbuja de visibilidad
	-- del cliente deja de estar en el mapa que publica el DLL, y sin posicion
	-- no hay forma de saber si ha llegado. La ruta avanzaba entonces solo por
	-- su plazo de 40 s, que se lee como que el bot se ha parado.
	local p = server[name]
	if p then return p[1], p[2], p[3] end
	return nil
end

-- "nombre,x,y,z;nombre,x,y,z". Reemplaza la tabla entera: una posicion vieja es
-- peor que ninguna, porque parece buena.
function R:OnPositions(list)
	local nuevo = {}
	for entry in list:gmatch("[^;]+") do
		local name, x, y, z = entry:match("^(.-),(-?[%d%.]+),(-?[%d%.]+),(-?[%d%.]+)$")
		if name then
			nuevo[name] = { tonumber(x), tonumber(y), tonumber(z) }
		end
	end
	server = nuevo
end

local function Dist2D(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

--- Color -------------------------------------------------------------------

local function ColourFor(units)
	if #units == 1 then
		local unit = ns.Selection:UnitFor(units[1])
		if unit then
			local c = ns.W:ClassColor(unit)
			return { r = c.r, g = c.g, b = c.b }
		end
	end
	return MULTI
end

--- Limpiar -----------------------------------------------------------------

local function DropRoute(route)
	for _, name in ipairs(route.units) do
		if byUnit[name] == route then byUnit[name] = nil end
	end
	for i = #routes, 1, -1 do
		if routes[i] == route then tremove(routes, i) end
	end
end

-- Quitar a estas unidades de cualquier ruta en la que estuvieran. Una ruta que
-- se queda sin unidades desaparece: la alternativa seria dejar dibujado un
-- camino que ya no recorre nadie.
function R:ClearFor(units)
	for _, name in ipairs(units) do
		local route = byUnit[name]
		if route then
			for i = #route.units, 1, -1 do
				if route.units[i] == name then tremove(route.units, i) end
			end
			byUnit[name] = nil
			if route.u then route.u[name] = nil end
			if #route.units == 0 then DropRoute(route) end
		end
	end
end

function R:ClearAll()
	routes = {}
	byUnit = {}
	if ns.Marks then ns.Marks:ClearAll() end
end

-- Por donde va la ruta: el punto al que apunta la unidad MENOS avanzada. Es lo
-- que se dibuja y lo que se cuenta, porque un punto sigue siendo parte del
-- camino mientras le quede alguien por pisarlo.
local function MinIdx(route)
	local m
	for _, name in ipairs(route.units) do
		local u = route.u[name]
		if u and (not m or u.idx < m) then m = u.idx end
	end
	return m or 1
end

function R:Count()
	local pts = 0
	for _, r in ipairs(routes) do pts = pts + (#r.pts - MinIdx(r) + 1) end
	return #routes, pts
end

--- Mandar el tramo actual --------------------------------------------------
--
-- CADA UNIDAD VA A SU PROPIO PUNTO Y A SU PROPIO RITMO. Antes la ruta tenia UN
-- indice y no avanzaba hasta que llegaban todos, y en juego eso se notaba como
-- lentitud: el grupo se paraba en cada punto a esperar al ultimo (PRUEBAS-11
-- F1). Ahora el indice es por unidad y el que llega sigue.
--
-- El HUECO en la formacion se calcula UNA vez, al crear la ruta, y se guarda.
-- Recalcularlo en cada tramo cambiaria de sitio a cada bot en cada punto -- la
-- formacion giraria sola -- y ademas haria que dos unidades que avanzan en
-- tramos distintos se repartieran contra listas distintas.
--
-- `mover` es la lista de las que acaban de cambiar de punto, para que las que
-- coinciden en el mismo tick salgan en UN paquete.
local function Issue(route, mover)
	local playerName = UnitName("player")
	local batch = {}

	for _, name in ipairs(mover) do
		local u = route.u[name]
		local p = u and route.pts[u.idx]
		if p then
			local o = route.off[name] or { 0, 0 }
			-- El destino de VERDAD de este punto de ruta, con su hueco.
			local fx, fy, fz = p[1] + o[1], p[2] + o[2], p[3]

			-- Y a donde se le manda AHORA, que puede ser un punto intermedio si
			-- el de verdad queda fuera del alcance util de la IA.
			local tx, ty, tz = fx, fy, fz
			local cx, cy, cz = PosOf(name)
			local d = cx and Dist2D(cx, cy, fx, fy) or nil

			if d and d > R.cfg.maxleg then
				local f = R.cfg.maxleg / d
				tx = cx + (fx - cx) * f
				ty = cy + (fy - cy) * f
				tz = (cz or fz) + (fz - (cz or fz)) * f
			end

			u.at = GetTime()

			-- EL RELOJ Y EL CONTADOR SON DEL PUNTO DE RUTA, NO DEL ENVIO, y
			-- distinguirlo cuesta un campo mas -- `arm`, el indice para el que
			-- ya se armaron -- porque `sent ~= idx` NO sirve: es cierto tanto
			-- para un punto nuevo como para un reenvio.
			--
			-- Sin esto, cada reenvio los ponia a cero, con lo cual ni el plazo
			-- ni el tope de reintentos llegaban NUNCA: un bot de verdad
			-- atascado repetia su orden para siempre y la ruta no terminaba.
			-- Es el fallo que la simulacion encontro despues de arreglar el
			-- anterior, o sea que lo introdujo el propio arreglo.
			if u.arm ~= u.idx then
				u.since = u.at
				u.stalls = 0
				u.arm = u.idx
			end

			u.fx, u.fy = fx, fy         -- el punto de ruta
			u.tx, u.ty = tx, ty         -- el trozo que se acaba de mandar
			u.partial = (tx ~= fx or ty ~= fy)
			-- El punto que de verdad se le ha ordenado. Es lo que distingue
			-- "va hacia el punto 3" de "su indice dice 3 pero nadie se lo ha
			-- dicho"; ver el comentario de Advance.
			u.sent = u.idx
			-- El largo del trozo, para poder decir "ya va por el 95%". Se mide
			-- al MANDARLO, que es el unico momento en que se sabe de donde sale.
			u.d0 = cx and Dist2D(cx, cy, tx, ty) or nil
			-- Donde estaba al mandarlo, para detectar que no se ha movido.
			u.px, u.py, u.pat = cx, cy, GetTime()

			if name == playerName then
				ns.Orders:MoveSelfTo(tx, ty, tz)
			else
				tinsert(batch, { name, tx, ty, tz })
			end
		end
	end

	if #batch > 0 then ns.Orders:MoveBatch(batch) end
	return true
end

-- El hueco de cada unidad en la formacion, decidido una vez por ruta.
local function BuildOffsets(route, x, y)
	local offs = ns.Orders:SpreadOffsets(#route.units, ns.Orders:FacingTo(x, y))
	route.off = {}
	for i, name in ipairs(route.units) do
		route.off[name] = offs[i] or { 0, 0 }
	end
end

-- Arrancar el estado por unidad en el punto 1. `issued` = true cuando la orden
-- de ese primer tramo la manda OTRO (el click derecho normal, via Orders:Click):
-- entonces aqui solo se anota a donde va, para poder detectar la llegada.
local function StartUnits(route, issued)
	local now = GetTime()
	route.u = {}
	for _, name in ipairs(route.units) do
		local p = route.pts[1]
		local o = route.off[name] or { 0, 0 }
		local tx, ty = p[1] + o[1], p[2] + o[2]
		local cx, cy = PosOf(name)
		route.u[name] = {
			idx = 1, at = now, since = now, stalls = 0, arm = 1,
			tx = tx, ty = ty, fx = tx, fy = ty,
			partial = false,
			-- `sent = 1` cuando la orden la manda otro: para el avance es
			-- exactamente lo mismo que si la hubieramos mandado aqui.
			--
			-- SALVO SI ESE PUNTO ESTA DEMASIADO LEJOS. El click derecho normal
			-- manda el destino ENTERO (lo hace Orders:Click, que no sabe de
			-- troceo), asi que a mas de `maxleg` la IA lo ignoraria. Dejando
			-- `sent` a nil, el siguiente tick lo manda ya troceado -- 0,2 s en
			-- vez de los 5 que tardaria en notarlo el detector de bot parado.
			sent = (issued and not (cx and Dist2D(cx, cy, tx, ty) > R.cfg.maxleg))
			       and 1 or nil,
			d0 = cx and Dist2D(cx, cy, tx, ty) or nil,
			px = cx, py = cy, pat = now,
		}
	end
	if not issued then Issue(route, route.units) end
end

--- Crear y encadenar -------------------------------------------------------

-- Las unidades de la seleccion, como lista propia. Copia y no la tabla viva:
-- la seleccion cambia y la ruta tiene que seguir siendo de quien la recibio.
local function SelectedUnits()
	local out = {}
	for _, n in ipairs(ns.Selection:Get()) do tinsert(out, n) end
	return out
end

-- Click derecho normal: una ruta nueva de UN punto. Se registra aunque solo
-- tenga un destino porque es lo que permite que el siguiente shift+click
-- encadene desde el -- sin esto, "mandarlos y luego anadir puntos mientras van"
-- no seria posible.
--
-- NO MANDA LA ORDEN. El click derecho normal ya la manda por su camino de
-- siempre, que ademas pasa por el servidor para que decida si era atacar o
-- lootear. Aqui solo se anota el destino.
function R:Set(x, y, z)
	local units = SelectedUnits()
	if #units == 0 then return false end
	self:ClearFor(units)
	if not self.enabled then return false end

	local route = { units = units, pts = { NewPoint(x, y, z) }, col = ColourFor(units) }
	BuildOffsets(route, x, y)
	StartUnits(route, true)     -- la orden del primer tramo ya va por Orders:Click
	tinsert(routes, route)
	for _, n in ipairs(units) do byUnit[n] = route end
	-- Devuelve el NUMERO del punto, no un simple si/no: quien llama lo necesita
	-- para pedirle al servidor el suelo de verdad de ESE punto y corregirlo
	-- cuando conteste. Sigue siendo un valor cierto, asi que los sitios que solo
	-- miran si salio bien no cambian.
	return route.pts[1].id
end

-- Shift + click derecho: un punto mas al final. Si no habia ruta, esto ES la
-- ruta y ademas arranca -- de otra forma el primer shift+click no haria nada y
-- habria que acordarse de dar uno normal antes.
function R:Add(x, y, z)
	if not self.enabled then return false end

	local units = SelectedUnits()
	if #units == 0 then
		ns.Print("Nada seleccionado: el punto no seria de nadie.")
		return false
	end

	-- Solo se encadena sobre una ruta que sea EXACTAMENTE de esta seleccion. Si
	-- has cambiado de unidades, encadenar sobre la ruta anterior las mandaria a
	-- todas a un sitio que no pediste.
	local route = byUnit[units[1]]
	if route then
		local same = #route.units == #units
		if same then
			for _, n in ipairs(units) do
				if byUnit[n] ~= route then same = false break end
			end
		end
		if not same then route = nil end
	end

	if not route then
		self:Set(x, y, z)
		local nueva = byUnit[units[1]]
		if nueva then
			-- Aqui SI hay que mandarla: este camino no viene de un click derecho
			-- normal, asi que nadie mas la ha mandado.
			Issue(nueva, nueva.units)
			ns.Flare:Show(x, y, z, "move")
			ns.Print(("Ruta: |cffffff00punto 1|r (%d unidad%s)")
				:format(#units, #units == 1 and "" or "es"))
		end
		return nueva and nueva.pts[1] and nueva.pts[1].id or true
	end

	local pt = NewPoint(x, y, z)
	tinsert(route.pts, pt)
	route.col = ColourFor(route.units)
	ns.Print(("Ruta: |cffffff00punto %d|r"):format(#route.pts))
	return pt.id
end

-- EL SERVIDOR HA DICHO DONDE ESTA EL SUELO DE VERDAD DE ESE PUNTO.
--
-- Llega un instante despues del click, asi que el aro se dibuja primero en la
-- estimacion y salta aqui. Es feo de describir y no se nota en juego: en llano
-- las dos cuentas coinciden, y donde no coinciden es justo donde la estimacion
-- estaba mal.
--
-- Se corrige el punto Y se vuelve a mandar el tramo de quien fuera hacia el:
-- un bot andando hacia el sitio equivocado no se arregla solo por mover el
-- dibujo.
function R:Correct(id, x, y, z, reissue)
	if not id or id == 0 then return false end

	for _, route in ipairs(routes) do
		for i, p in ipairs(route.pts) do
			if p.id == id then
				local dx, dy, dz = x - p[1], y - p[2], z - p[3]
				if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 and math.abs(dz) < 0.05 then
					return true      -- la estimacion ya era buena
				end
				p[1], p[2], p[3] = x, y, z

				-- La marca del mundo de ese punto, si la hay, se rehace: su
				-- posicion la fija el servidor al colocarla y no se mueve sola.
				if ns.Marks then ns.Marks:Redo(id) end

				-- Y quien fuera hacia el se entera -- salvo que la orden ya
				-- saliera corregida, que es el caso del click derecho normal.
				-- Los que van a otro punto no se tocan: reordenar a todos por
				-- esto seria pararlos.
				if not reissue then return true end

				local again = {}
				for _, n in ipairs(route.units) do
					local u = route.u and route.u[n]
					if u and u.idx == i then
						u.sent = nil          -- que el siguiente tick lo remande
						u.d0 = nil
						tinsert(again, n)
					end
				end
				if #again > 0 then Issue(route, again) end
				return true
			end
		end
	end
	return false
end

--- Avance ------------------------------------------------------------------

-- Ha llegado esta unidad a su punto?
--
-- DOS FORMAS DE LLEGAR, Y LA SEGUNDA ES LA QUE PIDIO F1. La primera es la
-- obvia: estar a menos de `arrive` yardas. La segunda es "ya va por el 95% del
-- tramo" -- `near` de la distancia que habia al salir -- y existe porque un
-- radio fijo es demasiado exigente en un tramo largo: el bot pasa los ultimos
-- metros frenando, rodeando una piedra y recolocandose, y todo eso es tiempo
-- parado que en un RTS se siente como que no obedece.
--
-- Se usa el MAYOR de los dos umbrales, no el menor: en un tramo corto manda
-- `arrive` (el 5% de cuatro yardas no seria nada) y en uno largo manda el
-- porcentaje. Cada uno cubre el caso en el que el otro no sirve.
local function Advance()
	local now = GetTime()

	for i = #routes, 1, -1 do
		local route = routes[i]

		-- Quien ya no esta en el grupo no puede llegar a ningun sitio.
		for k = #route.units, 1, -1 do
			local n = route.units[k]
			if n ~= UnitName("player") and not ns.Selection:UnitFor(n) then
				byUnit[n] = nil
				route.u[n] = nil
				tremove(route.units, k)
			end
		end

		if #route.units == 0 or #route.pts == 0 then
			DropRoute(route)
		else
			-- Las que hay que mandar en este tick, para que salgan en un paquete.
			local mover, vivas = {}, 0

			for _, name in ipairs(route.units) do
				local u = route.u[name]
				if u then
					-- SOLO SE COMPRUEBA LA LLEGADA DE UN TRAMO QUE SE HAYA
					-- MANDADO. `u.sent` es el punto que de verdad se le ordeno,
					-- y sin esa condicion habia dos fallos, los dos por el
					-- mismo hueco -- un indice apuntando a un punto que la
					-- unidad no sabe que existe:
					--
					--   * Si un bot LLEGABA al ultimo punto y despues anadias
					--     otro con shift, su indice ya apuntaba al nuevo pero
					--     nadie se lo habia mandado. Como seguia parado en el
					--     punto anterior, la siguiente comprobacion lo daba por
					--     llegado y SE SALTABA el punto nuevo entero.
					--   * Y su reloj era el del tramo viejo, asi que podia
					--     ademas darse por encallado nada mas anadirlo.
					if u.idx <= #route.pts and u.sent == u.idx then
						local llego, repetir, rendirse = false, false, false
						local x, y = PosOf(name)

						if u.tx and x then
							local umbral = R.cfg.arrive
							if u.d0 and u.d0 > 0 then
								umbral = math.max(umbral, u.d0 * R.cfg.near)
							end
							llego = Dist2D(x, y, u.tx, u.ty) <= umbral
						end

						-- SE HA MOVIDO ALGO DESDE LA ULTIMA VEZ QUE MIRAMOS?
						--
						-- La red de seguridad, y la que de verdad contesta a "el
						-- bot se olvida de que iba caminando". El troceo de
						-- arriba arregla la causa que se pudo identificar
						-- (`reactDistance`), pero un bot se puede quedar quieto
						-- por media docena de motivos que no controlamos --
						-- combate, un salto de mmap, la IA cambiando de opinion.
						-- En vez de intentar preverlos, se mira el SINTOMA: no
						-- ha llegado y lleva `stall` segundos sin avanzar un
						-- metro. Repetir es barato y seguro, porque `MoveBot`
						-- limpia el registro del movimiento anterior.
						--
						-- Y SE RINDE A LAS `retries`. Sin ese tope la primera
						-- version se colgaba para siempre con un bot de verdad
						-- atascado: cada reintento reiniciaba el reloj, asi que
						-- el plazo no llegaba nunca y la ruta se quedaba ahi.
						-- Lo caza la simulacion, no el juego.
						if not llego and x then
							if u.px and Dist2D(x, y, u.px, u.py) > 1.0 then
								u.px, u.py, u.pat = x, y, now
								u.stalls = 0
							elseif (now - (u.pat or now)) > R.cfg.stall then
								u.stalls = (u.stalls or 0) + 1
								if u.stalls >= R.cfg.retries then
									rendirse = true
								else
									repetir = true
								end
							end
						end

						-- SIN POSICION no hay ni llegada ni atasco que medir, y
						-- el unico juez posible es el reloj. Se mide desde que
						-- empezo ESTE punto de ruta (`since`), no desde el
						-- ultimo reenvio: si no, repetir la orden aplazaria el
						-- plazo indefinidamente, que es como se colgaba.
						if not x and (now - (u.since or now)) > R.cfg.timeout then
							rendirse = true
						end

						if rendirse then
							-- Se pasa al siguiente punto igual: una ruta que se
							-- salta un tramo es mejor que una que se para.
							u.idx = u.idx + 1
						elseif llego then
							-- Si esto era solo un TROZO de un tramo largo, el
							-- punto de ruta sigue siendo el mismo: se vuelve a
							-- apuntar desde aqui, y el indice no avanza.
							if u.partial then repetir = true else u.idx = u.idx + 1 end
						end

						if repetir then u.sent = nil end
					end

					-- Le queda camino? Entonces cuenta como viva, y si su tramo
					-- actual no se ha mandado todavia, se manda ahora. Un solo
					-- sitio que decide "hay que mandarle algo", en vez de
					-- hacerlo solo en la transicion: asi cubre igual al que
					-- acaba de avanzar y al que se quedo esperando un punto que
					-- aun no existia.
					if u.idx <= #route.pts then
						vivas = vivas + 1
						if u.sent ~= u.idx then tinsert(mover, name) end
					end
				end
			end

			if #mover > 0 then Issue(route, mover) end
			-- La ruta muere cuando la ULTIMA unidad ha pasado el ultimo punto.
			if vivas == 0 then DropRoute(route) end
		end
	end
end

--- Dibujo ------------------------------------------------------------------

local overlay, rings, nums = nil, {}, {}

local function Overlay()
	if overlay then return overlay end
	overlay = CreateFrame("Frame", "RTSRouteOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	-- Por debajo de los marcadores del cursor y muy por debajo de la barra: una
	-- ruta es fondo, no interfaz.
	overlay:SetFrameStrata("BACKGROUND")
	return overlay
end

-- EL TRAZO SE QUITO, Y NO POR NO SABER DIBUJARLO.
--
-- Hubo dos versiones y las dos se vieron en juego: una fila de puntitos y una
-- linea continua girando una textura con `DrawRouteLine`, la funcion del mapa de
-- vuelo. La segunda ademas costo dos fallos que merece la pena tener escritos,
-- porque la tecnica sirve para otras cosas:
--
--   * `DrawRouteLine` no dibuja un rectangulo girado: dibuja el CONTENEDOR
--     horizontal y mete el trazo dentro con ocho coordenadas de textura. Lo que
--     sobra del contenedor cae fuera de [0,1], y una textura de WoW no repite,
--     RECORTA -- devuelve el pixel del borde. Con una textura blanca de borde a
--     borde el contenedor entero sale relleno: rectangulos, no lineas. Hace
--     falta una textura con la primera y la ultima FILA transparentes, que es
--     exactamente lo que significa el 32/30 de `TAXIROUTE_LINEFACTOR`.
--   * La esquina del contenedor, medida a lo ancho, cae a `(l/w)*sen*cos`. Con
--     un trazo fino eso se sale del limite del cliente hasta en un tramo de 50
--     px, y entonces "TexCoord out of range" ABORTA el dibujo entero.
--
-- Y aun arreglado, el veredicto en pantalla fue que un trazo proyectado en la
-- capa de interfaz no se parece a una ruta de RTS: no tiene profundidad, se
-- dibuja sobre la colina que deberia taparlo, y con la camara girando la linea
-- entera nada de lado. Un PUNTO en el suelo no se compara con nada y aguanta
-- eso; una linea de cien pixeles se compara con el terreno en toda su longitud.
--
-- Asi que la ruta son ahora sus PUNTOS, cada uno con su numero. Menos dibujo,
-- ninguna de las dos pegas, y el numero dice ademas lo mismo que `/rts route`
-- imprime ("Bot 3/5"), que antes habia que contar aros para saberlo.

local RING_TEX = "Interface\\AddOns\\RTSCommand\\halo-02.tga"

local function GetRing(i)
	if rings[i] then return rings[i] end
	local t = Overlay():CreateTexture(nil, "ARTWORK")
	t:SetTexture(RING_TEX)
	t:SetBlendMode("ADD")
	t:Hide()
	rings[i] = t
	return t
end

-- El numero del punto. Va en su propia capa por encima del aro, y con contorno
-- porque el fondo es el mundo: sobre hierba clara un numero sin contorno
-- desaparece, y eso no se ve en una captura de prueba hecha sobre tierra.
local function GetNum(i)
	if nums[i] then return nums[i] end
	local fs = Overlay():CreateFontString(nil, "OVERLAY")
	fs:SetFont(GameFontNormal:GetFont(), R.cfg.num, "OUTLINE")
	fs:Hide()
	nums[i] = fs
	return fs
end

-- Un punto de la ruta: marcador en el suelo y numero encima.
--
-- El marcador va TUMBADO, no de cara a la camara: la misma elipse que usa el
-- destello de orden. Un aro cuadrado sobre el suelo se lee como una pegatina en
-- el monitor y no como algo que este ahi.
--
-- El NUMERO en cambio no se tumba ni se escala con la distancia mas alla de un
-- poco: es una etiqueta, no un objeto del mundo, y un numero en perspectiva no
-- se lee. Se centra en el marcador porque asi los dos dicen lo mismo -- si el
-- numero flotara arriba habria que decidir a que punto pertenece cuando dos
-- caen cerca.
local function PlaceRing(i, x, y, z, n, col)
	local M = ns.Markers
	local depth = M:CamCoords(x, y, z)
	if not depth then return i end
	local sx, sy = M:Project(x, y, z)
	if not sx then return i end

	local w, h = M:GroundEllipse(x, y, z, R.cfg.ring * 0.5)
	if not w then
		w = M:YardsToPixels(R.cfg.ring, depth)
		h = w
	end

	-- Acotado por los dos lados. Sin tope de abajo el punto lejano desaparece y
	-- la ruta parece acabar antes de donde acaba; sin tope de arriba, un punto a
	-- dos yardas de la camara tapa la pantalla.
	local k = 1
	if w < R.cfg.minpx then k = R.cfg.minpx / w
	elseif w > R.cfg.maxpx then k = R.cfg.maxpx / w end
	w, h = w * k, h * k
	if h < 4 then h = 4 end

	local t = GetRing(i)
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	t:SetWidth(w)
	t:SetHeight(h)
	t:SetVertexColor(col.r, col.g, col.b, 0.9)
	t:Show()

	local fs = GetNum(i)
	fs:ClearAllPoints()
	fs:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	fs:SetText(tostring(n))
	fs:SetTextColor(1, 1, 1, 0.95)
	fs:Show()

	return i + 1
end

-- Los puntos que todavia tiene que pisar alguien, en el mismo orden en que se
-- dibujan. Es lo que ve el servidor: un punto por el que ya paso el ultimo bot
-- deja de tener marcador porque deja de ser parte del camino.
local function Pending()
	local out = {}
	for _, route in ipairs(routes) do
		for k = MinIdx(route), #route.pts do
			local p = route.pts[k]
			if p.id then
				out[#out + 1] = { id = p.id, x = p[1], y = p[2], z = p[3] }
			end
		end
	end
	return out
end

local function Draw()
	local r = 1

	if R.enabled and ns.Markers and RTS_HasCam == 1 then
		for _, route in ipairs(routes) do
			local col = route.col or MULTI
			-- El numero es el indice ABSOLUTO del punto en la ruta, no su sitio
			-- entre los que quedan: asi el "3" del suelo es el mismo 3 que dice
			-- `/rts route`, y no cambia de numero al pasar por el anterior.
			for k = MinIdx(route), #route.pts do
				local p = route.pts[k]
				r = PlaceRing(r, p[1], p[2], p[3], k, col)
			end
		end
	end

	for i = r, #rings do rings[i]:Hide() end
	for i = r, #nums do nums[i]:Hide() end
end

--- Ciclo -------------------------------------------------------------------

function R:Create()
	-- LOS TRES VERBOS DE LAS RUTAS. Vivian en `Camera.lua` hasta 2026-09-02,
	-- cuando el canal se mudo a `Link.lua`; ahora cada modulo lee lo suyo.
	--
	-- EL FORMATO SE VALIDA AQUI, y no es opcional: nos susurramos a nosotros
	-- mismos, asi que nuestro propio `POS` de peticion llega de vuelta por este
	-- mismo camino. El `(.+)` es lo que lo descarta -- la peticion va sola.
	ns.Link:On("POS", function(rest)
		local pos = rest:match("^(.+)$")
		if pos then R:OnPositions(pos) end
	end)

	-- DONDE ESTA EL SUELO DE VERDAD de un punto que se pregunto. Llega un
	-- instante despues del click; el aro salta de la estimacion al sitio bueno,
	-- y quien fuera andando hacia el punto recibe la orden otra vez.
	ns.Link:On("GROUNDAT", function(rest)
		local gid, gx, gy, gz, gsent =
			rest:match("^(%d+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%d)$")
		if not gid then return end
		-- `gsent == 1` = la orden ya salio con el punto corregido (viene de un
		-- CLICK). Entonces esto solo mueve el dibujo; remandar el tramo pararia
		-- al bot para volver a mandarlo al mismo sitio.
		R:Correct(tonumber(gid), tonumber(gx), tonumber(gy), tonumber(gz),
			gsent ~= "1")
		-- El destello de la orden tambien: es el unico aviso que hay cuando la
		-- ruta esta apagada.
		if ns.Flare and ns.Flare.Move then
			ns.Flare:Move(tonumber(gx), tonumber(gy), tonumber(gz))
		end
	end)

	-- El rayo se fue al cielo o no habia mapa: el addon se queda con su
	-- estimacion. Se calla a proposito -- un aviso por click seria ruido.
	ns.Link:On("GROUNDNO", function() end)

	Overlay()

	if RTSCommandDB and type(RTSCommandDB.routeOn) == "boolean" then
		self.enabled = RTSCommandDB.routeOn
	end
	if RTSCommandDB and type(RTSCommandDB.routeCfg) == "table" then
		for k, v in pairs(self.cfg) do
			local n = tonumber(RTSCommandDB.routeCfg[k])
			if n and n > 0 then self.cfg[k] = n end
		end
	end

	-- DOS RITMOS, por lo mismo que Markers: el AVANCE mira posiciones que el DLL
	-- publica a 30 Hz, asi que cinco veces por segundo sobra y ahorra el paseo
	-- por todas las unidades; el DIBUJO tiene que ir por frame o la ruta nada
	-- de lado cada vez que se gira la camara.
	local acc, ask = 0, 0
	Overlay():SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc >= 0.2 then
			acc = 0
			if #routes > 0 then Advance() end
			-- Los marcadores del mundo van en el latido lento y no por frame:
			-- solo cambian cuando cambia la ruta, y `Sync` solo manda la
			-- diferencia. Se llama tambien con la lista vacia, que es lo que
			-- retira el ultimo marcador cuando la ruta se acaba.
			if ns.Marks then ns.Marks:Sync(Pending()) end
		end

		-- Pedirle al servidor donde estan, SOLO mientras hay ruta. Dos veces por
		-- segundo y un paquete pequeno para todo el grupo. Sin ruta no se pide
		-- nada: el resto del addon se apana con lo que ve el cliente, y esto
		-- existe solo para el caso en que el cliente NO lo ve.
		ask = ask + e
		if ask >= 0.5 then
			ask = 0
			if #routes > 0 and ns.Orders:HasServer() then ns.SendServer("POS") end
		end

		Draw()
	end)
end

function R:Toggle()
	self.enabled = not self.enabled
	RTSCommandDB.routeOn = self.enabled
	if not self.enabled then self:ClearAll() end
	ns.Print("rutas con shift + click derecho " ..
		(self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Un solo camino para todos los numeros. Se llama `Tune` y no `Set` porque
-- `Set` ya es "empieza una ruta aqui", y dos verbos con el mismo nombre en el
-- mismo modulo es como se acaba llamando al equivocado.
--
-- LAS CLAVES SON TODAS EN MINUSCULA a proposito: el manejador de `/rts` pasa el
-- subcomando en minuscula, asi que un `maxDots` en la tabla no lo encontraria
-- nunca y el comando se leeria como "no existe" en vez de como "mal escrito".
function R:Tune(key, value)
	local n = tonumber(value)
	if self.cfg[key] == nil or not n or n <= 0 then return false end
	self.cfg[key] = n
	RTSCommandDB.routeCfg = RTSCommandDB.routeCfg or {}
	RTSCommandDB.routeCfg[key] = n
	ns.Print(("route %s = %.2f"):format(key, n))
	return true
end

function R:Report()
	local n, pts = self:Count()
	ns.Print(("rutas: %s   |cffffff00%d|r activa(s), |cffffff00%d|r punto(s) pendientes")
		:format(self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r", n, pts))
	for i, route in ipairs(routes) do
		-- Por unidad, porque ahora cada una va por su cuenta: un solo numero
		-- diria menos justo cuando mas importa, que es cuando se han separado.
		local partes = {}
		for _, name in ipairs(route.units) do
			local u = route.u[name]
			tinsert(partes, ("%s %d/%d"):format(name, u and u.idx or 0, #route.pts))
		end
		ns.Print(("  %d. %s"):format(i, table.concat(partes, "   ")))
	end
	if RTS_HasCam ~= 1 then
		ns.Print("|cffff0000rts_core no esta inyectado|r: sin coordenadas no hay " ..
			"ni avance ni dibujo.")
	end
	ns.Print("|cffffff00shift + click derecho|r encadena puntos; el click derecho " ..
		"normal empieza de nuevo.")
	ns.Print("trazo: |cffffff00marcador y numero por punto|r, sin linea entre " ..
		"ellos -- el numero es el mismo que sale arriba.")

	local parts = {}
	for _, k in ipairs({ "arrive", "near", "timeout", "maxleg", "stall",
	                     "retries", "ring", "num" }) do
		tinsert(parts, ("%s=%.2f"):format(k, self.cfg[k]))
	end
	ns.Print("|cffffff00/rts route <clave> <n>|r  " .. table.concat(parts, "  "))
end
