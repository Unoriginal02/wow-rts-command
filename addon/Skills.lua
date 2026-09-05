--[[
	Skills.lua -- los hechizos de cada personaje, los huecos configurables y
	lanzarlos.

	=== SIGUE SIN DIBUJAR NADA, Y AHORA POR OTRA RAZON ======================

	Antes era porque la sala estaba vacia y poner botones aqui la habria
	predecidido. Ahora la sala existe (`Hall.lua`) y quien dibuja es `Cast.lua`.
	La separacion se queda porque es la buena: aqui viven los DATOS, las
	ACCIONES y la PERSISTENCIA, y `Cast` solo pinta lo que le den. En el estado
	B hay cinco columnas pidiendo lo mismo a la vez, y con la logica dentro del
	panel serian cinco copias.

	    ns.Skills:Available(name)   -> todo lo que ese personaje puede ofrecer
	    ns.Skills:Slots(name)       -> los huecos configurados, 1..6, con agujeros
	    ns.Skills:SetSlot(name,i,id)-> configurar uno (nil lo vacia)
	    ns.Skills:Use(name, i)      -> lanzar el hueco i de ese personaje
	    ns.Skills:Subscribe(fn)     -> aviso de que algo cambio

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
		w = { spells = {}, actions = {} }
		hall.who[name] = w
	end
	return w
end

-- Los huecos de un personaje, ya resueltos a hechizo. Devuelve una lista de
-- `n` posiciones donde cada una es una tabla o nil.
--
-- SIN CONFIGURAR, LOS PRIMEROS DE SU BARRA. Ver la cabecera: un hueco vacio
-- nada mas seleccionar a alguien se lee como que la barra no funciona.
function K:Slots(name, n)
	name = name or ns.Selection:GetPrimary()
	n = n or ns.Hall.shown or K.MAX_SLOTS

	local cat = self:Available(name)
	local byId = {}
	for _, s in ipairs(cat) do byId[s.spellId] = s end

	local w = Store(name, false)
	local cfg = w and w.spells

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
	         type = DEFAULT_TYPE, stale = stale or nil }
end

function K:SetSlot(name, i, spellId)
	if not name or not i then return end
	local w = Store(name, true)
	if not w then return end

	-- La primera vez que se toca un hueco hay que CONGELAR lo que se estaba
	-- ensenando, o cambiar el hueco 3 borraria el 1, el 2 y el 4 -- que eran
	-- los primeros de la barra y no estaban guardados. Es el fallo clasico de
	-- pasar de un valor derivado a uno guardado.
	if not next(w.spells) then
		local shown = self:Slots(name, self.MAX_SLOTS)
		for k = 1, self.MAX_SLOTS do
			if shown[k] then w.spells[k] = shown[k].spellId end
		end
	end

	w.spells[i] = spellId and tonumber(spellId) or nil
	Notify()
end

function K:ClearSlots(name)
	local w = Store(name, false)
	if not w then return end
	w.spells = {}
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
			w.actions = type(w.actions) == "table" and w.actions or {}
			for i, id in pairs(w.spells) do
				local n = tonumber(i)
				if not n or n < 1 or n > self.MAX_SLOTS or
				   not tonumber(id) or not GetSpellInfo(tonumber(id)) then
					w.spells[i] = nil
					malos = malos + 1
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

--- Apuntar -----------------------------------------------------------------
--
-- EL GESTO DE §5 DEL BRIEF. Pulsar un hechizo que necesita objetivo no lo
-- manda: lo deja ARMADO, con la luz circular de las mascotas recorriendo el
-- icono, y el siguiente click elige sobre quien -- en la lista de personajes o
-- en el mundo 3D, indistintamente.
--
-- Con Alt va sobre el propio personaje sin preguntar, que es la convencion de
-- siempre en WoW y la del video. Con un objetivo ya apuntado se manda ya,
-- porque preguntar cuando la respuesta esta delante es una pulsacion de mas.

function K:Use(name, i)
	name = name or ns.Selection:GetPrimary()
	local s = self:Slots(name)[i]
	if not s then
		if self:Pending(name) then
			ns.Print("|cff888888habilidades:|r pidiendo la barra de " .. name .. "...")
		end
		return
	end

	local letter = s.type or self:TypeOf(s.spellId, name)
	local info = self:TypeInfo(letter)

	if IsAltKeyDown() or not info.ask then
		local guid = IsAltKeyDown() and UnitGUID(ns.Selection:UnitFor(name) or "player") or nil
		Fire(name, s.spellId, guid)
		ns.Print(("|cff33ccff%s|r -> %s%s"):format(name, s.name,
			guid and " (sobre si)" or ""))
		return
	end

	-- Con algo ya apuntado no se pregunta... salvo que sea del bando
	-- equivocado. AVISA Y NO BLOQUEA: `IsPositive()` se apoya en atributos que
	-- el nucleo corrige a mano y no es infalible, asi que negarse en redondo
	-- podria dejar un hechizo inservible por una clasificacion mala.
	if UnitExists("target") then
		local hostil = UnitCanAttack("player", "target")
		if info.friendly ~= nil and info.friendly == hostil then
			ns.Print(("|cffff8800%s|r es %s y tu objetivo no lo parece. " ..
			          "Elige otro, o pulsa otra vez para mandarlo igual."):format(
				s.name, info.label))
			if self.warned ~= s.spellId then
				self.warned = s.spellId
				aiming = { owner = name, slot = i, spellId = s.spellId,
				           name = s.name, type = letter, at = GetTime() }
				Notify()
				return
			end
		end
		self.warned = nil
		Fire(name, s.spellId, UnitGUID("target"))
		ns.Print(("|cff33ccff%s|r -> %s sobre %s"):format(name, s.name, UnitName("target")))
		return
	end

	aiming = { owner = name, slot = i, spellId = s.spellId, name = s.name,
	           type = letter, at = GetTime() }
	ns.Print(("|cffffd100%s|r (%s): elige objetivo con el click izquierdo; " ..
	          "el derecho cancela."):format(s.name, info.label))
	Notify()
end

function K:Aiming()
	return aiming
end

function K:CancelAim()
	if not aiming then return false end
	aiming = nil
	self.warned = nil
	Notify()
	return true
end

-- Llamada desde `RTSMode` (mundo) y desde `Party` (la lista) cuando hay una
-- habilidad armada y pinchas algo. Un guid vacio la cancela: pinchar el suelo
-- con algo armado significa "olvida".
function K:AimAt(guid, label)
	if not aiming then return false end
	local a = aiming
	aiming = nil
	self.warned = nil

	if not guid then
		ns.Print("|cff888888" .. a.name .. ": cancelada.|r")
		Notify()
		return true
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
	local n = ns.Hall.shown or K.MAX_SLOTS
	local slots = self:Slots(name, n)
	ns.Print(("habilidades de |cff33ccff%s|r: %d huecos%s"):format(
		name, n, self:Pending(name) and " (pidiendo...)" or ""))
	for i = 1, n do
		local s = slots[i]
		if s then
			ns.Print(("  %d. %s (%d) |cff888888%s%s|r"):format(
				i, s.name, s.spellId, s.type or "?", s.stale and " -- ya no en su barra" or ""))
		else
			ns.Print(("  %d. |cff666666vacio|r"):format(i))
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
