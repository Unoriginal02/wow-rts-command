--[[
	Skills.lua -- las habilidades del personaje primario, y lanzarlas.

	=== ESTE FICHERO NO DIBUJA NADA, Y ESO ES LA DECISION ===================

	El centro de la consola (la "sala") se vacio el 2026-09-02 para redisenarlo,
	y ese rediseno no esta hecho. Escribir aqui una fila de botones seria
	predecidirlo -- la sala nueva naceria con seis huecos de habilidad de tal
	tamano porque estaban puestos, no porque se hubieran elegido. Es exactamente
	lo que se evito al borrar `HERO_W`, `PARTY_W` y compania de `Bar.lua`.

	Asi que aqui viven los DATOS y las ACCIONES, y quien los pinte los pintara
	cuando la sala se decida:

	    ns.Skills:Slots()        -> { {spellId, name, texture}, ... }
	    ns.Skills:Use(i)         -> lanzar el hueco i
	    ns.Skills:Subscribe(fn)  -> aviso de que la lista cambio

	Mientras tanto ya es utilizable: las teclas 1..6 llaman a `Use`, que es como
	se usa de verdad en el video.

	=== DE DONDE SALEN LOS HECHIZOS DE UN BOT ==============================

	De SU barra de acciones, no de tu libro. Tu libro solo tiene TUS hechizos --
	la Polimorfia del mago no esta ahi porque no la conoces -- asi que
	"arrastrar del libro de hechizos" es imposible para un bot y no es rodeable.
	La barra del bot ademas es la lista BUENA: son los hechizos que tu pusiste
	ahi jugandolo.

	Lo contesta el servidor con el verbo `BARS`, que existe desde la etapa 5n y
	sigue compilado.

	=== DOS TRAMPAS DEL CLIENTE, LAS DOS YA PAGADAS ========================

	1. `HasServer()` ES FALSO DURANTE EL PRIMER SEGUNDO, aunque mod-rts este
	   delante: se pone a cierto con la PRIMERA respuesta. Pedir la barra en ese
	   instante encontraba el canal cerrado y no se reintentaba nunca -- un
	   desplegable eternamente en "pidiendo su barra". Se usa
	   `Link:WhenServer`, que es ese bucle escrito una sola vez.

	2. `GetActionInfo` NO GARANTIZA DEVOLVER UN ID DE HECHIZO. Puede devolver el
	   INDICE DEL LIBRO, y pasarle un indice a `GetSpellInfo` **no da error**:
	   devuelve otro hechizo cualquiera, con nombre e icono. De ahi los
	   "hechizos raros" de la etapa 5o. Aqui solo afecta a TU propia barra (la
	   del bot viene del servidor y son ids de verdad), y se contrasta contra
	   `GetActionTexture`, que es la unica fuente que no puede mentir porque es
	   literalmente el dibujo que hay en pantalla.
]]

local ADDON, ns = ...

local K = {}
ns.Skills = K

local MAX_SLOTS = 6      -- los "six quick items" del video

--- Estado ------------------------------------------------------------------

-- name -> { ids = {spellId,...}, at = GetTime(), pending = bool }
local bars = {}
local listeners = {}
local aiming = nil       -- { slot } mientras se espera a que elijas objetivo

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
local function MyBar()
	local ids, seen = {}, {}

	for slot = 1, 120 do
		local kind, id = GetActionInfo(slot)
		if kind == "spell" and id and id > 0 and not seen[id] then
			local name, _, icon = GetSpellInfo(id)
			local shown = GetActionTexture(slot)
			if name and icon and shown and icon == shown then
				seen[id] = true
				table.insert(ids, id)
				if #ids >= MAX_SLOTS * 4 then break end
			end
		end
	end

	return ids
end

--- Pedir la del primario ---------------------------------------------------

function K:Request(name)
	if not name or name == "" then return end

	if name == ns.MyName() then
		bars[name] = { ids = MyBar(), at = GetTime() }
		Notify()
		return
	end

	local b = bars[name] or {}
	bars[name] = b
	b.pending = true

	-- `WhenServer` y no `HasServer` a secas: ver la trampa 1 de la cabecera.
	ns.Link:WhenServer(function(ok)
		if not ok then
			b.pending = false
			b.ids = {}
			Notify()
			return
		end
		b.ids = nil
		b.staging = {}
		ns.SendServer("BARS " .. name)
	end)
end

function K:Refresh()
	self:Request(ns.Selection:GetPrimary())
end

--- Lo que hay --------------------------------------------------------------

-- `{ { spellId, name, texture }, ... }`, como mucho `MAX_SLOTS`. La lista vacia
-- es una respuesta valida: un bot sin barra guardada no tiene nada que ofrecer.
function K:Slots()
	local name = ns.Selection:GetPrimary()
	local b = bars[name]
	if not b or not b.ids then return {} end

	local out = {}
	for _, id in ipairs(b.ids) do
		local sname, _, icon = GetSpellInfo(id)
		if sname then
			table.insert(out, { spellId = id, name = sname, texture = icon })
			if #out >= MAX_SLOTS then break end
		end
	end
	return out
end

function K:Owner()
	return ns.Selection:GetPrimary()
end

function K:Pending()
	local b = bars[ns.Selection:GetPrimary()]
	return b and b.pending or false
end

--- Lanzar ------------------------------------------------------------------

-- `CastSpellByName` esta PROTEGIDA en 3.3.5a, y un boton seguro tampoco vale:
-- su contenido cambia con el primario y cambiar los atributos de un boton
-- seguro esta bloqueado EN COMBATE, que es justo cuando se usa. Los dos caminos
-- van por el servidor -- `CAST` para un bot, `SELFCAST` para ti -- que ademas
-- los hace de la misma forma en vez de tener dos mecanismos.
local function Fire(spellId, guid)
	local owner = ns.Selection:GetPrimary()
	local hex = guid and (tostring(guid):gsub("^0[xX]", "")) or nil

	if owner == ns.MyName() then
		ns.SendServer("SELFCAST " .. spellId .. (hex and (" " .. hex) or ""))
	else
		ns.SendServer("CAST " .. owner .. " " .. spellId .. (hex and (" " .. hex) or ""))
	end
end

-- Pulsar una habilidad PREGUNTA a quien; con Alt va sobre ti directamente.
--
-- Es la convencion del video (*"if I hit two, it's going to ask me who I want
-- to cast this on. If instead I hold alt and hit two, you would see it autocast
-- onto me"*) y es la de siempre en WoW, asi que se entiende sola.
--
-- SIN Alt no se manda nada todavia: queda ARMADA, y el siguiente click en el
-- mundo o en la consola elige el objetivo. Con un objetivo ya apuntado se manda
-- ya, porque preguntar cuando la respuesta esta delante es una pulsacion de mas.
function K:Use(i)
	local slots = self:Slots()
	local s = slots[i]
	if not s then
		if self:Pending() then
			ns.Print("|cff888888habilidades:|r pidiendo la barra de " .. self:Owner() .. "...")
		end
		return
	end

	if IsAltKeyDown() then
		Fire(s.spellId, UnitGUID("player"))
		ns.Print(("|cff33ccff%s|r -> %s (sobre ti)"):format(self:Owner(), s.name))
		return
	end

	if UnitExists("target") then
		Fire(s.spellId, UnitGUID("target"))
		ns.Print(("|cff33ccff%s|r -> %s sobre %s"):format(self:Owner(), s.name, UnitName("target")))
		return
	end

	aiming = { slot = i, spellId = s.spellId, name = s.name, at = GetTime() }
	ns.Print(("|cffffd100%s:|r elige objetivo con el click izquierdo; el derecho cancela."):format(s.name))
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

-- Llamada desde `RTSMode` cuando hay una habilidad armada y pinchas algo. Un
-- guid vacio la cancela: pinchar el suelo con algo armado significa "olvida".
function K:AimAt(guid, label)
	if not aiming then return false end
	local a = aiming
	aiming = nil

	if not guid then
		ns.Print("|cff888888" .. a.name .. ": cancelada.|r")
		Notify()
		return true
	end

	Fire(a.spellId, guid)
	ns.Print(("|cff33ccff%s|r -> %s sobre %s"):format(self:Owner(), a.name, label or "eso"))
	Notify()
	return true
end

--- El canal ----------------------------------------------------------------

function K:Create()
	if self.created then return end
	self.created = true

	ns.Link:On("BARS", function(rest)
		-- DOS SENTIDOS: mandamos "BARS <nombre>" y nos lo oimos de vuelta. La
		-- respuesta trae un segundo campo con la lista (o "-" si esta vacia).
		local name, payload = rest:match("^(%S+)%s+(%S.*)$")
		if not name then return end

		local b = bars[name]
		if not b then return end
		b.staging = b.staging or {}
		if payload == "-" then return end

		for id in payload:gmatch("%d+") do
			table.insert(b.staging, tonumber(id))
		end
	end)

	ns.Link:On("BARSEND", function(rest)
		local name = rest:match("^(%S+)$")
		if not name then return end
		local b = bars[name]
		if not b then return end
		b.ids = b.staging or {}
		b.staging = nil
		b.pending = false
		b.at = GetTime()
		Notify()
	end)

	-- Cambiar de primario cambia la barra.
	ns.Selection:Subscribe(function()
		local who = ns.Selection:GetPrimary()
		if who ~= K.lastOwner then
			K.lastOwner = who
			K:Request(who)
		end
	end)

	-- Y LA PRIMERA VEZ, QUE NO ES UN CAMBIO.
	--
	-- Esto faltaba y es el fallo de `PRUEBAS-20` C1: sin ninguna seleccion
	-- todavia, `GetPrimary()` cae a tu personaje -- correctamente -- pero nadie
	-- habia pedido su barra, asi que `Slots()` devolvia vacio y `/rts skills`
	-- decia *"nada. Un bot sin barra de accion guardada no ofrece hechizos"*.
	--
	-- El mensaje era el equivocado y esa es la parte que vale: hablaba de un BOT
	-- cuando el primario era el jugador, y de "barra guardada" cuando el
	-- problema era que no se habia leido ninguna. Un diagnostico que nombra la
	-- causa que no es cuesta mas que uno que calla.
	K.lastOwner = ns.Selection:GetPrimary()
	K:Request(K.lastOwner)
end

function K:Report()
	local slots = self:Slots()
	ns.Print(("habilidades de |cff33ccff%s|r: %d%s"):format(
		self:Owner(), #slots, self:Pending() and " (pidiendo...)" or ""))
	for i, s in ipairs(slots) do
		ns.Print(("  %d. %s (%d)"):format(i, s.name, s.spellId))
	end
	if #slots == 0 and not self:Pending() then
		if self:Owner() == ns.MyName() then
			ns.Print("  |cff888888nada en tus casillas de accion. Pon hechizos en la barra " ..
			         "y vuelve a mirar.|r")
		else
			ns.Print("  |cff888888nada: ese bot no tiene barra de acciones guardada. " ..
			         "Entra con el una vez y colocale hechizos.|r")
		end
	end
end
