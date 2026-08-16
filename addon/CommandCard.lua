--[[
	CommandCard.lua -- WC3-style ability grid for the current selection.

	A 4x3 grid of orders. Buttons grey out when nothing is selected, so the
	card doubles as the selection indicator. The formation button opens a
	flyout because formation is group-wide rather than per-selection.
]]

local ADDON, ns = ...

local CC = {}
ns.CommandCard = CC

local COLS, ROWS = 4, 3
local BTN = 36
local GAP = 4

local frame, buttons, header, flyout

local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

--- Cast prompt -------------------------------------------------------------

StaticPopupDialogs["RTSCOMMAND_CAST"] = {
	text = "Cast which spell? (exact spell name)",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 64,
	OnAccept = function(self)
		local box = self.editBox or getglobal(self:GetName() .. "EditBox")
		ns.Orders:Cast(box:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		ns.Orders:Cast(self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

--- Order table -------------------------------------------------------------
-- needsSelection=false marks orders that work without a selection.

local ORDERS = {
	{ name = "Move",     icon = "Interface\\Icons\\Ability_Warrior_Charge",
	  tip = "Move to position.\nRallies to you until rts_core.dll adds click-to-move.",
	  fn = function() ns.Orders:MoveToCursor() end },

	{ name = "Hold",     icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	  tip = "Hold position. Bots stop following and stand their ground.",
	  fn = function() ns.Orders:Hold() end },

	{ name = "Follow",   icon = "Interface\\Icons\\Ability_Rogue_Sprint",
	  tip = "Resume following you.",
	  fn = function() ns.Orders:Follow() end },

	{ name = "Attack",   icon = "Interface\\Icons\\Ability_Warrior_Cleave",
	  tip = "Attack your current target.",
	  fn = function() ns.Orders:Attack() end },

	{ name = "Pull",     icon = "Interface\\Icons\\Ability_Marksmanship",
	  tip = "Pull your current target back to the group.",
	  fn = function() ns.Orders:Pull() end },

	{ name = "Tank",     icon = "Interface\\Icons\\Ability_Defend",
	  tip = "Tanks pick up your target.",
	  fn = function() ns.Orders:TankAttack() end },

	{ name = "Max DPS",  icon = "Interface\\Icons\\Ability_Warrior_InnerRage",
	  tip = "Burn cooldowns.",
	  fn = function() ns.Orders:MaxDPS() end },

	{ name = "Flee",     icon = "Interface\\Icons\\Ability_Rogue_Feint",
	  tip = "Break off and flee.",
	  fn = function() ns.Orders:Flee() end },

	{ name = "Grind",    icon = "Interface\\Icons\\INV_Sword_04",
	  tip = "Free-roam and grind mobs nearby.",
	  fn = function() ns.Orders:Grind() end },

	{ name = "Formation", icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
	  tip = "Pick a group formation.", needsSelection = false,
	  fn = function(self) CC:ToggleFlyout(self) end },

	{ name = "Cast",     icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
	  tip = "Make the selection cast a specific spell.",
	  fn = function() StaticPopup_Show("RTSCOMMAND_CAST") end },

	{ name = "Clear",    icon = "Interface\\Icons\\Spell_ChargeNegative",
	  tip = "Clear selection.", needsSelection = false,
	  fn = function() ns.Selection:Clear() end },
}

--- Formation flyout --------------------------------------------------------

function CC:BuildFlyout()
	flyout = CreateFrame("Frame", "RTSFormationFlyout", frame)
	flyout:SetBackdrop(BACKDROP)
	flyout:SetBackdropColor(0, 0, 0, 0.9)
	flyout:SetWidth(96)
	flyout:SetFrameStrata("DIALOG")
	flyout:Hide()

	local list = ns.Orders.FORMATIONS
	local prev

	for i, name in ipairs(list) do
		local b = CreateFrame("Button", nil, flyout)
		b:SetWidth(80)
		b:SetHeight(18)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

		-- Explicit font string: a template-less Button has none of its own,
		-- so SetText alone would render nothing.
		local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", b, "LEFT", 6, 0)
		text:SetText(name)

		if prev then
			b:SetPoint("TOP", prev, "BOTTOM", 0, -1)
		else
			b:SetPoint("TOP", flyout, "TOP", 0, -8)
		end

		b:SetScript("OnClick", function()
			ns.Orders:Formation(name)
			flyout:Hide()
		end)

		prev = b
	end

	flyout:SetHeight(#list * 19 + 16)
end

function CC:ToggleFlyout(anchor)
	if not flyout then self:BuildFlyout() end

	if flyout:IsShown() then
		flyout:Hide()
	else
		flyout:ClearAllPoints()
		flyout:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
		flyout:Show()
	end
end

--- Construction ------------------------------------------------------------

function CC:Create()
	if frame then return frame end

	frame = CreateFrame("Frame", "RTSCommandCard", UIParent)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.7)
	frame:SetWidth(COLS * (BTN + GAP) + 16)
	frame:SetHeight(ROWS * (BTN + GAP) + 34)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		RTSCommandDB.commandCard = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	header:SetPoint("TOP", frame, "TOP", 0, -8)

	buttons = {}
	for i, order in ipairs(ORDERS) do
		local b = CreateFrame("Button", "RTSCommandButton" .. i, frame)
		b:SetWidth(BTN)
		b:SetHeight(BTN)

		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.icon:SetTexture(order.icon)
		-- Trim the icon border so it sits flush like an action button.
		b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + col * (BTN + GAP), -24 - row * (BTN + GAP))

		b.order = order
		b:SetScript("OnClick", function(self) self.order.fn(self) end)

		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.order.name)
			GameTooltip:AddLine(self.order.tip, 0.8, 0.8, 0.8, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)

		buttons[i] = b
	end

	local pos = RTSCommandDB.commandCard
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 190, 190)
	end

	ns.Selection:Subscribe(function() CC:Refresh() end)

	self.frame = frame
	return frame
end

function CC:Refresh()
	if not frame then return end

	local n = ns.Selection:Count()

	if n == 0 then
		header:SetText("|cff888888No selection|r")
	elseif n == 1 then
		header:SetText("|cff00ff00" .. ns.Selection:Single() .. "|r")
	else
		header:SetText(("|cff00ff00%d units|r"):format(n))
	end

	local enabled = n > 0
	for _, b in ipairs(buttons) do
		local needs = b.order.needsSelection ~= false
		if enabled or not needs then
			b:Enable()
			b.icon:SetVertexColor(1, 1, 1)
		else
			b:Disable()
			b.icon:SetVertexColor(0.35, 0.35, 0.35)
		end
	end
end

function CC:Toggle()
	if not frame then return end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
