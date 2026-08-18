--[[
	HUD.lua -- el contenedor de la HUD de RTS, a escala de pixel.

	Es el paso 1 del apartado 7 del estudio, con dos cosas dentro para poder
	juzgarlo con los ojos en vez de sobre el papel:

	  - el MINIMAPA de verdad, reparentado abajo a la izquierda con margen
	  - la HUELLA de la barra de control a su derecha, con las medidas escritas
	    encima, para decidir la altura antes de dibujar un solo pixel de arte

	Tres decisiones que vienen del estudio y conviene no perder:

	1. ESCALA DE PIXEL. WoW no dibuja en pixeles, dibuja en unidades: la
	   pantalla mide 768 unidades de alto a escala 1. Con 1440 px y uiScale
	   0.86, una unidad son 1.61 pixeles fisicos -- o sea que una textura de 512
	   se estira a 826 e interpola. Este contenedor lleva su propia escala,
	   768/altoFisico, de modo que dentro de el 1 unidad = 1 pixel y el arte
	   sale nitido. El resto del juego conserva su uiScale intacto; no se toca.

	2. LA LINEA DE MENSAJES NO ES UN ADORNO. El chat entra en la lista de
	   Chrome.lua, y con el se va ns.Print, que es el unico canal de diagnostico
	   que tiene este addon. Asi que la HUD replica cada ns.Print sobre el
	   mundo, arriba a la izquierda, estilo WC3, y se desvanece sola. Sin esto,
	   esconder el chat seria quedarse ciego.

	3. CUELGA DE UIParent, DE MOMENTO. Con la opcion B, UIParent sigue visible,
	   asi que no hace falta colgar de WorldFrame -- y colgar de UIParent evita
	   pelearse con el orden de dibujo del resto de paneles del addon. El dia
	   que se pase a la opcion A hay que cambiar PARENT aqui y nada mas: la
	   escala ya se calcula contra la del padre, sea cual sea.
]]

local ADDON, ns = ...

local H = {}
ns.HUD = H

H.active = false

-- El padre de la HUD. Un unico sitio que cambiar si algun dia se esconde
-- UIParent entero (opcion A): ahi pasaria a ser WorldFrame.
local PARENT = UIParent

-- Medidas en PIXELES FISICOS, que es en lo que piensa uno mirando la pantalla.
-- Dentro del contenedor 1 unidad = 1 pixel, asi que se usan tal cual.
local D = {
	pad    = 22,    -- margen contra los bordes de la pantalla
	mini   = 210,   -- lado del panel del minimapa
	gap    = 14,    -- separacion entre paneles
	height = 210,   -- alto de la barra de control (la pregunta a contestar)
	right  = 300,   -- ancho del bloque de acciones de bots, a la derecha
}

H.cfg = {}
for k, v in pairs(D) do H.cfg[k] = v end

-- Reparto vertical de la barra de control, en pixeles: titulo arriba, nota
-- abajo, y separacion entre botones. Estan aqui arriba porque el alto por
-- defecto se DERIVA de ellos y del tamano del boton, en vez de elegirse a ojo.
local TOP, BOTTOM, CELLGAP = 30, 24, 5
local ROWS = 3

local hud, msgFrame, miniPanel, zoneText, strip
local msgLines = {}
local MSG_LINES, MSG_LIFE, MSG_FADE = 9, 14, 3

local FONT = GameFontNormal:GetFont()

--- Escala ------------------------------------------------------------------

-- 3.3.5a no tiene GetPhysicalScreenSize, asi que la resolucion sale del CVar
-- `gxResolution` -- y SOLO de ese.
--
-- LA PRIMERA VERSION LEIA `gxWindowedResolution` EN MODO VENTANA Y ESE CVAR NO
-- EXISTE EN ESTE CLIENTE. Comprobado en el Config.wtf de la maquina: hay
-- gxResolution, gxWindow y gxMaximize, y ninguno mas. GetCVar devolvia nil, el
-- patron no casaba, la escala se quedaba en 1 y la HUD salia un 45% mas grande
-- de lo pedido -- que es exactamente el fallo que decia el comentario que
-- estaba evitando. Misma leccion que `nameplateMaxDistance`: comprobar contra
-- el cliente, no contra lo que dice internet.
--
-- La segunda mitad es la correccion por relacion de aspecto, y hace falta
-- porque gxResolution guarda la resolucion de PANTALLA COMPLETA. En ventana
-- maximizada la ventana es igual de ancha pero mas baja (la barra de tareas), y
-- el escritorio puede ni siquiera tener la misma forma. La relacion de aspecto
-- de UIParent SI es la de la ventana real -- su alto en unidades es fijo y su
-- ancho cambia con la forma -- asi que el alto verdadero sale del ancho.
-- Se asume que la ventana ocupa todo el ancho, que es lo que hace maximizada;
-- si algun dia se juega en ventana pequena, el informe de /rts ui ensena los
-- dos numeros y se ve enseguida.
local function PhysicalSize()
	local w, h = tostring(GetCVar("gxResolution") or ""):match("(%d+)x(%d+)")
	w, h = tonumber(w), tonumber(h)
	if not w or not h or h < 240 then return nil, nil end

	local aspect = GetScreenWidth() / GetScreenHeight()
	if aspect and aspect > 0.5 then
		local real = w / aspect
		if real > 240 and math.abs(real - h) > 2 then h = real end
	end
	return w, h
end

local function ApplyScale()
	if not hud then return end
	local w, h = PhysicalSize()
	H.pixels = h
	H.screenW = w
	local pixel = h and (768 / h) or 1
	local parentScale = hud:GetParent():GetEffectiveScale()
	if not parentScale or parentScale <= 0 then parentScale = 1 end
	local s = pixel / parentScale
	if s < 0.2 then s = 0.2 elseif s > 4 then s = 4 end
	hud:SetScale(s)
	H.pixel = pixel
end

-- Compartido con el visor de texturas (`/rts art`): cualquier frame que quiera
-- la misma escala de pixel que la HUD la pide aqui, en vez de repetir la
-- cuenta. Juzgar arte a otra escala es juzgar otra cosa.
function H:ScaleFrame(f)
	if not self.pixels then
		local _, h = PhysicalSize()
		self.pixels = h
	end
	local pixel = (self.pixels and (768 / self.pixels)) or 1
	local ps = f:GetParent() and f:GetParent():GetEffectiveScale() or 1
	if not ps or ps <= 0 then ps = 1 end
	local s = pixel / ps
	if s < 0.2 then s = 0.2 elseif s > 4 then s = 4 end
	f:SetScale(s)
end

--- El tamano de referencia: el boton de la barra de acciones ---------------
--
-- "Que los botones se vean como los de la barra de acciones" es una medida
-- mejor que cualquier numero elegido a ojo, porque es la que el jugador ya
-- tiene calibrada en la retina despues de anos de juego. Y no se escribe como
-- constante: se MIDE del cliente, asi que sigue valiendo si cambia el uiScale
-- o la resolucion, que es justo cuando un numero fijo se estropea.
--
-- La cuenta es la del apartado 1.2 del estudio al reves: un boton mide 36
-- unidades, y en pixeles fisicos eso es 36 * escalaEfectiva * (altoFisico/768).

function H:ActionButtonPixels()
	local btn = _G["ActionButton1"]
	local units = (btn and btn:GetWidth()) or 36
	if not units or units < 4 then units = 36 end
	local sc = (btn and btn:GetEffectiveScale()) or UIParent:GetEffectiveScale() or 1
	return units * sc * ((H.pixels or 768) / 768)
end

-- El alto que hace falta para que la rejilla tenga botones de ese tamano.
function H:HeightForCell(px)
	return math.floor(TOP + BOTTOM + ROWS * px + CELLGAP * (ROWS - 1) + 0.5)
end

--- Piezas de dibujo --------------------------------------------------------

-- El aspecto vive entero en Skin.lua: texturas del propio cliente, como
-- recomienda el apartado 6 del estudio. Aqui solo se pide "vistete".
local function Panel(parent, name, dim)
	local f = CreateFrame("Frame", name, parent)
	ns.Skin:Dress(f, dim)
	return f
end

local function Label(parent, size, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size or 13, "OUTLINE")
	fs:SetTextColor(r or 0.95, g or 0.85, b or 0.55)
	return fs
end

-- Una celda vacia del tamano de un boton de carta de comandos. Sirven para una
-- sola cosa y es la que se pidio: ver si la altura elegida da para las filas
-- que hacen falta, sin haber dibujado arte.
local function Cell(parent, side)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(side)
	f:SetHeight(side)

	-- Las dos capas existen siempre y Skin enciende la que toque, para que
	-- cambiar de aspecto en vivo no tenga que crear ni destruir nada.
	f.flatEdge = f:CreateTexture(nil, "BACKGROUND")
	f.flatEdge:SetAllPoints(f)
	f.flatEdge:SetTexture(0.62, 0.52, 0.30, 0.55)

	f.flatFill = f:CreateTexture(nil, "BORDER")
	f.flatFill:SetPoint("TOPLEFT", 1, -1)
	f.flatFill:SetPoint("BOTTOMRIGHT", -1, 1)
	f.flatFill:SetTexture(0.10, 0.11, 0.14, 0.92)

	f.slot = f:CreateTexture(nil, "BACKGROUND")
	f.slot:SetAllPoints(f)

	ns.Skin:Slot(f)
	return f
end

-- Las celdas se CREAN una vez y se REDIMENSIONAN en cada distribucion. Es lo
-- que convierte /rts ui height en una pregunta que se contesta mirando: al
-- bajar la barra, los botones encogen con ella, asi que se ve de un vistazo a
-- que altura dejan de tener tamano de boton.
local function Grid(parent, cols, rows)
	local g = CreateFrame("Frame", nil, parent)
	g.cols, g.rows, g.cells = cols, rows, {}
	for r = 1, rows do
		for c = 1, cols do
			local cell = Cell(g, 1)
			cell.r, cell.c = r, c
			table.insert(g.cells, cell)
		end
	end
	return g
end

local function SizeGrid(g, side, gap)
	if side < 8 then side = 8 end
	g:SetWidth(g.cols * side + (g.cols - 1) * gap)
	g:SetHeight(g.rows * side + (g.rows - 1) * gap)
	for _, cell in ipairs(g.cells) do
		cell:SetWidth(side)
		cell:SetHeight(side)
		cell:ClearAllPoints()
		cell:SetPoint("TOPLEFT", g, "TOPLEFT",
			(cell.c - 1) * (side + gap), -(cell.r - 1) * (side + gap))
	end
	return side
end

--- Linea de mensajes -------------------------------------------------------

local function BuildMessages()
	msgFrame = CreateFrame("Frame", "RTSHUDMessages", hud)
	msgFrame:SetWidth(760)
	msgFrame:SetHeight(MSG_LINES * 20)

	for i = 1, MSG_LINES do
		local fs = Label(msgFrame, 14, 1, 1, 1)
		fs:SetJustifyH("LEFT")
		fs:SetPoint("TOPLEFT", msgFrame, "TOPLEFT", 0, -(i - 1) * 20)
		fs:SetWidth(760)
		fs:SetHeight(20)
		fs:SetText("")
		msgLines[i] = { fs = fs, at = 0 }
	end

	local acc = 0
	msgFrame:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.1 then return end
		acc = 0
		local now = GetTime()
		for i = 1, MSG_LINES do
			local L = msgLines[i]
			if L.at > 0 then
				local age = now - L.at
				if age > MSG_LIFE + MSG_FADE then
					L.fs:SetText("")
					L.at = 0
				elseif age > MSG_LIFE then
					L.fs:SetAlpha(1 - (age - MSG_LIFE) / MSG_FADE)
				else
					L.fs:SetAlpha(1)
				end
			end
		end
	end)
end

--- El chat, sobre el mundo -------------------------------------------------
--
-- Esconder la ventana de chat deja sin ver lo que dicen los bots, el grupo y
-- los susurros -- que en este servidor es medio juego. En vez de devolver la
-- ventana, los mensajes se copian a esta misma linea, que es exactamente lo
-- que hace WC3: texto sobre el mundo, arriba a la izquierda, y se va solo.
--
-- Solo los tipos que importan aqui. El resto (comercio, canales publicos,
-- registro de combate) es ruido en una partida de un jugador.

local CHAT_COLOUR = {
	CHAT_MSG_SAY            = "ffffff",
	CHAT_MSG_YELL           = "ff4040",
	CHAT_MSG_PARTY          = "aaaaff",
	CHAT_MSG_PARTY_LEADER   = "aaaaff",
	CHAT_MSG_RAID           = "ff7f00",
	CHAT_MSG_RAID_LEADER    = "ff7f00",
	CHAT_MSG_WHISPER        = "ff80ff",
	CHAT_MSG_MONSTER_SAY    = "ffff80",
	CHAT_MSG_MONSTER_YELL   = "ff6060",
	CHAT_MSG_SYSTEM         = "ffff00",
}

H.mirrorChat = true

-- El mas nuevo arriba. Se empuja la lista hacia abajo en vez de reanclar
-- nada: son nueve cadenas, y mover texto es mas barato que mover frames.
function H:Message(msg)
	if not msgFrame then return end
	for i = MSG_LINES, 2, -1 do
		msgLines[i].fs:SetText(msgLines[i - 1].fs:GetText() or "")
		msgLines[i].at = msgLines[i - 1].at
	end
	msgLines[1].fs:SetText(tostring(msg))
	msgLines[1].at = GetTime()
	msgLines[1].fs:SetAlpha(1)
end

--- El minimapa -------------------------------------------------------------
--
-- Minimap es un frame normal de Blizzard y se puede reparentar: el motor lo
-- sigue dibujando el. Lo que NO viene incluido es su decoracion -- borde
-- redondo, tag del norte, botones de zoom, mapa del mundo -- que son hijos y
-- regiones suyas y viajan con el. Se apagan una a una, guardando lo que estaba
-- encendido, en vez de por lista de nombres: la lista de nombres se queda
-- corta en cuanto un addon cuelga su boton del minimapa.
--
-- La mascara cuadrada es lo que lo hace parecer un minimapa de RTS. WC3 y SC2
-- lo tienen rectangular; WoW lo recorta en circulo con Textures\MinimapMask.

local miniWas

local function GrabMinimap()
	if miniWas then return end

	miniWas = {
		parent = Minimap:GetParent(),
		scale  = Minimap:GetScale(),
		level  = Minimap:GetFrameLevel(),
		w      = Minimap:GetWidth(),
		points = {},
		kids   = {},
		regions = {},
	}
	for i = 1, Minimap:GetNumPoints() do
		miniWas.points[i] = { Minimap:GetPoint(i) }
	end

	for _, kid in ipairs({ Minimap:GetChildren() }) do
		table.insert(miniWas.kids, { f = kid, shown = kid:IsShown() })
		kid:Hide()
	end
	for _, reg in ipairs({ Minimap:GetRegions() }) do
		if reg.IsShown and reg.Hide then
			table.insert(miniWas.regions, { f = reg, shown = reg:IsShown() })
			reg:Hide()
		end
	end

	Minimap:SetParent(miniPanel)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", miniPanel, "CENTER", 0, 0)
	Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
	-- El ESTRATO se hereda del nuevo padre solo, asi que no se toca: ponerselo
	-- a mano seria una cosa mas que devolver al salir. El NIVEL no se hereda, y
	-- si se queda por debajo del panel el borde del panel dibuja sobre el mapa.
	Minimap:SetFrameLevel(miniPanel:GetFrameLevel() + 3)
end

local function ReleaseMinimap()
	if not miniWas then return end

	Minimap:SetMaskTexture("Textures\\MinimapMask")
	Minimap:SetScale(miniWas.scale)
	Minimap:SetParent(miniWas.parent)
	Minimap:SetFrameLevel(miniWas.level or 1)
	Minimap:ClearAllPoints()
	if #miniWas.points > 0 then
		for _, p in ipairs(miniWas.points) do
			Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end
	else
		Minimap:SetPoint("TOPRIGHT", MinimapCluster, "TOPRIGHT", -18, -38)
	end

	for _, rec in ipairs(miniWas.kids) do
		if rec.shown then rec.f:Show() end
	end
	for _, rec in ipairs(miniWas.regions) do
		if rec.shown then rec.f:Show() end
	end

	miniWas = nil
end

--- Distribucion ------------------------------------------------------------

local function Layout()
	if not hud then return end
	local c = H.cfg
	local W = hud:GetWidth()

	msgFrame:ClearAllPoints()
	msgFrame:SetPoint("TOPLEFT", hud, "TOPLEFT", c.pad, -c.pad)

	miniPanel:ClearAllPoints()
	miniPanel:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", c.pad, c.pad)
	miniPanel:SetWidth(c.mini)
	miniPanel:SetHeight(c.mini)

	-- El mapa, dentro del panel y por dentro del borde. Se escala en vez de
	-- redimensionarse: cambiar el TAMANO del Minimap cambia cuanto mundo se ve,
	-- escalarlo no -- y para juzgar la distribucion interesa que la vista sea
	-- la misma de siempre, solo mas grande.
	if miniWas then
		-- El hueco util depende del marco: el dorado de WC3 es mucho mas gordo
		-- que el fino, y si nadie lo pregunta el mapa se dibuja por debajo.
		local inner = c.mini - ns.Skin:Inset() * 2
		Minimap:SetScale(inner / (miniWas.w > 0 and miniWas.w or 140))
	end

	strip:ClearAllPoints()
	strip:SetPoint("BOTTOMLEFT", miniPanel, "BOTTOMRIGHT", c.gap, 0)
	strip:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -c.pad, c.pad)
	strip:SetHeight(c.height)

	strip.rightBox:SetWidth(c.right)

	-- Los botones salen del alto que quede, no al reves. TOP es el titulo,
	-- BOTTOM la nota de los retratos.
	local side = math.floor((c.height - TOP - BOTTOM - CELLGAP * (ROWS - 1)) / ROWS)
	SizeGrid(strip.grid, side, CELLGAP)
	local rSide = math.min(side, math.floor((c.right - 24 - CELLGAP * 3) / 4))
	SizeGrid(strip.rightBox.grid, rSide, CELLGAP)

	strip.measure:SetText(("barra: %d x %d px (%s del alto)   boton: %d px")
		:format(W - c.pad * 2 - c.mini - c.gap, c.height,
		        H.pixels and ("%.1f%%"):format(c.height / H.pixels * 100)
		                  or "|cffff0000?|r",
		        side))
end

local function BuildStrip()
	strip = Panel(hud, "RTSHUDStrip")

	local title = Label(strip, 13)
	title:SetPoint("TOPLEFT", strip, "TOPLEFT", 12, -10)
	title:SetText("|cffffd100ORDENES / CARTA DE COMANDOS|r  (hueco)")

	-- 4x3 es la carta de comandos de Warcraft 3. Puesta aqui de verdad, aunque
	-- este vacia, porque es la unica manera de contestar "cuanto alto hace
	-- falta" sin construir la carta entera primero.
	strip.grid = Grid(strip, 4, 3)
	strip.grid:SetPoint("TOPLEFT", strip, "TOPLEFT", 12, -30)

	local note = Label(strip, 11, 0.75, 0.75, 0.8)
	note:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 12, 9)
	note:SetText("retratos del grupo: centro-arriba (estudio 5.2)")

	strip.measure = Label(strip, 12, 0.6, 0.9, 1)
	strip.measure:SetPoint("TOPLEFT", strip.grid, "TOPRIGHT", 18, -2)

	local rightBox = Panel(strip, nil, true)
	rightBox:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -8, -8)
	rightBox:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -8, 8)
	strip.rightBox = rightBox

	local rTitle = Label(rightBox, 12)
	rTitle:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 10, -8)
	rTitle:SetText("ACCIONES DE BOTS")

	rightBox.grid = Grid(rightBox, 4, 3)
	rightBox.grid:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 10, -26)
end

local function BuildMinimapPanel()
	miniPanel = Panel(hud, "RTSHUDMinimap")

	zoneText = Label(miniPanel, 14)
	zoneText:SetPoint("BOTTOM", miniPanel, "TOP", 0, 6)
	zoneText:SetText("")
end

--- Crear -------------------------------------------------------------------

function H:Create()
	if hud then return end

	hud = CreateFrame("Frame", "RTSHUD", PARENT)
	hud:SetFrameStrata("MEDIUM")
	hud:SetPoint("BOTTOMLEFT", PARENT, "BOTTOMLEFT", 0, 0)
	hud:SetPoint("TOPRIGHT", PARENT, "TOPRIGHT", 0, 0)
	hud:Hide()

	ns.Skin:Load()

	BuildMessages()
	BuildMinimapPanel()
	BuildStrip()
	ApplyScale()

	if type(RTSCommandDB.hud) == "table" then
		for k in pairs(D) do
			local v = tonumber(RTSCommandDB.hud[k])
			if v then self.cfg[k] = v end
		end
	end

	-- Sin una medida guardada, el alto NO sale de la tabla de arriba: se calca
	-- del boton de la barra de acciones. Un numero elegido a ojo se equivoca en
	-- cuanto cambia la pantalla; este no.
	if type(RTSCommandDB.hudChat) == "boolean" then
		self.mirrorChat = RTSCommandDB.hudChat
	end

	if not (RTSCommandDB.hud and tonumber(RTSCommandDB.hud.height)) then
		self:Fit(true)
	end
	Layout()

	-- Cambiar de resolucion en caliente invalida la escala de pixel entera; es
	-- el apartado 6 del estudio y cuesta dos lineas ahora o una tarde despues.
	local ev = CreateFrame("Frame", "RTSHUDEvents")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("ZONE_CHANGED")
	ev:RegisterEvent("ZONE_CHANGED_INDOORS")
	ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	for e in pairs(CHAT_COLOUR) do ev:RegisterEvent(e) end

	ev:SetScript("OnEvent", function(_, event, msg, author)
		local colour = CHAT_COLOUR[event]
		if colour then
			if not (H.active and H.mirrorChat) then return end
			if not msg or msg == "" then return end
			H:Message(author and author ~= ""
				and ("|cff%s[%s]|r %s"):format(colour, author, msg)
				or  ("|cff%s%s|r"):format(colour, msg))
			return
		end

		if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
			ApplyScale()
			-- Si el alto lo puso el jugador, se respeta; si lo calcamos
			-- nosotros del boton de accion, se vuelve a calcar -- que es todo
			-- el sentido de haberlo derivado en vez de escribirlo.
			if H.autoFit then H:Fit(true) end
			Layout()
		else
			zoneText:SetText(GetMinimapZoneText() or "")
		end
	end)

	-- Con el chat escondido, ns.Print no llega a ninguna parte. Se envuelve una
	-- sola vez, aqui y no en Core.lua, para que este fichero se pueda quitar
	-- entero sin dejar rastro en el resto del addon.
	local orig = ns.Print
	ns.Print = function(msg)
		orig(msg)
		H:Message(msg)
	end
end

--- Entrar y salir ----------------------------------------------------------

-- Para que Skin pueda pedir recolocacion despues de revestir: cambiar de
-- marco cambia el hueco util, asi que el minimapa hay que reescalarlo.
function H:Relayout()
	Layout()
end

function H:Enter()
	if self.active then return end
	self:Create()
	self.active = true
	ApplyScale()
	GrabMinimap()
	Layout()
	zoneText:SetText(GetMinimapZoneText() or "")
	hud:Show()
end

function H:Leave()
	if not self.active then return end
	self.active = false
	ReleaseMinimap()
	if hud then hud:Hide() end
	for i = 1, MSG_LINES do
		if msgLines[i] then
			msgLines[i].fs:SetText("")
			msgLines[i].at = 0
		end
	end
end

function H:Toggle()
	if self.active then self:Leave() else self:Enter() end
	ns.Print("HUD de RTS " .. (self.active and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

--- Ajustes -----------------------------------------------------------------

function H:Set(key, value)
	if D[key] == nil then return false end
	local n = tonumber(value)
	if not n then return false end
	self.cfg[key] = n
	if key == "height" or key == "mini" then self.autoFit = false end
	RTSCommandDB.hud = RTSCommandDB.hud or {}
	RTSCommandDB.hud[key] = n
	Layout()
	return true
end

-- Alto de la barra tal que los botones midan lo mismo que los de la barra de
-- acciones del juego. El minimapa se iguala a la barra a proposito: los dos
-- forman UNA banda, y una banda con dos alturas distintas se ve como un error
-- aunque este puesta a posta.
function H:Fit(quiet)
	local px = self:ActionButtonPixels()
	local h = self:HeightForCell(px)
	self.cfg.height = h
	self.cfg.mini = h
	-- El bloque de la derecha tiene que dar para sus cuatro columnas al mismo
	-- tamano; si no, sus botones salen mas pequenos que los de la izquierda y
	-- parece un fallo de alineacion en vez de falta de sitio.
	self.cfg.right = math.max(D.right, math.floor(4 * px + CELLGAP * 3 + 24))
	self.autoFit = true
	if RTSCommandDB.hud then
		RTSCommandDB.hud.height = nil
		RTSCommandDB.hud.mini = nil
		RTSCommandDB.hud.right = nil
	end
	Layout()
	if not quiet then
		ns.Print(("boton de la barra de acciones = |cffffff00%.0f px|r -> " ..
			"barra de %d px de alto"):format(px, h))
	end
	return h
end

function H:MirrorChat()
	self.mirrorChat = not self.mirrorChat
	RTSCommandDB.hudChat = self.mirrorChat
	ns.Print("chat sobre el mundo " ..
		(self.mirrorChat and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

function H:Reset()
	for k, v in pairs(D) do self.cfg[k] = v end
	RTSCommandDB.hud = nil
	self:Fit(true)
end

function H:Report()
	local c = self.cfg
	ns.Print(("pantalla fisica: %s   1 unidad de HUD = 1 pixel (escala %.4f)"):format(
		(H.screenW and H.pixels) and ("%dx%d"):format(H.screenW, H.pixels)
			or "|cffff0000no leida|r",
		H.pixel or 0))
	ns.Print(("margen %d   minimapa %d   hueco %d   alto de barra %d   bloque derecho %d")
		:format(c.pad, c.mini, c.gap, c.height, c.right))
	if H.pixels then
		ns.Print(("la barra ocupa el |cffffff00%.1f%%|r del alto de pantalla; " ..
			"el minimapa con su margen, %.1f%%"):format(
			c.height / H.pixels * 100, (c.mini + c.pad) / H.pixels * 100))
	end
	ns.Print(("boton de la barra de acciones: |cffffff00%.0f px|r   " ..
		"boton de la HUD: |cffffff00%d px|r%s"):format(
		self:ActionButtonPixels(),
		math.floor((c.height - TOP - BOTTOM - CELLGAP * (ROWS - 1)) / ROWS),
		self.autoFit and "  (calcado)" or "  (a mano, |cffffff00/rts ui fit|r lo recalca)"))
	ns.Print("|cffffff00/rts ui height <px>|r  |cffffff00mini <px>|r  |cffffff00pad <px>|r  " ..
		"|cffffff00right <px>|r  |cffffff00gap <px>|r  |cffffff00fit|r  |cffffff00default|r")
end
