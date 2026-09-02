--[[
	Marks.lua -- los marcadores de ruta que dibuja EL CLIENTE, no nosotros.

	Todo lo que este addon ha puesto "en el mundo" hasta ahora era una textura
	de interfaz aparcada en el pixel donde cae la proyeccion: sin profundidad,
	dibujada encima de la colina que deberia taparla, y nadando de lado cada vez
	que gira la camara. Los efectos de verdad que tiene el cliente -- el circulo
	de seleccion, el brillo del modelo, las placas de vida -- son todos POR
	UNIDAD y necesitan un GUID del que colgar. Un punto de ruta es suelo pelado.

	La excepcion es el `DynamicObject`: vive en una posicion cualquiera del
	mundo y el cliente le pinta encima el visual persistente de su hechizo, en
	su propio bucle de dibujo y con profundidad correcta. Es lo que son las
	manchas de Consagracion o de Muerte y Descomposicion. Asi que el marcador no
	lo dibujamos: colocamos un objeto y lo dibuja el cliente -- el mismo trato
	que hizo funcionar las placas de vida en la etapa 5e.

	QUE HECHIZO es una pregunta para el OJO, no para el codigo: cada visual
	tiene su tamano, su color y su animacion, y una lista de ids escrita de
	memoria es justo la clase de constante que en este proyecto no dibuja nada
	sin dar error. Por eso:

	  * la lista de candidatos la construye el SERVIDOR a partir del almacen de
	    hechizos ya cargado -- todos los que tienen efecto de aura de area
	    persistente, que son exactamente aquellos para los que el cliente tiene
	    un visual de suelo;
	  * y aqui vive la herramienta para recorrerla en vivo, `/rts mark`, con los
	    marcadores de la ruta ya puesta cambiando debajo mientras se pasa de uno
	    a otro.

	Cuando haya un ganador, se fija con `/rts mark <id>` y `/rts mark size <n>`,
	que es lo que queda guardado; hardcodearlo es cambiar los valores por
	defecto de `M.cfg`.

	EL SLOT NO ES LA POSICION EN LA RUTA, ES UNA IDENTIDAD. Si el slot fuera "el
	tercero de los que quedan", pisar el primer punto renumeraria todos los
	demas y habria que recolocar la ruta entera en cada llegada. Cada punto
	nace con un numero propio que no cambia, asi que llegar a uno es una sola
	orden de quitar.
]]

local ADDON, ns = ...

local M = {}
ns.Marks = M

-- Sube cuando un valor de fabrica cambia de forma que lo guardado por una
-- version anterior ya no representa una decision del jugador. Sin esto, apagar
-- las marcas por defecto no habria apagado nada en el unico cliente que
-- importa: el que ya tiene `on = 1` guardado de ayer.
local CFG_VERSION = 2


-- El aspecto elegido. Se guarda porque el servidor lo pierde al desconectar:
-- el addon es donde ya persisten los ajustes por personaje, asi que es el addon
-- quien se lo recuerda al servidor en cada sesion.
--
-- LOS VALORES DE FABRICA SON LOS ELEGIDOS MIRANDOLOS EN JUEGO: "Shield of the
-- Blue" (45848) a una decima de su tamano original. Estan aqui como PUNTO DE
-- PARTIDA, no como constante: la herramienta sigue recorriendo la lista entera.
--
-- APAGADOS DE FABRICA DESDE 2026-08-23, y el motivo es la ANIMACION.
--
-- Con `obj 0.1` el tamano en reposo era el bueno, pero al aparecer la marca
-- pegaba un estallido enorme. Eso es el visual del hechizo naciendo: cada
-- visual persistente trae su propia animacion de entrada, y esa animacion vive
-- en el cliente, en el kit del hechizo. El servidor decide DONDE, CUAL y CUANTO
-- de grande -- radio y escala -- pero no puede decirle al cliente que se salte
-- una animacion, ni empezarla a medias, ni acortarla. No hay campo para eso.
--
-- O sea que lo unico que quedaba era buscar entre los 572 visuales uno que
-- naciera quieto, y eso es una caza a ciegas de las que este proyecto ya ha
-- pagado varias. Con los aros de la ruta cumpliendo, no vale la pena: se apaga
-- y la herramienta se queda entera para cuando alguien quiera volver a mirar.
-- `/rts mark on` los enciende.
M.cfg = {
	on    = 0,     -- 0 = sin marcadores en el mundo (solo el aro y el numero)
	spell = 45848, -- 0 = el primero de la lista del servidor
	size  = 0,     -- radio en yardas; 0 = automatico (1/10 del tamano del hechizo)
	obj   = 0.1,   -- escala del MODELO: 0.1 es la medida buena, vista en juego
	mode  = 0,     -- 0 el tamano lo mandamos nosotros, 1 lo decide el cliente
}

-- DOS MANDOS DE TAMANO PORQUE UNO NO BASTA, Y NO ES INDECISION.
--
-- `size` es DYNAMICOBJECT_RADIUS, que es una PETICION: el cliente decide si el
-- visual de suelo que sea se estira con ese radio, y para el que no, todo lo
-- que mandemos se guarda, se contesta y se ignora -- que en pantalla se lee
-- como "el mando no hace nada" y no lo es. `obj` es OBJECT_FIELD_SCALE_X, la
-- escala del modelo, el mismo campo que hace grande o pequena a una criatura:
-- otro campo y otro camino, asi que un visual sordo a uno puede contestar al
-- otro. Cual escucha cada visual es cosa de mirarlo, no de razonarlo.

-- Lo ultimo que dijo el servidor. Se ensena tal cual: es la unica fuente
-- honesta de en que punto de la lista estamos.
M.at = { index = 0, total = 0, spell = 0, size = 0, mode = 0, placed = 0,
         own = 0, obj = 1, name = "?" }

local placed = {}      -- [slot] = true, lo que creemos que hay puesto
local TEST_SLOT = 9999 -- fuera del alcance de cualquier ruta real

local function Server()
	return ns.Orders and ns.Orders:HasServer()
end

local function Send(body)
	if Server() then ns.SendServer(body) end
end

--- Aspecto -----------------------------------------------------------------

-- Recordarle al servidor lo que tenemos guardado. Se llama al entrar en modo
-- RTS y cuando el servidor contesta por primera vez.
function M:Apply()
	if not Server() then return end
	if self.cfg.spell and self.cfg.spell > 0 then
		Send(("MARKSET spell %d"):format(self.cfg.spell))
	end
	-- El orden importa: el hechizo primero, porque el tamano automatico se
	-- deriva de EL. Al reves se derivaria del hechizo anterior.
	Send(("MARKSET size %.2f"):format(self.cfg.size))
	Send(("MARKSET obj %.2f"):format(self.cfg.obj))
	Send(("MARKSET mode %d"):format(self.cfg.mode))
end

local function Save()
	RTSCommandDB = RTSCommandDB or {}
	RTSCommandDB.marks = {
		v = CFG_VERSION,
		on = M.cfg.on, spell = M.cfg.spell, size = M.cfg.size,
		obj = M.cfg.obj, mode = M.cfg.mode,
	}
end

--- Colocar -----------------------------------------------------------------

-- Lo que hay que ver, contra lo que creemos que hay puesto. Solo se manda la
-- diferencia: un mensaje de addon por marcador y por vuelta seria mucho mas
-- trafico del que hace falta, y ademas el servidor tendria que rehacer objetos
-- que ya estan bien.
function M:Sync(list)
	if not Server() then return end

	if self.cfg.on == 0 then
		self:ClearAll()
		return
	end

	local want = {}
	for _, e in ipairs(list) do want[e.id] = e end

	for slot in pairs(placed) do
		if slot ~= TEST_SLOT and not want[slot] then
			Send(("MARKOFF %d"):format(slot))
			placed[slot] = nil
		end
	end

	for slot, e in pairs(want) do
		if not placed[slot] then
			Send(("MARK %d %.2f %.2f %.2f"):format(slot, e.x, e.y, e.z))
			placed[slot] = true
		end
	end
end

function M:ClearAll()
	if next(placed) == nil then return end
	Send("MARKOFF 0")
	placed = {}
end

-- El servidor se olvida de todo al desconectar o al cambiar de mapa (el nucleo
-- tira todos los dynobjects del jugador), asi que nuestra idea de lo que hay
-- puesto tiene que olvidarse tambien -- si no, `Sync` no volveria a mandar
-- nada porque cree que ya estan.
function M:Forget()
	placed = {}
end

-- Un punto que se ha MOVIDO despues de colocar su marca. El servidor fija la
-- posicion al crear el objeto y no la mueve sola, asi que hay que olvidarse de
-- esa marca para que el siguiente `Sync` la vuelva a poner en el sitio bueno.
function M:Redo(slot)
	if slot then placed[slot] = nil end
end

--- Respuestas del servidor -------------------------------------------------

function M:OnAt(index, total, spell, size, mode, count, own, obj, name)
	self.at = {
		index = index, total = total, spell = spell,
		size = size, mode = mode, placed = count, own = own,
		obj = obj or 1, name = name,
	}
	-- Lo que diga el servidor es lo que se guarda: si se pidio un hechizo que
	-- no existe, lo guardado seria una mentira que sobrevive al reinicio.
	--
	-- El TAMANO no: el servidor informa del efectivo, y guardarlo convertiria el
	-- automatico en un numero fijo en cuanto se pidiera el estado una vez -- y
	-- entonces cambiar de hechizo dejaria el tamano del anterior.
	self.cfg.spell, self.cfg.mode = spell, mode
	self.cfg.obj = self.at.obj
	Save()
end

function M:Report()
	local a = self.at
	ns.Print(("marcas: %s   |cffffff00%s|r (id %d)   %d/%d de la lista")
		:format(self.cfg.on == 1 and "|cff00ff00ON|r" or "|cffff0000OFF|r",
			a.name, a.spell, a.index + 1, a.total))
	ns.Print(("  radio |cffffff00%.2f|r de %.2f del hechizo (x%.2f)   " ..
		"escala del modelo |cffffff00x%.2f|r   puestas |cffffff00%d|r")
		:format(a.size, a.own, a.own > 0 and (a.size / a.own) or 0, a.obj or 1,
			a.placed))
	ns.Print(("  modo |cffffff00%d|r%s")
		:format(a.mode,
			a.mode == 1 and " |cffff8800-- el cliente decide el radio de casi " ..
				"todas las manchas de suelo e ignora el nuestro|r"
			             or " -- el cliente usa nuestro radio"))
	if not Server() then
		ns.Print("|cffff0000mod-rts no contesta|r: sin servidor no hay marcadores " ..
			"en el mundo, solo el numero.")
	end
	ns.Print("|cffffff00/rts mark next|prev|r recorre la lista, " ..
		"|cffffff00find <texto>|r busca, |cffffff00<id>|r va directo.")
	ns.Print("|cffffff00/rts mark size <yardas>|r o |cffffff00scale <fraccion>|r  " ..
		"|cffffff00mode 0|1|r  |cffffff00test|r pone una donde apuntas  " ..
		"|cffffff00list|r la lista.")
	-- SI EL TAMANO NO SE MUEVE, ES QUE EL VISUAL NO ESCUCHA AL RADIO. El otro
	-- mando escala el modelo y no pasa por esa decision del cliente.
	ns.Print("|cffffff00/rts mark obj <n>|r escala el MODELO (0.5 = la mitad). " ..
		"Es el mando de tamano que no depende del visual.")
	-- Y el aro con el numero que se ve en cada punto de la ruta NO es esto: es
	-- interfaz proyectada, con su propio mando. Dos cosas encima del mismo sitio.
	ns.Print("|cff888888El aro con el numero de cada punto es interfaz, no esta marca: " ..
		"su tamano es |cffffff00/rts route ring <yardas>|r|cff888888.|r")
end

-- Una pagina de la lista. Llega troceada y cada trozo dice desde donde va, asi
-- que no depende de que lleguen en orden.
function M:OnList(total, from, payload)
	local i = from
	for entry in payload:gmatch("[^;]+") do
		local id, name = entry:match("^(%d+)|(.*)$")
		if id then
			ns.Print(("  |cffffff00%4d|r  %s  |cff888888(id %s)|r"):format(i + 1, name, id))
		end
		i = i + 1
	end
	self.at.total = total
end

--- El mando ----------------------------------------------------------------

function M:Command(args)
	local sub, value = (args or ""):match("^(%S*)%s*(.*)$")
	sub = (sub or ""):lower()

	if sub == "" then
		-- Sin argumentos el servidor contesta el estado y `OnAt` lo imprime.
		if Server() then Send("MARKSET") else self:Report() end
		return
	end

	if sub == "on" or sub == "off" then
		self.cfg.on = (sub == "on") and 1 or 0
		Save()
		if self.cfg.on == 0 then self:ClearAll() end
		ns.Print("marcadores en el mundo: " ..
			(self.cfg.on == 1 and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		return
	end

	if not Server() then
		ns.Print("|cffff0000mod-rts no contesta|r: el ajuste de marcadores vive en " ..
			"el servidor.")
		return
	end

	if sub == "next" or sub == "prev" then
		Send(("MARKSET %s %s"):format(sub, value ~= "" and value or "1"))
	elseif sub == "size" then
		Send(("MARKSET size %s"):format(value))
	elseif sub == "scale" or sub == "escala" then
		-- El tamano como FRACCION del original, que es como se pide de verdad:
		-- "una decima de lo que mide" en vez de un numero de yardas que solo
		-- significa algo si ya sabes cuanto media.
		Send(("MARKSET scale %s"):format(value))
	elseif sub == "obj" or sub == "objeto" or sub == "modelo" then
		Send(("MARKSET obj %s"):format(value))
	elseif sub == "mode" then
		Send(("MARKSET mode %s"):format(value))
	elseif sub == "find" then
		Send(("MARKSET find %s"):format(value))
	elseif sub == "list" then
		local from = tonumber(value) or 0
		ns.Print(("lista de visuales, desde el %d:"):format(from + 1))
		Send(("MARKQ %d 20"):format(from))
	elseif sub == "test" then
		if value:lower() == "off" then
			Send(("MARKOFF %d"):format(TEST_SLOT))
			placed[TEST_SLOT] = nil
			return
		end
		local x, y, z = ns.Markers and ns.Markers:CursorGroundPoint()
		if not x then
			ns.Print("No se donde apunta el raton (hace falta rts_core y modo RTS).")
			return
		end
		Send(("MARK %d %.2f %.2f %.2f"):format(TEST_SLOT, x, y, z))
		placed[TEST_SLOT] = true
		ns.Print("marca de prueba puesta. |cffffff00/rts mark test off|r la quita.")
	elseif tonumber(sub) then
		Send(("MARKSET spell %d"):format(tonumber(sub)))
	else
		self:Report()
	end
end

--- Ciclo -------------------------------------------------------------------

function M:Create()
	-- LOS CUATRO VERBOS DE LAS MARCAS. Vivian en `Camera.lua` hasta 2026-09-02.
	-- El servidor contesta el estado ENTERO despues de cada cambio, asi que el
	-- addon nunca tiene que suponer que su peticion salio bien.
	ns.Link:On("MARKAT", function(rest)
		local mi, mt, msp, msz, mmo, mc, mow, mob, mn =
			rest:match("^(%d+) (%d+) (%d+) ([%d%.]+) (%d+) (%d+) ([%d%.]+) ([%d%.]+) (.*)$")
		if not mi then return end
		M:OnAt(tonumber(mi), tonumber(mt), tonumber(msp),
			tonumber(msz) or 0, tonumber(mmo) or 0, tonumber(mc) or 0,
			tonumber(mow) or 0, tonumber(mob) or 1, mn)
		M:Report()
	end)

	-- `MARKQ` se dice en los dos sentidos: la peticion va sola y la respuesta
	-- trae tres campos. Validar el formato es lo que descarta nuestro eco.
	ns.Link:On("MARKQ", function(rest)
		local qt, qf, qp = rest:match("^(%d+) (%d+) (.+)$")
		if qt then M:OnList(tonumber(qt), tonumber(qf), qp) end
	end)

	ns.Link:On("MARKERR", function(rest)
		local n = rest:match("^(%d+)$")
		if n then ns.Print("|cffff0000No se pudo poner la marca " .. n .. ".|r") end
	end)

	ns.Link:On("MARKNO", function(rest)
		ns.Print("|cffffff00Ningun visual se llama|r " .. rest)
	end)

	-- EL NUCLEO TIRA TODOS LOS DYNOBJECTS DEL JUGADOR AL CAMBIAR DE MAPA, asi
	-- que los marcadores de ruta ya no existen. Sin olvidarlo aqui, `M:Sync`
	-- creeria que siguen puestos y no volveria a mandarlos nunca.
	--
	-- Este evento lo escuchaba el frame del canal en `Camera.lua`, que era el
	-- unico sitio donde `Marks` no tenia nada que hacer. Ahora es suyo.
	local leave = CreateFrame("Frame", "RTSMarksEvents")
	leave:RegisterEvent("PLAYER_LEAVING_WORLD")
	leave:SetScript("OnEvent", function() M:Forget() end)

	local saved = RTSCommandDB and RTSCommandDB.marks
	if type(saved) == "table" then
		for k in pairs(self.cfg) do
			local n = tonumber(saved[k])
			if n then self.cfg[k] = n end
		end
		if (tonumber(saved.v) or 1) < CFG_VERSION then
			self.cfg.on = 0
			ns.Print("marcas de suelo apagadas (|cffffff00/rts mark on|r las devuelve).")
		end
	end
	-- Acotado AL LEERLO y no solo al escribirlo: unas SavedVariables viejas
	-- sobreviven a la version que las escribio, y un tamano de 688 guardado por
	-- una version anterior no lo arregla ningun `Set*` -- esos solo corren
	-- cuando el jugador teclea.
	-- El 0 es un valor VALIDO aqui: significa automatico. Acotarlo hacia arriba
	-- si, porque un 688 guardado por una version anterior no es una intencion.
	if self.cfg.size < 0 or self.cfg.size > 200 then self.cfg.size = 0 end
	if self.cfg.obj <= 0 or self.cfg.obj > 20 then self.cfg.obj = 1 end
	if self.cfg.mode ~= 1 then self.cfg.mode = 0 end
	if self.cfg.on ~= 0 then self.cfg.on = 1 end
end
