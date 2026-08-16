--[[
	State.lua -- what each commanded unit is DOING, as a colour.

	rts_core.dll tints unit models through the client's own highlight, which is
	drawn as part of the model and therefore occluded by terrain for free. The
	DLL can see WHERE units are but has no idea what you asked them to do, so the
	meaning has to come from here and go out over the CVar channel (Channel.lua).

	  blue    selected, standing by
	  green   walking to an ordered point, and for as long as they keep walking
	  red     sent to fight, and for as long as they are fighting
	  orange  interacting

	=== how a state is decided =============================================

	Two sources, and the second is what stops the colour lying:

	  the ORDER    -- classified from the playerbots command text itself, so
	                  every path that sends an order is covered without any
	                  call site having to remember to tag anything
	  the WORLD    -- UnitAffectingCombat for fighting, and the DLL's own
	                  position stream for movement

	An order alone would leave a bot green forever after one move order. The
	world alone cannot tell "walking because you told it to" from "walking
	because it is following you". Together they behave: the order picks the
	colour, the world decides how long it lasts.
]]

local ADDON, ns = ...

local S = {}
ns.UnitState = S

-- Wire codes. These MUST match TintState in the DLL's Publisher.cpp; they go
-- out three bits at a time, so nothing above 7 will ever fit.
S.NONE     = 0
S.SELECTED = 1
S.MOVING   = 2
S.COMBAT   = 3
S.INTERACT = 4

-- How long an order holds its colour with no corroboration from the world.
-- These are floors, not lifetimes. Outgoing chat is spaced 0.15s per whisper,
-- the server relays it, and the bot then has to react -- an order that dropped
-- its colour the moment it was sent would flash and be gone before the bot took
-- a single step.
local MOVE_GRACE    = 1.5
local COMBAT_GRACE  = 4.0
local INTERACT_HOLD = 2.5    -- nothing reports "done interacting"; time it out

-- No new published position in this long means the unit is standing still.
local STOPPED_AFTER = 0.30

S.orders = {}   -- unit name -> { kind = ..., at = GetTime() }

--- Order classification ----------------------------------------------------
-- Keyed on the playerbots command text rather than on the function that sent
-- it, because every order in the addon -- command card, key bindings, the RTS
-- mouse handler, and `/rts cmd <anything>` -- ends up as a string passed to
-- Orders:Send / SendTo / Broadcast. Classifying there catches all of them, and
-- catches any order added later for free.

local KIND = {
	-- movement
	go        = "move",
	follow    = "move",
	flee      = "move",
	runaway   = "move",
	formation = "move",
	-- `position stay X,Y,Z` is how an RTS move order is actually issued: it
	-- moves the anchor the bot wants to stand on, and the bot walks there on
	-- its own. See Orders:MoveUnitTo. It is always the LAST message of a move
	-- order, which matters -- the `stay` that arms the anchor classifies as a
	-- stop, and would otherwise leave the unit reading as idle while walking.
	position  = "move",
	-- combat
	attack          = "combat",
	pull            = "combat",
	grind           = "combat",
	["tank attack"] = "combat",
	["max dps"]     = "combat",
	-- interaction
	cast = "interact",
	-- an explicit stop is not a state of its own: it ends whatever was running
	stay = "stop",
}

-- "tank attack" and "max dps" are two words; everything else is one. Try the
-- pair first so "max dps" is not read as an unknown verb "max".
function S:Classify(command)
	if type(command) ~= "string" then return nil end
	local w1, w2 = command:lower():match("^(%a+)%s*(%a*)")
	if not w1 then return nil end
	if w2 and w2 ~= "" then
		local pair = KIND[w1 .. " " .. w2]
		if pair then return pair end
	end
	return KIND[w1]
end

-- Record that `name` was just given `command`. Unknown commands leave the
-- current state alone rather than resetting it -- a raw command we cannot
-- classify is not evidence that the bot stopped what it was doing.
function S:Note(name, command)
	local kind = self:Classify(command)
	if not kind then return end
	if kind == "stop" then
		self.orders[name] = nil
	else
		self.orders[name] = { kind = kind, at = GetTime() }
	end
end

function S:Forget(name)
	self.orders[name] = nil
end

--- Live evidence -----------------------------------------------------------

-- Is the DLL still seeing this unit move? Markers:SampleUnits only stamps `ct`
-- when the published position actually CHANGES, so "moved recently" is a direct
-- read of the position stream rather than a velocity threshold to tune.
local function Moving(guid)
	if not guid then return false end
	local t = ns.Markers.track[string.upper(guid)]
	if not t then return false end
	return (GetTime() - t.ct) < STOPPED_AFTER
end

--- Resolution --------------------------------------------------------------

-- The wire code for one selected unit. Self-pruning: an order that no longer
-- holds its colour up is finished, and is dropped on the way past.
function S:Code(name, unit, guid)
	-- Combat outranks everything and needs no order behind it. "Red while
	-- fighting" means a bot that gets jumped goes red on its own.
	if unit and UnitAffectingCombat(unit) then return self.COMBAT end

	local o = self.orders[name]
	if o then
		local age = GetTime() - o.at
		if o.kind == "combat" then
			if age < COMBAT_GRACE then return self.COMBAT end
		elseif o.kind == "interact" then
			if age < INTERACT_HOLD then return self.INTERACT end
		elseif o.kind == "move" then
			-- The grace covers the trip from keypress to first step; after that
			-- the bot's own movement is what keeps it green.
			if age < MOVE_GRACE or Moving(guid) then return self.MOVING end
		end
		self.orders[name] = nil
	end

	return self.SELECTED
end

S.NAMES = { [0] = "none", "selected", "moving", "combat", "interact" }
