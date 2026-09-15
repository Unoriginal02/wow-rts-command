--[[
	Core.lua -- init, events, slash commands, binding entry points.
]]

local ADDON, ns = ...

local PREFIX = "|cff33ccffRTS|r "

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

-- HUBO AQUI UN `ns.IsOurs(frame)` Y SE FUE CON EL FALLO QUE LO PARIO.
--
-- Subia por los padres buscando un nombre que empezara por "RTS" para decidir
-- si un tooltip era de la consola. Existia porque el modo RTS esconde
-- `GameTooltip` -- correctamente, el tooltip de unidad del mundo es cromo de
-- Blizzard -- y lo hacia negandole el `OnShow` a TODO: `GameTooltip` es UNO
-- SOLO, el mismo objeto que dibuja "Lobo, nivel 8" es el que `W:Tip` usa para
-- los botones de la consola, asi que desde la etapa 5i hasta PRUEBAS-18 C4 la
-- barra de control no tuvo ni un tooltip.
--
-- La excepcion arreglaba la consola y dejaba fuera todo lo demas: el botin, el
-- vendedor, la ficha, el registro de misiones. `Chrome.lua` ya no pregunta de
-- quien es el tooltip sino DONDE esta el raton (`IsWorldTip`), y con eso esto
-- no tiene a quien servir.

local DEFAULTS = {
	groups = {},
}

--- Event plumbing ----------------------------------------------------------


--- El nombre que el cliente tiene de si mismo -------------------------------
--
-- ESTA CLAVADO EN UN BUFFER QUE SOLO ESCRIBE LA PANTALLA DE SELECCION, y por eso
-- despues de un cambio de personaje el marco de arriba sigue diciendo el nombre
-- anterior aunque seas otro de verdad -- con su equipo, su libro y su grupo.
--
-- No es una teoria. `UnitName` esta en `0x0060E740` y lo primero que hace es
-- comparar el argumento con la cadena "player" (`0x009F6F4C`):
--
--     0060E78B  call 0x76E780        ; strcmpi(unidad, "player")
--     0060E792  jne  0x60E7B3        ; no es "player" -> mirar el objeto
--     0060E794  call 0x6B1060        ; SI lo es -> devolver el nombre guardado
--     0060E79B  call 0x84E350        ; lua_pushstring(L, ese nombre)
--
-- Y `0x006B1060` son cinco instrucciones: devuelve la direccion `0x00C79D18` si
-- el primer byte no es cero. O sea que **para "player" el cliente no mira el
-- objeto ni el guid**: lee un buffer estatico que se rellena al entrar al mundo
-- desde la lista de personajes, que es exactamente el paso que este cambio se
-- salta.
--
-- Asi que no hay evento que lo arregle ni funcion de Blizzard que lo recalcule:
-- lo que ellos dibujan es el contenido de ese buffer. Se les repinta encima.
--
-- LA CURA DE RAIZ SERIA QUE `rts_core` ESCRIBIERA EL BUFFER -- es memoria
-- normal del cliente y el DLL ya escribe cosas mas delicadas -- y entonces
-- `UnitName("player")` diria la verdad y esto sobraria entero. Queda apuntado y
-- no hecho: cuesta un canal nuevo para pasarle una CADENA al DLL (el que hay es
-- un entero empaquetado) y una recompilacion, y esto son ocho lineas.
--
-- Se engancha `PlayerFrame_Update` porque Blizzard lo vuelve a poner en cada
-- evento suyo; un `SetText` de una vez duraria hasta el primer cambio de vida.
-- `hooksecurefunc` corre DESPUES de la suya, que es lo que hace que la ultima
-- palabra sea nuestra.
-- Lo que hay que repintar cuando cambias de personaje sin que el cliente lance
-- `PLAYER_ENTERING_WORLD`. Cada entrada esta aqui porque se vio vieja en juego,
-- no por si acaso: las barras de accion seguian con los hechizos del anterior y
-- pulsar una lanzaba algo que este ya no conoce.
--
-- Todo entre `pcall` y comprobando que la funcion exista: son funciones de
-- Blizzard, y una que cambie de nombre no puede llevarse por delante el resto
-- de la lista ni el mensaje que viene detras.
-- ¿EL CLIENTE ESTA DE ACUERDO EN QUE ERES ESE?
--
-- El servidor manda nombre Y guid, y esto los contrasta contra
-- `UnitGUID("player")` -- que sale del gestor de objetos del cliente y es la
-- unica identidad suya que no miente. Existe porque sin ella el aviso TAPABA el
-- fallo: un `SWAPPED Bob` hacia que la interfaz dijera "Bob" aunque el cliente
-- siguiera siendo Avy, y entonces lo unico raro eran los hechizos -- que se lee
-- como un problema de barras y no como que el cambio no se aplico. Al recargar,
-- que borra el nombre que dijo el servidor, volvia a salir "Avy" y ahi se veia.
--
-- Devuelve nil si el cliente todavia no ha contestado nada (no es un desacuerdo,
-- es que no hay dato).
local function ClientAgrees(guid)
	local mine = UnitGUID("player")
	if not mine or not guid then return nil end
	return tonumber(mine) == tonumber(guid)
end

function ns.RefreshAfterSwap()
	local function Try(fn, ...)
		if type(fn) == "function" then pcall(fn, ...) end
	end

	-- Las barras de accion, que es lo que se reporto. Los botones leen
	-- `GetActionInfo`, y esos datos SI son los nuevos -- llegan en la rafaga de
	-- login -- asi que basta con pedirles que se vuelvan a leer.
	local bars = { "ActionButton", "MultiBarBottomLeftButton",
	               "MultiBarBottomRightButton", "MultiBarRightButton",
	               "MultiBarLeftButton" }
	for _, prefix in ipairs(bars) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b then Try(ActionButton_Update, b) end
		end
	end

	-- LA BARRA DE POSTURA, QUE ES OTRO MARCO Y NO OTRA PAGINA.
	--
	-- Cazado comparando capturas de los cinco personajes, login natural contra
	-- cambio: cuatro salian identicos y el guerrero no. La suya salia con dos
	-- huecos vacios y un hechizo distinto en medio -- y lo que se veia era
	-- literalmente OTRA FILA de las que tiene guardadas:
	--
	--     login natural ensena   6603, 78, 58984, 6673   -> casillas 73..76
	--     tras un cambio ensena  -, 78, 2764, -          -> casillas  1..12
	--
	-- Solo se ve en el guerrero porque es el unico de los cinco con BARRA DE
	-- POSTURA. Druida, pica y caballero de la muerte tienen la misma; mago,
	-- sacerdote, cazador y paladin dibujan siempre las 1..12, asi que quedarse
	-- ahi no se nota.
	--
	-- EL PRIMER ARREGLO APUNTO AL WIDGET EQUIVOCADO y merece quedar escrito.
	-- Di por hecho el esquema moderno -- un `ActionBarController` seguro que le
	-- cambia el atributo `actionpage` a los mismos botones -- y di un golpecito a
	-- la pagina para que se reevaluara. No hizo nada, y `/rts bars page` dijo por
	-- que en una linea: **`ActionBarController` NO EXISTE en este cliente**. Aqui
	-- manda el esquema viejo: un marco aparte, `BonusActionBarFrame`, con sus
	-- propios `BonusActionButton1..12`, que se DESLIZA por encima de la barra
	-- normal. Su estado es un `state` que vale "top" o "bottom", y el volcado lo
	-- enseño crudo:
	--
	--     login  ->  BonusActionBarFrame  VISIBLE  state=top
	--     cambio ->  BonusActionBarFrame  oculto   state=bottom
	--
	-- Es la regla de siempre de este proyecto -- comprobar contra el cliente y no
	-- contra lo que uno recuerda -- saltada por asumir la version moderna de una
	-- API. `ActionButton1` lee la casilla 1 en los DOS casos, y eso es correcto:
	-- no es el que se equivoca, es que esta tapado.
	--
	-- Quien decide mostrarlo es el manejador de Blizzard al recibir
	-- `UPDATE_BONUS_ACTIONBAR`, y un cambio de personaje no lo dispara. Asi que
	-- se le pide a el que lo mire.
	ns.SyncBonusBar()

	-- El grupo: los marcos salian con el nombre y las barras vacias, que es como
	-- se ve un compañero del que el cliente no tiene datos todavia.
	for i = 1, 4 do
		local pf = _G["PartyMemberFrame" .. i]
		if pf then Try(PartyMemberFrame_UpdateMember, pf) end
	end
	Try(UpdatePartyMemberBackground)

	-- Tu marco y el del objetivo, por lo mismo.
	Try(PlayerFrame_Update)
	Try(TargetFrame_Update, _G.TargetFrame)

	ns.FixPlayerName()
end

function ns.FixPlayerName()
	local fs = _G.PlayerName or (PlayerFrame and PlayerFrame.name)
	if not fs or not fs.SetText then return end

	if not ns.nameHooked and type(PlayerFrame_Update) == "function" then
		ns.nameHooked = true
		hooksecurefunc("PlayerFrame_Update", function()
			if ns.serverName then fs:SetText(ns.MyName()) end
		end)
	end

	fs:SetText(ns.MyName())
end

-- PONER LA BARRA DE POSTURA COMO TOCA, QUE ES LO QUE UN CAMBIO DE PERSONAJE
-- NO HACE SOLO.
--
-- ESCRITO CONTRA EL CODIGO DE VERDAD, no contra lo que yo recordaba de la API.
-- El FrameXML del cliente se saca de `Data\esES\patch-esES.MPQ` en dos minutos
-- (ver `CLAUDE.md`), y lo de abajo es lo que dicen `BonusActionBarFrame.lua` y
-- `MainMenuBar.lua` de ESTE cliente. Dos vueltas de adivinar costaron mas que
-- eso.
--
-- Lo que hay que saber, y ninguna de las dos cosas se deduce:
--
--   * QUIEN LO ARREGLA EN UN /reload. `MainMenuBar_OnEvent` con
--     `PLAYER_ENTERING_WORLD` llama a `MainMenuBar_ToPlayerArt()`, y ahi dentro:
--     `if GetBonusBarOffset() > 0 then ShowBonusActionBar(true) else
--     HideBonusActionBar(true) end`. **Con `override = true`.** Un cambio de
--     personaje no dispara ese evento, y por eso el `/reload` lo arregla y el
--     cambio no.
--
--   * EL `override` NO ES DECORATIVO. Sin el, las dos funciones empiezan con
--     `if ((not MainMenuBar.busy) and (not UnitHasVehicleUI("player"))) or
--     override`, asi que un `MainMenuBar.busy` que se quedo puesto las deja
--     mudas. Blizzard pasa `true` en todos los sitios donde de verdad quiere que
--     ocurra, y esto es uno de ellos.
--
--   * Y `state` NO SIRVE COMO TESTIGO INMEDIATO. Solo lo escribe
--     `BonusActionBar_OnUpdate` al ACABAR el deslizamiento, 0,15 s despues. La
--     version anterior lo miraba en la misma linea y por eso las tres puertas
--     que probo dijeron "no ha abierto" -- incluida la que si abria. **Segundo
--     testigo equivocado seguido en este mismo fallo**: primero
--     `ActionButton1.action`, que nunca cambia, y luego `state`, que cambia
--     tarde. Ahora se comprueba `IsShown()` medio segundo despues.
--
--   * `mode` SE ATASCA. El deslizamiento vive en el `OnUpdate` del marco, y un
--     marco escondido no recibe `OnUpdate` -- y `Chrome.lua` esconde este marco
--     al entrar en modo RTS. Si se queda a medias con `mode = "show"`, la
--     guarda interna (`mode ~= "show" and state ~= "top"`) deja a
--     `ShowBonusActionBar` sin hacer nada PARA SIEMPRE. Por eso se desatasca
--     antes de pedir nada.
--
-- Los dos sentidos importan y no es simetria por gusto: entrar en el guerrero
-- deja la barra abajo enseñando casillas que no son suyas, y salir de el la
-- deja arriba enseñando las 73..84 de un mago, que estan vacias.
--
-- Y se toca SOLO la barra de postura, no `MainMenuBar_ToPlayerArt` entera, que
-- seria lo que hace el /reload: esa esconde y ensena `MultiBarLeft` y compania,
-- que SI son marcos seguros. `BonusActionBarFrame` es un `Frame` normal -- sus
-- botones son seguros, el no -- asi que ensenarlo no puede bloquear una casilla.
function ns.SyncBonusBar(verbose)
	local fr = _G.BonusActionBarFrame
	if not fr then
		if verbose then ns.Print("|cff888888barra de postura: este cliente no la tiene.|r") end
		return
	end

	local off = 0
	if type(GetBonusBarOffset) == "function" then
		local ok, v = pcall(GetBonusBarOffset)
		if ok then off = tonumber(v) or 0 end
	end
	local quiere = (off > 0)

	local function Visible()
		if type(fr.IsShown) ~= "function" then return nil end
		local ok, r = pcall(fr.IsShown, fr)
		if ok then return r and true or false end
		return nil
	end

	-- DESATASCAR ANTES DE PEDIR. Ver la cabecera: un `mode` a medias deja a las
	-- dos funciones mudas, y un `state` que dice "top" con el marco escondido es
	-- la misma mentira por el otro lado.
	fr.mode = "none"
	fr.completed = 1
	if fr.state == "top" and Visible() == false then fr.state = "bottom" end

	local fn = quiere and _G.ShowBonusActionBar or _G.HideBonusActionBar
	if type(fn) ~= "function" then
		ns.Print("|cffff8800barra de postura:|r este cliente no tiene " ..
		         (quiere and "ShowBonusActionBar" or "HideBonusActionBar") .. ".")
		return
	end
	pcall(fn, true)

	if verbose then
		ns.Print(("barra de postura: postura %d, pedido %s (el resultado tarda 0,15 s)"):format(
			off, quiere and "arriba" or "abajo"))
	end

	-- Y SE COMPRUEBA DESPUES, que es la unica forma de comprobarlo. Medio segundo
	-- es tres veces el deslizamiento. Solo habla si salio mal, o si se le pidio.
	ns.bonusCheck = ns.bonusCheck or CreateFrame("Frame")
	ns.bonusCheck.acc = 0
	ns.bonusCheck.quiere = quiere
	ns.bonusCheck.off = off
	ns.bonusCheck.verbose = verbose and true or false
	ns.bonusCheck:SetScript("OnUpdate", function(self, e)
		self.acc = self.acc + e
		if self.acc < 0.5 then return end
		self:SetScript("OnUpdate", nil)

		local vis = Visible()
		if vis == self.quiere then
			if self.verbose then
				ns.Print(("|cff33ccffbarra de postura OK|r (%s, state=%s)"):format(
					vis and "arriba" or "abajo", tostring(fr.state)))
			end
			return
		end
		ns.Print(("|cffff8800barra de postura:|r postura %d, la queria %s y esta %s " ..
		          "(state=%s, mode=%s). Dimelo con esta linea."):format(
			self.off, self.quiere and "arriba" or "abajo",
			vis and "arriba" or "abajo", tostring(fr.state), tostring(fr.mode)))
	end)
end

-- QUE FILA DE LAS 120 ESTA DIBUJANDO LA BARRA, Y QUIEN LA DIBUJA.
--
-- Existe porque el 2026-09-04 el arreglo obvio no funciono y la razon es que
-- **no se sabe con que mecanismo dibuja este cliente la barra de postura**. Las
-- capturas dicen que despues de un cambio de personaje `GetBonusBarOffset()`
-- vale 1 -- o sea que el dato ESTA -- y aun asi se dibujan las casillas 0-11 en
-- vez de las 72-83. Con el dato bueno y el dibujo malo, lo que falta es saber
-- QUE widget decide, y eso no se razona: se le pregunta.
--
-- Es la regla de `/rts portrait api` y `/rts skills status` otra vez: en vez de
-- comprobar una constante escrita de memoria, no tener constante. Y ademas
-- PRUEBA los candidatos y dice cual mueve la aguja, que es la tabla de los siete
-- encuadres del retrato aplicada aqui -- el bueno se reconoce en cuanto sale.
function ns.DumpBarPage()
	local function T(v) return tostring(v) end
	local function Q(fn, ...)
		if type(fn) ~= "function" then return "(no existe)" end
		local ok, a = pcall(fn, ...)
		return ok and T(a) or "(error)"
	end

	-- Que casilla ABSOLUTA (1..120) esta leyendo el primer boton. Es EL dato:
	-- si dice 1 estamos en la pagina 1 y si dice 73 en la barra de postura.
	local function Slot1()
		local b = _G.ActionButton1
		if not b then return "(sin ActionButton1)" end
		local a = b.action
		if a == nil and type(ActionButton_CalculateAction) == "function" then
			local ok, r = pcall(ActionButton_CalculateAction, b)
			if ok then a = r end
		end
		return T(a)
	end

	ns.Print("|cffffff00--- barra: quien dibuja ---|r")
	ns.Print(("pagina %s   postura %s   forma %s"):format(
		Q(GetActionBarPage), Q(GetBonusBarOffset), Q(GetShapeshiftForm)))
	ns.Print(("ActionButton1 lee la casilla |cffffff00%s|r"):format(Slot1()))

	-- LOS MARCOS QUE PODRIAN SER EL MECANISMO. No se da por hecho que exista
	-- ninguno: en 3.3.5 conviven el esquema viejo (un marco aparte,
	-- `BonusActionBarFrame`) y el nuevo (un controlador seguro que le cambia el
	-- atributo `actionpage` a los mismos botones), y cual de los dos manda en
	-- ESTE cliente es justo lo que no se sabe.
	for _, n in ipairs({ "BonusActionBarFrame", "ActionBarController",
	                     "MainMenuBarArtFrame", "BonusActionButton1",
	                     "VehicleMenuBar", "PetActionBarFrame" }) do
		local fr = _G[n]
		if not fr then
			ns.Print(("|cff888888%-22s no existe|r"):format(n))
		else
			local vis = "?"
			if type(fr.IsShown) == "function" then
				local ok, r = pcall(fr.IsShown, fr)
				if ok then vis = r and "VISIBLE" or "oculto" end
			end
			local st = ""
			if fr.state ~= nil then st = "  state=" .. T(fr.state) end
			if type(fr.GetAttribute) == "function" then
				local ok, r = pcall(fr.GetAttribute, fr, "state")
				if ok and r ~= nil then st = st .. "  attr=" .. T(r) end
			end
			ns.Print(("%-22s %s%s"):format(n, vis, st))
		end
	end

	-- LAS DOS FILAS, UNA AL LADO DE LA OTRA. `GetActionInfo` toma la casilla
	-- absoluta, asi que aqui se ve de un vistazo que las dos existen y cual es
	-- la que sale en pantalla. Sin esto "la barra esta mal" no distingue entre
	-- "falta el dato" y "se dibuja la otra fila", que tienen arreglos opuestos.
	local function Row(from)
		local out = {}
		for i = from, from + 11 do
			local t, id = GetActionInfo(i)
			out[#out + 1] = t and (T(id)) or "-"
		end
		return table.concat(out, " ")
	end
	ns.Print(("|cffffff00  1..12|r %s"):format(Row(1)))
	ns.Print(("|cffffff00 73..84|r %s"):format(Row(73)))

	-- Y AHORA SE INTENTA ARREGLAR DE VERDAD, con el testigo bueno.
	--
	-- La primera version de este volcado miraba `ActionButton1.action` esperando
	-- que saltara de 1 a 73, y eso no podia pasar nunca: ese boton siempre lee la
	-- casilla 1: lo que cambia es si esta TAPADO por la barra de postura. Mirar el
	-- witness equivocado hizo que las cuatro pruebas salieran "no cambia nada"
	-- cuando una de ellas si estaba haciendo algo.
	ns.Print("|cffffff00--- arreglando ---|r")
	ns.SyncBonusBar(true)
end

local f = CreateFrame("Frame", "RTSCommandCore")
-- CUANTAS VECES HA ENTRADO EL CLIENTE EN EL MUNDO. Es el testigo que decide
-- si un cambio de personaje le hizo recargar el mundo: sin recarga no hay
-- `PLAYER_ENTERING_WORLD` y el numero se queda quieto. Lo lee `/rts whoami`.
ns.worldEntries = 0

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")
f:RegisterEvent("RAID_ROSTER_UPDATE")

local initialised = false

local function Initialise()
	if initialised then return end
	initialised = true

	-- Scales are derived from the camera's diagonal FOV unless a calibration run
	-- explicitly overrode them; a stale SX from an older eyeball calibration must
	-- NOT silently win over the derived value.
	if RTSCommandDB.SX then ns.Markers.SX = RTSCommandDB.SX end
	if RTSCommandDB.SY then ns.Markers.SY = RTSCommandDB.SY end
	if RTSCommandDB.DEPTH_BIAS then ns.Markers.DEPTH_BIAS = RTSCommandDB.DEPTH_BIAS end
	if RTSCommandDB.forceScale then ns.Markers.autoIntrinsics = false end
	-- Calibration samples survive a reload so refining the fit costs no re-sweep.
	if type(RTSCommandDB.calSamples) == "table" then
		ns.Calib.samples = RTSCommandDB.calSamples
	end

	-- LOS HUECOS DE HABILIDAD. Acota al LEER y no solo al escribir, que es la
	-- cuarta vez que hace falta en este addon: un fichero de SavedVariables no
	-- olvida ninguna clave y sobrevive a la version que la escribio, y los
	-- `Set*` solo corren cuando el jugador teclea.
	ns.Skills:Load()

	-- LO QUE LA SALA VIEJA DEJO GUARDADO, TIRADO AL CARGAR, Y SIGUE HACIENDO
	-- FALTA. La sala se volvio a llenar el 2026-09-04, pero **con otras
	-- claves**: los huecos de habilidad viven ahora en `RTSCommandDB.hall.who`
	-- y no en `RTSCommandDB.skills`, que era una lista plana de otro diseno.
	--
	-- Que el nombre nuevo sea distinto es lo que deja tirar el viejo sin
	-- pensarlo: si se hubiera reutilizado la clave, el primer arranque tras la
	-- actualizacion habria leido huecos de un formato que ya no es -- que es
	-- exactamente lo que costo el `grow = 688`, el `camHold` de una funcion
	-- borrada y el `railCropGen` cuyo indice seguia siendo valido pero
	-- significaba otra cosa.
	RTSCommandDB.skills    = nil   -- huecos de habilidad por personaje
	RTSCommandDB.portrait  = nil   -- encuadre del modelo 3D del heroe
	RTSCommandDB.targets   = nil   -- sitio del panel flotante de objetivos
	RTSCommandDB.targetsOn = nil   -- si se pedia la lista TGTS al servidor
	RTSCommandDB.focus     = nil   -- sitio del readout de foco

	-- Y ESTA NO ES UN CAMBIO DE FORMATO: ES UN INTERRUPTOR QUE NUNCA SE PIDIO.
	--
	-- `questAuto` decidia si el grupo seguia al heroe al aceptar y entregar
	-- misiones. Nadie lo pidio, y guardado en OFF de una ronda de pruebas vieja
	-- bloqueaba el reparto entero con un `return` mudo -- tres vueltas buscando
	-- el fallo en otro sitio. Borrado el interruptor, se tira la clave: dejarla
	-- seria dejar el mismo cepo puesto para el dia que alguien vuelva a leerla.
	RTSCommandDB.questAuto = nil

	-- EL CANAL PRIMERO. Todo lo de debajo registra verbos en el (`ns.Link:On`) y
	-- varios mandan su primera peticion desde su propio `Create`, asi que el
	-- frame tiene que existir antes. Es la unica dependencia de orden de esta
	-- lista que no se puede deducir leyendo los ficheros, y por eso esta dicha.
	ns.Link:Create()

	-- QUIEN ERES, DICHO POR EL SERVIDOR.
	--
	-- Hacen falta las dos mitades y ninguna vale sola:
	--
	--   * EL AVISO. Un cambio de personaje no dispara un segundo
	--     `PLAYER_ENTERING_WORLD` -- la recarga del mundo pasa ANTES de soltar
	--     el heroe, asi que ese evento llega mientras todavia eres el de antes.
	--     Sin esto el addon no se entera nunca de que ha cambiado.
	--   * EL NOMBRE. El cliente sigue ensenando el nombre viejo en su marco, y
	--     `UnitName("player")` con el. Eso convertia al heroe que acabas de
	--     dejar -- que vuelve de bot y se llama como te llamabas -- en "tu" para
	--     media docena de comprobaciones del addon.
	--
	-- Es autoridad, no una pista: el servidor es quien acaba de meter ese
	-- personaje en la sesion.
	ns.Link:On("SWAPPED", function(rest)
		local name, guid = rest:match("^(%S+)%s+(%d+)$")
		if not name then return end

		-- SI EL CLIENTE NO ESTA DE ACUERDO, NO SE DISIMULA.
		--
		-- Ponerle el nombre nuevo a un cliente que no llego a cambiar es lo que
		-- convertia un fallo entero en "los hechizos salen mal": todo lo demas
		-- parecia correcto porque lo estabamos escribiendo nosotros.
		if ClientAgrees(guid) == false then
			ns.Print("|cffff4040El cambio NO se aplico en tu cliente.|r El servidor " ..
			         "dice que eres " .. name .. " y tu cliente sigue siendo " ..
			         tostring(UnitName("player")) .. ".")
			ns.Print("|cff888888Es el cambio de mundo, que no llego a completarse. " ..
			         "Vuelve a pedirlo; si se repite, dimelo con esta linea.|r")
			return
		end

		-- EL GUID VA CON EL NOMBRE. Ver `ns.MyName` en `Bridge.lua`: la
		-- anulacion solo vale mientras sigas siendo ese personaje, y sin el guid
		-- una reconexion despues de un cambio dejaria el nombre de otro pegado.
		ns.serverName = name
		ns.serverNameGuid = UnitGUID("player")

		ns.Selection:IdentityChanged()
		ns.FixPlayerName()

		-- Y AHORA SE PIDEN LAS BARRAS OTRA VEZ, que es el unico momento en que
		-- el cliente las puede aceptar.
		--
		-- Su manejador de `SMSG_ACTION_BUTTONS` se salta el repaso y el
		-- repintado si en ese instante no tiene objeto de jugador propio
		-- (`0x006D87E2`, comprobado en el binario), y la rafaga de login llega
		-- justo antes de que lo adopte -- el objeto propio viaja en esa misma
		-- rafaga. Aqui ya hemos comprobado que el guid del cliente coincide con
		-- el que dice el servidor, o sea que la identidad ESTA puesta: es el
		-- primer momento en que pedirlas sirve de algo.
		ns.SendServer("REBARS")

		-- Y SE RECARGA LA INTERFAZ, que es lo unico que arregla lo de los
		-- hechizos.
		--
		-- Los DATOS del personaje nuevo llegan bien: `SendInitialSpells` y
		-- `SendInitialActionButtons` van dentro de la rafaga de login
		-- (`Player.cpp:11790,11793`) y el cliente los guarda. Lo que no pasa es
		-- que la interfaz se entere: los marcos de Blizzard se redibujan con
		-- `PLAYER_ENTERING_WORLD`, y **el cambio no dispara ninguno** -- la
		-- recarga del mundo ocurre ANTES de soltar el heroe, y despues de
		-- cambiar de verdad no hay evento. Asi que las barras seguian ensenando
		-- las del personaje anterior, y pulsar una lanzaba un hechizo que este
		-- ya no conoce: de ahi el "se buguea".
		--
		-- Se podria refrescar marco por marco, y seria una lista que se queda
		-- corta: barras, libro, talentos, reputaciones, misiones, bolsas... y la
		-- siguiente que falte se descubre en juego. `ReloadUI` reconstruye la
		-- interfaz ENTERA a partir de datos que ya son correctos, y no toca la
		-- conexion -- no es un relogueo, es lo mismo que `/reload`.
		--
		-- Con un respiro para que el mensaje se lea, y apagable: quien prefiera
		-- una interfaz rara a un parpadeo tiene `/rts swap ui`.
		ns.Print(("|cff33ccffAhora eres %s.|r"):format(name))
		if RTSCommandDB.swapReload == false then
			ns.Print("|cff888888La interfaz NO se refresca (|cffffff00/rts swapui|r). " ..
			         "Si las barras ensenan los hechizos del anterior, es esto.|r")
			return
		end

		-- REFRESCAR LO QUE SE QUEDA VIEJO, EN VEZ DE RECARGAR LA INTERFAZ.
		--
		-- `ReloadUI()` era lo limpio y **el cliente lo prohibe**: en juego salio
		-- *"No se ha podido realizar la accion de interfaz debido a un AddOn"*, que
		-- es el aviso de accion prohibida. Desde codigo de addon no se puede
		-- recargar la interfaz, y punto; teclearlo a mano si funciona porque
		-- entonces no hay addon en la pila.
		--
		-- Asi que se refresca a mano lo que depende de `PLAYER_ENTERING_WORLD`, que
		-- es el evento que un cambio de personaje NO dispara. **Es una lista y las
		-- listas se quedan cortas**, asi que se dice en voz alta: si algo sigue
		-- viejo, `/reload` lo arregla y ademas dice cual falta.
		ns.RefreshAfterSwap()
		ns.Print("|cff888888Si algo sigue con lo del personaje anterior, " ..
		         "|cffffff00/reload|r lo arregla -- y dime que era.|r")	end)

	-- LA RESPUESTA A `WHOAMI`, que no recarga nada. Ver el verbo en mod-rts: son
	-- dos verbos y no uno para que preguntar quien eres no recargue la interfaz.
	-- LAS DOCE PRIMERAS CASILLAS, LAS DEL SERVIDOR AL LADO DE LAS DEL CLIENTE.
	--
	-- "las barras no son las de ese personaje" tiene dos causas con arreglos
	-- opuestos, y desde el cliente se ven igual: o el servidor manda otra cosa
	-- -- y entonces el fallo esta en el cambio -- o manda justo eso, y lo que
	-- hay guardado para ese personaje no es lo que el jugador recuerda. Puestas
	-- una encima de otra se distingue de un vistazo.
	ns.Link:On("MYBARS", function(rest)
		local srv = {}
		for tok in rest:gmatch("%S+") do srv[#srv + 1] = tok end

		ns.Print("|cffffff00casilla   servidor        cliente|r")
		for i = 1, 12 do
			local t, id = GetActionInfo(i)
			local cli = "-"
			if t then
				local nombre = (t == "spell" and id and GetSpellInfo(id)) or nil
				cli = tostring(t) .. ":" .. tostring(id) ..
				      (nombre and (" (" .. nombre .. ")") or "")
			end

			local sv = srv[i] or "?"
			local sid = sv:match("^1:(%d+)$")
			if sid then
				local nombre = GetSpellInfo(tonumber(sid))
				if nombre then sv = sv .. " (" .. nombre .. ")" end
			end

			ns.Print(("  %2d  %-22s %s"):format(i, sv, cli))
		end
		ns.Print("|cff888888Si las dos columnas coinciden, el cambio manda bien y " ..
		         "lo guardado para ese personaje ES eso.|r")
	end)

	ns.Link:On("IAM", function(rest)
		local name, guid = rest:match("^(%S+)%s+(%d+)$")
		if not name then return end

		-- Mismo contraste que en `SWAPPED`, y aqui es todavia mas necesario:
		-- esto corre en CADA entrada al mundo, incluida la de despues de un
		-- `/reload`. Si el cliente se quedo siendo otro, escribir aqui el nombre
		-- del servidor borraria la unica pista que quedaba de que algo fallo.
		if ClientAgrees(guid) == false then
			ns.Print(("|cffff4040Tu cliente cree que eres %s y el servidor dice %s.|r " ..
			          "El ultimo cambio no llego a aplicarse."):format(
				tostring(UnitName("player")), name))
			return
		end

		ns.serverName = name
		ns.serverNameGuid = UnitGUID("player")
		ns.FixPlayerName()

		-- Y SE DICE QUIEN ERES, aqui y no en la entrada al mundo. Despues de un
		-- cambio de personaje "¿quien soy?" deja de ser una curiosidad: es el
		-- dato del que depende todo lo demas del addon, y si el cliente lo tiene
		-- mal el sintoma aparece tres modulos mas alla.
		ns.Print(("|cff33ccffEres %s|r |cff888888%s|r"):format(
			name, tostring(UnitGUID("player"))))
	end)

	ns.Markers:Create()
	ns.SelectionRing:Create()
	ns.Flare:Create()
	ns.Route:Create()
	ns.Marks:Create()
	ns.Channel:Create()
	ns.Camera:Create()
	ns.FreeCam:Create()
	-- El punto de la camara en el mapa del mundo. No dibuja hasta que se abre
	-- el mapa con la camara libre encendida, pero su textura cuelga de
	-- `WorldMapDetailFrame`, que es de FrameXML y ya existe aqui.
	ns.Radar:Create()
	ns.Chrome:Create()
	-- La escala de pixel. No dibuja nada: es el contenedor del que cuelgan la
	-- barra de abajo y las ventanas propias.
	ns.Pixels:Create()
	-- Skills se crea SIEMPRE, aunque nadie dibuje todavia sus huecos: registra
	-- verbos en el canal y se suscribe a la seleccion, y las dos cosas tienen
	-- que estar puestas antes del primer cambio de primario. Bags no esta aqui a
	-- proposito: se crea la primera vez que se pide, porque su ventana no hace
	-- falta hasta entonces.
	ns.Skills:Create()
	ns.Chain:Create()
	-- Quests se crea SIEMPRE y aqui, por dos motivos que apuntan al mismo sitio:
	-- el seguimiento automatico (aceptar y entregar detras de ti) tiene que
	-- estar enganchado mientras juegas NORMAL, que es cuando hablas con los
	-- PNJ; y el boton de compartir del registro nativo se engancha una sola vez
	-- al arrancar. Con creacion perezosa habria que abrir algo nuestro primero
	-- para que el registro de Blizzard empezara a funcionar, y eso no se
	-- adivina.
	ns.Quests:Create()
	-- La sonda del botin. No dibuja nada: se engancha al `LootFrame` de
	-- Blizzard y solo habla cuando la ventana se cierra sola. Ver Loot.lua.
	ns.Loot:Create()
	if type(RTSCommandDB.selfBotAuto) == "boolean" then
		ns.RTSMode.selfBot.auto = RTSCommandDB.selfBotAuto
	end
	if type(RTSCommandDB.freeLoot) == "boolean" then
		ns.RTSMode.freeLoot = RTSCommandDB.freeLoot
	end
	if type(RTSCommandDB.lootAll) == "boolean" then
		ns.RTSMode.lootAll = RTSCommandDB.lootAll
	end
	if type(RTSCommandDB.questAI) == "boolean" then
		ns.RTSMode.questAI = RTSCommandDB.questAI
	end
	-- Umbral de "esto ha sido un giro de camara, no un click". Depende del raton
	-- y de la sensibilidad del cliente, asi que se guarda por personaje en vez
	-- de vivir como constante en el codigo.
	if type(RTSCommandDB.turnEps) == "number" and RTSCommandDB.turnEps > 0 then
		ns.RTSMode.turnEps = RTSCommandDB.turnEps
	end
	ns.Print("cargado. |cffffff00/rts help|r para la lista de comandos.")

	-- rts_core.dll may be injected at any point, including mid-session, so
	-- poll for it rather than checking once at load.
	local acc = 0
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnUpdate", function(self, e)
		acc = acc + e
		if acc < 2 then return end
		acc = 0

		if ns.Bridge:TryAttach() then
			ns.Print(("|cff00ff00native bridge attached|r (rts_core %s) - " ..
				"precise coordinates enabled."):format(ns.Bridge.version or "?"))
			self:SetScript("OnUpdate", nil)
		end
	end)
end

f:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ns.worldEntries = (ns.worldEntries or 0) + 1
		-- Y AQUI ES DONDE SE NOTA QUE ERES OTRO. Con el cambio de personaje
		-- este evento ya no significa "acabo de conectarme": significa que la
		-- sesion puede tener un personaje distinto al de hace un segundo, y
		-- todo lo que este guardado por nombre deja de referirse a quien creia.
		if initialised then
			-- EL MUNDO DEL CLIENTE ESTA OTRA VEZ EN PIE, Y SOLO NOSOTROS LO
			-- SABEMOS. El cambio de personaje tira el mundo del cliente con un
			-- `SMSG_NEW_WORLD` y tiene que esperar a que vuelva antes de mandar
			-- la rafaga de login; el acuse que manda el cliente por su cuenta
			-- (`MSG_MOVE_WORLDPORT_ACK`) el servidor no lo puede ver, porque el
			-- nucleo tira esa clase de paquete mientras el jugador siga en el
			-- mundo. Este evento es el aviso, y sin el la espera se comia doce
			-- segundos de reloj por cada cambio.
			--
			-- Se manda SIEMPRE, tambien en un login normal: el servidor sabe si
			-- habia alguien esperando y contesta que no en silencio. Preguntar
			-- primero costaria otro viaje de ida y vuelta para ahorrar un
			-- mensaje de veinte bytes.
			-- VARIAS VECES, no una. De este mensaje depende que el servidor
			-- deje de esperar y mande la rafaga de login; si se pierde, el
			-- cambio se cae entero doce segundos despues y el cliente se queda
			-- siendo quien era. Y perderse se pierde: el canal acababa de
			-- sobrevivir a una recarga de mundo.
			--
			-- Repetirlo no cuesta nada porque `ClientPorted` es idempotente --
			-- levanta una bandera -- y contesta que no cuando no hay ningun
			-- cambio esperando, que es el caso de cualquier login normal.
			ns.SendServer("PORTED")
			local ping = CreateFrame("Frame")
			ping.acc, ping.left = 0, 4
			ping:SetScript("OnUpdate", function(self, e)
				self.acc = self.acc + e
				if self.acc < 0.5 then return end
				self.acc, self.left = 0, self.left - 1
				ns.SendServer("PORTED")
				if self.left <= 0 then self:SetScript("OnUpdate", nil) end
			end)

			-- Y SE PREGUNTA COMO NOS LLAMAMOS, porque el cliente no lo sabe.
			-- `UnitName("player")` devuelve un buffer que solo rellena la
			-- pantalla de seleccion de personaje (ver `ns.FixPlayerName`), asi
			-- que despues de un cambio miente -- y despues de recargar la
			-- interfaz vuelve a mentir, porque el buffer sigue igual. Preguntar
			-- en cada entrada al mundo lo arregla en los dos casos y no cuesta
			-- nada en un login normal, donde la respuesta es la esperada.
			ns.SendServer("WHOAMI")

			ns.Selection:IdentityChanged()
			-- AQUI YA NO SE DICE QUIEN ERES, Y ESO ES EL ARREGLO.
			--
			-- Decia *"Eres Neferite"* estando ya en Bob, y se leia como que el
			-- cambio habia fallado. No fallaba: la linea imprimia
			-- `UnitName("player")`, que sale de un buffer estatico
			-- (`0x00C79D18`) que **solo rellena la pantalla de seleccion de
			-- personaje** -- o sea el nombre con el que ARRANCASTE la sesion,
			-- para siempre. Era el testigo equivocado, dicho con la voz del
			-- bueno.
			--
			-- El aviso se dice ahora al contestar `IAM`, que es el servidor
			-- diciendo a quien acaba de meter en la sesion. Llega un instante
			-- despues de esta linea y es autoridad, no una pista.

			-- Y SE LE PIDE A BLIZZARD QUE REPINTE SU MARCO.
			--
			-- Reportado como *"al loguear con otro pj me sigo llamando
			-- Neferite"*, con el nombre viejo en el marco de arriba **y el
			-- personaje viejo tambien en la lista del grupo** -- dos cosas que
			-- no pueden ser ciertas a la vez, porque nadie sale en su propio
			-- grupo. Una de las dos esta sin actualizar.
			--
			-- Si el que esta sin actualizar es el marco, esto lo arregla: es la
			-- misma funcion que llama Blizzard en sus propios eventos, y no
			-- esta protegida. Si despues de esto el nombre SIGUE siendo el
			-- viejo, entonces lo que esta mal es el nombre que el cliente
			-- guarda de si mismo, y eso es otro problema y otro arreglo -- pero
			-- ya sabriamos cual de los dos es, que es lo que hoy no se sabe.
			--
			-- Envuelto porque no es nuestra: una funcion de Blizzard que cambie
			-- de nombre no puede llevarse por delante la entrada al mundo.
			if type(PlayerFrame_Update) == "function" then
				pcall(PlayerFrame_Update)
			end
		end
		return

	elseif event == "VARIABLES_LOADED" then
		RTSCommandDB = RTSCommandDB or {}
		for k, v in pairs(DEFAULTS) do
			if RTSCommandDB[k] == nil then RTSCommandDB[k] = v end
		end

	elseif event == "PLAYER_LOGIN" then
		-- VARIABLES_LOADED can arrive after PLAYER_LOGIN on a cold start.
		RTSCommandDB = RTSCommandDB or {}
		for k, v in pairs(DEFAULTS) do
			if RTSCommandDB[k] == nil then RTSCommandDB[k] = v end
		end
		Initialise()

	else -- roster changed
		if initialised then
			ns.Selection:Prune()
			-- El metodo de botin es del GRUPO, y el grupo se rehace cada vez
			-- que entra o sale un bot -- asi que hay que volver a ponerlo. La
			-- estrategia de botin de cada bot es lo mismo pero por otro motivo:
			-- vive en la memoria del bot, y uno que acaba de entrar nace con la
			-- de fabrica.
			ns.RTSMode:ApplyFreeLoot(true)
			if ns.RTSMode.active then
				ns.RTSMode:ApplyLootAll(true)
				ns.RTSMode:ApplyQuestAI()
			end
			-- Un bot que entra o sale es una columna mas o una menos en la
			-- ventana de bolsas. Solo hace algo si esta abierta.
			ns.Bags:RosterChanged()
		end
	end
end)

--- Binding labels ----------------------------------------------------------
-- Shown in the Key Bindings UI. Must be globals.

BINDING_HEADER_RTSCOMMAND        = "RTS Command"
BINDING_NAME_RTSCOMMAND_TOGGLE   = "Show/hide the RTS console bar"
BINDING_NAME_RTSCOMMAND_MODE     = "Toggle RTS mode (mouse control)"
BINDING_NAME_RTSCOMMAND_CAMERA   = "Toggle detached RTS camera"
BINDING_NAME_RTSCOMMAND_CALIBRATE = "Calibrate projection (cursor on a unit)"
BINDING_NAME_RTSCOMMAND_SELECTALL = "Select all units"
BINDING_NAME_RTSCOMMAND_CLEAR    = "Clear selection"

BINDING_HEADER_RTSCOMMAND_ORDERS = "RTS Command: Orders"
BINDING_NAME_RTSCOMMAND_ORDER_MOVE   = "Order: Move"
BINDING_NAME_RTSCOMMAND_ORDER_HOLD   = "Order: Hold position"
BINDING_NAME_RTSCOMMAND_ORDER_FOLLOW = "Order: Follow"
BINDING_NAME_RTSCOMMAND_ORDER_ATTACK = "Order: Attack target"
BINDING_NAME_RTSCOMMAND_ORDER_ATTACKMOVE = "Order: Attack-move to cursor"
BINDING_NAME_RTSCOMMAND_RELEASE = "Leave command mode"
BINDING_NAME_RTSCOMMAND_COMMAND = "Command mode (borrow selected bot's bar)"
BINDING_NAME_RTSCOMMAND_SLOT1 = "Command slot 1"
BINDING_NAME_RTSCOMMAND_SLOT2 = "Command slot 2"
BINDING_NAME_RTSCOMMAND_SLOT3 = "Command slot 3"
BINDING_NAME_RTSCOMMAND_SLOT4 = "Command slot 4"
BINDING_NAME_RTSCOMMAND_SLOT5 = "Command slot 5"
BINDING_NAME_RTSCOMMAND_SLOT6 = "Command slot 6"
BINDING_NAME_RTSCOMMAND_SLOT7 = "Command slot 7"
BINDING_NAME_RTSCOMMAND_SLOT8 = "Command slot 8"
BINDING_NAME_RTSCOMMAND_SLOT9 = "Command slot 9"
BINDING_NAME_RTSCOMMAND_SLOT10 = "Command slot 10"

BINDING_HEADER_RTSCOMMAND_UNITS  = "RTS Command: Select unit"
BINDING_NAME_RTSCOMMAND_UNIT1 = "Select unit 1 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT2 = "Select unit 2 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT3 = "Select unit 3 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT4 = "Select unit 4 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT5 = "Select unit 5 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT6 = "Select unit 6 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT7 = "Select unit 7 (shift: add)"
BINDING_NAME_RTSCOMMAND_UNIT8 = "Select unit 8 (shift: add)"

BINDING_HEADER_RTSCOMMAND_GROUPS = "RTS Command: Control groups"
BINDING_NAME_RTSCOMMAND_GROUP1 = "Control group 1 (alt: store)"
BINDING_NAME_RTSCOMMAND_GROUP2 = "Control group 2 (alt: store)"
BINDING_NAME_RTSCOMMAND_BAGS = "Bolsas del grupo"
BINDING_HEADER_RTSCOMMAND_SKILLS = "RTS Command - habilidades"
BINDING_NAME_RTSCOMMAND_SKILL1 = "Habilidad 1 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL2 = "Habilidad 2 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL3 = "Habilidad 3 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL4 = "Habilidad 4 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL5 = "Habilidad 5 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL6 = "Habilidad 6 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL7 = "Habilidad 7 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL8 = "Habilidad 8 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL9 = "Habilidad 9 (alt: sobre ti)"
BINDING_NAME_RTSCOMMAND_SKILL10 = "Habilidad 10 (alt: sobre ti)"
BINDING_HEADER_RTSCOMMAND_WINDOWS = "RTS Command - ventanas"
BINDING_NAME_RTSCOMMAND_GROUP3 = "Control group 3 (alt: store)"
BINDING_NAME_RTSCOMMAND_GROUP4 = "Control group 4 (alt: store)"

--- Binding entry points ----------------------------------------------------
-- Referenced by Bindings.xml. Must be globals.

function RTSCommand_SelectIndex(i)
	local roster = ns.Selection:GetRosterWithPlayer()
	local m = roster[i]
	if not m then return end

	if IsShiftKeyDown() or IsControlKeyDown() then
		ns.Selection:Toggle(m.name)
	else
		ns.Selection:SelectOnly(m.name)
	end
end

function RTSCommand_SelectAll()
	ns.Selection:SelectAll()
end

function RTSCommand_ClearSelection()
	ns.Selection:Clear()
end

-- Alt held = store the current selection, otherwise recall.
function RTSCommand_ControlGroup(i)
	if IsAltKeyDown() then
		ns.Selection:SaveGroup(i)
	else
		ns.Selection:RecallGroup(i)
	end
end

function RTSCommand_OrderMove()   ns.Orders:MoveToCursor() end
function RTSCommand_OrderHold()   ns.Orders:Hold()   end
function RTSCommand_OrderFollow() ns.Orders:Follow() end
function RTSCommand_OrderAttack() ns.Orders:Attack() end
function RTSCommand_OrderAttackMove() ns.RTSMode:AttackMoveToCursor() end
-- LAS TECLAS DE LA SALA SE FUERON CON ELLA. `RTSCommand_ReleasePossession`,
-- `RTSCommand_ToggleCommandMode` y los diez `RTSCommand_CommandSlot` apuntaban
-- a `Skills`, que esta borrado, asi que estan fuera de `Bindings.xml` tambien:
-- una tecla que llama a una funcion inexistente da un error de Lua cada vez
-- que se pulsa, y dejar la funcion como cascara vacia es peor -- responde y no
-- hace nada, que es el fallo silencioso de siempre.
--
-- Nota: los diez `RTSCommand_CommandSlot` YA estaban colgando de esa forma
-- desde que se borro `CommandMode.lua`. Se vio al quitar los otros dos.

-- Los paneles flotantes que esta tecla encendia y apagaba estan borrados, y la
-- consola que la heredo tambien. Lo que queda que se pueda ensenar y esconder es
-- la barra de abajo, asi que la tecla es suya.
function RTSCommand_ToggleUI()
	if not ns.RTSMode:IsActive() then
		ns.Print("|cff888888la barra solo esta puesta en modo RTS.|r")
		return
	end
	if ns.Dock.active then ns.Dock:Leave() else ns.Dock:Enter() end
end

function RTSCommand_ToggleRTSMode()
	ns.RTSMode:Toggle()
end

-- Las bolsas de todo el grupo. La tecla natural es I, pero NO se asigna sola:
-- asignar teclas por nuestra cuenta pisa lo que el jugador tuviera puesto, y
-- este addon tiene la regla dura de devolver todo como estaba. Sale en
-- Opciones > Teclas, bajo "RTS Command".
function RTSCommand_ToggleBags()
	ns.Bags:Toggle()
end

-- LA TECLA DE POSEER SE FUE CON LA POSESION, 2026-09-11. Ver el bloque de
-- `RTSCommand_ReleasePossession` justo arriba: una tecla que llama a una
-- funcion inexistente da un error de Lua en cada pulsacion, asi que sale de
-- `Bindings.xml` en el mismo cambio -- y dejar la funcion como cascara vacia
-- seria peor, porque responde y no hace nada.

-- LA TECLA DE CICLAR EL PRIMARIO SE FUE, y el CONCEPTO se queda.
--
-- `PRUEBAS-20` C3: *"casi funciona, puedo cambiar de heroe con tab, pero no
-- puedo volver atras. Tampoco se si usare tab (...) porque puedo clicar a los
-- personajes desde el tablero central de la consola. Puedes quitarlo"*.
--
-- El "no puedo volver atras" tenia arreglo -- en WoW, TAB y SHIFT-TAB son dos
-- asignaciones distintas, asi que `IsShiftKeyDown()` dentro de la de TAB no se
-- cumple nunca y habria hecho falta una segunda tecla. Pero el gesto entero
-- sobra: pinchar el retrato en la consola hace lo mismo y es lo que se va a
-- usar.
--
-- **El primario NO se va con la tecla.** Sigue siendo lo que decide de quien es
-- la barra de habilidades, y lo pone `Selection:Set` al seleccionar a UNO. Esa
-- es la mitad que importaba.

-- Las seis habilidades rapidas del primario. Sin Alt preguntan a quien; con Alt
-- van sobre ti.
-- LAS TECLAS VAN SOBRE LO QUE HAY DELANTE, que no es siempre lo mismo:
--
--   con uno cogido (o ninguno)  los DIEZ huecos del dueno de la barra
--   con dos o mas               los CUATRO de grupo, a TODOS los cogidos
--
-- La segunda mitad es la que no es obvia y es la que hace util la tecla: con
-- cuatro columnas en pantalla, "el hueco 2" pulsado a mano son cuatro clicks.
-- Y por eso las teclas 5..10 no hacen nada con varios cogidos: no existe un
-- quinto hueco de grupo, y mandar el quinto de OTRO juego seria lanzar un
-- hechizo que el jugador no esta viendo.
function RTSCommand_Skill(i)
	if ns.Dock:State() == "B" then
		if i > ns.Dock.B_SLOTS then
			ns.Print(("|cff888888con varios cogidos solo hay %d huecos.|r"):format(ns.Dock.B_SLOTS))
			return
		end
		for _, m in ipairs(ns.Dock:Columns()) do
			ns.Skills:Use(m.name, i, "group")
		end
		return
	end
	ns.Skills:Use(ns.Dock:Subject(), i, "main")
end

function RTSCommand_Calibrate()
	ns.Markers:Calibrate()
end

function RTSCommand_ToggleCamera()
	ns.Camera:Toggle()
end

--- Slash commands ----------------------------------------------------------

local HELP = {
	"|cffffff00/rts mode|r - enter and leave RTS mode (camera, mouse, bottom bar)",
	"|cffffff00/rts all|r - select every bot",
	"|cffffff00/rts clear|r - clear selection",
	"|cffffff00/rts list|r - list the roster",
	"|cffffff00/rts move|r / |cffffff00hold|r / |cffffff00follow|r / |cffffff00attack|r",
	"|cffffff00/rts rally|r - everyone WALKS to where you are (the Rally slot teleports them); |cffffff00skull|r / |cffffff00moon|r mark your target",
	"|cffffff00/rts reset|r - factory behaviour for the whole party",
	"|cffffff00/rts form <name>|r - " .. table.concat({ "near", "far", "melee", "queue", "chaos", "circle", "line", "shield", "arrow" }, ", "),
	"|cffffff00/rts cmd <text>|r - send any raw playerbots command to the selection",
	"|cffffff00/rts amove|r - attack-move to the cursor",
	"|cffffff00/rts flare|r - order marker settings (time/size/start/hold/alpha/ease/fade)",
	"|cffffff00/rts markers|r - halo that follows the mouse pointer (off by default)",
	"|cffffff00/rts radar|r - marks where the free camera is on the WORLD MAP (|cffffff00on|r/|cffffff00off|r)",
	"|cffffff00/rts route|r - routes with shift + right-click; |cffffff00off|r turns them off",
	"|cffffff00/rts mark|r - the ground marker on each waypoint: |cffffff00next|prev|find|r picks the visual, |cffffff00size|r the size",
	"|cffffff00/rts loot|r - free-for-all party loot; |cffffff00/rts lootall|r makes the bots pick up everything",
	"|cffffff00/rts self|r - your own character fights with the playerbots AI; |cffffff00auto|r / |cffffff00status|r",
	"|cffffff00/rts tri|r - green triangle over heads (parked; |cffffff00/rts tri help|r)",
	"|cffffff00/rts turn|r - why a click got eaten: measures camera turn against the threshold",
	"|cffffff00/rts halo <0-2>|r - cursor halo style, |cffffff00/rts halo size <yards>|r",
	"|cffffff00/rts ring|r - native ring under the selection; |cffffff00tint|r adds the model glow, |cffffff00test|r checks the hook",
	"|cffffff00/rts cam|r - detached RTS camera (WASD on the plane, SPACE/C up and down, Q/E pivot, right-drag turns)",
	"|cffffff00/rts cam save|r - frame it how you want, then save; |cffffff00show|r reprints the values",
	"|cffffff00/rts cam frame|r - re-apply it; |cffffff00tilt|r / |cffffff00zoom|r / |cffffff00fov <deg>|r nudge; |cffffff00clear|r forgets it",
	"|cffffff00/rts cam fly|r / |cffffff00fly 0|r - forward follows your view, or runs flat (RTS)",
	"|cffffff00/rts cam here|r - recentre over your character; |cffffff00mouse|r toggles mouse steering",
	"|cffffff00/rts fc|r - free camera settings (speed, height, smoothing, turning)",
	"|cffffff00/rts fc home|r - brings the camera back over your hero if it gets stuck",
	"|cffffff00/rts fc eyes|r - puts the camera above your hero facing his way, and attaches it (RIGHT-click the Lock slot)",
	"|cffffff00/rts cam probe|r - PROBE: is the client free camera usable here? (|cffffff00spec 0|r leaves)",
	"|cffffff00/rts cam collision|r - the camera passes through geometry (caves); |cffffff00geo|r inventories the rest",
	"|cffffff00/rts cam speed <n>|r - how fast it flies",
	"|cffffff00/rts cam shadow <0-5>|r - shadow under characters (-1 leaves it alone)",
	"|cffffff00/rts channel|r - what the DLL is being told about your selection",
	"|cffffff00/rts state|r - the tint colour each selected unit is being given",
	"|cffffff00/rts cal|r - measure the projection (fixes rings that sit short)",
	"|cffffff00/rts aim|r - why the ground point lands where it lands (cursor vs the DLL ray)",
	"|cffffff00/rts version|r - versions of all three pieces (addon, server, DLL)",
	"|cffffff00/rts pick|r / |cffffff00pick on|r - what is under the cursor, once or continuously",
	"|cffffff00/rts debug|r - echo every message to and from the server module",
	"|cffffff00/rts native|r - rts_core.dll status + offset self-test",
	"|cffffff00/rts ui|r - what gets hidden on entering RTS mode (by default, only the action bars)",
	"|cffffff00/rts macros|r - exports the catalogue as REAL GAME macros (for bars and key binds)",
	"|cffffff00/rtscmd <cmd>|r - send a playerbots command to the SELECTION; |cffffff00/rtsall|r to the party",
	"|cffffff00/rts art|r - client texture browser (to dress the UI without drawing)",
	"|cffffff00/rts bags|r - the bags of the whole party (also on its own key)",
	"|cffffff00/rts quests|r - the WHOLE party's quest log; |cffffff00blizzard|r opens the game's own",
	"|cffffff00/rts quests force|r - when you turn in, the party completes and gets paid too",
	"|cffffff00/rts quests ai|r - gives back (or removes) playerbots' automatic turn-in",
	"|cffffff00/rts skills|r - the spell slots: your ten and the four group ones",
	"|cffffff00/rts chain|r - the attack chain; |cffffff00/rts chain off|r clears it",
	"|cffffff00/rts npc|r - trainer and vendor, acting as the primary",
	"|cffffff00/rts swap <name>|r - you BECOME that character of your account (with a load)",
	"|cffffff00/rts win|r - the floating windows; |cffffff00/rts win reset|r recentres them",
	"|cffffff00/rts skin|r - WC3 or flat look; |cffffff00/rts skin wall <path>|r swaps one piece",
	"|cffffff00/rts dock|r - the bottom bar: state, slot size, columns",
	"|cffffff00/rts bring|r - teleports them to your side AND they follow you",
	"|cffffff00/rts chat|r - the bots' gossip dump; |cffffff00show|r brings it back, |cffffff00off|r lets it through",
	"|cffffff00/rts invite|r - puts your bots in the party; |cffffff00list|r shows or changes them",
	"|cffffff00/rts orders|r - the catalogue that opens on right-clicking a slot",
	"|cffffff00/rts tray|r - what each slot holds; |cffffff00clear|r empties them",
	"|cffffff00/rts portraits|r - the game frames that select when clicked; |cffffff00glow <n>|r raises the mark",
	"|cffffff00/rts focus|r - the selected unit looks after whoever you click; |cffffff00unfocus|r drops it",
	"Bind keys under Key Bindings -> RTS Command.",
}

SLASH_RTSCOMMAND1 = "/rts"
SlashCmdList["RTSCOMMAND"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	-- `/rts` a secas ensena la ayuda. Antes encendia y apagaba los tres paneles
	-- flotantes, que ya no existen; dejarlo encendiendo la barra habria hecho que
	-- teclear `/rts` por costumbre te cambiara la pantalla.
	if cmd == "" or cmd == "help" then
		for _, line in ipairs(HELP) do ns.Print(line) end

	elseif cmd == "all" then
		ns.Selection:SelectAll()

	elseif cmd == "clear" then
		ns.Selection:Clear()

	elseif cmd == "list" then
		local roster = ns.Selection:GetRosterWithPlayer()
		if #roster == 0 then
			ns.Print("Roster is empty - no group members.")
		end
		for i, m in ipairs(roster) do
			ns.Print(("%d. %s%s"):format(i, m.name,
				ns.Selection:IsSelected(m.name) and " |cff00ff00[selected]|r" or ""))
		end

	elseif cmd == "move"   then ns.Orders:MoveToCursor()
	-- REUNIR, CRANEO Y LUNA eran tres casillas de la rejilla 4x4 y no tenian
	-- comando: se pulsaban o no existian. Al pasar la rejilla a macros lo
	-- primero que hace falta es una boca por la que el macro pueda hablar.
	elseif cmd == "reunir" or cmd == "rally" then ns.Orders:MoveToMe()
	elseif cmd == "craneo" or cmd == "skull" then ns.Orders:MarkTarget(false)
	elseif cmd == "luna"   or cmd == "moon"  then ns.Orders:MarkTarget(true)
	elseif cmd == "reset"  then ns.Orders:ResetAll()
	elseif cmd == "hold"   then ns.Orders:Hold()
	elseif cmd == "follow" then ns.Orders:Follow()
	elseif cmd == "attack" then ns.Orders:Attack()
	elseif cmd == "amove" then ns.RTSMode:AttackMoveToCursor()

	elseif cmd == "form" or cmd == "formation" then
		if rest == "" then
			ns.Print("Usage: /rts form <" .. table.concat(ns.Orders.FORMATIONS, "|") .. ">")
		else
			ns.Orders:Formation(rest:lower())
		end

	elseif cmd == "cmd" or cmd == "raw" then
		ns.Orders:Raw(rest)

	elseif cmd == "mode" or cmd == "rts" then
		ns.RTSMode:Toggle()

	elseif cmd == "cal" or cmd == "calibrate" then
		local sub = (rest or ""):lower()
		if sub == "start" or sub == "on" then
			ns.Calib:Start()
		elseif sub == "stop" or sub == "off" then
			ns.Calib:Stop()
		elseif sub == "report" or sub == "fit" then
			ns.Calib:Report()
		elseif sub == "apply" then
			ns.Calib:Apply()
		elseif sub == "auto" then
			ns.Calib:Auto()
		elseif sub == "dump" then
			ns.Calib:Dump()
		elseif sub == "clear" or sub == "reset" then
			ns.Calib:Reset()
		else
			ns.Print("Projection calibration - measures the projection from the")
			ns.Print("game's own mouseover picking, so no eyeballing is involved.")
			ns.Print("|cffffff00/rts cal start|r - begin recording")
			ns.Print("  then hover each bot, sweeping side to side, at several")
			ns.Print("  distances. Bots must be standing still.")
			ns.Print("|cffffff00/rts cal stop|r / |cffffff00report|r / |cffffff00apply|r / |cffffff00auto|r / |cffffff00dump|r / |cffffff00clear|r")
			ns.Print("Scales are derived from the camera's diagonal FOV by default;")
			ns.Print("|cffffff00auto|r restores that, |cffffff00apply|r overrides it with a measurement.")
		end

	elseif cmd == "punto" or cmd == "radar" then
		local sub = strlower(strtrim(rest or ""))
		if sub == "" or sub == "show" or sub == "status" then
			ns.Radar:Status()
		elseif sub == "on" or sub == "si" then
			ns.Radar:Set(true)
		elseif sub == "off" or sub == "no" then
			ns.Radar:Set(false)
		else
			ns.Radar:Toggle()
		end

	elseif cmd == "markers" then
		ns.Markers:Toggle()

	elseif cmd == "aim" or cmd == "punteria" then
		-- Por que el punto de suelo sale donde sale. Contesta si el rayo del
		-- DLL se esta usando o se esta descartando, y con que numeros.
		ns.Markers:AimToggle((rest or ""):match("^(%S*)"))

	elseif cmd == "loot" then
		ns.RTSMode:ToggleFreeLoot()

	elseif cmd == "lootall" or cmd == "botin" then
		-- Distinto de `loot`: aquel es QUIEN puede lootear (el metodo del
		-- grupo), este es QUE recogen los bots (`ll all` contra `ll normal`).
		ns.RTSMode:ToggleLootAll()

	elseif cmd == "self" or cmd == "selfbot" then
		local sub = (rest or ""):match("^(%S*)"):lower()
		if sub == "auto" then
			ns.RTSMode:SelfBotAuto()
		elseif sub == "status" or sub == "?" then
			ns.RTSMode:SelfBotStatus()
		else
			ns.RTSMode:SelfBotToggle()
		end

	elseif cmd == "route" or cmd == "ruta" or cmd == "rutas" then
		local sub, arg = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		if sub == "" or sub == "status" or sub == "?" then
			ns.Route:Report()
		elseif sub == "on" or sub == "off" or sub == "toggle" then
			ns.Route:Toggle()
		elseif sub == "clear" or sub == "borrar" then
			ns.Route:ClearAll()
			ns.Print("rutas borradas.")
		elseif ns.Route.cfg[sub] ~= nil then
			if not ns.Route:Tune(sub, arg) then ns.Route:Report() end
		else
			ns.Route:Report()
		end

	elseif cmd == "mark" or cmd == "marca" or cmd == "marcas" then
		ns.Marks:Command(rest)

	elseif cmd == "flare" then
		local sub, a1 = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		if sub == "" or sub == "status" or sub == "?" then
			ns.Flare:Status()
		elseif sub == "on" or sub == "off" or sub == "toggle" then
			ns.Flare:Toggle()
		elseif sub == "reset" then
			ns.Flare:Reset()
		else
			ns.Flare:Set(sub, a1)
		end

	elseif cmd == "ring" or cmd == "rings" or cmd == "circle" then
		local sub = (rest or ""):match("^(%S*)"):lower()
		local cfg = ns.SelectionRing
		if sub == "tint" then
			cfg:ToggleTint()
		elseif sub == "test" then
			cfg:ToggleTest()
		elseif sub == "status" or sub == "?" then
			cfg:Status()
		else
			cfg:Toggle()
		end


	elseif cmd == "cam" or cmd == "camera" then
		local sub, arg = rest:match("^(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		if sub == "speed" then
			ns.Camera:SetSpeed(arg)
		elseif sub == "fly" then
			ns.Camera:SetFly(arg ~= "0" and arg ~= "off")
		elseif sub == "frame" then
			ns.Camera:Frame()
		elseif sub == "save" then
			ns.Camera:SavePreset()
		elseif sub == "show" or sub == "values" then
			ns.Camera:Report()
		elseif sub == "clear" then
			ns.Camera:ClearPreset()
		elseif sub == "tilt" or sub == "zoom" or sub == "fov" or sub == "shadow" then
			ns.Camera:SetFrame(sub, arg)
		-- El sondeo de la camara libre del cliente. Son comandos de diagnostico,
		-- no funciones: ver el final de `Camera.lua`.
		elseif sub == "probe" or sub == "sondeo" then
			ns.Camera:Probe()
		elseif sub == "spec" then
			ns.Camera:Spectate(arg ~= "0" and arg ~= "off")
		elseif sub == "ctrl" or sub == "control" then
			ns.Camera:Control(arg == "1" or arg == "on")
		elseif sub == "colision" or sub == "collision" then
			ns.Camera:CameraCut(arg == "1" or arg == "on")
		elseif sub == "geo" then
			ns.Camera:Geo()
		elseif sub == "sspeed" then
			ns.Camera:SpecSpeed(arg)
		elseif sub == "mouse" or sub == "mouselook" then
			ns.Camera:ToggleMouselook()
		elseif sub == "here" or sub == "recenter" then
			ns.Camera:Recenter()
		elseif sub == "on" then
			ns.Camera:On()
		elseif sub == "off" then
			ns.Camera:Off()
		else
			ns.Camera:Toggle()
		end

	elseif cmd == "chat" then
		ns.Chatter:Report((rest or ""):match("^(%S*)"))

	elseif cmd == "traer" or cmd == "bring" then
		ns.Actions:Bring()

	elseif cmd == "invitar" or cmd == "invite" then
		ns.Actions:Invite(rest)

	elseif cmd == "ordenes" or cmd == "orders" then
		ns.Actions:Report()

	elseif cmd == "macros" or cmd == "macro" then
		-- Los mandos que van a las dos barras verticales de la derecha, que el
		-- modo RTS deja a la vista justo para esto. Ver Macros.lua.
		local sub = (rest or ""):match("^(%S*)"):lower()
		if sub == "" or sub == "build" or sub == "crear" then
			ns.Macros:Build()
		elseif sub == "list" or sub == "lista" then
			ns.Macros:List()
		elseif sub == "clear" or sub == "borrar" then
			ns.Macros:Clear()
		else
			ns.Macros:Status()
		end

	elseif cmd == "ui" then
		-- El interruptor de la opcion B del estudio: ocultado selectivo. Desde
		-- el rediseno del 2026-09-13 ya no lleva medidas: la HUD que las tenia
		-- se ha borrado y lo que dibuja el addon abajo se mide solo (el hueco
		-- vale lo que un boton de accion del juego).
		local sub = (rest or ""):lower():match("^(%S*)") or ""

		if sub == "" or sub == "status" or sub == "?" then
			ns.Chrome:Status()

		elseif sub == "what" or sub == "que" then
			ns.Chrome:What()

		elseif ns.Chrome.hide[sub] ~= nil then
			ns.Chrome:SetHidden(sub)
			ns.Print(("%s: %s"):format(sub,
				ns.Chrome.hide[sub] and "|cffff4040se oculta en modo RTS|r"
				or "|cff40ff40se deja como esta|r"))

		else
			ns.Print("|cffffff00/rts ui|r - que se esconde en modo RTS")
			local names = {}
			for _, sset in ipairs(ns.Chrome.SETS) do names[#names + 1] = sset.k end
			ns.Print("|cffffff00/rts ui <conjunto>|r - " .. table.concat(names, ", "))
			ns.Print("|cffffff00/rts ui what|r - nombrar lo que sigue visible en pantalla")
			ns.Print("De fabrica solo se esconden |cffffff00bars|r y |cffffff00side|r, " ..
				"que son las que sustituye la barra de abajo.")
		end

	elseif cmd == "dock" or cmd == "barra" then
		ns.Dock:Report()

	elseif cmd == "tray" or cmd == "bandeja" then
		local sub = (rest or ""):lower():match("^(%S*)") or ""
		if sub == "clear" or sub == "vaciar" then
			ns.Tray:Clear()
		else
			ns.Tray:Report()
		end

	elseif cmd == "pixels" or cmd == "pixeles" then
		ns.Pixels:Report()

	elseif cmd == "marcos" or cmd == "portraits" then
		ns.Portraits:Report(rest)

	-- CUIDAR, EN DOS TIEMPOS. Esta aqui y no en un boton porque el boton se
	-- fue con la rejilla: ahora es un macro (`/rts macros` crea "Cuidar"), y un
	-- macro no puede preguntar sobre quien. Asi que el comando ARMA el gesto y
	-- el segundo click, en el mundo, elige.
	elseif cmd == "focus" or cmd == "cuidar" then
		ns.Cast:StartFocus()

	elseif cmd == "unfocus" or cmd == "suelta" then
		local who = ns.Dock:Subject()
		if who then ns.Cast:ClearFocus(who) end

	elseif cmd == "fc" or cmd == "freecam" then
		-- Se corta la primera palabra y el RESTO se deja entero en vez de exigir
		-- dos palabras justas: un patron `^(%S*)%s*(%S*)$` devuelve nil en cuanto
		-- llega un argumento de mas, y entonces el comando cae en el informe y
		-- **parece no hacer nada** -- el peor sintoma posible para un ajuste.
		local sub, tail = rest:match("^(%S*)%s*(.-)%s*$")
		sub = (sub or ""):lower()
		local arg = (tail or ""):match("^(%S*)")
		if sub == "" or sub == "show" or sub == "status" then
			ns.FreeCam:Report()
		elseif sub == "mouse" or sub == "raton" then
			ns.FreeCam:Mouse()
		-- ANTES del `Set`, que es el cajon de sastre: `Set` no conoce `home`,
		-- asi que caeria ahi, se quejaria de que quiere un numero, y el comando
		-- parece roto justo cuando hace falta.
		elseif sub == "home" or sub == "casa" then
			ns.FreeCam:Home()
		-- EL CANDADO, que hasta el 2026-09-13 solo tenia boton (la casilla nueve
		-- de la rejilla). La rejilla se borro y su sitio es un macro, asi que
		-- necesita un comando por el que hablar.
		elseif sub == "lock" or sub == "candado" then
			ns.FreeCam:ToggleLock()
		-- LA PRIMERA PERSONA, que es el clic DERECHO de esa misma casilla. Tiene
		-- comando por lo mismo que el candado: la casilla lo lanza por aqui, y
		-- sin comando no habria forma de probarlo sin tener la bandeja puesta.
		elseif sub == "ojos" or sub == "eyes" or sub == "primera" then
			ns.FreeCam:ToggleEyes()
		else
			ns.FreeCam:Set(sub, arg)
		end

	elseif cmd == "bars" or cmd == "barras" then
		local sub = strlower(strtrim(rest or ""))
		if sub == "page" or sub == "pagina" then
			ns.DumpBarPage()
		elseif not ns.Link:HasServer() then
			ns.Print("|cffff8800barras:|r hace falta mod-rts.")
		else
			ns.SendServer("MYBARS")
		end

	elseif cmd == "swapui" then
		RTSCommandDB.swapReload = (RTSCommandDB.swapReload == false)
		ns.Print(("cambiar: refrescar la interfaz al cambiar de personaje |cffffff00%s|r."):format(
			RTSCommandDB.swapReload and "SI" or "NO"))

	elseif cmd == "swap" or cmd == "cambiar" then
		-- CAMBIAR DE PERSONAJE, SIN PASAR POR LA LISTA DE PERSONAJES.
		--
		-- La version del 2026-09-03 por la manana te sacaba a esa lista y tenias
		-- que entrar tu. Ya no: el servidor se traga el `SMSG_LOGOUT_COMPLETE`
		-- (que es lo unico que mandaba al cliente a esa pantalla) y manda la
		-- rafaga de login del otro personaje con el cliente todavia en el mundo.
		--
		-- Lo que hace que eso funcione es un paquete corriente: el cliente adopta
		-- como suyo cualquier objeto que llegue con `UPDATEFLAG_SELF`, y ese lo
		-- manda `Map::SendInitSelf` dentro del propio login. El detalle, con las
		-- direcciones del cliente, esta en `RtsSwap.h` y en `CLAUDE.md`.
		--
		-- Tu grupo se rehace solo: el heroe que dejas entra de bot y los demas
		-- vuelven detras.
		local who = strtrim(rest or "")

		-- SIN NOMBRE, EL QUE TENGAS COGIDO. Es lo que hacia la casilla "Control"
		-- de la rejilla 4x4, y es lo que permite que esto quepa en un macro: un
		-- macro no puede preguntar a quien.
		--
		-- UNO Y SOLO UNO. Con varios cogidos no hay respuesta correcta, y elegir
		-- el primero de la lista seria elegir por el jugador algo que no se puede
		-- deshacer sin otra carga.
		if who == "" then
			local sel = ns.Selection:Get()
			if #sel == 1 then
				who = sel[1]
			elseif #sel > 1 then
				ns.Print(("|cffff8800cambiar:|r hay %d seleccionados. Coge a UNO."):format(#sel))
				return
			end
		end

		if who == "" or who == ns.MyName() then
			ns.Print("cambiar: |cffffff00/rts swap <nombre>|r, o coge a un companero " ..
			         "y |cffffff00/rts swap|r a secas. Personaje de |cffffff00tu " ..
			         "cuenta|r, y no vale en combate.")
			ns.Print("|cff888888Pasas a SER ese personaje -- sus bolsas, su libro, sus " ..
			         "barras -- y el que dejas se queda de bot en tu grupo.|r")
		else
			if ns.RTSMode.active then ns.RTSMode:Toggle() end
			ns.SendServer("SWAP " .. who)
		end

	elseif cmd == "whoami" or cmd == "quiensoy" then
		-- QUIEN CREE EL CLIENTE QUE ES, con dos testigos independientes.
		--
		-- Existe por el cambio de personaje: el servidor puede decir "eres Avy" y
		-- el cliente seguir siendo Neferite, y desde fuera las dos cosas se ven
		-- igual. Los dos testigos separan los dos fallos posibles, que tienen
		-- arreglos distintos:
		--
		--   * `UnitName("player")` sale del guid activo del gestor de objetos del
		--     cliente (`objmgr+0xC0`), que es lo que escribe un objeto recibido con
		--     `UPDATEFLAG_SELF`. Si dice el nombre NUEVO, la identidad si cambio y
		--     lo roto es el estado del mundo, no la identidad.
		--   * el DLL lee ESE MISMO campo por su cuenta, sin pasar por Lua, y de ahi
		--     saca la posicion que publica. Si Lua dice un nombre y la posicion es
		--     la del otro, es cache de la interfaz y no del gestor de objetos.
		--
		-- Y las entradas al mundo dicen si hubo recarga: `SMSG_LOGIN_VERIFY_WORLD`
		-- NO HACE NADA si el mapa que trae es el que ya tienes, asi que un cambio
		-- entre dos personajes del mismo mapa no dispara `PLAYER_ENTERING_WORLD`.
		-- Si el numero no sube, el cliente no recargo -- que es justo lo que hay
		-- que saber para decidir si hace falta forzarlo.
		ns.Print(("|cffffff00player|r %s  |cff888888%s|r"):format(
			tostring(UnitName("player")), tostring(UnitGUID("player"))))

		-- LOS TRES CAMPOS QUE EL CLIENTE GUARDA APARTE, uno al lado del otro.
		-- `UnitName`, `UnitClass` y `UnitRace` sobre "player" NO miran el objeto:
		-- leen una ficha estatica que solo rellena la pantalla de seleccion de
		-- personaje (`0x00C79D18`, `0x00C79E89`, `0x00C79E8A`), o sea el paso que
		-- el cambio se salta. Todo lo demas -- vida, retrato, hechizos -- sale
		-- del objeto y es correcto, y esa mezcla es lo que hace el sintoma
		-- ilegible: retrato de uno, nombre del otro.
		--
		-- Aqui se imprimen los DOS: lo que dice el cliente y lo que decimos
		-- nosotros. Si difieren, hubo un cambio y la correccion esta actuando.
		ns.Print(("|cffffff00cliente|r %s / %s   |cffffff00nosotros|r %s / %s"):format(
			tostring(UnitName("player")), tostring(select(2, UnitClass("player"))),
			tostring(ns.MyName()), tostring(ns.MyClass())))
		ns.Print(("|cffffff00entradas al mundo|r %d   |cffffff00companeros|r %d"):format(
			ns.worldEntries or 0, GetNumPartyMembers() or 0))

		-- QUE FILA DE LAS 120 ESTA DIBUJANDO LA BARRA, que es el testigo que
		-- faltaba el 2026-09-04. Un guerrero, un druida o una pica dibujan la
		-- BARRA DE POSTURA (casillas 72-83 y siguientes) y no la pagina 1, y
		-- quien lo decide es `GetBonusBarOffset()`. Los dos numeros separan dos
		-- fallos con arreglos opuestos:
		--
		--   * postura>0 y la barra ensena la pagina 1 -> el dato esta bien y lo
		--     que no se entero es la interfaz: el golpecito de pagina de
		--     `RefreshAfterSwap` lo arregla.
		--   * postura=0 teniendo el personaje su aura de postura -> el que no se
		--     entero es el CLIENTE, y entonces el arreglo es del servidor.
		--
		-- `forma` es la misma pregunta por otra via, para que un `GetBonus...`
		-- que no exista en este cliente no se lea como un cero legitimo.
		ns.Print(("|cffffff00pagina|r %s   |cffffff00postura|r %s   |cffffff00forma|r %s"):format(
			tostring(type(GetActionBarPage) == "function" and GetActionBarPage() or "?"),
			tostring(type(GetBonusBarOffset) == "function" and GetBonusBarOffset() or "?"),
			tostring(type(GetShapeshiftForm) == "function" and GetShapeshiftForm() or "?")))

		-- EL GRUPO CON SUS GUIDS, porque el fallo que esto persigue es que un
		-- compañero y tu parezcais el mismo. Con los guids delante se ve de un
		-- vistazo si es una coincidencia de nombre o de identidad, que son dos
		-- cosas distintas y solo una es un fallo del cliente.
		for i = 1, (GetNumPartyMembers() or 0) do
			local u = "party" .. i
			ns.Print(("  |cff888888%s|r %s  |cff666666%s|r"):format(
				u, tostring(UnitName(u)), tostring(UnitGUID(u))))
		end

		if RTS_Ready == 1 then
			ns.Print(("|cffffff00DLL|r hasPos=%s  %.1f, %.1f, %.1f"):format(
				tostring(RTS_HasPos), RTS_PX or 0, RTS_PY or 0, RTS_PZ or 0))
		else
			ns.Print("|cff888888DLL: no inyectado, solo vale la linea de arriba.|r")
		end

	elseif cmd == "npc" or cmd == "personaje" then
		-- El entrenador / vendedor, actuando como el primario. Sobre lo que
		-- tengas apuntado, que es el camino sin raton.
		if UnitExists("target") then
			ns.Npc:Toggle(UnitGUID("target"), UnitName("target"))
		else
			ns.Print("personaje: apunta a un entrenador o vendedor primero.")
		end

	elseif cmd == "chain" or cmd == "cadena" then
		if (rest or ""):lower():match("^off") or (rest or ""):lower():match("^clear") then
			ns.Chain:Clear()
		else
			ns.Chain:Report()
		end

	elseif cmd == "skills" or cmd == "habilidades" then
		local sub, arg = (rest or ""):match("^(%S*)%s*(.*)$")
		sub = (sub or ""):lower()
		if sub == "reset" or sub == "limpiar" then
			-- EL PRIMARIO Y NO `Hall:Subject()`, que desde la 0.80.0 es nil con
			-- nada cogido -- y entonces esto limpiaria los huecos de quien
			-- decidiera `ClearSlots` por su cuenta. Se dice el nombre al
			-- limpiar: borrar la configuracion de quien no era es de las cosas
			-- que no se pueden deshacer.
			ns.Skills:ClearSlots(arg ~= "" and arg or ns.Selection:GetPrimary())
		else
			ns.Skills:Report()
		end

	elseif cmd == "quests" or cmd == "misiones" then
		local sub = (rest or ""):lower():match("^(%S*)") or ""
		if sub == "ai" or sub == "ia" then
			-- El interruptor de la maquinaria de misiones de playerbots. Existe
			-- para que apagarla no sea un cambio permanente y escondido: la
			-- apagamos porque entrega sola al ABRIR la ventana de un PNJ, y eso
			-- es una decision que el jugador tiene que poder deshacer.
			local on = not ns.RTSMode.questAI
			ns.RTSMode.questAI = on
			RTSCommandDB.questAI = on
			ns.RTSMode:ApplyQuestAI()
			ns.Print("misiones: IA de misiones de los bots " ..
				(on and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
			ns.Print(on
				and "  vuelven a entregar solos al abrir la ventana de un PNJ."
				or  "  solo entregan cuando pulsas tu el boton de completar.")
			return
		end
		if sub == "force" or sub == "forzar" then
			local on = not ns.Quests:Force()
			ns.Quests:Force(on)
			ns.Print("misiones: entrega FORZADA " ..
				(on and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
			ns.Print(on
				and "  al entregar tu, los demas completan y cobran aunque no la llevaran hecha."
				or  "  al entregar tu, solo cobran los que ya la tuvieran lista.")
			return
		end
		-- SIN ARGUMENTO, EL REGISTRO DEL GRUPO, y esto cambia el 2026-09-14.
		--
		-- Abria el de Blizzard, que es el mismo argumento que ya se escribio una
		-- vez en la casilla de la rejilla 4x4: el registro del cliente esta a un
		-- click en el menu de juego -- que ahora vive en la bandeja -- asi que
		-- gastar el comando corto en un atajo a algo que ya tiene atajo deja sin
		-- boca a lo unico que NO tiene otra: el registro de los companeros.
		--
		-- El de Blizzard sigue aqui, en |cffffff00/rts misiones mio|r.
		if sub == "mio" or sub == "propio" or sub == "blizzard" then
			ns.Quests:Open()
		else
			ns.QuestBook:Toggle()
		end

	elseif cmd == "bags" or cmd == "bolsas" then
		ns.Bags:Toggle()

	elseif cmd == "win" or cmd == "ventana" then
		-- Las ventanas flotantes (bolsas, quests, entrenador). Aqui solo se
		-- listan y se recolocan: abrirlas es cosa de cada una, con su tecla.
		local sub = (rest or ""):match("^(%S*)") or ""
		if sub:lower() == "reset" then
			ns.Window:ResetAll()
		else
			ns.Window:Report()
		end

	elseif cmd == "skin" or cmd == "piel" then
		-- El aspecto de las ventanas. Pensado para usarse con /rts art al lado:
		-- se mira una textura, se copia su ruta con un click, se pega aqui.
		local sub, arg = rest:match("^(%S*)%s*(.-)$")
		sub = (sub or ""):lower()
		if sub == "" then
			ns.Skin:Toggle()
		elseif sub == "status" or sub == "?" then
			ns.Skin:Status()
		elseif sub == "default" or sub == "reset" then
			ns.Skin:Reset()
		elseif ns.Skin.tex[sub] ~= nil then
			if not ns.Skin:Set(sub, strtrim(arg or "")) then
				ns.Print(("|cffffff00/rts skin %s <ruta>|r - ahora %s")
					:format(sub, ns.Skin.tex[sub]))
			end
		else
			ns.Skin:Status()
		end

	elseif cmd == "art" then
		-- Que texturas del cliente existen de verdad, mirandolas. Es el paso
		-- previo a vestir una ventana: una ruta que no carga no da error, dibuja
		-- nada, y construir encima de eso se descubre tarde.
		local sub = (rest or ""):lower()
		if sub == "" then
			ns.Art:Toggle()
		elseif sub == "next" or sub == "+" then
			ns.Art:Page(1)
		elseif sub == "prev" or sub == "-" then
			ns.Art:Page(-1)
		elseif sub == "scan" then
			ns.Art:Scan()
		elseif sub == "all" or sub == "todo" then
			ns.Art:Filter("")
		else
			ns.Art:Filter(sub)
		end

	elseif cmd == "channel" then
		ns.Channel:Dump()

	elseif cmd == "state" then
		-- Why each unit is the colour it is: the order still standing, and the
		-- two live signals that decide how long that order keeps its colour.
		local COLOUR = {
			[ns.UnitState.SELECTED] = "|cff2a72ffblue|r   selected",
			[ns.UnitState.MOVING]   = "|cff1aff40green|r  moving",
			[ns.UnitState.COMBAT]   = "|cffff1a1ared|r    combat",
			[ns.UnitState.INTERACT] = "|cffff8c1aorange|r interact",
		}
		local sel = ns.Selection:Get()
		if #sel == 0 then ns.Print("Nothing selected.") end
		for _, name in ipairs(sel) do
			local unit = ns.Selection:UnitFor(name)
			local guid = unit and UnitGUID(unit)
			-- Read the order BEFORE Code(), which drops it once it has expired.
			local o = ns.UnitState.orders[name]
			local code = ns.UnitState:Code(name, unit, guid)
			local track = guid and ns.Markers.track[string.upper(guid)]
			ns.Print(("%s -> %s"):format(name, COLOUR[code] or tostring(code)))
			ns.Print(("    order=%s%s  incombat=%s  lastmoved=%s")
				:format(o and o.kind or "none",
				        o and (" %.1fs ago"):format(GetTime() - o.at) or "",
				        unit and tostring(UnitAffectingCombat(unit) and true or false) or "?",
				        track and ("%.2fs"):format(GetTime() - track.ct) or "not published"))
		end

	elseif cmd == "turn" then
		local M = ns.RTSMode
		local eps = tonumber(rest:match("^eps%s+([%d%.]+)$"))
		if eps and eps > 0 then
			M.turnEps = eps
			RTSCommandDB.turnEps = eps
			ns.Print(("umbral de giro = %.4f"):format(eps))
		elseif rest == "reset" then
			M.turnEps = 0.05
			RTSCommandDB.turnEps = nil
			ns.Print("umbral de giro devuelto a 0.0500")
		elseif rest == "" then
			M.turnDebug = not M.turnDebug
			ns.Print("informe de clicks " ..
				(M.turnDebug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
				.. (" - umbral actual %.4f"):format(M.turnEps))
			if M.turnDebug then
				ns.Print("Cada click dira cuanto giro la camara mientras lo hacias.")
				ns.Print("Un click quieto deberia dar un numero PEQUENO; un arrastre")
				ns.Print("para girar, uno GRANDE. El umbral va entre los dos.")
				ns.Print("Si sale |cffff0000TRAGADO|r en clicks que querias dar, subelo:")
				ns.Print("|cffffff00/rts turn eps <n>|r")
			end
		else
			ns.Print("|cffffff00/rts turn|r - informe por click (giro medido vs umbral)")
			ns.Print("|cffffff00/rts turn eps <n>|r - cambiar el umbral; |cffffff00reset|r lo devuelve")
			ns.Print(("umbral actual %.4f"):format(M.turnEps))
		end

	elseif cmd == "halo" then
		local h = ns.Markers.halo
		local n = tonumber(rest)
		local size = tonumber(rest:match("^size%s+([%d%.]+)$"))
		if size then
			h.size = size
			RTSCommandDB.haloSize = size
			ns.Print(("halo size = %.1f yards across"):format(size))
		elseif n and h.styles[n] then
			h.style = n
			RTSCommandDB.halo = n
			ns.Print(("halo style %d - %s"):format(n, h.styles[n].name))
		else
			ns.Print("|cffffff00/rts halo <n>|r - switch the cursor halo:")
			for i = 0, 2 do
				ns.Print(("  %d %s%s"):format(i, h.styles[i].name,
					h.style == i and " |cff00ff00<-- current|r" or ""))
			end
			ns.Print("|cffffff00/rts halo size <yards>|r - " ..
				("currently %.1f"):format(h.size))
		end

	elseif cmd == "tri" or cmd == "triangle" then
		local sub, a1, a2 = rest:match("^(%S*)%s*(%S*)%s*(%S*)$")
		sub = (sub or ""):lower()
		local cfg = ns.Markers.tri
		local n1, n2 = tonumber(a1), tonumber(a2)

		if sub == "" then
			ns.Markers:ToggleTriangles()
		elseif sub == "mobs" then
			cfg.mobs = not cfg.mobs
			ns.Print("triangles over mobs " .. (cfg.mobs and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		elseif sub == "sel" or sub == "selection" then
			cfg.sel = not cfg.sel
			ns.Print("triangles over selection " .. (cfg.sel and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		elseif sub == "height" and n1 then
			cfg.height = n1
			ns.Print(("triangle height = %.1f yards above the feet"):format(n1))
		elseif sub == "scale" and n1 then
			cfg.scale = n1
			ns.Print(("triangle scale = %d (pixel size at 1 yard)"):format(n1))
		elseif sub == "size" and n1 then
			cfg.min = n1
			if n2 then cfg.max = n2 end
			ns.Print(("triangle size clamped to %d..%d px"):format(cfg.min, cfg.max))
		else
			ns.Print("|cffffff00/rts tri|r - toggle the head triangles")
			ns.Print("|cffffff00/rts tri mobs|r / |cffffff00sel|r - which units get one")
			ns.Print("|cffffff00/rts tri height <yards>|r - raise or lower it over the head")
			ns.Print("|cffffff00/rts tri scale <n>|r - how fast it shrinks with distance")
			ns.Print("|cffffff00/rts tri size <min> [max]|r - pixel clamp")
			ns.Print(("now: %s  mobs=%s sel=%s height=%.1f scale=%d size=%d..%d")
				:format(cfg.enabled and "ON" or "OFF", tostring(cfg.mobs), tostring(cfg.sel),
				        cfg.height, cfg.scale, cfg.min, cfg.max))
		end
		RTSCommandDB.tri = cfg

	elseif cmd == "units" then
		-- Diagnostic: dump every unit position the DLL publishes, vs the player.
		local pn = RTS_UN or 0
		ns.Print(("player: %.2f, %.2f, %.2f  (facing %.2f)"):format(RTS_PX or 0, RTS_PY or 0, RTS_PZ or 0, RTS_PF or 0))
		ns.Print(("published units: %d"):format(pn))
		for i = 1, pn do
			local g = _G["RTS_U" .. i .. "G"]
			local ux = _G["RTS_U" .. i .. "X"]
			local uy = _G["RTS_U" .. i .. "Y"]
			local uz = _G["RTS_U" .. i .. "Z"]
			local dist = math.sqrt((ux - RTS_PX)^2 + (uy - RTS_PY)^2)
			ns.Print(("  %d %s  %.2f, %.2f, %.2f  (%.1fy away)"):format(i, tostring(g), ux, uy, uz, dist))
		end
		-- Compare to what the client's own API says about a party member.
		if GetNumPartyMembers() > 0 then
			ns.Print(("party1 guid = %s"):format(tostring(UnitGUID("party1"))))
		end

		-- Resolve each SELECTED unit exactly as the ring code does.
		ns.Print("--- selection resolution ---")
		for _, name in ipairs(ns.Selection:Get()) do
			local unit = ns.Selection:UnitFor(name)
			local guid = unit and UnitGUID(unit)
			local x, y, z = ns.Markers:UnitWorld(guid)
			if x then
				local d = math.sqrt((x - RTS_PX)^2 + (y - RTS_PY)^2)
				ns.Print(("%s -> token=%s guid=%s -> pos %.2f,%.2f (%.1fy from you)")
					:format(name, tostring(unit), tostring(guid), x, y, d))
			else
				ns.Print(("%s -> token=%s guid=%s -> |cffff0000NO MATCH in map|r")
					:format(name, tostring(unit), tostring(guid)))
			end
		end

	elseif cmd == "pick" then
		-- `/rts pick` samples once, wherever the cursor happens to be when you
		-- press Enter -- which is rarely where you were hovering. `/rts pick on`
		-- prints continuously so you can hover a wolf and watch.
		local sub = (rest or ""):lower()
		if sub == "on" or sub == "off" then
			ns.RTSMode:LivePick(sub == "on")
		else
			ns.RTSMode:PickReport()
		end

	elseif cmd == "body" or cmd == "cuerpo" then
		local a, b = rest:match("^(%S*)%s*(%S*)$")
		a = (a or ""):lower()
		b = (b or ""):lower()
		if a == "" or a == "status" then ns.Body:Report()
		elseif a == "help" or a == "ayuda" then ns.Body:Help()
		elseif a == "flags" then
			if b == "auto" then ns.Body:FlagsAuto()
			elseif b == "uber" then ns.Body:OneBit("uber")
			elseif b == "comm" or b == "commentator" then ns.Body:OneBit("comm")
			else ns.Body:Flags(b ~= "off" and b ~= "no") end
		elseif a == "skip" or a == "salto" then
			ns.Body:Skip(b ~= "off" and b ~= "no")
		elseif a == "log" then
			ns.Body:Log(b ~= "off" and b ~= "no")
		elseif a == "look" or a == "mirar" or a == "cam" then ns.Body:Look()
		elseif a == "invert" or a == "todos" then
			ns.Body:Invert(b ~= "off" and b ~= "no")
		elseif a == "nofix" then
			ns.Body:NoFix(b ~= "off" and b ~= "no")
		elseif a == "blink" or a == "parpadeo" then
			ns.Body:Blink(b ~= "off" and b ~= "no")
		elseif a == "attack" or a == "atacar" or a == "espada" then
			ns.Body:Attack(b ~= "off" and b ~= "no")
		elseif a == "sites" or a == "sitios" then
			if b == "all" or b == "todos" then ns.Body:Sites(63)
			else ns.Body:Sites(0) end
		elseif a == "site" or a == "sitio" then
			local n = tonumber(b)
			if n and n >= 0 and n <= 17 then ns.Body:Sites(n + 1)
			else ns.Print("|cffff0000body:|r |cffffff00/rts body site 0..17|r") end
		elseif a == "reset" or a == "off" then ns.Body:Off()
		else ns.Body:Help() end

	elseif cmd == "debug" then
		ns.Link.debug = not ns.Link.debug
		ns.Print("channel debug " .. (ns.Link.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r")
			.. " - shows every message to and from mod-rts.")

	elseif cmd == "pickradius" then
		local n = tonumber(rest)
		if n then
			ns.RTSMode.hostilePickRadius = n
			ns.Print(("hostile pick radius = %d px"):format(n))
		else
			ns.Print(("hostile pick radius is %d px - |cffffff00/rts pickradius <px>|r")
				:format(ns.RTSMode.hostilePickRadius))
		end

	elseif cmd == "version" or cmd == "ver" then
		ns.Print(("addon      |cffffff00%s|r"):format(GetAddOnMetadata(ADDON, "Version") or "?"))
		ns.Print(("mod-rts    %s"):format(ns.Link.serverVersion
			and ("|cff00ff00" .. ns.Link.serverVersion .. "|r")
			or "|cffff0000not answering|r"))
		ns.Print(("rts_core   %s"):format(RTS_Ready == 1
			and ("|cff00ff00" .. tostring(RTS_Version) .. "|r")
			or "|cffff0000not injected|r"))

	elseif cmd == "native" then
		ns.Bridge:TryAttach()
		if not ns.Bridge:IsNative() then
			ns.Print("native bridge |cffff0000not attached|r - rts_core.dll is not injected.")
			ns.Print("Orders still work; coordinates and click-to-move do not.")
		else
			ns.Print(("native bridge |cff00ff00attached|r, rts_core %s (heartbeat %s)")
				:format(ns.Bridge.version or "?", tostring(ns.Bridge:Heartbeat())))
			local x, y, z, f = ns.Bridge:GetPlayerWorldPosition()
			if x then
				ns.Print(("player world pos: %.2f, %.2f, %.2f (facing %.2f)"):format(x, y, z, f or 0))
			else
				ns.Print("|cffff0000no position yet|r - are you in the world?")
			end
			local n = ns.Bridge:ObjectCount()
			if n then ns.Print(("objects tracked: %d"):format(n)) end

			-- Raycast self-test: ground Z under the player should match player Z.
			if RTS_GroundHit == 1 and x then
				local dz = RTS_GroundZ - z
				local ok = (math.abs(dz) < 2.0) and "|cff00ff00OK|r" or "|cffffff00check|r"
				ns.Print(("raycast: ground Z %.2f vs player Z %.2f (%.2f diff) %s")
					:format(RTS_GroundZ, z, dz, ok))
			elseif RTS_GroundHit == 0 then
				ns.Print("|cffff0000raycast: no ground hit|r (offset may be wrong)")
			end

			-- Cursor terrain raycast -- what a click-to-move order will use.
			if RTS_CurHit == 1 then
				ns.Print(("|cff00ff00cursor ground:|r %.1f, %.1f, %.1f"):format(RTS_CurX, RTS_CurY, RTS_CurZ))
			elseif RTS_CurHit == 0 then
				ns.Print("|cffffff00cursor ray: no hit|r (pointing at sky, or cursor off-window)")
			else
				ns.Print("|cffffff00cursor ray: absent|r - rts_core older than 0.8.0")
			end

			-- Camera + screen-centre look-at point.
			if RTS_HasCam == 1 then
				ns.Print(("camera pos: %.1f, %.1f, %.1f"):format(RTS_CamX, RTS_CamY, RTS_CamZ))
				if RTS_LookHit == 1 then
					ns.Print(("|cff00ff00look-at ground:|r %.1f, %.1f, %.1f"):format(RTS_LookX, RTS_LookY, RTS_LookZ))
				else
					ns.Print("|cffffff00look-at: no hit|r (aim at ground, not sky)")
				end
			else
				ns.Print("|cffff0000camera not read|r - see rts_core.log")
			end
		end

	else
		ns.Print("Unknown command. Try |cffffff00/rts help|r.")
	end
end
