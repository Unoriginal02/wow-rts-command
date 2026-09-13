--[[
	Art.lua -- visor de texturas del cliente. `/rts art`.

	POR QUE EXISTE. Un addon puede usar CUALQUIER textura que venga en el
	cliente con solo escribir su ruta `Interface\...`: son miles, no ocupan un
	byte en el addon y se saltan la regla de potencias de dos porque ya estan
	en formato del juego. Es lo que hace posible vestir la interfaz al estilo WC3
	sin dibujar arte -- WC3 y WoW comparten lenguaje visual (piedra gris, oro
	repujado, ranuras negras con marco dorado), asi que las piezas existen.

	El problema es saber CUALES existen de verdad en ESTE cliente. Una lista de
	rutas escrita de memoria acierta muchas y falla algunas, y una ruta que no
	carga no da error: dibuja nada. Construir la barra encima de eso es
	descubrirlo pieza a pieza, tarde y confundido con un fallo de anclaje.
	Igual que `gxWindowedResolution`, que no existe y costo una pasada entera
	por el juego. Asi que primero se miran, y luego se construye con las que
	sobrevivan.

	EL VISOR TAMBIEN ES UN EXPERIMENTO. `/rts art scan` prueba si
	`GetTexture()` sirve de oraculo: si una ruta que no carga devuelve nil,
	entonces se pueden comprobar cientos de rutas de golpe y sin mirar. Si
	devuelve la ruta igualmente, el oraculo no vale y no queda mas remedio que
	el ojo. Contestar eso cuesta un comando y cambia como se hace todo lo
	demas, asi que va primero.

	Se dibuja a ESCALA DE PIXEL, la de `Pixels.lua`, porque juzgar arte a otra
	escala es juzgar otra cosa.
]]

local ADDON, ns = ...

local A = {}
ns.Art = A

--- Los candidatos ----------------------------------------------------------
--
-- `g` grupo, `k` como se previsualiza, `p` la ruta.
--
--   tile   fondo en mosaico     -> se pinta como backdrop repetido
--   edge   marco de 9 trozos    -> se pinta como borde de una caja vacia
--   art    pieza suelta u hoja  -> se pinta estirada, para ver que lleva
--
-- Escritas de memoria a proposito y SIN filtrar: el visor esta justamente
-- para separar las que existen de las que me he inventado. Una ruta que no
-- carga aqui no es un fallo del visor, es el resultado.

local CANDIDATES = {
	-- Piedra y fondos: el muro de la barra inferior de WC3.
	{ g = "piedra", k = "tile", p = "Interface\\FrameGeneral\\UI-Background-Marble" },
	{ g = "piedra", k = "tile", p = "Interface\\FrameGeneral\\UI-Background-Rock" },
	{ g = "piedra", k = "tile", p = "Interface\\DialogFrame\\UI-DialogBox-Background" },
	{ g = "piedra", k = "tile", p = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
	{ g = "piedra", k = "tile", p = "Interface\\Tooltips\\UI-Tooltip-Background" },
	{ g = "piedra", k = "tile", p = "Interface\\ChatFrame\\ChatFrameBackground" },
	{ g = "piedra", k = "tile", p = "Interface\\AchievementFrame\\UI-Achievement-Parchment" },
	{ g = "piedra", k = "tile", p = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground" },
	{ g = "piedra", k = "tile", p = "Interface\\QuestFrame\\QuestBG" },
	{ g = "piedra", k = "tile", p = "Interface\\Stationery\\StationeryTest1" },

	-- Marcos de nueve trozos: el reborde dorado.
	{ g = "borde", k = "edge", p = "Interface\\DialogFrame\\UI-DialogBox-Border" },
	{ g = "borde", k = "edge", p = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border" },
	{ g = "borde", k = "edge", p = "Interface\\Tooltips\\UI-Tooltip-Border" },
	{ g = "borde", k = "edge", p = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder" },
	{ g = "borde", k = "edge", p = "Interface\\Common\\Common-Input-Border" },
	{ g = "borde", k = "edge", p = "Interface\\Tooltips\\ChatBubble-Backdrop" },
	{ g = "borde", k = "edge", p = "Interface\\Buttons\\WHITE8X8" },

	-- Aros de retrato: el marco del heroe de WC3.
	{ g = "retrato", k = "art", p = "Interface\\TargetingFrame\\UI-TargetingFrame" },
	{ g = "retrato", k = "art", p = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite" },
	{ g = "retrato", k = "art", p = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite" },
	{ g = "retrato", k = "art", p = "Interface\\TargetingFrame\\UI-PartyFrame" },
	{ g = "retrato", k = "art", p = "Interface\\CharacterFrame\\TempPortraitAlphaMask" },
	{ g = "retrato", k = "art", p = "Interface\\AchievementFrame\\UI-Achievement-IconFrame" },
	{ g = "retrato", k = "art", p = "Interface\\Minimap\\UI-Minimap-Border" },
	{ g = "retrato", k = "art", p = "Interface\\Minimap\\MiniMap-TrackingBorder" },
	{ g = "retrato", k = "art", p = "Interface\\Minimap\\UI-Minimap-Background" },

	-- Ranuras: la carta de comandos.
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\UI-Quickslot2" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\UI-Quickslot" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\UI-Quickslot-Depress" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\UI-EmptySlot-White" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\UI-Slot-Background" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\ButtonHilight-Square" },
	{ g = "ranura", k = "art", p = "Interface\\Buttons\\CheckButtonHilight" },
	{ g = "ranura", k = "art", p = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
	{ g = "ranura", k = "art", p = "Interface\\Icons\\INV_Misc_QuestionMark" },

	-- Barras: vida y mana del retrato.
	{ g = "barra", k = "art", p = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ g = "barra", k = "art", p = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	{ g = "barra", k = "art", p = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ g = "barra", k = "art", p = "Interface\\CastingBar\\UI-CastingBar-Fill-Standard" },
	{ g = "barra", k = "art", p = "Interface\\CastingBar\\UI-CastingBar-Border" },

	-- Piezas sueltas: cabecera, separadores, botones de la fila de arriba.
	{ g = "pieza", k = "art", p = "Interface\\Buttons\\UI-Panel-Button-Up" },
	{ g = "pieza", k = "art", p = "Interface\\LFGFrame\\UI-LFG-SEPARATOR" },
	{ g = "pieza", k = "art", p = "Interface\\WorldStateFrame\\WorldState-CaptureBar" },
	{ g = "pieza", k = "art", p = "Interface\\PVPFrame\\UI-Character-PVP-Highlight" },
	{ g = "pieza", k = "art", p = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Human" },
	{ g = "pieza", k = "art", p = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf" },
	{ g = "pieza", k = "art", p = "Interface\\MainMenuBar\\UI-MainMenuBar-Border" },
	{ g = "pieza", k = "art", p = "Interface\\PetitionFrame\\Petition-Bottom" },
}

local COLS, ROWS = 4, 3
local PER = COLS * ROWS
local CELL_W, CELL_H, CELL_GAP = 210, 150, 12
local PREVIEW_H = 104

local panel, cells, pageLabel, probeTex
local page = 1
local filter = nil

--- El oraculo --------------------------------------------------------------
-- Se pregunta a una textura escondida si acepto la ruta. Si un fichero que no
-- existe deja GetTexture() en nil, se pueden comprobar cientos de golpe; si
-- devuelve la ruta igualmente, no vale y solo queda el ojo. Es lo primero que
-- contesta `/rts art scan`, porque cambia el metodo de todo lo que viene.

local function Probe(path)
	if not probeTex then
		local f = CreateFrame("Frame")
		f:Hide()
		probeTex = f:CreateTexture(nil, "ARTWORK")
	end
	probeTex:SetTexture(nil)
	probeTex:SetTexture(path)
	return probeTex:GetTexture()
end

--- La lista visible --------------------------------------------------------

local function List()
	if not filter then return CANDIDATES end
	local out = {}
	for _, c in ipairs(CANDIDATES) do
		if c.g == filter or c.p:lower():find(filter, 1, true) then
			table.insert(out, c)
		end
	end
	return out
end

local function Pages()
	local n = #List()
	return math.max(1, math.ceil(n / PER))
end

--- Pintar ------------------------------------------------------------------

local function Paint()
	local list = List()
	local pages = Pages()
	if page > pages then page = pages end
	if page < 1 then page = 1 end

	for i = 1, PER do
		local cell = cells[i]
		local c = list[(page - 1) * PER + i]

		-- Cada celda sabe pintar las tres formas, asi que se limpian las dos
		-- que no toquen en vez de crear y destruir frames por pagina.
		cell.box:SetBackdrop(nil)
		cell.tex:SetTexture(nil)
		cell.tex:Hide()

		if not c then
			cell:Hide()
		else
			cell:Show()
			cell.path = c.p
			local short = c.p:match("([^\\]+)$") or c.p
			local dir = c.p:match("Interface\\(.-)\\[^\\]+$") or "?"

			if c.k == "tile" then
				cell.box:SetBackdrop({ bgFile = c.p, tile = true, tileSize = 64 })
			elseif c.k == "edge" then
				cell.box:SetBackdrop({
					bgFile = "Interface\\Buttons\\WHITE8X8",
					edgeFile = c.p, tile = false, edgeSize = 16,
					insets = { left = 5, right = 5, top = 5, bottom = 5 },
				})
				cell.box:SetBackdropColor(0.05, 0.05, 0.06, 1)
			else
				cell.tex:SetTexture(c.p)
				cell.tex:Show()
			end

			local got = Probe(c.p)
			cell.name:SetText(short)
			cell.where:SetText(("|cff888888%s|r  %s"):format(dir,
				got and "" or "|cffff4040nil|r"))
		end
	end

	pageLabel:SetText(("%d / %d   %s"):format(page, pages,
		filter and ("filtro: |cffffff00" .. filter .. "|r") or "todo"))
end

--- Construir ---------------------------------------------------------------

local function Build()
	if panel then return end

	local W = COLS * CELL_W + (COLS + 1) * CELL_GAP
	local H = ROWS * CELL_H + (ROWS + 1) * CELL_GAP + 62

	panel = CreateFrame("Frame", "RTSArt", UIParent)
	panel:SetWidth(W)
	panel:SetHeight(H)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.92)
	panel:SetBackdropBorderColor(0.72, 0.60, 0.34, 1)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()

	-- La misma escala de pixel que el resto: juzgar arte a otra escala es juzgar
	-- otra cosa.
	ns.Pixels:ScaleFrame(panel)

	local font = GameFontNormal:GetFont()

	local title = panel:CreateFontString(nil, "OVERLAY")
	title:SetFont(font, 15, "OUTLINE")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)
	title:SetTextColor(0.95, 0.85, 0.55)
	title:SetText("TEXTURAS DEL CLIENTE  -  click en una copia su ruta al chat")

	pageLabel = panel:CreateFontString(nil, "OVERLAY")
	pageLabel:SetFont(font, 13, "OUTLINE")
	pageLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -46, -14)
	pageLabel:SetTextColor(0.6, 0.9, 1)

	local hint = panel:CreateFontString(nil, "OVERLAY")
	hint:SetFont(font, 12, "OUTLINE")
	hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 12)
	hint:SetTextColor(0.7, 0.7, 0.75)
	hint:SetText("rueda del raton o /rts art next / prev  ·  /rts art <grupo>  ·  " ..
		"grupos: piedra borde retrato ranura barra pieza")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() panel:Hide() end)

	panel:EnableMouseWheel(true)
	panel:SetScript("OnMouseWheel", function(_, delta)
		page = page - delta
		Paint()
	end)

	cells = {}
	for i = 1, PER do
		local r = math.floor((i - 1) / COLS)
		local c = (i - 1) % COLS

		local cell = CreateFrame("Button", nil, panel)
		cell:SetWidth(CELL_W)
		cell:SetHeight(CELL_H)
		cell:SetPoint("TOPLEFT", panel, "TOPLEFT",
			CELL_GAP + c * (CELL_W + CELL_GAP),
			-(40 + r * (CELL_H + CELL_GAP)))

		local box = CreateFrame("Frame", nil, cell)
		box:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
		box:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 0, 0)
		box:SetHeight(PREVIEW_H)
		cell.box = box

		-- Tablero de ajedrez detras: sin el, una pieza con alfa se confunde
		-- con una que no ha cargado, que es exactamente lo que hay que
		-- distinguir aqui.
		local checker = box:CreateTexture(nil, "BACKGROUND")
		checker:SetAllPoints(box)
		checker:SetTexture(0.16, 0.16, 0.18, 1)

		cell.tex = box:CreateTexture(nil, "ARTWORK")
		cell.tex:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
		cell.tex:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)

		cell.name = cell:CreateFontString(nil, "OVERLAY")
		cell.name:SetFont(font, 12, "OUTLINE")
		cell.name:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -4)
		cell.name:SetWidth(CELL_W - 4)
		cell.name:SetJustifyH("LEFT")
		cell.name:SetTextColor(1, 1, 1)

		cell.where = cell:CreateFontString(nil, "OVERLAY")
		cell.where:SetFont(font, 11, "OUTLINE")
		cell.where:SetPoint("TOPLEFT", cell.name, "BOTTOMLEFT", 0, -2)
		cell.where:SetWidth(CELL_W - 4)
		cell.where:SetJustifyH("LEFT")

		cell:SetScript("OnClick", function(self)
			if self.path then ns.Print(self.path) end
		end)

		cells[i] = cell
	end
end

--- Comandos ----------------------------------------------------------------

function A:Toggle()
	Build()
	if panel:IsShown() then
		panel:Hide()
	else
		ns.Pixels:ScaleFrame(panel)
		Paint()
		panel:Show()
	end
end

function A:Page(delta)
	Build()
	page = page + delta
	Paint()
	if not panel:IsShown() then panel:Show() end
end

function A:Filter(text)
	Build()
	filter = (text ~= "" and text:lower()) or nil
	page = 1
	Paint()
	if not panel:IsShown() then panel:Show() end
	ns.Print(("%d texturas%s"):format(#List(),
		filter and (" con |cffffff00" .. filter .. "|r") or ""))
end

-- El experimento. Cuenta cuantas rutas devuelven nil y ensena las que fallan,
-- compacto porque con el chat escondido solo hay nueve lineas.
function A:Scan()
	local bad = {}
	for _, c in ipairs(CANDIDATES) do
		if not Probe(c.p) then
			table.insert(bad, c.p:match("([^\\]+)$") or c.p)
		end
	end

	ns.Print(("%d rutas probadas, |cffff4040%d|r devuelven nil"):format(#CANDIDATES, #bad))
	if #bad == 0 then
		ns.Print("Ninguna devuelve nil. |cffffff00Dos lecturas posibles|r: o todas")
		ns.Print("existen, o GetTexture() no sirve de oraculo en 3.3.5a. Lo dice")
		ns.Print("el visor: si en |cffffff00/rts art|r hay recuadros vacios, no sirve.")
	else
		local line = "  "
		for _, n in ipairs(bad) do
			if line:len() + n:len() > 66 then ns.Print(line) line = "  " end
			line = line .. n .. "  "
		end
		if line ~= "  " then ns.Print(line) end
		ns.Print("|cff00ff00El oraculo funciona|r: se pueden comprobar rutas a ciegas.")
	end
end
