--[[
	Npc.lua -- el entrenador y el vendedor, siendo el bot.

	Es lo del video (*"I'm actually interacting AS THE BOT and getting that full
	kind of experience"*), y resulto no necesitar ningun truco: `Trainer.h` del
	nucleo expone la lista, el estado por hechizo y el "ensename esto" tomando un
	`Player*` cualquiera. El servidor calcula para el bot, nosotros dibujamos.

	Lo unico que sigue sin poderse es abrir LA VENTANA DE BLIZZARD con datos del
	bot -- y deja de importar en cuanto dibujas la tuya. El porque entero esta en
	`RtsNpc.h`.

	=== TRES BOTONES QUE EL VIDEO NO TIENE =================================

	*Aprender todo lo que pueda*, *vender la basura gris* y *reparar*. En el
	video se hace hechizo a hechizo, que es fiel a la ventana original y es
	exactamente el trabajo que un grupo de cuatro multiplica por cuatro. La
	ventana sigue estando -- se puede aprender uno suelto -- pero el caso normal
	es un boton.

	=== COMPRAR Y ENTRENAR SI EXIGEN ESTAR DELANTE =========================

	Al reves que las misiones, y a proposito. El bot camina hasta el NPC de todas
	formas (el click derecho sobre un PNJ ya hace eso desde la etapa 5h), asi que
	saltarse la comprobacion no compraria nada. Cuando esta lejos, el servidor lo
	DICE en vez de no hacer nada: un boton que calla es indistinguible de un
	boton roto.
]]

local ADDON, ns = ...

local N = {}
ns.Npc = N

--- Medidas, en unidades de DIBUJO ------------------------------------------

local ROW   = 52
local ICON  = 40
local PAD   = 10
local BTN_W = 260
local BTN_H = 46
local W     = 1000

--- Estado ------------------------------------------------------------------

local win, sheet, tabs, actions
local mode = "trainer"          -- "trainer" | "vendor"
local target = { guid = nil, name = nil, bot = nil }
local data = { trainer = {}, vendor = {}, copper = 0, staging = nil }
local rows = {}

local ST_AVAILABLE, ST_UNAVAILABLE, ST_KNOWN = 0, 1, 2

local function Money(copper)
	copper = tonumber(copper) or 0
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if g > 0 then return string.format("|cffffd700%d|ro |cffc7c7cf%d|rp %dc", g, s, c) end
	if s > 0 then return string.format("|cffc7c7cf%d|rp %dc", s, c) end
	return string.format("%dc", c)
end

local function HexOf(guid)
	return (tostring(guid or ""):gsub("^0[xX]", ""))
end

--- Pedir -------------------------------------------------------------------

function N:Ask()
	if not target.guid or not target.bot then return end
	data.staging = {}
	ns.SendServer((mode == "trainer" and "TRAINER " or "VENDOR ") ..
	              target.bot .. " " .. HexOf(target.guid))
end

--- Dibujo ------------------------------------------------------------------

local function NewRow(i)
	local r = rows[i]
	if r then return r end

	r = CreateFrame("Button", "RTSNpcRow" .. i, sheet)
	r:SetHeight(ROW)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetWidth(ICON)
	r.icon:SetHeight(ICON)
	r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	r.label = ns.W:Text(r, ns.W.FONT.small)
	r.label:SetPoint("LEFT", r, "LEFT", ICON + 10, 6)

	r.sub = ns.W:Text(r, ns.W.FONT.tiny)
	r.sub:SetPoint("LEFT", r, "LEFT", ICON + 10, -12)

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(1, 1, 1, 0.12)

	rows[i] = r
	return r
end

local function PaintTrainer(r, e)
	local name, _, icon = GetSpellInfo(e.spellId)
	r.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	r.label:SetText(name or ("hechizo " .. e.spellId))

	if e.state == ST_KNOWN then
		r.label:SetTextColor(0.45, 0.45, 0.45)
		r.sub:SetText("|cff556655ya lo sabe|r")
		r:SetScript("OnClick", nil)
		r:SetAlpha(0.6)
	elseif e.state == ST_AVAILABLE then
		r.label:SetTextColor(1, 1, 1)
		r.sub:SetText(Money(e.cost))
		r:SetAlpha(1)
		r.spellId = e.spellId
		r:SetScript("OnClick", function(self)
			ns.SendServer(("TRAIN %s %s %d"):format(target.bot, HexOf(target.guid), self.spellId))
		end)
	else
		r.label:SetTextColor(1, 0.35, 0.35)
		r.sub:SetText(("|cffff5555nivel %d|r  %s"):format(e.reqLevel or 0, Money(e.cost)))
		r:SetScript("OnClick", nil)
		r:SetAlpha(0.75)
	end
end

local function PaintVendor(r, e)
	local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(e.itemId)
	r.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	r.label:SetText(name or ("objeto " .. e.itemId))
	r:SetAlpha(1)

	-- Misma trampa que en las bolsas: sin cache, `GetItemInfo` devuelve nil y no
	-- da error. Se pide con un tooltip invisible y se redibuja luego.
	if not name and ns.Bags then
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetHyperlink("item:" .. e.itemId)
		GameTooltip:Hide()
	end

	local left = (e.left and e.left >= 0) and ("  |cff88ff88x" .. e.left .. "|r") or ""
	if e.extendedCost and e.extendedCost > 0 then
		-- Los objetos de coste extendido (insignias, marcas) NO se pueden
		-- comprar desde aqui: su precio no es oro y replicar esa cuenta seria
		-- inventarse la mitad de un sistema. Se ensenan apagados en vez de
		-- esconderse, para que no parezca que el vendedor tiene menos cosas.
		r.sub:SetText("|cffff8800precio especial (no desde aqui)|r" .. left)
		r:SetScript("OnClick", nil)
		r:SetAlpha(0.55)
		return
	end

	r.sub:SetText(Money(e.price) .. left)
	r.slot = e.slot
	r:SetScript("OnClick", function(self)
		local n = IsShiftKeyDown() and 5 or 1
		ns.SendServer(("BUY %s %s %d %d"):format(target.bot, HexOf(target.guid), self.slot, n))
		-- Comprar cambia el dinero y puede agotar el hueco: se vuelve a pedir.
		N:Ask()
	end)
end

function N:Layout()
	if not win or not win:IsOpen() then return end

	win:SetTitle(("%s  --  %s"):format(target.name or "?", target.bot or "?"))

	local list = data[mode] or {}
	local y = 0
	for i, e in ipairs(list) do
		local r = NewRow(i)
		r:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -y)
		r:SetWidth(W - PAD * 2)
		r:Show()
		if mode == "trainer" then PaintTrainer(r, e) else PaintVendor(r, e) end
		y = y + ROW
	end
	for i = #list + 1, #rows do rows[i]:Hide() end

	if #list == 0 then
		actions.empty:SetText(mode == "trainer"
			and "|cff888888No entrena a los de su clase, o ya lo sabe todo.|r"
			or  "|cff888888No vende nada.|r")
	else
		actions.empty:SetText("")
	end

	actions.money:SetText("Lleva " .. Money(data.copper))

	local h = 46 + PAD + BTN_H + PAD + math.max(ROW, y) + PAD
	local maxH = (ns.HUD and ns.HUD.pixels or 1440) * 0.72
	if h > maxH then h = maxH end
	win:SetSize(W, h)
	sheet:SetWidth(W - PAD * 2)
	sheet:SetHeight(math.max(ROW, y))
end

--- Los botones -------------------------------------------------------------

local function MakeButton(parent, label, tip, fn)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(BTN_W)
	b:SetHeight(BTN_H)
	if ns.Skin then ns.Skin:Dress(b, true) end
	b.label = ns.W:Text(b, ns.W.FONT.small)
	b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label:SetText(label)
	b:SetScript("OnClick", fn)
	ns.W:Tip(b, label, tip)
	return b
end

--- Ciclo -------------------------------------------------------------------

function N:Create()
	if win then return end

	win = ns.Window:New("RTSNpc", "Personaje", W, 600)

	local body = win:Body()

	actions = CreateFrame("Frame", "RTSNpcActions", body)
	actions:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, 0)
	actions:SetWidth(W - PAD * 2)
	actions:SetHeight(BTN_H)

	tabs = {}
	tabs.trainer = MakeButton(actions, "Entrenador", "Lo que puede aprender de el.", function()
		mode = "trainer" ; N:Ask() ; N:Layout()
	end)
	tabs.trainer:SetPoint("LEFT", actions, "LEFT", 0, 0)

	tabs.vendor = MakeButton(actions, "Vendedor", "Lo que vende.", function()
		mode = "vendor" ; N:Ask() ; N:Layout()
	end)
	tabs.vendor:SetPoint("LEFT", tabs.trainer, "RIGHT", 8, 0)

	tabs.all = MakeButton(actions, "Aprender todo lo que pueda",
		"De mas barato a mas caro, hasta que se quede sin oro.", function()
		ns.SendServer(("TRAIN %s %s 0"):format(target.bot, HexOf(target.guid)))
	end)
	tabs.all:SetPoint("LEFT", tabs.vendor, "RIGHT", 24, 0)

	tabs.junk = MakeButton(actions, "Vender la basura gris",
		"Todo lo gris con precio de venta. Las bolsas con cosas dentro se quedan.", function()
		ns.SendServer(("SELLJUNK %s %s"):format(target.bot, HexOf(target.guid)))
	end)
	tabs.junk:SetPoint("LEFT", tabs.all, "RIGHT", 8, 0)

	tabs.repair = MakeButton(actions, "Reparar", "Todo el equipo, con su descuento.", function()
		ns.SendServer(("REPAIR %s %s"):format(target.bot, HexOf(target.guid)))
	end)
	tabs.repair:SetPoint("LEFT", tabs.junk, "RIGHT", 8, 0)

	actions.money = ns.W:Text(actions, ns.W.FONT.small)
	actions.money:SetPoint("RIGHT", actions, "RIGHT", 0, 0)

	sheet = CreateFrame("Frame", "RTSNpcSheet", body)
	sheet:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -PAD)
	sheet:SetWidth(1)
	sheet:SetHeight(1)

	actions.empty = ns.W:Text(sheet, ns.W.FONT.small)
	actions.empty:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -8)

	body:EnableMouseWheel(true)
	body:SetScript("OnMouseWheel", function(_, delta)
		N.scroll = math.max(0, (N.scroll or 0) - delta * ROW)
		sheet:ClearAllPoints()
		sheet:SetPoint("TOPLEFT", actions, "BOTTOMLEFT", 0, -PAD + N.scroll)
	end)

	local function Chunks(kind)
		return function(rest)
			-- DOS SENTIDOS: mandamos "TRAINER <bot> <guid>" (dos campos detras
			-- del verbo) y la respuesta es "TRAINER <bot> <trozo>". Se distingue
			-- por el contenido del segundo campo: el nuestro es un guid en hex,
			-- el suyo lleva comas. Sin este filtro, nuestra propia peticion
			-- entraria como una fila basura.
			local bot, payload = rest:match("^(%S+)%s+(%S.*)$")
			if not bot or not payload:find(",") then return end
			data.staging = data.staging or {}
			for piece in payload:gmatch("[^;]+") do
				table.insert(data.staging, piece)
			end
		end
	end

	ns.Link:On("TRAINER", Chunks("trainer"))
	ns.Link:On("VENDOR", Chunks("vendor"))

	ns.Link:On("TRAINEND", function(rest)
		local bot, copper = rest:match("^(%S+)%s+(%d+)$")
		if not bot then return end
		local out = {}
		for _, p in ipairs(data.staging or {}) do
			local id, cost, state, lvl = p:match("^(%d+),(%d+),(%d+),(%d+)$")
			if id then
				table.insert(out, { spellId = tonumber(id), cost = tonumber(cost),
				                    state = tonumber(state), reqLevel = tonumber(lvl) })
			end
		end
		data.trainer, data.staging, data.copper = out, nil, tonumber(copper)
		N:Layout()
	end)

	ns.Link:On("VENDEND", function(rest)
		local bot, copper = rest:match("^(%S+)%s+(%d+)$")
		if not bot then return end
		local out = {}
		for _, p in ipairs(data.staging or {}) do
			local slot, id, price, left, ext = p:match("^(%d+),(%d+),(%d+),(-?%d+),(%d+)$")
			if slot then
				table.insert(out, { slot = tonumber(slot), itemId = tonumber(id),
				                    price = tonumber(price), left = tonumber(left),
				                    extendedCost = tonumber(ext) })
			end
		end
		data.vendor, data.staging, data.copper = out, nil, tonumber(copper)
		N:Layout()
	end)

	ns.Link:On("TRAINED", function(rest)
		local bot, n, spent = rest:match("^(%S+)%s+(%d+)%s+(%d+)$")
		if not bot then return end
		ns.Print(("|cff33ccff%s|r aprendio %s hechizo(s) por %s"):format(bot, n, Money(spent)))
		N:Ask()
	end)

	ns.Link:On("SOLD", function(rest)
		local bot, n, earned = rest:match("^(%S+)%s+(%d+)%s+(%d+)$")
		if not bot then return end
		ns.Print(("|cff33ccff%s|r vendio %s objeto(s) por %s"):format(bot, n, Money(earned)))
		N:Ask()
	end)

	ns.Link:On("REPAIRED", function(rest)
		local bot, cost = rest:match("^(%S+)%s+(%d+)$")
		if not bot then return end
		ns.Print(("|cff33ccff%s|r reparo por %s"):format(bot, Money(cost)))
		N:Ask()
	end)

	ns.Link:On("BOUGHT", function(rest)
		local bot = rest:match("^(%S+)$")
		if bot then ns.Print(("|cff33ccff%s|r lo compro."):format(bot)) end
	end)

	ns.Link:On("NPCERR", function(rest)
		ns.Print("|cffff8800personaje:|r " .. rest)
	end)
end

-- Abrir contra un NPC, actuando como el primario.
function N:Open(guid, name)
	self:Create()

	if not guid then
		ns.Print("personaje: apunta a un entrenador o a un vendedor primero.")
		return
	end

	target.guid, target.name = guid, name
	target.bot = ns.Selection:GetPrimary()
	data.trainer, data.vendor, data.staging = {}, {}, nil

	win:Open()
	self:Ask()
	self:Layout()
end

function N:Toggle(guid, name)
	self:Create()
	if win:IsOpen() then win:Close() else self:Open(guid, name) end
end
