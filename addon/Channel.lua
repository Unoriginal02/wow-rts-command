--[[
	Channel.lua -- the addon -> DLL direction.

	rts_core.dll can push data at us all day (it executes Lua that assigns
	RTS_* globals), but it cannot ask us anything: a C function pointer that
	lives outside Wow.exe is rejected by the client's Lua with ERROR #134 and
	takes the client down with it. That is why the DLL could tint models but
	had no idea which ones you had selected.

	A CVar closes the loop. It is ordinary client memory, Lua is allowed to
	write it with SetCVar, and the client parses the value into an int the DLL
	reads straight out of the CVar object (+0x30 -- see Offsets.h).

	=== protocol 3 ==========================================================

	    bits  0..23   eight slots x three bits of state
	    bits 24..26   sequence number
	    bit  27       draw the native ground circle
	    bit  28       also glow the unit models
	    bit  29       diagnostic: a circle under EVERY published unit
	    bit  30       LIBRE otra vez -- ver abajo
	    bit  31       unusable -- the client parses the value with a SIGNED atoi

	El bit 30 se uso unas horas del 2026-09-06 para dibujar cada aro DOS veces,
	con la idea de que saldria mas marcado. En juego salen dos aros, asi que
	esta fuera de los dos lados: el addon no lo manda y el DLL ya no lo lee.
	Quien lo reutilice no hereda nada.

	Con los cinco bits altos puestos y el peor caso de estados y secuencia el
	valor no llega a 2^31, que es el techo del `atoi` con signo.

	Protocol 2 packed nine state slots into bits 0..26 and had no room left:
	the sequence took 27..29 and the model glow took 30. The native ground
	circle needed a gate bit of its own, so a slot was given up for it -- nine
	to eight, when the party this was built for is at most five. Both sides
	refuse to decode a value from the other protocol, so a half-updated install
	(new addon, old DLL, or the reverse) goes quiet instead of misfiring.

	Slot k is the k-th player in the DLL's published list (RTS_U1..RTS_UN with
	T == 4). Creatures do not take a slot; they can never be selected, and
	spending three bits on each of them would have cost the states we need.
	State codes come from State.lua and mean a colour on the model.

	=== why a sequence number, and not a stamp of the list ===================

	Protocol 1 sent a selection bitmask stamped with a hash of the published
	guids, and the DLL threw the whole reply away when the hash did not match.
	That is what made the tint blink. The published list is sorted, our reply is
	always a tick old, and ANY change to the list -- two bots swapping places was
	enough -- invalidated the stamp, so the mask was dropped, every unit was
	cleared, and the tint came back a frame or two later. Constantly, because
	bots move.

	Now the DLL keeps the last eight lists it published and our reply just names
	which one it was computed from. The DLL resolves slot k to a GUID from that
	list and matches it by identity against the list it is publishing now, so a
	late reply is stale rather than wrong and nothing is ever dropped.

	The CVar we borrow is a PvP AFK-notification toggle, meaningless on a
	private server with no PvP. Its original value is saved on login and put
	back on logout, so nothing leaks into Config.wtf.
]]

local ADDON, ns = ...

local C = {}
ns.Channel = C

local CVAR = "enablePVPNotifyAFK"
local PROTOCOL = 3

-- How many units the DLL publishes -- kPublishedUnits in Publisher.cpp, and it
-- must not be smaller than that or the far end of every published list is
-- silently ignored. Shared on the namespace because RTSMode picks its attack
-- targets out of the same list, and the two drifting apart is how a hostile you
-- can plainly see becomes unclickable.
ns.MAX_UNITS = 32
local MAX_UNITS = ns.MAX_UNITS
local STATE_SLOTS  = 8        -- how many of them can carry a state
local STATE_STEP   = 8        -- 3 bits per slot
local SEQ_STEP     = 2 ^ 24   -- slots occupy bits 0..23
local CIRCLE_STEP  = 2 ^ 27   -- native ground circle under selected units
local TINT_STEP    = 2 ^ 28   -- model glow, on top of the circle
local ALL_STEP     = 2 ^ 29   -- diagnostic: circle on every unit, one colour
local PLAYER_TYPE  = 4        -- RTS_U{i}T for a player object
local UPDATE_EVERY = 0.05

C.last = nil

-- Value to hand back when we are done. Anything that is not a plain toggle is
-- one of ours from a session that did not shut down cleanly, so it is ignored.
local function CaptureOriginal()
	if RTSCommandDB.cvarBackup then return end
	local v = GetCVar(CVAR)
	if v ~= "0" and v ~= "1" then v = "1" end
	RTSCommandDB.cvarBackup = v
end

local function Restore()
	SetCVar(CVAR, RTSCommandDB.cvarBackup or "1")
end

-- guid -> state code, for everything currently selected.
local function SelectionStates()
	local out = {}
	for _, name in ipairs(ns.Selection:Get()) do
		local unit = ns.Selection:UnitFor(name)
		local guid = unit and UnitGUID(unit)
		if guid then
			out[string.upper(guid)] = ns.UnitState:Code(name, unit, guid)
		end
	end
	return out
end

-- The packed value for right now, or nil when there is nothing to answer.
function C:Value()
	local seq = RTS_UGEN
	if not seq then return nil end

	-- Refuse to answer a DLL that speaks protocol 1: RTS_UGEN was a 14-bit hash
	-- there, and shifting one of those into the sequence field would overflow
	-- the signed range and land as garbage rather than as a stale reply.
	if RTS_PROTO ~= PROTOCOL then return nil end

	local states = SelectionStates()

	-- Slot k = the k-th player in the published list. The DLL walks its own copy
	-- of that list the same way, so neither side has to send indices.
	local bits, slot, place = 0, 0, 1
	local count = math.min(RTS_UN or 0, MAX_UNITS)
	for i = 1, count do
		if slot >= STATE_SLOTS then break end
		if _G["RTS_U" .. i .. "T"] == PLAYER_TYPE then
			local g = _G["RTS_U" .. i .. "G"]
			local s = (g and states[string.upper(g)]) or 0
			bits = bits + s * place
			slot = slot + 1
			place = place * STATE_STEP
		end
	end

	-- Bit 27 asks for the native ground circle under each selected unit; bit 28
	-- additionally glows the models. BOTH ARE ON BY DEFAULT since 2026-09-18:
	-- the circle marks the ground and the glow marks the character, and from an
	-- RTS camera the ground is the half that competes with the grass. Either one
	-- can be switched off on its own (`/rts ring`, `/rts ring tint`).
	local ring = ns.SelectionRing
	local circle = (ring and ring.enabled) and CIRCLE_STEP or 0
	local tint   = (ring and ring.modelTint) and TINT_STEP or 0
	local all    = (ring and ring.testAll) and ALL_STEP or 0

	return all + tint + circle + seq * SEQ_STEP + bits
end

-- Only writes when the value actually changes: SetCVar is cheap but it runs the
-- CVar's change callback, and firing that 20x/second for an unchanged value is
-- pointless work inside the client.
function C:Update()
	local v = self:Value()
	if not v or v == self.last then return end
	self.last = v
	SetCVar(CVAR, tostring(v))
end

function C:Create()
	CaptureOriginal()

	local f = CreateFrame("Frame", "RTSChannel", UIParent)
	f:RegisterEvent("PLAYER_LOGOUT")
	f:SetScript("OnEvent", Restore)

	local acc = 0
	f:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < UPDATE_EVERY then return end
		acc = 0
		C:Update()
	end)

	self.frame = f
end

-- Diagnostic: what we are sending and what it decodes to.
function C:Dump()
	if RTS_UGEN == nil then
		ns.Print("|cffff0000channel:|r no unit list published yet (is rts_core injected?)")
		return
	end
	if RTS_PROTO ~= PROTOCOL then
		ns.Print(("|cffff0000channel:|r DLL speaks protocol %s, this addon speaks %d.")
			:format(tostring(RTS_PROTO or 1), PROTOCOL))
		ns.Print("Re-inject the current rts_core.dll -- tinting is off until then.")
		return
	end

	local v = self:Value()
	if not v then ns.Print("|cffff0000channel:|r nothing to send.") return end

	local all = math.floor(v / ALL_STEP)
	local rest = v - all * ALL_STEP
	local tint = math.floor(rest / TINT_STEP)
	rest = rest - tint * TINT_STEP
	local circle = math.floor(rest / CIRCLE_STEP)
	rest = rest - circle * CIRCLE_STEP
	local seq = math.floor(rest / SEQ_STEP)
	local bits = rest - seq * SEQ_STEP
	ns.Print(("channel: cvar=%s value=%d seq=%d circle=%d modeltint=%d testall=%d (published seq=%s)")
		:format(CVAR, v, seq, circle, tint, all, tostring(RTS_UGEN)))

	local slot = 0
	local count = math.min(RTS_UN or 0, MAX_UNITS)
	for i = 1, count do
		if _G["RTS_U" .. i .. "T"] == PLAYER_TYPE and slot < STATE_SLOTS then
			local s = math.floor(bits / (STATE_STEP ^ slot)) % STATE_STEP
			ns.Print(("  slot %d  unit %d  %s  -> %s")
				:format(slot, i, tostring(_G["RTS_U" .. i .. "G"]),
				        ns.UnitState.NAMES[s] or ("?" .. s)))
			slot = slot + 1
		end
	end
	if slot == 0 then ns.Print("  (no players in the published list)") end
end
