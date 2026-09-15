--[[
	Actions.lua -- the addon's own orders, with their own icons, and the
	dropdown that puts one into a tray slot.

	=== WHY THEY STOPPED BEING GAME MACROS ================================

	Until now the only way to keep an order at hand was to create a client
	MACRO (`/rts macros`) and drag it into the tray. That works, and it costs
	two things every single time:

	  1. THE ICON COMES FROM THE CLIENT'S LIST. `CreateMacro` does not take a
	     texture path: it takes the number of an icon inside the macro icon
	     list. So a macro can only wear a picture the game already ships, and
	     finding one means scrolling two thousand cells with no search box.
	     There is none that says "the party's bags" or "the party's quest log",
	     because those two things do not exist in WoW: they are ours.

	  2. THERE ARE 36 AND THEY BELONG TO THE ACCOUNT. Every catalogue order ate
	     one of the player's macro slots, and the catalogue grew to eat them all.

	AN ORDER OF OURS DOES NOT NEED TO BE A MACRO. `RunMacro` is protected, but
	what lives inside these macros is not: `/rts whatever` is handled by the
	addon itself and `/rtscmd whatever` ends up as a whisper. Both can be called
	from an ordinary button, and an ordinary button accepts ANY texture -- the
	thousands the client ships, and ours.

	WHAT STILL DOES NEED A REAL MACRO is anything with a PROTECTED verb inside:
	`/cast`, `/use`, `/target`. That cannot be fired from Lua no matter what
	button you put on it. Which is why the tray still accepts a macro dragged
	onto it -- a warrior stance, say -- and why `/rts macros` has not gone
	anywhere: one slot takes both.

	=== OUR OWN ICONS =====================================================

	  art = "bolsas"    ->  Interface\AddOns\RTSCommand\art\icons\bolsas.tga
	  icon = "INV_..."  ->  Interface\Icons\INV_...   (one of the client's)

	`art` wins when present. The PNG is dropped into the desktop icon folder
	NAMED AFTER THE ORDER and `rts-tools\Convertir_Arte.bat` fits it into 64x64
	and writes the TGA; the original stays in `art-src\icons`.

	The art FILENAMES are still Spanish (`invitar`, `candado`...) while the rest
	of this file is English, and that is deliberate: they are files on disk, and
	the rule below -- the PNG name is the authority, with no translation table
	in between -- is worth more than matching languages. Renaming them is a
	rename of the asset, not of the code.

	A TEXTURE PATH THAT DOES NOT EXIST RAISES NO ERROR: it draws nothing. So
	"I added the icon and the slot came out blank" is always the filename or a
	missing deploy, never the code -- and that is exactly why the PNG name is
	the authority and there is no translation table in between.

	OURS ARE NOT CROPPED. The client's icons carry a padding border that
	everyone crops at 7% (`SetTexCoord(0.07, 0.93, ...)`); ours arrive already
	fitted with transparency around them, so cropping would eat the drawing.
]]

local ADDON, ns = ...

local A = {}
ns.Actions = A

local ART_DIR = "Interface\\AddOns\\RTSCommand\\art\\icons\\"
local ICON_DIR = "Interface\\Icons\\"

--- The catalogue ----------------------------------------------------------
--
-- `cmd` is the lines the order fires, in the same format as a macro body.
-- `raw` means they are already our own commands; without it they are
-- playerbots verbs and go out through `/rtscmd`.
--
-- `cmd2` IS THE SECOND ORDER, the RIGHT-CLICK one, and almost nothing carries
-- it. It is only worth it when the two are the same thing seen two ways -- the
-- lock pins the camera at its current distance on left-click and puts it ABOVE
-- THE HERO on right-click -- because right-click already had an owner in the
-- tray (the dropdown that changes the slot), and taking that away in exchange
-- for just any second order would be hiding the only way to configure it. On
-- the slots that carry one, the dropdown moves to SHIFT+right and the tooltip
-- says so.
--
-- `d2` is its description. With no `d2` there is nothing to show in the
-- tooltip, so a `cmd2` without a `d2` is a hidden feature -- the same as not
-- having it at all.
--
-- NO VERB IS INVENTED: every one is in `ChatCommandHandlerStrategy.cpp` or is
-- a strategy name from `StrategyContext.h`.
--
-- `g` is the dropdown group. It only separates things visually: twelve lines
-- in a row read like a shopping list.
--
-- `id` is what gets SAVED in the slot, so it is not renamed lightly: renaming
-- leaves the player's slots pointing at an order that no longer exists. See
-- `OLD_IDS` below, which is how the Spanish ids survived being renamed. The
-- visible name can change whenever you like.

local LIST = {
	-- --- FROM PLAYERBOTS, ONLY TWO -------------------------------------
	--
	-- The catalogue once held twenty-two verbs and was cut to two on
	-- 2026-09-14, at the player's request: *"from playerbot leave only follow
	-- and stop... we'll add them back one at a time later"*.
	--
	-- Putting one back is one line here. Every verb still lives in playerbots
	-- and `/rtscmd <verb>` sends it with none of this needed.
	{ id = "invite", g = "Bots", name = "Bring bots", raw = true,
	  icon = "Spell_Holy_PrayerOfHealing", art = "invitar",
	  cmd = { "/rts invite" },   d = "puts your bots in the party" },
	-- FOLLOW AND HOLD GO THROUGH THE ADDON'S COMMAND, not through `/rtscmd`.
	--
	-- They are playerbots verbs and could be whispered, and they used to be.
	-- The difference is that `/rts follow` and `/rts hold` arrive through
	-- mod-rts: no chat line, no queue, and the bot's AI gets woken up, so it
	-- moves immediately. Whispering them cost a full think cycle of its own.
	--
	-- And they respect the selection exactly as before: the selected ones, or
	-- the whole party when nothing is selected.
	{ id = "follow", g = "Bots", name = "Follow me", raw = true,
	  icon = "Ability_Rogue_Sprint", art = "sigueme",
	  cmd = { "/rts follow" },   d = "go back to following you" },
	{ id = "hold",   g = "Bots", name = "Hold", raw = true,
	  icon = "Ability_Warrior_DefensiveStance", art = "quieto",
	  cmd = { "/rts hold" },     d = "stand your ground right there" },

	-- --- OUR OWN ORDERS: the ones the addon does and playerbots does not ---
	--
	-- RALLY MEANS TELEPORTING THEM, and this was corrected on 2026-09-14: the
	-- slot used to send `/rts rally`, which is the order to WALK to your
	-- position -- the bots come on foot, with their own pathing and their own
	-- pace. What was wanted was to bring them at once, which is playerbots'
	-- `summon` verb (`SummonAction`: teleports the bot next to its master).
	--
	-- Both still exist and are NOT the same thing: `/rts rally` sends them
	-- walking and this slot brings them. If the server has
	-- `allowSummonInCombat` off, in a fight the bot answers that it cannot.
	--
	-- IT GOES TO THE WHOLE PARTY, WHATEVER THE SELECTION SAYS, which is why it
	-- goes out through `/rtsall` and not `/rtscmd`. Bringing is an order about
	-- regrouping: with two bots selected, "bring" would still have to bring all
	-- five, and if it depended on the selection it would leave three stranded
	-- without saying so -- which is exactly the kind of thing you do not notice
	-- until you go looking for them.
	--
	-- AND IT BRINGS FOLLOW WITH IT, both things at once. A bot that was on
	-- `stay` lands next to you and stands there frozen: you moved its feet but
	-- not its orders. "Bring" means "come with me", so the follow goes inside
	-- and not in a second slot you have to remember to press.
	{ id = "rally",  g = "Party", name = "Rally", raw = true,
	  icon = "Spell_Arcane_TeleportOrgrimmar", art = "reunir",
	  cmd = { "/rts bring" },    d = "brings the WHOLE party and they follow you" },
	-- SKULL AND MOON DO TWO THINGS AT ONCE -- they mark your target and send
	-- the party after that mark -- which is why they are not plain `rti skull`:
	-- half of placing the icon belongs to the client and the other half to the
	-- server.
	{ id = "skull",  g = "Party", name = "Skull", raw = true,
	  icon = "INV_Misc_Bone_HumanSkull_01",
	  cmd = { "/rts skull" },    d = "skull on your target: everyone onto it" },
	{ id = "moon",   g = "Party", name = "Moon", raw = true,
	  icon = "Spell_Nature_Polymorph",
	  cmd = { "/rts moon" },     d = "moon on your target: keep it controlled" },
	{ id = "reset",  g = "Party", name = "Reset party", raw = true,
	  icon = "INV_Misc_PocketWatch_01",
	  cmd = { "/rts reset" },    d = "factory behaviour for everyone" },
	{ id = "control", g = "Party", name = "Control", raw = true,
	  icon = "Spell_Shadow_Possession", art = "control",
	  cmd = { "/rts swap" },     d = "you BECOME whoever you have selected" },

	-- --- OUR OWN WINDOWS, THE CAMERA AND THE DOOR -----------------------
	--
	-- LEAVING AS A SLOT CARRIES A DANGER, which is why it is written down: RTS
	-- mode hides the action bars, so if the player does not put "RTS mode" in a
	-- slot, the only way out is the key binding or `/rts mode`.
	{ id = "bags",   g = "Windows", name = "Bags", raw = true,
	  icon = "INV_Misc_Bag_09", art = "bolsas",
	  cmd = { "/rts bags" },     d = "the bags of the WHOLE party" },
	{ id = "quests", g = "Windows", name = "Quests", raw = true,
	  icon = "INV_Misc_Book_09",
	  cmd = { "/rts quests" },   d = "the quest log of the WHOLE party" },
	{ id = "lock",   g = "Windows", name = "Lock", raw = true,
	  icon = "INV_Misc_Key_03", art = "candado",
	  cmd = { "/rts fc lock" },  d = "pins the camera to your hero",
	  cmd2 = { "/rts fc eyes" },
	  d2 = "puts the camera above the hero, facing his way, and attaches it" },
	{ id = "camera", g = "Windows", name = "Camera", raw = true,
	  icon = "INV_Misc_Spyglass_03",
	  cmd = { "/rts fc home" },  d = "brings the camera back over your hero" },
	-- `/rts mode` AND NOT BARE `/rts`: the naked command prints the HELP --
	-- sixty lines of chat -- and does not touch the mode.
	{ id = "mode",   g = "Windows", name = "RTS mode", raw = true,
	  icon = "Spell_ChargeNegative",
	  cmd = { "/rts mode" },     d = "enter and leave RTS mode" },
}

A.LIST = LIST

local byId = {}
for _, e in ipairs(LIST) do byId[e.id] = e end

-- === THE IDS WERE RENAMED AND THE SAVED SLOTS DID NOT NOTICE ============
--
-- These ids were Spanish until the file was translated, and they are the exact
-- string sitting in `RTSCommandDB.tray` on every machine that has ever
-- configured a slot. Renaming them without this map would have emptied the
-- player's tray into "that order is no longer in the catalogue" messages --
-- the failure the comment on `id` warns about, committed by the person who
-- wrote the warning.
--
-- So the old names keep resolving, forever, and cost one table lookup on a
-- path that only runs on a click. There is no migration pass rewriting the
-- saved data: a rewrite can only run outside combat, has to be guarded, and
-- buys nothing that this does not.
local OLD_IDS = {
	invitar  = "invite",
	sigueme  = "follow",
	quieto   = "hold",
	reunir   = "rally",
	craneo   = "skull",
	luna     = "moon",
	bolsas   = "bags",
	misiones = "quests",
	candado  = "lock",
	camara   = "camera",
	modo     = "mode",
	-- `reset` and `control` were already the same word in both languages.
}

function A:Find(id)
	if not id then return nil end
	return byId[id] or byId[OLD_IDS[id] or ""] or nil
end

-- Returns the path and WHETHER IT IS OURS, which is what decides the cropping.
function A:Texture(entry)
	if not entry then return nil, false end
	if entry.art then return ART_DIR .. entry.art .. ".tga", true end
	return ICON_DIR .. (entry.icon or "INV_Misc_QuestionMark"), false
end

-- Paints an order's icon onto a texture that already exists. In one place
-- because the slot and the dropdown both want it, and the cropping is the part
-- that gets forgotten.
function A:Paint(tex, entry)
	local path, mine = self:Texture(entry)
	tex:SetTexture(path or "")
	if mine then
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	tex:SetVertexColor(1, 1, 1)
	tex:SetAlpha(1)
end

--- Firing them ------------------------------------------------------------
--
-- Dispatched BY HAND rather than searched for across all of `SlashCmdList`.
-- There are three commands, all of them ours, and a generic search would let
-- lines into the catalogue that look like they work and do not -- `/cast`, for
-- one, which is protected and cannot be fired from here even once found.

-- Where a bot order goes out. It is the same string `Macros.lua` uses to
-- recognise its own macros, which is why it is not written loose in each place.
local MARK = "/rtscmd"

local RUNNER = {
	["/rts"]     = "RTSCOMMAND",
	["/rtscmd"]  = "RTSCMD",
	["/rtsc"]    = "RTSCMD",
	["/rtsall"]  = "RTSALL",
}

local function RunLine(line)
	line = strtrim(line or "")
	if line == "" then return end

	local verb, rest = line:match("^(%S+)%s*(.-)$")
	local key = RUNNER[(verb or ""):lower()]
	local fn = key and SlashCmdList[key]
	if not fn then
		ns.Print("|cffff0000orders:|r I do not know whose |cffffff00" ..
			tostring(verb) .. "|r that is. If it carries /cast or /use, it has " ..
			"to be a macro.")
		return
	end
	fn(rest or "")
end

-- AN ORDER'S LINES, IN ONE PLACE. Two paths want them -- firing it and writing
-- it into a macro -- and composing them twice is how you end up with a tray
-- that does one thing and a macro of the same name that does another.
local function Lines(entry, alt)
	local out = {}
	for _, c in ipairs((alt and entry.cmd2) or entry.cmd) do
		table.insert(out, entry.raw and c or (MARK .. " " .. c))
	end
	return out
end

function A:Run(id, alt)
	local e = self:Find(id)
	if not e then
		ns.Print("|cffff8800orders:|r that slot points at |cffffff00" ..
			tostring(id) .. "|r, which is no longer in the catalogue. " ..
			"Right-click it to change it.")
		return
	end
	-- Asking for the second order of something that has none does not fire the
	-- first one instead: the player asked for a different thing, and doing the
	-- one they did not ask for is worse than doing nothing. The caller has
	-- already checked whether it exists (`entry.cmd2`).
	if alt and not e.cmd2 then return end
	for _, line in ipairs(Lines(e, alt)) do RunLine(line) end
end

-- The written body: for the tooltip and for `Macros.lua`'s macros.
function A:Body(entry)
	return table.concat(Lines(entry), "\n")
end

--- Bringing the bots in ---------------------------------------------------
--
-- `.playerbots bot add <names>` is a SERVER command, not an addon one: it goes
-- out as if you had typed it in chat -- anything starting with a dot is handled
-- by the server and never actually gets said out loud. It is the same path the
-- selfbot in `RTSMode.lua` already uses, and there is no other way to do it:
-- the addon has no means of calling a GM command.
--
-- THE NAMES GO FLUSH AGAINST THE COMMAS, and this is not cosmetic.
-- mod-playerbots splits the list on commas (`split(charnameStr, ',')`, in
-- `PlayerbotMgr.cpp`) and does NOT strip spaces; the server then rejects any
-- name carrying one -- `normalizePlayerName` returns false the moment it sees
-- a space. So "Avy, Bob" adds Avy and silently drops Bob, and all you see is a
-- "Character ' Bob' not found" lost among the other replies. It is joined here
-- and cannot be typed wrong.
--
-- THE LIST BELONGS TO THE PLAYER and is saved per account, but it ships with
-- one already in it: a slot you have to configure before it does anything is a
-- slot that does nothing. `/rts invite list <names>` changes it without
-- touching this file.

local BOTS = { "Neferite", "Kirinah", "Avy", "Secretaria", "Bob" }

local function Roster()
	local saved = RTSCommandDB and RTSCommandDB.bots
	if type(saved) == "table" and #saved > 0 then return saved end
	return BOTS
end

-- Commas, spaces or both are fine: what separates names here is typed by a
-- person, not by a program.
local function SetRoster(text)
	local out = {}
	for name in tostring(text or ""):gmatch("[^%s,]+") do
		table.insert(out, name)
	end
	if #out == 0 or not RTSCommandDB then return nil end
	RTSCommandDB.bots = out
	return out
end

function A:Invite(rest)
	local sub, tail = strtrim(rest or ""):match("^(%S*)%s*(.-)$")

	sub = (sub or ""):lower()
	if sub == "list" or sub == "lista" then
		if strtrim(tail or "") ~= "" and not SetRoster(tail) then
			ns.Print("|cffff8800invite:|r I did not understand a single name there.")
			return
		end
		ns.Print("|cffffff00your bots|r: " .. table.concat(Roster(), ", "))
		ns.Print("Change them with |cffffff00/rts invite list <names>|r.")
		return
	end

	local names = table.concat(Roster(), ",")
	-- SAY WHO IS BEING CALLED, because the server's replies come back in
	-- English and out of order ("ok", "player already logged in", "not found")
	-- and without this line you cannot even tell who was being addressed.
	ns.Print("|cffffff00bringing|r: " .. table.concat(Roster(), ", "))
	SendChatMessage(".playerbots bot add " .. names, "SAY")
end

--- Bringing the party -----------------------------------------------------
--
-- Two orders that are really one: `summon` teleports them to your side and
-- `follow` takes their anchor off. See the catalogue for why they travel
-- together.
--
-- IT DOES NOT GO OUT THROUGH `/rtsall follow` but through the addon's own
-- path, which knows how to drop the drawn route and clear the "this one is
-- holding" mark. A bare `follow` said over chat leaves both of those in place,
-- and the next move order behaves as if the bot were still anchored.

function A:Bring()
	if not ns.Orders:SummonAll() then return end
	ns.Print("|cffffff00bring|r: the party at your side")
	ns.Orders:FollowAll()
end

--- The dropdown -----------------------------------------------------------
--
-- It is OURS and not the client's `UIDropDownMenu`, for two reasons you see
-- the moment you try: theirs cannot draw an icon on each line -- only text and
-- a check mark -- and its width and typeface are the game's, not this
-- console's.
--
-- IT CLOSES WHEN YOU CLICK OUTSIDE, and that means a screen-sized button
-- underneath the menu. It is the only way there is: a frame gets no
-- notification that someone clicked somewhere else.

-- IN PHYSICAL PIXELS, like everything hanging off the `Pixels` container. A
-- row of 22 would be right in screen units and here it is half a line of text:
-- the `small` font is 22 TALL. This is the trap `Widgets` warns about in its
-- header, and you pay it the moment you copy a number from another addon.
local ROW_H   = 30      -- height of one order
local HEAD_H  = 24      -- height of a group title
local MENU_W  = 250
local PAD     = 6

local menu, catcher, rows, heads
local pick                -- who to tell once something is chosen

local function Close()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end

A.Close = function(self) Close() end

function A:IsOpen()
	return menu and menu:IsShown() and true or false
end

local function Catcher()
	if catcher then return catcher end
	catcher = CreateFrame("Button", "RTSActionMenuCatcher", UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:SetFrameLevel(1)
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", Close)
	catcher:Hide()
	return catcher
end

-- One menu line. Icon on the left, name beside it: stacked vertically and with
-- twelve options, the picture is what the eye finds before the text.
local function Row(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(MENU_W)
	b:SetHeight(ROW_H)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(ROW_H - 6)
	b.icon:SetHeight(ROW_H - 6)
	b.icon:SetPoint("LEFT", b, "LEFT", 3, 0)

	b.label = ns.W:Text(b, ns.W.FONT.small)
	b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.label:SetJustifyH("LEFT")

	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	return b
end

local function Build()
	if menu then return end

	menu = CreateFrame("Frame", "RTSActionMenu", ns.Pixels:Host() or UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetFrameLevel(20)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	ns.Skin:Dress(menu)
	menu:Hide()

	menu.title = ns.W:Text(menu, ns.W.FONT.small)
	menu.title:SetJustifyH("LEFT")

	rows, heads = {}, {}
end

-- Places titles and lines in one pass and returns the total height.
local function Fill(current)
	local inset = ns.Skin:Inset()
	local y = inset
	local nr, nh = 0, 0

	-- BOTH TOP CORNERS, not top-left and a bare right: a FontString anchored by
	-- TOPLEFT and by RIGHT has to satisfy "my top edge here" and "my centre
	-- there" at the same time, and it resolves that by stretching.
	menu.title:ClearAllPoints()
	menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", inset + 2, -y)
	menu.title:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -inset, -y)
	y = y + HEAD_H + 2

	local group

	local function Place(f, h)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", menu, "TOPLEFT", inset, -y)
		f:Show()
		y = y + h
	end

	for _, e in ipairs(LIST) do
		if e.g ~= group then
			group = e.g
			nh = nh + 1
			local t = heads[nh]
			if not t then
				t = ns.W:Text(menu, ns.W.FONT.tiny)
				t:SetJustifyH("LEFT")
				heads[nh] = t
			end
			t:SetText("|cff88ccff" .. group .. "|r")
			Place(t, HEAD_H)
		end

		nr = nr + 1
		local b = rows[nr]
		if not b then
			b = Row(menu)
			rows[nr] = b
		end
		b.entry = e
		A:Paint(b.icon, e)
		-- THE ONE ALREADY IN THERE GETS MARKED. Without this, opening the menu
		-- over a full slot does not say what it holds, and the player changes it
		-- by accident believing it was empty.
		b.label:SetText((e.id == current and "|cffffd100" or "|cffffffff")
			.. e.name .. "|r")
		b:SetScript("OnClick", function(self)
			local fn = pick
			Close()
			if fn then fn(self.entry.id) end
		end)
		ns.W:Tip(b, e.name, e.d)
		Place(b, ROW_H)
	end

	-- CLEAR, ALWAYS LAST. Separated from the catalogue by a gap: it is not an
	-- order, it is the opposite of all of them.
	nr = nr + 1
	local clear = rows[nr]
	if not clear then
		clear = Row(menu)
		rows[nr] = clear
	end
	clear.entry = nil
	clear.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	clear.icon:SetTexCoord(0, 1, 0, 1)
	clear.label:SetText("|cffff8888Empty the slot|r")
	clear:SetScript("OnClick", function()
		local fn = pick
		Close()
		if fn then fn(false) end
	end)
	ns.W:Tip(clear, "Empty", "Leaves the slot free.")
	y = y + 4
	Place(clear, ROW_H)

	-- Leftovers from a previous time. They are hidden, not destroyed: a frame
	-- in 3.3.5a cannot be destroyed, and reusing them is the only thing that
	-- stops us manufacturing twelve every time the menu opens.
	for i = nr + 1, #rows do rows[i]:Hide() end
	for i = nh + 1, #heads do heads[i]:SetText("") end

	return y + inset
end

-- `anchor` is the slot. The menu opens to its LEFT and UPWARDS, which is where
-- there is room: the tray lives pinned to the bottom-right corner, so a menu
-- growing downwards would fall off the screen entirely. `SetClampedToScreen`
-- is the safety net for when it still does not fit.
function A:Open(anchor, title, current, onPick)
	if self:IsOpen() then
		Close()
		-- Clicking the SAME slot again closes it; a different one moves it.
		if menu.anchor == anchor then return end
	end

	-- THE SAVED ID MAY BE AN OLD ONE, and if it is not normalised here the
	-- highlight below silently stops working: a slot holding `candado` would
	-- open the menu with nothing marked, because the entry now calls itself
	-- `lock`. That is exactly the failure the comment on the highlight warns
	-- about -- "the player changes it by accident believing it was empty" --
	-- reintroduced by renaming the ids. `Find` already knows both spellings,
	-- so the fix is to ask it rather than to compare raw strings.
	local e = self:Find(current)
	current = e and e.id or current

	Build()
	pick = onPick
	menu.anchor = anchor
	menu.title:SetText("|cffffd100" .. (title or "Pick an order") .. "|r")

	local h = Fill(current)
	menu:SetWidth(MENU_W + ns.Skin:Inset() * 2)
	menu:SetHeight(h)
	menu:ClearAllPoints()
	menu:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -PAD, 0)

	Catcher():Show()
	menu:Show()
end

--- Saying it on screen ----------------------------------------------------
--
-- A TEXTURE THAT DOES NOT LOAD RAISES NO ERROR: it leaves the button blank. So
-- the only way to answer "some icons don't show up" is to ask the client about
-- them one by one, and that is what this does.
--
-- The oracle is the one from `/rts art scan`: you hand a hidden texture a path
-- and ask it back what it has. If it returns nil, the file is not where it
-- says. IT MAY NOT WORK -- in 3.3.5a it is not clear that `GetTexture()` tells
-- a good path from a bad one -- and that is why the report prints both
-- readings instead of one: if they all answer yes and there are still blank
-- slots, the oracle is lying and the cause is elsewhere.

local probe

local function Loads(path)
	if not probe then
		local f = CreateFrame("Frame")
		f:Hide()
		probe = f:CreateTexture(nil, "ARTWORK")
	end
	probe:SetTexture(nil)
	probe:SetTexture(path)
	return probe:GetTexture() and true or false
end

function A:Report()
	ns.Print("|cffffff00orders|r -- what fits in a tray slot:")

	local group, bad = nil, {}
	for _, e in ipairs(LIST) do
		if e.g ~= group then
			group = e.g
			ns.Print("  |cff88ccff" .. group .. "|r")
		end

		local path, mine = self:Texture(e)
		local ok = Loads(path)
		if not ok then table.insert(bad, { e = e, path = path }) end

		ns.Print(("    %s%-12s|r %s%s"):format(
			ok and "|cffffffff" or "|cffff4040", e.name, e.d,
			mine and "  |cff888888(our own icon)|r" or ""))
	end

	if #bad > 0 then
		ns.Print(("|cffff4040%d icon(s) do not load|r:"):format(#bad))
		for _, b in ipairs(bad) do
			ns.Print("    " .. b.path)
		end
		ns.Print("If it is one of |cffffff00ours|r: the addon has not been " ..
			"deployed, or the file is not named the same as the order's `art`.")
	else
		ns.Print("Every icon |cff00ff00answers yes|r.")
		ns.Print("If you still see a blank slot, it is the CLIENT: a texture it " ..
			"has already tried to load stays as it is for the whole session. " ..
			"|cffffff00Close WoW and come back in|r -- a /reload is not enough.")
	end

	ns.Print("They are set with |cffffff00right-click|r on a slot over on the right.")
end
