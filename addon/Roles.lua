--[[
	Roles.lua -- the role of each character, under its slots.

	  Bob
	  [1][2][3][4][5][6][7][8][9][0]
	  [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]
	  [    TANK    ]

	One word, in the colour of what it says, and CLICKING IT CYCLES: tank ->
	dps -> heal -> tank, going round only the ones that character actually has.
	`Dock` reserves the room in both states; what is drawn in it is here.

	=== WHAT A ROLE IS IN PLAYERBOTS, WHICH DECIDES EVERYTHING ELSE ==========

	It is a COMBAT STRATEGY with a name, not a field you set. Playerbots builds
	the bot's combat engine out of its talent tree when the AI is created
	(`AiFactory::GetPlayerRoles`, which reads the spec tab: a protection warrior
	comes out `tank`, a shadow priest `dps`, a restoration druid `heal`), and
	from then on what says "this bot tanks" is that the strategy called `tank`
	is switched on in its combat engine. The chat command a player would type is
	`co +tank,-dps`; there is no role variable anywhere to read or write.

	THREE THINGS FOLLOW, and all three are visible in this file:

	  1. THE LIST IS ASKED FOR, NEVER ASSUMED. Which of the three a character
	     has depends on its CLASS, and the answer is in playerbots' own class
	     contexts: a warrior offers `tank` and `dps`, a priest `heal` and `dps`,
	     a rogue only `dps`. mod-rts reads that set (`RtsBotApi::Supported`) and
	     answers `ROLES <bot> tank:0,dps:1`. A rogue's row is therefore a
	     rogue's row: it says DPS and there is nothing to cycle to.

	  2. TURNING ONE ON TURNS THE OTHERS OFF, and the SERVER does it, not us
	     (`rts::command::SetRole`). Two stances at once is not a configuration,
	     it is a bug you would spend a fight diagnosing.

	  3. AND THE DRAWING FOLLOWS THE ANSWER, NOT THE REQUEST. A click sends
	     `ROLE <bot> <name> 1` and repaints with the fresh `ROLES` that comes
	     back. Lighting the button up on our own request would hide exactly the
	     case where the request never went out -- the same rule `Cast` follows
	     with "look after".

	=== WHY ONE CLICK AND NOT A MENU ========================================

	Because there are at most three of them and they are mutually exclusive.
	A dropdown to choose one of two (a warrior: tank or dps) is two gestures --
	open, pick -- to say a thing that has a single other value. Cycling says it
	in one, and the list is short enough that you never have to go round twice.

	RIGHT-CLICK GOES BACKWARDS. It costs one line and it is what makes a
	three-way cycle usable when you overshoot; the tooltip says so, because a
	gesture nobody announces is a gesture that does not exist.

	=== THIS IS NOT THE STANCE LABEL THAT WAS DELETED =======================

	On 2026-09-13 a STANCE widget was deleted the same day it was born: it was
	named after a warrior's combat stance -- battle, defensive, berserker --
	and showed this instead, which is a different question. A stance is a SPELL
	and stays one: `/cast Defensive Stance` in a macro for your hero, a spell
	slot for a bot. Nothing here touches that.

	=== YOUR OWN HERO GETS THE SAME ROW, BY ANOTHER ROAD ====================

	He had none at first, and the reason was sound as far as it went: you are
	not driven by playerbots, there is no strategy engine to ask, and the server
	answers `ROLES <you> -`. What it missed is the half that matters -- **in RTS
	mode you cannot change your own stance either**. The action bar is gone, so
	"just cast Defensive Stance" is not available where the decision is made,
	and a hero you command like a unit but cannot put on the front line is the
	one unit in the bar you have no say over.

	AND YOUR HERO CAN BE A BOT. `.playerbots bot self` hangs a playerbots AI on
	your own character, which is what makes him fight on his own in RTS mode --
	rotations, reacting when the group is attacked, the lot. WHEN HE HAS ONE HIS
	ROW IS A BOT'S ROW: mod-rts answers `ROLES <you>` with real roles (`Roles`
	lets you be your own subject) and the click sends `ROLE`, exactly like the
	others. The AI is what picks his rotation, so the AI's role is the true
	answer -- and it changes his stance itself as part of it.

	WITHOUT AN AI THE MECHANISM IS THE OTHER ONE. Then the role is a SPELL --
	the stance or form that puts you in that role -- and the click casts it:

	    Defensive Stance / Bear Form / Blood Presence   -> TANK
	    Battle, Berserker / Cat, Moonkin / Shadowform   -> DPS
	    Tree of Life                                    -> HEAL

	THE CAST GOES THROUGH THE SERVER (`Skills:SelfCast` -> `SELFCAST`), which is
	the same road your spell slots already take and the only one that works:
	`CastSpellByName` is protected, and a secure button would have to have its
	attribute rewritten every time the stance changed -- which is forbidden in
	combat, exactly when you want to switch.

	AND IT IS STILL NOT THE STANCE LABEL OF 2026-09-13. That one wore the word
	STANCE and showed the playerbots role underneath -- two things, one label,
	neither right. Here each half says what it is: the word is the ROLE, the
	tooltip names the spell, and which of the two is running depends on who the
	row belongs to.

	WHAT YOUR CLASS HAS IS ASKED OF THE CLIENT, not assumed: the forms come from
	`GetShapeshiftFormInfo`, the same list the game's own stance bar draws. A
	rogue's Stealth is in there and is not a role, so it is not offered; a
	paladin has no stance at all and gets no row, which is the truth.
]]

local ADDON, ns = ...

local R = {}
ns.Roles = R

R.active = false

--- The three, and how they read ------------------------------------------
--
-- THE ORDER OF THE CYCLE IS THIS LIST, and it is written from the front line
-- backwards -- who takes the hits, who deals them, who puts them back -- so
-- going round it once reads like a sentence instead of like a table.
--
-- `cc` and `passive` are roles to mod-rts as well (it offers five), and they
-- are deliberately NOT in here: they are not exclusive with the other three,
-- so a cycle that included them would sometimes turn a thing on without
-- turning anything off, and the word on the button would stop meaning "this is
-- what this character does in a fight". They stay reachable as what they are:
-- `cc` is part of the class engine, and standing down is Hold.
local CYCLE = { "tank", "dps", "heal" }

local LABEL = { tank = "TANK", dps = "DPS", heal = "HEAL" }

-- COLOUR-CODED, and with the colours the player already has in their eye from
-- the game's own role icons: blue shield, green cross, red sword.
local COLOR = {
	tank = { r = 0.36, g = 0.58, b = 0.96 },
	dps  = { r = 0.92, g = 0.36, b = 0.30 },
	heal = { r = 0.36, g = 0.84, b = 0.44 },
}

-- A character that has roles but none of them switched on. It happens: a
-- paladin with an odd spec comes out of `GetPlayerRoles` with nothing, and a
-- bot left `passive` by hand reads the same way. Grey and a dash, which is the
-- honest answer -- and the click still works, because the first press of a
-- cycle that starts nowhere is what fixes it.
local NONE = { r = 0.55, g = 0.55, b = 0.58 }

--- YOUR OWN HERO ---------------------------------------------------------
--
-- THE SPELLS THAT MEAN A ROLE, BY ID. By id and not by name because the client
-- is Spanish and "Postura defensiva" is not what this file would have to match
-- on an English one; an id is the same number everywhere.
--
-- The list is short because it is only the ones that CHANGE WHAT YOU DO IN A
-- FIGHT. A druid's Travel Form is in the same client list and is not a role, so
-- it is not here -- and being absent is not a bug: a form this table does not
-- know simply is not offered, which is what should happen to Stealth too.
--
-- AND A WRONG NUMBER HERE CANNOT MISFIRE. The id is only ever used to LOOK UP
-- a spell you already have -- the name comes from the client, the id from your
-- own spell list, and this table only decides which role that pairing means. A
-- number that is wrong therefore loses an option; it never casts the wrong
-- thing.
--
-- Checked against the server's own source rather than from memory: 71, 2457 and
-- 2458 in `PlayerbotFactory.cpp:3267-3272` and `SpellInfoCorrections.cpp:4743`,
-- 768/5487/9634/33891 in `SSCHelpers.h:58-61`, 24858 in
-- `DruidShapeshiftActions.h:135`, 48263 in `PlayerbotAI.cpp:62`. The other
-- three (Shadowform and the two dk presences) are not written down anywhere in
-- there -- playerbots casts them by name -- so they are the only ones on trust.
local STANCE_SPELL = {
	[2457]  = "dps",    -- Battle Stance
	[71]    = "tank",   -- Defensive Stance
	[2458]  = "dps",    -- Berserker Stance
	[5487]  = "tank",   -- Bear Form
	[9634]  = "tank",   -- Dire Bear Form
	[768]   = "dps",    -- Cat Form
	[24858] = "dps",    -- Moonkin Form
	[33891] = "heal",   -- Tree of Life
	[15473] = "dps",    -- Shadowform
	[48266] = "tank",   -- Blood Presence
	[48263] = "dps",    -- Frost Presence
	[48265] = "dps",    -- Unholy Presence
}

-- role -> the id we last SAW you in. It is the hero's half of the same
-- capture-and-restore the server does for the bots: a fury warrior lives in
-- Berserker, and going TANK and back has to put him where he was and not in
-- Battle just because Battle comes first in the client's list.
local heroLast = {}

local function IsHero(name)
	return name ~= nil and name == ns.MyName()
end

-- Declared up here because both roads need it and the hero's road has to be
-- able to ask "did the server answer with roles for me?".
local who = {}

local ROLE_SET = { tank = true, dps = true, heal = true }

-- YOUR HERO CAN BE A BOT, AND THEN HE IS ONE. `.playerbots bot self` hangs a
-- playerbots AI on your own character -- the same AI the others have, with the
-- same combat engine -- and from that moment the honest answer to "what is his
-- role" is the AI's, not his stance: the AI is what picks his rotation, and it
-- switches his stance itself as part of it.
--
-- So the two roads are not a choice this file makes, they are a question it
-- asks: mod-rts answers `ROLES <you>` with real roles when you have an AI
-- (`RoleSubject` lets you be your own subject) and with nothing when you do
-- not. With roles -> the bot road, and the click sends `ROLE`. Without ->
-- the stance road below, and the click casts.
local function HeroByAI(name)
	if not IsHero(name) then return false end
	local e = who[name]
	if not (e and e.list) then return false end
	for _, r in ipairs(e.list) do
		if ROLE_SET[r.name] then return true end
	end
	return false
end

-- role -> { id, name, active }. Your stances, crossed with the ids the server
-- knows you have.
--
-- TWO SOURCES AND BOTH ARE NEEDED. The client lists the forms you can take
-- (`GetShapeshiftFormInfo`, what the game's stance bar draws) but gives no
-- spell id; the id is what `SELFCAST` needs, and that comes from your own spell
-- list, which is the one `Skills` already asks the server for. They are joined
-- by the name, which is the same string on both sides -- both are `GetSpellInfo`
-- in the end.
local function HeroStances()
	local out = {}
	local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
	if n == 0 then return out end

	local byName = {}
	for _, s in ipairs(ns.Skills:Available(ns.MyName())) do
		byName[s.name] = s.spellId
	end

	for i = 1, n do
		local _, sname, active = GetShapeshiftFormInfo(i)
		local id = sname and byName[sname]
		local role = id and STANCE_SPELL[id]
		if role then
			if active then heroLast[role] = id end
			local cur = out[role]
			-- The one you are IN beats everything; after that, the one you were
			-- in last time; and failing both, the first the client lists.
			if not cur or active or (heroLast[role] == id and not cur.active) then
				out[role] = { id = id, name = sname, active = active and true or false }
			end
		end
	end

	return out
end

--- What we know ----------------------------------------------------------
--
-- name -> { list = { { name = , active = }, ... }, at = , pending = }
-- (declared further up: the hero road reads it too)

-- HOW OLD AN ANSWER IS ALLOWED TO GET. The roles of a bot can change without
-- us: the player can type `co +tank` at it in chat, and playerbots itself
-- rebuilds the engine when the bot changes spec. Asking again now and then is
-- one short message per character and it is the difference between a row that
-- is right and a row that WAS right.
local STALE = 30

-- And how long an unanswered question waits before it is asked again. Without
-- this a single lost reply leaves that character's row blank for the rest of
-- the session, because `pending` would never come down.
local RETRY = 5

local function Entry(name)
	local e = who[name]
	if not e then
		e = {}
		who[name] = e
	end
	return e
end

function R:Request(name)
	if not name or name == "" then return end
	local e = Entry(name)
	e.pending = true
	e.asked = GetTime()
	-- `WhenServer` and not `HasServer`: mod-rts is only KNOWN to be there from
	-- its first reply, so asking in the first second of the session picks the
	-- "no server" path and reads as if roles did not work at all. Same loop as
	-- everywhere else, written once in `Link`.
	ns.Link:WhenServer(function(ok)
		if not ok then
			-- No mod-rts: nothing can answer this, and an empty list is what
			-- makes the row hide itself instead of waiting forever.
			--
			-- AND IT COUNTS AS AN ANSWER FOR THE CLOCK (`at`), which is not
			-- bookkeeping: `Want` re-asks anything older than `STALE`, and with
			-- `at` left unset that is TRUE THE INSTANT THIS RETURNS -- the
			-- repaint this very call triggers would ask again, and again, for
			-- the whole session. Timed out means timed out for thirty seconds,
			-- after which it is worth one more try in case mod-rts came up.
			e.pending = false
			e.list = e.list or {}
			e.at = GetTime()
			if R.active then R:Refresh() end
			return
		end
		ns.SendServer("ROLES " .. name)
	end)
end

-- The ones on screen right now, asked for at most once each. It is called from
-- the repaint, which runs on every selection change, so it has to be the thing
-- that decides NOT to ask -- otherwise it would ask five times a second.
function R:Want(names)
	local now = GetTime()
	for _, n in ipairs(names or {}) do
		local e = who[n]
		if not e then
			self:Request(n)
		elseif e.pending then
			if now - (e.asked or 0) > RETRY then self:Request(n) end
		elseif now - (e.at or 0) > STALE then
			self:Request(n)
		end
	end
end

--- Reading what we know --------------------------------------------------

-- The roles of that character that are in the cycle, in the cycle's order.
-- Empty means "not a bot", "nothing has answered yet" or "no mod-rts" -- and
-- all three draw the same, which is right: not one of them is something the
-- player can act on.
function R:Stances(name)
	local out = {}

	if IsHero(name) and not HeroByAI(name) then
		local forms = HeroStances()
		for _, s in ipairs(CYCLE) do
			if forms[s] then table.insert(out, s) end
		end
		return out
	end

	local e = who[name or ""]
	if not (e and e.list) then return out end
	for _, s in ipairs(CYCLE) do
		for _, r in ipairs(e.list) do
			if r.name == s then table.insert(out, s) end
		end
	end
	return out
end

-- The one that is ON, or nil.
function R:Current(name)
	if IsHero(name) and not HeroByAI(name) then
		local forms = HeroStances()
		for _, s in ipairs(CYCLE) do
			if forms[s] and forms[s].active then return s end
		end
		return nil
	end

	local e = who[name or ""]
	if not (e and e.list) then return nil end
	for _, r in ipairs(e.list) do
		if r.active and ROLE_SET[r.name] then return r.name end
	end
	return nil
end

-- YOUR HERO HAS JUST CHANGED ROAD -- the AI came or went (`RTSMode`, the AUTO
-- verb) -- so whatever we knew about him is from the other side of it. Thrown
-- away rather than refreshed in place: the answer does not change, the QUESTION
-- does, and a stale list would keep the row on the wrong road for `STALE`
-- seconds, which is most of the time you would spend looking at it.
function R:Recheck()
	local me = ns.MyName and ns.MyName()
	if me then who[me] = nil end
	if self.active then self:Refresh() end
end

function R:Pending(name)
	local e = who[name or ""]
	return (e and e.pending) or false
end

-- WHETHER ANYTHING HAS COME BACK ABOUT THIS ONE, which is not the same question
-- as whether it has roles -- and telling the two apart is the whole point of
-- the waiting state below. `list` is only ever set by an answer (a real one, or
-- the timeout that says nobody is going to answer).
function R:Answered(name)
	-- YOUR OWN HERO IS NOT WAITING ON THE SERVER, he is waiting on his own spell
	-- list -- the one thing here that needs an id. With no forms at all there is
	-- nothing to wait for and the row goes away at once.
	if IsHero(name) and not HeroByAI(name) then
		-- Still on the stance road: he is not waiting on the channel but on his
		-- own spell list, which is where the ids come from. With no forms at all
		-- there is nothing to wait for and the row goes at once.
		local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
		if n == 0 then return true end
		return #ns.Skills:Available(ns.MyName()) > 0
	end

	local e = who[name or ""]
	return (e and e.list) ~= nil
end

-- The SPELL behind a role, for your hero, so the tooltip can name it. A bot has
-- no spell to name: its role is a strategy.
function R:What(name, role)
	if not (IsHero(name) and role) or HeroByAI(name) then return nil end
	local f = HeroStances()[role]
	return f and f.name or nil
end

--- Changing it -----------------------------------------------------------

function R:Cycle(name, back)
	local list = self:Stances(name)
	if #list == 0 then return end

	-- ONE ROLE IS NOT A CYCLE, AND IT SAYS SO. A rogue is dps and there is
	-- nothing else it can be; a click that quietly did nothing would read as a
	-- broken button, and dimming the row is not enough on its own.
	if #list == 1 then
		ns.Print(("|cff888888%s can only be|r %s|cff888888 -- it is the only " ..
			"role its class has.|r"):format(name, LABEL[list[1]] or list[1]))
		return
	end

	if not ns.Link:HasServer() then
		ns.Print("|cffff8800roles:|r mod-rts is needed to change a role.")
		return
	end

	local cur, now = 0, self:Current(name)
	for i, s in ipairs(list) do
		if s == now then cur = i end
	end

	local nxt
	if back then
		nxt = list[((cur - 2) % #list) + 1]
	else
		nxt = list[(cur % #list) + 1]
	end

	-- YOUR HERO CHANGES ROLE BY CASTING, and the row does not light up until the
	-- client says the stance took -- same rule as the bots, and it matters more
	-- here: a cast can be refused (dead, silenced, already switching) and a
	-- button that went blue anyway would be lying about where you are standing.
	if IsHero(name) and not HeroByAI(name) then
		local f = HeroStances()[nxt]
		if not f then return end
		ns.Skills:SelfCast(f.id)
		return
	end

	-- ONLY THE ONE BEING TURNED ON IS SENT. The server drops the other two
	-- itself and answers with the list it ended up with; see the header.
	ns.SendServer("ROLE " .. name .. " " .. nxt .. " 1")
end

--- The widget ------------------------------------------------------------

local mainTag             -- state A: one, under the row of ten
local colTag = {}         -- state B: ci -> one, under each 2x2

local function Tag(parent)
	local b = CreateFrame("Button", nil, parent)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()

	-- ANCHORED LEFT AND RIGHT, NOT GIVEN A WIDTH. A FontString with a width set
	-- does not clip in 3.3.5a: it breaks into a second line that spills out of
	-- the row's height (`SetWordWrap` does not exist here). Held between the two
	-- sides inside a one-line height, what does not fit is cut instead.
	b.label = ns.W:Text(b, ns.W.FONT.mini)
	b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
	b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.label:SetJustifyH("CENTER")

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		if not self.owner then return end
		R:Cycle(self.owner, button == "RightButton")
	end)

	return b
end

local function Place(tag, host, x, y, w, h)
	tag:SetParent(host)
	tag:ClearAllPoints()
	tag:SetPoint("TOPLEFT", host, "TOPLEFT", x, -y)
	tag:SetWidth(w)
	tag:SetHeight(h)
	tag.label:SetHeight(h)
end

local function Paint(tag, name)
	local list = R:Stances(name)
	if #list == 0 then
		tag.owner = nil

		-- NOTHING TO SAY YET IS NOT THE SAME AS NOTHING TO SAY, and drawing
		-- both as an empty strip is how "the roles do not work" and "the roles
		-- have not arrived" came to look identical. Until an answer lands the
		-- row holds a grey ellipsis; once it lands with nothing in it -- your
		-- own hero, someone who left the group -- the row goes away for good.
		if not R:Answered(name) then
			tag.label:SetText("...")
			tag.label:SetTextColor(NONE.r, NONE.g, NONE.b)
			tag.bg:SetTexture(0, 0, 0, 0.45)
			tag:SetAlpha(0.7)
			ns.W:Tip(tag, ("Role of %s"):format(name), "Asking the server...")
			tag:Show()
			return
		end

		tag:Hide()
		return
	end

	tag.owner = name

	local cur = R:Current(name)
	local c = (cur and COLOR[cur]) or NONE
	tag.label:SetText(cur and (LABEL[cur] or cur:upper()) or "--")
	tag.label:SetTextColor(c.r, c.g, c.b)
	-- THE COLOUR IS SAID TWICE: in the word and behind it. The word on its own
	-- is four letters of caption text, which is not enough to read a colour off
	-- at a glance with five columns up -- and reading it at a glance is the
	-- entire reason the row is colour-coded.
	tag.bg:SetTexture(c.r * 0.30, c.g * 0.30, c.b * 0.30, 0.85)

	local turnable = #list > 1
	tag:SetAlpha(turnable and 1 or 0.55)

	local names = {}
	for _, s in ipairs(list) do table.insert(names, LABEL[s] or s) end

	-- THE SPELL, WHEN THERE IS ONE. Your hero's role is a stance, and the row
	-- says TANK while what actually happens is Defensive Stance: naming it is
	-- what keeps the two connected instead of looking like two systems.
	local spell = R:What(name, cur)
	local head = spell and (spell .. "\n") or ""

	if turnable then
		ns.W:Tip(tag, ("Role of %s"):format(name),
			head .. table.concat(names, " > ") .. "\n" ..
			"|cffffff00Click:|r the next one. |cffffff00Right click:|r the one before.")
	else
		ns.W:Tip(tag, ("Role of %s"):format(name),
			head .. "Its class only has this one.")
	end

	tag:Show()
end

--- Laying out ------------------------------------------------------------

function R:Layout()
	if not self.active then return end
	if ns.Dock:State() == "A" then
		self:LayoutA()
	else
		self:LayoutB()
	end
	self:Refresh()
end

function R:LayoutA()
	for _, t in pairs(colTag) do t:Hide() end

	local host = ns.Dock:Host("role")
	if not host then return end

	if not mainTag then mainTag = Tag(host) end

	-- AS WIDE AS A STATE B COLUMN, and not as wide as the ten slots. The row is
	-- one word: stretched across the whole bar it would be a word floating in
	-- the middle of six hundred pixels of nothing, and it would stop reading as
	-- a button. Two slots is the same block that same word occupies when several
	-- are picked, so it lands in the same place either way.
	local w = ns.Dock:SlotSize() * 2 + ns.Dock:Gap()
	local max = host:GetWidth() or w
	if max > 0 and w > max then w = max end

	Place(mainTag, host, 0, 0, w, ns.Dock:RoleHeight())
	mainTag:Show()
end

function R:LayoutB()
	if mainTag then mainTag:Hide() end

	local cols = ns.Dock:Columns()
	local cell = ns.Dock:RoleCell()
	if not cell then return end

	for ci = 1, #cols do
		local host = ns.Dock:Host("col" .. ci)
		if host then
			local t = colTag[ci]
			if not t then
				t = Tag(host)
				colTag[ci] = t
			end
			Place(t, host, cell.x, cell.y, cell.w, cell.h)
			t:Show()
		end
	end

	-- The columns left over from a wider selection. Walked with `pairs` and not
	-- up to `#colTag`, for the reason `Cast` writes out in full: the table is
	-- filled by index and a drop from five to two leaves holes that `#` stops
	-- short of.
	for ci, t in pairs(colTag) do
		if ci > #cols then t:Hide() end
	end
end

--- Repainting ------------------------------------------------------------

function R:Refresh()
	if not self.active then return end

	if ns.Dock:State() == "A" then
		local owner = ns.Dock:Subject()
		if not owner then return end
		self:Want({ owner })
		if mainTag then Paint(mainTag, owner) end
		return
	end

	local names = {}
	for ci, m in ipairs(ns.Dock:Columns()) do
		table.insert(names, m.name)
		local t = colTag[ci]
		if t then Paint(t, m.name) end
	end
	self:Want(names)
end

--- Entering and leaving --------------------------------------------------

function R:Enter()
	self.active = true

	if not self.wired then
		self.wired = true
		ns.Dock:OnLayout(function() R:Layout() end)
		ns.Selection:Subscribe(function() R:Refresh() end)

		-- YOUR OWN STANCE CHANGES WITHOUT US: a macro, the stance bar before
		-- entering RTS mode, or the cast we just asked the server for, which
		-- lands a moment later. `UPDATE_SHAPESHIFT_FORM` is what the game's own
		-- stance bar listens to, and the second event is for learning one.
		--
		-- AND THE SPELL LIST TOO (`Skills:Subscribe`): the id only exists once
		-- the server has answered, so without this the hero's row would sit on
		-- its ellipsis until something else happened to repaint it.
		local ev = CreateFrame("Frame", "RTSRolesEvents")
		ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		ev:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
		ev:SetScript("OnEvent", function()
			if R.active then R:Refresh() end
		end)
		ns.Skills:Subscribe(function() R:Refresh() end)

		-- WE HEAR OUR OWN QUESTION COME BACK -- the channel whispers to itself
		-- -- so the handler has to tell the two directions apart by shape. The
		-- question is `ROLES <bot>` and the answer `ROLES <bot> <list>`: two
		-- fields against one. Without this, our own request would be read as an
		-- answer with no roles in it and wipe the row we just asked about.
		ns.Link:On("ROLES", function(rest)
			local name, list = rest:match("^(%S+)%s+(%S+)$")
			if not name then return end

			local e = Entry(name)
			e.list = {}
			e.pending = false
			e.at = GetTime()
			if list ~= "-" then
				for role, on in list:gmatch("(%a+):([01])") do
					table.insert(e.list, { name = role, active = on == "1" })
				end
			end
			R:Refresh()
		end)
	end

	self:Layout()
end

function R:Leave()
	self.active = false
	if mainTag then mainTag:Hide() end
	for _, t in pairs(colTag) do t:Hide() end
end

-- `/rts roles`. It is a DIAGNOSTIC and not a listing, and it is written that
-- way on purpose: when the row does not draw, the question is never "which
-- roles does this bot have" -- it is WHICH OF THE FOUR LINKS IS BROKEN. So it
-- says all four, in the order they run, and then asks again so that running it
-- twice shows whether the answer comes back at all.
function R:Report()
	ns.Print(("|cffffff00roles|r -- the row is %s, dock state |cff33ccff%s|r"):format(
		self.active and "|cff00ff00up|r" or "|cffff8800down|r (enter RTS mode first)",
		self.active and ns.Dock:State() or "-"))

	if ns.Link:HasServer() then
		ns.Print(("  channel: |cff00ff00mod-rts %s|r"):format(
			tostring(ns.Link.serverVersion or "?")))
	else
		ns.Print("  channel: |cffff8800nothing has answered yet|r -- with no mod-rts " ..
			"there are no roles to ask for.")
	end

	local tag = (ns.Dock:State() == "A") and mainTag or colTag[1]
	if not tag then
		ns.Print("  the label: |cffff8800not built|r -- `Layout` has not run.")
	else
		ns.Print(("  the label: %s, %dx%d at %s"):format(
			tag:IsShown() and "|cff00ff00shown|r" or "|cff888888hidden (nothing to say)|r",
			math.floor(tag:GetWidth() or 0), math.floor(tag:GetHeight() or 0),
			tostring(tag.owner or "nobody")))
	end

	local names = {}
	if not self.active or ns.Dock:State() == "A" then
		table.insert(names, ns.Dock:Subject())
	else
		for _, m in ipairs(ns.Dock:Columns()) do table.insert(names, m.name) end
	end

	for _, n in ipairs(names) do
		local e = who[n]
		if IsHero(n) and not HeroByAI(n) then
			-- YOUR OWN LINE READS OFF THE CLIENT, not off the channel, so it
			-- prints the stances and the spell behind each one -- which is the
			-- only place the two halves of this row can be seen side by side.
			local forms = HeroStances()
			local parts = {}
			for _, s in ipairs(CYCLE) do
				local f = forms[s]
				if f then
					table.insert(parts, (f.active and "|cff00ff00" or "|cff666666")
						.. s .. " (" .. f.name .. ")|r")
				end
			end
			if #parts == 0 then
				ns.Print(("  |cff33ccff%s|r: |cff888888you, and no stance that " ..
					"means a role -- %d forms in the client.|r"):format(n,
					GetNumShapeshiftForms and GetNumShapeshiftForms() or 0))
			else
				ns.Print(("  |cff33ccff%s|r (you): %s"):format(n, table.concat(parts, " ")))
			end
		elseif not e or not e.list then
			ns.Print(("  |cff33ccff%s|r: |cff888888no answer yet|r"):format(n))
		elseif #e.list == 0 then
			ns.Print(("  |cff33ccff%s|r: |cff888888answered with nothing -- not a " ..
				"playerbot, or out of your group.|r"):format(n))
		else
			local parts = {}
			for _, r in ipairs(e.list) do
				table.insert(parts, (r.active and "|cff00ff00" or "|cff666666")
					.. r.name .. "|r")
			end
			ns.Print(("  |cff33ccff%s|r: %s"):format(n, table.concat(parts, " ")))
		end
	end

	-- AND ASKED AGAIN, ignoring the cache. Running it twice is the test: if the
	-- second run still says "no answer yet", nothing is coming back and the
	-- problem is behind the channel, not in the drawing.
	for _, n in ipairs(names) do self:Request(n) end
	ns.Print("|cff888888Asked again. Run it once more: if it still says no answer, " ..
		"turn on |cffffff00/rts debug|cff888888 and look for a line starting with ROLES.|r")
end

ns.Dock:Register(R)
