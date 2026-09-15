--[[
	Macros.lua -- the orders to the bots, as game macros.

	THE CATALOGUE LIVES IN `Actions.lua` AND THIS FILE COPIES IT INTO GAME
	MACROS. Ever since the tray learned to fire the orders by itself -- with an
	icon of its own and spending no macros -- this is no longer the normal way to
	use them: it is the way to GET THEM OUT OF THE ADDON. A real macro can be put
	on a game bar, it can be given a key and it can be dragged anywhere; an order
	of ours lives only in the tray.

	`/rts macros` creates (or updates) the catalogue's macros.
	DRAGGING THEM TO THE TRAY IS THE PLAYER'S JOB, once. They do not place
	themselves: that would be `PickupMacro` + `PlaceAction`, `PlaceAction` is of
	the protected family and has not been checked on this client -- and nothing
	is built here on an unchecked reading. If one day it is checked and it does
	let us, it is one line.

	=== WHERE THE ORDER GOES OUT ==========================================

	Each macro is one or more `/rtscmd <playerbots command>` lines.

	`/rtscmd` goes TO THE SELECTED, and if nobody is selected it goes to the
	whole party AND SAYS SO. `/rtsall` always goes to the whole party. Both go
	through `Orders`, which means they inherit the send queue -- four whispers in
	the same frame are eaten by the client's chat rate limit without a single
	error, which is the bug that queue exists so as not to repeat.

	A macro that talked straight down `/p` would work too, and that is why it is
	worth knowing it is NOT the same thing: it would always go to all five.

	=== WHAT THIS CLIENT ASKS FOR, CHECKED AGAINST IT =====================

	Read out of `Blizzard_MacroUI.lua` and `.xml` of THIS client (pulled from
	`patch-esES.MPQ`), not from memory:

	  CreateMacro(name, ICON, body, perCharacter)
	  EditMacro(index, name, ICON, body)

	**THE ICON IS AN INDEX, NOT A PATH.** It is the position inside the client's
	macro icon list, the one `GetMacroIconInfo(i)` translates into a texture.
	Passing "Interface\\Icons\\Whatever" is not an error: it gives an empty icon,
	which is the same old silent failure mode. So here that list is walked ONCE,
	name -> index is saved, and whatever does not turn up keeps the question mark
	AND IS CALLED OUT on screen.

	  MAX_ACCOUNT_MACROS = 36      the account ones (indices 1..36)
	  MAX_CHARACTER_MACROS = 18    the character ones (indices 37..54)
	  name: 16 letters             (`letters="16"` of MacroPopupEditBox)
	  body: 255 letters            (`letters="255"` of MacroFrameText)

	They are created among the ACCOUNT ones: an order to a bot does not depend on
	which character you are playing.

	=== WHY IT UPDATES INSTEAD OF DELETING AND CREATING ===================

	An action bar saves the macro's INDEX, not its name. Deleting and creating
	again shuffles the indices, so the button the player had placed would end up
	pointing at another macro -- or at none. Running `/rts macros` again has to
	be free, so if one of ours with that name already exists it gets an
	`EditMacro` on top and its place on the bar is respected.

	"One of ours" is recognised because its body carries `/rtscmd`. A macro of
	the player's that happens to be called the same is NOT touched: it is flagged
	and skipped.
]]

local ADDON, ns = ...

local M = {}
ns.Macros = M

-- What marks a macro as ours, and at the same time the channel the order goes
-- out through. The two things are the same string on purpose: there is no way
-- to have one without the other and let them drift apart.
local MARK = "/rtscmd"

-- From `Blizzard_MacroUI.lua`. They are read off the client if they are there
-- (they are globals of its own), and if not, from here: a wrong number here
-- turns into macros created out of range that never show up.
local ACCOUNT_MAX = 36
local CHAR_MAX = 18
local NAME_MAX = 16
local BODY_MAX = 255

--- The catalogue, which no longer lives here ------------------------------
--
-- THIS FILE STOPS BEING THE OWNER OF THE ORDERS. The list has moved wholesale
-- to `Actions.lua`, which is what shows it in the tray dropdown and what fires
-- it. It is still read here for the one thing a real macro does and an order of
-- ours does not: existing OUTSIDE the addon -- on a game bar, with its key, or
-- to be dragged wherever.
--
-- It is asked for BY FUNCTION and not copied into a local on load: that way the
-- order of the files in the `.toc` does not matter, which is the class of
-- dependency that gives no warning when it breaks -- an empty catalogue simply
-- comes out.

local function Catalogue()
	return (ns.Actions and ns.Actions.LIST) or {}
end

--- The icons: from the name to the index ----------------------------------
--
-- The whole list is walked ONCE and saved by file name, with no path and in
-- upper case. It is a couple of thousand entries: a blink, and it only happens
-- when the macros are created.

local iconIndex

local function IconIndex()
	if iconIndex then return iconIndex end
	local map = {}

	-- The icon list belongs to the client, not to the macro addon, but loading
	-- it costs nothing and takes away the doubt of whether it was available yet.
	if not IsAddOnLoaded("Blizzard_MacroUI") then
		pcall(LoadAddOn, "Blizzard_MacroUI")
	end

	local n = GetNumMacroIcons and GetNumMacroIcons() or 0
	for i = 1, n do
		local tex = GetMacroIconInfo(i)
		if type(tex) == "string" then
			local base = tex:match("[^\\/]+$") or tex
			base = base:upper()
			-- First one wins: if the same name comes up twice it makes no
			-- difference which, they are the same texture.
			if not map[base] then map[base] = i end
		end
	end

	-- AN EMPTY LIST IS NOT SAVED. If it is not there yet (the interface has only
	-- just loaded), caching the failure leaves it failing for ever and the
	-- macros would all come out with a question mark and nothing to explain it.
	-- It is the same mistake as caching a CVar that does not exist yet -- the
	-- FOV was dead for THREE stages because of that. It gets tried again next
	-- time.
	if n == 0 then return map end
	iconIndex = map
	return iconIndex
end

local function IconFor(name)
	return IconIndex()[(name or ""):upper()]
end

--- The macros already there -----------------------------------------------

local function Limits()
	local a = _G.MAX_ACCOUNT_MACROS or ACCOUNT_MAX
	local c = _G.MAX_CHARACTER_MACROS or CHAR_MAX
	return a, c
end

-- Walks the REAL indices of the existing macros. The account ones are 1..n; the
-- character ones always start at MAX_ACCOUNT_MACROS+1, whether the account is
-- full or not.
local function EachMacro(fn)
	local amax = Limits()
	local na, nc = GetNumMacros()
	for i = 1, (na or 0) do
		if fn(i) then return i end
	end
	for i = 1, (nc or 0) do
		local idx = amax + i
		if fn(idx) then return idx end
	end
end

-- "Ours" is any macro whose body talks through one of our commands. `/rtscmd`
-- marks the bot-order ones and `/rts` the addon's own (lock, windows, exit) --
-- both have to count, or `/rts macros` would refuse to update half of its own
-- catalogue saying it belongs to the player.
local function IsOurs(body)
	if type(body) ~= "string" then return false end
	return body:find(MARK, 1, true) ~= nil or body:find("/rts", 1, true) ~= nil
end

-- Returns index, isOurs. Compares by NAME because that is the only thing that
-- survives the player moving it somewhere else.
local function FindByName(name)
	local found, mine
	EachMacro(function(i)
		local n, _, body = GetMacroInfo(i)
		if n == name then
			found, mine = i, IsOurs(body)
			return true
		end
	end)
	return found, mine
end

-- The macro's body is THE SAME TEXT that fires the order from the tray, and
-- that is why `Actions.lua` writes it and not this file: two places composing
-- the same lines come apart the day one of them changes.
local function BodyOf(entry)
	return ns.Actions:Body(entry)
end

--- Creating and updating --------------------------------------------------

-- IF THE CLIENT REFUSES, LET IT BE READ ONCE AND NOT TWENTY-FOUR TIMES.
--
-- `CreateMacro` and `EditMacro` are not on the list of protected functions this
-- project has checked, but neither has the opposite been checked -- and between
-- assuming they are fine and finding out through twenty-four identical red
-- errors, better to stop at the first one and say which it was.
local function Blocked(name, err)
	ns.Print(("|cffff0000macros:|r the client would not let '%s' be touched: %s")
		:format(name, tostring(err)))
	ns.Print("If it says 'blocked', the function is protected on this client " ..
		"and the macros have to be made by hand from |cffffff00/macro|r.")
end

--- THERE IS NO AUTOMATIC PRUNING, AND THIS IS THE SCAR --------------------
--
-- On 2026-09-14 `Build` deleted, before creating, every "mine" macro that was
-- no longer in the catalogue. The idea was good -- the catalogue as the single
-- truth, with no orphans -- and the RULE was bad: "mine" was decided with
-- `IsOurs`, that is, *any macro whose body has `/rts` or `/rtscmd` inside it*.
--
-- That does not tell apart what this addon created from what the PLAYER wrote
-- for himself using our commands. And the player had four of his own --
-- `/rts command`, `/rts mode`, `Playerbots add` (which starts with `/rts` and
-- goes on with GM commands) and `Traerlos` (`/rtscmd summon`) -- that fell into
-- that net and went out with the twenty-two of the cull, having never been
-- created by us.
--
-- THE LESSON, written where it was made: an addon can create and can UPDATE
-- what it created, but **deleting what it did not create is not its to do**,
-- and "looks like mine" is not "is mine". To be able to delete by right it
-- would have to save which macros we created, name by name, and even then a
-- repeated name would make it ambiguous.
--
-- So nothing is deleted. Taking an entry out of the catalogue stops it being
-- created and that is all; the leftover macro is deleted by the player from
-- `/macro`, which is where nobody can get it wrong.
--
-- (`M:Clear()` still exists and still deletes by `IsOurs` -- but that is the
-- player asking for it on purpose, by typing it, and it says how many it takes
-- with it.)

function M:Build()
	if InCombatLockdown() then
		ns.Print("|cffff8800macros:|r not in combat. Leave the fight and try again.")
		return
	end

	local amax = Limits()
	local made, upd, skipped, full = 0, 0, 0, 0
	local noIcon = {}

	for _, e in ipairs(Catalogue()) do
		local body = BodyOf(e)
		local icon = IconFor(e.icon)
		if not icon then
			table.insert(noIcon, e.icon)
			icon = IconFor("INV_Misc_QuestionMark") or 1
		end

		-- Name and body go through the same trim the client would apply in
		-- silence. Better seen here than discovered in the window.
		local name = e.name
		if name:len() > NAME_MAX then
			ns.Print(("|cffff8800macros:|r '%s' goes over %d letters, it gets trimmed.")
				:format(name, NAME_MAX))
			name = name:sub(1, NAME_MAX)
		end
		if body:len() > BODY_MAX then
			ns.Print(("|cffff8800macros:|r the body of '%s' goes over %d letters and is NOT created.")
				:format(name, BODY_MAX))
			skipped = skipped + 1
		else
			local idx, mine = FindByName(name)
			if idx and not mine then
				ns.Print(("|cffff8800macros:|r you already have a macro called '%s' " ..
					"that is not mine. I am not touching it."):format(name))
				skipped = skipped + 1
			elseif idx then
				local ok, err = pcall(EditMacro, idx, name, icon, body)
				if not ok then return Blocked(name, err) end
				upd = upd + 1
			else
				local na = GetNumMacros()
				if (na or 0) >= amax then
					full = full + 1
				else
					local ok, err = pcall(CreateMacro, name, icon, body, false)
					if not ok then return Blocked(name, err) end
					made = made + 1
				end
			end
		end
	end

	ns.Print(("macros: |cff00ff00%d new|r, %d updated%s%s."):format(
		made, upd,
		skipped > 0 and (", |cffff8800" .. skipped .. " skipped|r") or "",
		full > 0 and (", |cffff0000" .. full .. " with no room|r") or ""))

	if #noIcon > 0 then
		-- AN ICON THAT IS NOT ON THE LIST IS NOT AN ERROR: it gives an empty
		-- hole. Saying so here is the difference between fixing it in a minute
		-- and staring at a bar full of gaps wondering what broke.
		ns.Print("|cffff8800macros:|r no icon (they are not on the client's list): " ..
			table.concat(noIcon, ", "))
	end
	if full > 0 then
		ns.Print(("The account macros are %d and they are full. Delete one " ..
			"or use |cffffff00/rts macros clear|r and try again."):format(amax))
	end

	-- WHERE TO PUT THEM CHANGED ON 2026-09-13. It used to be "the two vertical
	-- bars on the right", because RTS mode left them in view on purpose for
	-- this. Now it hides them with the rest of the action bars and the place is
	-- the TRAY: ten slots of its own, which is where the 4x4 grid ended up.
	ns.Print("Open |cffffff00/macro|r and drag them to the |cffffff00ten slots|r " ..
		"at the bottom right, in RTS mode.")

	-- AND IT SAYS HOW MANY THERE ARE, because the catalogue is already up
	-- against the account limit: 35 out of 36. With two macros of the player's
	-- own, the last of the catalogue do not fit -- and that comes out through
	-- `full`, but only AFTER trying. Saying it beforehand is the difference
	-- between understanding it and thinking the command is broken.
	local amax2 = Limits()
	ns.Print(("|cff888888The catalogue is %d macros and the account takes %d.|r")
		:format(#Catalogue(), amax2))
end

--- Deleting ours ----------------------------------------------------------

function M:Clear()
	if InCombatLockdown() then
		ns.Print("|cffff8800macros:|r not in combat.")
		return
	end

	-- Highest to lowest: deleting shuffles the indices of everything behind it.
	local mine = {}
	EachMacro(function(i)
		local _, _, body = GetMacroInfo(i)
		if IsOurs(body) then table.insert(mine, i) end
	end)
	table.sort(mine, function(a, b) return a > b end)

	for _, i in ipairs(mine) do DeleteMacro(i) end
	ns.Print(("macros: deleted %d of mine. Yours are not touched."):format(#mine))
	if #mine > 0 then
		ns.Print("|cffff8800Careful:|r deleting shuffles the indices, so check " ..
			"the buttons on the bar.")
	end
end

--- What is there and what it would do -------------------------------------

function M:List()
	ns.Print(("catalogue: %d macros. |cffffff00/rts macros|r creates them."):format(#Catalogue()))
	for _, e in ipairs(Catalogue()) do
		local idx, mine = FindByName(e.name)
		local mark = (idx and mine) and "|cff00ff00[placed]|r"
			or (idx and "|cffff8800[taken]|r" or "|cff888888[no]|r")
		ns.Print(("  %s |cffffff00%-13s|r %s  |cff888888%s|r"):format(
			mark, e.name, table.concat(e.cmd, " + "), e.d or ""))
	end
end

function M:Status()
	local amax, cmax = Limits()
	local na, nc = GetNumMacros()
	local n = 0
	EachMacro(function(i)
		local _, _, body = GetMacroInfo(i)
		if IsOurs(body) then n = n + 1 end
	end)
	ns.Print(("macros: %d/%d account, %d/%d character; %d are mine.")
		:format(na or 0, amax, nc or 0, cmax, n))
	ns.Print(("client icons: %d on the list."):format(
		GetNumMacroIcons and GetNumMacroIcons() or 0))
	ns.Print("|cffffff00/rts macros|r creates or updates  " ..
		"|cffffff00list|r what is there  |cffffff00clear|r deletes mine")
	ns.Print("Each one sends |cffffff00/rtscmd <cmd>|r: to the SELECTED, " ..
		"or to the whole party if there is nobody.")
end

--- The two commands the macros use ----------------------------------------
--
-- They are registered here and not in `Core.lua` because they are the flip side
-- of this file: a catalogue macro means nothing without them, and separating
-- them is how you end up with a verb nobody listens to.

local function Route(text, forceAll)
	text = strtrim(text or "")
	if text == "" then
		ns.Print("|cffffff00/rtscmd <cmd>|r - to the selected " ..
			"(or to the whole party if there is nobody).")
		ns.Print("|cffffff00/rtsall <cmd>|r - always to the whole party.")
		return
	end

	local sel = ns.Selection:Get()
	if forceAll or #sel == 0 then
		-- SAY IT. An order going out to all five when you thought you had
		-- ordered one is exactly the symptom this catalogue comes to make
		-- reachable.
		if not forceAll then
			ns.Print("|cffffff00no selection|r -> to the whole party:")
		end
		ns.Orders:Broadcast(text, "> " .. text .. " (whole party)")
	else
		ns.Orders:Send(text, "> " .. text)
	end
end

SLASH_RTSCMD1 = "/rtscmd"
SLASH_RTSCMD2 = "/rtsc"
SlashCmdList["RTSCMD"] = function(msg) Route(msg, false) end

SLASH_RTSALL1 = "/rtsall"
SlashCmdList["RTSALL"] = function(msg) Route(msg, true) end
