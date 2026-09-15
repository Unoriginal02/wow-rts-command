--[[
	Cast.lua -- the spell slots on the bottom bar.

	It is the contents of the LEFT half of the `Dock`, and it draws the two
	states the Dock decides on:

	  A  none or one     the name and TEN slots
	  B  two or more     per column: name and a 2x2 of FOUR

	The data and the actions are not here: `Skills.lua` has them. What is here
	is the DRAWING and the GESTURE. In state B there are up to five columns
	asking for the same thing at once, and with the logic inside the panel that
	would be five copies of everything.

	=== THE MACROS LEFT THIS FILE =============================================

	Until 2026-09-13 this file also drew four macro bars per character, with a
	catalogue of twelve actions WRITTEN INTO THE CODE (`stay`, `follow`,
	`max dps`...). They went away whole: the orders to the bots are now real
	game macros, in the tray on the right (`Tray.lua`), and the catalogue that
	creates them is the one in `Macros.lua`, which already existed.

	The only thing that survived from that catalogue is LOOK AFTER (`PFOCUS`),
	and not out of nostalgia: it is the only one of the twelve that does not fit
	in a macro, because it needs a second click to choose who for. It lives here
	as a gesture and it is fired from `/rts focus`, which DOES fit in a macro.

	=== THE FOUR OF STATE B ARE NOT THE FIRST FOUR OF THE TEN =================

	They are another set (`Skills`: "group"). The reason is in `Dock.lua`.

	=== THE GESTURE OF §5, AND THE CIRCLING LIGHT =============================

	Pressing a slot whose spell needs a target does not send it: it leaves it
	ARMED, and the icon starts spinning with **the hunter pet light**. The next
	click chooses who for -- on a game frame or out in the 3D world, either way.

	THE LIGHT BELONGS TO THE CLIENT AND IS NOT REIMPLEMENTED. Taken from reading
	its FrameXML (`Data\esES\patch-esES.MPQ`, see `CLAUDE.md`), not from memory:

	  * `AutoCastShineTemplate` (UIPanelTemplates.xml:699) is 16 sparkle
	    textures with their `OnLoad`, and it is an ordinary VIRTUAL template.
	  * `AutoCastShine_AutoCastStart(frame, r, g, b)` turns it on and
	    `..._AutoCastStop(frame)` turns it off (UIParent.lua:3477,3494).
	  * **THE ANIMATION COMES FOR FREE**: `UIParent`'s `OnUpdate` moves it.

	AND ONE TRAP: `AutoCastShine_OnLoad` looks its sparkles up by name
	(`_G[name..i]`), so **the frame HAS to have a name**.

	=== SETTING UP A SLOT =====================================================

	RIGHT CLICK opens the spell list of THAT character -- which is its action
	bar, not your book, because your book does not have the mage's Polymorph
	(see `Skills.lua`). "Drag it out of the book" cannot exist for a bot and
	there is no way round it: `PickupSpell` only picks up what you know.
]]

local ADDON, ns = ...

local C = {}
ns.Cast = C

C.active = false

local spellBtn = {}       -- i -> square button (state A)
local colBtn = {}         -- ci -> { head, spells = {} }
local headName
local flyout

--- The names, clipped by length --------------------------------------------
--
-- A name on this client runs to twelve letters, and at size 32 that is a label
-- wider than half a row of slots: the caption weighed more than what is below
-- it, which is what actually gets used. So it gets cut.
--
-- NO ELLIPSIS, on purpose: the three dots give back nearly all the width you
-- just took away, so they would be the same problem written another way. And a
-- cut name is just as recognisable: they are the five in your group, not a list
-- of strangers.
--
-- The state B column is cut shorter than the big caption because it is
-- narrower -- there was already a `SetWidth` there so that a long name would
-- not draw on top of the one next to it, but a `SetWidth` does not clip: IT
-- BREAKS INTO TWO LINES, and the second one spills out of the header's height.
local NAME_A = 10         -- the big caption, above the ten slots
local NAME_B = 8          -- the one on each column

local function Clip(name, max)
	name = tostring(name or "")
	if name:len() <= max then return name end
	local cut = name:sub(1, max)
	-- Do not split a letter down the middle. In UTF-8 the continuation bytes run
	-- from 0x80 to 0xBF and a stray byte is drawn as a black diamond; the
	-- Spanish client allows accents in names, so it can happen.
	while cut ~= "" do
		local b = cut:byte(-1)
		if b < 0x80 or b >= 0xC0 then break end
		cut = cut:sub(1, -2)
	end
	-- And if the last thing left is the START of a multibyte letter, it has to
	-- go too: its tail went with the cut.
	local b = cut:byte(-1)
	if b and b >= 0xC0 then cut = cut:sub(1, -2) end
	return cut
end

--- Focus state -------------------------------------------------------------
--
-- name -> guid, so we can draw who is wearing it. The server says so when it
-- confirms, we do not assume it ourselves: a button that lights up off its own
-- request hides exactly the case where the request never went out.
C.focus = {}

function C:PointAt(name, guid, label)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800look after:|r mod-rts is needed.")
		return
	end
	local hex = guid and (tostring(guid):gsub("^0[xX]", "")) or "-"
	ns.SendServer("PFOCUS " .. name .. " " .. hex)
	if label then
		ns.Print(("|cff33ccff%s|r now looks after |cffffd100%s|r."):format(name, label))
	end
end

function C:ClearFocus(name)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800look after:|r mod-rts is needed.")
		return
	end
	ns.SendServer("PFOCUS " .. name .. " -")
end

-- ARMING THE LOOK AFTER GESTURE. `/rts focus` calls it, which is what the
-- player puts in a macro on the tray.
function C:StartFocus(name)
	name = name or ns.Dock:Subject()
	if not name then return end
	self.pendingFocus = name
	ns.Print(("|cffffd100Look after (%s):|r choose who; right click cancels."):format(name))
	self:Refresh()
end

--- The arming light --------------------------------------------------------

local shineSeq = 0

-- The light spills out of the button on purpose -- the sparkles spin OUTSIDE
-- the icon -- so at 9% per side it does not reach far enough to tread on the
-- neighbour.
local SHINE_SCALE = 1.18
local SHINE_LIFT  = 10

local function Shine(b)
	if b.shine then return b.shine end
	if type(_G.AutoCastShine_AutoCastStart) ~= "function" then return nil end

	shineSeq = shineSeq + 1
	local ok, f = pcall(CreateFrame, "Frame", "RTSShine" .. shineSeq, b,
	                    "AutoCastShineTemplate")
	if not ok or not f then return nil end
	f:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.shine = f
	return f
end

local function SetArmed(b, on)
	local f = Shine(b)
	if not f then return end
	if on then
		-- It gets remeasured and raised again EVERY TIME, not on creation: the
		-- button changes level when it is reparented between state A and state
		-- B, and a level set only once goes stale without raising an error --
		-- the light would go back under the icon and it would look like it
		-- never comes up.
		f:SetWidth(b:GetWidth() * SHINE_SCALE)
		f:SetHeight(b:GetHeight() * SHINE_SCALE)
		f:SetFrameLevel(b:GetFrameLevel() + SHINE_LIFT)
		AutoCastShine_AutoCastStart(f)
	elseif type(_G.AutoCastShine_AutoCastStop) == "function" then
		AutoCastShine_AutoCastStop(f)
	end
end

--- The picker flyout -------------------------------------------------------

local ROW_H = 34
local rows = {}

local function EnsureFlyout()
	if flyout then return flyout end
	flyout = CreateFrame("Frame", "RTSCastPicker", ns.Pixels:Host())
	flyout:SetFrameStrata("DIALOG")
	flyout:EnableMouse(true)
	flyout:Hide()

	local bg = flyout:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(0, 0, 0, 0.92)
	return flyout
end

local function FlyoutRow(i)
	if rows[i] then return rows[i] end
	local b = CreateFrame("Button", nil, flyout)
	b:SetHeight(ROW_H)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(ROW_H - 6)
	b.icon:SetHeight(ROW_H - 6)
	b.icon:SetPoint("LEFT", b, "LEFT", 4, 0)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- A Button with no template brings no FontString, so `SetText` would draw
	-- nothing. It gets made by hand, like everywhere else in the addon.
	b.text = ns.W:Text(b, ns.W.FONT.normal)
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetJustifyH("LEFT")

	rows[i] = b
	return b
end

-- HOW MANY ROWS FIT AT ONCE. The server sends the bot's bar AND everything it
-- knows, which is fifty or a hundred entries depending on the level; without
-- paging, the list would be drawn 3,000 pixels tall and would read as "it does
-- not show up".
local PAGE = 14

-- `entries` = { { icon, text, sub, fn }, ... }
function C:ShowPicker(anchor, entries, page)
	EnsureFlyout()

	page = page or 0
	local total = #entries
	local pages = math.max(1, math.ceil(total / PAGE))
	if page >= pages then page = pages - 1 end
	if page < 0 then page = 0 end

	local from = page * PAGE + 1
	local to   = math.min(total, from + PAGE - 1)

	local shown = {}
	if page > 0 then
		table.insert(shown, {
			icon = "Interface\\Buttons\\UI-MicroStream-Green",
			text = ("|cffffd100... previous|r |cff888888(%d/%d)|r"):format(page, pages),
			keep = true,
			fn = function() C:ShowPicker(anchor, entries, page - 1) end,
		})
	end
	for i = from, to do table.insert(shown, entries[i]) end
	if to < total then
		table.insert(shown, {
			icon = "Interface\\Buttons\\UI-MicroStream-Red",
			text = ("|cffffd100more ... |r|cff888888(%d more, %d/%d)|r"):format(
				total - to, page + 2, pages),
			keep = true,
			fn = function() C:ShowPicker(anchor, entries, page + 1) end,
		})
	end
	entries = shown

	local n = 0
	for i, e in ipairs(entries) do
		local b = FlyoutRow(i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -(6 + (i - 1) * (ROW_H + 2)))
		b:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -(6 + (i - 1) * (ROW_H + 2)))
		b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		b.text:SetText(e.text .. (e.sub and (" |cff888888" .. e.sub .. "|r") or ""))
		b:SetScript("OnClick", function()
			-- A navigation row does NOT close the list: it redraws it on
			-- another page.
			if not e.keep then flyout:Hide() end
			local ok, err = pcall(e.fn)
			if not ok then ns.Print("|cffff0000dock:|r " .. tostring(err)) end
		end)
		b:Show()
		n = i
	end
	for i = n + 1, #rows do rows[i]:Hide() end

	flyout:SetWidth(440)
	flyout:SetHeight(n * (ROW_H + 2) + 12)
	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 8)
	flyout:Show()
end

function C:HidePicker()
	if flyout then flyout:Hide() end
end

-- A character's spell list, for setting up a slot. `set` says which of the two
-- sets it goes to -- and it is written in the list's header, because "slot 2"
-- means two different things and the player has to know which one they are
-- touching.
function C:PickSpell(anchor, name, i, set)
	local cat = ns.Skills:Available(name)
	if #cat == 0 then
		ns.Print(("|cffff8800%s|r has no spells to offer%s."):format(name,
			ns.Skills:Pending(name) and " yet (asking for them...)" or
			": with the server up to date this should not happen -- |cffffff00/rts skills|r"))
		return
	end

	local entries = {
		{ icon = "Interface\\Icons\\INV_Misc_QuestionMark", text = "|cff888888(empty the slot)|r",
		  fn = function() ns.Skills:SetSlot(name, i, nil, set) end },
	}
	for _, s in ipairs(cat) do
		local info = ns.Skills:TypeInfo(s.type)
		table.insert(entries, {
			icon = s.texture, text = s.name, sub = info.label,
			fn = function() ns.Skills:SetSlot(name, i, s.spellId, set) end,
		})
	end

	self:ShowPicker(anchor, entries)
end

--- The spell buttons -------------------------------------------------------

local function SpellButton(store, i, parent, size, set)
	local b = store[i]
	if not b then
		b = ns.W:Button(parent, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if not self.owner then return end
			if button == "RightButton" then
				C:PickSpell(self, self.owner, self.index, self.set)
				return
			end
			C:HidePicker()
			if self.spell then
				ns.Skills:Use(self.owner, self.index, self.set)
			else
				-- AN EMPTY SLOT DOES NOT KEEP QUIET. A click that does nothing
				-- is indistinguishable from a broken button.
				ns.Print("empty slot: |cffffff00right|r click to give it a spell.")
			end
		end)
		store[i] = b
	end
	b.set = set
	return b
end

local function PlaceSquare(b, parent, c)
	b:SetParent(parent)
	b:SetWidth(c.w)
	b:SetHeight(c.h)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", c.x, -c.y)
	b:Show()
end

local function PaintSpell(b, owner, i, s, aiming, set)
	b.owner, b.index, b.set, b.spell = owner, i, set, s and s.spellId or nil

	if not s then
		b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
		b.icon:SetTexCoord(0, 1, 0, 1)
		b.icon:SetVertexColor(0.35, 0.35, 0.4)
		b.icon:SetAlpha(0.8)
		b.label:SetText("")
		ns.W:Tip(b, "Slot " .. i .. " empty",
			"Right click to choose a spell of " .. owner .. ".")
		SetArmed(b, false)
		return
	end

	b.icon:SetTexture(s.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	-- A SPELL THAT IS NO LONGER ON ITS BAR IS DRAWN DIMMED, not erased. The bot
	-- may not be loaded yet or the reply may not have arrived.
	if s.stale then
		b.icon:SetVertexColor(0.55, 0.4, 0.4)
	else
		b.icon:SetVertexColor(1, 1, 1)
	end

	local info = ns.Skills:TypeInfo(s.type)
	local extra = s.stale and "\n|cffff8800no longer on its bar|r" or ""
	local q = ns.Skills:QueuedFor(owner)
	if q and q.id == s.spellId then
		extra = extra .. "\n|cffffd100queued, waiting for a slot|r"
	end
	-- THE THREE GESTURES, WRITTEN DOWN. A modifier that is not spelled out
	-- anywhere is a modifier that does not exist.
	extra = extra .. (info.ask
		and "\n|cff888888Click: choose a target. Alt: on itself.|r"
		or  "\n|cff888888Click: sent right away. Shift: choose a target.|r")
	ns.W:Tip(b, s.name, ("%s -- %s%s\n|cff888888Right click: change it.|r"):format(
		owner, info.label, extra))

	SetArmed(b, aiming and aiming.owner == owner and aiming.slot == i
		and (aiming.set or "main") == (set or "main"))
end

--- Layout ------------------------------------------------------------------

local function HideAll(list)
	for _, b in ipairs(list) do b:Hide() end
end

function C:Layout()
	if not self.active then return end
	if ns.Dock:State() == "A" then
		self:LayoutA()
	else
		self:LayoutB()
	end
	self:Refresh()
end

function C:LayoutA()
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		HideAll(col.spells)
	end

	local hHost = ns.Dock:Host("head")
	local sHost = ns.Dock:Host("spells")
	if not (hHost and sHost) then return end

	if not headName then
		headName = ns.W:Text(hHost, ns.W.FONT.big)
		headName:SetJustifyH("LEFT")
	end
	headName:SetParent(hHost)
	headName:ClearAllPoints()
	headName:SetPoint("BOTTOMLEFT", hHost, "BOTTOMLEFT", 2, 2)
	headName:Show()

	local cells = ns.Dock:SpellCells()
	for i = 1, ns.Dock.MAIN_N do
		local c = cells[i]
		if c then
			PlaceSquare(SpellButton(spellBtn, i, sHost, c.w, "main"), sHost, c)
		elseif spellBtn[i] then
			spellBtn[i]:Hide()
		end
	end
end

function C:LayoutB()
	HideAll(spellBtn)
	if headName then headName:Hide() end

	local cols = ns.Dock:Columns()
	local cells = ns.Dock:ColumnSpellCells()

	for ci = 1, #cols do
		local h = ns.Dock:Host("col" .. ci)
		local col = colBtn[ci]
		if not col then
			col = { spells = {} }
			col.head = ns.W:Text(h, ns.W.FONT.normal)
			col.head:SetJustifyH("LEFT")
			colBtn[ci] = col
		end

		col.head:SetParent(h)
		col.head:ClearAllPoints()
		col.head:SetPoint("TOPLEFT", h, "TOPLEFT", 2, 0)
		col.head:SetHeight(ns.Dock:BHeadHeight())
		-- THE NAME IS BOUNDED BY ITS COLUMN'S WIDTH. Without this a long name
		-- draws as far as it likes, which with five columns side by side is on
		-- top of the one next to it.
		col.head:SetWidth(ns.Dock:ColWidth())
		col.head:Show()

		for i = 1, ns.Dock.B_SLOTS do
			local c = cells[i]
			if c then
				PlaceSquare(SpellButton(col.spells, i, h, c.w, "group"), h, c)
			elseif col.spells[i] then
				col.spells[i]:Hide()
			end
		end
	end

	-- The columns left over from an earlier layout. `#colBtn` is no good as a
	-- limit: it is filled by index and a drop from five to two can leave holes
	-- that `#` cuts short of. It gets walked with `pairs`.
	for ci, col in pairs(colBtn) do
		if ci > #cols then
			if col.head then col.head:Hide() end
			HideAll(col.spells)
		end
	end
end

--- Refresh -----------------------------------------------------------------

function C:Refresh()
	if not self.active then return end
	local aiming = ns.Skills:Aiming()

	if ns.Dock:State() == "A" then
		local owner = ns.Dock:Subject()
		if not owner then return end

		if headName then
			local c = ns.W:ClassColor(ns.Selection:UnitFor(owner) or "player")
			headName:SetText(Clip(owner, NAME_A))
			headName:SetTextColor(c.r, c.g, c.b)
		end
		local slots = ns.Skills:Slots(owner, ns.Dock.MAIN_N, "main")
		for i = 1, ns.Dock.MAIN_N do
			local b = spellBtn[i]
			if b and b:IsShown() then PaintSpell(b, owner, i, slots[i], aiming, "main") end
		end
		return
	end

	local cols = ns.Dock:Columns()
	for ci, m in ipairs(cols) do
		local col = colBtn[ci]
		if col then
			local c = ns.W:ClassColor(m.unit)
			col.head:SetText(Clip(m.name, NAME_B))
			col.head:SetTextColor(c.r, c.g, c.b)

			local slots = ns.Skills:Slots(m.name, ns.Dock.B_SLOTS, "group")
			for i = 1, ns.Dock.B_SLOTS do
				local b = col.spells[i]
				if b and b:IsShown() then PaintSpell(b, m.name, i, slots[i], aiming, "group") end
			end
		end
	end
end

--- The second click of look after ------------------------------------------

-- Called from `RTSMode` when there is a focus pending. Returns true if it has
-- eaten the click.
function C:AimAt(guid, label)
	local who = self.pendingFocus
	if not who then return false end
	self.pendingFocus = nil

	if not guid then
		ns.Print("|cff888888look after: cancelled.|r")
		self:Refresh()
		return true
	end

	self:PointAt(who, guid, label)
	self:Refresh()
	return true
end

function C:CancelAim()
	if not self.pendingFocus then return false end
	self.pendingFocus = nil
	self:Refresh()
	return true
end

--- Entering and leaving ----------------------------------------------------

function C:Enter()
	self.active = true

	if not self.wired then
		self.wired = true
		ns.Dock:OnLayout(function() C:Layout() end)
		ns.Skills:Subscribe(function() C:Refresh() end)
		ns.Selection:Subscribe(function() C:Refresh() end)

		ns.Link:On("PFOCUS", function(rest)
			-- TWO DIRECTIONS: we send `PFOCUS <bot> <guid>` and the reply comes
			-- back with a third field (hostile 0/1). That is what tells them
			-- apart, and without it our own echo would light up the state
			-- without the server having said a thing.
			local bot, guid, hostile = rest:match("^(%S+)%s+(%S+)%s+([01])$")
			if not bot then return end
			C.focus[bot] = (guid ~= "-") and guid or nil
			C:Refresh()
		end)
	end

	self:Layout()
end

function C:Leave()
	self.active = false
	self.pendingFocus = nil
	self:HidePicker()
	HideAll(spellBtn)
	if headName then headName:Hide() end
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		HideAll(col.spells)
	end
end

function C:Report()
	local owner = ns.Dock:Subject()
	ns.Print(("|cffffff00slots of|r |cff33ccff%s|r"):format(tostring(owner)))
	ns.Print(("  looks after: %s"):format(self.focus[owner] or "|cff888888nobody|r"))
	ns.Print("  the spell list: |cffffff00/rts skills|r")
end

ns.Dock:Register(C)
