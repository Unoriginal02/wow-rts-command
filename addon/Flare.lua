--[[
	Flare.lua -- the "go here" marker.

	A brief pulse on the ground where you just sent someone, so an order has a
	visible result even when the units are off-screen or slow to start.

	This is drawn by the addon, not the server, and that is a deliberate
	reversal of the reasoning used for selection rings.

	A ring at a unit's feet has to be CORRECT: it sits there permanently, next
	to a model, and any error reads as broken. That is why it needs sampled
	terrain, and why two attempts at it were thrown away.

	A flare has to be roughly right for one second. It appears exactly where you
	clicked -- the cursor raycast gives the true ground point -- expands, fades,
	and is gone before anyone could notice it is not depth-tested. The server
	route (a DynamicObject) would have meant guessing at a SpellVisual id AND
	attaching an aura to keep it alive, which is two unknowns for something a
	quad and a timer do reliably.
]]

local ADDON, ns = ...

local F = {}
ns.Flare = F

F.enabled = true

-- Every one of these is a FEEL setting, and feel is not something that can be
-- derived -- it has to be looked at, adjusted, looked at again. So they are all
-- live-tunable from chat (/rts flare <key> <value>) and saved per character.
-- `/rts flare` on its own prints the whole set as one pasteable line.
--
-- Defaults as of 2026-08-16: down from a 2.2s flare that started at full size
-- and bloomed outward, which read as a blast going off rather than a marker
-- landing where you clicked, and was still sitting there while you gave the
-- next order.
F.OPTIONS = {
	-- key        default  min    max    description
	{ "time",       0.75,  0.05,  10,   "seconds from appearing to gone" },
	{ "size",       4.20,  0.20,  40,   "yards across at FULL size" },
	{ "start",      0.25,  0.01,   4,   "fraction of full size it opens FROM" },
	{ "hold",       0.25,  0.00,   1,   "fraction of its life at full brightness" },
	{ "alpha",      1.00,  0.05,   1,   "peak opacity" },
	{ "ease",       2.00,  0.10,   6,   "growth curve; 1 linear, higher snaps open faster" },
	{ "fade",       2.00,  0.10,   6,   "fade curve; 1 linear, higher lingers then drops" },
}

for _, o in ipairs(F.OPTIONS) do F[o[1]] = o[2] end

F.colours = {
	move   = { 0.25, 1.00, 0.40 },
	attack = { 1.00, 0.30, 0.15 },
}

local texture
local active = {}       -- { x, y, z, t0, colour }

local function Texture()
	if texture then return texture end
	local overlay = CreateFrame("Frame", "RTSFlareOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("BACKGROUND")

	texture = overlay:CreateTexture(nil, "ARTWORK")
	texture:SetTexture("Interface\\AddOns\\RTSCommand\\halo-01.tga")
	texture:SetBlendMode("ADD")
	texture:Hide()

	F.overlay = overlay
	return texture
end

-- Drop a flare at a world point. `kind` is "move" or "attack".
function F:Show(x, y, z, kind)
	if not self.enabled or not x then return end
	Texture()
	active = { x = x, y = y, z = z, t0 = GetTime(),
	           colour = self.colours[kind or "move"] or self.colours.move }
end

-- Mover el destello que ya esta puesto, sin reiniciar su desvanecido. Lo usa
-- la respuesta del servidor con el suelo de verdad: reiniciarlo haria un doble
-- parpadeo por cada click.
function F:Move(x, y, z)
	if not active.t0 or not x then return end
	active.x, active.y, active.z = x, y, z
end

function F:Update()
	local t = texture
	if not t then return end

	if not active.t0 then t:Hide() return end

	local age = GetTime() - active.t0
	if age >= self.time then
		active.t0 = nil
		t:Hide()
		return
	end

	local M = ns.Markers
	local sx, sy = M:Project(active.x, active.y, active.z)
	if not sx then t:Hide() return end

	local f = age / self.time

	-- Opens from `start` of full size up to full over its life. Eased rather
	-- than linear so it snaps open and then settles, instead of creeping outward
	-- at a constant rate for the whole flare.
	local grow = 1 - (1 - f) ^ self.ease
	local yards = self.size * (self.start + (1 - self.start) * grow)

	-- Perspective-correct: the same ground ellipse the cursor reticle uses, so
	-- the flare lies flat instead of facing the camera like a decal.
	local w, h = M:GroundEllipse(active.x, active.y, active.z, yards * 0.5)
	if not w then
		local depth = M:CamCoords(active.x, active.y, active.z)
		if not depth then t:Hide() return end
		w = M:YardsToPixels(yards, depth)
		h = w
	end
	if h < 2 then h = 2 end

	local c = active.colour
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	t:SetWidth(w)
	t:SetHeight(h)
	-- Fades on a curve rather than linearly: a linear fade reads as a light
	-- being switched off, this reads as a pulse dying away. It holds at full for
	-- the first `hold` of its life so that a short flare still registers instead
	-- of fading from the instant it appears.
	local a = self.alpha
	if f >= self.hold then
		a = a * (1 - (f - self.hold) / (1 - self.hold)) ^ self.fade
	end
	t:SetVertexColor(c[1], c[2], c[3], a)
	t:Show()
end

function F:Create()
	Texture()
	-- Restored key by key rather than wholesale, so a config saved before an
	-- option existed cannot leave that option nil and divide by it later.
	local cfg = RTSCommandDB and RTSCommandDB.flareCfg
	if type(cfg) == "table" then
		for _, o in ipairs(self.OPTIONS) do
			local v = tonumber(cfg[o[1]])
			if v then self[o[1]] = math.max(o[3], math.min(o[4], v)) end
		end
		if type(cfg.enabled) == "boolean" then self.enabled = cfg.enabled end
	elseif RTSCommandDB and type(RTSCommandDB.flare) == "boolean" then
		self.enabled = RTSCommandDB.flare   -- pre-config saved value
	end
	self.overlay:SetScript("OnUpdate", function() F:Update() end)
end

local function Option(key)
	for _, o in ipairs(F.OPTIONS) do
		if o[1] == key then return o end
	end
	return nil
end

-- Set one option. Clamped rather than rejected: a value out of range is far
-- more likely to be a misjudged guess than a mistake worth refusing, and
-- clamping shows you the edge of the range instead of just saying no.
function F:Set(key, value)
	local o = Option((key or ""):lower())
	local n = tonumber(value)
	if not o or not n then
		self:Status()
		return
	end

	local clamped = math.max(o[3], math.min(o[4], n))
	self[o[1]] = clamped
	self:Save()

	if clamped ~= n then
		ns.Print(("flare %s = %.2f |cffffff00(clamped from %.2f; range %.2f..%.2f)|r")
			:format(o[1], clamped, n, o[3], o[4]))
	else
		ns.Print(("flare %s = %.2f"):format(o[1], clamped))
	end
end

function F:Save()
	local cfg = {}
	for _, o in ipairs(self.OPTIONS) do cfg[o[1]] = self[o[1]] end
	cfg.enabled = self.enabled
	RTSCommandDB.flareCfg = cfg
end

function F:Reset()
	for _, o in ipairs(self.OPTIONS) do self[o[1]] = o[2] end
	self:Save()
	ns.Print("flare reset to defaults.")
	self:Status()
end

-- Prints the settings twice on purpose: once explained, once as a single line
-- that can be copied straight out of chat and pasted back to whoever is tuning
-- this. Reading seven values out of seven separate lines is how transcription
-- errors happen.
function F:Status()
	ns.Print("|cffffff00/rts flare <key> <value>|r - order marker settings:")
	local parts = {}
	for _, o in ipairs(self.OPTIONS) do
		local key, _, lo, hi, desc = o[1], o[2], o[3], o[4], o[5]
		ns.Print(("  |cff33ccff%-6s|r %6.2f   (%.2f..%.2f)  %s")
			:format(key, self[key], lo, hi, desc))
		table.insert(parts, ("%s=%.2f"):format(key, self[key]))
	end
	ns.Print("copy this line: |cff00ff00" .. table.concat(parts, " ") .. "|r")
	ns.Print("|cffffff00/rts flare reset|r restores defaults, |cffffff00/rts flare off|r hides it.")
end

function F:Toggle()
	self.enabled = not self.enabled
	self:Save()
	if not self.enabled and texture then texture:Hide() end
	ns.Print("order flare " .. (self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end
