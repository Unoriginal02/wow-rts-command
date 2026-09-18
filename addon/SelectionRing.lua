--[[
	SelectionRing.lua -- the selection ring under each unit.

	=== what changed, 2026-08-15 ============================================

	This file used to DRAW the ring: rts_core fired twelve rays down around each
	selected unit, published the heights, and Lua interpolated them into a few
	dozen soft dots. It was parked because it never read as a ring lying on the
	ground -- and it never could have. A UI texture is not depth-tested and is not
	drawn with the frame's own camera, so it always floats a little, always swims
	a little when you turn, and always draws over the hill it should be behind.

	The client has drawn exactly the right marker since 2004: the circle under
	whatever you have targeted. It is part of the scene, so it is occluded and
	drapes over slopes for free, and it is placed by the renderer itself, so it
	cannot lag the frame. Its only limit was that it asked "is this THE
	highlighted unit?" against one global guid -- one unit at a time.

	The client keeps those circles as two guid slots and drains them once a
	frame -- resolve the unit, draw its circle, clear the slot. rts_core hooks
	that drain (Circle.cpp): the client's own two are drawn as usual, then our
	units are fed through the same call one at a time. Nothing is drawn here any
	more. This file just owns the flags Channel.lua packs into bits 27-29, and
	makes sure the client's own circle is switched on.

	Colour follows the client's, for now: reusing its draw path means taking the
	colour it picks. The state colours still reach the model glow (bit 28).

	The terrain sampler in GroundRing.cpp is left in the DLL but is no longer
	called by anything. It solved by hand -- twelve raycasts per unit per tick --
	the one problem the native circle does not have.

	Colours come from State.lua, unchanged:
	  blue selected . green moving . red combat . orange interacting
]]

local ADDON, ns = ...

local R = {}
ns.SelectionRing = R

-- Bumping `version` discards settings saved under the old defaults. Done here
-- because `enabled` flips meaning: it used to turn on a Lua dot ring that was
-- off for good reason, and now turns on the native circle, which is the point.
--
-- TO 4 ON 2026-09-18, AND THIS TIME IT IS `modelTint` THAT CHANGES DEFAULT: the
-- glow goes ON. It was born off because the circle was meant to be the marker
-- and the glow the extra, and in game that is backwards -- the circle is under
-- the unit, which from an RTS camera is exactly where the grass and the slope
-- are, and it is the same grey the client puts under your target. The glow is
-- on the model, in the state's own colour, and it is what actually answers
-- "which ones are mine" at a glance.
--
-- The bump is not decoration. `Create` only reads the saved table when the
-- version matches, so without it anybody who has ever entered RTS mode carries
-- the old `modelTint = false` saved and would never see this change, looking
-- for the fault in code that is already doing what it says.
R.version = 4
R.enabled = true
R.modelTint = true

-- UNA PASADA POR UNIDAD, Y NO HAY MANDO PARA CAMBIARLO. Duro una tarde y lo
-- desmintio el juego en el primer vistazo.
--
-- La idea era que dos pasadas del MISMO dibujo darian un aro mas marcado, que
-- es lo que parecia la seleccion del mundo cuando se apilaba con la nuestra.
-- En pantalla no da un aro mas marcado: **da DOS AROS**. Las dos pasadas no
-- caen una encima de otra.
--
-- Se anota aqui y no se deja el interruptor puesto porque un ajuste cuyo unico
-- valor alternativo esta comprobado que se ve mal no es un ajuste, es una
-- trampa -- y ademas el bit 30 del canal vuelve a estar libre, asi que dejarlo
-- entendido al otro lado seria plantar el fallo para quien lo reutilice.

-- Diagnostic only, never saved: makes the DLL give EVERY unit it renders a
-- circle in one colour. If the world fills with rings, the patched gate is
-- understood correctly and any remaining problem is in the selection, not in
-- the hook. Deliberately not persisted -- it is not a mode to be left on.
R.testAll = false

-- The client will not draw a circle for anyone, us included, while this is 0.
-- It is on by default in a stock client; a UI addon or a stray /console can
-- have turned it off, and the symptom -- no circles, no error -- is confusing
-- enough to be worth ruling out on every login.
local CIRCLE_CVAR = "ObjectSelectionCircle"

local function EnsureCVar()
	if GetCVar(CIRCLE_CVAR) == "0" then
		SetCVar(CIRCLE_CVAR, "1")
		ns.Print(("|cffffff00%s|r was off -- switched on, or nothing gets a circle.")
			:format(CIRCLE_CVAR))
	end
end

function R:Create()
	local s = RTSCommandDB and RTSCommandDB.ring
	if type(s) == "table" and s.version == self.version then
		if type(s.enabled) == "boolean" then self.enabled = s.enabled end
		if type(s.modelTint) == "boolean" then self.modelTint = s.modelTint end
		-- `bright` vivio unas horas del 2026-09-06 y se tira al leer. Un fichero
		-- de SavedVariables no olvida ninguna clave y sobrevive a la version que
		-- la escribio; sin esto, quien la tuviera guardada seguiria mandando el
		-- bit 30 que ya no significa nada. Sexta purga de este addon.
		if s.bright ~= nil then s.bright = nil end
	end
	EnsureCVar()
end

function R:Save()
	RTSCommandDB.ring = {
		version = self.version,
		enabled = self.enabled,
		modelTint = self.modelTint,
	}
end

-- Both toggles reach the DLL through Channel.lua, which only writes the CVar
-- when the packed value changes -- so flipping either one takes effect on the
-- next channel tick without anything having to be nudged.

function R:Toggle()
	self.enabled = not self.enabled
	self:Save()
	if self.enabled then EnsureCVar() end
	ns.Print("ground selection circles " ..
		(self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

function R:ToggleTint()
	self.modelTint = not self.modelTint
	self:Save()
	ns.Print("model glow " .. (self.modelTint and "|cff00ff00ON|r" or "|cffff0000OFF|r")
		.. " - the character painted in the colour of what he is doing. ON by " ..
		"default; switching it off leaves only the circle on the ground.")
end

function R:ToggleTest()
	self.testAll = not self.testAll
	if self.testAll then
		ns.Print("|cffff00ffcircle test ON|r - every unit the DLL publishes should now")
		ns.Print("wear a circle, selected or not. If they do, the hook works and any")
		ns.Print("remaining problem is in the selection. |cffffff00/rts ring test|r to stop.")
	else
		ns.Print("circle test |cffff0000OFF|r")
	end
end

function R:Status()
	ns.Print(("circles %s, model glow %s, %s=%s"):format(
		self.enabled and "|cff00ff00on|r" or "|cffff0000off|r",
		self.modelTint and "|cff00ff00on|r" or "|cffff0000off|r",
		CIRCLE_CVAR, tostring(GetCVar(CIRCLE_CVAR))))
	ns.Print("El circulo nativo de tu objetivo se apaga cuando el objetivo es un " ..
	         "JUGADOR y hay algo seleccionado; una criatura conserva el suyo.")
	if RTS_PROTO and RTS_PROTO ~= 3 then
		ns.Print(("|cffff0000rts_core speaks protocol %s|r - circles need protocol 3. " ..
			"Re-inject the current rts_core.dll."):format(tostring(RTS_PROTO)))
	elseif RTS_Ready ~= 1 then
		ns.Print("|cffff0000rts_core is not injected|r - the circle is drawn by the DLL.")
	end
end
