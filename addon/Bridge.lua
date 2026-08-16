--[[
	Bridge.lua -- native capability layer.

	WotLK 3.3.5a Lua cannot do three things this addon eventually needs:
	  1. read/steer the camera            (no API at all)
	  2. turn a screen click into a world position (no raycast until Cataclysm)
	  3. project a world position to screen (needed for drag-box selection)

	rts_core.dll will provide those by assigning a table to RTSCommand.Bridge.impl.
	Until then every call here returns nil and the addon degrades to the
	coordinate-free order set (go <name> / stay / follow / attack), which is
	fully functional -- just not click-to-move.

	Nothing outside this file may touch impl directly. Orders and UI ask the
	Bridge and branch on nil. That way the DLL landing is a pure upgrade with
	no changes anywhere else.
]]

local ADDON, ns = ...
RTSCommand = ns

local B = {}
ns.Bridge = B

-- rts_core.dll cannot expose callable C functions to WoW's Lua: the client
-- rejects C function pointers outside Wow.exe (ERROR #134). So the DLL PUSHES
-- instead -- it sets plain Lua globals (RTS_Ready, RTS_PX, ...) ~10x/second via
-- the client's own script execution. We read those globals; nothing is called
-- across the boundary.

B._attached = false

function B:IsNative()
	return RTS_Ready == 1
end

-- Returns true the first time the native side is detected.
function B:TryAttach()
	if self._attached then return false end
	if RTS_Ready ~= 1 then return false end

	self._attached = true
	self.version = RTS_Version or "?"
	return true
end

-- Player world position, or nil if the DLL is absent / not in world yet.
function B:GetPlayerWorldPosition()
	if RTS_Ready ~= 1 or RTS_HasPos ~= 1 then return nil end
	return RTS_PX, RTS_PY, RTS_PZ, RTS_PF
end

-- Per-unit world position is not available in the push model yet (the DLL would
-- need to know which GUID to publish). Returns nil until the request channel
-- exists; callers already branch on nil.
function B:GetUnitWorldPosition(_, _)
	return nil
end

function B:ObjectCount()
	return RTS_N
end

-- Monotonic counter the DLL bumps each publish. Lets us tell "attached and
-- alive" from "attached but the DLL stopped ticking".
function B:Heartbeat()
	return RTS_HB
end

-- Ground point under the mouse cursor as x, y, z world coords, or nil.
-- rts_core 0.8.0+ raycasts the cursor against real terrain and publishes the
-- hit; Markers unprojects onto a plane at that height each frame, so the point
-- is both correct on slopes and locked to the mouse. Without the DLL it falls
-- back to a plane at the player's Z -- fine beside your character, wrong up a
-- hill. This is what makes Move a click-to-move order.
function B:GetCursorWorldPosition()
	if not ns.Markers then return nil end
	return ns.Markers:GetCursorPoint()
end

--- Convenience -------------------------------------------------------------

-- True when we can issue coordinate orders ("go X;Y;Z").
function B:HasWorldCoords()
	return self:GetPlayerWorldPosition() ~= nil
end

return B
