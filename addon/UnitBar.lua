--[[
	UnitBar.lua -- the RTS unit row.

	One portrait per commandable group member. Click selects, shift/ctrl-click
	adds to selection. This is the stand-in for drag-box selection until
	rts_core.dll can project world positions to screen.
]]

local ADDON, ns = ...

local UB = {}
ns.UnitBar = UB

local MAX_BUTTONS = 8
local BTN_SIZE = 46
local BTN_GAP = 6

local buttons = {}
local frame

local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

--- Button construction -----------------------------------------------------

local function CreateButton(index, parent)
	local b = CreateFrame("Button", "RTSUnitButton" .. index, parent)
	b:SetWidth(BTN_SIZE)
	b:SetHeight(BTN_SIZE + 10)

	b.portrait = b:CreateTexture(nil, "ARTWORK")
	b.portrait:SetWidth(BTN_SIZE - 6)
	b.portrait:SetHeight(BTN_SIZE - 6)
	b.portrait:SetPoint("TOP", b, "TOP", 0, -3)

	-- Class-coloured frame around the portrait.
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetPoint("TOPLEFT", b.portrait, "TOPLEFT", -2, 2)
	b.border:SetPoint("BOTTOMRIGHT", b.portrait, "BOTTOMRIGHT", 2, -2)
	b.border:SetTexture("Interface\\Buttons\\WHITE8X8")

	-- Selection glow.
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetPoint("TOPLEFT", b.portrait, "TOPLEFT", -3, 3)
	b.glow:SetPoint("BOTTOMRIGHT", b.portrait, "BOTTOMRIGHT", 3, -3)
	b.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	b.glow:SetBlendMode("ADD")
	b.glow:Hide()

	b.health = CreateFrame("StatusBar", nil, b)
	b.health:SetWidth(BTN_SIZE - 6)
	b.health:SetHeight(5)
	b.health:SetPoint("TOP", b.portrait, "BOTTOM", 0, -2)
	b.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	b.health:SetMinMaxValues(0, 1)

	b.healthBG = b.health:CreateTexture(nil, "BACKGROUND")
	b.healthBG:SetAllPoints()
	b.healthBG:SetTexture(0, 0, 0, 0.6)

	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("TOP", b.health, "BOTTOM", 0, -1)
	b.label:SetWidth(BTN_SIZE + 8)

	-- Index badge, so hotkeys are discoverable.
	b.index = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	b.index:SetPoint("TOPLEFT", b.portrait, "TOPLEFT", 2, -2)
	b.index:SetText(index)

	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		if not self.unitName then return end

		if button == "RightButton" then
			-- Right-click a portrait targets that unit, handy before Attack.
			TargetUnit(self.unitName)
			return
		end

		if IsShiftKeyDown() or IsControlKeyDown() then
			ns.Selection:Toggle(self.unitName)
		else
			ns.Selection:SelectOnly(self.unitName)
		end
	end)

	b:SetScript("OnEnter", function(self)
		if not self.unitName then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.unitName)
		GameTooltip:AddLine("Click to select", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Shift-click to add to selection", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click to target", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return b
end

--- Layout ------------------------------------------------------------------

function UB:Create()
	if frame then return frame end

	frame = CreateFrame("Frame", "RTSUnitBar", UIParent)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetHeight(BTN_SIZE + 34)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		RTSCommandDB.unitBar = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	for i = 1, MAX_BUTTONS do
		buttons[i] = CreateButton(i, frame)
		if i == 1 then
			buttons[i]:SetPoint("LEFT", frame, "LEFT", 10, 4)
		else
			buttons[i]:SetPoint("LEFT", buttons[i - 1], "RIGHT", BTN_GAP, 0)
		end
	end

	local pos = RTSCommandDB.unitBar
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", -170, 190)
	end

	ns.Selection:Subscribe(function() UB:Refresh() end)

	-- Health/portrait polling. Cheap, and avoids wiring up a pile of events.
	local acc = 0
	frame:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.25 then return end
		acc = 0
		UB:UpdateVitals()
	end)

	self.frame = frame
	return frame
end

function UB:Refresh()
	if not frame then return end

	-- Your own character is in here too: in RTS mode it is a unit like any
	-- other, so it needs a portrait to click like any other.
	local roster = ns.Selection:GetRosterWithPlayer()
	local count = math.min(#roster, MAX_BUTTONS)

	for i = 1, MAX_BUTTONS do
		local b = buttons[i]
		local m = roster[i]

		if m then
			b.unitName = m.name
			b.unit = m.unit
			b:Show()

			SetPortraitTexture(b.portrait, m.unit)
			b.label:SetText(m.name)

			local _, class = UnitClass(m.unit)
			local c = class and RAID_CLASS_COLORS[class]
			if c then
				b.border:SetTexture(c.r, c.g, c.b, 1)
				b.health:SetStatusBarColor(c.r, c.g, c.b)
			else
				b.border:SetTexture(0.4, 0.4, 0.4, 1)
				b.health:SetStatusBarColor(0.4, 0.8, 0.4)
			end

			if ns.Selection:IsSelected(m.name) then b.glow:Show() else b.glow:Hide() end
		else
			b.unitName, b.unit = nil, nil
			b:Hide()
		end
	end

	frame:SetWidth(math.max(count, 1) * (BTN_SIZE + BTN_GAP) + 16)
	UB:UpdateVitals()
end

function UB:UpdateVitals()
	for i = 1, MAX_BUTTONS do
		local b = buttons[i]
		if b.unit and UnitExists(b.unit) then
			local max = UnitHealthMax(b.unit)
			local frac = (max > 0) and (UnitHealth(b.unit) / max) or 0
			b.health:SetValue(frac)

			-- Grey out the dead.
			if UnitIsDeadOrGhost(b.unit) then
				b.portrait:SetVertexColor(0.4, 0.4, 0.4)
			else
				b.portrait:SetVertexColor(1, 1, 1)
			end
		end
	end
end

function UB:Toggle()
	if not frame then return end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
