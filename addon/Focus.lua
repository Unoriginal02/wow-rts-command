--[[
	Focus.lua -- what the group is currently fighting.

	WoW's own target frame cannot be used for this, and not for want of trying.
	The server sets its side of the target with Player::SetSelection -- that is
	the field mod-playerbots reads, and it is why the attack order works at all
	-- but the frame you SEE is driven by your client's own selection, which
	only changes when your client sends CMSG_SET_SELECTION. There is no packet
	to push a target down to a client in 3.3.5a, and the Lua targeting functions
	are protected.

	So the focus gets its own readout, and the name comes from the server on the
	attack reply -- the only side that can turn a guid into a name here.

	WHAT THIS IS FOR. Not "keeping your own target free": in RTS mode there is
	no separate you. You are the director, and the character you logged in with
	is another unit under command, exactly like the bots. Nobody has a personal
	target to protect.

	In global RTS mode this readout is close to noise, because every unit can be
	fighting something different and one line cannot say that. It earns its
	place in COMMAND MODE, where attention is on one borrowed character and
	"what is this one hitting or healing" is the question you actually have.
	Hidden by default in RTS mode for that reason.
]]

local ADDON, ns = ...

local F = {}
ns.Focus = F

F.holdTime = 12        -- seconds before a stale focus fades out

local frame, label, count
local setAt = 0

local BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function F:Create()
	frame = CreateFrame("Frame", "RTSFocusFrame", UIParent)
	frame:SetWidth(200)
	frame:SetHeight(44)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.25, 0, 0, 0.75)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		RTSCommandDB.focus = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	local pos = RTSCommandDB and RTSCommandDB.focus
	if pos then
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", frame, "TOP", 0, -6)
	title:SetText("|cffaaaaaaEngaging|r")

	label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOP", title, "BOTTOM", 0, -3)

	count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)

	frame:Hide()

	-- Nothing tells us when a fight ends -- the name is all the server sends --
	-- so the readout times out rather than lying about a corpse.
	local acc = 0
	frame:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		if setAt > 0 and (GetTime() - setAt) > F.holdTime then F:Clear() end
	end)

	self.frame = frame
end

function F:Set(name, units)
	if not frame then return end
	if not name then self:Clear() return end

	-- SUPERSEDED 2026-08-15 by Targets.lua, which shows every target in the
	-- fight with a count on each instead of one line that can only ever
	-- describe one of them. Kept because it is the cheap readout if the panel
	-- is ever turned off, but silent while that panel is doing the job.
	if ns.Targets and ns.Targets.enabled then return end

	setAt = GetTime()
	label:SetText("|cffff8080" .. name .. "|r")
	count:SetText(("%d unit%s"):format(units or 0, (units == 1) and "" or "s"))
	frame:Show()
end

function F:Clear()
	setAt = 0
	if frame then frame:Hide() end
end

function F:Toggle()
	if not frame then return end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
