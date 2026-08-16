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
				tinsert(roster, { name = UnitName(unit), unit = unit })
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local unit = "party" .. i
			if UnitExists(unit) then
				tinsert(roster, { name = UnitName(unit), unit = unit })
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
	tinsert(roster, { name = UnitName("player"), unit = "player", isPlayer = true })
	return roster
end

-- name -> unit token, or nil if they left the group.
-- In RTS mode your own character is selectable, so match the player too.
function S:UnitFor(name)
	if name == UnitName("player") then return "player" end
	for _, m in ipairs(self:GetRoster()) do
		if m.name == name then return m.unit end
	end
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
function S:Prune()
	local roster, keep, changed = self:GetRosterWithPlayer(), {}, false
	local present = {}
	for _, m in ipairs(roster) do present[m.name] = true end

	for _, n in ipairs(self.selected) do
		if present[n] then tinsert(keep, n) else changed = true end
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
