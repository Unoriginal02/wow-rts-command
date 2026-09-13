--[[
	Skin.lua -- el aspecto de las ventanas propias, en un solo sitio.

	Las texturas salen del propio cliente (ver `/rts art`), asi que vestir la
	interfaz al estilo WC3 no cuesta un solo fichero de arte. Lo que si cuesta es
	tenerlas repartidas por el codigo: el dia que una no guste hay que buscarla
	en cuatro ficheros. Aqui hay UNA tabla de rutas y UNA funcion que las
	aplica, y los frames vestidos se apuntan en una lista para poder
	revestirlos en caliente.

	POR QUE SE PUEDE CAMBIAR EN VIVO. `/rts skin` alterna entre el aspecto
	plano y el de WC3, y `/rts skin wall <ruta>` acepta cualquier ruta -- que
	es justo lo que `/rts art` escribe al hacer click en una casilla. Los dos
	comandos estan pensados para usarse juntos: se mira, se copia, se prueba,
	sin recargar y sin compilar nada.

	LO QUE NO LLEVA, Y POR QUE. Nada de TexCoord. Las hojas grandes del cliente
	(los marcos de objetivo, la barra principal) traen varias piezas en una
	imagen y hay que recortarlas con coordenadas, y acertar esas coordenadas a
	ciegas es adivinar. Todo lo que se usa aqui se dibuja ENTERO: un marco de
	nueve trozos y una ranura cuadrada no necesitan recorte. El recorte llega
	cuando haya con que mirarlo, no antes -- misma regla que el arte propio.
]]

local ADDON, ns = ...

local S = {}
ns.Skin = S

S.on = true

-- Elegidas mirandolas en `/rts art`, no de memoria.
--
--   wall  fondo del panel. En mosaico, asi que vale a cualquier anchura.
--   edge  marco de nueve trozos. El reborde dorado sobre piedra de siempre;
--         es la pieza que mas parecido da con WC3 y no necesita recorte.
--   slot  ranura de boton, cuadrada y con hueco oscuro dentro.
--   ring  aro de retrato. GUARDADO PARA CUANDO HAYA RETRATOS: es una hoja con
--         varias piezas, asi que llegado el dia necesita TexCoord.
S.DEFAULTS = {
	wall = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edge = "Interface\\DialogFrame\\UI-DialogBox-Border",
	slot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag",
	ring = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
}

S.tex = {}
for k, v in pairs(S.DEFAULTS) do S.tex[k] = v end

-- El marco dorado de WoW quiere 32 de borde y 11-12 de margen interior. Es su
-- medida, no una elegida: con menos, las esquinas se solapan y se ve un
-- churro. El aspecto plano usa el marco fino, que quiere 16 y 5.
local WC3_EDGE, WC3_INSET = 32, 12
local FLAT_EDGE, FLAT_INSET = 16, 5

local FLAT = {
	bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = FLAT_EDGE,
	insets = { left = FLAT_INSET, right = FLAT_INSET, top = FLAT_INSET, bottom = FLAT_INSET },
}

local panels, cells = {}, {}

--- Aplicar -----------------------------------------------------------------

-- Cuanto hay que meterse hacia dentro para no pisar el marco. Con el marco
-- gordo de WC3 el hueco util es mas pequeno, y quien dibuje dentro de un panel
-- tiene que saberlo o se le sale por debajo del borde.
function S:Inset()
	return self.on and (WC3_INSET + 2) or (FLAT_INSET + 3)
end

function S:Backdrop()
	if not self.on then return FLAT end
	return {
		bgFile   = self.tex.wall,
		edgeFile = self.tex.edge,
		tile = true, tileSize = 32, edgeSize = WC3_EDGE,
		insets = { left = WC3_INSET, right = WC3_INSET, top = WC3_INSET, bottom = WC3_INSET },
	}
end

function S:Dress(frame, dim)
	if not frame.rtsSkinned then
		table.insert(panels, frame)
		frame.rtsSkinned = true
	end
	frame.rtsDim = dim
	frame:SetBackdrop(self:Backdrop())
	if self.on then
		-- La piedra ya trae su color; oscurecerla la mata. Solo se baja el
		-- brillo de los paneles interiores para que se lean como huecos.
		frame:SetBackdropColor(1, 1, 1, dim and 0.55 or 1)
		frame:SetBackdropBorderColor(1, 1, 1, 1)
	else
		frame:SetBackdropColor(0, 0, 0, dim and 0.45 or 0.78)
		frame:SetBackdropBorderColor(0.72, 0.60, 0.34, 1)
	end
end

-- Una celda de la carta de comandos. En plano son dos rectangulos de color; en
-- WC3, la ranura del cliente estirada a la celda. Las dos capas existen
-- siempre y se enciende la que toque, para que cambiar de aspecto no tenga que
-- crear ni destruir nada.
function S:Slot(cell)
	if not cell.rtsSkinned then
		table.insert(cells, cell)
		cell.rtsSkinned = true
	end
	if self.on then
		cell.flatEdge:Hide()
		cell.flatFill:Hide()
		cell.slot:SetTexture(self.tex.slot)
		cell.slot:Show()
	else
		cell.slot:Hide()
		cell.flatEdge:Show()
		cell.flatFill:Show()
	end
end

--- Revestir en caliente ----------------------------------------------------

function S:Refresh()
	for _, f in ipairs(panels) do self:Dress(f, f.rtsDim) end
	for _, c in ipairs(cells) do self:Slot(c) end
	if ns.Dock and ns.Dock.active then ns.Dock:Layout() end
end

function S:Toggle()
	self.on = not self.on
	RTSCommandDB.skinOn = self.on
	self:Refresh()
	ns.Print("aspecto: " ..
		(self.on and "|cffffd100WC3|r (texturas del cliente)" or "|cffaaaaaaplano|r"))
end

function S:Set(key, path)
	if self.tex[key] == nil then return false end
	if not path or path == "" then return false end
	self.tex[key] = path
	RTSCommandDB.skin = RTSCommandDB.skin or {}
	RTSCommandDB.skin[key] = path
	self:Refresh()
	ns.Print(("%s = %s"):format(key, path))
	return true
end

function S:Reset()
	for k, v in pairs(self.DEFAULTS) do self.tex[k] = v end
	RTSCommandDB.skin = nil
	self:Refresh()
	ns.Print("texturas devueltas a las elegidas por defecto.")
end

function S:Status()
	ns.Print(("aspecto: %s"):format(self.on and "|cffffd100WC3|r" or "|cffaaaaaaplano|r"))
	for _, k in ipairs({ "wall", "edge", "slot", "ring" }) do
		ns.Print(("  |cffffff00%-5s|r %s"):format(k, self.tex[k]))
	end
	ns.Print("|cffffff00/rts skin wall / edge / slot / ring <ruta>|r - " ..
		"copia la ruta con click en |cffffff00/rts art|r")
end

function S:Load()
	if type(RTSCommandDB.skinOn) == "boolean" then self.on = RTSCommandDB.skinOn end
	if type(RTSCommandDB.skin) == "table" then
		for k, v in pairs(RTSCommandDB.skin) do
			if self.tex[k] ~= nil and type(v) == "string" then self.tex[k] = v end
		end
	end
end
