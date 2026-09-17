--[[
	Cast.lua -- the spell slots on the bottom bar.

	It is the contents of the LEFT half of the `Dock`, and it draws the two
	states the Dock decides on:

	  A  none or one     the name and TEN slots
	  B  two or more     per column: name and a 2x2 of FOUR

	The data and the actions are not here: `Skills.lua` has them. What is here
	is the DRAWING and the GESTURE. In state B there are up to five columns
	asking for the same thing at once, and with the logic inside the panel that
	would be five copies of everything.

	=== THE MACROS LEFT THIS FILE =============================================

	Until 2026-09-13 this file also drew four macro bars per character, with a
	catalogue of twelve actions WRITTEN INTO THE CODE (`stay`, `follow`,
	`max dps`...). They went away whole: the orders to the bots are now real
	game macros, in the tray on the right (`Tray.lua`), and the catalogue that
	creates them is the one in `Macros.lua`, which already existed.

	The only thing that survived from that catalogue is LOOK AFTER (`PFOCUS`),
	and not out of nostalgia: it is the only one of the twelve that does not fit
	in a macro, because it needs a second click to choose who for. It lives here
	as a gesture and it is fired from `/rts focus`, which DOES fit in a macro.

	=== THE FOUR OF STATE B ARE NOT THE FIRST FOUR OF THE TEN =================

	They are another set (`Skills`: "group"). The reason is in `Dock.lua`.

	=== THE GESTURE OF §5, AND THE CIRCLING LIGHT =============================

	Pressing a slot whose spell needs a target does not send it: it leaves it
	ARMED, and the icon starts spinning with **the hunter pet light**. The next
	click chooses who for -- on a game frame or out in the 3D world, either way.

	THE LIGHT BELONGS TO THE CLIENT AND IS NOT REIMPLEMENTED. Taken from reading
	its FrameXML (`Data\esES\patch-esES.MPQ`, see `CLAUDE.md`), not from memory:

	  * `AutoCastShineTemplate` (UIPanelTemplates.xml:699) is 16 sparkle
	    textures with their `OnLoad`, and it is an ordinary VIRTUAL template.
	  * `AutoCastShine_AutoCastStart(frame, r, g, b)` turns it on and
	    `..._AutoCastStop(frame)` turns it off (UIParent.lua:3477,3494).
	  * **THE ANIMATION COMES FOR FREE**: `UIParent`'s `OnUpdate` moves it.

	AND ONE TRAP: `AutoCastShine_OnLoad` looks its sparkles up by name
	(`_G[name..i]`), so **the frame HAS to have a name**.

	=== SETTING UP A SLOT =====================================================

	RIGHT CLICK opens the spell list of THAT character -- which is its action
	bar, not your book, because your book does not have the mage's Polymorph
	(see `Skills.lua`). "Drag it out of the book" cannot exist for a bot and
	there is no way round it: `PickupSpell` only picks up what you know.
]]

local ADDON, ns = ...

local C = {}
ns.Cast = C

C.active = false

-- Las teclas de la fila de arriba. Arriba del todo porque las LEEN dos sitios
-- muy separados: el dibujo del hueco (el numero que se ve) y el atado del
-- binding, y las dos tienen que decir lo mismo o el numero pintado miente.
local KEY_NAMES = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

-- CUANTOS HUECOS CON TECLA LLEVA UNA COLUMNA del estado B. Son los DOS DE
-- ARRIBA del 2x2, y las mismas diez teclas se reparten por columnas en el
-- orden en que estan en pantalla: 1-2 la primera, 3-4 la segunda, hasta 9-0
-- con cinco cogidos. Asi la tecla y el hueco se leen de izquierda a derecha
-- igual que en el estado A, sin nada que traducir.
--
-- La fila de abajo se queda sin tecla A PROPOSITO: son veinte huecos y diez
-- numeros, y darle a la de abajo un modificador la pondria a competir con el
-- que ya significa "elige objetivo" en ese mismo boton. Se deja para el raton.
local B_KEYS = 2

-- QUE TECLA LE TOCA A UN HUECO, o nil si no lleva ninguna. `col` es el indice
-- de columna del estado B y no se usa en el A.
--
-- UNA SOLA FUNCION PARA LOS DOS SITIOS que tienen que decir lo mismo: el
-- numero que se pinta encima del hueco y el que decide `KeyButton` al
-- pulsarlo. Escrito dos veces, el dia que cambie el reparto uno de los dos se
-- queda viejo y el numero pintado miente.
local function KeyFor(set, i, col)
	if (set or "main") == "main" then
		return (i <= ns.Dock.MAIN_N) and KEY_NAMES[i] or nil
	end
	if not col or i > B_KEYS then return nil end
	return KEY_NAMES[(col - 1) * B_KEYS + i]
end

--- LOS ENFRIAMIENTOS -------------------------------------------------------
--
-- DE DONDE SALEN, que es lo que decide todo lo demas:
--
--   * DE TU HEROE los sabe el cliente. `GetSpellCooldown(id)` es de TU libro y
--     tu personaje esta en el. Sale gratis y sin preguntar a nadie.
--   * DE UN BOT no los sabe. Ese libro no es el tuyo, y de un id ajeno el
--     cliente solo tiene lo del DBC -- nombre, icono, rango -- que no dice si
--     esta enfriando. Los contesta el servidor (`CDQ`/`CD`).
--
-- Asi que hay dos caminos y no uno con un rodeo, y el de tu heroe es el bueno:
-- no cuesta mensaje, no llega tarde y no se puede perder.
--
-- LA RUEDA LA ANIMA EL CLIENTE. `CooldownFrame_SetTimer(cd, inicio, total, 1)`
-- y se acabo: no hay que refrescarla, baja sola. Por eso se pregunta despacio
-- (una vez por segundo) y no por fotograma -- lo unico que hace falta saber es
-- CUANDO EMPIEZA uno nuevo, y un segundo de retraso en eso no se ve.
local cdCache = {}        -- id -> { start, dur }   (del bot que se este mirando)
local cdOwner = nil       -- de quien es esa cache
local cdAsked = 0
-- UN NOMBRE POR RUEDA, y un contador y no el indice del hueco: en el estado
-- de varios hay cinco columnas con un hueco 1 cada una, y cinco frames con
-- el mismo nombre se pisan en `_G`.
local cdSeq = 0

local spellBtn = {}       -- i -> square button (state A)
local colBtn = {}         -- ci -> { head, spells = {} }
local headName
local flyout

--- The names, small, and clipped by length ---------------------------------
--
-- SMALL SINCE 2026-09-17, and that is the whole point of them. A name on this
-- client runs to twelve letters, and at size 32 that was a label wider than
-- half the row of slots underneath it: the caption weighed more on the screen
-- than the thing that actually gets used. Both states now draw it at
-- `FONT.mini`, which is a shade over the size the client writes its own text
-- at -- a caption, not a headline.
--
-- AND THE CUT COMES BACK ALMOST TO NOTHING. It was there because the label was
-- huge, not because names are long: at this size twelve letters fit in the ten
-- slots with room to spare, and they nearly fit in one state B column. So the
-- big caption is not cut at all (twelve is the client's own ceiling) and the
-- column one only gives up its last letters.
--
-- NO ELLIPSIS, on purpose: the three dots give back nearly all the width you
-- just took away, so they would be the same problem written another way. And a
-- cut name is just as recognisable: they are the five in your group, not a list
-- of strangers.
--
-- The `SetWidth` on the column caption stays and is NOT what clips: a
-- FontString with a width BREAKS INTO TWO LINES, and the second one spills out
-- of the header's height. It is there so a long name does not draw on top of
-- the column next to it.
local NAME_A = 12         -- the caption above the ten slots
local NAME_B = 11         -- the one on each column

local function Clip(name, max)
	name = tostring(name or "")
	if name:len() <= max then return name end
	local cut = name:sub(1, max)
	-- Do not split a letter down the middle. In UTF-8 the continuation bytes run
	-- from 0x80 to 0xBF and a stray byte is drawn as a black diamond; the
	-- Spanish client allows accents in names, so it can happen.
	while cut ~= "" do
		local b = cut:byte(-1)
		if b < 0x80 or b >= 0xC0 then break end
		cut = cut:sub(1, -2)
	end
	-- And if the last thing left is the START of a multibyte letter, it has to
	-- go too: its tail went with the cut.
	local b = cut:byte(-1)
	if b and b >= 0xC0 then cut = cut:sub(1, -2) end
	return cut
end

--- Focus state -------------------------------------------------------------
--
-- name -> guid, so we can draw who is wearing it. The server says so when it
-- confirms, we do not assume it ourselves: a button that lights up off its own
-- request hides exactly the case where the request never went out.
C.focus = {}

function C:PointAt(name, guid, label)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800look after:|r mod-rts is needed.")
		return
	end
	local hex = guid and (tostring(guid):gsub("^0[xX]", "")) or "-"
	ns.SendServer("PFOCUS " .. name .. " " .. hex)
	if label then
		ns.Print(("|cff33ccff%s|r now looks after |cffffd100%s|r."):format(name, label))
	end
end

function C:ClearFocus(name)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800look after:|r mod-rts is needed.")
		return
	end
	ns.SendServer("PFOCUS " .. name .. " -")
end

-- ARMING THE LOOK AFTER GESTURE. `/rts focus` calls it, which is what the
-- player puts in a macro on the tray.
function C:StartFocus(name)
	name = name or ns.Dock:Subject()
	if not name then return end
	self.pendingFocus = name
	ns.Print(("|cffffd100Look after (%s):|r choose who; right click cancels."):format(name))
	self:Refresh()
end

--- The arming light --------------------------------------------------------

local shineSeq = 0

-- The light spills out of the button on purpose -- the sparkles spin OUTSIDE
-- the icon -- so at 9% per side it does not reach far enough to tread on the
-- neighbour.
local SHINE_SCALE = 1.18
local SHINE_LIFT  = 10

local function Shine(b)
	if b.shine then return b.shine end
	if type(_G.AutoCastShine_AutoCastStart) ~= "function" then return nil end

	shineSeq = shineSeq + 1
	local ok, f = pcall(CreateFrame, "Frame", "RTSShine" .. shineSeq, b,
	                    "AutoCastShineTemplate")
	if not ok or not f then return nil end
	f:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.shine = f
	return f
end

local function SetArmed(b, on)
	local f = Shine(b)
	if not f then return end
	if on then
		-- It gets remeasured and raised again EVERY TIME, not on creation: the
		-- button changes level when it is reparented between state A and state
		-- B, and a level set only once goes stale without raising an error --
		-- the light would go back under the icon and it would look like it
		-- never comes up.
		f:SetWidth(b:GetWidth() * SHINE_SCALE)
		f:SetHeight(b:GetHeight() * SHINE_SCALE)
		f:SetFrameLevel(b:GetFrameLevel() + SHINE_LIFT)
		AutoCastShine_AutoCastStart(f)
	elseif type(_G.AutoCastShine_AutoCastStop) == "function" then
		AutoCastShine_AutoCastStop(f)
	end
end

--- The picker flyout -------------------------------------------------------

local ROW_H = 34
local rows = {}

local function EnsureFlyout()
	if flyout then return flyout end
	flyout = CreateFrame("Frame", "RTSCastPicker", ns.Pixels:Host())
	flyout:SetFrameStrata("DIALOG")
	flyout:EnableMouse(true)
	flyout:Hide()

	local bg = flyout:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(0, 0, 0, 0.92)
	return flyout
end

local function FlyoutRow(i)
	if rows[i] then return rows[i] end
	local b = CreateFrame("Button", nil, flyout)
	b:SetHeight(ROW_H)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(ROW_H - 6)
	b.icon:SetHeight(ROW_H - 6)
	b.icon:SetPoint("LEFT", b, "LEFT", 4, 0)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- A Button with no template brings no FontString, so `SetText` would draw
	-- nothing. It gets made by hand, like everywhere else in the addon.
	b.text = ns.W:Text(b, ns.W.FONT.normal)
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetJustifyH("LEFT")

	rows[i] = b
	return b
end

-- HOW MANY ROWS FIT AT ONCE. The server sends the bot's bar AND everything it
-- knows, which is fifty or a hundred entries depending on the level; without
-- paging, the list would be drawn 3,000 pixels tall and would read as "it does
-- not show up".
local PAGE = 14

-- `entries` = { { icon, text, sub, fn }, ... }
function C:ShowPicker(anchor, entries, page)
	EnsureFlyout()

	page = page or 0
	local total = #entries
	local pages = math.max(1, math.ceil(total / PAGE))
	if page >= pages then page = pages - 1 end
	if page < 0 then page = 0 end

	local from = page * PAGE + 1
	local to   = math.min(total, from + PAGE - 1)

	local shown = {}
	if page > 0 then
		table.insert(shown, {
			icon = "Interface\\Buttons\\UI-MicroStream-Green",
			text = ("|cffffd100... previous|r |cff888888(%d/%d)|r"):format(page, pages),
			keep = true,
			fn = function() C:ShowPicker(anchor, entries, page - 1) end,
		})
	end
	for i = from, to do table.insert(shown, entries[i]) end
	if to < total then
		table.insert(shown, {
			icon = "Interface\\Buttons\\UI-MicroStream-Red",
			text = ("|cffffd100more ... |r|cff888888(%d more, %d/%d)|r"):format(
				total - to, page + 2, pages),
			keep = true,
			fn = function() C:ShowPicker(anchor, entries, page + 1) end,
		})
	end
	entries = shown

	local n = 0
	for i, e in ipairs(entries) do
		local b = FlyoutRow(i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -(6 + (i - 1) * (ROW_H + 2)))
		b:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -(6 + (i - 1) * (ROW_H + 2)))
		b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		b.text:SetText(e.text .. (e.sub and (" |cff888888" .. e.sub .. "|r") or ""))
		b:SetScript("OnClick", function()
			-- A navigation row does NOT close the list: it redraws it on
			-- another page.
			if not e.keep then flyout:Hide() end
			local ok, err = pcall(e.fn)
			if not ok then ns.Print("|cffff0000dock:|r " .. tostring(err)) end
		end)
		b:Show()
		n = i
	end
	for i = n + 1, #rows do rows[i]:Hide() end

	flyout:SetWidth(440)
	flyout:SetHeight(n * (ROW_H + 2) + 12)
	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 8)
	flyout:Show()
end

function C:HidePicker()
	if flyout then flyout:Hide() end
end

-- A character's spell list, for setting up a slot. `set` says which of the two
-- sets it goes to -- and it is written in the list's header, because "slot 2"
-- means two different things and the player has to know which one they are
-- touching.
function C:PickSpell(anchor, name, i, set)
	local cat = ns.Skills:Available(name)
	if #cat == 0 then
		ns.Print(("|cffff8800%s|r has no spells to offer%s."):format(name,
			ns.Skills:Pending(name) and " yet (asking for them...)" or
			": with the server up to date this should not happen -- |cffffff00/rts skills|r"))
		return
	end

	local entries = {
		{ icon = "Interface\\Icons\\INV_Misc_QuestionMark", text = "|cff888888(empty the slot)|r",
		  fn = function() ns.Skills:SetSlot(name, i, nil, set) end },
	}
	for _, s in ipairs(cat) do
		local info = ns.Skills:TypeInfo(s.type)
		table.insert(entries, {
			icon = s.texture, text = s.name, sub = info.label,
			fn = function() ns.Skills:SetSlot(name, i, s.spellId, set) end,
		})
	end

	self:ShowPicker(anchor, entries)
end

--- The spell buttons -------------------------------------------------------

local function SpellButton(store, i, parent, size, set)
	local b = store[i]
	if not b then
		b = ns.W:Button(parent, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		-- LA RUEDA DEL ENFRIAMIENTO ES DEL CLIENTE, no una textura nuestra que
		-- haya que animar: `CooldownFrameTemplate` se dibuja y baja solo. Y el
		-- frame tiene que tener NOMBRE porque la plantilla busca sus piezas por
		-- nombre, la misma trampa que `AutoCastShine`.
		cdSeq = cdSeq + 1
		b.cd = CreateFrame("Cooldown", "RTSCastCd" .. cdSeq, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints(b.icon)
		b:SetScript("OnClick", function(self, button)
			if not self.owner then return end
			if button == "RightButton" then
				C:PickSpell(self, self.owner, self.index, self.set)
				return
			end
			C:HidePicker()
			if self.spell then
				ns.Skills:Use(self.owner, self.index, self.set)
			else
				-- AN EMPTY SLOT DOES NOT KEEP QUIET. A click that does nothing
				-- is indistinguishable from a broken button.
				ns.Print("empty slot: |cffffff00right|r click to give it a spell.")
			end
		end)
		store[i] = b
	end
	b.set = set
	return b
end

local function PlaceSquare(b, parent, c)
	b:SetParent(parent)
	b:SetWidth(c.w)
	b:SetHeight(c.h)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", c.x, -c.y)
	b:Show()
end

local function PaintSpell(b, owner, i, s, aiming, set, col)
	b.owner, b.index, b.set, b.spell = owner, i, set, s and s.spellId or nil

	-- LA TECLA, ESCRITA EN EL HUECO QUE LA TIENE. Un atajo que no esta en
	-- pantalla es un atajo que no existe: hay que acordarse de el, y nadie se
	-- acuerda de diez. Solo lleva numero el hueco que tiene tecla -- la fila de
	-- arriba en el estado A, los dos de arriba de cada columna en el B; el
	-- resto se deja limpio en vez de poner un numero que no hace nada, que
	-- seria peor que no poner ninguno.
	b.label:SetText(KeyFor(set, i, col) or "")

	if not s then
		b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
		b.icon:SetTexCoord(0, 1, 0, 1)
		b.icon:SetVertexColor(0.35, 0.35, 0.4)
		b.icon:SetAlpha(0.8)
		ns.W:Tip(b, "Slot " .. i .. " empty",
			"Right click to choose a spell of " .. owner .. ".")
		SetArmed(b, false)
		if b.cd then b.cd:Hide() end
		return
	end

	b.icon:SetTexture(s.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetAlpha(1)

	-- A SPELL THAT IS NO LONGER ON ITS BAR IS DRAWN DIMMED, not erased. The bot
	-- may not be loaded yet or the reply may not have arrived.
	if s.stale then
		b.icon:SetVertexColor(0.55, 0.4, 0.4)
	else
		b.icon:SetVertexColor(1, 1, 1)
	end

	local info = ns.Skills:TypeInfo(s.type)
	local extra = s.stale and "\n|cffff8800no longer on its bar|r" or ""
	local q = ns.Skills:QueuedFor(owner)
	if q and q.id == s.spellId then
		extra = extra .. "\n|cffffd100queued, waiting for a slot|r"
	end
	-- THE THREE GESTURES, WRITTEN DOWN. A modifier that is not spelled out
	-- anywhere is a modifier that does not exist.
	extra = extra .. (info.ask
		and "\n|cff888888Click: choose a target. Alt: on itself.|r"
		or  "\n|cff888888Click: sent right away. Shift: choose a target.|r")
	ns.W:Tip(b, s.name, ("%s -- %s%s\n|cff888888Right click: change it.|r"):format(
		owner, info.label, extra))

	SetArmed(b, aiming and aiming.owner == owner and aiming.slot == i
		and (aiming.set or "main") == (set or "main"))

	C:PaintCooldown(b, owner, s.spellId)
end

--- Enfriamientos: las dos fuentes ------------------------------------------

-- Es tu propio personaje? Entonces lo sabe el cliente y no hay que preguntar.
local function IsMine(owner)
	return owner == nil or owner == ns.MyName()
end

function C:PaintCooldown(b, owner, spellId)
	if not b.cd or not spellId then return end

	local start, dur
	if IsMine(owner) then
		local st, du = GetSpellCooldown(spellId)
		start, dur = st, du
	else
		local e = (cdOwner == owner) and cdCache[spellId] or nil
		if e then start, dur = e.start, e.dur end
	end

	-- `dur > 1.5` DEJA FUERA EL GLOBAL. El enfriamiento global sale en TODOS los
	-- hechizos a la vez cada vez que lanzas cualquier cosa, y pintarlo convierte
	-- la barra entera en una rueda que gira sin parar: mucho movimiento que no
	-- dice nada. Es lo que hace la propia barra del juego.
	if start and dur and dur > 1.5 and start > 0 then
		CooldownFrame_SetTimer(b.cd, start, dur, 1)
	else
		b.cd:Hide()
	end
end

-- Preguntar por los que hay puestos, despacio.
--
-- SOLO POR LOS QUE SE VEN, y por eso la lista la manda quien dibuja: el bot
-- conoce cien hechizos y en los huecos hay veinte. Los otros ochenta serian
-- ochenta numeros por mensaje, dos veces por segundo, sobre un canal de 255
-- caracteres.
function C:AskCooldowns()
	if not self.active then return end
	if ns.Dock:State() ~= "A" then return end

	local owner = ns.Dock:Subject()
	if not owner or IsMine(owner) then return end
	if not ns.Orders:HasServer() or not ns.Link:ServerAtLeast(55) then return end

	local now = GetTime()
	if now - cdAsked < 1.0 then return end
	cdAsked = now

	local slots = ns.Skills:Slots(owner, ns.Dock.MAIN_TOTAL, "main")
	local ids, seen = {}, {}
	for i = 1, ns.Dock.MAIN_TOTAL do
		local sp = slots[i]
		if sp and sp.spellId and not seen[sp.spellId] then
			seen[sp.spellId] = true
			table.insert(ids, sp.spellId)
		end
	end
	if #ids == 0 then return end

	ns.SendServer(("CDQ %s %s"):format(owner, table.concat(ids, ",")))
end

--- Layout ------------------------------------------------------------------

local function HideAll(list)
	for _, b in ipairs(list) do b:Hide() end
end

--- LAS TECLAS 1234567890 ---------------------------------------------------
--
-- Las MISMAS diez teclas en los dos estados, repartidas segun lo que haya en
-- pantalla (`KeyFor`, arriba):
--
--   A  uno cogido      los diez huecos de la fila de arriba
--   B  varios cogidos  los DOS de arriba de cada columna, dos por cabeza:
--                      1-2 el primero, 3-4 el segundo... 9-0 el quinto
--
-- La fila de abajo no lleva tecla en ninguno de los dos, y no es un olvido: no
-- quedan numeros, y repartir Shift+1..0 sobre ella pondria un modificador a
-- competir con el que ya significa "elige objetivo" en el mismo boton. Esa
-- fila es del raton.
--
-- === POR QUE UN BOTON INTERMEDIO Y NO EL HUECO ============================
--
-- `SetBindingClick` quiere el NOMBRE de un frame, y los huecos no lo tienen:
-- `W:Button` los crea con `nil` de nombre, como todo en esta consola. Ponerles
-- nombre seria la respuesta corta y trae dos problemas que este proxy no tiene:
-- el hueco se ESCONDE (estado B, consola cerrada) y un binding a un frame
-- escondido no dispara, y ademas el binding tendria que rehacerse cada vez que
-- el reparto de huecos cambia de sitio.
--
-- Diez botones propios, invisibles, con nombre fijo y una vida entera. Lo que
-- cambia es a quien apuntan, y eso se lee en el momento de la pulsacion -- que
-- con varios cogidos no es solo QUIEN, sino tambien QUE HUECO: la tecla 3 es
-- el hueco 1 del segundo de la fila.
--
-- === Y SE COGEN PRESTADAS, NO SE ROBAN ===================================
--
-- 1..0 son la barra de acciones del jugador. Se guarda lo que cada tecla hacia
-- y se devuelve al salir, que es la misma regla de `FreeCam:GrabKeys` y la de
-- los frames de Blizzard: **lo que habia antes se anota y se pone de vuelta**.
--
-- En combate no se pueden tocar (`SetBinding*` esta protegida), asi que se
-- avisa y se reintenta al salir de la pelea. Ni coger ni devolver puede fallar
-- en silencio: una tecla que se queda cogida despues de salir del modo RTS es
-- una barra de acciones que no responde, y eso no se relaciona con el modo.
local keyBtn, savedKeys = {}, nil

local function KeyButton(i)
	local b = keyBtn[i]
	if b then return b end
	b = CreateFrame("Button", "RTSCastKey" .. i, UIParent)
	b:Hide()
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnClick", function()
		-- EL DUENO SE LEE AHORA, no cuando se ato la tecla. La consola cambia
		-- de sujeto cada vez que cambias la seleccion, y un dueno capturado al
		-- atar lanzaria el hechizo del bot de hace diez minutos.
		if ns.Dock:State() == "A" then
			local owner = ns.Dock:Subject()
			if not owner then return end
			ns.Skills:Use(owner, i, "main")
			return
		end

		-- CON VARIOS COGIDOS la tecla dice columna y hueco, y las dos cosas se
		-- leen igual de tarde: la columna es el orden de la seleccion y ese
		-- orden cambia con cada clic.
		--
		-- Y SIN COLUMNA NO PASA NADA. Con tres cogidos las teclas 7..0 no
		-- apuntan a nadie; se callan en vez de caer sobre el ultimo, que seria
		-- mandar un hechizo que nadie ha pedido.
		local ci   = math.floor((i - 1) / B_KEYS) + 1
		local slot = (i - 1) % B_KEYS + 1
		local m = ns.Dock:Columns()[ci]
		if not m then return end
		ns.Skills:Use(m.name, slot, "group")
	end)
	keyBtn[i] = b
	return b
end

function C:GrabKeys()
	if savedKeys then return true end
	if InCombatLockdown() then
		ns.Print("|cffff8800teclas:|r en combate no se pueden coger 1..0.")
		return false
	end
	savedKeys = {}
	for i, k in ipairs(KEY_NAMES) do
		savedKeys[k] = GetBindingAction(k) or ""
		SetBindingClick(k, KeyButton(i):GetName())
	end
	return true
end

function C:ReleaseKeys()
	if not savedKeys then return true end
	if InCombatLockdown() then return false end
	for k, action in pairs(savedKeys) do
		if action ~= "" then SetBinding(k, action) else SetBinding(k, nil) end
	end
	savedKeys = nil
	return true
end

function C:KeysPending()
	return savedKeys ~= nil
end

function C:Layout()
	if not self.active then return end
	if ns.Dock:State() == "A" then
		self:LayoutA()
	else
		self:LayoutB()
	end
	self:Refresh()
end

function C:LayoutA()
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		HideAll(col.spells)
	end

	local hHost = ns.Dock:Host("head")
	local sHost = ns.Dock:Host("spells")
	if not (hHost and sHost) then return end

	if not headName then
		headName = ns.W:Text(hHost, ns.W.FONT.mini)
		headName:SetJustifyH("LEFT")
	end
	headName:SetParent(hHost)
	headName:ClearAllPoints()
	headName:SetPoint("BOTTOMLEFT", hHost, "BOTTOMLEFT", 2, 2)
	headName:Show()

	local cells = ns.Dock:SpellCells()
	for i = 1, ns.Dock.MAIN_TOTAL do
		local c = cells[i]
		if c then
			PlaceSquare(SpellButton(spellBtn, i, sHost, c.w, "main"), sHost, c)
		elseif spellBtn[i] then
			spellBtn[i]:Hide()
		end
	end
end

function C:LayoutB()
	HideAll(spellBtn)
	if headName then headName:Hide() end

	local cols = ns.Dock:Columns()
	local cells = ns.Dock:ColumnSpellCells()

	for ci = 1, #cols do
		local h = ns.Dock:Host("col" .. ci)
		local col = colBtn[ci]
		if not col then
			col = { spells = {} }
			col.head = ns.W:Text(h, ns.W.FONT.mini)
			col.head:SetJustifyH("LEFT")
			colBtn[ci] = col
		end

		col.head:SetParent(h)
		col.head:ClearAllPoints()
		col.head:SetPoint("TOPLEFT", h, "TOPLEFT", 2, 0)
		col.head:SetHeight(ns.Dock:BHeadHeight())
		-- THE NAME IS BOUNDED BY ITS COLUMN'S WIDTH. Without this a long name
		-- draws as far as it likes, which with five columns side by side is on
		-- top of the one next to it.
		col.head:SetWidth(ns.Dock:ColWidth())
		col.head:Show()

		for i = 1, ns.Dock.B_SLOTS do
			local c = cells[i]
			if c then
				PlaceSquare(SpellButton(col.spells, i, h, c.w, "group"), h, c)
			elseif col.spells[i] then
				col.spells[i]:Hide()
			end
		end
	end

	-- The columns left over from an earlier layout. `#colBtn` is no good as a
	-- limit: it is filled by index and a drop from five to two can leave holes
	-- that `#` cuts short of. It gets walked with `pairs`.
	for ci, col in pairs(colBtn) do
		if ci > #cols then
			if col.head then col.head:Hide() end
			HideAll(col.spells)
		end
	end
end

--- Refresh -----------------------------------------------------------------

function C:Refresh()
	if not self.active then return end
	local aiming = ns.Skills:Aiming()

	if ns.Dock:State() == "A" then
		local owner = ns.Dock:Subject()
		if not owner then return end

		if headName then
			local c = ns.W:ClassColor(ns.Selection:UnitFor(owner) or "player")
			headName:SetText(Clip(owner, NAME_A))
			headName:SetTextColor(c.r, c.g, c.b)
		end
		local slots = ns.Skills:Slots(owner, ns.Dock.MAIN_TOTAL, "main")
		for i = 1, ns.Dock.MAIN_TOTAL do
			local b = spellBtn[i]
			if b and b:IsShown() then PaintSpell(b, owner, i, slots[i], aiming, "main") end
		end
		return
	end

	local cols = ns.Dock:Columns()
	for ci, m in ipairs(cols) do
		local col = colBtn[ci]
		if col then
			local c = ns.W:ClassColor(m.unit)
			col.head:SetText(Clip(m.name, NAME_B))
			col.head:SetTextColor(c.r, c.g, c.b)

			local slots = ns.Skills:Slots(m.name, ns.Dock.B_SLOTS, "group")
			for i = 1, ns.Dock.B_SLOTS do
				local b = col.spells[i]
				if b and b:IsShown() then
					PaintSpell(b, m.name, i, slots[i], aiming, "group", ci)
				end
			end
		end
	end
end

--- The second click of look after ------------------------------------------

-- Called from `RTSMode` when there is a focus pending. Returns true if it has
-- eaten the click.
function C:AimAt(guid, label)
	local who = self.pendingFocus
	if not who then return false end
	self.pendingFocus = nil

	if not guid then
		ns.Print("|cff888888look after: cancelled.|r")
		self:Refresh()
		return true
	end

	self:PointAt(who, guid, label)
	self:Refresh()
	return true
end

function C:CancelAim()
	if not self.pendingFocus then return false end
	self.pendingFocus = nil
	self:Refresh()
	return true
end

--- Entering and leaving ----------------------------------------------------

function C:Enter()
	self.active = true

	-- LAS TECLAS, AL ABRIR. No antes: fuera de la consola 1..0 son la barra de
	-- acciones del jugador y tienen que seguir siendolo.
	self:GrabKeys()

	if not self.wired then
		self.wired = true
		-- LA SALIDA DE COMBATE DEVUELVE LO QUE NO SE PUDO DEVOLVER.
		-- `SetBinding` esta bloqueada en combate, asi que cerrar la consola
		-- en mitad de una pelea dejaria 1..0 cogidas hasta la siguiente vez
		-- que se abriera -- o sea, una barra de acciones muerta sin nada que
		-- lo relacione con esto. Misma red que la de `Camera.lua` con Q/E.
		local ev = CreateFrame("Frame", "RTSCastKeyEvents")
		ev:RegisterEvent("PLAYER_REGEN_ENABLED")
		ev:RegisterEvent("PLAYER_LEAVING_WORLD")
		ev:SetScript("OnEvent", function()
			if not C.active then C:ReleaseKeys() end
		end)
		ns.Dock:OnLayout(function() C:Layout() end)
		ns.Skills:Subscribe(function() C:Refresh() end)
		ns.Selection:Subscribe(function() C:Refresh() end)

		-- LO QUE ENFRIA AHORA MISMO. Ver `AskCooldowns`: vienen solo los que
		-- estan enfriando, y "-" significa NINGUNO -- que no es lo mismo que
		-- que no haya contestado nadie. Sin ese caso, una rueda puesta se
		-- quedaria girando despues de que el hechizo ya estuviera listo.
		ns.Link:On("CD", function(rest)
			local who, list = rest:match("^(%S+)%s+(%S+)$")
			if not who then return end
			cdOwner, cdCache = who, {}
			if list ~= "-" then
				for id, rem, tot in list:gmatch("(%d+):(%d+):(%d+)") do
					id, rem, tot = tonumber(id), tonumber(rem), tonumber(tot)
					-- El arranque se despeja: con el total y lo que queda, el
					-- momento en que empezo es resta. Es lo que la rueda pide.
					cdCache[id] = { start = GetTime() - (tot - rem) / 1000,
					                dur = tot / 1000 }
				end
			end
			C:Refresh()
		end)

		-- EL LATIDO. Una vez por segundo, y solo mientras la consola mira a un
		-- bot: `AskCooldowns` se calla sola en cualquier otro caso.
		local tick = CreateFrame("Frame", "RTSCastCdTick")
		tick:SetScript("OnUpdate", function() C:AskCooldowns() end)

		ns.Link:On("PFOCUS", function(rest)
			-- TWO DIRECTIONS: we send `PFOCUS <bot> <guid>` and the reply comes
			-- back with a third field (hostile 0/1). That is what tells them
			-- apart, and without it our own echo would light up the state
			-- without the server having said a thing.
			local bot, guid, hostile = rest:match("^(%S+)%s+(%S+)%s+([01])$")
			if not bot then return end
			C.focus[bot] = (guid ~= "-") and guid or nil
			C:Refresh()
		end)
	end

	self:Layout()
end

function C:Leave()
	self.active = false
	self:ReleaseKeys()
	self.pendingFocus = nil
	self:HidePicker()
	HideAll(spellBtn)
	if headName then headName:Hide() end
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		HideAll(col.spells)
	end
end

function C:Report()
	local owner = ns.Dock:Subject()
	ns.Print(("|cffffff00slots of|r |cff33ccff%s|r"):format(tostring(owner)))
	ns.Print(("  looks after: %s"):format(self.focus[owner] or "|cff888888nobody|r"))
	ns.Print("  the spell list: |cffffff00/rts skills|r")
end

ns.Dock:Register(C)
