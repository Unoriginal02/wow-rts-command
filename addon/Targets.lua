--[[
	Targets.lua -- everything the group is engaged with, in one panel.

	Replaces the single-line "engaging" readout, which could only ever describe
	one thing while four units fought four different ones.

	Each row is something one of your units is pointed at: name, health, and a
	badge saying HOW MANY of your units are on it. Enemies and allies both --
	"who is my healer looking after" is the same question as "who is my warrior
	hitting", and server-side it is the same field, so a heal target appears
	here exactly like an attack target does.

	Clicking a row aims the bot you are commanding at it. That is what makes
	command mode usable: before this you could only cast at whatever the bot
	already happened to have selected, with no way to redirect it.

	=== why there are no portraits =========================================

	SetPortraitTexture needs a UNIT TOKEN, and a GUID only becomes a token if it
	is already your target, your mouseover, or in your party. Party members
	therefore DO get a real portrait; a wolf twenty yards away cannot, because
	the client will not give us a handle on it.

	So enemies get an icon by kind rather than a face. Being straight about that
	beats a row of identical question marks pretending to be avatars.
]]

local ADDON, ns = ...

local T = {}
ns.Targets = T

T.enabled = true
T.maxRows = 8

local ROW_H = 26
local WIDTH = 190

local frame, rows = nil, {}
local entries, pending = {}, {}

local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local ICON_HOSTILE  = "Interface\\Icons\\Ability_DualWield"
local ICON_FRIENDLY = "Interface\\Icons\\Spell_Holy_Heal"

--- Rows -------------------------------------------------------------------

local function GetRow(i)
	if rows[i] then return rows[i] end

	local r = CreateFrame("Button", "RTSTargetRow" .. i, frame)
	r:SetWidth(WIDTH - 16)
	r:SetHeight(ROW_H - 2)
	r:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -20 - (i - 1) * ROW_H)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetWidth(20)
	r.icon:SetHeight(20)
	r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)

	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
	r.bar:SetWidth(WIDTH - 70)
	r.bar:SetHeight(14)
	r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	r.bar:SetMinMaxValues(0, 100)

	r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetTexture(0, 0, 0, 0.6)

	r.label = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.label:SetPoint("LEFT", r.bar, "LEFT", 3, 0)

	-- How many of your units are on this one. The number that tells you at a
	-- glance whether anything is being ignored.
	r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	r.count:SetPoint("RIGHT", r, "RIGHT", -2, 0)

	r:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	r:SetScript("OnClick", function(self)
		if self.guid then T:Aim(self.guid, self.name) end
	end)

	rows[i] = r
	return r
end

--- Data -------------------------------------------------------------------

-- "hex,count,hp,hostile,isplayer,name" per entry, semicolon separated.
function T:OnData(list)
	for entry in list:gmatch("[^;]+") do
		local hex, count, hp, hostile, isplayer, name =
			entry:match("^(%x+),(%d+),(%d+),([01]),([01]),(.+)$")
		if hex then
			tinsert(pending, {
				guid = "0x" .. hex,
				hex = hex,
				count = tonumber(count),
				hp = tonumber(hp),
				hostile = hostile == "1",
				isPlayer = isplayer == "1",
				name = name,
			})
		end
	end
end

function T:OnDataEnd()
	entries = pending
	pending = {}
	self:Refresh()
end

function T:Refresh()
	if not frame then return end

	if not self.enabled or #entries == 0 then
		frame:Hide()
		return
	end

	local n = math.min(#entries, self.maxRows)
	for i = 1, n do
		local e = entries[i]
		local r = GetRow(i)
		r.guid, r.name = e.guid, e.name

		-- A party member is the one case where the client will hand us a real
		-- portrait, because it already has a unit token for them.
		local token = e.isPlayer and ns.Selection:UnitFor(e.name) or nil
		if token and UnitExists(token) then
			SetPortraitTexture(r.icon, token)
		else
			r.icon:SetTexture(e.hostile and ICON_HOSTILE or ICON_FRIENDLY)
		end

		r.bar:SetValue(e.hp)
		if e.hostile then
			r.bar:SetStatusBarColor(0.75, 0.15, 0.15)
		else
			r.bar:SetStatusBarColor(0.15, 0.65, 0.25)
		end

		r.label:SetText(e.name)
		r.count:SetText(e.count > 1 and ("|cffffff00x" .. e.count .. "|r") or "")
		r:Show()
	end

	for i = n + 1, #rows do rows[i]:Hide() end

	frame:SetHeight(24 + n * ROW_H)
	frame:Show()
end

--- Aiming -----------------------------------------------------------------

T.aimed = nil

function T:Aim(guid, name)
	if not ns.CommandMode.active or not ns.CommandMode.bot then
		ns.Print("Take command of a unit first (alt-click it).")
		return
	end

	self.aimed = guid
	ns.SendServer(("AIM %s %s"):format(ns.CommandMode.bot, tostring(guid):gsub("^0[xX]", "")))
	ns.Print(("|cffffff00%s|r -> %s"):format(ns.CommandMode.bot, name))
end

function T:ClearAim()
	self.aimed = nil
end

--- Lifecycle ---------------------------------------------------------------

function T:Create()
	frame = CreateFrame("Frame", "RTSTargetsFrame", UIParent)
	frame:SetWidth(WIDTH)
	frame:SetHeight(60)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.75)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		RTSCommandDB.targets = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("|cffaaaaaaObjetivos|r")

	local pos = RTSCommandDB and RTSCommandDB.targets
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -30, 60)
	end

	frame:Hide()
	self.frame = frame

	-- Polled rather than pushed: the server has no cheap way to notice "the
	-- group's target set changed", and twice a second is invisible to the eye
	-- while costing one small message.
	--
	-- On its own frame, not the panel's: the panel hides itself when there is
	-- nothing to show, and a hidden frame stops ticking -- so polling from it
	-- would mean the panel could never come back.
	local poller = CreateFrame("Frame")
	local acc = 0
	poller:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		if T.enabled and ns.Orders:HasServer()
		   and (ns.RTSMode.active or ns.CommandMode.active) then
			ns.SendServer("TGTS")
		end
	end)
	self.poller = poller

	if RTSCommandDB and type(RTSCommandDB.targetsOn) == "boolean" then
		self.enabled = RTSCommandDB.targetsOn
	end
end

function T:Toggle()
	self.enabled = not self.enabled
	if not self.enabled and frame then frame:Hide() end
	RTSCommandDB.targetsOn = self.enabled
	ns.Print("targets panel " .. (self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end
