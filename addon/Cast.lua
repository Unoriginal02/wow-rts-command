--[[
	Cast.lua -- los huecos de hechizo de la barra de abajo.

	Es el contenido de la parte IZQUIERDA del `Dock`, y dibuja los dos estados
	que el decide:

	  A  ninguno o uno   el nombre y DIEZ huecos
	  B  dos o mas       por columna: nombre y 2x2 de CUATRO

	Los datos y las acciones no estan aqui: `Skills.lua` los tiene. Aqui esta el
	DIBUJO y el GESTO. En el estado B hay hasta cinco columnas pidiendo lo mismo
	a la vez, y con la logica dentro del panel serian cinco copias de todo.

	=== LOS MACROS SE FUERON DE AQUI ======================================

	Hasta el 2026-09-13 este fichero dibujaba tambien cuatro barras de macro por
	personaje, con un catalogo de doce acciones ESCRITAS EN EL CODIGO (`stay`,
	`follow`, `max dps`...). Se fueron enteras: las ordenes a los bots son ahora
	macros del juego de verdad, en la bandeja de la derecha (`Tray.lua`), y el
	catalogo que las crea es el de `Macros.lua`, que ya existia.

	Lo unico que sobrevivio de aquel catalogo es CUIDAR (`PFOCUS`), y no por
	nostalgia: es la unica de las doce que no cabe en un macro, porque necesita
	un segundo click para elegir sobre quien. Vive aqui como gesto y se dispara
	desde `/rts focus`, que SI cabe en un macro.

	=== LOS CUATRO DEL ESTADO B NO SON LOS CUATRO PRIMEROS DE LOS DIEZ =====

	Son otro juego (`Skills`: "group"). La razon esta en `Dock.lua`.

	=== EL GESTO DE §5, Y LA LUZ CIRCULAR =================================

	Pulsar un hueco cuyo hechizo necesita objetivo no lo manda: lo deja ARMADO,
	y el icono se pone a dar vueltas con **la luz de las mascotas de cazador**.
	El siguiente click elige sobre quien -- en un marco del juego o en el mundo
	3D, indistintamente.

	LA LUZ ES DEL CLIENTE Y NO SE REIMPLEMENTA. Sacado de leer su FrameXML
	(`Data\esES\patch-esES.MPQ`, ver `CLAUDE.md`), no de memoria:

	  * `AutoCastShineTemplate` (UIPanelTemplates.xml:699) son 16 texturas de
	    chispa con su `OnLoad`, y es una plantilla VIRTUAL corriente.
	  * `AutoCastShine_AutoCastStart(frame, r, g, b)` la enciende y
	    `..._AutoCastStop(frame)` la apaga (UIParent.lua:3477,3494).
	  * **LA ANIMACION SALE GRATIS**: la mueve el `OnUpdate` de `UIParent`.

	Y UNA TRAMPA: `AutoCastShine_OnLoad` busca sus chispas por nombre
	(`_G[name..i]`), asi que **el frame TIENE que tener nombre**.

	=== CONFIGURAR UN HUECO ===============================================

	CLICK DERECHO abre la lista de hechizos de ESE personaje -- que es su barra
	de acciones, no tu libro, porque tu libro no tiene la Polimorfia del mago
	(ver `Skills.lua`). "Arrastrar del libro" no puede existir para un bot y no
	es rodeable: `PickupSpell` solo coge lo que tu conoces.
]]

local ADDON, ns = ...

local C = {}
ns.Cast = C

C.active = false

local spellBtn = {}       -- i -> boton cuadrado (estado A)
local colBtn = {}         -- ci -> { head, spells = {} }
local headName
local flyout

--- Los nombres, acotados a lo largo ---------------------------------------
--
-- Un nombre de este cliente llega a doce letras, y a cuerpo 32 eso es una
-- etiqueta mas ancha que media fila de huecos: el rotulo pesaba mas que lo que
-- hay debajo, que es lo que de verdad se usa. Se corta.
--
-- SIN PUNTOS SUSPENSIVOS a proposito: los tres puntos devuelven casi todo el
-- ancho que se acaba de quitar, asi que serian el mismo problema escrito de
-- otra forma. Y un nombre cortado se reconoce igual: son los cinco de tu grupo,
-- no una lista de desconocidos.
--
-- La columna del estado B se corta antes que el rotulo grande porque es mas
-- estrecha -- ahi ya habia un `SetWidth` para que un nombre largo no se dibujara
-- encima del de al lado, pero un `SetWidth` no recorta: PARTE EN DOS LINEAS, y
-- la segunda se sale del alto de la cabecera.
local NAME_A = 10         -- el rotulo grande, encima de los diez huecos
local NAME_B = 8          -- el de cada columna

local function Clip(name, max)
	name = tostring(name or "")
	if name:len() <= max then return name end
	local cut = name:sub(1, max)
	-- No partir una letra por la mitad. En UTF-8 los bytes de continuacion van
	-- de 0x80 a 0xBF y un byte suelto se dibuja como un rombo negro; el cliente
	-- en espanol admite tildes en los nombres, asi que puede pasar.
	while cut ~= "" do
		local b = cut:byte(-1)
		if b < 0x80 or b >= 0xC0 then break end
		cut = cut:sub(1, -2)
	end
	-- Y si lo ultimo que queda es el ARRANQUE de una letra multibyte, sobra
	-- tambien: su cola se fue en el corte.
	local b = cut:byte(-1)
	if b and b >= 0xC0 then cut = cut:sub(1, -2) end
	return cut
end

--- Estado del foco --------------------------------------------------------
--
-- name -> guid, para poder dibujar quien lo lleva puesto. Lo dice el servidor
-- al confirmar, no lo suponemos nosotros: un boton que se enciende con su
-- propia peticion esconde justo el caso en el que la peticion no salio.
C.focus = {}

function C:PointAt(name, guid, label)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800cuidar:|r hace falta mod-rts.")
		return
	end
	local hex = guid and (tostring(guid):gsub("^0[xX]", "")) or "-"
	ns.SendServer("PFOCUS " .. name .. " " .. hex)
	if label then
		ns.Print(("|cff33ccff%s|r se dedica a |cffffd100%s|r."):format(name, label))
	end
end

function C:ClearFocus(name)
	if not ns.Link:HasServer() then
		ns.Print("|cffff8800cuidar:|r hace falta mod-rts.")
		return
	end
	ns.SendServer("PFOCUS " .. name .. " -")
end

-- ARMAR EL GESTO DE CUIDAR. Lo llama `/rts focus`, que es lo que el jugador
-- pone en un macro de la bandeja.
function C:StartFocus(name)
	name = name or ns.Dock:Subject()
	if not name then return end
	self.pendingFocus = name
	ns.Print(("|cffffd100Cuidar (%s):|r elige a quien; el click derecho cancela."):format(name))
	self:Refresh()
end

--- La luz de armado -------------------------------------------------------

local shineSeq = 0

-- La luz se sale del boton a proposito -- las chispas giran POR FUERA del
-- icono -- asi que con un 9% por lado no llega a pisar al vecino.
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
		-- Se remide y se resube CADA VEZ, no al crearlo: el boton cambia de
		-- nivel al reparentarse entre el estado A y el B, y un nivel puesto una
		-- sola vez se queda viejo sin dar error -- la luz volveria debajo del
		-- icono y pareceria que no sale.
		f:SetWidth(b:GetWidth() * SHINE_SCALE)
		f:SetHeight(b:GetHeight() * SHINE_SCALE)
		f:SetFrameLevel(b:GetFrameLevel() + SHINE_LIFT)
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

	-- Un Button sin plantilla no trae FontString, asi que `SetText` no dibujaria
	-- nada. Se crea a mano, como en el resto del addon.
	b.text = ns.W:Text(b, ns.W.FONT.normal)
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.text:SetJustifyH("LEFT")

	rows[i] = b
	return b
end

-- CUANTAS FILAS CABEN DE UNA VEZ. El servidor manda la barra del bot Y todo lo
-- que sabe, que son cincuenta o cien entradas segun el nivel; sin paginar, la
-- lista se dibujaria de 3.000 pixeles de alto y se leeria como "no sale".
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
			text = ("|cffffd100... anteriores|r |cff888888(%d/%d)|r"):format(page, pages),
			keep = true,
			fn = function() C:ShowPicker(anchor, entries, page - 1) end,
		})
	end
	for i = from, to do table.insert(shown, entries[i]) end
	if to < total then
		table.insert(shown, {
			icon = "Interface\\Buttons\\UI-MicroStream-Red",
			text = ("|cffffd100mas ... |r|cff888888(%d mas, %d/%d)|r"):format(
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
			-- Una fila de navegacion NO cierra la lista: vuelve a dibujarla en
			-- otra pagina.
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

-- La lista de hechizos de un personaje, para configurar un hueco. `set` dice a
-- cual de los dos juegos va -- y se escribe en la cabecera de la lista, porque
-- "el hueco 2" significa dos cosas distintas y el jugador tiene que saber cual
-- esta tocando.
function C:PickSpell(anchor, name, i, set)
	local cat = ns.Skills:Available(name)
	if #cat == 0 then
		ns.Print(("|cffff8800%s|r no tiene hechizos que ofrecer%s."):format(name,
			ns.Skills:Pending(name) and " todavia (pidiendolos...)" or
			": con el servidor al dia esto no deberia pasar -- |cffffff00/rts skills|r"))
		return
	end

	local entries = {
		{ icon = "Interface\\Icons\\INV_Misc_QuestionMark", text = "|cff888888(vaciar el hueco)|r",
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

--- Los botones de hechizo -------------------------------------------------

local function SpellButton(store, i, parent, size, set)
	local b = store[i]
	if not b then
		b = ns.W:Button(parent, size)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
				-- UN HUECO VACIO NO SE QUEDA CALLADO. Un click que no hace nada
				-- es indistinguible de un boton roto.
				ns.Print("hueco vacio: click |cffffff00derecho|r para ponerle un hechizo.")
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

local function PaintSpell(b, owner, i, s, aiming, set)
	b.owner, b.index, b.set, b.spell = owner, i, set, s and s.spellId or nil

	if not s then
		b.icon:SetTexture("Interface\\Buttons\\UI-Quickslot")
		b.icon:SetTexCoord(0, 1, 0, 1)
		b.icon:SetVertexColor(0.35, 0.35, 0.4)
		b.icon:SetAlpha(0.8)
		b.label:SetText("")
		ns.W:Tip(b, "Hueco " .. i .. " vacio",
			"Click derecho para elegir un hechizo de " .. owner .. ".")
		SetArmed(b, false)
		return
	end

	b.icon:SetTexture(s.texture)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.icon:SetAlpha(1)
	b.label:SetText("")

	-- UN HECHIZO QUE YA NO ESTA EN SU BARRA SE DIBUJA APAGADO, no se borra. El
	-- bot puede estar sin cargar o la respuesta puede no haber llegado.
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
	-- LOS TRES GESTOS, ESCRITOS. Un modificador que no se cuenta en ningun sitio
	-- es un modificador que no existe.
	extra = extra .. (info.ask
		and "\n|cff888888Click: elegir objetivo. Alt: sobre si mismo.|r"
		or  "\n|cff888888Click: se manda ya. Shift: elegir objetivo.|r")
	ns.W:Tip(b, s.name, ("%s -- %s%s\n|cff888888Click derecho: cambiar.|r"):format(
		owner, info.label, extra))

	SetArmed(b, aiming and aiming.owner == owner and aiming.slot == i
		and (aiming.set or "main") == (set or "main"))
end

--- Distribucion -----------------------------------------------------------

local function HideAll(list)
	for _, b in ipairs(list) do b:Hide() end
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
		headName = ns.W:Text(hHost, ns.W.FONT.big)
		headName:SetJustifyH("LEFT")
	end
	headName:SetParent(hHost)
	headName:ClearAllPoints()
	headName:SetPoint("BOTTOMLEFT", hHost, "BOTTOMLEFT", 2, 2)
	headName:Show()

	local cells = ns.Dock:SpellCells()
	for i = 1, ns.Dock.MAIN_N do
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
			col.head = ns.W:Text(h, ns.W.FONT.normal)
			col.head:SetJustifyH("LEFT")
			colBtn[ci] = col
		end

		col.head:SetParent(h)
		col.head:ClearAllPoints()
		col.head:SetPoint("TOPLEFT", h, "TOPLEFT", 2, 0)
		col.head:SetHeight(ns.Dock:BHeadHeight())
		-- EL NOMBRE SE ACOTA AL ANCHO DE SU COLUMNA. Sin esto un nombre largo se
		-- dibuja hasta donde quiera, que con cinco columnas pegadas es encima del
		-- de al lado.
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

	-- Las columnas que sobran de un reparto anterior. `#colBtn` no vale como
	-- tope: se llena por indice y una bajada de cinco a dos puede dejar agujeros
	-- que `#` corta antes de tiempo. Se recorre con `pairs`.
	for ci, col in pairs(colBtn) do
		if ci > #cols then
			if col.head then col.head:Hide() end
			HideAll(col.spells)
		end
	end
end

--- Refresco ---------------------------------------------------------------

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
		local slots = ns.Skills:Slots(owner, ns.Dock.MAIN_N, "main")
		for i = 1, ns.Dock.MAIN_N do
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
				if b and b:IsShown() then PaintSpell(b, m.name, i, slots[i], aiming, "group") end
			end
		end
	end
end

--- El segundo click de cuidar ---------------------------------------------

-- Llamada desde `RTSMode` cuando hay un foco pendiente. Devuelve true si se ha
-- comido el click.
function C:AimAt(guid, label)
	local who = self.pendingFocus
	if not who then return false end
	self.pendingFocus = nil

	if not guid then
		ns.Print("|cff888888cuidar: cancelado.|r")
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
		ns.Dock:OnLayout(function() C:Layout() end)
		ns.Skills:Subscribe(function() C:Refresh() end)
		ns.Selection:Subscribe(function() C:Refresh() end)

		ns.Link:On("PFOCUS", function(rest)
			-- DOS SENTIDOS: mandamos `PFOCUS <bot> <guid>` y la respuesta trae
			-- un tercer campo (hostil 0/1). Ese es el discriminante, y sin el
			-- nuestro propio eco encenderia el estado sin que el servidor haya
			-- dicho nada.
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
	HideAll(spellBtn)
	if headName then headName:Hide() end
	for _, col in pairs(colBtn) do
		if col.head then col.head:Hide() end
		HideAll(col.spells)
	end
end

function C:Report()
	local owner = ns.Dock:Subject()
	ns.Print(("|cffffff00huecos de|r |cff33ccff%s|r"):format(tostring(owner)))
	ns.Print(("  cuida de: %s"):format(self.focus[owner] or "|cff888888nadie|r"))
	ns.Print("  la lista de hechizos: |cffffff00/rts skills|r")
end

ns.Dock:Register(C)
