--[[
	Marks.lua -- the route markers THE CLIENT draws, not us.

	Everything this addon has put "in the world" so far was an interface
	texture parked on the pixel where the projection lands: no depth, drawn on
	top of the hill that ought to hide it, and swimming sideways every time the
	camera turns. The real effects the client has -- the selection circle, the
	model glow, the nameplates -- are all PER UNIT and need a GUID to hang off.
	A route point is bare ground.

	The exception is the `DynamicObject`: it lives at any position in the world
	and the client paints the persistent visual of its spell on top of it, in
	its own drawing loop and with correct depth. It is what the patches of
	Consecration or Death and Decay are. So we do not draw the marker: we place
	an object and the client draws it -- the same deal that made the nameplates
	work back in stage 5e.

	WHICH SPELL is a question for the EYE, not for the code: every visual has
	its own size, its own colour and its own animation, and a list of ids
	written from memory is exactly the kind of constant that in this project
	draws nothing without raising an error. Hence:

	  * the candidate list is built by the SERVER out of the already loaded
	    spell store -- all the ones with a persistent area aura effect, which
	    are exactly those the client has a ground visual for;
	  * and here lives the tool to walk it live, `/rts mark`, with the markers
	    of the route already laid down changing underneath while you step from
	    one to the next.

	When there is a winner, it is fixed with `/rts mark <id>` and
	`/rts mark size <n>`, which is what stays saved; hardcoding it means
	changing the default values of `M.cfg`.

	THE SLOT IS NOT THE POSITION IN THE ROUTE, IT IS AN IDENTITY. If the slot
	were "the third of the ones left", stepping on the first point would
	renumber all the rest and the whole route would have to be laid out again
	on every arrival. Every point is born with a number of its own that does
	not change, so reaching one is a single order to remove.
]]

local ADDON, ns = ...

local M = {}
ns.Marks = M

-- Goes up when a factory value changes in a way that makes what an earlier
-- version saved stop being a decision of the player's. Without this, switching
-- the marks off by default would not have switched anything off on the only
-- client that matters: the one that already has `on = 1` saved from yesterday.
local CFG_VERSION = 2


-- The chosen look. It is saved because the server loses it on disconnect: the
-- addon is where the per-character settings already persist, so it is the
-- addon that reminds the server of it every session.
--
-- THE FACTORY VALUES ARE THE ONES CHOSEN BY LOOKING AT THEM IN GAME: "Shield
-- of the Blue" (45848) at a tenth of its original size. They are here as a
-- STARTING POINT, not as a constant: the tool still walks the whole list.
--
-- OFF BY DEFAULT SINCE 2026-08-23, and the reason is the ANIMATION.
--
-- With `obj 0.1` the resting size was the good one, but on appearing the mark
-- let out an enormous burst. That is the spell's visual being born: every
-- persistent visual brings its own entry animation, and that animation lives
-- in the client, in the spell's kit. The server decides WHERE, WHICH and HOW
-- BIG -- radius and scale -- but it cannot tell the client to skip an
-- animation, nor to start it halfway through, nor to shorten it. There is no
-- field for that.
--
-- So the only thing left was to hunt among the 572 visuals for one that was
-- born still, and that is a blind hunt of the kind this project has already
-- paid for several times. With the route rings doing their job, it is not
-- worth it: it gets switched off and the tool stays whole for whenever anyone
-- wants to go back and look. `/rts mark on` turns them on.
M.cfg = {
	on    = 0,     -- 0 = no markers in the world (just the ring and the number)
	spell = 45848, -- 0 = the first one on the server's list
	size  = 0,     -- radius in yards; 0 = automatic (1/10 of the spell's size)
	obj   = 0.1,   -- scale of the MODEL: 0.1 is the good measure, seen in game
	mode  = 0,     -- 0 we send the size, 1 the client decides it
}

-- TWO SIZE CONTROLS BECAUSE ONE IS NOT ENOUGH, AND IT IS NOT INDECISION.
--
-- `size` is DYNAMICOBJECT_RADIUS, which is a REQUEST: the client decides
-- whether whichever ground visual it is stretches with that radius, and for
-- the one that does not, everything we send is stored, answered and ignored --
-- which on screen reads as "the control does nothing" and it is not that.
-- `obj` is OBJECT_FIELD_SCALE_X, the model scale, the same field that makes a
-- creature big or small: another field and another path, so a visual deaf to
-- one may answer the other. Which one each visual listens to is a matter of
-- looking at it, not of reasoning about it.

-- The last thing the server said. It is shown exactly as it came: it is the
-- only honest source of where in the list we are.
M.at = { index = 0, total = 0, spell = 0, size = 0, mode = 0, placed = 0,
         own = 0, obj = 1, name = "?" }

local placed = {}      -- [slot] = true, what we believe is placed
local TEST_SLOT = 9999 -- out of the reach of any real route

local function Server()
	return ns.Orders and ns.Orders:HasServer()
end

local function Send(body)
	if Server() then ns.SendServer(body) end
end

--- The look ----------------------------------------------------------------

-- Reminding the server of what we have saved. Called on entering RTS mode and
-- when the server answers for the first time.
function M:Apply()
	if not Server() then return end
	if self.cfg.spell and self.cfg.spell > 0 then
		Send(("MARKSET spell %d"):format(self.cfg.spell))
	end
	-- The order matters: the spell first, because the automatic size derives
	-- from IT. The other way round it would derive from the previous spell.
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

--- Placing -----------------------------------------------------------------

-- What has to be seen, against what we believe is placed. Only the difference
-- is sent: one addon message per marker per round would be far more traffic
-- than is needed, and on top of that the server would have to redo objects
-- that are already right.
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

-- The server forgets everything on disconnect or on changing map (the core
-- throws away all of the player's dynobjects), so our idea of what is placed
-- has to be forgotten too -- otherwise `Sync` would never send anything again
-- because it believes they are already there.
function M:Forget()
	placed = {}
end

-- A point that has MOVED after its mark was placed. The server fixes the
-- position when it creates the object and does not move it by itself, so that
-- mark has to be forgotten for the next `Sync` to put it back in the right
-- place.
function M:Redo(slot)
	if slot then placed[slot] = nil end
end

--- The server's answers ----------------------------------------------------

function M:OnAt(index, total, spell, size, mode, count, own, obj, name)
	self.at = {
		index = index, total = total, spell = spell,
		size = size, mode = mode, placed = count, own = own,
		obj = obj or 1, name = name,
	}
	-- Whatever the server says is what gets saved: if a spell that does not
	-- exist was asked for, what was saved would be a lie that survives the
	-- restart.
	--
	-- The SIZE is not: the server reports the effective one, and saving it
	-- would turn the automatic into a fixed number the moment the state was
	-- asked for once -- and then changing spell would leave the previous one's
	-- size behind.
	self.cfg.spell, self.cfg.mode = spell, mode
	self.cfg.obj = self.at.obj
	Save()
end

function M:Report()
	local a = self.at
	ns.Print(("marks: %s   |cffffff00%s|r (id %d)   %d/%d of the list")
		:format(self.cfg.on == 1 and "|cff00ff00ON|r" or "|cffff0000OFF|r",
			a.name, a.spell, a.index + 1, a.total))
	ns.Print(("  radius |cffffff00%.2f|r of the spell's %.2f (x%.2f)   " ..
		"model scale |cffffff00x%.2f|r   placed |cffffff00%d|r")
		:format(a.size, a.own, a.own > 0 and (a.size / a.own) or 0, a.obj or 1,
			a.placed))
	ns.Print(("  mode |cffffff00%d|r%s")
		:format(a.mode,
			a.mode == 1 and " |cffff8800-- the client decides the radius of " ..
				"nearly every ground patch and ignores ours|r"
			             or " -- the client uses our radius"))
	if not Server() then
		ns.Print("|cffff0000mod-rts is not answering|r: with no server there are " ..
			"no markers in the world, only the number.")
	end
	ns.Print("|cffffff00/rts mark next|prev|r walks the list, " ..
		"|cffffff00find <text>|r searches, |cffffff00<id>|r goes straight there.")
	ns.Print("|cffffff00/rts mark size <yards>|r or |cffffff00scale <fraction>|r  " ..
		"|cffffff00mode 0|1|r  |cffffff00test|r puts one where you point  " ..
		"|cffffff00list|r the list.")
	-- IF THE SIZE DOES NOT MOVE, IT MEANS THE VISUAL IS NOT LISTENING TO THE
	-- RADIUS. The other control scales the model and does not go through that
	-- decision of the client's.
	ns.Print("|cffffff00/rts mark obj <n>|r scales the MODEL (0.5 = half). " ..
		"It is the size control that does not depend on the visual.")
	-- And the ring with the number you see at each point of the route is NOT
	-- this: it is projected interface, with its own control. Two things on top
	-- of the same spot.
	ns.Print("|cff888888The ring with each point's number is interface, not this " ..
		"mark: its size is |cffffff00/rts route ring <yards>|r|cff888888.|r")
end

-- One page of the list. It arrives in pieces and each piece says where it
-- starts from, so it does not depend on them arriving in order.
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

--- The control -------------------------------------------------------------

function M:Command(args)
	local sub, value = (args or ""):match("^(%S*)%s*(.*)$")
	sub = (sub or ""):lower()

	if sub == "" then
		-- With no arguments the server answers the state and `OnAt` prints it.
		if Server() then Send("MARKSET") else self:Report() end
		return
	end

	if sub == "on" or sub == "off" then
		self.cfg.on = (sub == "on") and 1 or 0
		Save()
		if self.cfg.on == 0 then self:ClearAll() end
		ns.Print("markers in the world: " ..
			(self.cfg.on == 1 and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		return
	end

	if not Server() then
		ns.Print("|cffff0000mod-rts is not answering|r: the marker setting lives " ..
			"on the server.")
		return
	end

	if sub == "next" or sub == "prev" then
		Send(("MARKSET %s %s"):format(sub, value ~= "" and value or "1"))
	elseif sub == "size" then
		Send(("MARKSET size %s"):format(value))
	elseif sub == "scale" or sub == "escala" then
		-- The size as a FRACTION of the original, which is how it really gets
		-- asked for: "a tenth of what it measures" instead of a number of yards
		-- that only means something if you already know what it measured.
		Send(("MARKSET scale %s"):format(value))
	elseif sub == "obj" or sub == "objeto" or sub == "modelo" then
		Send(("MARKSET obj %s"):format(value))
	elseif sub == "mode" then
		Send(("MARKSET mode %s"):format(value))
	elseif sub == "find" then
		Send(("MARKSET find %s"):format(value))
	elseif sub == "list" then
		local from = tonumber(value) or 0
		ns.Print(("list of visuals, from %d on:"):format(from + 1))
		Send(("MARKQ %d 20"):format(from))
	elseif sub == "test" then
		if value:lower() == "off" then
			Send(("MARKOFF %d"):format(TEST_SLOT))
			placed[TEST_SLOT] = nil
			return
		end
		local x, y, z = ns.Markers and ns.Markers:CursorGroundPoint()
		if not x then
			ns.Print("I do not know where the mouse is pointing (rts_core and RTS mode are needed).")
			return
		end
		Send(("MARK %d %.2f %.2f %.2f"):format(TEST_SLOT, x, y, z))
		placed[TEST_SLOT] = true
		ns.Print("test mark placed. |cffffff00/rts mark test off|r takes it away.")
	elseif tonumber(sub) then
		Send(("MARKSET spell %d"):format(tonumber(sub)))
	else
		self:Report()
	end
end

--- Cycle -------------------------------------------------------------------

function M:Create()
	-- THE FOUR MARK VERBS. They lived in `Camera.lua` until 2026-09-02. The
	-- server answers the WHOLE state after every change, so the addon never has
	-- to assume its request went through.
	ns.Link:On("MARKAT", function(rest)
		local mi, mt, msp, msz, mmo, mc, mow, mob, mn =
			rest:match("^(%d+) (%d+) (%d+) ([%d%.]+) (%d+) (%d+) ([%d%.]+) ([%d%.]+) (.*)$")
		if not mi then return end
		M:OnAt(tonumber(mi), tonumber(mt), tonumber(msp),
			tonumber(msz) or 0, tonumber(mmo) or 0, tonumber(mc) or 0,
			tonumber(mow) or 0, tonumber(mob) or 1, mn)
		M:Report()
	end)

	-- `MARKQ` is said in both directions: the request goes on its own and the
	-- answer brings three fields. Validating the format is what discards our
	-- own echo.
	ns.Link:On("MARKQ", function(rest)
		local qt, qf, qp = rest:match("^(%d+) (%d+) (.+)$")
		if qt then M:OnList(tonumber(qt), tonumber(qf), qp) end
	end)

	ns.Link:On("MARKERR", function(rest)
		local n = rest:match("^(%d+)$")
		if n then ns.Print("|cffff0000Could not place mark " .. n .. ".|r") end
	end)

	ns.Link:On("MARKNO", function(rest)
		ns.Print("|cffffff00No visual is called|r " .. rest)
	end)

	-- THE CORE THROWS AWAY ALL OF THE PLAYER'S DYNOBJECTS ON A MAP CHANGE, so
	-- the route markers no longer exist. Without forgetting it here, `M:Sync`
	-- would believe they are still placed and would never send them again.
	--
	-- This event was listened to by the channel frame in `Camera.lua`, which
	-- was the one place where `Marks` had nothing to do. Now it is its own.
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
			ns.Print("ground marks switched off (|cffffff00/rts mark on|r brings them back).")
		end
	end
	-- Clamped ON READING and not only on writing: an old set of SavedVariables
	-- outlives the version that wrote it, and a size of 688 saved by an earlier
	-- version is not fixed by any `Set*` -- those only run when the player
	-- types.
	-- 0 is a VALID value here: it means automatic. Clamping it from above yes,
	-- because a 688 saved by an earlier version is not an intention.
	if self.cfg.size < 0 or self.cfg.size > 200 then self.cfg.size = 0 end
	if self.cfg.obj <= 0 or self.cfg.obj > 20 then self.cfg.obj = 1 end
	if self.cfg.mode ~= 1 then self.cfg.mode = 0 end
	if self.cfg.on ~= 0 then self.cfg.on = 1 end
end
