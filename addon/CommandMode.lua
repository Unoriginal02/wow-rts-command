--[[
	CommandMode.lua -- borrowing one bot's spellbook for a few seconds.

	Select a bot, its action bar appears, you cast through it, and after a few
	seconds of not using it the bot goes back to what it was doing. Enough to
	drop an emergency heal on the tank without ceasing to be the director.

	=== why this is not possession =========================================

	Full possession (alt-click) hands you the character: camera swings to it,
	third person, control transferred, and all of that torn back down when you
	are finished. That is right for "I want to BE this character for a while"
	and completely wrong for three seconds of healing.

	Command mode charms nothing. No client control changes hands, so the camera
	never moves and you never leave RTS mode. The spells are cast by the SERVER,
	as that bot, on your instruction.

	=== where the bar comes from ===========================================

	The bot's own action bars, out of character_action -- the ones you arranged
	when you last logged in as that character.

	This is better than listing its whole spellbook: a level 80 spellbook is
	long, unordered, and full of things you would never click. The bars are
	already curated, already in your preferred order, and configuring a bot's
	command bar is just "play them for five minutes and set your bars".

	Worth knowing: mod-playerbots never reads action bars to choose what to cast
	(verified -- only shaman totems touch them, and only as storage). So
	arranging them changes nothing about the bot's own rotation. They are purely
	a record of your preference, which is exactly what makes them safe to borrow.

	The wire carries only spell IDs. The client turns each into a name and icon
	itself with GetSpellInfo, so a full bar costs a couple of hundred bytes.

	=== why this is a panel and not your real action bar ===================

	Two walls, and both are the client's.

	Your own action buttons can only hold spells YOU know -- there is no way to
	put another character's spell on your bar, because the button stores a spell
	id the client then validates against your own spellbook.

	The bar you actually see in RTS mode is not yours at all: it is the CAMERA
	creature's possess bar. Player::PossessSpellInitialize builds it from the
	charmed unit's CharmInfo (Player.cpp:9816), and an Invisible Stalker knows
	nothing, so it comes out empty. That empty bar could be FILLED with the
	bot's spells easily enough -- but clicking one sends CMSG_PET_ACTION, and
	the server would then try to cast it from the camera creature, which does
	not know it. Redirecting that to the bot needs a hook inside
	WorldSession::HandlePetActionHelper, and there is no module hook there --
	only a core patch, which this project deliberately avoids.

	So: our own panel, placed where the empty possess bar sits, with the number
	keys bound to it while it is up. As close to the real thing as the client
	allows without patching it.
]]

local ADDON, ns = ...

local M = {}
ns.CommandMode = M

M.active = false
M.bot = nil

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local PER_ROW = 12

local frame, buttons, title = nil, {}, nil
local pending = {}      -- spell ids arriving in chunks

--- Frame -------------------------------------------------------------------

local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function GetButton(i)
	if buttons[i] then return buttons[i] end

	local b = CreateFrame("Button", "RTSCommandSpell" .. i, frame)
	b:SetWidth(BUTTON_SIZE)
	b:SetHeight(BUTTON_SIZE)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	b:SetScript("OnClick", function(self)
		if self.spellId then M:Cast(self.spellId) end
	end)
	b:SetScript("OnEnter", function(self)
		if not self.spellId then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetHyperlink("spell:" .. self.spellId)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	buttons[i] = b
	return b
end

function M:Create()
	frame = CreateFrame("Frame", "RTSCommandBar", UIParent)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.8)
	frame:SetWidth(200)
	frame:SetHeight(BUTTON_SIZE + 34)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		RTSCommandDB.cmdBar = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -7)

	local pos = RTSCommandDB and RTSCommandDB.cmdBar
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		-- Over the main action bar, which in RTS mode is the camera's empty
		-- possess bar anyway -- so this lands where your bar would have been.
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20)
	end

	frame:Hide()
	self.frame = frame

	-- The focus readout only earns its place here, where attention is on one
	-- character. Ask the server what that bot is pointed at while we are using
	-- it; twice a second is enough for a readout nobody is reading closely.
	local acc = 0
	frame:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		if M.active and M.bot then ns.SendServer("FOCUS " .. M.bot) end
	end)
end

--- Bar building ------------------------------------------------------------

function M:SetSpells(ids)
	local n = 0
	for _, id in ipairs(ids) do
		local name, _, icon = GetSpellInfo(id)
		-- A spell the client cannot resolve is not worth a blank button.
		if name and icon then
			n = n + 1
			local b = GetButton(n)
			b.spellId = id
			b.icon:SetTexture(icon)
			b:ClearAllPoints()
			local row = math.floor((n - 1) / PER_ROW)
			local col = (n - 1) % PER_ROW
			b:SetPoint("TOPLEFT", frame, "TOPLEFT",
				10 + col * (BUTTON_SIZE + BUTTON_GAP),
				-24 - row * (BUTTON_SIZE + BUTTON_GAP))
			b:Show()
		end
	end

	for i = n + 1, #buttons do buttons[i]:Hide() end

	local cols = math.min(n, PER_ROW)
	local rows = math.max(1, math.ceil(n / PER_ROW))
	frame:SetWidth(math.max(200, 20 + cols * (BUTTON_SIZE + BUTTON_GAP)))
	frame:SetHeight(30 + rows * (BUTTON_SIZE + BUTTON_GAP))

	if n == 0 then
		ns.Print(("|cffffff00%s has no usable spells on its action bars.|r"):format(
			tostring(self.bot)))
		ns.Print("Log in as that character and arrange its bars - that is where this comes from.")
	end
end

--- Channel -----------------------------------------------------------------

-- Spell ids arrive in chunks because one addon message caps at 255 characters.
function M:OnBars(bot, list)
	if bot ~= self.bot then return end
	if list == "-" then pending = {} return end

	for id in list:gmatch("[^,]+") do
		local n = tonumber(id)
		if n then tinsert(pending, n) end
	end
end

function M:OnBarsEnd(bot)
	if bot ~= self.bot then return end
	self:SetSpells(pending)
	pending = {}
end

function M:Cast(spellId)
	if not self.active or not self.bot then return end

	-- Whatever you last clicked in the targets panel. Without one the server
	-- falls back to the bot's own selection, which for a healer is usually who
	-- it was already helping -- fine as a default, useless as the only option,
	-- which is why the panel exists.
	local aim = ns.Targets and ns.Targets.aimed
	if aim then
		ns.SendServer(("CAST %s %d %s"):format(self.bot, spellId,
			tostring(aim):gsub("^0[xX]", "")))
	else
		ns.SendServer(("CAST %s %d"):format(self.bot, spellId))
	end
end

--- Number keys ------------------------------------------------------------
-- 1..9 and 0 fire the first ten buttons while command mode is up, then hand the
-- keys straight back. Same borrow-and-restore pattern as the camera's Q/E, and
-- never saved, so a crash or reload cannot strand your real bindings.
--
-- These are your ACTION BAR keys, which in RTS mode are driving the camera's
-- empty possess bar anyway -- so there is nothing to lose while they are ours.
-- If you have bound 1-4 to control groups, command mode borrows those too and
-- gives them back on exit.

local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local savedKeys = {}

function RTSCommand_CommandSlot(i)
	local b = buttons[i]
	if b and b.spellId and M.active then M:Cast(b.spellId) end
end

local function GrabKeys()
	if InCombatLockdown() then
		ns.Print("|cffffff00Number keys unavailable in combat|r - click the buttons instead.")
		return
	end
	for i, key in ipairs(KEYS) do
		savedKeys[key] = GetBindingAction(key) or ""
		SetBinding(key, "RTSCOMMAND_SLOT" .. i)
	end
end

local function ReleaseKeys()
	if not next(savedKeys) then return end
	if InCombatLockdown() then return end
	for key, was in pairs(savedKeys) do
		if was == "" then SetBinding(key) else SetBinding(key, was) end
	end
	savedKeys = {}
end

--- Enter / leave -----------------------------------------------------------

function M:Enter(botName)
	if not ns.Orders:HasServer() then
		ns.Print("|cffffff00Command mode needs mod-rts.|r")
		return
	end
	if not botName then
		ns.Print("Select one unit first, then |cffffff00/rts command|r.")
		return
	end

	self.active = true
	self.bot = botName
	pending = {}

	title:SetText("|cff33ccffCommanding|r " .. botName)
	frame:Show()
	GrabKeys()
	ns.SendServer("BARS " .. botName)

	ns.Print(("|cff00ff00Command mode|r - |cffffff00%s|r. Click a spell to cast it as them."):format(botName))
	ns.Print("Keys |cffffff001-0|r fire the first ten. They carry on by themselves a few seconds after you stop.")
end

function M:Leave()
	if not self.active then return end
	self.active = false
	self.bot = nil
	pending = {}
	ReleaseKeys()
	if frame then frame:Hide() end
	ns.Focus:Clear()
	if ns.Orders:HasServer() then ns.SendServer("UNCOMMAND") end
	ns.Print("|cffff0000Command mode off|r")
end

function M:Toggle()
	if self.active then
		self:Leave()
		return
	end

	-- One unit, and not your own character: you already control that directly.
	local sel = ns.Selection:Get()
	if #sel ~= 1 then
		ns.Print("Select exactly ONE unit to command.")
		return
	end
	if sel[1] == UnitName("player") then
		ns.Print("That is your own character - you already have its bars.")
		return
	end
	self:Enter(sel[1])
end
