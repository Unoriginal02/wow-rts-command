--[[
	Dock.lua -- the layout of the bottom of the screen.

	It replaces `Bar.lua` (the console art) and `Hall.lua` (the layout of its
	hall), both deleted on 2026-09-13. The one-piece console with the minimap
	inside it is discarded whole: the minimap goes back where it has always
	been, the player, target and party frames are the game's own, and the only
	thing the addon draws down here are ACTION BARS.

	  +---------------------------------------------------------------+
	  |                                                               |
	  |              Bob  (dps)                                       |
	  |        [1][2][3][4][5][6][7][8][9][0]    [M][M][M][M]         |
	  |                                          [M][M][M][M]         |
	  |                                          [bags]               |
	  |                                          [char][talents]...   |
	  +---------------------------------------------------------------+

	IN THE MIDDLE: THE UNIT, or the units. ON THE RIGHT: WHAT IS YOURS -- the
	command macros, the bags and the game buttons. The division is not
	aesthetic: what is in the centre CHANGES with every selection click and what
	is on the right never moves. Mixing them would force the eye to check every
	time whether the button it is after is still where it was.

	And that is why the one that gets centred is the one in the centre: what
	changes width lays itself out again around the same axis, and what does not
	change stays nailed to its corner.

	=== TWO STATES, AND THE SELECTION DECIDES THEM ==========================

	  A  none or one      the name and TEN slots
	  B  two or more      one column per head: name and a 2x2 of FOUR

	AND ONLY THE NAME. There was a STANCE label next to it, which showed the
	playerbots role (tank/dps/heal) and let you change it. It was deleted whole
	the same day it was born, for two reasons that go together:

	  - It was not what was asked for. A warrior's "combat stance" is battle,
	    defensive or berserker; the playerbots role is another thing and putting
	    it there under that name was answering a different question.
	  - And what was being asked for NEEDS NO INTERFACE. A stance is a SPELL:
	    yours fits in a macro (`/cast Defensive Stance`) that gets dragged onto
	    the tray, and a bot's shows up in its spell list, so it goes into one of
	    its ten slots with a right-click. A button of its own for that would be
	    a third way of doing what two already do.

	The bots' role is decided by playerbots, whose it is.

	WITH NOTHING SELECTED IT IS YOU WHO SHOWS UP, and this is the opposite of
	what the hall did. There the centre emptied when the selection was let go,
	because drawing somebody's slots without having them picked read as if they
	were still picked. Here there is no such ambiguity: with no selection the
	owner is YOU, with your name written above it, which is exactly what an
	ordinary action bar shows when you are not commanding anyone.

	=== THE FOUR OF STATE B ARE NOT THE FIRST FOUR OF THE TEN ===============

	And this one IS a deliberate change from the hall, asked for on 2026-09-13.
	Before, the 2x2 showed slots 1..4 of the same row, with the argument that
	two lists are two places to configure the same thing. The argument against
	is stronger: with four picked you do not want each one's first four spells,
	you want WHAT GETS SENT AS A GROUP -- the stun, the emergency heal, the
	shield -- which are almost never the same ones you use when you are running
	just one.

	They are two sets saved per character (`Skills`: `main` and `group`) and the
	size of each is fixed: ten and four. They are configured the same way, with
	a right-click, so there are not two gestures to learn.

	=== EVERYTHING IN PHYSICAL PIXELS =======================================

	The Dock hangs off `ns.Pixels:Host()`, which carries the 768/physicalHeight
	scale: from its children inwards, one unit is one pixel. That convention
	stays -- it is the one `Widgets` and our own windows already use -- even
	though today there is no art to justify it, because the day there is it
	justifies itself, and in the meantime the SIDE OF THE SLOT COMES MEASURED
	out of the client itself (`Pixels:ActionButtonPixels`): a slot on this bar
	measures exactly what a button on the game's action bar measures.

	=== WHO DRAWS IS NOT THIS FILE ==========================================

	The same contract `Bar` and `Hall` had, which is the best thing the addon
	has: here are the AREAS and the STATE, and the content is put in by `Cast`
	(the slots) and `Tray` (the macros and the game buttons), which sign
	themselves up with `Dock:Register(m)` and ask for their frame with
	`Dock:Host(key)`.
]]

local ADDON, ns = ...

local D = {}
ns.Dock = D

D.active = false

--- The measurements, in physical pixels -----------------------------------

-- The margin against the edge of the screen. The same on both sides and at the
-- bottom: two blocks that start at different heights read as out of square.
local MARGIN = 30

-- AND THE COMMON FLOOR OF THE TWO BLOCKS. The right side ends in the row of
-- game buttons, which hangs below the macro block, and `Tray` reserves that
-- gap leaving this same breathing space underneath. The centre has to start at
-- the SAME height or it ends up eight pixels lower than everything else --
-- which is exactly what could be seen.
--
-- It is a single number and both of them use it: the centre to lift itself and
-- `Tray` to reserve. Two equal numbers written in two places come apart the
-- day somebody touches one.
local FOOT_PAD = 8

-- The side of the slot COMES MEASURED, with a ceiling and a floor in case the
-- measurement cannot be taken (with no action bar loaded it returns the
-- factory 36).
local SLOT_MIN, SLOT_MAX = 38, 84
local GAP = 7

local MAIN_N = 10       -- the slots of state A
local B_SLOTS = 4       -- the 2x2 of state B
local B_COLS, B_ROWS = 2, 2

local HEAD_H   = 32     -- the header of state A: the name
local HEAD_GAP = 8
local B_HEAD_H = 26
local B_HEAD_GAP = 6
local COL_GAP  = 30     -- between columns of state B

-- FIVE BY TWO, TEN SQUARES. It started at four by two and fell short as soon
-- as it was used: eight orders do not cover the basic command set (follow,
-- hold, attack, pull, flee), assisting and upkeep. The grid is wide, not tall,
-- because what limits it from above is the macro block -- growing upwards
-- pushes the bags and the menu off the screen.
local MACRO_COLS, MACRO_ROWS = 5, 2

D.MAIN_N  = MAIN_N
D.B_SLOTS = B_SLOTS
D.MACRO_N = MACRO_COLS * MACRO_ROWS

--- Internal state ---------------------------------------------------------

local host                -- the pixel-scale container
local left, right         -- the two root frames (`left` is the centred one)
local rightFoot = 0       -- what `Tray` reserves below for the game buttons
local frames = {}         -- key -> Frame
local rects  = {}         -- key -> { x, y, w, h } inside ITS root
local panels = {}
local listeners = {}

local function Slot()
	local px = ns.Pixels:ActionButtonPixels() or 58
	px = math.floor(px + 0.5)
	if px < SLOT_MIN then px = SLOT_MIN elseif px > SLOT_MAX then px = SLOT_MAX end
	return px
end

--- Registration -----------------------------------------------------------

-- `m` needs `Enter`/`Leave`, both of them optional. With the usual guard
-- against double registration: two `Enter`s are duplicated buttons on top of
-- their own, and a `/reload` should not be able to cause that.
function D:Register(m)
	if not m then return end
	for _, other in ipairs(panels) do
		if other == m then return end
	end
	table.insert(panels, m)
	if self.active and m.Enter then m:Enter() end
end

function D:OnLayout(fn)
	table.insert(listeners, fn)
	if self.active then pcall(fn) end
end

local function Announce()
	for _, fn in ipairs(listeners) do
		-- A module that fails cannot leave the bar half laid out nor take the
		-- others down with it.
		local ok, err = pcall(fn)
		if not ok then ns.Print("|cffff0000dock:|r " .. tostring(err)) end
	end
end

--- The state --------------------------------------------------------------

function D:State()
	return (ns.Selection:Count() >= 2) and "B" or "A"
end

-- Whose the row of slots is in state A. The only one selected, and if there is
-- none, YOU: see the header.
function D:Subject()
	return ns.Selection:Single() or ns.MyName()
end

-- The characters whose columns get drawn in state B, in party order with the
-- hero first -- which is the order the player has in front of them in the
-- game's frames.
function D:Columns()
	local out = {}
	for _, m in ipairs(ns.Selection:GetRosterHeroFirst()) do
		if ns.Selection:IsSelected(m.name) then
			table.insert(out, m)
		end
	end
	return out
end

--- The layout -------------------------------------------------------------

local function Rect(key, x, y, w, h)
	rects[key] = { x = x, y = y, w = w, h = h }
end

local function Recompute()
	rects = {}
	local s = Slot()
	D.slot = s

	--- LEFT --------------------------------------------------------------
	if D:State() == "A" then
		local w = MAIN_N * s + GAP * (MAIN_N - 1)
		D.leftW = w
		D.leftH = HEAD_H + HEAD_GAP + s
		Rect("head",   0, 0, w, HEAD_H)
		Rect("spells", 0, HEAD_H + HEAD_GAP, w, s)
		D.cols = 0
	else
		local cols = #D:Columns()
		local colW = B_COLS * s + GAP * (B_COLS - 1)
		local colH = B_HEAD_H + B_HEAD_GAP + B_ROWS * s + GAP * (B_ROWS - 1)
		D.colW, D.colH = colW, colH
		D.cols = cols
		D.leftW = cols * colW + COL_GAP * math.max(cols - 1, 0)
		D.leftH = colH
		for i = 1, cols do
			Rect("col" .. i, (i - 1) * (colW + COL_GAP), 0, colW, colH)
		end
	end

	--- RIGHT -------------------------------------------------------------
	--
	-- The macro block sets the width; the row of game buttons hangs below it
	-- and it is `Tray` that measures it, being the one that knows how much
	-- room the client's micro-buttons take (they are its own and have their
	-- own size).
	local mw = MACRO_COLS * s + GAP * (MACRO_COLS - 1)
	local mh = MACRO_ROWS * s + GAP * (MACRO_ROWS - 1)
	D.rightW, D.rightH = mw, mh
	Rect("macros", 0, 0, mw, mh)
end

--- What the content modules use -------------------------------------------

function D:Get(key) return rects[key] end

local function RootFor(key)
	if key == "macros" then return right end
	return left
end

local function Place(key, f)
	local r = rects[key]
	local root = RootFor(key)
	if r and root and r.w > 0 and r.h > 0 then
		f:SetParent(root)
		f:SetWidth(r.w)
		f:SetHeight(r.h)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", root, "TOPLEFT", r.x, -r.y)
		f:Show()
	else
		f:Hide()
	end
end

-- The frame of an area. They are created on demand and never destroyed --
-- going from state B to A hides the columns instead of deleting them.
--
-- IT IS PLACED AS IT IS CREATED, and that is not a detail: `Layout` lays out
-- over the frames THAT ALREADY EXIST and announces AFTERWARDS, but the column
-- ones are only asked for by the content, which runs inside that announcement.
-- Without placing them here, the first time several are picked they are born
-- 0x0 and unanchored and not one column comes out. It is a bug that was
-- already paid for once in `Hall.lua`.
function D:Host(key)
	local root = RootFor(key)
	if not root then return nil end
	local f = frames[key]
	if not f then
		f = CreateFrame("Frame", "RTSDock_" .. key, root)
		f:SetFrameLevel(root:GetFrameLevel() + 2)
		f:EnableMouse(false)
		frames[key] = f
		Place(key, f)
	end
	return f
end

--- The cells, in coordinates of THEIR frame -------------------------------

function D:SpellCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	for i = 1, MAIN_N do
		out[i] = { x = (i - 1) * (s + GAP), y = 0, w = s, h = s }
	end
	return out
end

function D:ColumnSpellCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	local y0 = B_HEAD_H + B_HEAD_GAP
	for i = 1, B_SLOTS do
		local c = (i - 1) % B_COLS
		local r = math.floor((i - 1) / B_COLS)
		out[i] = { x = c * (s + GAP), y = y0 + r * (s + GAP), w = s, h = s }
	end
	return out
end

function D:MacroCells()
	local out = {}
	local s = self.slot or 0
	if s <= 0 then return out end
	for i = 1, MACRO_COLS * MACRO_ROWS do
		local c = (i - 1) % MACRO_COLS
		local r = math.floor((i - 1) / MACRO_COLS)
		out[i] = { x = c * (s + GAP), y = r * (s + GAP), w = s, h = s }
	end
	return out
end

function D:HeadHeight()  return HEAD_H end
function D:BHeadHeight() return B_HEAD_H end
function D:ColWidth()    return self.colW or 0 end
function D:Margin()      return MARGIN end
function D:FootPad()     return FOOT_PAD end

-- WHAT `Tray` RESERVES BELOW for the row of game buttons, in pixels. This file
-- does not decide it because it cannot: the micro-buttons belong to the client
-- and measure whatever they measure. It is asked for here instead of anchoring
-- the row to the floor with the macros above it, because that way the macro
-- block does not move every time the client shows or hides one of its buttons.
function D:SetRightFoot(px)
	rightFoot = px or 0
	if not (right and host) then return end
	right:ClearAllPoints()
	right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -MARGIN, MARGIN + rightFoot)
end

--- Laying out -------------------------------------------------------------

function D:Layout()
	if not left then return end
	Recompute()

	left:SetWidth(math.max(self.leftW or 1, 1))
	left:SetHeight(math.max(self.leftH or 1, 1))
	right:SetWidth(math.max(self.rightW or 1, 1))
	right:SetHeight(math.max(self.rightH or 1, 1))

	-- An area this layout did not produce is HIDDEN instead of staying where it
	-- was: going from B to A would leave five columns drawn over the row.
	for key, f in pairs(frames) do
		Place(key, f)
	end

	Announce()
end

--- Entering and leaving ---------------------------------------------------

function D:Enter()
	if not left then
		host = ns.Pixels:Host()
		if not host then return end

		-- CENTRED, and that is why it is anchored by the BOTTOM and not by a
		-- corner: the block changes width with every selection -- ten slots
		-- with one picked, five columns with five -- and anchored by the
		-- centre it lays itself out again without a single sum. With a corner
		-- the x would have to be recalculated on every change of state, which
		-- is the kind of number that gets forgotten in the third place.
		left = CreateFrame("Frame", "RTSDockLeft", host)
		left:SetPoint("BOTTOM", host, "BOTTOM", 0, MARGIN + FOOT_PAD)
		left:EnableMouse(false)

		-- THE RIGHT IS ANCHORED BY THE BOTTOM JUST LIKE THE LEFT, and on top
		-- of it `Tray` puts its row of game buttons. The other way round --
		-- the row anchored to the floor and the macros above -- the whole
		-- block moved every time the client shows or hides a micro-button.
		right = CreateFrame("Frame", "RTSDockRight", host)
		right:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -MARGIN, MARGIN + rightFoot)
		right:EnableMouse(false)
	end

	self.active = true
	left:Show()
	right:Show()

	for _, m in ipairs(panels) do
		if m.Enter then m:Enter() end
	end

	self:Layout()

	if not self.wired then
		self.wired = true

		-- A CHANGE OF SELECTION LAYS OUT AGAIN, it does not just repaint.
		-- Going from one to two changes the NUMBER of areas. Only when the
		-- SHAPE changes -- otherwise every click would move twenty buttons to
		-- leave them where they already were.
		ns.Selection:Subscribe(function()
			if not D.active then return end
			local st = D:State()
			local n = (st == "B") and #D:Columns() or 0
			local subj = D:Subject()
			if st ~= D.lastState or n ~= D.lastCols then
				D.lastState, D.lastCols, D.lastSubject = st, n, subj
				D:Layout()
			elseif subj ~= D.lastSubject then
				-- Same layout, another owner: announcing is enough.
				D.lastSubject = subj
				Announce()
			end
		end)
	end
end

function D:Leave()
	self.active = false
	for _, m in ipairs(panels) do
		if m.Leave then m:Leave() end
	end
	if left then left:Hide() end
	if right then right:Hide() end
end

function D:Report()
	if not self.active then
		ns.Print("|cff888888dock:|r not up. It goes up on entering RTS mode.")
		return
	end
	ns.Print(("|cffffff00dock|r state |cff33ccff%s|r, %d px slot (one action button)"):format(
		self:State(), self.slot or 0))
	if self:State() == "A" then
		ns.Print(("  %s: %d slots"):format(tostring(self:Subject()), MAIN_N))
	else
		ns.Print(("  %d columns of %d slots"):format(self.cols or 0, B_SLOTS))
	end
	ns.Print(("  macros: %dx%d"):format(MACRO_COLS, MACRO_ROWS))
end
