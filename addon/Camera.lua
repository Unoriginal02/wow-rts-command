--[[
	Camera.lua -- the detached RTS camera.

	The camera is NOT steered from here, and not from rts_core.dll either. The
	server summons an invisible creature and hands the client control of it
	(mod-rts, RtsCamera.cpp). The client's camera then follows it, because the
	camera always follows whatever unit the client is currently moving -- the
	same mechanism behind Eye of Kilrogg and Mind Control.

	So the movement keys need no work at all: WASD flies the camera, space and X
	raise and lower it, exactly as they would on a flying mount, because as far
	as the client is concerned that is what is happening.

	What IS left to this file:
	  - asking the server to start and stop the camera
	  - Q/E pivot, SPACE and C height -- WoW binds all four to something else

	=== the channel: SEE Link.lua ===========================================

	The transport used to live here and moved out on 2026-09-02. What matters
	from this file's side is unchanged: we ask, and we WAIT for the answer
	rather than assuming, because enabling can legitimately fail -- dead, in
	flight, in a vehicle -- and we take the player's Q and E keys on the way in.

	The server answers "CAM 1" / "CAM 0", which arrives through `Link:On("CAM")`
	below.
]]

local ADDON, ns = ...

local C = {}
ns.Camera = C

C.active = false

--- Making the angle stick --------------------------------------------------
--
-- cameraSmoothStyle is WoW's "adjust camera automatically": with it on, the
-- client slides the camera back behind the unit whenever it moves. In normal
-- play that is helpful. For an RTS camera it is fatal -- you tilt down to look
-- at the map, pan one step, and the client puts it back. That is the
-- "it re-tilts to the original position" behaviour, and re-applying our own
-- tilt could never win the argument, because the client re-runs its correction
-- every frame you move.
--
-- 0 = never adjust. Captured before it is changed and put back when the camera
-- goes off, so normal play is unaffected -- the discipline the nameplate CVars
-- had to learn after the first version of that set them and walked away.
--
-- Declared up here, above everything that calls it: these are locals, so a
-- definition further down the file would simply not exist yet at the point
-- OnState refers to it, and the call would find a nil global instead.
-- HARD RULE: everything RTS mode changes, RTS mode puts back. Outside it the
-- camera must be ordinary WoW -- third person, scroll to zoom, auto-adjust on.
-- So every CVar this file touches goes through here, and every one of them is
-- captured before its first change and restored on the way out. An earlier
-- version set cameraDistanceMaxFactor and never gave it back, which quietly
-- changed how far normal play could zoom out. That is the bug this prevents.
-- `rtsFov` no es un ajuste de camara -- es el canal que lleva lo unico que el
-- empaquetado de la seleccion no puede: un numero. El DLL lo lee como el campo
-- de vision que se quiere, en decimas de grado. Viaja en esta lista porque
-- necesita la misma disciplina que los CVars de verdad: capturado antes del
-- primer cambio y devuelto al salir -- que aqui significa volver a 0, o sea
-- "no toques el FOV", y con eso el angulo normal vuelve solo.
--
-- Hasta el 2026-09-06 esto era `guildMemberNotify`, tomado prestado. Ver mas
-- abajo: ese CVar no existe en este cliente y el canal llevaba tres etapas
-- muerto sin que nada lo dijera.
-- shadowLevel es la TERCERA que no es de camara, y esta si es lo que dice ser:
-- la sombra que el cliente dibuja bajo cada personaje. Se pidio en PRUEBAS-18
-- ("sombras mas duras y grandes debajo de los personajes para distinguirlos
-- mejor") y en este Config.wtf esta a 0, o sea apagadas -- comprobado abriendo
-- el fichero, que es como se comprueba un CVar en este proyecto desde
-- `gxWindowedResolution`.
--
-- LO QUE ESTE CVAR NO DA, dicho por delante: no hay mando de TAMANO ni de
-- DUREZA de la sombra en 3.3.5a. Es una escala de calidad, y lo unico que se
-- puede hacer es encenderla y subirla. Si con la sombra puesta las unidades
-- siguen sin distinguirse, la respuesta buena no es este CVar: es el circulo
-- nativo bajo los pies, que ya existe (etapa 5e) y admite color por unidad.
local FOV_CVAR = "rtsFov"

-- El canal de experimentos del modelo del heroe. Existe por la misma razon que
-- `rtsFov`: el canal empaquetado no tiene bits libres y esto necesita un NUMERO.
-- Ver `/rts fc poke` y `camera::Poke` en el DLL.
-- El canal de experimentos de CAMARA: offset en bytes y valor, en dos CVars
-- separados a proposito. Meter los dos en un entero obliga a desplazar el signo
-- para poder mandar negativos, y ahi es donde se equivocan estas cosas: un
-- `-1.5` que llega como `+1.5` se lee como "el candidato no era" cuando lo que
-- fallo fue el transporte. El DLL lee el float que el propio CVar guarda.

local CVARS = {
	"cameraSmoothStyle", "cameraDistanceMaxFactor", "cameraDistanceMax",
	FOV_CVAR, "shadowLevel",
}
-- UN CVAR NUESTRO, NO UNO PRESTADO -- y el prestado NUNCA EXISTIO.
--
-- El canal del FOV se escribio en la etapa 5g tomando prestado
-- `guildMemberNotify`, "un aviso del registro de hermandad, inerte en un
-- servidor solitario". La cadena esta en el `Wow.exe` -- por eso parecia buena
-- -- pero el cliente no la tiene registrada como CVar, y `rts_core.log` lo lleva
-- diciendo desde entonces en una linea que nadie leyo:
--
--     cvar: 'guildMemberNotify' not found -- channel unavailable
--
-- O sea que la camara isometrica de la etapa 5g **no se ha aplicado ni una sola
-- vez**, y las dos rondas que la dieron por arreglada (0.50.0 y la 0.52.0)
-- arreglaron cosas reales que eran necesarias y no suficientes. Tres intentos
-- sobre un canal que estaba muerto por debajo.
--
-- La cura es dejar de depender de que exista un CVar ajeno que nos venga bien:
-- `RegisterCVar` crea uno, y existe en este cliente (comprobado en el binario,
-- no de memoria). Con eso el canal no puede faltar, no pisa ningun ajuste de
-- nadie, y lo unico que deja detras es una linea en Config.wtf que dice lo que
-- es.
-- Se crea si no esta. `SetCVar` sobre un nombre que no existe **no da error**:
-- no hace nada, que es exactamente como este canal llevaba tres etapas
-- fallando.
--
-- Se llama desde `Create` y NO en el ambito del fichero, aunque ahi seria mas
-- corto: `ns.Print` todavia no existe cuando este fichero carga. Lo canto
-- el orden del `.toc` antes de recargar, que es donde se ve.
--
-- CADA CVar SE MIRA POR SU CUENTA, y eso arregla un fallo latente. La version
-- anterior registraba `rtsPoke` DENTRO del `if` de `rtsFov`, asi que en cuanto
-- el primero existia (queda escrito en Config.wtf) el segundo ya no se
-- registraba nunca. Funcionaba de casualidad, porque el segundo tambien queda
-- escrito -- pero un CVar nuevo anadido a la lista mas tarde no se habria
-- creado jamas en un cliente que ya tuviera el primero, y `SetCVar` sobre lo
-- que no existe **no da error**: no hace nada.
local OURS = { FOV_CVAR }

local function EnsureFovCVar()
	if type(RegisterCVar) == "function" then
		for _, cv in ipairs(OURS) do
			if GetCVar(cv) == nil then RegisterCVar(cv, "0") end
		end
	end
	if GetCVar(FOV_CVAR) ~= nil then return true end
	-- Si ni asi, se dice: es la diferencia entre "el FOV no se aplica" y una
	-- tarde buscando por que.
	ns.Print("|cffff0000camara:|r no puedo crear el CVar |cffffff00" .. FOV_CVAR ..
	         "|r; el angulo se quedara en el del cliente.")
	return false
end
local cvarWas = nil

local function HoldCamera(overrides)
	if not cvarWas then
		cvarWas = {}
		for _, cv in ipairs(CVARS) do cvarWas[cv] = GetCVar(cv) end
	end
	for cv, want in pairs(overrides or {}) do SetCVar(cv, want) end
end

local function ReleaseCamera()
	if not cvarWas then return end
	for _, cv in ipairs(CVARS) do
		if cvarWas[cv] ~= nil then SetCVar(cv, cvarWas[cv]) end
	end
	cvarWas = nil
end

--- Turn keys ---------------------------------------------------------------
-- WoW's own TURNLEFT/TURNRIGHT actions, not a per-frame Lua turn: the movement
-- system turns smoothly and continuously while the key is held, which nothing
-- driven from OnUpdate can match.
--
-- The previous bindings are restored on the way out and never saved, so a
-- reload, a disconnect or a crash leaves the player's real keys untouched --
-- SaveBindings is deliberately not called anywhere in this file.

local saved = {}

-- THE KEYS HAVE MOVED THREE TIMES AND THE SHAPE THAT SETTLED IS: mouse rotates,
-- Q/E pivot, SPACE and C raise and lower. Only the last hop is worth keeping as
-- history, because the other two were wrong for reasons that no longer apply:
-- Q/E first turned the camera in place (the mouse does that better) and then
-- carried the height, which left the pivot with nowhere to go.
--
-- Height is the camera's WORLD Z, not its distance from the group. An early
-- version made those keys zoom, which duplicated the scroll wheel and moved the
-- camera closer to and further from the party rather than up and down over it.
--
-- That has to go through the server. The camera creature is possessed, so the
-- client owns its position -- and with flight off (which is what makes WASD run
-- flat) the client has no vertical movement to offer at all. So the keys report
-- only their transitions, and the server moves the camera on its own tick for as
-- long as one is held. Two messages per press, not one per frame.
--
-- The keys are SPACE and C since 2026-08-23. Q and E are the pivot.
local held = { up = false, down = false }

local function Vertical(dir)
	ns.SendServer(("CAM ZV %d"):format(dir))
end

function RTSCommand_CameraDown(_, _, down)
	if held.down == down then return end
	held.down = down
	Vertical(down and -1 or 0)
end

function RTSCommand_CameraUp(_, _, down)
	if held.up == down then return end
	held.up = down
	Vertical(down and 1 or 0)
end

-- PIVOTE con Q/E, 2026-08-18.
--
-- Antes Q/E iban a TURNLEFT/TURNRIGHT del propio cliente, que gira la camara
-- SOBRE SI MISMA: lo que estabas mirando se va de pantalla. Pivotar la lleva en
-- arco alrededor del punto que mira, que se queda quieto mientras lo ves desde
-- otro lado -- el gesto de WC3/SC2.
--
-- El precio es que ya no lo puede hacer el cliente. Girar era gratis porque el
-- giro es suyo; orbitar es un cambio de POSICION, y la camara esta poseida, asi
-- que solo el servidor puede moverla. De ahi que estas teclas pasen a reportar
-- transiciones como +/- en vez de ir a una accion del juego.
local pivoting = { left = false, right = false }

local function Pivot(dir)
	ns.SendServer(("CAM PV %d"):format(dir))
end

function RTSCommand_CameraPivotLeft(_, _, down)
	if pivoting.left == down then return end
	pivoting.left = down
	Pivot(down and -1 or 0)
end

function RTSCommand_CameraPivotRight(_, _, down)
	if pivoting.right == down then return end
	pivoting.right = down
	Pivot(down and 1 or 0)
end

local function GrabTurnKeys()
	-- NO SI LA CAMARA LIBRE YA TIENE LAS TECLAS. Las dos usan `saved` para
	-- devolver lo que habia, asi que si la segunda captura por encima de la
	-- primera se apunta como "original" el binding de la primera -- y al salir
	-- el jugador se queda con ESPACIO haciendo de camara para siempre. Esa
	-- corrupcion no da ningun error: solo teclas que ya no son suyas.
	if ns.FreeCam and ns.FreeCam.active then
		ns.Print("|cffff8800camara:|r la camara libre ya tiene las teclas.")
		return false
	end
	if InCombatLockdown() then
		ns.Print("|cffffff00Teclas de camara no disponibles en combate|r - la camara sigue yendo.")
		return
	end

	-- Q/E PIVOTAN, desde 2026-08-18. Iban a TURNLEFT/TURNRIGHT, que es el giro
	-- propio del cliente: continuo y suave, pero sobre el propio eje de la
	-- camara, asi que lo que mirabas se iba de pantalla. Ahora van a botones
	-- nuestros que solo avisan de que la tecla baja y sube; el servidor la
	-- orbita alrededor del punto que mira.
	--
	-- Se pierde la suavidad del movimiento del cliente y se gana el gesto
	-- correcto. Si se nota a pasos, el dial es RTS.Camera.PivotSpeed.
	for key, button in pairs({ Q = "RTSCamPivotLeftButton",
	                           E = "RTSCamPivotRightButton" }) do
		saved[key] = GetBindingAction(key) or ""
		SetBindingClick(key, button)
	end

	-- ESPACIO SUBE Y C BAJA, 2026-08-23. Antes eran +/- y el teclado numerico,
	-- que es donde estan en un editor y no donde las busca la mano en un juego:
	-- espacio ya es "arriba" en todo lo que vuela, y C queda al lado de WASD.
	--
	-- Las dos son teclas OCUPADAS de fabrica -- espacio salta y C abre la ficha
	-- del personaje -- y por eso importa que pasen por `saved`: se apuntan antes
	-- de tocarlas y vuelven al salir del modo, igual que los CVars de la camara.
	-- La ficha sigue estando a un click en el rail.
	for key, button in pairs({
		["SPACE"] = "RTSCamUpButton",
		["C"]     = "RTSCamDownButton",
	}) do
		saved[key] = GetBindingAction(key) or ""
		SetBindingClick(key, button)
	end
end

-- Returns false if it could not run, so the caller knows the keys are still
-- ours and has to try again later.
local function ReleaseTurnKeys()
	if not next(saved) then return true end
	if InCombatLockdown() then return false end

	for key, was in pairs(saved) do
		if was == "" then
			SetBinding(key)          -- one argument clears the binding
		else
			SetBinding(key, was)
		end
	end
	saved = {}
	return true
end

--- El canal: ya no vive aqui -----------------------------------------------
--
-- `ns.SendServer`, el frame de `CHAT_MSG_ADDON` y el reparto de doce verbos
-- estuvieron en este fichero hasta 2026-09-02, por historia: la camara fue lo
-- primero que hablo con mod-rts. Estan en `Link.lua`, y la camara es hoy un
-- cliente mas del canal -- registra `CAM` y `CAMPOS` como cualquier otro.
--
-- `Send` se queda como atajo local porque este fichero manda quince mensajes.

local function Send(body)
	ns.Link:Send(body)
end

-- The two hidden buttons Q and E are bound to. Created once, never shown; a
-- keybinding on a button fires its OnClick.
--
-- PLAIN buttons, not SecureActionButtonTemplate. The secure template was the
-- first attempt and Q/E did nothing at all: a secure button with no `type`
-- attribute has nothing to do when clicked, and the template's own click
-- handling gets in the way of a plain OnClick script. Nothing here needs to be
-- secure -- CameraZoomIn and CameraZoomOut are ordinary unprotected functions,
-- which is the whole reason this approach works.
--
-- Buttons must exist BEFORE SetBindingClick names them, so this is called from
-- Create() at login rather than lazily when the camera turns on.
local function MakeZoomButtons()
	for name, fn in pairs({ RTSCamDownButton       = RTSCommand_CameraDown,
	                        RTSCamUpButton         = RTSCommand_CameraUp,
	                        RTSCamPivotLeftButton  = RTSCommand_CameraPivotLeft,
	                        RTSCamPivotRightButton = RTSCommand_CameraPivotRight }) do
		if not _G[name] then
			local b = CreateFrame("Button", name, UIParent)
			b:Hide()
			-- BOTH edges. Registering only AnyDown gives one event per press
			-- and no way to know the key was let go, which is exactly what a
			-- held-to-move control needs. With both, OnClick's third argument
			-- is the down/up flag.
			b:RegisterForClicks("AnyDown", "AnyUp")
			b:SetScript("OnClick", fn)
		end
	end
end

-- Where the camera creature should stand relative to the character: a distance
-- BEHIND them and a height ABOVE. Sent before every enable, because the server
-- keeps this only in memory -- the addon is where per-character settings already
-- persist, so it is the addon's job to remind the server on each session.
local function SendOffset()
	-- Always sent, even with nothing saved: the defaults above are the point,
	-- and leaving the server to fall back to its own config would mean the
	-- framing depended on which of two files had been edited last.
	local o = (RTSCommandDB and RTSCommandDB.camOffset) or C.DEFAULTS
	Send(("CAM OFFSET %.2f %.2f"):format(o.back or 0, o.up or 12))
end

function C:Toggle()  SendOffset() Send("CAM TOGGLE") end
function C:On()      SendOffset() Send("CAM ON")     end
function C:Off()     Send("CAM OFF")    end
function C:Status()  Send("CAM STATUS") end
function C:Recenter() SendOffset() Send("CAM HERE") end

-- NO HAY ALTURA SOBRE EL SUELO, y esta borrada en vez de apartada. Mantener una
-- separacion constante sobre el terreno mientras panoramizas se construyo por
-- los dos caminos posibles y los dos se vieron en juego el 2026-08-23; ninguno
-- falla por como estaba ajustado, fallan por lo que son:
--
--   corrigiendolo el SERVIDOR (medir el terreno y teleportar) baja a escalones,
--   y cada teleport cancela el avance que esta aplicando el cliente, asi que el
--   movimiento se para en seco en cada uno. Parece un ascensor, no una camara.
--
--   corrigiendolo el CLIENTE (hover) necesita la GRAVEDAD ENCENDIDA, porque el
--   hover es un modificador del seguimiento del suelo del cliente y sin
--   gravedad no hay seguimiento que modificar. Y la gravedad apagada es
--   justamente lo que hace que la camara se quede donde se la pone: al armar el
--   hover la camara CAE al suelo y el hover la levanta despues. Esa caida es el
--   mecanismo, no un fallo del mecanismo -- y es lo que se vio en pantalla.
--
-- La camara vuelve a ser la de siempre: cuelga a la altura que se le da, y lo
-- unico que la mueve en vertical son las teclas de subir y bajar.

-- Flight decides whether forward follows the view or runs flat. Off is the RTS
-- behaviour; on is the old flying-mount behaviour, kept so the two can be
-- compared in game rather than argued about.
function C:SetFly(on)
	Send(("CAM FLY %d"):format(on and 1 or 0))
end

function C:SetSpeed(n)
	if not tonumber(n) then
		ns.Print("Usage: |cffffff00/rts cam speed <0.5-50>|r")
		return
	end
	Send(("CAM SPEED %s"):format(tostring(n)))
end

--- Mouselook while flying --------------------------------------------------
--
-- While the camera is actually moving, the mouse should steer it, so a hand
-- already on WASD can fine-tune the framing without reaching for right-click.
-- The moment it stops, the mouse goes back to being a cursor for selecting and
-- ordering.
--
-- This keys off the camera ACTUALLY MOVING rather than off the movement keys,
-- for two reasons: the keys cannot be watched without rebinding WASD or
-- swallowing keyboard input, and "is it moving" is the real question anyway --
-- it stays true while gliding to a stop. Position comes from rts_core, which
-- publishes the live camera every frame; a possessed camera only translates
-- when a movement key is held, since turning rotates it in place.
--
-- The release is deliberately late. Letting go of W to press A is a gap of a
-- few tens of milliseconds, and dropping mouselook in that gap would yank the
-- cursor back on screen and then hide it again -- so a short grace rides over
-- direction changes.

local RELEASE_GRACE = 0.25   -- seconds of stillness before the cursor returns
local MOVE_EPSILON  = 0.02   -- yards per sample; below this it is not moving

-- OFF by default as of 2026-08-15. Two reasons, and the second is the real one:
--
--   * it did not work in RTS mode, and probably cannot -- the mouse catcher
--     frame owns the cursor there, so MouselookStart has nothing to take;
--   * right-drag to orbit is the explicit control, and an automatic mouselook
--     fighting it for the same mouse would be worse than not having either.
--
-- Kept because outside RTS mode, flying the camera with no frame in the way,
-- it is still a reasonable thing to want. `/rts cam mouse` turns it on.
C.mouselook = { enabled = false }

local look = { lastX = nil, lastY = nil, lastZ = nil, stillFor = 0, ours = false }

local function StopOurMouselook()
	if look.ours then
		if IsMouselooking() then MouselookStop() end
		look.ours = false
	end
end

-- Returns true while the camera has moved recently.
local function CameraMoving(elapsed)
	if RTS_HasCam ~= 1 then return false end

	local x, y, z = RTS_CamX, RTS_CamY, RTS_CamZ
	if not look.lastX then
		look.lastX, look.lastY, look.lastZ = x, y, z
		return false
	end

	local dx, dy, dz = x - look.lastX, y - look.lastY, z - look.lastZ
	look.lastX, look.lastY, look.lastZ = x, y, z

	if (dx * dx + dy * dy + dz * dz) > (MOVE_EPSILON * MOVE_EPSILON) then
		look.stillFor = 0
		return true
	end

	look.stillFor = look.stillFor + elapsed
	return look.stillFor < RELEASE_GRACE
end

function C:UpdateMouselook(elapsed)
	if not self.active or not self.mouselook.enabled then
		StopOurMouselook()
		return
	end

	if CameraMoving(elapsed) then
		-- Never start it if the player is already holding a mouse button to
		-- look around: that is their mouselook, and stopping it later would be
		-- taking something we did not take.
		if not IsMouselooking() then
			MouselookStart()
			look.ours = true
		end
	else
		StopOurMouselook()
	end
end

function C:ToggleMouselook()
	self.mouselook.enabled = not self.mouselook.enabled
	if not self.mouselook.enabled then StopOurMouselook() end
	RTSCommandDB.camMouselook = self.mouselook.enabled
	ns.Print("mouse steering while flying " ..
		(self.mouselook.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- The server telling us what actually happened.
function C:OnState(on)
	if on == self.active then return end
	self.active = on

	if on then
		GrabTurnKeys()
		look.lastX, look.stillFor = nil, 0
		self:Frame()
		ns.Print("|cff00ff00Camara RTS ON|r - WASD desplaza plano, Q/E rotan, +/- suben y bajan.")
		ns.Print("Right-drag sets the angle and it |cff00ff00stays|r - the client's auto-adjust is off.")
		ns.Print("Frame it how you like, then |cffffff00/rts cam save|r to make that the RTS view.")
	else
		StopOurMouselook()
		ReleaseTurnKeys()
		ReleaseCamera()
		-- A height key still held as the camera goes away would leave the
		-- server driving a camera that no longer exists, and the next enable
		-- would start already climbing.
		held.up, held.down = false, false
		Vertical(0)
		-- Lo mismo para el pivote, y por el mismo motivo: soltar la camara con
		-- Q o E pulsada dejaba al servidor orbitando una camara que ya no esta,
		-- y el siguiente encendido empezaba girando solo.
		pivoting.left, pivoting.right = false, false
		Pivot(0)
		ns.Print("|cffff0000RTS camera OFF|r - back on your character.")
	end
end

--- RTS framing -------------------------------------------------------------
-- The look a WC3 or StarCraft camera has: pulled well back and tilted steeply
-- down, so the ground reads as a map rather than as scenery.
--
-- Both halves are approximations of things WoW does not expose directly. There
-- is no "set camera pitch" call in 3.3.5a, so the tilt is done by running the
-- client's own view movement for a measured time and stopping it -- which means
-- the ANGLE is a function of how long it ran, and has to be tuned by eye rather
-- than set. Hence `tilt` being a duration in seconds.
--
-- MoveViewUp, NOT MoveViewDown. The names describe where the CAMERA goes, not
-- where you end up looking: moving the camera up puts it above the unit looking
-- down, which is the RTS view. Using MoveViewDown drove the camera under the
-- unit and pointed it at the sky -- which is exactly what it did in game.
--
-- FOV is not touched yet. The camera struct's fov lives at +0x40 and rts_core
-- already reads it, but the addon has no way to send the DLL a NUMBER -- the
-- CVar channel carries a packed bitfield with no room for one. That needs a
-- second borrowed CVar and is a separate job.

--- THE DEFAULT RTS FRAMING ---------------------------------------------------
--
-- This is the block to edit when a good framing has been found. `/rts cam save`
-- exists to FIND those numbers, not to be run every session -- it prints one
-- pasteable line, and those values belong here so every character and every
-- fresh install starts correctly framed with nothing to set up.
--
-- A saved framing (RTSCommandDB.camOffset / camPreset) overrides these; that is
-- the tool still being available for future changes. /rts cam clear drops back
-- to exactly what is written here.
--
--   back  yards BEHIND the character the camera stands. This is the one that
--         pulls the party down into frame instead of leaving them underfoot.
--   up    yards ABOVE the character it stands.
--   tilt  seconds of downward view movement applied on entry, used only when
--         no view preset has been saved.
--   zoom  yards to pull the camera back from the point it orbits.
-- Measured in game 2026-08-16 with /rts cam save and set here, which is the
-- whole point of that command: find the framing once, bake it in, never set it
-- up again on a new character.
C.DEFAULTS = {
	back = 14.9,
	up   = 12.0,
	tilt = 0.85,
	zoom = 50,

	-- CAMPO DE VISION DIAGONAL EN GRADOS, y por defecto **0 = no tocarlo**.
	--
	-- Estuvo en 60 desde la etapa 5g, con la idea de que estrechar el angulo
	-- aplana la perspectiva y hace que la escena se lea como un mapa. Nunca se
	-- aplico -- el canal estaba muerto (ver `FOV_CVAR`) -- asi que **ese 60 no
	-- se ha visto nunca en juego**: la camara que el jugador conoce es la de los
	-- 90 grados del cliente.
	--
	-- El dia que el canal empezo a funcionar (2026-09-06) la camara cambio sola
	-- de aspecto sin que nadie tocara nada, y eso no es un valor por defecto: es
	-- un cambio de comportamiento colado por la puerta de atras. Vuelve a 0, que
	-- es la camara de siempre, y el angulo se pide cuando se quiere con
	-- `/rts cam fov <grados>`.
	--
	-- Necesita rts_core inyectado: el struct de la camara lo escribe el DLL.
	fov = 0,

	-- La sombra bajo los personajes mientras dura el modo RTS. -1 = no tocarla.
	-- 2 enciende la sombra proyectada, que es lo que hace que un personaje se
	-- despegue del suelo a vista de pajaro; este Config.wtf la trae a 0.
	shadow = 2,
}

-- EL ENCUADRE VIVO. Lo que `C:Frame()` aplica al entrar en modo RTS.
--
-- `fov` FALTABA AQUI, y por eso la camara isometrica de la etapa 5g no se
-- aplico NUNCA -- ni antes ni despues del arreglo de la 0.50.0.
--
-- La 0.50.0 arreglo que `Camera:Create()` machacaba esta tabla entera con el
-- frame de eventos, y el informe de entonces dijo que el FOV "deberia aplicarse
-- ahora". No era verdad, y `PRUEBAS-20` E1 lo caza: aquel arreglo era necesario
-- pero no suficiente, porque **la clave nunca estuvo en esta tabla**. Con
-- `cfg.fov` nil, `Frame()` escribe el CVar prestado a 0 -- que significa
-- literalmente "no toques el FOV" -- asi que el DLL lo respetaba al pie de la
-- letra.
--
-- Lo que lo hizo invisible durante cuatro etapas es lo de siempre: `C:Report()`
-- lee `tonumber(f.fov) or tonumber(d.fov)`, o sea que **caia a DEFAULTS e
-- imprimia 60 mientras se escribia 0**. Un lector que miente en la direccion
-- tranquilizadora, tercera vez en este mismo fichero.
--
-- Por eso `Frame()` ahora vuelve a LEER los CVars despues de escribirlos (ver
-- `C:Report`): un valor que el cliente recorta o rechaza se ve, en vez de
-- suponerse.
C.frame = {
	tilt = C.DEFAULTS.tilt,
	zoom = C.DEFAULTS.zoom,
	fov = C.DEFAULTS.fov,
	shadow = C.DEFAULTS.shadow,
	maxFactor = "4",     -- cameraDistanceMaxFactor: the multiplier cap
	distanceMax = "50",  -- cameraDistanceMax: the absolute cap, in yards
}


-- The client has had exactly this feature since 2004: five camera view slots,
-- SaveView(n) storing the current pitch and distance and SetView(n) gliding
-- back to it. That is strictly better than the timed MoveView hack -- it stores
-- a real angle instead of "however far it turned in 0.85 seconds", it restores
-- the distance too, and the client animates the transition itself.
--
-- Slot 5 is used because slots 1 and 2 are the ones WoW's own default bindings
-- reach. Anything you had saved in 5 will be overwritten by /rts cam save.
local VIEW_SLOT = 5

-- Point the camera where you want it -- angle, distance, everything -- then
-- save. That framing is what entering RTS mode restores from then on.
-- Saving has two halves, because the framing has two halves.
--
-- SaveView stores the camera's ANGLE and DISTANCE -- how it is oriented around
-- whatever it is orbiting. It knows nothing about where that thing is standing,
-- which is why a saved framing came back at the right tilt with the party in
-- the wrong part of the screen. The other half is the camera creature's own
-- placement, and only the server knows that, so it is asked for it here and the
-- answer arrives as CAMPOS.
function C:SavePreset()
	SaveView(VIEW_SLOT)
	RTSCommandDB.camPreset = true
	Send("CAM POS")   -- answered by OnOffset below
	ns.Print("|cff00ff00Angle and zoom saved.|r Asking the server where the camera is standing...")
end

-- How steeply the camera is looking down, in degrees, from the forward vector
-- rts_core publishes. Nil without the DLL.
--
-- Es un LECTOR, no un mando: se imprime en `/rts cam` para que un encuadre se
-- pueda repetir en codigo y no solo en una ranura de vista guardada.
--
-- No hay ninguna llamada que fije un angulo en 3.3.5a. SI se puede cerrar el
-- lazo -- mover la vista con el movimiento continuo del cliente y parar cuando
-- este numero cruza el que se quiere -- y se escribio el 2026-09-06 como
-- `/rts cam pitch`. **Se borro el mismo dia, a peticion**: la camara vuelve a
-- ser la de siempre y lo unico que se pidio conservar del experimento fue el
-- mando del FOV. Queda escrito porque la tecnica sirve, no el codigo.
function C:PitchDegrees()
	if RTS_HasCam ~= 1 or not RTS_CamFwdZ then return nil end
	local fz = math.max(-1, math.min(1, RTS_CamFwdZ))
	return -math.deg(math.asin(fz))
end

-- The server's answer: how far behind the character the camera is, and how far
-- above. Stored here, sent back on every enable, and printed as one line that
-- can be copied out and pasted into C.DEFAULTS above.
function C:OnOffset(back, up)
	RTSCommandDB.camOffset = { back = back, up = up }
	ns.Print(("|cff00ff00Framing saved|r - %.1f yards back, %.1f up."):format(back, up))
	self:Report()
end

-- Everything about the current framing, as one pasteable line.
--
-- Built defensively and value by value. The first version chained five lookups
-- into one format call and printed nothing at all in game -- and because WoW
-- hides Lua errors unless scriptErrors is on, it failed silently with no clue
-- which lookup was nil. A readout that can fail quietly is worse than none.
function C:Report()
	local saved = RTSCommandDB and RTSCommandDB.camOffset
	local d = self.DEFAULTS or {}
	local f = self.frame or {}

	local back  = tonumber(saved and saved.back) or tonumber(d.back) or 0
	local up    = tonumber(saved and saved.up)   or tonumber(d.up)   or 12
	local tilt  = tonumber(f.tilt) or tonumber(d.tilt) or 0
	local zoom  = tonumber(f.zoom) or tonumber(d.zoom) or 0
	local pitch = self:PitchDegrees()

	-- EL FORMATO LLEVABA CINCO HUECOS Y SEIS ARGUMENTOS, asi que imprimia el FOV
	-- bajo la etiqueta `pitch` y tiraba el pitch de verdad. Cazado al perseguir
	-- por que el FOV no se aplicaba (`PRUEBAS-20` E1) -- o sea que el unico
	-- lector que habia de este valor tambien mentia, y por eso nadie vio en
	-- cuatro etapas que se estaba escribiendo 0.
	--
	-- Es la tercera vez en este fichero: el comentario de arriba dice que un
	-- lector que falla en silencio es peor que ninguno, y lo decia sobre si
	-- mismo sin saberlo. `format` en Lua NO se queja de argumentos de mas.
	local fov = tonumber(f.fov) or 0
	ns.Print(("copy this line: |cff00ff00back=%.1f up=%.1f tilt=%.2f zoom=%.0f fov=%.0f pitch=%s|r")
		:format(back, up, tilt, zoom, fov,
		        pitch and ("%.1f"):format(pitch) or "no-dll"))

	-- LO QUE EL CLIENTE SE QUEDO DE VERDAD, al lado de lo que le pedimos.
	--
	-- `SetCVar` sobre un CVar recortado o inexistente no da error en 3.3.5a, asi
	-- que sin esta linea "el zoom no llega mas lejos" y "no hay sombras" son
	-- sintomas sin numero detras. Si lo pedido y lo aplicado no coinciden, el
	-- cliente lo recorto y se ve aqui en vez de en una ronda de pruebas.
	local a = C.applied
	if a then
		ns.Print(("cvars aplicados: |cff00ff00fov=%s|r (pedido %d) zoomFactor=%s zoomMax=%s " ..
		          "sombra=%s suavizado=%s")
			:format(tostring(a.fov), math.floor(fov * 10),
			        tostring(a.maxFactor), tostring(a.distanceMax),
			        tostring(a.shadow), tostring(a.smooth)))
		-- LA VUELTA COMPLETA, que es lo unico que prueba que el canal esta vivo:
		-- lo que se pide, lo que se quedo en el CVar, y el angulo con el que el
		-- DLL dibuja DESPUES de escribirlo. Si los tres no cuadran se sabe en
		-- cual de los tres saltos se perdio.
		--
		-- No tenerlo costo TRES rondas: el CVar prestado no existia, `SetCVar`
		-- sobre un nombre inexistente no da error, y sin leer la vuelta no habia
		-- forma de distinguir "no se aplica" de "no llega".
		if GetCVar(FOV_CVAR) == nil then
			ns.Print("|cffff0000  el CVar del FOV no existe|r - " ..
			         "sin el, el angulo no viaja. |cffffff00/reload|r.")
		elseif RTS_Ready ~= 1 then
			ns.Print("|cffff8800  rts_core no esta inyectado|r - el FOV lo escribe el DLL, " ..
			         "asi que ese CVar no lo lee nadie.")
		elseif RTS_CamFov and RTS_CamFov > 0 then
			local diag = math.deg(RTS_CamFov)
			local w, h = GetScreenWidth(), GetScreenHeight()
			local aspect = (h and h > 0) and (w / h) or (16 / 9)
			local horiz = 2 * math.deg(math.atan(
				math.tan(math.rad(diag * 0.5)) / math.sqrt(1 + 1 / (aspect * aspect))))
			ns.Print(("  el DLL dibuja con |cff00ff00%.1f|r diagonales = " ..
			          "|cff00ff00%.1f|r horizontales%s"):format(diag, horiz,
				(fov > 0 and math.abs(diag - fov) > 1.5)
					and ("  |cffff8800(se pidieron %.0f)|r"):format(fov) or ""))
		end
	else
		ns.Print("|cff888888cvars: todavia sin aplicar (entra en modo RTS).|r")
	end

	ns.Print("Send that over and it becomes the built-in default - no setup per character.")
end

function C:ClearPreset()
	RTSCommandDB.camPreset = nil
	RTSCommandDB.camOffset = nil
	self.frame.tilt = self.DEFAULTS.tilt
	self.frame.zoom = self.DEFAULTS.zoom
	RTSCommandDB.camFrame = nil
	ns.Print(("RTS camera framing cleared - back to the built-in default " ..
		"(%.1f back, %.1f up)."):format(self.DEFAULTS.back, self.DEFAULTS.up))
end

function C:Frame()
	local cfg = self.frame

	-- Raise the zoom ceiling only while we are in RTS mode; ReleaseCamera puts
	-- both caps back, so normal play keeps whatever limits it had.
	--
	-- BOTH caps matter. cameraDistanceMaxFactor is a multiplier and
	-- cameraDistanceMax is an absolute ceiling in yards; raising only the
	-- multiplier still leaves the scroll wheel stopping short. Together they
	-- give the wheel a much wider run, right in to the group and well back out.
	HoldCamera({
		cameraSmoothStyle       = "0",
		cameraDistanceMaxFactor = cfg.maxFactor,
		cameraDistanceMax       = cfg.distanceMax,
		-- Tenths of a degree, so the DLL reads a whole number. 0 = leave it.
		[FOV_CVAR]              = tostring(math.floor((cfg.fov or 0) * 10)),
	})

	-- La sombra va aparte del bloque de arriba porque puede estar apagada: -1
	-- significa "no la toques", y entonces no se escribe nada. Con un valor, la
	-- captura ya la hizo `HoldCamera` en su primera llamada, asi que se restaura
	-- sola al salir -- misma regla dura que el resto.
	local sh = tonumber(cfg.shadow)
	if sh and sh >= 0 then SetCVar("shadowLevel", tostring(math.floor(sh))) end

	-- LO QUE EL CLIENTE SE QUEDO, no lo que le pedimos.
	--
	-- Un CVar puede recortarse (cameraDistanceMaxFactor tiene tope propio) o no
	-- existir, y en 3.3.5a `SetCVar` sobre algo que no existe **no da error**.
	-- Sin leerlo de vuelta, "el zoom no llega mas lejos" y "las sombras no salen"
	-- son dos sintomas sin ningun numero detras -- que es exactamente como
	-- llegaron de `PRUEBAS-20`. Se guarda y `/rts cam` lo imprime.
	C.applied = {
		fov         = GetCVar(FOV_CVAR),
		smooth      = GetCVar("cameraSmoothStyle"),
		maxFactor   = GetCVar("cameraDistanceMaxFactor"),
		distanceMax = GetCVar("cameraDistanceMax"),
		shadow      = GetCVar("shadowLevel"),
	}

	if RTSCommandDB.camPreset then
		SetView(VIEW_SLOT)
		return
	end

	-- No saved framing yet: approximate one, and say so, because this path is
	-- the guess and the saved one is not.
	CameraZoomOut(cfg.zoom)
	self:Tilt(cfg.tilt)
	ns.Print("No saved framing - using defaults. Point the camera how you like it," ..
		" then |cffffff00/rts cam save|r.")
end

-- Tilt by running the client's own view movement for `seconds`. Positive tilts
-- the camera UP and over, so you look down; negative goes the other way.
--
-- Stopped on a timer rather than after a fixed number of frames: the view moves
-- at a rate per second, so a frame count would give a different angle on a
-- different machine, and on the same machine at a different framerate.
local tilter

function C:Tilt(seconds)
	seconds = tonumber(seconds) or 0
	if seconds == 0 then return end

	local up = seconds > 0
	local want = math.abs(seconds)

	if up then MoveViewUpStart(1) else MoveViewDownStart(1) end

	tilter = tilter or CreateFrame("Frame")
	local elapsed = 0
	tilter:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + e
		if elapsed >= want then
			-- Stop BOTH: a second tilt starting while the first is still
			-- running would otherwise leave the old one turning forever.
			MoveViewUpStop()
			MoveViewDownStop()
			self:SetScript("OnUpdate", nil)
		end
	end)
end

-- Applies immediately as well as saving. Tuning an angle you cannot see until
-- the next relog is not tuning, it is guessing -- the flare settings made that
-- point already.
function C:SetFrame(key, value)
	local cfg = self.frame
	local n = tonumber(value)

	if key == "tilt" and n then
		-- Negative is allowed and useful: it is how you come back up after
		-- overshooting, without having to leave and re-enter the camera.
		local amount = math.max(-4, math.min(4, n))
		HoldCamera({ cameraSmoothStyle = "0" })
		self:Tilt(amount)
		-- Only a positive tilt is remembered as the ENTRY angle; a negative one
		-- is a correction you are making now, not a framing you want next time.
		if amount > 0 then cfg.tilt = amount end
		ns.Print(("tilt %+.2f applied%s"):format(amount,
			amount > 0 and (", saved as the entry angle") or ""))

	elseif key == "fov" and n then
		-- EL SUELO BAJA DE 20 A 5. Pedido: *"lo quiero a 15 para probar"*, y el
		-- tope de 20 lo habria convertido en 20 **sin decir nada** -- un numero
		-- que se acepta y se cambia por otro es peor que uno que se rechaza.
		-- Por debajo de 20 grados el mundo se aplana casi del todo, que es
		-- justamente lo que se quiere ver.
		cfg.fov = (n <= 0) and 0 or math.max(5, math.min(140, n))
		HoldCamera({ [FOV_CVAR] = tostring(math.floor(cfg.fov * 10)) })
		-- Y SI ESTAMOS EN LA CAMARA LIBRE, EL FOV VA POR OTRO CAMINO.
		--
		-- En modo comentarista el FOV lo tiene el estado de esa camara
		-- (`0x00ACE4E4`) y lo repone el cliente, asi que el CVar que lee el DLL
		-- pierde la pelea -- que es exactamente lo que se vio: `/rts cam fov`
		-- no hacia nada con la camara libre puesta. `SpecApply` lo manda por
		-- `CommentatorSetCamera`, que es quien es dueño de ese campo ahora.
		if C.place and C.place.x then
			C.place.fov = nil            -- que lo recalcule desde `cfg.fov`
			C:SpecApply()
		end
		if cfg.fov == 0 then
			ns.Print("fov override |cffff0000off|r - the client's own 90 degrees.")
		else
			ns.Print(("fov = %.0f degrees (WoW's own is 90; lower is flatter)"):format(cfg.fov))
		end
		if RTS_Ready ~= 1 then
			ns.Print("|cffff0000rts_core is not injected|r - fov is written by the DLL.")
		end

	elseif key == "shadow" and n then
		-- 0..5 es la escala del cliente; -1 (o cualquier negativo) es "no la
		-- toques", y entonces hay que DEVOLVER la que habia -- apagar la opcion
		-- y dejar puesto lo que puso es el fallo que la etapa del `camHold` ya
		-- pago una vez: una funcion escondida con su interruptor puesto no esta
		-- escondida.
		cfg.shadow = (n < 0) and -1 or math.min(5, math.floor(n))
		if cfg.shadow < 0 then
			local was = cvarWas and cvarWas.shadowLevel
			if was then SetCVar("shadowLevel", was) end
			ns.Print("sombras: |cffff0000sin tocar|r (las del cliente)")
		else
			HoldCamera({})     -- captura la original si aun no lo estaba
			SetCVar("shadowLevel", tostring(cfg.shadow))
			ns.Print(("sombras: |cffffff00%d|r (0 apagadas, 5 el maximo del cliente). " ..
				"No hay mando de tamano ni de dureza en 3.3.5a."):format(cfg.shadow))
		end

	elseif key == "zoom" and n then
		cfg.zoom = math.max(1, math.min(50, n))
		HoldCamera({ cameraDistanceMaxFactor = cfg.maxFactor })
		CameraZoomOut(cfg.zoom)
		ns.Print(("zoom = %.0f applied"):format(cfg.zoom))

	else
		ns.Print(("camera framing: tilt=%.2f zoom=%.0f sombra=%s"):format(
			cfg.tilt, cfg.zoom, (cfg.shadow or -1) < 0 and "sin tocar" or tostring(cfg.shadow)))
		ns.Print("|cffffff00/rts cam tilt <sec>|r - negative tilts back up")
		ns.Print("|cffffff00/rts cam zoom <yards>|r / |cffffff00fov <deg>|r - " ..
		         "|cffffff00frame|r re-applies all")
		ns.Print("|cff888888El fov es DIAGONAL, como el del cliente: los 90 de " ..
		         "siempre son 90 diagonales. 0 = no tocarlo.|r")
		ns.Print("|cffffff00/rts cam shadow <0-5>|r - sombra bajo los personajes, -1 no tocarla")
		return
	end

	self:SaveFrame()
end

-- El encuadre a disco, en un solo sitio. Sale de `SetFrame`, donde estaba
-- escrito a mano al final: en cuanto hubo un segundo llamante, la copia habria
-- sido la que se olvida de una clave el dia que se anada una. El segundo
-- llamante ya no esta, y esto se queda igual -- un solo sitio no cuesta nada.
function C:SaveFrame()
	local f = self.frame
	RTSCommandDB.camFrame = { tilt = f.tilt, zoom = f.zoom, fov = f.fov,
	                          shadow = f.shadow }
end

--- EL SONDEO DE LA CAMARA LIBRE DEL CLIENTE ---------------------------------
--
-- Este cliente trae una camara libre COMPLETA con API de Lua -- la de
-- comentarista de arenas -- y esta seccion existe para averiguar en juego si se
-- puede usar en mundo abierto. El porque entero, con las direcciones
-- desensambladas de este `Wow.exe` y las lineas del nucleo, esta en
-- `mod-rts/src/RtsCamera.h`, en `Spectate`.
--
-- POR QUE IMPORTA: la camara de hoy es una criatura del servidor que posees, o
-- sea que el CLIENTE es dueño de su posicion y el servidor solo la mueve con
-- `NearTeleportTo` -- que cancela el movimiento que el cliente esta aplicando.
-- De esa unica causa salen "no se puede avanzar y subir a la vez" y la altura
-- sobre el terreno que se construyo por los dos caminos y se borro el
-- 2026-08-23 (ver el aviso de arriba, donde estaba el codigo). Si el cliente
-- dibuja desde su camara de comentarista, eso se cae entero.
--
-- ESTO NO CONSTRUYE NADA. Es un sondeo, y esta escrito como un sondeo: cada
-- paso dice lo que significa que falle, porque un resultado malo tiene que
-- estrechar el problema y no solo reportarlo.
--
-- === LOS DOS TESTIGOS, Y POR QUE NO SIRVE EL OBVIO ========================
--
-- `CommentatorGetCamera()` NO vale para saber si la camara se movio: lee la
-- posicion de los globales del estado de comentarista (`0x00ACE4B4/B8/BC`), o
-- sea **lo que le pediste**, no donde esta la camara de verdad. Un lector que
-- devuelve tu propia peticion es el modo de fallo que este proyecto lleva
-- persiguiendo desde el `C:Report()` que imprimia el FOV que no se aplicaba.
--
-- El testigo honesto es `RTS_CamX/Y/Z`, que el DLL saca del campo de posicion
-- de la camara ACTIVA (`cam+0x08`) sin pasar por Lua. Sin DLL inyectado el
-- sondeo lo dice y pide mirar la pantalla, que es la degradacion correcta.
--
-- Para lo que SI vale `CommentatorGetCamera` es para el paso 1: devuelve SEIS
-- numeros si la puerta esta abierta y NADA si esta cerrada (`0x0056A2A0`, la
-- rama de gate cerrado sale sin apilar nada). Es una lectura pura, cero riesgo.
--
-- Y de paso dejo apuntado lo que salio de desensamblarla, porque el DLL no lo
-- tiene y le hace falta si algun dia se va por el camino B: lee los angulos de
-- **`cam+0x11C` (yaw) y `cam+0x120` (pitch)**, en radianes, sobre la camara
-- activa. `Offsets.h` dice hoy que no conoce ningun campo de pitch ni yaw.

local SPEC_FNS = {
	"CommentatorSetCamera", "CommentatorGetCamera",
	"CommentatorSetCameraCollision", "CommentatorSetMoveSpeed",
	"CommentatorFollowPlayer", "CommentatorSetTargetHeightOffset",
	"CommentatorZoomIn", "CommentatorZoomOut",
}

-- Todo lo de esta seccion pasa por aqui. Ninguna de estas funciones se ha
-- llamado nunca en este proyecto, asi que se llaman con `pcall` y se comprueba
-- que existan: una funcion que no esta da un error de Lua que abortaria el
-- sondeo entero en su primer paso, y entonces no se sabria nada de los demas.
local function Try(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then return false, "no existe" end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if not ok then return false, tostring(a) end
	return true, a, b, c, d, e, f
end

-- ¿Esta abierta la puerta? Seis numeros = si.
local function GateOpen()
	local ok, x = Try("CommentatorGetCamera")
	return ok and type(x) == "number", x
end

-- === EL FOV DE `SetCamera` NO ADMITE 0, Y ESO COSTO UNA PASADA ============
--
-- Visto en juego el 2026-09-07: la camara se colocaba bien y la pantalla era
-- una mancha morada -- *"como si tuviera el FOV mas estrecho posible"*, y era
-- exactamente eso: **un grado**.
--
-- `CommentatorSetCamera` toma el sexto argumento en GRADOS y lo acota entre
-- `[0x009E2B40]` y `[0x00A0FF40]`, que leidos del binario valen 0.01745329 y
-- 2.09439516 radianes -- o sea **1 y 120 grados**. Y el suelo no es un valor
-- cualquiera: `0.01745329` ES `DEG2RAD`, la misma constante con la que
-- convierte. Pasar 0 da `0 <= DEG2RAD`, gana el suelo, y te quedas con 1 grado
-- de campo de vision, que es un teleobjetivo absurdo.
--
-- EL FALLO DE FONDO NO FUE EL NUMERO: fue traerme una convencion de otro canal.
-- En `rtsFov` -- el CVar que lee el DLL -- 0 significa *"no toques el FOV"*, y
-- lo escribi aqui como si fuera una propiedad del FOV y no de ese canal. Dos
-- caminos que llevan al mismo campo (`cam+0x40`) con dos convenciones
-- distintas para el mismo valor.
--
-- Asi que aqui no hay "no lo toques": SIEMPRE se manda un FOV valido. El del
-- encuadre si esta puesto, y 90 -- el propio de WoW -- si no.
local SPEC_FOV_MIN, SPEC_FOV_MAX = 1, 120
local SPEC_FOV_DEFAULT = 90

local function SpecFov()
	local f = tonumber(C.frame and C.frame.fov) or 0
	if f <= 0 then f = SPEC_FOV_DEFAULT end
	if f < SPEC_FOV_MIN then f = SPEC_FOV_MIN end
	if f > SPEC_FOV_MAX then f = SPEC_FOV_MAX end
	return f
end

local function CamWitness()
	if RTS_Ready ~= 1 or RTS_HasCam ~= 1 then return nil end
	return RTS_CamX, RTS_CamY, RTS_CamZ
end

local function Moved(ax, ay, az, bx, by, bz)
	if not ax or not bx then return nil end
	local dx, dy, dz = bx - ax, by - ay, bz - az
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- === LAS DOS MITADES, Y POR QUE NO PUEDEN IR JUNTAS =======================
--
-- Visto en juego el 2026-09-07, primera pasada: los flags y el paquete del modo
-- salian del servidor de golpe, y era una carrera. `SetPlayerFlag` no manda
-- nada -- marca el campo sucio, y la actualizacion sale en el siguiente flush,
-- unos 100 ms despues -- mientras que el paquete sale ya. Asi que el paquete
-- llegaba PRIMERO, el predicado del cliente leia los flags viejos, y la puerta
-- estaba cerrada.
--
-- Y LA RAMA DE PUERTA CERRADA NO ES UN NO-OP, que es lo que lo hizo caro: cae
-- en la misma que `enable == 0` y mete la camara en modo 1 con el estado que
-- hubiera. En pantalla, la camara se fue lejisimo y por debajo del suelo. Un
-- intento fallido que no deja las cosas como estaban es la peor forma de
-- fallar.
--
-- Asi que el retraso no se adivina: `CommentatorGetCamera()` contesta seis
-- numeros en cuanto los flags han llegado y nada mientras no, o sea que **el
-- cliente dice cuando se puede armar**. Se sondea hasta que conteste y solo
-- entonces se pide el modo. Es la leccion de `HasServer()` y del `PORTED` del
-- cambio de personaje: un estado que viaja no es un estado que ya llego.
--- LOS FLAGS DE ESPECTADOR SE MANDAN SIEMPRE.
---
--- Hubo un intento (2026-09-08) de no ponerlos cuando el DLL estuviera
--- inyectado, parcheando las dos puertas del cliente que los exigen, para
--- recuperar el mouseover que `PLAYER_FLAGS_UBER` mata. **Salio mal en juego:
--- desaparecieron todos los modelos, no solo el heroe, y el cliente entraba en
--- camara de espectador en juego normal.** El porque -- `0x006DE980` no es la
--- puerta del modo, es un "¿soy espectador?" con dieciocho llamantes -- esta en
--- `rts-client-mod/src/Camera.h`. Borrado de los dos lados.
function C:Spectate(on, after)
	self.specWait = after
	Send("CAM SPEC " .. (on and "1" or "0"))
end

function C:Arm(on, after)
	self.armWait = after
	Send("CAM SPECARM " .. (on and "1" or "0"))
end

--- QUIEN CONDUCE TU CUERPO -------------------------------------------------
--
-- Es un TRATO, no un ajuste, y las dos mitades se excluyen:
--
--   * `ctrl 1` -- el servidor. Es lo que hace falta para que una orden mueva a
--     TU propio heroe (`orders::MoveSelf`), y a cambio el cliente se queda sin
--     espada al pasar por encima de un bicho y sin click derecho: le llega un
--     `SMSG_CLIENT_CONTROL_UPDATE` con cero y eso pone a cero el global que
--     miran tanto el cursor de ataque como el ataque.
--   * `ctrl 0` -- el cliente, que es lo de fabrica desde mod-rts 0.47.0. Raton
--     normal dentro del modo RTS.
--
-- Las direcciones del cliente que lo demuestran estan en `RtsCamera.cpp`.
function C:Control(on)
	if not ns.Link:ServerAtLeast(47) then
		ns.Print("|cffff0000camara:|r |cffffff00/rts cam ctrl|r necesita mod-rts 0.47.0" ..
		         (" y hay %s. Reinicia el worldserver."):format(
		            tostring(ns.Link.serverVersion or "ninguno")))
		return
	end
	Send("CAM CTRL " .. (on and "1" or "0"))
end

-- === LA COLOCACION SE GUARDA, Y NO ES SOLO ORDEN =========================
--
-- `CommentatorSetCamera` toma los seis valores de golpe, asi que cambiar SOLO
-- el FOV significa volver a mandar posicion y angulos. Sin guardarlos, un
-- `/rts cam fov 60` tendria que inventarselos -- y meteria la camara en otro
-- sitio como efecto secundario de tocar el FOV.
--
-- Es tambien la semilla del controlador de verdad: la capa C del brief (el
-- solver) calcula estos seis numeros y esta funcion es la unica que los aplica.
--
-- SE LLAMA `place` Y NO `spec` POR UN FALLO QUE YA COSTO UNA PASADA. La primera
-- version la llamaba `C.spec`, y `OnSpec` hacia `self.spec = on` -- un booleano
-- encima de la tabla. La respuesta del servidor llega ANTES de colocar la
-- camara, asi que cuando `SpecApply` corria la tabla ya era `true` y reventaba
-- con *"attempt to index local 's' (a boolean value)"*, dejando la camara sin
-- colocar en otro continente.
--
-- Es EXACTAMENTE el fallo que este fichero ya documenta veinte lineas mas
-- abajo, en `Create`: `self.frame = f` guardaba el widget de eventos encima de
-- `C.frame`, que es la tabla de encuadre, y se comio el FOV durante cuatro
-- etapas. Mismo fichero, misma clase de error, y la nota estaba escrita. El
-- estado de encendido es `C.specOn`; los nombres se separan a proposito.
C.place = { x = nil, y = nil, z = nil, yaw = 0, pitch = -45, fov = nil }

-- LA VELOCIDAD DE LA CAMARA LIBRE, y sus unidades NO son yardas/segundo.
--
-- `CommentatorSetMoveSpeed` escribe un campo del objeto de la camara de
-- comentarista (`0x00568300` sobre `0x00ACE4A8`) y lo que signifique el numero
-- no se puede leer del binario. Lo que si se sabe es empirico y basta: **20
-- manda la camara a otro continente en dos segundos**. Asi que se guarda por
-- personaje y se ajusta a ojo, que es lo unico honesto con una unidad
-- desconocida -- igual que los siete encuadres del retrato o las cinco ventanas
-- de recorte de los railes.
local SPEC_SPEED_DEFAULT = 1.0

function C:SpecSpeed(n)
	if n ~= nil then
		n = tonumber(n)
		if not n or n <= 0 or n > 20 then
			ns.Print("|cffff0000sspeed:|r un numero entre 0 y 20. 20 se va de la zona.")
			return RTSCommandDB.camSpecSpeed or SPEC_SPEED_DEFAULT
		end
		RTSCommandDB.camSpecSpeed = n
		Try("CommentatorSetMoveSpeed", n)
		ns.Print(("|cff33ccffsspeed:|r velocidad de la camara libre = %.2f"):format(n))
	end
	return RTSCommandDB.camSpecSpeed or SPEC_SPEED_DEFAULT
end

function C:SpecPlace(x, y, z, yaw, pitch, fov)
	local s = self.place
	if x then s.x, s.y, s.z = x, y, z end
	if yaw then s.yaw = yaw end
	if pitch then s.pitch = pitch end
	if fov then s.fov = fov end
	return self:SpecApply()
end

function C:SpecApply()
	local s = self.place
	if not s.x then return false, "sin sitio todavia" end
	-- El FOV SIEMPRE valido: ver el bloque de `SpecFov`. Un 0 aqui son 1 grado.
	--
	-- Y SI SE ACOTA, SE DICE. `/rts cam fov` admite hasta 140 porque el DLL
	-- llega ahi; esta camara topa en 120, que es del cliente y no se negocia.
	-- Dos topes distintos para el mismo numero es un tope que se olvida -- ya
	-- paso con el suelo del FOV, que estaba a 20 en dos sitios.
	local want = tonumber(s.fov) or SpecFov()
	local fov = math.max(SPEC_FOV_MIN, math.min(SPEC_FOV_MAX, want))
	if math.abs(fov - want) > 0.01 then
		ns.Print(("|cffffd100fov:|r pediste %.0f y la camara libre topa en %d; " ..
		          "aplicado %.0f."):format(want, SPEC_FOV_MAX, fov))
	end
	s.fov = fov
	local ok, err = Try("CommentatorSetCamera", s.x, s.y, s.z, s.yaw, s.pitch, fov)
	return ok, err
end

function C:OnSpec(on)
	self.specOn = on
	local after = self.specWait
	self.specWait = nil
	ns.Print("|cff33ccffspec:|r flags " .. (on and "ON" or "OFF"))
	if after then after() end
end

function C:OnArm(on)
	local after = self.armWait
	self.armWait = nil
	ns.Print("|cff33ccffspec:|r modo " .. (on and "LIBRE (6)" or "normal (1)"))
	if after then after() end
end

-- Espera a que la puerta se abra, sondeando. `tries` a 4 Hz.
--
-- El plazo existe porque un fallo tiene que ACABAR: sin el, una puerta que no
-- se abre nunca deja el sondeo colgado sin decir nada, que es indistinguible de
-- que el comando no hiciera nada.
function C:WaitGate(tries, ok, fail)
	if GateOpen() then ok() return end
	if tries <= 0 then fail() return end
	self:After(0.25, function() C:WaitGate(tries - 1, ok, fail) end)
end

-- El paso 5, suelto: apagar la colision de camara. Es la opcion A del §9 del
-- brief -- la camara deja de empujarse contra techos y paredes -- y es una
-- llamada, asi que no necesita el resto del sondeo para probarse.
-- UN NUMERO, NO UN BOOLEANO, aunque su propio texto de uso diga "bool".
--
-- Visto en juego: pasarle `true` contesta
-- *"Usage: CommentatorSetCameraCollision(bool enable)"*. La funcion valida su
-- argumento con la misma llamada que `SetCamera` usa para los seis suyos
-- (`0x0084DF20`, o sea `lua_isnumber`), asi que un booleano no pasa el filtro.
-- El texto de uso describe la INTENCION; el filtro describe lo que acepta, y
-- cuando discrepan manda el filtro.
-- LO QUE HACE DE VERDAD, LEIDO EN EL BINARIO EL 2026-09-10 -- porque hasta ese
-- dia esto era una llamada suelta que nadie hacia y una suposicion razonable
-- sobre lo que pasaria si alguien la hacia.
--
-- El manejador (`0x0056AB70`) escribe 1 o 0 en `0x00ACE4F0`, que es el campo
-- `+0x48` del objeto de comentarista que vive en `0x00ACE4A8`. Y ese campo se
-- LEE, en el recorrido de camara:
--
--   00568B31  cmp dword ptr [esi + 0x48], 0
--   00568B43  je  0x568b69                  ; 0 -> se salta el rayo entero
--   00568B49  push 0x100171                 ; 1 -> rayo contra terreno+WMO+M2
--   00568B5B  call 0x77f310                 ; CGWorldFrame::Intersect
--
-- O sea que la camara de comentarista SI colisiona, y con las mismas banderas
-- que nuestro rayo de suelo. Apagarlo no la hace "atravesar mejor": le quita el
-- rayo de encima.
--
-- Y ARRANCA ENCENDIDO. El global esta a 0 en el fichero, pero `0x0056BC80` --
-- el init del objeto -- escribe 1 en `+0x48`. Tiene UN solo llamante
-- (`0x0056C150`), y ese esta dentro de la cadena de arranque del cliente
-- (`0x0052B864`, entre otras quince llamadas de inicializacion), asi que corre
-- UNA VEZ al abrir el juego. Por eso basta con apagarlo al entrar: nadie lo
-- vuelve a encender por detras.
--
-- OJO CON EL MOMENTO: el manejador exige los DOS flags de jugador (bit 19 y bit
-- 22) antes de escribir nada, y si no los tienes se va por `je 0x56ac01` y
-- RETORNA SIN ESCRIBIR Y SIN ERROR. Llamarlo antes de armar es una llamada que
-- parece funcionar y no hace nada.
--
-- UN NUMERO, NO UN BOOLEANO, aunque su propio texto de uso diga "bool".
--
-- Visto en juego: pasarle `true` contesta
-- *"Usage: CommentatorSetCameraCollision(bool enable)"*. La funcion valida su
-- argumento con la misma llamada que `SetCamera` usa para los seis suyos
-- (`0x0084DF20`, o sea `lua_isnumber`), asi que un booleano no pasa el filtro.
-- El texto de uso describe la INTENCION; el filtro describe lo que acepta, y
-- cuando discrepan manda el filtro.
--
-- Callada y con una sola boca: la usan `FreeCam` al entrar y salir, y el
-- comando de abajo. Dos caminos para lo mismo es como se acaba arreglando la
-- mitad de un fallo.
function C:SetCollision(on)
	return Try("CommentatorSetCameraCollision", on and 1 or 0)
end

function C:CameraCut(on)
	local ok, err = self:SetCollision(on)
	if not ok then
		ns.Print("|cffff0000cut:|r " .. tostring(err))
		ns.Print("  si dice 'no existe', este cliente no es el que se analizo.")
		return
	end
	ns.Print("|cff33ccffcut:|r colision de camara " ..
		(on and "|cffff0000ON|r (normal)" or "|cff00ff00OFF|r (atraviesa)"))
	if not GateOpen() then
		-- El unico fallo posible aqui es silencioso, asi que se dice ANTES de
		-- que el jugador se vaya a probarlo a una cueva.
		ns.Print("  |cffff8800Sin modo espectador esto no ha escrito nada|r: " ..
			"el manejador exige los dos flags y se calla si faltan.")
	end
end

-- El paso 6: inventario de lo que el binario tiene para esconder geometria.
--
-- SOLO LECTURA Y A PROPOSITO. El §10/§11 del brief pide un corte seccional por
-- shader, que en un cliente cerrado sin fuentes no es alcanzable; lo que SI hay
-- dentro del binario es `CClipVolume`, `M2UseClipPlanes`, `glClipPlane`,
-- `farClipOverride` y varios interruptores de categorias enteras de geometria.
-- Esto averigua cuales de ellos son CVars, que es lo unico que Lua alcanza.
--
-- UN `nil` SIGNIFICA "no es un CVar", NO "no existe". Varios de esos nombres
-- salen de `World.cpp` del cliente, o sea que son comandos de consola -- y la
-- consola de desarrollo esta encendida en este cliente (`showToolsUI "1"` en
-- `Config.wtf`), asi que lo que no salga aqui se prueba alli.
local GEO_CVARS = {
	"farClipOverride", "M2UseClipPlanes", "showCull", "shadowCull",
	"antiportal", "minimapPortalMax", "horizonFarclipScale",
	"horizonNearclipScale", "farclip", "nearclip",
}

function C:Geo()
	ns.Print("|cff33ccffgeo:|r lo que este cliente expone para esconder geometria")
	for _, name in ipairs(GEO_CVARS) do
		local v = GetCVar(name)
		if v == nil then
			ns.Print("  " .. name .. ": |cff9a9a9ano es CVar|r")
		else
			ns.Print("  " .. name .. ": |cff00ff00" .. tostring(v) .. "|r")
		end
	end
	for _, name in ipairs({ "TogglePortals", "SetFarclip", "GetFarclip" }) do
		ns.Print("  " .. name .. "(): |cffffd100" .. type(_G[name]) .. "|r")
	end
	ns.Print("  Lo que salga nil se prueba en la consola (Ctrl+Alt+F o ~).")
	ns.Print("  Es un INVENTARIO, no una funcion: sirve para disenar, no para usar.")
end

-- El sondeo, en orden, parando en el primero que no conteste.
function C:Probe()
	ns.Print("|cff33ccff=== sondeo de la camara libre del cliente ===|r")

	-- Paso 0: ¿estan las funciones?
	local missing = {}
	for _, n in ipairs(SPEC_FNS) do
		if type(_G[n]) ~= "function" then table.insert(missing, n) end
	end
	if #missing > 0 then
		ns.Print("|cffff00001)|r faltan " .. #missing .. " funciones: " ..
			table.concat(missing, ", "))
		ns.Print("   SIGNIFICA: este cliente no es el que se analizo. Para el sondeo.")
		return
	end
	ns.Print("|cff00ff001)|r las " .. #SPEC_FNS .. " funciones existen.")

	-- Paso 1: la puerta.
	if GateOpen() then
		ns.Print("|cff00ff002)|r la puerta ya estaba ABIERTA.")
		self:ProbeStep2()
		return
	end

	ns.Print("|cffffd1002)|r puerta cerrada; pidiendo los flags al servidor...")
	if not ns.Link:HasServer() then
		ns.Print("   |cffff0000sin mod-rts|r: nadie puede poner los flags. Para el sondeo.")
		return
	end

	-- Los flags tardan un tick de mundo en llegar, asi que se ESPERA a que el
	-- cliente lo confirme en vez de suponerlo. Tres segundos a 4 Hz.
	self:Spectate(true, function()
		C:WaitGate(12,
			function()
				ns.Print("|cff00ff002b)|r puerta ABIERTA.")
				C:ProbeStep2()
			end,
			function()
				ns.Print("|cffff00002b)|r la puerta SIGUE cerrada tras 3 s.")
				ns.Print("   SIGNIFICA: los flags no llegaron, o el predicado")
				ns.Print("   quiere algo mas que los dos bits. Mirar PLAYER_FLAGS")
				ns.Print("   en el jugador antes que cualquier otra cosa.")
			end)
	end)
end

-- Paso 3 y 4: ¿dibuja desde ella, y se queda?
function C:ProbeStep2()
	local ax, ay, az = CamWitness()
	if not ax then
		ns.Print("|cffffd1003)|r sin rts_core inyectado: no hay testigo objetivo.")
		ns.Print("   Se coloca la camara igual; MIRA LA PANTALLA y dime si salta.")
	end

	-- `UnitPosition` NO EXISTE en 3.3.5a, asi que no se intenta: Lua no tiene
	-- coordenadas de mundo en este cliente y esa es la razon de que el DLL
	-- exista. La posicion sale de `RTS_PX/PY/PZ`, y si no hay DLL se parte de
	-- donde esta la camara ahora -- peor punto de partida, pero no es nada.
	local px, py, pz
	if RTS_Ready == 1 and RTS_HasPos == 1 then
		px, py, pz = RTS_PX, RTS_PY, RTS_PZ
	elseif ax then
		px, py, pz = ax, ay, az
	else
		ns.Print("|cffff00003)|r sin rts_core no hay coordenadas de mundo en Lua,")
		ns.Print("   asi que no se puede pedir un sitio concreto. Abre con")
		ns.Print("   |cffffff002-Jugar.bat|r para que el DLL entre y repite.")
		return
	end

	-- SE COLOCA ANTES DE ARMAR, Y ESE ORDEN ES EL ARREGLO DE LA PRIMERA PASADA.
	--
	-- El estado de la camara de comentarista (`0x00ACE4B4/B8/BC`) empieza sin
	-- inicializar, asi que entrar en el modo 6 sin haberla colocado primero
	-- dibuja desde donde estuviera esa memoria: lejisimo y por debajo del
	-- suelo, que es literalmente lo que se vio. `SetCamera` no necesita el modo
	-- -- escribe en ese estado y le hace falta solo la puerta, que ya esta
	-- abierta aqui -- asi que colocar primero es gratis y quita el salto.
	--
	-- 30 yardas por encima y mirando 45 grados abajo: si esto se aplica se ve
	-- sin ninguna duda. El FOV lo pone `SpecApply` y NUNCA es 0 -- ver su
	-- bloque: un 0 aqui no significa "dejalo", significa un grado.
	local ok, err = C:SpecPlace(px, py, pz + 30, 0, -45, nil)
	if not ok then
		ns.Print("|cffff00003)|r SetCamera fallo: " .. tostring(err))
		return
	end
	ns.Print("|cff33ccff3)|r camara colocada en " ..
		string.format("%.1f %.1f %.1f", px, py, pz + 30) ..
		", pitch -45, fov " .. tostring(C.place.fov) .. ".")

	-- Y AHORA el modo. Si esto se manda antes, el paso 4 mide un salto que no
	-- es el que se pidio.
	C:Arm(true)

	-- Medio segundo: suficiente para que el frame siguiente la publique, corto
	-- para no confundirlo con una deriva.
	-- === EL TESTIGO ES "ESTA DONDE LA PUSE", NO "SE MOVIO" ================
	--
	-- La primera version medía el DESPLAZAMIENTO, y dio un falso negativo en la
	-- segunda pasada: los flags y el modo siguen puestos entre pruebas, asi que
	-- la camara YA estaba en el sitio pedido y colocarla otra vez movio 0.00
	-- yardas. El sondeo lo leyo como *"el modo 6 no se arma fuera de una
	-- arena. Camino A muerto"* -- una conclusion fuerte y falsa, sobre algo que
	-- habia funcionado en la pasada anterior.
	--
	-- "No se movio" y "no funciona" solo son lo mismo si la camara empezaba en
	-- otro sitio, y eso deja de ser cierto en cuanto el sondeo se repite. La
	-- pregunta de verdad -- *¿esta la camara donde la puse?* -- no depende de
	-- donde estuviera antes, y se contesta comparando la posicion publicada
	-- contra la pedida.
	--
	-- Es la misma leccion que `C:Report()` imprimiendo el FOV que no se
	-- aplicaba, solo que este mintio en la direccion alarmante: manda a
	-- arreglar algo que no esta roto.
	C:After(0.5, function()
		local bx, by, bz = CamWitness()
		local sp = C.place
		local d = Moved(ax, ay, az, bx, by, bz)          -- informativo
		local off = Moved(sp.x, sp.y, sp.z, bx, by, bz)  -- el veredicto

		if off == nil then
			ns.Print("   sin testigo: contesta tu si la vista salto.")
		elseif off < 5 then
			ns.Print(("|cff00ff004)|r LA CAMARA ESTA DONDE SE PIDIO (%.2f yardas " ..
				"de error, se movio %.1f)."):format(off, d or 0))
			ns.Print("   SIGNIFICA: el cliente dibuja desde la camara de")
			ns.Print("   comentarista en mundo abierto. Camino A viable.")
		else
			ns.Print(("|cffff00004)|r la camara esta a %.1f yardas de donde se " ..
				"pidio."):format(off))
			ns.Print("   SIGNIFICA: el modo 6 no se arma aqui, o algo la mueve.")
			ns.Print("   Camino A en duda; el B es el DLL escribiendo cam+0x08.")
			return
		end

		-- ¿Se queda, o la repone el cliente? Es la misma pregunta que el FOV
		-- ya contesto por su lado: ese campo lo reescribe el cliente, asi que
		-- hay que escribirlo cada tick. Si esta se queda, se conduce solo al
		-- cambiar y sale mucho mas barata.
		local cx, cy, cz = bx, by, bz
		C:After(3.0, function()
			local ex, ey, ez = CamWitness()
			local drift = Moved(cx, cy, cz, ex, ey, ez)
			if drift == nil then
				ns.Print("   (sin testigo para la deriva)")
			elseif drift < 2 then
				ns.Print("|cff00ff005)|r SE QUEDA (deriva " ..
					string.format("%.2f", drift) .. "). Se conduce al cambiar.")
			else
				ns.Print("|cffffd1005)|r vuelve sola (deriva " ..
					string.format("%.1f", drift) .. "). Hay que reponerla cada tick,")
				ns.Print("   igual que el FOV. Es viable, solo mas caro.")
			end
			-- PASO 6, YA CONTESTADO EN JUEGO EL 2026-09-07, y por eso aqui ya
			-- no se prueba: se APAGA.
			--
			-- Con `SetMoveSpeed(20)` la camara avanza con W y **el personaje no
			-- se mueve** -- misma posicion publicada antes y despues, al
			-- centimetro. O sea que el cliente desvia WASD a la camara de
			-- comentarista, que es la buena noticia: un solo dueño de la tecla.
			--
			-- Y AUN ASI NO QUEREMOS SU MOVIMIENTO. Sus unidades no son
			-- yardas/segundo en ningun sentido util (20 manda la camara a otro
			-- continente en dos segundos) y, sobre todo, dejarselo al cliente
			-- devuelve la XY a su dueño mientras nosotros llevamos la Z -- que
			-- es la forma exacta del fallo que mato la retencion de altura:
			-- corregir cada tick lo que otro escribe cada tick. Un dueño.
			--
			-- PERO NO SE DEJA EN 0 TODAVIA, Y ESO SE VIO EN JUEGO.
			--
			-- El modo 6 se queda WASD **y no se lo devuelve al personaje**, asi
			-- que con la velocidad a 0 no se mueve nada: ni la camara ni tu.
			-- *"Estamos donde toca pero no me puedo mover."*
			--
			-- 0 es lo correcto el dia que el controlador lea WASD por su cuenta
			-- -- por el mismo camino que ya usan ESPACIO/C, botones propios con
			-- `SetBindingClick` -- porque entonces el dueño somos nosotros. Hasta
			-- ese dia, apagarlo deja una camara que no sirve para nada, y una
			-- pieza a medias que no se puede probar no ayuda a construir la
			-- siguiente. `/rts cam sspeed <n>` lo ajusta.
			Try("CommentatorSetMoveSpeed", C:SpecSpeed())
			ns.Print(("|cff33ccff6)|r WASD mueve la CAMARA (no tu personaje), " ..
				"velocidad %s."):format(tostring(C:SpecSpeed())))
			ns.Print("   |cff888888Provisional: el controlador la conducira el.|r")
			ns.Print("   Luego: |cffffff00/rts cam fov 60|r, |cffffff00/rts cam cut|r, " ..
				"|cffffff00/rts cam geo|r.")
			ns.Print("   Para salir: |cffffff00/rts cam spec 0|r.")
		end)
	end)
end

-- Un temporizador de una vez. `C_Timer` no existe en 3.3.5a.
--
-- UN FRAME POR LLAMADA, y no uno compartido, porque el sondeo se ANIDA: el paso
-- de la deriva se programa desde dentro del callback del paso anterior. Con un
-- frame unico eso funciona por accidente -- solo porque el de fuera ya se ha
-- borrado el script cuando el de dentro lo pone -- y deja de funcionar en
-- cuanto dos esperas se solapen, sin dar ningun error. Son tres frames en toda
-- la sesion de un sondeo; no vale la pena la trampa.
function C:After(delay, fn)
	local f = CreateFrame("Frame")
	local left = delay
	f:SetScript("OnUpdate", function(self2, e)
		left = left - e
		if left <= 0 then
			self2:SetScript("OnUpdate", nil)
			local ok, err = pcall(fn)
			if not ok then ns.Print("|cffff0000sondeo:|r " .. tostring(err)) end
		end
	end)
end

function C:Create()
	MakeZoomButtons()
	EnsureFovCVar()

	local saved = RTSCommandDB and RTSCommandDB.camFrame
	if type(saved) == "table" then
		-- UN `fov` GUARDADO DE ANTES DEL 2026-09-06 NO ES UNA PREFERENCIA.
		--
		-- El canal estuvo muerto desde la etapa 5g, asi que cualquier numero
		-- guardado ahi se escribio a ciegas y **no se llego a ver nunca**.
		-- Aplicarlo ahora que el canal funciona seria estrenar en la cara del
		-- jugador una decision que nadie tomo mirando la pantalla.
		--
		-- Se tira UNA vez, con sello, y se dice. Septima purga de este addon.
		if RTSCommandDB.camFovGen ~= 1 then
			RTSCommandDB.camFovGen = 1
			if tonumber(saved.fov) and tonumber(saved.fov) ~= 0 then
				ns.Print(("|cff888888camara: descartado fov=%s, guardado cuando ese " ..
				          "canal no funcionaba. /rts cam fov <grados> lo pone.|r")
					:format(tostring(saved.fov)))
			end
			saved.fov = nil
		end

		if tonumber(saved.tilt) then self.frame.tilt = saved.tilt end
		if tonumber(saved.zoom) then self.frame.zoom = saved.zoom end
		if tonumber(saved.fov)  then self.frame.fov  = saved.fov  end
		-- Acotado AL LEER, no solo al escribir: las SavedVariables sobreviven a
		-- la version que las escribio (la leccion del `grow = 688`).
		local sh = tonumber(saved.shadow)
		if sh then self.frame.shadow = (sh < 0) and -1 or math.min(5, math.floor(sh)) end
	end

	-- EL FRAME DE LA CAMARA, que ya no es el del canal. Se queda con sus dos
	-- eventos propios y con el `OnUpdate` del raton.
	local f = CreateFrame("Frame", "RTSCameraEvents")
	-- SetBinding is blocked in combat, so a camera switched off mid-fight would
	-- leave Q and E ours until the next toggle. Catch the moment combat drops
	-- and hand them back then.
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_LEAVING_WORLD")

	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if not C.active then ReleaseTurnKeys() end
		elseif event == "PLAYER_LEAVING_WORLD" then
			-- The server drops the camera on logout and zone change; make sure
			-- the player's keys come back with us.
			if C.active then C:OnState(false) end
		end
	end)

	-- LOS DOS VERBOS DE LA CAMARA. El resto de los que habia aqui se han ido a
	-- sus duenos: `WHAT` y `DID` a quien los pide, `GROUNDAT`/`POS` a `Route`,
	-- los `MARK*` a `Marks`, `VER` a `Link`.
	ns.Link:On("CAM", function(rest)
		-- El eco de nuestras propias peticiones (`CAM ON`, `CAM STATUS`,
		-- `CAM ZV 1`...) llega por aqui igual, asi que el formato SE VALIDA: la
		-- respuesta del servidor es un solo digito y nada mas.
		local state = rest:match("^([01])$")
		if state then C:OnState(state == "1") end
	end)

	ns.Link:On("CAMPOS", function(rest)
		local pback, pup = rest:match("^(%-?[%d%.]+) (%-?[%d%.]+)$")
		if pback then C:OnOffset(tonumber(pback) or 0, tonumber(pup) or 12) end
	end)

	-- La confirmacion del sondeo. Es de UN SOLO SENTIDO -- lo que manda el
	-- addon es `CAM SPEC 1`, o sea el verbo `CAM` -- asi que esta en
	-- `REPLY_ONLY` y no necesita discriminante de formato como `CAM`. Se valida
	-- igualmente el digito, que cuesta una linea.
	ns.Link:On("SPEC", function(rest)
		local state = rest:match("^([01])$")
		if state then C:OnSpec(state == "1") end
	end)

	ns.Link:On("SPECARM", function(rest)
		local state = rest:match("^([01])$")
		if state then C:OnArm(state == "1") end
	end)

	-- Igual que los dos de arriba: un solo sentido (el addon manda `CAM CTRL`),
	-- asi que esta en `REPLY_ONLY` y no hace falta discriminante.
	ns.Link:On("CTRL", function(rest)
		local state = rest:match("^([01])$")
		if state then C.bodyServer = (state == "1") end
	end)

	-- `self.events`, NO `self.frame`. `C.frame` es la tabla de ENCUADRE
	-- (tilt, zoom, fov, shadow, los dos topes de zoom) que se declara arriba y
	-- que este mismo `Create` acaba de rellenar desde las SavedVariables --
	-- guardar aqui el widget la machacaba entera.
	--
	-- FALLO PREEXISTENTE, encontrado el 2026-09-02 al mudar el canal, no
	-- introducido por la mudanza. Lo que rompia, en silencio y sin error:
	--
	--   * `cfg.fov` salia nil, o sea que el CVar prestado se escribia a 0 --
	--     que significa "no toques el FOV". La camara isometrica de la etapa 5g
	--     no se aplicaba nunca.
	--   * `cfg.maxFactor` y `cfg.distanceMax` nil: los topes de zoom no subian.
	--   * `cfg.shadow` nil: las sombras de la etapa 5o no se ponian.
	--   * `cfg.tilt`/`cfg.zoom` nil en el camino SIN encuadre guardado.
	--
	-- Por que no se veia: con un encuadre guardado, `C:Frame()` sale por
	-- `SetView(VIEW_SLOT)` antes de usar tilt y zoom, y `C:Report()` cae a
	-- `DEFAULTS` cuando la tabla no contesta -- asi que IMPRIMIA los valores
	-- correctos mientras no aplicaba ninguno. Un lector que miente en la
	-- direccion tranquilizadora es lo que lo mantuvo escondido.
	self.events = f

	if RTSCommandDB and type(RTSCommandDB.camMouselook) == "boolean" then
		self.mouselook.enabled = RTSCommandDB.camMouselook
	end

	-- SE BORRA LA CLAVE DE UNA VERSION QUE YA NO EXISTE. `camHold` guardaba la
	-- altura sobre el suelo, que esta quitada -- y las SavedVariables no olvidan
	-- ninguna clave: sobreviven a la version que la escribio. Sin esto, un
	-- cliente que llego a probarla se queda con basura en su fichero para
	-- siempre. Misma leccion que el `grow = 688` de la etapa 5j: lo guardado se
	-- revisa AL LEERLO, no solo al escribirlo.
	if RTSCommandDB then RTSCommandDB.camHold = nil end

	-- PURGA NUMERO DIEZ: `cut` y `cutz`, el corte seccional, descartado el
	-- 2026-09-10. Vivieron un dia y llegaron a disco (`cut = 15`, `cutz = 4`).
	--
	-- `SaveFrame` reescribe `camFrame` entera, asi que las claves caerian solas
	-- la proxima vez que el jugador toque el encuadre -- pero "solas" y "cuando
	-- toque algo" no es una purga: si no vuelve a tocarlo, se quedan para
	-- siempre. Las SavedVariables no olvidan ninguna clave.
	if RTSCommandDB and RTSCommandDB.camFrame then
		RTSCommandDB.camFrame.cut  = nil
		RTSCommandDB.camFrame.cutz = nil
	end

	-- Every frame: the camera position it watches is republished every frame,
	-- and a grace period measured in tens of milliseconds cannot be tracked on
	-- a slower timer.
	f:SetScript("OnUpdate", function(_, e) C:UpdateMouselook(e) end)

	-- The DLL may attach mid-session and the server may already have a camera
	-- running from before a reload, so ask rather than assume we start off.
	-- `VERSION` ya lo pide `Link:Create`.
	Send("CAM STATUS")
end
