--[[
	Selection.lua -- who is currently under command.

	Selection is stored as a list of NAMES, not unit tokens. Tokens ("party2")
	shuffle whenever the group changes, and every order we send is addressed by
	name anyway (whisper), so names are the stable identity.

	Anything that changes selection fires ns.Selection:Notify(), which the UI
	layers subscribe to. No UI code reaches into this table directly.
]]

local ADDON, ns = ...

local S = {}
ns.Selection = S

S.selected = {}      -- array of names, ordered
S.listeners = {}

-- THE PRIMARY: WHOSE SKILL BAR THIS IS, which is NOT the same thing as who the
-- orders go to.
--
-- From the video: *"if we hit tab, we get the command bar for the next person in
-- the group WITHOUT DESELECTING"*. Those are two concepts and until now there
-- was only one here: the selection decided both, so looking at the mage's skills
-- meant giving up commanding the group.
--
-- Separating them is what makes the real RTS gesture possible: the whole group
-- held and attacking, and you leafing through each one's skills with Tab to cast
-- ONE particular thing without letting go of anybody.
--
-- The consistency rule, and it is the only delicate part: **selecting ONE makes
-- them primary**. Otherwise clicking a bot would show somebody else's skills,
-- which reads as the bar being broken. Selecting SEVERAL does not touch the
-- primary: there the player has said nothing about who interests them.
S.primary = nil

--- Roster ------------------------------------------------------------------

-- Every commandable group member (everyone but you). On a solo/bot server this
-- is exactly the bot party.
function S:GetRoster()
	local roster = {}
	local raid = GetNumRaidMembers()

	if raid > 0 then
		for i = 1, raid do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then
				local n = UnitName(unit)
				ns.NoteClass(n, unit)
				tinsert(roster, { name = n, unit = unit })
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local unit = "party" .. i
			if UnitExists(unit) then
				-- EVERY PARTY MEMBER'S CLASS IS NOTED IN PASSING. It is what
				-- makes YOURS knowable after a character swap: whoever you
				-- are now was here a second ago, and for a `partyN` the
				-- client does look at the object. See `ns.MyClass`.
				local n = UnitName(unit)
				ns.NoteClass(n, unit)
				tinsert(roster, { name = n, unit = unit })
			end
		end
	end

	return roster
end

-- The roster INCLUDING your own character, which in RTS mode is a unit like
-- any other -- selectable, orderable, commandable. You go last so the bots keep
-- the slot numbers your fingers already know.
--
-- Kept separate from GetRoster because that one means "everyone I command by
-- whispering", and whispering yourself is not a thing. The unit bar and the
-- mouse handler want this list; the order dispatcher wants the other.
function S:GetRosterWithPlayer()
	local roster = self:GetRoster()
	tinsert(roster, { name = ns.MyName(), unit = "player", isPlayer = true })
	return roster
end

-- THE SAME LIST WITH THE HERO FIRST, which is what §3/§6 of the brief asks for:
-- *"the active hero is always the first item in the list"*.
--
-- It does not replace `GetRosterWithPlayer`, which leaves the player LAST on
-- purpose -- there the order is fixed by the control-group keys your fingers
-- have already learnt, and changing it would shift the bots along by one. This
-- one is for DRAWING, where what matters is that the hero reads first.
--
-- And "the hero" is whoever you are NOW, not who you logged in as: after a
-- character swap the first in the list is the new one. `ns.MyName()` is the only
-- place that answers that correctly -- `UnitName("player")` comes out of a
-- buffer that only the character-selection screen fills in, and it keeps the
-- session's name forever.
function S:GetRosterHeroFirst()
	local out = { { name = ns.MyName(), unit = "player", isPlayer = true } }
	for _, m in ipairs(self:GetRoster()) do
		tinsert(out, m)
	end
	return out
end

-- name -> unit token, or nil if they left the group.
-- In RTS mode your own character is selectable, so the player matches too.
--
-- THE GROUP IS LOOKED AT FIRST, AND THE ORDER IS THE FIX. It used to compare
-- against `ns.MyName()` before anything else, and that turns any name collision
-- into "that one is you". After a character swap there is a party member called
-- what you used to be called -- it is literally the hero you have just left,
-- back as a bot -- so clicking THAT bot resolved to `player`.
--
-- The symptom looked nothing like the cause: you selected the bot and ended up
-- with both of you selected, and the Control button said "select a party member
-- first" about someone who was one. With the group first, a name that is in the
-- group resolves to its group unit, which is the only thing it can be.
function S:UnitFor(name)
	for _, m in ipairs(self:GetRoster()) do
		if m.name == name then return m.unit end
	end
	if name == ns.MyName() then return "player" end
	return nil
end

--- Queries -----------------------------------------------------------------

function S:Get()
	return self.selected
end

function S:Count()
	return #self.selected
end

function S:IsEmpty()
	return #self.selected == 0
end

function S:IsSelected(name)
	for _, n in ipairs(self.selected) do
		if n == name then return true end
	end
	return false
end

-- The single selected unit, or nil when 0 or many are selected.
-- The command card uses this to decide whether to show per-unit detail.
function S:Single()
	if #self.selected == 1 then return self.selected[1] end
	return nil
end

--- Mutation ----------------------------------------------------------------

function S:Set(names)
	self.selected = {}
	for _, n in ipairs(names or {}) do
		tinsert(self.selected, n)
	end
	-- Just one: that one becomes the primary. Several or none: the primary stays
	-- as it was, unless it is no longer in the group (`Prune` checks that).
	if #self.selected == 1 then
		self.primary = self.selected[1]
	end
	self:Notify()
end

--- The primary -------------------------------------------------------------

function S:GetPrimary()
	-- With no primary chosen, yours. It is what keeps the skill row from ever
	-- being empty the moment you walk in.
	if self.primary then return self.primary end
	return ns.MyName()
end

-- NO CALLER SINCE 0.77.0, and said here so nobody goes looking for one.
--
-- The only gesture that used it was the right-click on a group row, and
-- `PRUEBAS-23` A5 ordered that removed. The primary sets itself, in `Set`, when
-- there is exactly one unit selected.
--
-- It stays because it is inert: a `set` nobody calls cannot arm itself, which is
-- the difference with the camera height hold -- that one had its switch SAVED in
-- the SavedVariables and turned itself back on.
function S:SetPrimary(name)
	if not name or self.primary == name then return end
	self.primary = name
	self:Notify()
end


function S:SelectOnly(name)
	self:Set({ name })
end

function S:Add(name)
	if not self:IsSelected(name) then
		tinsert(self.selected, name)
		self:Notify()
	end
end

function S:Remove(name)
	for i, n in ipairs(self.selected) do
		if n == name then
			tremove(self.selected, i)
			self:Notify()
			return
		end
	end
end

function S:Toggle(name)
	if self:IsSelected(name) then self:Remove(name) else self:Add(name) end
end

--- The select gesture, in one place -----------------------------------------
--
-- Click = that one only, shift or ctrl = add, DOUBLE CLICK = all of them. Used
-- by the group rows, the hero portrait and its bars, which is to say every
-- place in the console where a unit can be clicked.
--
-- IT IS HERE AND NOT IN EACH PANEL because otherwise the double-click window
-- would belong to each panel separately: clicking a bot in its row and then the
-- hero portrait would count as a double click in two different places at once.
-- With a single clock and a single name, two clicks are only a double click if
-- they are on THE SAME unit, which is what anybody expects.
--
-- WoW gives no double-click event on these frames, so it is measured by hand.
-- The window is the same one the world uses in RTSMode.lua, a little under
-- Windows' half second so two orders in a row are not confused for one.
local DOUBLE_CLICK = 0.40
local lastName, lastAt

function S:Click(name)
	if not name then return end

	if IsShiftKeyDown() or IsControlKeyDown() then
		self:Toggle(name)
		lastName, lastAt = name, GetTime()
		return
	end

	local now = GetTime()
	if lastName == name and lastAt and (now - lastAt) < DOUBLE_CLICK then
		self:SelectAll()
		lastName, lastAt = nil, nil     -- so a triple click does not reopen it
		return
	end

	self:SelectOnly(name)
	lastName, lastAt = name, now
end

function S:Clear()
	if #self.selected > 0 then
		self.selected = {}
		self:Notify()
	end
end

function S:SelectAll()
	local names = {}
	for _, m in ipairs(self:GetRosterWithPlayer()) do
		tinsert(names, m.name)
	end
	self:Set(names)
end

-- Drop anyone who has left the group. Called on roster events.
-- YOU ARE SOMEBODY ELSE. Called on entering the world, which with character
-- swapping no longer only means "I have just logged in".
--
-- `Prune` is no use for this and that is why this one is needed: `Prune` drops
-- whatever is no longer in the group, and after a swap **what is selected IS
-- there** -- it is precisely the party member you just jumped into, who is now
-- you. The selection survived intact and the symptom looked nothing like the
-- cause:
--
--   * you selected Avy to jump into him; on arrival, `selected` was still
--     {Avy}, that is to say YOURSELF. Clicking Neferite then left two selected
--     -- "it selects us both" -- with nothing to explain it.
--   * and with two selected the Control button uses the PRIMARY, which was Avy,
--     who is now you: "select a party member first". Which is to say that
--     **jumping into a character stopped you coming back to him**, which reads
--     as that character being forbidden and not as a stale selection.
--
-- A name is not enough to identify anything here: the only safe question is
-- whether the character the session has now is the same one as before.
function S:IdentityChanged()
	-- BY GUID AND NOT BY NAME. The name is the first thing to stop believing
	-- here: it is what may be telling the old version of the story, and on top
	-- of that it can be shared with a party member. The guid comes out of the
	-- client's object manager, which is the same field `UPDATEFLAG_SELF` writes
	-- -- that is to say, the definition of who you are playing.
	local me = UnitGUID("player")
	if not me or self.owner == me then return end

	self.owner = me
	self.selected = {}
	self.primary = nil
	self:Notify()
end

function S:Prune()
	local roster, keep, changed = self:GetRosterWithPlayer(), {}, false
	local present = {}
	for _, m in ipairs(roster) do present[m.name] = true end

	for _, n in ipairs(self.selected) do
		if present[n] then tinsert(keep, n) else changed = true end
	end

	-- The primary goes too if it left the group. Without this, the skill row
	-- would go on showing those of a bot that is no longer there, and its
	-- buttons would send orders the server rejects in silence.
	if self.primary and not present[self.primary] then
		self.primary = nil
		changed = true
	end

	if changed then
		self.selected = keep
		self:Notify()
	end
end

--- Control groups ----------------------------------------------------------
-- Persisted per character in RTSCommandDB.groups.

function S:SaveGroup(index)
	if not RTSCommandDB then return end
	RTSCommandDB.groups = RTSCommandDB.groups or {}

	local copy = {}
	for _, n in ipairs(self.selected) do tinsert(copy, n) end
	RTSCommandDB.groups[index] = copy

	ns.Print(("Control group %d set (%d unit%s)."):format(index, #copy, #copy == 1 and "" or "s"))
end

function S:RecallGroup(index)
	if not RTSCommandDB or not RTSCommandDB.groups then return end
	local g = RTSCommandDB.groups[index]
	if not g or #g == 0 then
		ns.Print(("Control group %d is empty."):format(index))
		return
	end

	-- Only recall members still present. Your own character counts, so a group
	-- saved with you in it comes back with you in it.
	local present, names = {}, {}
	for _, m in ipairs(self:GetRosterWithPlayer()) do present[m.name] = true end
	for _, n in ipairs(g) do
		if present[n] then tinsert(names, n) end
	end

	self:Set(names)
end

--- Change notification -----------------------------------------------------

function S:Subscribe(fn)
	tinsert(self.listeners, fn)
end

function S:Notify()
	for _, fn in ipairs(self.listeners) do
		local ok, err = pcall(fn)
		if not ok then ns.Print("UI error: " .. tostring(err)) end
	end
end
