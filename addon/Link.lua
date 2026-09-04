--[[
	Link.lua -- el canal addon <-> mod-rts. Los dos sentidos, en un sitio.

	=== POR QUE EXISTE ESTE FICHERO ==========================================

	Hasta 2026-09-02 todo esto vivia dentro de `Camera.lua`, por historia: la
	camara fue lo primero que hablo con mod-rts y el canal se quedo donde nacio.
	Funcionaba, y aun asi era el mayor freno del addon para crecer -- **cada
	verbo nuevo, de cualquier modulo, obligaba a editar el fichero de la
	camara**, que es el que menos tiene que ver con casi todos ellos. Cuando la
	sala se lleno (siete verbos) se edito `Camera.lua`; cuando se vacio, otra
	vez.

	Ahora la camara es un cliente mas de este canal, igual que `Orders`,
	`Route`, `Marks` y `RTSMode`.

	=== EL TRANSPORTE, QUE NO ES OBVIO ======================================

	Mensajes de addon susurrados A UNO MISMO:

	    SendAddonMessage("RTS", "CAM ON", "WHISPER", ns.MyName())

	Susurrarse a si mismo es lo que hace que esto funcione en solitario.
	`LANG_ADDON` solo es legal en PARTY, RAID, GUILD, BATTLEGROUND y WHISPER --
	un canal privado no es una opcion.

	CON GRUPO SE MANDA POR PARTY, desde 2026-09-03, porque el susurro depende de
	saber como te llamas y despues de un cambio de personaje eso no es cierto
	(ver `L:Send`). Este fichero decia que PARTY no valia porque *"el chat de
	grupo es donde mod-playerbots lee SUS propios comandos"*, y **eso no aplica a
	un mensaje de addon**: `PlayerbotAI.cpp:604` sale con `type == CHAT_MSG_ADDON`
	y `:610` sale otra vez con `lang == LANG_ADDON`, cada uno con su comentario
	diciendo justo eso. La objecion era buena para texto plano y se aplico de mas.

	Y una consecuencia que decide medio fichero: **oimos nuestras propias
	peticiones de vuelta**, porque nos las susurramos nosotros. CINCO verbos se
	dicen igual en los dos sentidos (`CAM`, `POS`, `WHAT`, `MARKQ`, `BAGS`), asi
	que un manejador tiene que validar SU PROPIO FORMATO y descartar el eco --
	que es justo lo que hacia la cadena de expresiones regulares de antes sin que
	se notara. Ver `REPLY_ONLY` mas abajo, que es la otra mitad de esto.

	El de `BAGS` se distingue por el NUMERO DE CAMPOS: la peticion es
	`BAGS <nombre>` y la respuesta `BAGS <nombre> <trozo>`. El de `NPCQ`, por una
	LETRA DE TIPO: la peticion es `NPCQ <guid>` y la respuesta
	`NPCQ <guid> Q|S ...`. Cada verbo nuevo de doble sentido tiene que traer su
	propio discriminante escrito, porque el generico -- "casa con un manejador"
	-- vale para los dos sentidos por construccion.

	=== EL REPARTO: POR VERBO, NO POR EXPRESION REGULAR =====================

	La version anterior probaba doce expresiones regulares completas en orden
	hasta que una casaba. Aqui se corta la primera palabra y se busca en una
	tabla; el manejador recibe EL RESTO y se encarga de su propio formato, que
	es donde tiene que estar -- quien sabe leer `MARKAT` es `Marks`.

	Ademas de ser mas barato, da algo que la cadena no podia dar:

	**UN VERBO SIN MANEJADOR SE PUEDE DECIR.** En la cadena, un mensaje que no
	casaba con ninguna de las doce caia al final y se ignoraba en silencio --
	indistinguible de un mensaje que nunca llego. `/rts debug` lo dice ahora, y
	eso importa justo ahora: mod-rts sigue contestando siete verbos de la sala
	borrada (`BARS`, `ROLES`, `PFOCUS`, `TGTS`...) que se van a volver a usar al
	redisenarla. Enterarse de que la respuesta LLEGA y no la escucha nadie es la
	diferencia entre un minuto y una ronda de pruebas.

	=== `HasServer` ES UNA PROMESA, NO UN HECHO =============================

	`serverSeen` se pone a cierto con la PRIMERA respuesta de mod-rts, o sea que
	es falso durante el primer segundo -- **teniendo mod-rts delante**. Preguntar
	en ese instante elige el camino de respaldo y se lee como que el arreglo no
	se aplico.

	Eso ya tropezo cuatro veces (el botin de la etapa 5m, el recordatorio de
	`Marks`, y las filas de habilidades y roles de la 5n), y las cuatro se
	arreglaron con el mismo bucle copiado. `WhenServer` es ese bucle, una vez.
]]

local ADDON, ns = ...

local L = {}
ns.Link = L

local PREFIX = "RTS"

-- Puesto por la PRIMERA respuesta del servidor, sea cual sea. Cualquier
-- respuesta prueba que mod-rts esta instalado y escuchando, que es lo que deja
-- a `Orders` mandar por aqui en vez de pagar un susurro de chat por bot.
L.serverSeen = false
L.serverVersion = nil

-- `/rts debug` saca los dos sentidos. Un click derecho que no hace nada puede
-- fallar en cuatro sitios -- el manejador, el envio, la clasificacion del
-- servidor o la orden misma -- y estrechar eso un paso por ciclo de pruebas ha
-- sido la parte mas lenta de todo este proyecto.
L.debug = false

local handlers = {}
local frame

--- Salida ------------------------------------------------------------------

-- EL SUSURRO A UNO MISMO DEPENDE DE SABER COMO TE LLAMAS, y despues de un
-- cambio de personaje eso no es cierto.
--
-- Visto en juego 2026-09-03: justo despues de cambiar salieron dos
-- *"No hay ningun jugador con el nombre Avy"* seguidos. Eran `PORTED` y
-- `WHOAMI`, o sea **los dos mensajes de los que depende el propio cambio** --
-- por eso el servidor decia "tu cliente no confirmo la recarga" y esperaba doce
-- segundos, y por eso el addon no se enteraba de su nombre nuevo. Un canal que
-- se cae precisamente en el momento que tiene que cubrir.
--
-- La cura es no necesitar el nombre: `LANG_ADDON` es legal en PARTY, y mod-rts
-- lee por `OnPlayerBeforeSendChatMessage`, que ve todos los tipos por igual --
-- el susurro no tenia nada de especial, era solo la forma de hablar estando
-- solo. Con grupo va por PARTY y no hay nombre que acertar; sin grupo se
-- susurra como siempre.
--
-- No molesta a playerbots: sus ordenes de chat son texto plano y esto es un
-- mensaje de addon con prefijo propio, que su lector ignora.
function L:Send(body)
	if self.debug then ns.Print("|cff888888-> " .. body .. "|r") end

	if (GetNumPartyMembers() or 0) > 0 then
		SendAddonMessage(PREFIX, body, "PARTY")
	else
		SendAddonMessage(PREFIX, body, "WHISPER", ns.MyName())
	end
end

-- El nombre viejo, que usan `Orders`, `Route`, `Marks` y `RTSMode`. Se queda
-- como funcion suelta a proposito: es el verbo mas usado del addon y
-- `ns.SendServer("POS")` se lee mejor que `ns.Link:Send("POS")` en medio de
-- codigo que no tiene nada que ver con el transporte.
function ns.SendServer(body)
	L:Send(body)
end

--- Entrada -----------------------------------------------------------------

-- `fn(rest, verb)`. `rest` es todo lo que va detras de la primera palabra, sin
-- el espacio, o "" si el verbo venia solo (`TGTEND`).
--
-- Varios manejadores por verbo estan permitidos y se llaman en orden de
-- registro. No hace falta hoy, pero la alternativa -- que el segundo pisara al
-- primero en silencio -- es la clase de fallo que cuesta una tarde.
function L:On(verb, fn)
	handlers[verb] = handlers[verb] or {}
	table.insert(handlers[verb], fn)
end

function L:HasServer()
	return self.serverSeen == true
end

--- Esperar al servidor -----------------------------------------------------

-- Llama a `fn` en cuanto mod-rts conteste, o al vencer el plazo -- lo que pase
-- antes. Si ya ha contestado, llama YA, en la misma vuelta.
--
-- EL PLAZO NO ES UN DETALLE: sin el, un servidor sin mod-rts dejaria la tarea
-- colgada para siempre y el camino de respaldo por chat no se aplicaria nunca.
-- 2,5 s es lo que ya usaban las cuatro copias que esto sustituye.
--
-- `fn` recibe `true` si el servidor contesto y `false` si vencio el plazo, para
-- que quien tenga camino de respaldo pueda elegirlo. Las cuatro copias
-- anteriores no lo distinguian y por eso todas acababan preguntando otra vez.
-- LOS FRAMES SE REUTILIZAN. Un frame de WoW no se puede destruir, y sin
-- mod-rts instalado CADA entrada en modo RTS crearia uno que gira 2,5 s y se
-- queda muerto para siempre. Con servidor no se crea ninguno -- se sale por la
-- primera linea -- asi que esto solo importa en el caso que mas se repite: el
-- que no tiene servidor.
local pool = {}

function L:WhenServer(fn, timeout)
	if self:HasServer() then fn(true) return end

	local w = table.remove(pool) or CreateFrame("Frame")
	w.acc = 0
	w.limit = timeout or 2.5
	w.fn = fn
	w:SetScript("OnUpdate", function(f, e)
		f.acc = f.acc + e
		local ok = L:HasServer()
		if not ok and f.acc <= f.limit then return end

		f:SetScript("OnUpdate", nil)
		local call = f.fn
		f.fn = nil
		table.insert(pool, f)
		-- `pcall` por la misma razon que en `Selection:Notify` y en
		-- `Bar:OnLayout`: esto corre fuera de la pila de quien lo pidio, asi que
		-- un fallo aqui no tiene a nadie debajo que lo recoja -- se comeria el
		-- resto de la secuencia sin decir nada. Y el frame vuelve al pozo ANTES
		-- de llamar, para que siga reutilizandose aunque la llamada reviente.
		local good, err = pcall(call, ok)
		if not good then ns.Print("|cffff0000link:|r " .. tostring(err)) end
	end)
end

--- El frame ----------------------------------------------------------------

-- LOS VERBOS QUE SOLO PUEDEN VENIR DEL SERVIDOR, y esto NO es burocracia: es
-- la unica forma de saber que mod-rts esta ahi.
--
-- Nos susurramos a nosotros mismos, asi que **oimos de vuelta cada peticion que
-- mandamos**. Marcar `serverSeen` con cualquier mensaje entrante lo pondria a
-- cierto con nuestro propio `VERSION` rebotando, sin mod-rts instalado -- y
-- entonces `Orders` mandaria por un canal que no escucha nadie en vez de caer
-- al respaldo por chat. Silencioso y total.
--
-- Cuatro verbos se dicen igual en los dos sentidos (`CAM`, `POS`, `WHAT`,
-- `MARKQ`), asi que "casa con un manejador" tampoco vale como prueba: nuestro
-- propio `WHAT <guid>` casa con el manejador de `WHAT`. Lo que si es prueba es
-- un verbo que NOSOTROS no decimos nunca.
--
-- `VER` es el ancla y basta por si solo -- se pide en `Create` y contesta en el
-- primer segundo. Los demas estan por si `VERSION` falla algun dia: sobra uno,
-- no falta ninguno. Si se anade un verbo de respuesta y no se apunta aqui, lo
-- unico que pasa es que no adelanta la deteccion; nada se rompe.
local REPLY_ONLY = {
	VER = true, DID = true, CAMPOS = true,
	GROUNDAT = true, GROUNDNO = true,
	MARKAT = true, MARKERR = true, MARKNO = true,
	BAGEND = true, BAGOK = true, BAGERR = true,
	NPCQEND = true, QDONE = true, QERR = true,
	BARSEND = true, SWAPPED = true, IAM = true, MYBARS = true,
	CASTQ = true,
	CHAINAT = true, CHAINEND = true,
	TRAINEND = true, VENDEND = true, TRAINED = true,
	SOLD = true, REPAIRED = true, BOUGHT = true, NPCERR = true,
}

--- Que sabe hacer el servidor que hay puesto -------------------------------
--
-- `¿ES AL MENOS 0.<minor>.0?`. Existe porque un verbo nuevo contra un mod-rts
-- viejo **no da error: no contesta**, y eso se ve como un boton que no hace
-- nada. Con esto el addon puede caer al verbo antiguo en vez de quedarse mudo,
-- que es lo que separa "el servidor esta desactualizado" de "esto esta roto".
--
-- Sin respuesta todavia devuelve `false`, que es lo prudente: el respaldo
-- siempre existe, el verbo nuevo no siempre.
function L:ServerAtLeast(minor)
	local v = self.serverVersion
	if not v then return false end
	local a, b = v:match("^(%d+)%.(%d+)")
	if not a then return false end
	a, b = tonumber(a), tonumber(b)
	if a > 0 then return true end
	return b >= (tonumber(minor) or 0)
end

-- El aviso sale UNA vez, no en cada mensaje.
local function NoteServer(verb)
	if L.serverSeen or not REPLY_ONLY[verb] then return end
	L.serverSeen = true
	ns.Print("|cff00ff00server module attached|r - direct orders enabled.")
end

local function Dispatch(message)
	local verb, rest = message:match("^(%S+)%s*(.*)$")
	if not verb then return end

	NoteServer(verb)

	local list = handlers[verb]
	if list then
		for _, fn in ipairs(list) do
			-- `pcall` por la misma razon que en `Selection:Notify` y en
			-- `Bar:OnLayout`: un manejador que reviente no puede llevarse por
			-- delante a los demas ni matar el canal para el resto de la sesion.
			local ok, err = pcall(fn, rest, verb)
			if not ok then ns.Print("|cffff0000link " .. verb .. ":|r " .. tostring(err)) end
		end
	elseif L.debug then
		-- Ver la cabecera: esto es lo que la cadena de expresiones regulares no
		-- podia decir. Solo con `/rts debug`, porque oimos nuestras propias
		-- peticiones de vuelta y sin filtrar seria una linea por envio.
		ns.Print("|cffffff00<- sin manejador:|r " .. verb)
	end
end

function L:Create()
	if frame then return end

	frame = CreateFrame("Frame", "RTSLink")
	frame:RegisterEvent("CHAT_MSG_ADDON")
	frame:SetScript("OnEvent", function(_, _, prefix, message)
		if prefix ~= PREFIX or type(message) ~= "string" then return end
		if L.debug then ns.Print("|cff888888<- " .. message .. "|r") end
		Dispatch(message)
	end)

	-- LA VERSION DEL MODULO DE SERVIDOR ES DE AQUI, no de la camara. Es lo que
	-- deja comprobar las tres piezas de una vez (`/rts version`) en vez de que
	-- la del DLL haga de sustituta de todo el proyecto.
	self:On("VER", function(rest)
		local v = rest:match("^(%S+)")
		if v then L.serverVersion = v end
	end)

	-- Se pregunta en vez de suponer, y ademas es lo que marca `serverSeen` en un
	-- arranque normal: se pide aqui, contesta en el primer segundo, y a partir
	-- de ahi las ordenes van por este canal en vez de por chat.
	self:Send("VERSION")
end
