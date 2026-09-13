--[[
	Bags.lua -- las bolsas de todo el grupo en una ventana, y pasar objetos.

	=== EL GESTO NO ES ARRASTRAR, Y NO ES UN CAPRICHO ========================

	El cursor de objetos de WoW (`PickupContainerItem` y compania) esta atado al
	inventario REAL del jugador: coge un objeto de una casilla de verdad y lo
	suelta en otra casilla de verdad. Nuestras casillas no son casillas suyas --
	son dibujos de las bolsas de OTRO personaje, que el servidor nos ha contado
	-- asi que no hay forma de meter eso en su cursor sin mentirle al cliente
	sobre lo que tiene en las manos.

	Asi que se coge con un click y se suelta con otro, y el objeto cogido va
	pegado al raton en un frame nuestro. Ademas de ser lo unico posible, es el
	gesto de WC3, que es la interfaz que este proyecto imita.

	=== `GetItemInfo` DEVUELVE nil Y NO DA ERROR ============================

	Esta es la trampa de este fichero, y es de la familia que este proyecto
	persigue desde la etapa 5i: el cliente solo conoce los objetos que ha visto
	en esta sesion. Un objeto en la bolsa de un bot que tu no has tocado nunca no
	esta en su cache, y `GetItemInfo` devuelve **nil sin quejarse**. El resultado
	seria una ventana con casillas vacias al azar -- vacias justo donde hay algo
	-- y ademas INTERMITENTE, porque se arreglan solas en cuanto el objeto pasa
	por delante del cliente por cualquier otro motivo.

	Dos cosas lo cierran:

	  * el SERVIDOR manda la cantidad y la calidad, asi que una casilla sin
	    cache se dibuja como un cuadro del color de su rareza con su numero
	    encima. Se ve que hay algo y de que clase, que es el 80% de lo que hace
	    falta para decidir moverlo.
	  * y se PIDE la cache con un tooltip invisible propio
	    (`GameTooltip:SetHyperlink` sobre un scanner nuestro), que es lo que hace
	    que el cliente consulte al servidor. En el siguiente latido ya hay icono
	    y nombre.

	El scanner es NUESTRO y no el `GameTooltip` compartido: ese es el que dibuja
	los tooltips de verdad, y pedirle una cache mientras el raton esta encima de
	un boton le borraria lo que estaba ensenando.

	=== POR QUE EL REFRESCO ES "VUELVE A PREGUNTAR" =========================

	Tras un movimiento el servidor contesta `BAGOK <de> <a>` y este fichero
	vuelve a pedir las bolsas de los dos. No aplica el cambio por su cuenta a
	proposito: saber donde CAE un objeto es simular el almacenamiento del nucleo
	(pilas que se juntan, bolsas de tipo, el hueco que elige `CanStoreItem`), y
	en cuanto esa simulacion se equivoca una vez la ventana ensena algo que no
	existe hasta el siguiente refresco -- que es peor que ir medio segundo tarde.
]]

local ADDON, ns = ...

local B = {}
ns.Bags = B

--- Medidas, en unidades de DIBUJO ------------------------------------------

-- LAS CASILLAS SALIERON DEMASIADO GRANDES, y el numero explica por que.
--
-- `PRUEBAS-20` A7: *"los iconos se ven SUPER GRANDES"*. La primera version uso
-- 74, copiado del boton de bolsa de los railes -- pero esta ventana lleva la
-- escala de pixel de `Pixels.lua`, o sea que **1 unidad de aqui es 1 pixel fisico**.
-- 74 px es MAS GRANDE que un boton de la barra de acciones, que en esta
-- pantalla mide 62, medido contra `ActionButton1`. Una casilla de bolsa tiene
-- que ser mas pequena que un boton de accion, no mayor.
--
-- 40 px es aproximadamente lo que mide una casilla de mochila del cliente, que
-- es la medida que el jugador ya tiene calibrada -- la misma regla que hizo que
-- el alto de la barra se calcara de `ActionButton1` en la etapa 5i.
local SLOT   = 40
local GAP    = 4
local COLS   = 6      -- casillas por fila dentro del panel de un personaje
local ROWS   = 6      -- filas VISIBLES; el resto se pasa con la rueda
-- EL RETRATO ES DE QUIEN SON LAS BOLSAS, y es lo que convierte una columna con
-- un nombre encima en la mochila DE alguien. Pedido con la mochila del cliente
-- delante: *"donde pone Mochila que sea el nombre, y donde la bolsa el avatar
-- del personaje propietario"*.
--
-- 36 y no mas: la cabecera tiene que caber en el alto que ya tenia sin comerse
-- filas de casillas, que es lo que la ventana esta aqui para ensenar.
local PORT   = 36
local HEAD   = PORT + 16   -- cabecera: retrato, nombre y huecos libres
-- Y EL DINERO ABAJO, EN SU PROPIA FRANJA. Es donde lo pone la mochila del
-- cliente, y ahi tiene un sitio fijo: en la cabecera compartia linea con los
-- huecos libres y las dos cifras se leian como una sola.
local FOOT   = 26
local COLGAP = 14
local PAD    = 10

local COLW = COLS * SLOT + (COLS - 1) * GAP
local VIEWH = ROWS * SLOT + (ROWS - 1) * GAP

--- Estado ------------------------------------------------------------------

-- name -> { conts = {{bag,size}}, items = {[bag..":"..slot] = {...}},
--           copper, free, staging }
local data = {}
local columns = {}        -- dibujados, en orden
local held = nil          -- { owner, guid, itemId, quality, count }
local win, sheet, holder

--- Utilidades --------------------------------------------------------------

local scanner

local function Scanner()
	if scanner then return scanner end
	scanner = CreateFrame("GameTooltip", "RTSBagsScanner", nil, "GameTooltipTemplate")
	scanner:SetOwner(UIParent, "ANCHOR_NONE")
	return scanner
end

-- Pedirle al cliente que se traiga un objeto que no conoce. No devuelve nada:
-- la respuesta llega cuando llega, y el siguiente redibujado la encuentra.
local function AskCache(itemId)
	local s = Scanner()
	s:ClearLines()
	s:SetHyperlink("item:" .. itemId)
end

local QUALITY = {
	[0] = { 0.62, 0.62, 0.62 },   -- gris
	[1] = { 1.00, 1.00, 1.00 },   -- comun
	[2] = { 0.12, 1.00, 0.00 },   -- infrecuente
	[3] = { 0.00, 0.44, 0.87 },   -- raro
	[4] = { 0.64, 0.21, 0.93 },   -- epico
	[5] = { 1.00, 0.50, 0.00 },   -- legendario
	[6] = { 0.90, 0.80, 0.50 },   -- artefacto
}

local function QualityColor(q)
	return QUALITY[q or 1] or QUALITY[1]
end

local function Money(copper)
	copper = tonumber(copper) or 0
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then return string.format("|cffffd700%d|ro |cffc7c7cf%d|rp %dc", g, s, c) end
	if s > 0 then return string.format("|cffc7c7cf%d|rp %dc", s, c) end
	return string.format("%dc", c)
end

--- El canal ----------------------------------------------------------------

local function Entry(name)
	data[name] = data[name] or {}
	return data[name]
end

function B:Request(name)
	if not name or name == "" then return end
	local d = Entry(name)
	-- El buffer se vacia AL PEDIR y no al recibir el primer trozo: si se
	-- vaciara al recibir, dos peticiones seguidas mezclarian la respuesta vieja
	-- con la nueva y saldrian objetos duplicados.
	d.staging = { conts = {}, items = {} }
	ns.SendServer("BAGS " .. name)
end

function B:RequestAll()
	for _, u in ipairs(ns.Selection:GetRosterWithPlayer()) do
		self:Request(u.name)
	end
end

local function ParsePiece(d, piece)
	local kind = piece:sub(1, 1)
	local rest = piece:sub(2)

	if kind == "B" then
		local bag, size = rest:match("^(%d+),(%d+)$")
		if bag then
			table.insert(d.staging.conts, { bag = tonumber(bag), size = tonumber(size) })
		end
		return
	end

	if kind == "I" then
		local bag, slot, guid, id, count, q, flags =
			rest:match("^(%d+),(%d+),(%x+),(%d+),(%d+),(%d+),(%d+)$")
		if not bag then return end
		d.staging.items[bag .. ":" .. slot] = {
			bag = tonumber(bag), slot = tonumber(slot),
			guid = guid, itemId = tonumber(id),
			count = tonumber(count), quality = tonumber(q), flags = tonumber(flags),
		}
	end
end

--- Dibujo ------------------------------------------------------------------

local function ItemTip(cell)
	if not cell.item then return end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. cell.item.itemId)
	GameTooltip:Show()
end

local function PaintCell(cell, item)
	cell.item = item

	if not item then
		cell.icon:Hide()
		cell.block:Hide()
		cell.count:SetText("")
		cell.border:SetVertexColor(0.35, 0.35, 0.38, 0.8)
		return
	end

	local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(item.itemId)
	if texture then
		cell.icon:SetTexture(texture)
		cell.icon:Show()
		cell.block:Hide()
	else
		-- Sin cache todavia: cuadro del color de la rareza y a pedirla. Ver la
		-- cabecera -- esto es lo que evita que la ventana parezca rota.
		local c = QualityColor(item.quality)
		cell.icon:Hide()
		cell.block:SetTexture(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1)
		cell.block:Show()
		AskCache(item.itemId)
	end

	cell.count:SetText(item.count > 1 and item.count or "")

	local c = QualityColor(item.quality)
	cell.border:SetVertexColor(c[1], c[2], c[3], 1)

	-- Vinculado: se ve, y se ve ANTES de intentar moverlo. Un objeto que no se
	-- deja coger sin decir por que se lee como que la ventana no responde.
	cell:SetAlpha(ns.W:Flag(item.flags, 1) and 0.45 or 1)
end

local function NewCell(parent, owner)
	local cell = CreateFrame("Button", nil, parent)
	cell:SetWidth(SLOT)
	cell:SetHeight(SLOT)
	cell.owner = owner

	cell.bg = cell:CreateTexture(nil, "BACKGROUND")
	cell.bg:SetAllPoints()
	cell.bg:SetTexture(0, 0, 0, 0.55)

	cell.block = cell:CreateTexture(nil, "ARTWORK")
	cell.block:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -4)
	cell.block:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 4)
	cell.block:Hide()

	cell.icon = cell:CreateTexture(nil, "ARTWORK")
	cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 3, -3)
	cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
	cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	cell.icon:Hide()

	cell.border = cell:CreateTexture(nil, "OVERLAY")
	cell.border:SetAllPoints()
	cell.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	cell.border:SetBlendMode("ADD")
	cell.border:SetAlpha(0.35)

	cell.count = ns.W:Text(cell, ns.W.FONT.small, "OVERLAY")
	cell.count:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 4)

	local hl = cell:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(1, 1, 1, 0.18)

	cell:SetScript("OnEnter", ItemTip)
	cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell:SetScript("OnClick", function(self, button)
		B:Clicked(self, button)
	end)

	return cell
end

--- Coger y soltar ----------------------------------------------------------

local function ShowHeld()
	if not holder then return end
	if not held then
		holder:Hide()
		return
	end
	local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(held.itemId)
	if texture then
		holder.icon:SetTexture(texture)
	else
		local c = QualityColor(held.quality)
		holder.icon:SetTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
	end
	holder:Show()
end

function B:Drop()
	held = nil
	ShowHeld()
end

function B:Clicked(cell, button)
	if button == "RightButton" then
		-- Soltar lo que llevas sin moverlo. Tiene que existir: sin cancelar, un
		-- objeto cogido por error se queda pegado al raton y la unica salida es
		-- soltarlo en algun sitio, o sea moverlo.
		if held then
			self:Drop()
			ns.Print("bolsas: soltado.")
		end
		return
	end

	if held then
		if held.owner == cell.owner then
			-- Mismo personaje: eso seria reordenar su propia bolsa, que no es lo
			-- que hace esta ventana. Se cancela en vez de mandar una orden que
			-- el servidor rechazaria.
			self:Drop()
			return
		end
		ns.SendServer("BAGMOVE " .. held.owner .. " " .. cell.owner .. " " .. held.guid)
		self:Drop()
		return
	end

	if not cell.item then return end
	if ns.W:Flag(cell.item.flags, 1) then
		ns.Print("bolsas: |cffff8800" .. (GetItemInfo(cell.item.itemId) or "eso") ..
		         "|r esta vinculado, no se puede pasar.")
		return
	end

	held = {
		owner = cell.owner, guid = cell.item.guid, itemId = cell.item.itemId,
		quality = cell.item.quality, count = cell.item.count,
	}
	ShowHeld()
end

--- Distribucion ------------------------------------------------------------
--
-- UN PANEL POR PERSONAJE, CON SU PROPIO SCROLL. Es lo que pidio `PRUEBAS-20`
-- A7: *"molaria usar un frame como el de mochila para cada integrante y que
-- tenga scroll interno en caso de que no quepan todos los objetos"*.
--
-- Y EL SCROLL TIENE QUE SER UN `ScrollFrame`, no un frame movido a mano.
-- **En 3.3.5a un frame hijo NO se recorta contra su padre** -- esta escrito en
-- este proyecto desde la etapa 5k, donde el minimapa se habria comido el borde
-- del arte por ese motivo. Un panel con las casillas dentro y desplazadas
-- hacia arriba las ensenaria igual, por encima de la cabecera y fuera del
-- marco. `ScrollFrame` es el unico tipo de frame que si recorta a su hijo, y
-- por eso hay uno por personaje en vez de un desplazamiento.

local function BuildColumn(index, name)
	local col = columns[index]
	if col then
		col.owner = name
		col:Show()
		return col
	end

	col = CreateFrame("Frame", "RTSBagsCol" .. index, sheet)
	col:SetWidth(COLW + PAD * 2)

	-- El marco, del mismo aspecto que el resto de la consola. `Skin` lo apunta
	-- en su lista, asi que `/rts skin` lo reviste en vivo como a los demas.
	if ns.Skin then ns.Skin:Dress(col, true) end

	-- El retrato del dueno, donde la mochila del cliente lleva el icono de la
	-- bolsa. Se rellena en `Layout`, que es quien sabe que unidad es cada uno.
	col.portrait = col:CreateTexture(nil, "ARTWORK")
	col.portrait:SetWidth(PORT)
	col.portrait:SetHeight(PORT)
	col.portrait:SetPoint("TOPLEFT", col, "TOPLEFT", PAD, -8)
	ns.W:Border(col, col.portrait, PORT)

	col.title = ns.W:Text(col, ns.W.FONT.small)
	col.title:SetPoint("TOPLEFT", col, "TOPLEFT", PAD + PORT + 8, -10)

	col.info = ns.W:Text(col, ns.W.FONT.tiny)
	col.info:SetPoint("TOPLEFT", col, "TOPLEFT", PAD + PORT + 8, -30)

	-- La franja del dinero, abajo del todo y con su propio fondo: sin el, una
	-- cifra suelta sobre el arte no se lee como una franja y vuelve a parecer
	-- texto perdido, que es el problema que se viene a arreglar.
	col.purse = col:CreateTexture(nil, "ARTWORK")
	col.purse:SetTexture(0, 0, 0, 0.45)
	col.purse:SetHeight(FOOT - 6)
	col.purse:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", PAD, 6)
	col.purse:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -PAD, 6)

	col.money = ns.W:Text(col, ns.W.FONT.tiny)
	col.money:SetPoint("RIGHT", col.purse, "RIGHT", -6, 0)

	-- La ventana que recorta.
	col.view = CreateFrame("ScrollFrame", "RTSBagsView" .. index, col)
	col.view:SetPoint("TOPLEFT", col, "TOPLEFT", PAD, -HEAD)
	col.view:SetWidth(COLW)
	col.view:SetHeight(VIEWH)

	col.inner = CreateFrame("Frame", "RTSBagsInner" .. index, col.view)
	col.inner:SetWidth(COLW)
	col.inner:SetHeight(VIEWH)
	col.view:SetScrollChild(col.inner)

	-- La rueda mueve ESTE panel y no los demas. Es lo que hace util tener uno
	-- por personaje: mirar las bolsas del mago no descoloca las del guerrero.
	col.view:EnableMouseWheel(true)
	col.view:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, (col.contentH or 0) - VIEWH)
		local at = math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * (SLOT + GAP)))
		self:SetVerticalScroll(at)
	end)

	col.cells = {}
	col.owner = name
	columns[index] = col
	return col
end

function B:Layout()
	if not win then return end

	local roster = ns.Selection:GetRosterWithPlayer()

	for i, u in ipairs(roster) do
		local col = BuildColumn(i, u.name)
		col:SetPoint("TOPLEFT", sheet, "TOPLEFT", (i - 1) * (COLW + PAD * 2 + COLGAP), 0)
		col:SetHeight(HEAD + VIEWH + FOOT + PAD)

		local d = data[u.name] or {}
		local cc = u.isPlayer and { 1, 0.85, 0.4 } or (ns.W:ClassColor(u.unit) or { 1, 1, 1 })
		col.title:SetText(u.name)
		col.title:SetTextColor(cc[1] or cc.r or 1, cc[2] or cc.g or 1, cc[3] or cc.b or 1)
		col.info:SetText("|cff88ff88" .. tostring(d.free or "?") .. "|r libres")
		col.money:SetText(Money(d.copper))

		-- Un bot que se acaba de ir del grupo sigue teniendo fila mientras dure
		-- este dibujado, asi que la unidad puede no existir. Sin esta guarda,
		-- `SetPortraitTexture` deja el retrato ANTERIOR puesto: la cara de otro
		-- personaje sobre las bolsas de este, que es peor que no tener cara.
		if u.unit and UnitExists(u.unit) then
			SetPortraitTexture(col.portrait, u.unit)
		else
			col.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end

		-- Las casillas, en el orden en que llegaron los contenedores: primero la
		-- mochila y luego cada bolsa equipada, que es como las ve el jugador en
		-- su propia interfaz.
		local n = 0
		for _, c in ipairs(d.conts or {}) do
			local first = (c.bag == 255) and 23 or 0
			for sl = first, first + (c.size or 0) - 1 do
				n = n + 1
				local cell = col.cells[n]
				if not cell then
					cell = NewCell(col.inner, u.name)
					col.cells[n] = cell
				end
				cell.owner = u.name
				local r = math.floor((n - 1) / COLS)
				local k = (n - 1) % COLS
				cell:SetPoint("TOPLEFT", col.inner, "TOPLEFT",
					k * (SLOT + GAP), -(r * (SLOT + GAP)))
				cell:Show()
				PaintCell(cell, (d.items or {})[c.bag .. ":" .. sl])
			end
		end
		for k = n + 1, #col.cells do col.cells[k]:Hide() end

		-- El alto del contenido decide cuanto se puede desplazar. Va aqui y no
		-- en la rueda porque cambia con el numero de bolsas, no con el gesto.
		local rows = math.max(1, math.ceil(n / COLS))
		col.contentH = rows * SLOT + (rows - 1) * GAP
		col.inner:SetHeight(math.max(VIEWH, col.contentH))
		if col.view:GetVerticalScroll() > math.max(0, col.contentH - VIEWH) then
			col.view:SetVerticalScroll(math.max(0, col.contentH - VIEWH))
		end
	end

	for i = #roster + 1, #columns do columns[i]:Hide() end

	local cols = math.max(1, #roster)
	local w = PAD * 2 + cols * (COLW + PAD * 2) + (cols - 1) * COLGAP
	local h = 46 + PAD + HEAD + VIEWH + FOOT + PAD + PAD
	win:SetSize(w, h)

	sheet:SetWidth(w - PAD * 2)
	sheet:SetHeight(HEAD + VIEWH + FOOT + PAD)
end

--- Ciclo -------------------------------------------------------------------

function B:Create()
	if win then return end

	win = ns.Window:New("RTSBags", "Bolsas del grupo", 900, 560)

	local body = win:Body()
	sheet = CreateFrame("Frame", "RTSBagsSheet", body)
	sheet:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, 0)
	sheet:SetWidth(1)
	sheet:SetHeight(1)

	holder = CreateFrame("Frame", "RTSBagsHeld", UIParent)
	holder:SetWidth(SLOT * 0.7)
	holder:SetHeight(SLOT * 0.7)
	holder:SetFrameStrata("TOOLTIP")
	holder:Hide()
	holder.icon = holder:CreateTexture(nil, "OVERLAY")
	holder.icon:SetAllPoints()
	if ns.Pixels and ns.Pixels.ScaleFrame then ns.Pixels:ScaleFrame(holder) end
	holder:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local s = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
	end)

	win:OnShow(function()
		B:RequestAll()
		B:Layout()
	end)
	win:OnHide(function()
		-- Lo que llevabas en la mano se suelta al cerrar. Si no, vuelve a
		-- aparecer pegado al raton la proxima vez y ya no se sabe de donde salio.
		B:Drop()
	end)

	ns.Link:On("BAGS", function(rest)
		-- DOS SENTIDOS: nosotros mandamos "BAGS <nombre>" y nos lo oimos de
		-- vuelta, porque el canal es un susurro a uno mismo. Lo que distingue la
		-- respuesta es que trae un segundo campo. Sin esta comprobacion, nuestra
		-- propia peticion entraria aqui como una respuesta vacia.
		local name, payload = rest:match("^(%S+)%s+(.+)$")
		if not name then return end

		local d = Entry(name)
		d.staging = d.staging or { conts = {}, items = {} }
		if payload == "-" then return end
		for piece in payload:gmatch("[^;]+") do
			ParsePiece(d, piece)
		end
	end)

	ns.Link:On("BAGEND", function(rest)
		local name, copper, free = rest:match("^(%S+)%s+(%d+)%s+(%d+)$")
		if not name then return end
		local d = Entry(name)
		local st = d.staging or { conts = {}, items = {} }
		d.conts, d.items = st.conts, st.items
		d.staging = nil
		d.copper, d.free = tonumber(copper), tonumber(free)
		B:Layout()
	end)

	ns.Link:On("BAGOK", function(rest)
		local from, to = rest:match("^(%S+)%s+(%S+)$")
		if not from then return end
		B:Request(from)
		B:Request(to)
	end)

	ns.Link:On("BAGERR", function(rest)
		local from, to, why = rest:match("^(%S+)%s+(%S+)%s+(.+)$")
		if not from then return end
		ns.Print("|cffff8800bolsas:|r de " .. from .. " a " .. to .. " -- " .. why)
	end)
end

function B:Toggle()
	self:Create()

	if not ns.Link:HasServer() then
		-- SIN mod-rts ESTO NO EXISTE, y decirlo es la mitad del trabajo: una
		-- ventana vacia se lee como "no tengo nada", no como "no hay servidor".
		ns.Print("|cffff8800bolsas:|r hacen falta mod-rts y el modo RTS; el cliente " ..
		         "solo puede ver TUS bolsas por su cuenta.")
	end

	local w = ns.Window:Get("RTSBags")
	if w then w:Toggle() end
end

-- Un cambio de grupo cambia el numero de columnas, asi que la ventana abierta
-- tiene que enterarse. Es el mismo motivo por el que `Bar:OnLayout` existe.
function B:RosterChanged()
	local w = ns.Window:Get("RTSBags")
	if w and w:IsOpen() then
		self:RequestAll()
		self:Layout()
	end
end
