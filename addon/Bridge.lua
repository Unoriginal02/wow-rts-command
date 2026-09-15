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

--- What you are called ------------------------------------------------------
--
-- `UnitName("player")` IS NOT TO BE TRUSTED now that you can change character
-- without going through the selection screen. Seen in game on 2026-09-03: after
-- the swap the client still shows the previous character's name, both in its
-- own frame and in that call. The identity DOES change -- the guid is the new
-- one and the party is the new one -- but the text lags behind.
--
-- And it is not cosmetic, because the hero you leave behind comes back as a bot
-- AND IS CALLED WHAT YOU USED TO BE CALLED: half a dozen places in the addon
-- compare names to decide "is this my character?", and with the old name stuck
-- on, every one of them answers yes about the wrong bot. On top of that the
-- channel to the server whispers to yourself BY NAME, so a stale name strikes
-- the whole thing dumb.
--
-- The server says it when the swap finishes (`SWAPPED`) and that is where it is
-- stored, TOGETHER WITH THE GUID IT REFERS TO: without that, a swap followed by
-- a reconnect would leave someone else's name stuck on forever. The guid is the
-- only identity that does not lie -- it comes out of the client's object
-- manager, which is the field `UPDATEFLAG_SELF` writes -- so the override only
-- holds while it is still the same one.
function ns.MyName()
	if ns.serverName and ns.serverNameGuid
	   and ns.serverNameGuid == UnitGUID("player") then
		return ns.serverName
	end
	return UnitName("player")
end

-- AND THE CLASS HAS EXACTLY THE SAME DEFECT, found on 2026-09-05 looking at a
-- mage wearing the warrior's colour after a swap.
--
-- It was not a suspicion: it is disassembled. `UnitClass` (`0x0060FEC0`)
-- compares its argument against the string "player" just like `UnitName`, and
-- if it matches it does NOT look at the object -- it calls `0x006B1080`, which
-- is two instructions:
--
--     006B1080  mov al, byte ptr [0xC79E89]
--     006B1085  ret
--
-- A static byte. And it sits right next to the name's (`0x00C79D18`, via
-- `0x006B1060`) and the race's (`0x00C79E8A`, via `0x006B1090`), which means
-- they are the SAME block: the "who am I" record that the character selection
-- screen fills in -- precisely the step the swap skips.
--
-- SO THE RULE IS WIDER THAN 0.62.0 SAID: it is not that "player"'s NAME lies
-- after a swap, it is that **"player"'s name, class and race all three lie**,
-- and those are the three fields the client keeps to one side instead of
-- reading from the object. Everything else (health, power, portrait, spells)
-- comes from the object and is correct -- which is exactly what made the
-- symptom so odd: the portrait was Bob and the name was Neferite.
--
-- THE CLASS IS LEARNED FROM THE PARTY, not from the server, and for two
-- reasons. One: the character you jump into WAS a party member of yours a second
-- earlier, so its `UnitClass("partyN")` -- which does go through the object --
-- has already been read and is correct. Two: that way no new verb is needed,
-- nor a hand-written table of class ids, which is the kind of constant this
-- project pays dearly for.
--
-- With no learned entry it falls back to `UnitClass("player")`, which is correct
-- as long as there has been no swap -- that is, always, in a normal session.
-- IT IS SAVED TO DISK, and it has to be: what is learned lives in memory, so a
-- `/reload` after a swap would lose it -- and then the colour would be wrong
-- again, because your own character does NOT appear in your party and there is
-- nowhere to relearn it from. A `/reload` is also the first thing anyone does
-- when something looks odd, which is to say exactly the gesture that would
-- reintroduce the bug.
--
-- The key is the name and the value a class token. It can be saved without
-- thinking twice because **a character's class never changes**: an old entry
-- cannot go stale, only go spare. It is the opposite of `grow = 688` and of
-- `camHold`, which were settings whose meaning changed.
local classOf

local function Learned()
	if classOf then return classOf end
	if type(RTSCommandDB) ~= "table" then return nil end
	RTSCommandDB.classOf = RTSCommandDB.classOf or {}
	classOf = RTSCommandDB.classOf
	return classOf
end

function ns.NoteClass(name, unit)
	if not name or not unit then return end
	local t = Learned()
	if not t then return end
	local token = select(2, UnitClass(unit))
	if token then t[name] = token end
end

function ns.MyClass()
	local mine = ns.MyName()
	local t = Learned()
	if mine and t and t[mine] then return t[mine] end
	return select(2, UnitClass("player"))
end

-- IS THIS TOKEN ME? By guid, never by name -- the 0.60.0 rule. It is needed
-- because after a swap there is a party member called what you used to be
-- called.
function ns.IsMe(unit)
	if not unit then return false end
	if unit == "player" then return true end
	return UnitIsUnit(unit, "player") and true or false
end

-- The name to SHOW for a token. For anyone but you it is the client's; for you
-- it is the only one that does not lie.
function ns.UnitLabel(unit)
	if ns.IsMe(unit) then return ns.MyName() end
	return UnitName(unit)
end

return B
