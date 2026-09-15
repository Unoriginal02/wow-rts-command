--[[
	Tray.lua -- the right-hand tray: ten slots, the bags and the game buttons.

	  [M][M][M][M][M]
	  [M][M][M][M][M]
	  [keyring][bag][bag][bag][bag][backpack]
	  [char][spells][talents][quests][social][pvp][lfg][menu][help]

	=== A SLOT TAKES TWO THINGS, AND THEY ARE DIFFERENT ====================

	  RIGHT-CLICK -> the `Actions.lua` dropdown, with the addon orders and their
	  icons. They are not macros: they eat none of the 36 account slots and they
	  can wear our own art, which is what macros CANNOT -- a macro icon comes by
	  number out of a closed client list that has no "party bags" and no "party
	  quest log" in it.

	  EXCEPT ON SLOTS WITH A SECOND ORDER. Some catalogue orders carry `cmd2`
	  -- the lock pins the camera at its current distance on left-click and puts
	  it ABOVE THE HERO on right-click -- and there the right button fires it
	  while the dropdown moves to SHIFT+right. It is the only place in the addon
	  where right-click means two different things depending on the slot, so the
	  tooltip on those slots spells it out in full: a gesture nobody announces
	  is a gesture that does not exist, and one that changes without warning is
	  worse.

	  DRAGGING -> a game macro, as always. Still needed for anything carrying a
	  protected verb inside (`/cast`, `/use`, `/target`), which Lua cannot fire
	  no matter how good the button is.

	What gets saved tells the two cases apart by shape: a string is a macro name
	and a table `{ act = "id" }` is a catalogue order. Slots configured before
	any of this were strings, so they still work with nothing converted.

	=== WHY THE BUTTON IS SECURE AND THE SLOT SAVES THE NAME ==============

	`RunMacro` is PROTECTED in 3.3.5a just like `CastSpellByName`, so an
	ordinary button cannot fire a macro however well it knows which one it is.
	What can is a `SecureActionButtonTemplate` with `type="macro"`: the client
	fires it itself and there is no protected function to call.

	And here it DOES work, unlike in the spell slots. The `Skills.lua` objection
	-- "a secure button is no use because its contents change with the selection
	and attributes cannot be changed in combat" -- does not apply: these slots do
	NOT change with the selection. They are configured once, out of combat, by
	dragging. All that is needed is not touching the attributes in combat, and
	that is guarded on every path.

	RIGHT-CLICK IS SWITCHED OFF WITH `type2 = ""`, and that is the line that
	frees it for the dropdown. A secure button looks first at the attribute for
	the BUTTON you pressed (`type2` for right) and only falls back to the general
	one (`type`) if it finds none, so putting an empty one there says "on right,
	nothing" without touching what left-click does.

	AND IT IS DONE THAT WAY, rather than `type1` instead of `type`, because of
	how each one fails. Both rely on the same thing -- that the client looks at
	the per-button attribute -- but if that were not true, with `type1` macros
	would NEVER fire, whereas this way the worst case is right-click firing the
	macro as well as opening the menu, which is what it already did yesterday.

	Catalogue orders need none of this: they are fired from `PostClick`, which
	is ordinary code, because what lives inside them -- `/rts ...` and
	`/rtscmd ...` -- is not protected.

	THE NAME IS SAVED, NOT THE INDEX, and it is the `Macros.lua` lesson in
	reverse: a game action bar saves the index, so deleting and recreating the
	macros shuffles the indices and the buttons end up pointing at someone else.
	Here the name is saved, which is what the player recognises and what
	`/rts macros` respects when it updates.

	=== THE GAME BUTTONS ARE THE GAME BUTTONS =============================

	`Rails.lua` tried it with buttons of our own calling `ToggleTalentFrame`,
	`ToggleWorldMap`, `ToggleGameMenu`... and in game (PRUEBAS-10 G2/G4/G5) the
	map would not open, the talents would not open and the menu threw "blocked
	from an action only available to the Blizzard UI". Those functions are
	protected and it makes no difference that the button is ours.

	So nothing is reimplemented here: theirs get MOVED. `CharacterMicroButton`
	and its siblings are reparented into a row of ours and handed back on exit.
	They are their buttons, with their handlers, so they open what they should.

	THE BAGS GO THE SAME WAY AND FOR THE SAME REASON. The backpack and the four
	bags are children of `MainMenuBarArtFrame`, so hiding the main bar took them
	with it and RTS mode had no bags. They are the client own item buttons --
	they accept drags, they show their free-slot count, they open on their key --
	and none of that can be reproduced by a button of ours calling `ToggleBag`.

	Three things that brings, and that have to be respected:

	  - They are PROTECTED frames: reparenting them in combat is forbidden. It
	    is deferred to `PLAYER_REGEN_ENABLED`, exactly as `Chrome` does.
	  - `MoveMicroButtons` repositions them on its own (entering a vehicle, the
	    pet bar). It gets hooked and they are put back.
	  - They run at NORMAL scale, not pixel scale: the row hangs off UIParent and
	    anchors to the macro block. A micro button inside the pixel container
	    renders at 62% and looks broken.
]]

local ADDON, ns = ...

local T = {}
ns.Tray = T

T.active = false

local btn = {}            -- i -> secure button
local microHooked = false   -- the MoveMicroButtons hook, installed once
local pendingMicro        -- "in" | "out" while waiting to leave combat

--- What gets saved -------------------------------------------------------
--
-- Per ACCOUNT, like the macros it holds: an order to a bot does not depend on
-- which character you are playing, and a player who sets the tray up on the
-- warrior does not want to do it all over again on the mage.

local function Store()
	if not RTSCommandDB then return {} end
	RTSCommandDB.tray = RTSCommandDB.tray or {}
	return RTSCommandDB.tray
end

-- A slot MACRO NAME, if what it holds is a macro.
function T:Get(i)
	local v = Store()[i]
	return type(v) == "string" and v or nil
end

-- A slot CATALOGUE ORDER, if what it holds is an order.
function T:Action(i)
	local v = Store()[i]
	if type(v) ~= "table" then return nil end
	return type(v.act) == "string" and v.act or nil
end

-- The secure attribute slot `i` should carry. In one place because three paths
-- want it (setting, repainting and leaving combat) and a half-written attribute
-- is a slot that looks full and does nothing.
local function Apply(b, i)
	local macro = T:Get(i)
	b:SetAttribute("macro", macro)
	b:SetAttribute("type", macro and "macro" or nil)
	-- Right-click, switched off by hand and always: see the header.
	b:SetAttribute("type2", "")
end

-- SAVING AND APPLYING travel together on purpose: a secure attribute set
-- without saving is lost on reload, and one saved without being set is a slot
-- that looks full and does nothing. Both failures look identical from outside.
--
-- `value` is a macro name, `{ act = "id" }`, or nothing to empty it.
function T:Set(i, value)
	if InCombatLockdown() then
		ns.Print("|cffff8800tray:|r a secure button cannot be changed in combat.")
		return false
	end
	if value == false then value = nil end
	Store()[i] = value
	local b = btn[i]
	if b then
		Apply(b, i)
		self:Paint(i)
	end
	return true
end

--- Picking an order ------------------------------------------------------
--
-- `Actions.lua` draws the dropdown; all that is decided here is which slot it
-- opens over and what to do with whatever gets chosen.
function T:Choose(i)
	local b = btn[i]
	if not b then return end
	if InCombatLockdown() then
		ns.Print("|cffff8800tray:|r a slot cannot be changed in combat.")
		return
	end
	ns.Actions:Open(b, "Slot " .. i, self:Action(i), function(id)
		T:Set(i, id and { act = id } or nil)
	end)
end

--- A slot macro ----------------------------------------------------------
--
-- Resolved EVERY time it is painted and never cached: the player can rename or
-- delete a macro with the tray up, and a slot showing the icon of something
-- that no longer exists is worse than an empty one.
local function MacroInfo(name)
	if not name then return nil end
	local idx = GetMacroIndexByName and GetMacroIndexByName(name) or 0
	if not idx or idx == 0 then return nil end
	local n, tex, body = GetMacroInfo(idx)
	return { index = idx, name = n or name, texture = tex, body = body }
end

--- Drawing ---------------------------------------------------------------

-- The footer on every tray tooltip: how you change a slot. It goes on all of
-- them because right-click is invisible -- nothing on screen announces it --
-- and a hidden feature is a feature that does not exist.
local HINT = "|cff888888Right-click: pick an order. Drag a macro to place one.|r"

-- The same footer for slots whose right button already has an owner. Written
-- separately rather than composed on the fly, because the changed gesture is
-- the one thing the player has to read there, and burying it inside the usual
-- sentence is not saying it.
local HINT2 = "|cff888888Shift + right-click: pick a different order.|r"

local function Empty(b, tip, body)
	b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
	b.icon:SetTexCoord(0, 1, 0, 1)
	b.icon:SetVertexColor(0.35, 0.35, 0.4)
	b.icon:SetAlpha(0.8)
	b.label:SetText("")
	ns.W:Tip(b, tip, body)
end

function T:Paint(i)
	local b = btn[i]
	if not b then return end

	-- A CATALOGUE ORDER. It comes first because it is what right-click puts
	-- there, which is the normal way to fill a slot from now on.
	local id = self:Action(i)
	if id then
		local e = ns.Actions:Find(id)
		if e then
			ns.Actions:Paint(b.icon, e)
			b.label:SetText("")
			-- BOTH ORDERS, BOTH IN THE TOOLTIP. The right-click one is visible
			-- nowhere at all unless it is written here.
			if e.cmd2 and e.d2 then
				ns.W:Tip(b, e.name, (e.d or "") ..
					"\n|cffffff00Right-click:|r " .. e.d2 .. "\n" .. HINT2)
			else
				ns.W:Tip(b, e.name, (e.d or "") .. "\n" .. HINT)
			end
		else
			-- An order that was taken out of the catalogue. The slot does not
			-- clear itself: same rule as a renamed macro, below.
			Empty(b, "|cffff8800" .. id .. "|r",
				"That order is no longer in the catalogue.\n" .. HINT)
		end
		return
	end

	local name = self:Get(i)
	local info = MacroInfo(name)

	if not info then
		if name then
			-- A DELETED MACRO IS NOT THROWN OUT OF THE SLOT. It may have been
			-- renamed, or this may be another character with other macros;
			-- wiping the player configuration over that would lose it silently.
			Empty(b, "|cffff8800" .. name .. "|r",
				"That macro no longer exists.\nRecreate it with |cffffff00/rts macros|r.\n" .. HINT)
		else
			Empty(b, "Slot " .. i .. " empty",
				"|cffffff00Right-click|r (or left) to pick an order.\n" ..
				"Or drag one of the game macros in here.")
		end
		return
	end

	b.icon:SetTexture(info.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetVertexColor(1, 1, 1)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	local body = (info.body or ""):gsub("^%s+", ""):gsub("%s+$", "")
	ns.W:Tip(b, info.name, (body ~= "" and (body .. "\n") or "") .. HINT)
end

function T:PaintAll()
	for i = 1, ns.Dock.MACRO_N do self:Paint(i) end
end

--- Picking up and dropping ----------------------------------------------

-- Whatever the cursor is carrying, if it is a macro. `GetCursorInfo` returns
-- "macro", index.
local function CursorMacro()
	local kind, a = GetCursorInfo()
	if kind ~= "macro" then return nil end
	local n = GetMacroInfo(a)
	return n
end

local function Slot(i, parent, size)
	local b = btn[i]
	if not b then
		b = ns.W:Button(parent, size, nil, "SecureActionButtonTemplate")
		b:RegisterForClicks("AnyUp")
		b:RegisterForDrag("LeftButton")
		b.slot = i

		-- DROPPING BY DRAGGING.
		b:SetScript("OnReceiveDrag", function(self)
			local name = CursorMacro()
			if not name then return end
			if T:Set(self.slot, name) then ClearCursor() end
		end)

		-- AND DROPPING BY CLICKING, which is how everyone does it on an action
		-- bar. The problem is that this button is secure: the click that drops
		-- the macro would also FIRE it. So when the cursor is carrying one, the
		-- type is switched off before the click and back on afterwards. Without
		-- this, placing a command macro runs it as a bonus.
		b:SetScript("PreClick", function(self)
			if not CursorMacro() then return end
			-- IN COMBAT THERE IS NOTHING TO DO BUT SAY SO. A secure button
			-- attributes are locked, so the type cannot be switched off and the
			-- macro cannot be placed: the click is going to FIRE whatever was
			-- already there. Staying quiet would leave the player watching their
			-- bot do something they never asked for, with no visible connection
			-- to having dragged a macro.
			if InCombatLockdown() then
				ns.Print("|cffff8800tray:|r a slot cannot be changed in combat; " ..
					"the click fires whatever it already held.")
				return
			end
			self:SetAttribute("type", nil)
		end)

		-- WHAT HAPPENS AFTER THE CLICK, IN ORDER. The secure button has already
		-- done its part (or nothing, if the slot holds no macro) and the rest is
		-- decided here: drop whatever the cursor carries, open the dropdown on
		-- right-click, or fire the catalogue order on left.
		b:SetScript("PostClick", function(self, button)
			if InCombatLockdown() then return end

			local dragged = CursorMacro()
			if dragged then
				if T:Set(self.slot, dragged) then ClearCursor() end
				return
			end
			-- Restored ALWAYS, not only when a macro was on the cursor:
			-- `PreClick` switched it off before knowing how this would end.
			Apply(self, self.slot)

			if button == "RightButton" then
				-- THE SECOND ORDER BEATS THE DROPDOWN, and only on slots that
				-- carry one. SHIFT gives it back, which is how the Lock slot can
				-- still be changed.
				local id = T:Action(self.slot)
				local e = id and ns.Actions:Find(id)
				if e and e.cmd2 and not IsShiftKeyDown() then
					ns.Actions:Run(id, true)
					return
				end
				T:Choose(self.slot)
				return
			end

			local id = T:Action(self.slot)
			if id then
				ns.Actions:Run(id)
			elseif not T:Get(self.slot) then
				-- AN EMPTY SLOT OFFERS ITSELF TO LEFT-CLICK. It does nothing
				-- else and right-click is invisible on screen; without this a
				-- freshly placed tray looks broken.
				T:Choose(self.slot)
			end
		end)

		-- PICKING UP BY DRAGGING. Leaves the macro on the cursor -- it can be
		-- dropped on another slot or into empty space -- and empties this one.
		--
		-- MACROS ONLY. A catalogue order does not exist outside this addon, so
		-- there is nothing to leave on the cursor: dragging one stays put on
		-- purpose, and it is removed from the dropdown.
		b:SetScript("OnDragStart", function(self)
			local name = T:Get(self.slot)
			if not name then return end
			local info = MacroInfo(name)
			if info then PickupMacro(info.index) end
			T:Set(self.slot, nil)
		end)

		btn[i] = b
	end
	Apply(b, i)
	return b
end

--- THE TWO BORROWED ROWS: the bags and the game buttons ------------------
--
-- Both are CLIENT buttons taken on loan and handed back. See the header for why
-- they are not reimplemented.
--
-- Top to bottom: macros, BAGS, game buttons. The bags sit right against the
-- macros because they get used while playing and the game menu almost never
-- does; and they go above the menu, not below, because the menu is the floor of
-- the whole block -- move the last one and everything above moves with it.

local MICRO = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
	"AchievementMicroButton", "QuestLogMicroButton", "SocialsMicroButton",
	"PVPMicroButton", "LFDMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

-- EN EL ORDEN DEL JUEGO, que es el que los dedos tienen aprendido: el llavero a
-- la izquierda, las cuatro bolsas de derecha a izquierda y la mochila al final.
-- Invertirlo "para que se lea de 1 a 4" seria cambiar de sitio la mochila, que
-- es la unica que se pulsa sin mirar.
local BAGS = {
	"KeyRingButton",
	"CharacterBag3Slot", "CharacterBag2Slot", "CharacterBag1Slot",
	"CharacterBag0Slot", "MainMenuBarBackpackButton",
}

-- Los micro-botones se solapan a proposito en la barra de Blizzard: su arte
-- lleva el borde compartido dentro, asi que separarlos deja diez botones
-- sueltos y mal cortados. Las bolsas no: son cuadros independientes.
local ROWS = {
	{ key = "bags",  names = BAGS,  gap = 2  },
	{ key = "micro", names = MICRO, gap = -3 },
}

-- LOS DOS HUECOS NO SON EL MISMO. Entre las bolsas y el menu de juego basta con
-- separarlos; entre el bloque de macros y las bolsas hace falta MAS, porque ahi
-- cambia de que va la cosa -- arriba son ordenes a los bots y abajo son cosas
-- tuyas -- y con el mismo aire los diez macros y las seis bolsas se leen como
-- una sola rejilla de tres filas.
local TOP_GAP = 12    -- entre el bloque de macros y la primera fila prestada

-- Y ESTE ES NEGATIVO A PROPOSITO. Los micro-botones del cliente miden 58 de
-- alto y su dibujo no llega abajo del todo: el arte lleva aire dentro, que es
-- lo que en la barra de Blizzard queda tapado por el borde de la propia barra.
-- Aqui no hay barra que lo tape, asi que un hueco de 4 se ve como veinte
-- pixeles de nada entre las bolsas y el menu.
--
-- Se compensa subiendo la fila dentro de su hueco. El numero esta puesto A OJO
-- contra la pantalla -- el aire del dibujo no se puede medir desde Lua -- y por
-- eso esta aqui solo, con nombre, y no sumado dentro de otra cuenta.
local ROW_GAP = -14   -- entre las dos filas prestadas

local rowOf = {}      -- key -> { frame = , was = {} }

local function RowNames(r)
	-- Para los micro-botones el cliente tiene su propia lista (`MainMenuBar.lua`)
	-- y esa es mejor que la nuestra: sabe cuales existen en ESTA version. La
	-- nuestra es el respaldo.
	if r.key == "micro" and type(_G.MICRO_BUTTONS) == "table"
	   and #_G.MICRO_BUTTONS > 0 then
		return _G.MICRO_BUTTONS
	end
	return r.names
end

local function RowButtons(r)
	local out = {}
	for _, name in ipairs(RowNames(r)) do
		local f = _G[name]
		if f then table.insert(out, f) end
	end
	return out
end

-- Colocar una fila y devolver su alto. A escala NORMAL: la fila cuelga de
-- UIParent (ver la cabecera).
local function PlaceRow(r)
	local hold = rowOf[r.key]
	if not (hold and hold.frame) then return 0 end
	local x, h = 0, 0
	for _, f in ipairs(RowButtons(r)) do
		f:SetParent(hold.frame)
		f:ClearAllPoints()
		f:SetPoint("BOTTOMLEFT", hold.frame, "BOTTOMLEFT", x, 0)
		f:Show()
		x = x + f:GetWidth() + r.gap
		if f:GetHeight() > h then h = f:GetHeight() end
	end
	hold.frame:SetWidth(math.max(x - r.gap, 1))
	hold.frame:SetHeight(math.max(h, 1))
	return h
end

-- Lo que `Dock` tiene que reservar debajo del bloque de macros, EN PIXELES: las
-- filas estan a escala normal y el Dock mide en pixeles fisicos, asi que hay que
-- pasar de una a otra o el hueco sale corto en una pantalla y largo en otra.
local function ReserveFoot(total)
	local host = ns.Pixels:Host()
	local k = (host and host:GetEffectiveScale() or 1)
	if k <= 0 then k = 1 end
	local row = rowOf.micro and rowOf.micro.frame
	local rs = row and row:GetEffectiveScale() or 1
	-- El respiro de debajo lo pone `Dock`, que es quien tiene que cuadrar el
	-- bloque del centro a la misma altura.
	ns.Dock:SetRightFoot(math.floor(total * (rs / k) + 0.5) + ns.Dock:FootPad())
end

-- El hueco que va ENCIMA de cada fila. El primero es mas grande: ver arriba.
local function GapBefore(i)
	return (i == 1) and TOP_GAP or ROW_GAP
end

local function PlaceBorrowed()
	local total = 0
	for i, r in ipairs(ROWS) do
		local h = PlaceRow(r)
		-- El hueco cuenta ANTES de la fila, igual que lo aplica el anclaje. Si
		-- aqui se sumara "detras" saldria el mismo numero por casualidad hoy y
		-- dejaria de salir en cuanto los dos huecos dejaran de ser iguales --
		-- que es justo lo que acaba de pasar.
		if h > 0 then total = total + GapBefore(i) + h end
	end
	ReserveFoot(total)
end

local function GrabBorrowed()
	if InCombatLockdown() then
		pendingMicro = "in"
		return
	end
	pendingMicro = nil

	for _, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold then
			for _, f in ipairs(RowButtons(r)) do
				local name = f:GetName()
				if name and not hold.was[name] then
					local pts = {}
					for i = 1, f:GetNumPoints() do
						pts[i] = { f:GetPoint(i) }
					end
					hold.was[name] = { parent = f:GetParent(), points = pts }
				end
			end
		end
	end

	PlaceBorrowed()

	if not microHooked and type(_G.MoveMicroButtons) == "function" then
		microHooked = true
		-- El cliente los recoloca solo (vehiculo, barra de mascota). No se
		-- pelea con el evento que lo provoca: se vuelve a poner despues.
		hooksecurefunc("MoveMicroButtons", function()
			if T.active and not InCombatLockdown() then PlaceBorrowed() end
		end)
	end
end

-- Devuelve si se ha podido: en combate no, y quien llama tiene que saberlo
-- para no esconder las filas con los botones del cliente todavia dentro.
local function ReleaseBorrowed()
	if InCombatLockdown() then
		pendingMicro = "out"
		return false
	end
	pendingMicro = nil

	for _, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold then
			for name, was in pairs(hold.was) do
				local f = _G[name]
				if f then
					f:SetParent(was.parent or MainMenuBarArtFrame or UIParent)
					f:ClearAllPoints()
					for _, p in ipairs(was.points) do
						f:SetPoint(unpack(p))
					end
				end
			end
			hold.was = {}
		end
	end
	return true
end

--- Distribuir -------------------------------------------------------------

function T:Layout()
	if not self.active then return end
	local hostF = ns.Dock:Host("macros")
	if not hostF then return end

	local cells = ns.Dock:MacroCells()
	for i = 1, ns.Dock.MACRO_N do
		local c = cells[i]
		if c then
			local b = Slot(i, hostF, c.w)
			b:SetParent(hostF)
			b:SetWidth(c.w)
			b:SetHeight(c.h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", hostF, "TOPLEFT", c.x, -c.y)
			b:Show()
			self:Paint(i)
		elseif btn[i] then
			btn[i]:Hide()
		end
	end

	-- LAS DOS FILAS PRESTADAS, COLGANDO UNA DE OTRA. Cada una se ancla a lo que
	-- tiene ENCIMA, asi que si una crece o desaparece la de abajo la sigue sin
	-- un solo numero mas.
	local above = hostF
	for i, r in ipairs(ROWS) do
		local hold = rowOf[r.key]
		if hold and hold.frame then
			hold.frame:ClearAllPoints()
			hold.frame:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -GapBefore(i))
			above = hold.frame
		end
	end
end

--- Entrar y salir ---------------------------------------------------------

function T:Enter()
	self.active = true

	for _, r in ipairs(ROWS) do
		if not rowOf[r.key] then
			-- DE UIParent, no del contenedor de pixel: ver la cabecera.
			local f = CreateFrame("Frame", "RTSTray_" .. r.key, UIParent)
			f:SetFrameStrata("MEDIUM")
			f:SetWidth(1)
			f:SetHeight(1)
			rowOf[r.key] = { frame = f, was = {} }
		end
		rowOf[r.key].frame:Show()
	end

	if not self.wired then
		self.wired = true
		ns.Dock:OnLayout(function() T:Layout() end)

		local ev = CreateFrame("Frame", "RTSTrayEvents")
		ev:RegisterEvent("UPDATE_MACROS")
		ev:RegisterEvent("PLAYER_REGEN_ENABLED")
		ev:SetScript("OnEvent", function(_, event)
			if event == "UPDATE_MACROS" then
				if T.active then T:PaintAll() end
				return
			end
			-- Salir de combate: lo que quedo aplazado.
			if pendingMicro == "in" and T.active then
				GrabBorrowed()
			elseif pendingMicro == "out" and not T.active then
				ReleaseBorrowed()
			end
			if T.active then
				for i = 1, ns.Dock.MACRO_N do
					local b = btn[i]
					if b then Apply(b, i) end
				end
			end
		end)
	end

	GrabBorrowed()
	self:Layout()
end

function T:Leave()
	self.active = false
	-- EL DESPLEGABLE NO CUELGA DE LA BANDEJA, asi que esconder las casillas no
	-- se lo lleva por delante: quedaria un menu flotando sobre el mundo con el
	-- atrapa-clicks puesto, o sea la pantalla entera sin responder.
	ns.Actions:Close()
	for _, b in pairs(btn) do b:Hide() end
	-- LAS FILAS SOLO SE ESCONDEN SI SE HAN PODIDO DEVOLVER. En combate no se
	-- pueden (son frames protegidos), y esconderlas con los botones dentro es la
	-- forma de quedarse sin bolsas y sin menu hasta que acabe la pelea.
	if ReleaseBorrowed() then
		for _, r in ipairs(ROWS) do
			local hold = rowOf[r.key]
			if hold and hold.frame then hold.frame:Hide() end
		end
	end
end

function T:Report()
	ns.Print(("|cffffff00bandeja|r -- %d casillas:"):format(ns.Dock.MACRO_N))
	for i = 1, ns.Dock.MACRO_N do
		local what
		local id = self:Action(i)
		if id then
			local e = ns.Actions:Find(id)
			what = e and ("|cff33ccff" .. e.name .. "|r |cff888888(orden)|r")
				or ("|cffff8800" .. id .. "|r (ya no esta en el catalogo)")
		else
			local name = self:Get(i)
			local info = MacroInfo(name)
			what = info and ("|cff33ccff" .. info.name .. "|r |cff888888(macro)|r")
				or (name and ("|cffff8800" .. name .. "|r (ya no existe)")
				or "|cff666666vacia|r")
		end
		ns.Print(("  %d. %s"):format(i, what))
	end
	ns.Print("|cffffff00Clic derecho|r en una casilla para elegir orden; " ..
		"arrastra un macro para poner uno del juego.")
end

function T:Clear()
	if InCombatLockdown() then
		ns.Print("|cffff8800bandeja:|r en combate no, son botones seguros.")
		return
	end
	for i = 1, ns.Dock.MACRO_N do self:Set(i, nil) end
	ns.Print(("bandeja: las %d casillas vacias."):format(ns.Dock.MACRO_N))
end

ns.Dock:Register(T)
