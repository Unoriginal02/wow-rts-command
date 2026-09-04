--[[
	Cast.lua -- los huecos de hechizo y los botones de accion.

	Es el contenido de la zona derecha de la sala, y dibuja los DOS estados que
	`Hall.lua` decide:

	  A  un personaje  ->  una fila de huecos + una fila de cuatro acciones
	  B  dos o mas     ->  una columna por personaje, con su nombre de cabecera

	Los datos y las acciones no estan aqui: `Skills.lua` los tiene. Aqui esta el
	DIBUJO y el GESTO. En el estado B hay hasta cinco columnas pidiendo lo mismo
	a la vez, y con la logica dentro del panel serian cinco copias de todo.

	=== EL GESTO DE §5, Y LA LUZ CIRCULAR ==================================

	Pulsar un hueco cuyo hechizo necesita objetivo no lo manda: lo deja ARMADO,
	y el icono se pone a dar vueltas con **la luz de las mascotas de cazador**,
	que es literalmente lo que pide el brief. El siguiente click elige sobre
	quien -- en la lista de la izquierda, en un marco de arriba o en el mundo
	3D, indistintamente.

	LA LUZ ES DEL CLIENTE Y NO SE REIMPLEMENTA. Sacado de leer su FrameXML
	(`Data\esES\patch-esES.MPQ`, ver `CLAUDE.md`), no de memoria:

	  * `AutoCastShineTemplate` (UIPanelTemplates.xml:699) son 16 texturas de
	    chispa con su `OnLoad`, y es una plantilla VIRTUAL corriente: se hereda
	    con `CreateFrame(..., "AutoCastShineTemplate")`.
	  * `AutoCastShine_AutoCastStart(frame, r, g, b)` la enciende y
	    `..._AutoCastStop(frame)` la apaga (UIParent.lua:3477,3494).
	  * **LA ANIMACION SALE GRATIS**: la mueve el `OnUpdate` de `UIParent`
	    (UIParent.xml:27), que recorre todas las encendidas. No hay que llevar
	    ningun temporizador.

	Y UNA TRAMPA: `AutoCastShine_OnLoad` busca sus chispas por nombre
	(`_G[name..i]`), asi que **el frame TIENE que tener nombre**. Sin nombre no
	da error: `self.sparkles` sale con 16 nil dentro y no se ve nada.

	El tamano tampoco es libre del todo: la animacion usa `self:GetWidth()` como
	recorrido, asi que la luz hay que redimensionarla al hueco o las chispas dan
	la vuelta por donde no es.

	=== CONFIGURAR UN HUECO ================================================

	CLICK DERECHO sobre el hueco abre la lista de hechizos de ESE personaje --
	que es su barra de acciones, no tu libro, porque tu libro no tiene la
	Polimorfia del mago (ver `Skills.lua`). Se elige y ya.

	"ARRASTRAR DEL LIBRO DE HECHIZOS" NO PUEDE EXISTIR PARA UN BOT y no es
	rodeable: `PickupSpell` solo coge lo que tu conoces. Lo que el brief pide --
	huecos vacios, configurables, por personaje -- se cumple entero; cambia el
	gesto de arrastrar a elegir.

	=== LOS CUATRO BOTONES DE ACCION =======================================

	Mismo mecanismo: click derecho para elegir que hace cada uno, de un catalogo
	de acciones de playerbot mas las nuestras. Aplican SOLO al personaje
	seleccionado, que es lo que los distingue de la rejilla 4x4 -- esa va
	siempre a todo el grupo.

	CURAR EN FOCUS NO HABIA QUE PROGRAMARLO. Es `PFOCUS`, compilado desde
	mod-rts 0.15.0: sobre un objetivo amistoso pone la lista
	`focus heal targets` de playerbots y su estrategia, que es IA suya y no una
	simulacion nuestra. Faltaba el boton. Ver `docs/HECHIZOS-COLA.md` §12.
]]

local ADDON, ns = ...

local C = {}
ns.Cast = C

C.active = false

local hosts = {}          -- key -> Frame de Hall
local spellBtn = {}       -- i -> boton (estado A)
local actBtn = {}         -- i -> boton (estado A)
local colBtn = {}         -- col -> { head = FontString, [i] = boton }
local flyout

--- Las acciones -----------------------------------------------------------
--
-- CADA UNA APLICA A UN SOLO PERSONAJE. Las que son comandos de chat de
-- playerbots van por `Orders:SendTo`, que susurra a ese bot y nada mas; las que
-- necesitan mas que una palabra van por mod-rts.
--
-- NINGUNA ES INVENTADA: `stay`, `follow`, `attack`, `flee`, `max dps`, `drink`
-- y `tank attack` son verbos de `ChatCommandHandlerStrategy.cpp`, y los roles
-- son estrategias registradas por clase en el propio mod-playerbots.

local ACTIONS = {
	{ key = "focus", label = "Focus", icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
	  aim = true,
	  tip = "Que se dedique a CUIDAR a quien elijas.\n" ..
	        "Sobre un amigo: le cura en exclusiva (`focus heal targets`).\n" ..
	        "Sobre un enemigo: se le pega y no le suelta.\n" ..
	        "Pulsa y luego elige el objetivo." },

	{ key = "unfocus", label = "Suelta", icon = "Interface\\Icons\\Spell_Shadow_Teleport",
	  tip = "Le quita el foco: vuelve a elegir objetivo por su cuenta.",
	  fn = function(name) ns.Cast:ClearFocus(name) end },

	{ key = "stay", label = "Quieto", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
	  tip = "Aguanta donde esta.",
	  fn = function(name) ns.Orders:SendTo(name, "stay") end },

	{ key = "follow", label = "Sigue", icon = "Interface\\Icons\\Ability_Rogue_Sprint",
	  tip = "Vuelve a seguirte.",
	  fn = function(name) ns.Orders:SendTo(name, "follow") end },

	{ key = "attack", label = "Ataca", icon = "Interface\\Icons\\Ability_Warrior_Cleave",
	  tip = "Ataca tu objetivo.",
	  fn = function(name) ns.Orders:SendTo(name, "attack") end },

	{ key = "maxdps", label = "A saco", icon = "Interface\\Icons\\Ability_Warrior_InnerRage",
	  tip = "Quema enfriamientos.",
	  fn = function(name) ns.Orders:SendTo(name, "max dps") end },

	{ key = "tank", label = "Tanque", icon = "Interface\\Icons\\Ability_Defend",
	  tip = "Que coja tu objetivo (`tank attack`).",
	  fn = function(name) ns.Orders:SendTo(name, "tank attack") end },

	{ key = "drink", label = "Bebe", icon = "Interface\\Icons\\INV_Drink_07",
	  tip = "Se sienta a comer y beber.",
	  fn = function(name) ns.Orders:SendTo(name, "drink") end },

	{ key = "flee", label = "Huye", icon = "Interface\\Icons\\Ability_Rogue_Feint",
	  tip = "Rompe el combate y se aleja.",
	  fn = function(name) ns.Orders:SendTo(name, "flee") end },

	{ key = "passive", label = "Pasivo", icon = "Interface\\Icons\\Spell_Nature_Sleep",
	  tip = "No hace nada por su cuenta. Sigue obedeciendo lo que le mandes.",
	  fn = function(name) ns.Cast:Role(name, "passive") end },

	{ key = "reset", label = "Reset", icon = "Interface\\Icons\\Spell_Nature_TimeStop",
	  tip = "Le devuelve el comportamiento de fabrica.\n" ..
	        "Para uno que se ha quedado con un rol viejo puesto.",
	  fn = function(name)
		if ns.Link:HasServer() then
			ns.SendServer("RESET " .. name)
		else
			ns.Orders:SendTo(name, "follow")
		end
	  end },
}

local ACT_BY_KEY = {}
for _, a in ipairs(ACTIONS) do ACT_BY_KEY[a.key] = a end

-- Los cuatro de fabrica. El primero es el caso de uso prioritario del brief.
local ACT_DEFAULT = { "focus", "stay", "follow", "attack" }

--- Estado del foco --------------------------------------------------------
--
-- name -> guid, para poder dibujar quien lo lleva puesto. Lo dice el servidor
-- al confirmar, no lo suponemos nosotros: un boton que se enciende con su
-- propia peticion esconde justo el caso en el que la peticion no salio. Es la
-- misma regla que la fila de roles de la etapa 5n.
C.focus = {}

function C:PointAt(name, guid, label)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800focus:|r hace falta mod-rts.")
		return
	end
	local hex = tostring(guid):gsub("^0[xX]", "")
	ns.SendServer("PFOCUS " .. name .. " " .. hex)
	ns.Print(("|cff33ccff%s|r -> foco en %s"):format(name, label or "eso"))
end

function C:ClearFocus(name)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800focus:|r hace falta mod-rts.")
		return
	end
	ns.SendServer("PFOCUS " .. name .. " -")
end

function C:Role(name, role)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800rol:|r hace falta mod-rts.")
		return
	end
	ns.SendServer("ROLE " .. name .. " " .. role .. " 1")
end

--- La configuracion de las acciones ---------------------------------------

local function ActionStore(name, create)
	if not RTSCommandDB then return nil end
	local hall = RTSCommandDB.hall
	if not hall then
		if not create then return nil end
		hall = {}
		RTSCommandDB.hall = hall
	end
	hall.who = hall.who or {}
	local w = hall.who[name]
	if not w and create then
		w = { spells = {}, actions = {} }
		hall.who[name] = w
	end
	return w
end

function C:ActionFor(name, i)
	local w = ActionStore(name, false)
	local key = w and w.actions and w.actions[i]
	return ACT_BY_KEY[key] or ACT_BY_KEY[ACT_DEFAULT[i] or ""]
end

function C:SetAction(name, i, key)
	local w = ActionStore(name, true)
	if not w then return end
	-- Congelar lo que se estaba ensenando la primera vez, o cambiar el tercero
	-- borraria los otros tres -- que eran los de fabrica y no estaban guardados.
	-- Mismo caso que `Skills:SetSlot`.
	if not next(w.actions) then
		for k = 1, ns.Hall.ACT_N do w.actions[k] = ACT_DEFAULT[k] end
	end
	w.actions[i] = key
	self:Layout()
end

--- La luz circular --------------------------------------------------------

-- Se crea bajo demanda y se guarda en el boton. Hace falta NOMBRE, ver la
-- cabecera: sin el, `AutoCastShine_OnLoad` no encuentra sus chispas y no se ve
-- nada -- sin dar error.
local shineSeq = 0

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
		-- El recorrido de la animacion es `GetWidth()`, asi que la luz tiene que
		-- medir lo que el boton o las chispas dan la vuelta por donde no es.
		f:SetWidth(b:GetWidth())
		f:SetHeight(b:GetHeight())
		AutoCastShine_AutoCastStart(f)
	elseif type(_G.AutoCastShine_AutoCastStop) == "function" then
		AutoCastShine_AutoCastStop(f)
	end
end

--- El desplegable de eleccion ---------------------------------------------

local ROW_H = 34
local rows = {}

local function EnsureFlyout()
	if flyout then return flyout end
	flyout = CreateFrame("Frame", "RTSCastPicker", ns.Bar:SlotFrame("hall"))
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

	-- Un Button sin plantilla no trae FontString, asi que `SetText` no dibujaria
	-- nada. Se crea a mano, como en el resto del addon.
	b.text = ns.W:Text(b, ns.W.FONT.normal)
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetJustifyH("LEFT")

	rows[i] = b
	return b
end

-- `entries` = { { icon, text, sub, fn }, ... }
function C:ShowPicker(anchor, title, entries)
	EnsureFlyout()

	local w = 340
	local n = 0
	for i, e in ipairs(entries) do
		local b = FlyoutRow(i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4, -(6 + (i - 1) * (ROW_H + 2)))
		b:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -4, -(6 + (i - 1) * (ROW_H + 2)))
		b.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		b.text:SetText(e.text .. (e.sub and (" |cff888888" .. e.sub .. "|r") or ""))
		b:SetScript("OnClick", function()
			flyout:Hide()
			local ok, err = pcall(e.fn)
			if not ok then ns.Print("|cffff0000sala:|r " .. tostring(err)) end
		end)
		b:Show()
		n = i
	end
	for i = n + 1, #rows do rows[i]:Hide() end

	flyout:SetWidth(w)
	flyout:SetHeight(n * (ROW_H + 2) + 12)
	flyout:ClearAllPoints()
	flyout:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 8)
	flyout:Show()
end

function C:HidePicker()
	if flyout then flyout:Hide() end
end

-- La lista de hechizos de un personaje, para configurar un hueco.
function C:PickSpell(anchor, name, i)
	local cat = ns.Skills:Available(name)
	local entries = {
		{ icon = "Interface\\Icons\\INV_Misc_QuestionMark", text = "|cff888888(vaciar el hueco)|r",
		  fn = function() ns.Skills:SetSlot(name, i, nil) end },
	}
	for _, s in ipairs(cat) do
		local info = ns.Skills:TypeInfo(s.type)
		table.insert(entries, {
			icon = s.texture, text = s.name, sub = info.label,
			fn = function() ns.Skills:SetSlot(name, i, s.spellId) end,
		})
	end

	if #cat == 0 then
		ns.Print(("|cffff8800%s|r no tiene hechizos que ofrecer%s."):format(name,
			ns.Skills:Pending(name) and " todavia (pidiendolos...)" or
			": entra con el una vez y ponle hechizos en la barra"))
		return
	end

	self:ShowPicker(anchor, name, entries)
end

function C:PickAction(anchor, name, i)
	local entries = {}
	for _, a in ipairs(ACTIONS) do
		table.insert(entries, {
			icon = a.icon, text = a.label,
			fn = function() C:SetAction(name, i, a.key) end,
		})
	end
	self:ShowPicker(anchor, name, entries)
end

--- Los botones ------------------------------------------------------------

local function SpellButton(store, i, parent, size)
	local b = store[i]
	if not b then
		b = ns.W:Button(parent, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if not self.owner then return end
			if button == "RightButton" then
				C:PickSpell(self, self.owner, self.index)
				return
			end
			C:HidePicker()
			if self.spell then
				ns.Skills:Use(self.owner, self.index)
			else
				-- UN HUECO VACIO NO SE QUEDA CALLADO. Un click que no hace nada
				-- es indistinguible de un boton roto, y ese es justo el fallo
				-- que este proyecto persigue desde la etapa 5i.
				ns.Print("hueco vacio: click |cffffff00derecho|r para ponerle un hechizo.")
			end
		end)
		store[i] = b
	end
	return b
end

local function PaintSpell(b, owner, i, s, aiming)
	b.owner, b.index, b.spell = owner, i, s and s.spellId or nil

	if not s then
		b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
		b.icon:SetTexCoord(0, 1, 0, 1)
		b.icon:SetVertexColor(0.35, 0.35, 0.4)
		b.icon:SetAlpha(0.8)
		b.label:SetText("")
		ns.W:Tip(b, "Hueco vacio", "Click derecho para elegir un hechizo de " .. owner .. ".")
		SetArmed(b, false)
		return
	end

	b.icon:SetTexture(s.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	-- UN HECHIZO QUE YA NO ESTA EN SU BARRA SE DIBUJA APAGADO, no se borra. El
	-- bot puede estar sin cargar o la respuesta puede no haber llegado; tirar la
	-- configuracion del jugador por eso seria perderla sin avisar.
	if s.stale then
		b.icon:SetVertexColor(0.55, 0.4, 0.4)
	else
		b.icon:SetVertexColor(1, 1, 1)
	end

	local info = ns.Skills:TypeInfo(s.type)
	local extra = s.stale and "\n|cffff8800ya no esta en su barra|r" or ""
	local q = ns.Skills:QueuedFor(owner)
	if q and q.id == s.spellId then
		extra = extra .. "\n|cffffd100en cola, esperando hueco|r"
	end
	ns.W:Tip(b, s.name, ("%s -- %s%s\n|cff888888Click derecho: cambiar.|r"):format(
		owner, info.label, extra))

	SetArmed(b, aiming and aiming.owner == owner and aiming.slot == i)
end

local function ActionButton(i, parent, size)
	local b = actBtn[i]
	if not b then
		b = ns.W:Button(parent, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if not self.owner then return end
			if button == "RightButton" then
				C:PickAction(self, self.owner, self.index)
				return
			end
			C:HidePicker()
			local a = self.act
			if not a then return end

			-- LAS QUE PIDEN OBJETIVO USAN EL MISMO ARMADO QUE LOS HECHIZOS, y
			-- eso no es reutilizar por reutilizar: es que el jugador ya sabe
			-- que un icono dando vueltas significa "elige a quien", y tener dos
			-- gestos para lo mismo seria peor que tener uno.
			if a.aim then
				C.pendingFocus = self.owner
				ns.Print(("|cffffd100%s:|r elige a quien cuidar; el derecho cancela."):format(a.label))
				C:Refresh()
				return
			end
			if a.fn then a.fn(self.owner) end
		end)
		actBtn[i] = b
	end
	return b
end

--- Distribucion -----------------------------------------------------------

function C:Layout()
	if not self.active then return end

	local st = ns.Hall:State()
	if st == "A" then
		self:LayoutA()
	else
		self:LayoutB()
	end
	self:Refresh()
end

function C:LayoutA()
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		for i, b in ipairs(col) do b:Hide() end
	end

	local sHost = ns.Hall:Host("spells")
	local aHost = ns.Hall:Host("actions")
	hosts.spells, hosts.actions = sHost, aHost

	local cells = ns.Hall:SpellCells()
	for i = 1, ns.Hall.slots do
		local c = cells[i]
		local b = spellBtn[i]
		if c then
			b = SpellButton(spellBtn, i, sHost, c.w)
			b:SetParent(sHost)
			b:SetWidth(c.w)
			b:SetHeight(c.h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", sHost, "TOPLEFT", c.x, -c.y)
			b:Show()
		elseif b then
			b:Hide()
		end
	end
	for i = ns.Hall.slots + 1, #spellBtn do spellBtn[i]:Hide() end

	local acells = ns.Hall:ActionCells()
	for i = 1, ns.Hall.ACT_N do
		local c = acells[i]
		local b = actBtn[i]
		if c then
			b = ActionButton(i, aHost, c.w)
			b:SetParent(aHost)
			b:SetWidth(c.w)
			b:SetHeight(c.h)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", aHost, "TOPLEFT", c.x, -c.y)
			b:Show()
		elseif b then
			b:Hide()
		end
	end
end

function C:LayoutB()
	for i, b in ipairs(spellBtn) do b:Hide() end
	for i, b in ipairs(actBtn) do b:Hide() end

	local cols = ns.Hall:Columns()
	local cells = ns.Hall:ColumnCells()

	for ci = 1, #cols do
		local host = ns.Hall:Host("col" .. ci)
		local col = colBtn[ci]
		if not col then
			col = {}
			col.head = ns.W:Text(host, ns.W.FONT.normal)
			col.head:SetJustifyH("CENTER")
			colBtn[ci] = col
		end
		col.head:SetParent(host)
		col.head:ClearAllPoints()
		col.head:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
		col.head:SetWidth(ns.Hall.colW or 100)
		col.head:SetHeight(ns.Hall:HeadHeight())
		col.head:Show()

		for i = 1, ns.Hall.slots do
			local c = cells[i]
			local b = col[i]
			if c then
				if not b then
					b = SpellButton(col, i, host, c.w)
				end
				b:SetParent(host)
				b:SetWidth(c.w)
				b:SetHeight(c.h)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", host, "TOPLEFT", c.x, -c.y)
				b:Show()
			elseif b then
				b:Hide()
			end
		end
		for i = ns.Hall.slots + 1, #col do
			if col[i] then col[i]:Hide() end
		end
	end

	-- Las columnas que sobran de un reparto anterior.
	-- Las columnas que sobran de un reparto anterior. `#colBtn` no vale como
	-- tope: `colBtn` se llena por indice y una bajada de cinco a dos deja
	-- agujeros que `#` puede cortar antes de tiempo. Se recorre con `pairs`.
	for ci, col in pairs(colBtn) do
		if ci > #cols then
			if col.head then col.head:Hide() end
			for _, b in ipairs(col) do b:Hide() end
		end
	end
end

--- Refresco ---------------------------------------------------------------

function C:Refresh()
	if not self.active then return end
	local aiming = ns.Skills:Aiming()

	if ns.Hall:State() == "A" then
		local owner = ns.Hall:Subject()
		local slots = ns.Skills:Slots(owner)
		for i = 1, ns.Hall.slots do
			local b = spellBtn[i]
			if b and b:IsShown() then PaintSpell(b, owner, i, slots[i], aiming) end
		end

		for i = 1, ns.Hall.ACT_N do
			local b = actBtn[i]
			if b and b:IsShown() then
				local a = self:ActionFor(owner, i)
				b.owner, b.index, b.act = owner, i, a
				if a then
					b.icon:SetTexture(a.icon)
					b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
					b.label:SetText(a.label)
					ns.W:Tip(b, a.label, ("%s\n|cff888888-> %s. Click derecho: cambiar.|r"):format(
						a.tip, owner))
					-- El foco encendido se dibuja, y lo dice el SERVIDOR: un
					-- boton que se enciende con su propia peticion esconde el
					-- caso en que la peticion no salio.
					local lit = (a.key == "focus" and self.focus[owner]) and true or false
					ns.W:Enable(b, true)
					if lit then
						b.label:SetTextColor(1, 0.82, 0.2)
					else
						b.label:SetTextColor(1, 1, 1)
					end
					SetArmed(b, a.aim and self.pendingFocus == owner)
				else
					b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
					b.label:SetText("")
					SetArmed(b, false)
				end
			end
		end
		return
	end

	local cols = ns.Hall:Columns()
	for ci, m in ipairs(cols) do
		local col = colBtn[ci]
		if col then
			local c = ns.W:ClassColor(m.unit)
			col.head:SetText(m.name)
			col.head:SetTextColor(c.r, c.g, c.b)
			local slots = ns.Skills:Slots(m.name)
			for i = 1, ns.Hall.slots do
				local b = col[i]
				if b and b:IsShown() then PaintSpell(b, m.name, i, slots[i], aiming) end
			end
		end
	end
end

--- El segundo click de una accion que apunta ------------------------------

-- Llamada desde `RTSMode`, `Party` y `Frames` cuando hay un foco pendiente.
-- Devuelve true si se ha comido el click.
function C:AimAt(guid, label)
	local who = self.pendingFocus
	if not who then return false end
	self.pendingFocus = nil

	if not guid then
		ns.Print("|cff888888foco: cancelado.|r")
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

--- Entrar y salir ---------------------------------------------------------

function C:Enter()
	self.active = true

	if not self.wired then
		self.wired = true
		ns.Hall:OnLayout(function() C:Layout() end)
		ns.Skills:Subscribe(function() C:Refresh() end)
		ns.Selection:Subscribe(function() C:Refresh() end)

		ns.Link:On("PFOCUS", function(rest)
			-- DOS SENTIDOS: mandamos `PFOCUS <bot> <guid>` y la respuesta trae
			-- un tercer campo (hostil 0/1). Ese es el discriminante, y sin el
			-- nuestro propio eco encenderia el boton sin que el servidor haya
			-- dicho nada -- que es exactamente lo que este boton existe para no
			-- hacer.
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
	self.pendingFocus = nil
	self:HidePicker()
	for _, b in ipairs(spellBtn) do b:Hide() end
	for _, b in ipairs(actBtn) do b:Hide() end
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		for _, b in ipairs(col) do b:Hide() end
	end
end

function C:Report()
	local owner = ns.Hall:Subject()
	ns.Print(("|cffffff00acciones de|r |cff33ccff%s|r"):format(tostring(owner)))
	for i = 1, ns.Hall.ACT_N do
		local a = self:ActionFor(owner, i)
		ns.Print(("  %d. %s"):format(i, a and a.label or "|cff666666vacio|r"))
	end
	ns.Print(("foco: %s"):format(self.focus[owner] or "|cff888888ninguno|r"))
end

ns.Hall:Register(C)
