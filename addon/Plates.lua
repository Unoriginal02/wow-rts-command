--[[
	Plates.lua -- the client's nameplates, the V bar and the friendly one.

	NOTHING IS DRAWN HERE. The bars over the heads are the client's own, same as
	the selection circle: they are part of the scene, so they are occluded, they
	sit at the right height on a slope and they cannot lag the frame. This file
	owns the three switches that decide what the client draws, and no more.

	=== why they were invisible in RTS mode ================================

	Not a setting, and not this addon: the client refused to draw them. The gate
	that decides whether a unit gets a plate starts by looking up the unit THE
	CAMERA IS ATTACHED TO, and gives up on every unit if it cannot find one --
	and the free camera is free precisely because that field is empty. First
	person kept its plates because there the camera IS attached to you.

	The whole chain is disassembled in `rts-client-mod/src/Offsets.h`, and the
	cure is two small patches in `Plates.cpp`: the gate is given the hero as its
	reference and the camera is left alone. They arm themselves when the camera
	loses its unit and go back when it gets one, so there is no switch here to
	leave half-set -- which is why this file has no on/off at all.

	YOUR OWN HERO WEARS NO BAR, and that is a decision, not a leftover: the two
	further doors that would give him one were found and deliberately left shut.

	`/rts plates probe` is what found them, and it stays: it nulls the gate's
	refusals ONE MORE AT A TIME and calls the gate after each, so a door that is
	shut says its own name in `rts_core.log` instead of costing a session per
	guess.

	=== what IS ours ======================================================

	  nameplateShowEnemies   the V key. The client's, both of them.
	  nameplateShowFriends   your bots' health over their heads.
	  rtsPlates              how far a plate may be, in yards. OURS, read by the
	                         DLL, and only while the free camera is up.

	The two nameplate CVars are PER CHARACTER and the client already saves them.
	They are read here and never forced: pressing V is the player's business,
	and a mode that switches your plates on because it thinks it knows better is
	the same rudeness as one that leaves them on afterwards.

	The distance is a different matter. The client's ceiling is 41 yards from
	the reference unit, which is right for a camera on your shoulder and covers
	about the middle of the screen from an RTS camera. So the DLL widens it
	while the free camera is up -- 260 yards unless this says otherwise, which
	is past the 250 the server will send at all -- and puts 41 back on the way
	out.
]]

local ADDON, ns = ...

local P = {}
ns.Plates = P

-- Ours, created with RegisterCVar. Never a borrowed one: `SetCVar` on a name
-- the client does not know **gives no error**, it does nothing, which is how
-- the FOV channel spent three stages dead with nothing saying so.
local RANGE_CVAR = "rtsPlates"

local ENEMY_CVAR  = "nameplateShowEnemies"
local FRIEND_CVAR = "nameplateShowFriends"

-- 0 means "the DLL's own default", which is 260 yards -- past the 250 the
-- server sends at all, so nothing visible is left out. The value is only read
-- while the patch is armed, so writing it outside RTS mode is harmless.
local DEFAULT = 0
local MIN, MAX = 10, 1000

local function On(cv)
	local v = GetCVar(cv)
	return v ~= nil and v ~= "0"
end

local function Word(v)
	return v and "|cff00ff00on|r" or "|cffff0000off|r"
end

function P:Create()
	if type(RegisterCVar) == "function" and GetCVar(RANGE_CVAR) == nil then
		RegisterCVar(RANGE_CVAR, tostring(DEFAULT))
	end
	if GetCVar(RANGE_CVAR) == nil then
		ns.Print(("|cffff0000plates:|r cannot create |cffffff00%s|r; the range " ..
			"stays at the DLL's default."):format(RANGE_CVAR))
	end
end

function P:SetRange(arg)
	local n = tonumber(arg)
	if not n then
		ns.Print("|cffffff00/rts plates <yards>|r -- 0 leaves it at the default (260).")
		return
	end
	n = math.floor(n)
	if n ~= 0 then
		if n < MIN then n = MIN end
		if n > MAX then n = MAX end
	end
	if GetCVar(RANGE_CVAR) == nil then
		ns.Print("|cffff0000plates:|r the CVar does not exist; nothing was written.")
		return
	end
	SetCVar(RANGE_CVAR, tostring(n))
	if n == 0 then
		ns.Print("nameplate range: |cffffff00260|r yards (the default)")
	else
		ns.Print(("nameplate range: |cffffff00%d|r yards"):format(n))
	end
	ns.Print("Only while the RTS camera is up. Outside it the client's own 41 " ..
		"yards come back.")
end

local function Flip(cv, what)
	local want = not On(cv)
	SetCVar(cv, want and "1" or "0")
	ns.Print(("%s nameplates %s"):format(what, Word(want)))
	return want
end

function P:ToggleFriends()
	Flip(FRIEND_CVAR, "friendly")
	ns.Print("Your bots' health over their heads. It is the client's own bar, " ..
		"the same one the V key draws on enemies, and the client remembers it " ..
		"per character.")
end

function P:ToggleEnemies()
	Flip(ENEMY_CVAR, "enemy")
end

-- LA SONDA, y no es una funcion: el heroe se quedo sin barra con los tres
-- parches puestos, asi que hay una CUARTA puerta en el portero del cliente y
-- adivinar cual de las diez cuesta una sesion por intento. Esto lee las
-- condiciones del portero para tu heroe Y para un bot de al lado -- uno de los
-- que SI lleva barra -- y escribe las dos lineas juntas en `rts_core.log`. Lo
-- que se diferencie es la respuesta.
function P:Probe()
	if GetCVar(RANGE_CVAR) == nil then
		ns.Print("|cffff0000plates:|r no existe el CVar; la sonda no se puede armar.")
		return
	end
	SetCVar(RANGE_CVAR, "-1")
	ns.Print("sonda de rotulos |cff00ff00ON|r - una linea por segundo en " ..
		"|cffffff00rts_core.log|r, con el modo RTS puesto y un bot cerca.")
	ns.Print("Se apaga con |cffffff00/rts plates 0|r. El alcance no cambia.")
end

function P:Status()
	ns.Print(("nameplates -- enemies %s, friendly %s, range %s"):format(
		Word(On(ENEMY_CVAR)), Word(On(FRIEND_CVAR)),
		tostring(GetCVar(RANGE_CVAR) or "?")))
	ns.Print("|cffffff00/rts plates friends|r, |cffffff00enemies|r, " ..
		"|cffffff00<yards>|r. The V key writes the enemy one itself.")
	if RTS_Ready ~= 1 then
		ns.Print("|cffff0000rts_core is not injected|r -- and under the free camera " ..
			"the client draws NO plates without it. Open the game with " ..
			"|cffffff002-Jugar.bat|r.")
	end
end
