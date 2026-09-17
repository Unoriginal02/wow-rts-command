--[[
	Skills.lua -- los hechizos de cada personaje, los huecos configurables y
	lanzarlos.

	=== NO DIBUJA NADA ======================================================

	Quien dibuja es `Cast.lua`, sobre las areas que reparte `Dock.lua`. Aqui
	viven los DATOS, las ACCIONES y la PERSISTENCIA. En el estado de varios
	cogidos hay cinco columnas pidiendo lo mismo a la vez, y con la logica
	dentro del panel serian cinco copias.

	    ns.Skills:Available(name)        -> todo lo que ese personaje ofrece
	    ns.Skills:Slots(name, n, set)    -> los huecos configurados, con agujeros
	    ns.Skills:SetSlot(name,i,id,set) -> configurar uno (nil lo vacia)
	    ns.Skills:Use(name, i, set)      -> lanzar el hueco i de ese personaje
	    ns.Skills:Subscribe(fn)          -> aviso de que algo cambio

	`set` son los DOS JUEGOS de huecos: "main" son los diez que salen con uno
	cogido y "group" los cuatro del 2x2 de cuando llevas varios.

	=== DE DONDE SALEN LOS HECHIZOS ========================================

	De SU personaje, no de tu libro. Tu libro solo tiene TUS hechizos -- la
	Polimorfia del mago no esta ahi porque no la conoces -- asi que "arrastrar
	del libro de hechizos" es imposible para un bot y no es rodeable. Lo contesta
	el servidor con el verbo `BARS`, y desde la 0.77.0 en DOS mitades:

	  1. SU BARRA DE ACCIONES, en el orden en que esta puesta. Es la lista
	     curada -- los hechizos que tu colocaste jugando ese personaje -- y por
	     eso es la que llena los huecos por defecto.
	  2. Y DETRAS, TODO LO DEMAS QUE SEPA, por nombre.

	La segunda mitad es la respuesta a `PRUEBAS-23` C2: *"¿son los de mi barra o
	los de playerbot? me gustaria que fueran los de playerbot porque va
	actualizando"*. **Playerbots no tiene una lista de hechizos que consultar**:
	su IA elige accion por accion, en el momento, y no guarda ningun catalogo.
	Lo que si existe y ademas hace lo que se pedia -- crecer solo segun el
	personaje sube de nivel -- es su libro de hechizos, que es lo que se manda.

	Se filtra en el servidor lo que seria un boton muerto: pasivos, oficios,
	idiomas, hechizos de mascota (ver `ActionBarSpells`) y los rangos viejos, que
	el nucleo ya marca como no activos.

	Y COMO LA LISTA PASA DE DOCE A CIEN, el desplegable de `Cast.lua` va por
	paginas desde la misma version. Sin eso se dibujaria de tres mil pixeles de
	alto y en juego se leeria como que no sale.

	=== LOS HUECOS SON DEL JUGADOR, NO DEL ORDEN DE LA BARRA ================

	Antes `Slots()` devolvia los seis primeros de la barra del bot. Eso no es
	configurable: es un recorte. El brief pide *"cada slot es clicable para
	asignarle un hechizo del personaje seleccionado"*, asi que ahora los huecos
	se guardan por personaje y la lista de la barra pasa a ser el CATALOGO del
	que se elige.

	SIN CONFIGURAR, LOS PRIMEROS. Un hueco vacio nada mas seleccionar a alguien
	se leeria como que la barra no funciona; los primeros de su barra son una
	respuesta razonable y ademas es lo que habia antes.

	=== EL TIPO DE HECHIZO LO DICE EL SERVIDOR =============================

	`BARS` devuelve `id:tipo` por hechizo, y el tipo es una letra
	(`docs/HECHIZOS-COLA.md` §2). El addon NO clasifica: `IsHarmfulSpell` y
	compania toman un nombre o un indice de TU libro, y el bot conoce hechizos
	que tu no. Lo unico que el cliente sabe de un id ajeno es lo que
	`GetSpellInfo` saca del DBC -- nombre, icono, rango -- que no incluye si
	necesita objetivo ni si es amistoso.

	Es la regla de `/rts portrait api` llevada al final: en vez de comprobar una
	constante, no tener constante.

	=== DOS TRAMPAS DEL CLIENTE, LAS DOS YA PAGADAS ========================

	1. `HasServer()` ES FALSO DURANTE EL PRIMER SEGUNDO, aunque mod-rts este
	   delante: se pone a cierto con la PRIMERA respuesta. Se usa
	   `Link:WhenServer`, que es ese bucle escrito una sola vez.

	2. `GetActionInfo` NO GARANTIZA DEVOLVER UN ID DE HECHIZO. Puede devolver el
	   INDICE DEL LIBRO, y pasarle un indice a `GetSpellInfo` **no da error**:
	   devuelve otro hechizo cualquiera, con nombre e icono. De ahi los
	   "hechizos raros" de la etapa 5o. Solo afecta a TU propia barra (la del
	   bot viene del servidor y son ids de verdad), y se contrasta contra
	   `GetActionTexture`, que es la unica fuente que no puede mentir porque es
	   literalmente el dibujo que hay en pantalla.
]]

local ADDON, ns = ...

local K = {}
ns.Skills = K

-- EL TECHO DE LO QUE SE GUARDA, y solo eso. Cuantos se DIBUJAN lo decide
-- `Hall.shown`, que desde la 0.78.0 es "los que quepan a lo ancho" en vez de un
-- numero fijo -- el boceto retocado del 2026-09-05.
--
-- Tiene que ir por delante de lo que quepa en la barra mas ancha (con `grow` 5
-- salen diecinueve), porque un hueco dibujado que no se puede guardar es un
-- boton que acepta un hechizo y lo olvida al recargar.
--
-- Con varios personajes cogidos se ensenan cuatro (el 2x2), y son los mismos
-- cuatro PRIMEROS de esta lista -- no otra configuracion.
K.MAX_SLOTS = 20

-- Y CUATRO EN GRUPO, QUE SON OTROS CUATRO. Desde el 2026-09-13 el 2x2 que sale
-- con varios cogidos NO ensena los cuatro primeros de los diez: es un juego
-- aparte, guardado aparte (`group`).
--
-- El argumento viejo era que dos listas son dos sitios donde configurar lo
-- mismo. El nuevo es mas fuerte: con cuatro cogidos no quieres los cuatro
-- primeros hechizos de cada uno, quieres LO QUE SE MANDA EN GRUPO -- el
-- aturdimiento, la curacion de emergencia, el escudo -- que casi nunca son los
-- que usas llevando a uno solo.
K.GROUP_SLOTS = 4

-- Los dos juegos, y como se llama cada uno donde se guarda. Escrito una vez:
-- una cadena "spells"/"group" repartida por el fichero es la forma tipica de
-- acabar guardando en un sitio y leyendo de otro.
local SET = {
	main  = { key = "spells", n = 20 },
	group = { key = "group",  n = 4  },
}

local function SetInfo(set)
	return SET[set or "main"] or SET.main
end

--- Estado ------------------------------------------------------------------

-- name -> { list = { {id=, t=}, ... }, at = GetTime(), pending = bool }
local bars = {}
local listeners = {}
local aiming = nil       -- ver "apuntar", abajo

--- Los tipos ---------------------------------------------------------------
--
-- Las letras vienen del servidor. `docs/HECHIZOS-COLA.md` §2 tiene la tabla
-- completa con el predicado de `SpellInfo` que decide cada una.

local TYPE = {
	S = { ask = false, label = "sobre si mismo" },
	N = { ask = false, label = "sin objetivo" },
	T = { ask = false, label = "totem" },
	A = { ask = true,  friendly = true,  label = "sobre un amigo" },
	H = { ask = true,  friendly = false, label = "sobre un enemigo" },
	G = { ask = true,  ground = true,    label = "en un sitio" },
	D = { ask = true,  dead = true,      label = "sobre un muerto" },

	-- SIN CLASIFICAR PREGUNTA, que no es lo mismo que `N`.
	--
	-- Un hueco configurado cuyo hechizo no esta en el catalogo de ahora --
	-- porque la respuesta del servidor no ha llegado, o porque el bot no esta
	-- cargado -- pasaba por `Describe`, que lo daba por `N`. Y `N` no pregunta:
	-- se manda tal cual, o sea **sobre el propio lanzador**. Un bufo puesto en
	-- un hueco se le aplicaba a si mismo por no saber todavia lo que era.
	--
	-- Preguntar cuando no se sabe es lo unico reversible de los dos: el click
	-- derecho cancela, mientras que un hechizo lanzado sobre quien no era no se
	-- deshace.
	["?"] = { ask = true, label = "sin clasificar" },
}

-- Sin servidor no hay letra. `N` es el valor seguro: se manda y el servidor
-- decide -- `CastAs` con guid vacio usa el objetivo que el bot ya tenga y, si
-- no tiene, se lo lanza a si mismo. Suponer `H` en cambio pediria un segundo
-- click para un grito de guerra.
local DEFAULT_TYPE = "N"

function K:TypeOf(spellId, owner)
	local b = bars[owner or ""]
	if b and b.list then
		for _, e in ipairs(b.list) do
			if e.id == spellId then return e.t or DEFAULT_TYPE end
		end
	end
	return DEFAULT_TYPE
end

function K:TypeInfo(letter)
	return TYPE[letter or DEFAULT_TYPE] or TYPE[DEFAULT_TYPE]
end

--- Aviso -------------------------------------------------------------------

function K:Subscribe(fn)
	table.insert(listeners, fn)
end

local function Notify()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then ns.Print("|cffff0000skills:|r " .. tostring(err)) end
	end
end

--- Tu propia barra ---------------------------------------------------------

-- Los hechizos de TU personaje, sacados de tus casillas de accion.
--
-- El id se contrasta con el icono. Ver la trampa 2 de la cabecera: `type` puede
-- decir "spell" y el segundo valor ser un indice del libro, y `GetSpellInfo`
-- sobre un indice devuelve OTRO hechizo sin quejarse. Si el icono del hechizo
-- que sale no es el que la casilla esta dibujando, el numero no era un id.
--
-- SOLO `"spell"`. Una casilla con un OBJETO se salta: un objeto no es un
-- hechizo, se gasta, y `GetActionInfo` lo devuelve como `"item"`. Ver
-- `docs/HECHIZOS-COLA.md` §8 para por que no entran hoy.
local function MyBar()
	local out, seen = {}, {}

	for slot = 1, 120 do
		local kind, id = GetActionInfo(slot)
		if kind == "spell" and id and id > 0 and not seen[id] then
			local name, _, icon = GetSpellInfo(id)
			local shown = GetActionTexture(slot)
			if name and icon and shown and icon == shown then
				seen[id] = true
				-- SIN LETRA: tus hechizos no pasan por `BARS`, asi que el
				-- servidor no los ha clasificado. `SELFCAST` con guid vacio se
				-- comporta igual que `CAST`, o sea que el valor seguro vale.
				table.insert(out, { id = id, t = DEFAULT_TYPE })
			end
		end
	end

	return out
end

--- Pedir la de un personaje ------------------------------------------------

-- TU PERSONAJE PASA POR EL SERVIDOR IGUAL QUE LOS DEMAS DESDE LA 0.77.0.
--
-- ESO ERA EL "NEFERITE NO TIENE SPELLS" de `PRUEBAS-23` C2. Tu heroe tenia su
-- propio camino -- `MyBar()`, leyendo tus casillas con `GetActionInfo` -- y ese
-- camino tiene la trampa 2 de la cabecera: el segundo valor puede ser el indice
-- del libro en vez del id. La defensa contra eso es contrastar el icono, y
-- cuando el cliente devuelve indices esa defensa **tira la lista entera**. En
-- pantalla: un personaje sin un solo hechizo y ningun error.
--
-- El servidor no tiene esa ambiguedad: lee la barra guardada del personaje, que
-- son ids de verdad, y ademas clasifica el tipo -- que por el camino propio no
-- se sabia (todos salian como "sin objetivo").
--
-- `MyBar()` SE QUEDA COMO RESPALDO y solo como eso: sin mod-rts delante es lo
-- unico que hay, y con el es lo que se dibuja mientras llega la respuesta, para
-- que la fila no aparezca vacia un segundo.
function K:Request(name)
	if not name or name == "" then return end

	local mine = (name == ns.MyName())

	local b = bars[name] or {}
	bars[name] = b
	b.pending = true

	-- `WhenServer` y no `HasServer` a secas: ver la trampa 1 de la cabecera.
	ns.Link:WhenServer(function(ok)
		if not ok then
			b.pending = false
			b.list = mine and MyBar() or {}
			Notify()
			return
		end
		if mine and not b.list then b.list = MyBar() end
		b.staging = {}
		ns.SendServer("BARS " .. name)
	end)
end

-- Pedir la de todos los que hagan falta ahora mismo. En el estado B hay hasta
-- cinco columnas y cada una necesita la suya; pedirlas al dibujar seria pedir
-- cinco veces por segundo.
function K:RequestFor(names)
	for _, n in ipairs(names or {}) do
		local b = bars[n]
		if not b or (not b.list and not b.pending) then
			self:Request(n)
		end
	end
end

function K:Refresh()
	self:Request(ns.Selection:GetPrimary())
end

--- El catalogo -------------------------------------------------------------

-- Todo lo que ese personaje puede ofrecer, para elegir en el desplegable.
-- `{ { spellId, name, texture, type }, ... }`
function K:Available(name)
	local b = bars[name or ""]
	if not b or not b.list then return {} end

	local out = {}
	for _, e in ipairs(b.list) do
		local sname, _, icon = GetSpellInfo(e.id)
		if sname then
			table.insert(out, { spellId = e.id, name = sname,
			                    texture = icon, type = e.t or DEFAULT_TYPE })
		end
	end
	return out
end

function K:Pending(name)
	local b = bars[name or ns.Selection:GetPrimary()]
	return b and b.pending or false
end

--- Los huecos configurados -------------------------------------------------
--
-- EL FORMATO Y POR QUE (§9.4 del brief, y `docs/HECHIZOS-COLA.md` §12):
--
--   RTSCommandDB.hall.who[nombre] = { spells = {id,...}, actions = {clave,...} }
--
-- Por NOMBRE y no por guid porque es la clave que el jugador reconoce y la que
-- usan `BARS` y `CAST`. Los AGUJEROS SE CONSERVAN: un hueco 3 vacio entre el 2
-- y el 4 es una decision, no un error de compactado -- por eso se guarda con
-- indices y no con `table.insert`.

local function Store(name, create)
	if not RTSCommandDB then return nil end
	local hall = RTSCommandDB.hall
	if not hall then
		if not create then return nil end
		hall = {}
		RTSCommandDB.hall = hall
	end
	hall.who = hall.who or {}
	local w = hall.who[name]
	if not w and create then
		w = { spells = {}, group = {}, actions = {} }
		hall.who[name] = w
	end
	if w and create then w.group = w.group or {} end
	return w
end

-- Los huecos de un personaje, ya resueltos a hechizo. Devuelve una lista de
-- `n` posiciones donde cada una es una tabla o nil.
--
-- SIN CONFIGURAR, LOS PRIMEROS DE SU BARRA. Ver la cabecera: un hueco vacio
-- nada mas seleccionar a alguien se lee como que la barra no funciona.
-- `set` ELIGE EL JUEGO: "main" son los diez de cuando llevas a uno, "group" los
-- cuatro del 2x2 de cuando llevas varios. Sin decir nada, los diez.
--
-- `n` POR DEFECTO ES EL TOPE DE SU JUEGO, NO LO QUE HAYA DIBUJADO, y esto fue
-- un fallo de verdad que duro un dia.
--
-- Antes caia a `Hall.shown` (fichero ya borrado), o sea "cuantos huecos hay pintados en la fila
-- del estado A". Con dos o mas personajes cogidos la sala esta en el estado B y
-- no hay fila: desde el 2026-09-05 `Recompute` deja `shown` en **0** -- y cero
-- en Lua es CIERTO, asi que `n` valia 0, el bucle no daba una vuelta y
-- `Slots(name)[i]` era nil.
--
-- En pantalla: los iconos SI salian (los pinta `Cast`, que pasa su 4 explicito)
-- y pulsarlos no hacia absolutamente nada. O sea *"con seleccion multiple los
-- hechizos no funcionan"*, sin un solo error y sin relacion visible con haber
-- vaciado el centro de la consola el dia anterior.
--
-- Resolver un hueco no tiene nada que ver con cuantos se dibujan: quien dibuja
-- ya pasa su cuenta. El tope es el unico valor que no puede envejecer.
function K:Slots(name, n, set)
	name = name or ns.Selection:GetPrimary()
	local info = SetInfo(set)
	n = n or info.n

	local cat = self:Available(name)
	local byId = {}
	for _, s in ipairs(cat) do byId[s.spellId] = s end

	local w = Store(name, false)
	local cfg = w and w[info.key]

	local out = {}
	if cfg and next(cfg) then
		for i = 1, n do
			local id = tonumber(cfg[i])
			-- UN ID QUE YA NO ESTA EN SU BARRA SE DIBUJA IGUAL, en gris. Lo que
			-- no se puede hacer es tirarlo: el bot puede estar desconectado o la
			-- respuesta puede no haber llegado todavia, y borrar la
			-- configuracion del jugador por eso seria perderla sin avisar.
			if id then
				out[i] = byId[id] or self:Describe(id, true)
			end
		end
		return out
	end

	for i = 1, n do out[i] = cat[i] end
	return out
end

-- Un hechizo del que solo se tiene el id. `stale` marca los que ya no estan en
-- la barra del bot, para que `Cast` los pinte apagados.
function K:Describe(id, stale)
	local sname, _, icon = GetSpellInfo(id)
	if not sname then return nil end
	return { spellId = id, name = sname, texture = icon,
	         type = "?", stale = stale or nil }
end

function K:SetSlot(name, i, spellId, set)
	if not name or not i then return end
	local w = Store(name, true)
	if not w then return end
	local info = SetInfo(set)
	local cfg = w[info.key]

	-- La primera vez que se toca un hueco hay que CONGELAR lo que se estaba
	-- ensenando, o cambiar el hueco 3 borraria el 1, el 2 y el 4 -- que eran
	-- los primeros de la barra y no estaban guardados. Es el fallo clasico de
	-- pasar de un valor derivado a uno guardado.
	if not next(cfg) then
		local shown = self:Slots(name, info.n, set)
		for k = 1, info.n do
			if shown[k] then cfg[k] = shown[k].spellId end
		end
	end

	cfg[i] = spellId and tonumber(spellId) or nil
	Notify()
end

function K:ClearSlots(name, set)
	local w = Store(name, false)
	if not w then return end
	local info = SetInfo(set)
	w[info.key] = {}
	Notify()
	ns.Print(("huecos de |cff33ccff%s|r a los de fabrica."):format(name))
end

-- Se acota AL LEER, que es la cuarta vez que hace falta en este addon. Un id
-- que `GetSpellInfo` no resuelve es basura de una version anterior o de otro
-- servidor, y dejarlo puesto es un hueco que no dibuja nada sin decir por que.
function K:Load()
	local hall = RTSCommandDB and RTSCommandDB.hall
	if type(hall) ~= "table" or type(hall.who) ~= "table" then return end

	local malos = 0
	for name, w in pairs(hall.who) do
		if type(w) ~= "table" then
			hall.who[name] = nil
		else
			w.spells = type(w.spells) == "table" and w.spells or {}
			w.group = type(w.group) == "table" and w.group or {}
			w.actions = type(w.actions) == "table" and w.actions or {}
			for _, info in pairs(SET) do
				local cfg = w[info.key]
				for i, id in pairs(cfg) do
					local n = tonumber(i)
					if not n or n < 1 or n > info.n or
					   not tonumber(id) or not GetSpellInfo(tonumber(id)) then
						cfg[i] = nil
						malos = malos + 1
					end
				end
			end
		end
	end
	if malos > 0 then
		ns.Print(("|cff888888sala: descartados %d huecos guardados que ya no valen.|r"):format(malos))
	end
end

--- Lanzar ------------------------------------------------------------------

-- `CastSpellByName` esta PROTEGIDA en 3.3.5a, y un boton seguro tampoco vale:
-- su contenido cambia con la seleccion y cambiar los atributos de un boton
-- seguro esta bloqueado EN COMBATE, que es justo cuando se usa. Los dos caminos
-- van por el servidor -- `CAST` para un bot, `SELFCAST` para ti -- que ademas
-- los hace de la misma forma en vez de tener dos mecanismos.
--
-- `CASTQ` ES EL MISMO CAMINO CON COLA. El brief pide que un hechizo pulsado
-- mientras el personaje esta ocupado *espere* en vez de fallar, y eso no se
-- puede hacer desde el cliente: el que sabe si el hueco esta libre es el
-- servidor. Sin mod-rts al dia se cae a `CAST`, que es lo de siempre.
local function Fire(owner, spellId, guid)
	local hex = guid and (tostring(guid):gsub("^0[xX]", "")) or nil

	if owner == ns.MyName() then
		ns.SendServer("SELFCAST " .. spellId .. (hex and (" " .. hex) or ""))
		return
	end

	-- 0.36.0 es donde entra `CASTQ`. Con un servidor anterior se manda `CAST`,
	-- que es lo de siempre: sin cola, pero funcionando. Un verbo que el servidor
	-- no conoce **no da error, no contesta**, o sea un boton que no hace nada.
	local verb = ns.Link:ServerAtLeast(36) and "CASTQ" or "CAST"
	ns.SendServer(verb .. " " .. owner .. " " .. spellId .. (hex and (" " .. hex) or ""))
end

-- EL OBJETIVO DEL CLIENTE, Y SOLO SI SIRVE PARA ATACAR.
--
-- `UnitGUID("target")` a secas no vale, y el porque esta escrito entero en el
-- bloque de "siempre pregunta" de abajo: en este modo el objetivo casi siempre
-- es el RESIDUO de haber pinchado a alguien, y eso incluye a los tuyos. Las
-- tres preguntas de aqui son las que separan "he elegido a quien atacar" de
-- "he seleccionado a mi sacerdotisa": existe, esta vivo, y se le puede atacar.
local function HostileTarget()
	if not UnitExists("target") then return nil end
	if UnitIsDead("target") then return nil end
	if not UnitCanAttack("player", "target") then return nil end
	return UnitGUID("target"), UnitName("target")
end

--- Apuntar -----------------------------------------------------------------
--
-- EL GESTO DE §5 DEL BRIEF. Pulsar un hechizo que necesita objetivo no lo
-- manda: lo deja ARMADO, con la luz circular de las mascotas recorriendo el
-- icono, y el siguiente click elige sobre quien -- en la lista de personajes o
-- en el mundo 3D, indistintamente.
--
-- Con Alt va sobre el propio personaje sin preguntar, que es la convencion de
-- siempre en WoW y la del video.
--
-- === Y SIEMPRE PREGUNTA, AUNQUE TENGAS ALGO APUNTADO ====================
--
-- Hasta el 2026-09-06 habia un atajo: con un objetivo puesto se lanzaba sobre
-- el sin preguntar, *"porque preguntar cuando la respuesta esta delante es una
-- pulsacion de mas"*. La premisa era falsa y en juego se veia asi:
--
--   * seleccionas a la sacerdotisa **pinchandola en el mundo** -- y ese gesto
--     ADEMAS la apunta, porque el cliente apunta lo que pinchas;
--   * pulsas su cura;
--   * y como "hay objetivo", se lanza sobre el objetivo, que es ella misma.
--     **Se cura a si misma.**
--
--   * seleccionandola desde la consola no hay objetivo, asi que se arma, eliges
--     a quien, y cura a quien elegiste. Que es lo que se pide.
--
-- O sea que el mismo boton hacia dos cosas distintas segun COMO hubieras
-- seleccionado, y la diferencia era invisible. El objetivo del cliente no es
-- una declaracion de intencion aqui: casi siempre es el residuo del gesto de
-- seleccionar. "La respuesta esta delante" solo era cierta fuera del modo RTS.
--
-- Con el atajo se va su red de seguridad -- el aviso de bando equivocado, que
-- existia para proteger un disparo que ya no se hace a ciegas -- y baja a
-- `AimAt`, donde el jugador SI ha elegido a quien. Alli avisa y no bloquea: la
-- clasificacion no es infalible y el servidor rechaza lo imposible de todas
-- formas.
--
-- === SALVO LO OFENSIVO, QUE SALE SOBRE LO APUNTADO (2026-09-16) =========
--
-- Pedido en juego, y no contradice nada de lo de arriba: lo que hacia falsa la
-- premisa era el RESIDUO -- pinchar a alguien para seleccionarlo lo apunta de
-- paso -- y ese residuo es SIEMPRE uno de los tuyos. Un hechizo `H` solo sale
-- si lo apuntado se puede atacar (`HostileTarget`), asi que el caso de la
-- sacerdotisa no puede llegar aqui: a ella no se le puede atacar y el gesto
-- cae en el de siempre.
--
-- Y la razon de que esta mitad SI merezca el atajo es que atacar es lo unico
-- que se hace en rafaga. Preguntar a quien una vez por hechizo esta bien para
-- una cura; para el tercer golpe sobre el mismo bicho es una pulsacion de mas
-- por cada uno, y el objetivo lleva ahi desde el primero.

-- UN HECHIZO A TU PROPIO HEROE, SIEMPRE SOBRE SI MISMO. Lo usa la fila de roles
-- (`Roles.lua`) para las posturas, que son hechizos y no estrategias.
--
-- EL GUID PROPIO VA PUESTO A PROPOSITO, y no es de adorno: `SELFCAST` sin
-- objetivo usa EL QUE TENGAS APUNTADO, y el servidor rechaza un hechizo
-- positivo lanzado sobre un enemigo (`RtsOrders.cpp`, "ese hechizo no va contra
-- ese objetivo"). Como en modo RTS lo normal es tener algo apuntado, sin esto
-- la postura defensiva fallaria justo cuando hace falta -- en combate.
function K:SelfCast(spellId)
	if not spellId then return end
	Fire(ns.MyName(), spellId, UnitGUID("player"))
end

function K:Use(name, i, set)
	name = name or ns.Selection:GetPrimary()
	local s = self:Slots(name, nil, set)[i]
	if not s then
		if self:Pending(name) then
			ns.Print("|cff888888habilidades:|r pidiendo la barra de " .. name .. "...")
		end
		return
	end

	local letter = s.type or self:TypeOf(s.spellId, name)
	local info = self:TypeInfo(letter)

	-- SHIFT PREGUNTA IGUALMENTE, y es la valvula de la clasificacion.
	--
	-- La letra la decide el servidor con los predicados del nucleo, sin ninguna
	-- lista de ids -- que es lo correcto y lo que este proyecto lleva etapas
	-- defendiendo. Pero "no pide objetivo explicito" no es lo mismo que "solo
	-- vale para el que lo lanza": un bufo que el juego deja echarle a un
	-- companero puede caer en `N` y entonces se manda a ciegas, o sea al propio
	-- lanzador.
	--
	-- En vez de inventar una regla nueva encima de la del nucleo -- que seria
	-- adivinar, y adivinar aqui se paga en botones que no hacen lo que dicen --
	-- se deja que lo diga el jugador, que es quien sabe si ese bufo va a otro.
	-- Alt = sobre si mismo, Shift = elijo yo, sin nada = lo que diga la letra.
	if IsAltKeyDown() or (not info.ask and not IsShiftKeyDown()) then
		local guid = IsAltKeyDown() and UnitGUID(ns.Selection:UnitFor(name) or "player") or nil
		Fire(name, s.spellId, guid)
		-- EL TIPO VA EN EL MENSAJE. "¿por que no me ha preguntado?" es una
		-- pregunta sobre la LETRA, y sin ella cuesta una ronda de pruebas
		-- averiguar si el hechizo esta mal clasificado o el gesto mal entendido.
		ns.Print(("|cff33ccff%s|r -> %s |cff888888(%s)|r%s"):format(name, s.name,
			info.label, guid and " sobre si" or ""))
		return
	end

	-- LO OFENSIVO NO PREGUNTA: SALE SOBRE LO QUE TENGAS APUNTADO.
	--
	-- `friendly == false` es la letra `H` y solo ella -- no "lo que no es
	-- amistoso", que se llevaria por delante al suelo (`G`), a los muertos
	-- (`D`) y a lo sin clasificar (`?`), donde preguntar sigue siendo lo unico
	-- reversible.
	--
	-- SIN NADA HOSTIL APUNTADO SE ARMA COMO SIEMPRE, que es la unica salida que
	-- no dispara a ciegas: mandarlo sin guid se lo tira el bot a lo que EL
	-- tenga apuntado, que no es lo que acabas de pedir, y no hay forma de
	-- notarlo desde aqui.
	--
	-- Y SHIFT SIGUE PREGUNTANDO, que es como se le lanza a otro sin tener que
	-- cambiar tu objetivo primero.
	if info.friendly == false and not IsShiftKeyDown() then
		local guid, who = HostileTarget()
		if guid then
			Fire(name, s.spellId, guid)
			ns.Print(("|cff33ccff%s|r -> %s sobre %s"):format(
				name, s.name, who or "tu objetivo"))
			return
		end
	end

	-- EL JUEGO VA EN LO ARMADO. El hueco 2 de los diez y el hueco 2 del 2x2 son
	-- hechizos distintos, asi que sin esto el 2x2 se dibujaba armado cuando lo
	-- armado era el otro.
	aiming = { owner = name, slot = i, set = set or "main", spellId = s.spellId,
	           name = s.name, type = letter, at = GetTime() }
	ns.Print(("|cffffd100%s|r (%s): elige objetivo con el click izquierdo; " ..
	          "el derecho cancela."):format(s.name,
		(not info.ask) and (info.label .. ", forzado con shift") or info.label))
	Notify()
end

function K:Aiming()
	return aiming
end

function K:CancelAim()
	if not aiming then return false end
	aiming = nil
	Notify()
	return true
end

-- Llamada desde `RTSMode` (el mundo 3D) cuando hay una
-- habilidad armada y pinchas algo. Un guid vacio la cancela: pinchar el suelo
-- con algo armado significa "olvida".
-- `hostile` es opcional: true, false, o nil cuando quien llama no lo sabe. Los
-- tres sitios que arman esto SI lo saben, asi que el aviso de bando llega
-- entero -- y aqui vale mas que donde estaba, porque el objetivo lo acabas de
-- elegir tu en vez de heredarlo del gesto anterior.
function K:AimAt(guid, label, hostile)
	if not aiming then return false end
	local a = aiming
	aiming = nil

	if not guid then
		ns.Print("|cff888888" .. a.name .. ": cancelada.|r")
		Notify()
		return true
	end

	-- AVISA Y NO BLOQUEA. `IsPositive()` se apoya en atributos que el nucleo
	-- corrige a mano y no es infalible, asi que negarse en redondo dejaria un
	-- hechizo inservible por una clasificacion mala. Y quien decide de verdad es
	-- el servidor, que rechaza lo imposible.
	local info = self:TypeInfo(a.type)
	if hostile ~= nil and info.friendly ~= nil and info.friendly == hostile then
		ns.Print(("|cffff8800ojo:|r %s es %s y %s no lo parece."):format(
			a.name, info.label, label or "eso"))
	end

	Fire(a.owner, a.spellId, guid)
	ns.Print(("|cff33ccff%s|r -> %s sobre %s"):format(a.owner, a.name, label or "eso"))
	Notify()
	return true
end

--- El canal ----------------------------------------------------------------

function K:Create()
	if self.created then return end
	self.created = true

	ns.Link:On("BARS", function(rest)
		-- DOS SENTIDOS: mandamos "BARS <nombre>" y nos lo oimos de vuelta. La
		-- respuesta trae un segundo campo con la lista (o "-" si esta vacia),
		-- que es lo que la distingue de la peticion.
		local name, payload = rest:match("^(%S+)%s+(%S.*)$")
		if not name then return end

		local b = bars[name]
		if not b then return end
		b.staging = b.staging or {}
		if payload == "-" then return end

		-- `id:letra`, y sin letra vale igual: un mod-rts anterior manda solo el
		-- numero y entonces todo es del tipo seguro. Que una version vieja del
		-- servidor deje la consola muda seria peor que perder la clasificacion.
		for piece in payload:gmatch("[^%s,]+") do
			local id, t = piece:match("^(%d+):?(%a?)$")
			if id then
				table.insert(b.staging, { id = tonumber(id),
				                          t = (t ~= "" and t) or DEFAULT_TYPE })
			end
		end
	end)

	ns.Link:On("BARSEND", function(rest)
		local name = rest:match("^(%S+)$")
		if not name then return end
		local b = bars[name]
		if not b then return end
		b.list = b.staging or {}
		b.staging = nil
		b.pending = false
		b.at = GetTime()
		Notify()
	end)

	-- LO QUE LA COLA CONTESTA. Un hechizo que se queda esperando y luego no sale
	-- tiene que decirlo: una orden que desaparece sin mensaje es indistinguible
	-- de una que nunca se dio, que es el modo de fallo que este proyecto
	-- persigue desde la etapa 5i.
	ns.Link:On("CASTQ", function(rest)
		local who, id, state, why = rest:match("^(%S+)%s+(%d+)%s+(%S+)%s*(.*)$")
		if not who then return end
		local sname = GetSpellInfo(tonumber(id)) or ("hechizo " .. id)

		if state == "ok" then
			K.queued[who] = nil
			Notify()
		elseif state == "wait" then
			K.queued[who] = { id = tonumber(id), at = GetTime() }
			Notify()
		else
			K.queued[who] = nil
			ns.Print(("|cffff8800%s|r no pudo lanzar %s: %s"):format(
				who, sname, (why ~= "" and why) or "sin motivo"))
			Notify()
		end
	end)

	-- Cambiar de primario cambia la barra.
	ns.Selection:Subscribe(function()
		local who = ns.Selection:GetPrimary()
		if who ~= K.lastOwner then
			K.lastOwner = who
			K:Request(who)
		end
		-- Y EN EL ESTADO B HACEN FALTA VARIAS. Sin esto, seleccionar a cuatro
		-- dejaria tres columnas en blanco hasta que cada uno pasara por
		-- primario, que es un orden que el jugador no tiene por que recorrer.
		local names = {}
		for _, n in ipairs(ns.Selection:Get()) do table.insert(names, n) end
		K:RequestFor(names)
	end)

	-- Y LA PRIMERA VEZ, QUE NO ES UN CAMBIO. Sin ninguna seleccion todavia,
	-- `GetPrimary()` cae a tu personaje -- correctamente -- pero nadie habia
	-- pedido su barra, asi que `Slots()` devolvia vacio y el diagnostico
	-- hablaba de "un bot sin barra guardada" con el jugador de primario. Un
	-- mensaje que nombra la causa que no es cuesta mas que uno que calla.
	K.lastOwner = ns.Selection:GetPrimary()
	K:Request(K.lastOwner)
end

-- name -> { id, at } mientras el servidor lo tiene en cola. Lo dibuja `Cast`.
K.queued = {}

function K:QueuedFor(name)
	return self.queued[name or ""]
end

function K:Report()
	local name = ns.Selection:GetPrimary()
	-- LOS DOS JUEGOS, Y DICIENDO CUAL ES CUAL. El diagnostico se abre justo
	-- cuando un boton no hace lo que se esperaba, y "el hueco 2" significa dos
	-- hechizos distintos segun cuantos lleves cogidos.
	for _, which in ipairs({ { "main", ns.Dock.MAIN_TOTAL, "tuyos (uno cogido)" },
	                         { "group", K.GROUP_SLOTS, "de grupo (dos o mas)" } }) do
		local set, n, label = which[1], which[2], which[3]
		local slots = self:Slots(name, n, set)
		ns.Print(("habilidades de |cff33ccff%s|r, %s: %d huecos%s"):format(
			name, label, n, self:Pending(name) and " (pidiendo...)" or ""))
		for i = 1, n do
			local s = slots[i]
			if s then
				ns.Print(("  %d. %s (%d) |cff888888%s%s|r"):format(
					i, s.name, s.spellId, s.type or "?", s.stale and " -- ya no en su barra" or ""))
			else
				ns.Print(("  %d. |cff666666vacio|r"):format(i))
			end
		end
	end

	local cat = self:Available(name)
	ns.Print(("  catalogo: %d hechizos"):format(#cat))
	if #cat == 0 and not self:Pending(name) then
		if name == ns.MyName() then
			ns.Print("  |cff888888nada en tus casillas de accion. Pon hechizos en la barra " ..
			         "y vuelve a mirar.|r")
		else
			ns.Print("  |cff888888nada: ese bot no tiene barra de acciones guardada. " ..
			         "Entra con el una vez y colocale hechizos.|r")
		end
	end
end
