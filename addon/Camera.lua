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
	  - Q/E rotation, which WoW binds to strafe by default

	=== the channel =========================================================

	Addon messages, whispered to ourselves:

	    SendAddonMessage("RTS", "CAM ON", "WHISPER", UnitName("player"))

	Whispering yourself is what keeps this working solo. Party would also have
	been hooked server-side, but party chat is where mod-playerbots reads its own
	commands, and a character need not be in a guild.

	The server answers on the same channel with "CAM 1" / "CAM 0". We wait for
	that rather than assuming, because enabling can legitimately fail -- dead, in
	flight, in a vehicle -- and we take the player's Q and E keys on the way in.
]]

local ADDON, ns = ...

local C = {}
ns.Camera = C

local PREFIX = "RTS"

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
-- guildMemberNotify is not a camera setting -- it is a second borrowed CVar,
-- carrying the one thing the packed selection channel cannot: a number. The DLL
-- reads it as the wanted field of view in tenths of a degree. It rides in this
-- list because it needs exactly the same discipline as the real camera CVars:
-- captured before the first change, put back on the way out.
local CVARS = {
	"cameraSmoothStyle", "cameraDistanceMaxFactor", "cameraDistanceMax",
	"guildMemberNotify",
}
local FOV_CVAR = "guildMemberNotify"
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

-- CHANGED 2026-08-16. Q and E used to turn the camera, which duplicated what the
-- mouse already does better, and left height on space/X -- flight actions that
-- stop existing the moment the camera stops flying.
--
-- Now the mouse owns rotation and Q/E own height, which is what was asked for
-- and is also the only arrangement that survives flight being off.
--
-- Height is the camera's WORLD Z, not its distance from the group. The first
-- version made Q/E zoom, which duplicated the scroll wheel and moved the camera
-- closer to and further from the party rather than up and down over it.
--
-- That has to go through the server. The camera creature is possessed, so the
-- client owns its position -- and with flight off (which is what makes WASD run
-- flat) the client has no vertical movement to offer at all. So Q/E report only
-- their key transitions, and the server moves the camera on its own tick for as
-- long as the key is held. Two messages per press, not one per frame.
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

local function GrabTurnKeys()
	if InCombatLockdown() then
		ns.Print("|cffffff00Teclas de camara no disponibles en combate|r - la camara sigue yendo.")
		return
	end

	-- CAMBIADO 2026-08-16, segunda vez y por buenas razones.
	--
	-- Q/E ROTAN. Van a las acciones propias del juego (TURNLEFT/TURNRIGHT), no
	-- a una funcion nuestra: el sistema de movimiento gira de forma continua y
	-- suave mientras la tecla esta pulsada, y eso no lo iguala nada movido
	-- desde un OnUpdate. Ademas asi rotar no depende del servidor para nada.
	--
	-- +/- SUBEN Y BAJAN. Esa parte SI tiene que ir por el servidor: la camara
	-- esta poseida, asi que el cliente manda su posicion, y con el vuelo
	-- apagado (que es lo que hace que WASD vaya plano) el cliente no ofrece
	-- ningun movimiento vertical. Las teclas solo avisan de que se pulsan y se
	-- sueltan; el servidor la sube mientras siga pulsada.
	for key, action in pairs({ Q = "TURNLEFT", E = "TURNRIGHT" }) do
		saved[key] = GetBindingAction(key) or ""
		SetBinding(key, action)
	end

	-- Las cuatro, porque "+" no es una tecla: en la fila de numeros se saca con
	-- Mayus y "=", asi que se coge "=" y tambien el teclado numerico, que es
	-- donde mucha gente espera encontrarlas.
	-- En un teclado espanol "+" ES una tecla propia (la del +, * y ]), no
	-- Mayus+"=" como en el americano. Se ponen las dos formas y las del
	-- teclado numerico: sobra con que exista una, y las que no existan en tu
	-- distribucion simplemente no se enlazan.
	for key, button in pairs({
		["+"]           = "RTSCamUpButton",
		["="]           = "RTSCamUpButton",
		["-"]           = "RTSCamDownButton",
		["NUMPADPLUS"]  = "RTSCamUpButton",
		["NUMPADMINUS"] = "RTSCamDownButton",
	}) do
		saved[key] = GetBindingAction(key) or ""
		SetBindingClick(key, button)
	end

	-- X sigue siendo la accion de descenso en vuelo, que no hace nada con el
	-- vuelo apagado. Se deja puesta para que encender el vuelo (/rts cam fly)
	-- devuelva el comportamiento de espacio/X sin volver a tocar teclas.
	saved.X = GetBindingAction("X") or ""
	SetBinding("X", "SITORSTAND")
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

--- Channel -----------------------------------------------------------------

-- `/rts debug` echoes both directions of the channel. A right-click that does
-- nothing can fail at four places -- the handler, the send, the server's
-- classification, or the order itself -- and narrowing that one step per test
-- cycle has been the slowest part of this whole build.
C.debug = false

local function Send(body)
	if C.debug then ns.Print("|cff888888-> " .. body .. "|r") end
	SendAddonMessage(PREFIX, body, "WHISPER", UnitName("player"))
end

-- The same pipe, for anything else that needs to reach mod-rts. Orders.lua uses
-- it for move and follow, which is why they no longer cost a chat whisper each.
function ns.SendServer(body)
	Send(body)
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
	for name, fn in pairs({ RTSCamDownButton = RTSCommand_CameraDown,
	                        RTSCamUpButton   = RTSCommand_CameraUp }) do
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

	-- Diagonal field of view in degrees while in RTS mode. WoW's own is 90;
	-- narrowing it flattens the perspective toward orthographic, which is most
	-- of what makes a scene read as a map rather than a place you are standing
	-- in. 0 leaves the client's alone. Needs rts_core injected -- it is the DLL
	-- that writes the camera struct.
	fov = 60,
}

C.frame = {
	tilt = C.DEFAULTS.tilt,
	zoom = C.DEFAULTS.zoom,
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
-- rts_core publishes. Nil without the DLL. Reported rather than used: there is
-- no way to SET a pitch in 3.3.5a, but a number is what makes a framing
-- reproducible in code instead of only in a saved view slot.
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

	ns.Print(("copy this line: |cff00ff00back=%.1f up=%.1f tilt=%.2f zoom=%.0f pitch=%s|r")
		:format(back, up, tilt, zoom, tonumber(f.fov) or 0,
		        pitch and ("%.1f"):format(pitch) or "no-dll"))
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
		cfg.fov = (n <= 0) and 0 or math.max(20, math.min(140, n))
		HoldCamera({ [FOV_CVAR] = tostring(math.floor(cfg.fov * 10)) })
		if cfg.fov == 0 then
			ns.Print("fov override |cffff0000off|r - the client's own 90 degrees.")
		else
			ns.Print(("fov = %.0f degrees (WoW's own is 90; lower is flatter)"):format(cfg.fov))
		end
		if RTS_Ready ~= 1 then
			ns.Print("|cffff0000rts_core is not injected|r - fov is written by the DLL.")
		end

	elseif key == "zoom" and n then
		cfg.zoom = math.max(1, math.min(50, n))
		HoldCamera({ cameraDistanceMaxFactor = cfg.maxFactor })
		CameraZoomOut(cfg.zoom)
		ns.Print(("zoom = %.0f applied"):format(cfg.zoom))

	else
		ns.Print(("camera framing: tilt=%.2f zoom=%.0f"):format(cfg.tilt, cfg.zoom))
		ns.Print("|cffffff00/rts cam tilt <sec>|r - negative tilts back up")
		ns.Print("|cffffff00/rts cam zoom <yards>|r / |cffffff00fov <deg>|r - |cffffff00frame|r re-applies all")
		return
	end

	RTSCommandDB.camFrame = { tilt = cfg.tilt, zoom = cfg.zoom, fov = cfg.fov }
end

function C:Create()
	MakeZoomButtons()

	local saved = RTSCommandDB and RTSCommandDB.camFrame
	if type(saved) == "table" then
		if tonumber(saved.tilt) then self.frame.tilt = saved.tilt end
		if tonumber(saved.zoom) then self.frame.zoom = saved.zoom end
		if tonumber(saved.fov)  then self.frame.fov  = saved.fov  end
	end

	local f = CreateFrame("Frame", "RTSCameraChannel")
	f:RegisterEvent("CHAT_MSG_ADDON")
	f:RegisterEvent("PLAYER_LEAVING_WORLD")
	-- SetBinding is blocked in combat, so a camera switched off mid-fight would
	-- leave Q and E ours until the next toggle. Catch the moment combat drops
	-- and hand them back then.
	f:RegisterEvent("PLAYER_REGEN_ENABLED")

	f:SetScript("OnEvent", function(_, event, prefix, message)
		if event == "PLAYER_REGEN_ENABLED" then
			if not C.active then ReleaseTurnKeys() end
			return
		end

		if event == "PLAYER_LEAVING_WORLD" then
			-- The server drops the camera on logout and zone change; make sure
			-- the player's keys come back with us.
			if C.active then C:OnState(false) end
			return
		end

		if prefix ~= PREFIX or type(message) ~= "string" then return end
		if C.debug then ns.Print("|cff888888<- " .. message .. "|r") end

		-- We hear our own outgoing requests too (they are whispered to us), so
		-- only the server's state replies are acted on.
		-- The server module's own version, so all three pieces can be checked
		-- at once instead of the DLL's standing in for the whole project.
		-- What the server decided a right-click meant, and how many bots took
		-- it. Printed because a click that silently does nothing is the single
		-- most confusing failure in this whole system.
		local tg = message:match("^TGTS (.+)$")
		if tg then ns.Targets:OnData(tg) return end
		if message == "TGTEND" then ns.Targets:OnDataEnd() return end

		local whatGuid, whatKind = message:match("^WHAT (%S+) (%d)$")
		if whatGuid then ns.RTSMode:OnKind(whatGuid, tonumber(whatKind)) return end

		local bars, blist = message:match("^BARS (%S+) (.*)$")
		if bars then ns.CommandMode:OnBars(bars, blist) return end

		local barsEnd = message:match("^BARSEND (%S+)$")
		if barsEnd then ns.CommandMode:OnBarsEnd(barsEnd) return end

		local focus = message:match("^FOCUS (.*)$")
		if focus then
			if focus == "-" then ns.Focus:Clear() else ns.Focus:Set(focus, 1) end
			return
		end

		local did, n, label = message:match("^DID (%a+)%s*(%d*)%s*(.*)$")
		if did then
			if did == "ATTACK" then
				local p = ns.Orders.lastClick
				if p then ns.Flare:Show(p.x, p.y, p.z, "attack") end
				ns.Focus:Set(label ~= "" and label or nil, tonumber(n) or 0)
				ns.Print(("Attack %s -> %s unit%s"):format(
					label ~= "" and ("|cffff6666" .. label .. "|r") or "target",
					n == "" and "0" or n, n == "1" and "" or "s"))
			elseif did == "INTERACT" then
				-- NO se manda `talk` aqui. El servidor YA ha interactuado --
				-- eso es justo lo que este mensaje nos esta contando -- y ademas
				-- distingue un PNJ (gossip) de un cadaver (botin).
				--
				-- La llamada que habia aqui era de cuando el servidor no lo
				-- hacia y el addon tenia que pedirlo por chat. Al pasarle esa
				-- tarea al servidor, esta linea se quedo de duplicado: sobre un
				-- cadaver susurraba `talk` -- querer hablar con un muerto -- y
				-- encima interrumpia la ventana de botin recien abierta, que es
				-- por lo que solo recogias una cosa y el resto se quedaba.
				--
				-- Mismo patron que ya costo una ronda entera: un apano en pie
				-- despues de que desapareciera el motivo que lo puso ahi.
				if n ~= "" and tonumber(n) == 0 then
					ns.Print("|cffffff00Nadie pudo interactuar.|r")
				end
			elseif did == "MOVE" and n == "0" then
				ns.Print("|cffffff00Move order reached no bots.|r")
			end
			return
		end

		local pback, pup = message:match("^CAMPOS (%-?[%d%.]+) (%-?[%d%.]+)$")
		if pback then
			C:OnOffset(tonumber(pback) or 0, tonumber(pup) or 12)
			return
		end

		local ver = message:match("^VER (%S+)$")
		if ver then C.serverVersion = ver return end

		local state = message:match("^CAM ([01])$")
		if state then
			-- Any reply at all proves mod-rts is installed and listening, which
			-- is what lets Orders send moves down this pipe instead of paying
			-- for a chat whisper (and an emote) per bot.
			if not C.serverSeen then
				C.serverSeen = true
				ns.Print("|cff00ff00server module attached|r - direct orders enabled.")
			end
			C:OnState(state == "1")
		end
	end)

	self.frame = f

	if RTSCommandDB and type(RTSCommandDB.camMouselook) == "boolean" then
		self.mouselook.enabled = RTSCommandDB.camMouselook
	end

	-- Every frame: the camera position it watches is republished every frame,
	-- and a grace period measured in tens of milliseconds cannot be tracked on
	-- a slower timer.
	f:SetScript("OnUpdate", function(_, e) C:UpdateMouselook(e) end)

	-- The DLL may attach mid-session and the server may already have a camera
	-- running from before a reload, so ask rather than assume we start off.
	Send("CAM STATUS")
	Send("VERSION")
end
