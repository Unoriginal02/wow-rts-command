--[[
	Window.lua -- las ventanas flotantes del modo RTS. Una sola implementacion.

	=== POR QUE EXISTE ESTE FICHERO ==========================================

	Las bolsas del grupo, las quests de un NPC y el entrenador/vendedor son tres
	paneles que se abren y se cierran. Escritos por separado serian tres veces
	el mismo trabajo -- arrastrar, cerrar, recordar el sitio, esconderse al salir
	del modo -- y, lo que es peor, tres veces DISTINTO: el tercero acabaria
	comportandose de otra manera que el primero sin que nadie lo hubiera
	decidido.

	Aqui hay UNA ventana y tres inquilinos.

	=== LOS PANELES FLOTANTES ESTUVIERON PROHIBIDOS, Y ESTO NO LOS RESUCITA ===

	`PRUEBAS-10` H1/H2 mando borrar tres paneles flotantes (`UnitBar`,
	`CommandCard`, el de `Targets`) con el argumento *"no quiero ninguno de esos
	paneles, ya tenemos hud definitivo"*. Aquello era correcto y sigue siendolo:
	eran paneles que decian lo MISMO que la barra de control y competian con
	ella por la mirada.

	Estos no. La diferencia es que estos se PIDEN y se CIERRAN -- no estan
	puestos mientras juegas -- y que lo que ensenan no cabe en la sala: la sala
	mide 344 x ~2246 unidades de dibujo, que en 2560x1440 son 1263 x 193 pixeles
	de verdad. Ciento noventa y tres pixeles son dos filas de bolsa. Las bolsas
	de cinco personajes no caben ahi por mucho que se redisene, asi que o son
	ventana o no existen.

	=== LO QUE ESTA VENTANA TIENE QUE HACER BIEN ============================

	Cinco cosas, y las cinco salen de fallos que este proyecto ya ha pagado:

	1. EL NOMBRE EMPIEZA POR "RTS". La ventana y sus tres hijos se crean CON
	   nombre, o sea que son globales del cliente, y un nombre sin prefijo es
	   una global suelta que puede pisar a la de otro addon -- o que otro addon
	   nos pise a nosotros. El prefijo es lo que hace que eso no pase.

	   Esto lo pedia ademas `ns.IsOurs`, que miraba el prefijo para dejar pasar
	   los tooltips con el cromo de Blizzard escondido: una ventana llamada de
	   otra forma salia entera SIN tooltips, tres ficheros mas alla de la causa.
	   Ese motivo ya no existe -- `Chrome.lua` esconde solo el tooltip del
	   mundo, mire quien mire -- pero el de las globales se queda.

	2. SE ESCONDE AL SALIR DEL MODO. Se registra UNA vez en `Bar:Register` -- el
	   gestor, no cada ventana -- para no repetir el enganche tres veces.

	3. NO SE ABRE SOLA AL ENTRAR. `Enter` no muestra nada a proposito. Una
	   ventana que reaparece porque estaba abierta hace media hora es una
	   ventana que el jugador no pidio, y el modo RTS ya esconde bastante cosa
	   como para ademas tapar el mundo por su cuenta.

	4. EL SITIO GUARDADO SE ACOTA AL LEERLO, no solo al escribirlo. Es el §7 de
	   `REVISION-ARQUITECTURA.md`, que este proyecto ha pagado cuatro veces
	   (`grow = 688`, `camHold`, `railCropGen`, y la purga de la sala). Aqui el
	   fallo concreto seria una ventana guardada fuera de pantalla al cambiar de
	   resolucion: no se ve, no se puede arrastrar de vuelta, y `/rts win reset`
	   seria la unica salida -- si a alguien se le ocurre que existe.

	5. ESCALA DE PIXEL PROPIA, la misma que la HUD (`H:ScaleFrame`). Sin ella el
	   arte se interpola y todo sale borroso, que es la leccion de la etapa 5i.
]]

local ADDON, ns = ...

local W = {}
ns.Window = W

--- Medidas, en unidades de DIBUJO ------------------------------------------
--
-- Igual que `Bar.lua`: aqui dentro 1 unidad = 1 pixel fisico, porque la ventana
-- lleva la escala de pixel de la HUD. Los numeros de este fichero son de dibujo
-- y NO de pantalla -- confundirlos es lo que dejo las guias de la sala a seis
-- pixeles en la etapa 5l.
local TITLE_H = 46      -- alto de la barra de titulo
local PAD     = 12      -- margen entre el marco y el contenido
local CLOSE   = 34      -- lado del boton de cerrar

local windows = {}      -- por nombre
local order   = {}      -- en orden de creacion, para `Leave` y `/rts win`

--- Persistencia ------------------------------------------------------------

local function Store(name)
	RTSCommandDB.win = RTSCommandDB.win or {}
	RTSCommandDB.win[name] = RTSCommandDB.win[name] or {}
	return RTSCommandDB.win[name]
end

-- EL SITIO SE NORMALIZA A UN ANCLA "CENTER", SIEMPRE.
--
-- `StartMoving` no promete conservar el ancla que tuviera el frame: WoW puede
-- dejarlo anclado por otra esquina, y entonces guardar solo `x, y` de
-- `GetPoint()` y restaurarlos como CENTER coloca la ventana en OTRO SITIO al
-- siguiente arranque. Es un fallo silencioso -- no da error, solo aparece
-- desplazada -- asi que en vez de confiar en el ancla se calcula el
-- desplazamiento del centro y se reancla a CENTER, que es el unico ancla que
-- este fichero entiende.
--
-- Los desplazamientos van en las unidades del PROPIO frame, porque es lo que
-- `SetPoint` espera, y este frame lleva su propia escala de pixel.
local function Normalize(f)
	local fx, fy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if not fx or not ux then return 0, 0 end

	local s  = f:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	if not s or s <= 0 then s = 1 end
	if not us or us <= 0 then us = 1 end

	local x = (fx * s - ux * us) / s
	local y = (fy * s - uy * us) / s

	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", x, y)
	return x, y
end

-- ¿Se ha quedado fuera de la pantalla?
--
-- Se pregunta DESPUES de colocarla y midiendo el rectangulo de verdad, en
-- pixeles de pantalla, en vez de razonando sobre el desplazamiento guardado --
-- que es la cuenta que se equivoca en cuanto las escalas del frame y de
-- UIParent no coinciden, y aqui nunca coinciden porque la ventana lleva la
-- escala de pixel de la HUD.
--
-- `SetClampedToScreen` ya impide arrastrarla fuera, asi que el unico camino
-- hasta aqui es cambiar de resolucion entre sesiones. Y el remedio es
-- recentrarla y DECIRLO: una ventana invisible que no se puede arrastrar de
-- vuelta se lee como "la ventana no abre", que manda a buscar el fallo al
-- sitio equivocado.
local function OffScreen(f)
	local s = f:GetEffectiveScale()
	if not s or s <= 0 then s = 1 end

	local left, right = f:GetLeft(), f:GetRight()
	local top, bottom = f:GetTop(), f:GetBottom()
	if not left or not right or not top or not bottom then return false end

	local us = UIParent:GetEffectiveScale()
	if not us or us <= 0 then us = 1 end
	local sw = UIParent:GetWidth() * us
	local sh = UIParent:GetHeight() * us

	local margin = 80   -- lo que hace falta ver para poder cogerla y arrastrarla
	return right * s < margin
	    or left * s > sw - margin
	    or top * s < margin
	    or bottom * s > sh
end

--- La ventana --------------------------------------------------------------

local Proto = {}

function Proto:Body()
	return self.body
end

function Proto:SetTitle(text)
	self.titleText:SetText(text or "")
end

-- `fn(self)` cuando se abre y cuando se cierra. Se guarda uno de cada, que es
-- lo que hace falta: el inquilino es siempre uno.
function Proto:OnShow(fn) self.onShow = fn end
function Proto:OnHide(fn) self.onHide = fn end

function Proto:IsOpen()
	return self.frame:IsShown()
end

function Proto:Open()
	if self.frame:IsShown() then return end
	self.frame:Show()
	if self.onShow then
		local ok, err = pcall(self.onShow, self)
		if not ok then ns.Print("|cffff0000" .. self.name .. ":|r " .. tostring(err)) end
	end
end

function Proto:Close()
	if not self.frame:IsShown() then return end
	self.frame:Hide()
	if self.onHide then
		local ok, err = pcall(self.onHide, self)
		if not ok then ns.Print("|cffff0000" .. self.name .. ":|r " .. tostring(err)) end
	end
end

function Proto:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end

-- El tamano se da en unidades de DIBUJO. Un inquilino que calcula su contenido
-- (las bolsas dependen de cuantos personajes haya) lo llama despues de saberlo.
function Proto:SetSize(w, h)
	self.w, self.h = w, h
	self.frame:SetWidth(w)
	self.frame:SetHeight(h)
	self.body:SetWidth(w - PAD * 2)
	self.body:SetHeight(h - TITLE_H - PAD)
	local st = Store(self.name)
	st.w, st.h = w, h
end

function Proto:ResetPosition()
	local st = Store(self.name)
	st.x, st.y = nil, nil
	self.frame:ClearAllPoints()
	self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

--- Fabrica -----------------------------------------------------------------

-- `name` TIENE que empezar por "RTS" -- ver el punto 1 de la cabecera. No se
-- corrige en silencio: se avisa y se corrige, porque el frame y sus tres hijos
-- se crean con nombre y sin prefijo son globales sueltas del cliente.
function W:New(name, title, w, h)
	if windows[name] then return windows[name] end

	if type(name) ~= "string" or name:sub(1, 3) ~= "RTS" then
		ns.Print("|cffff0000ventana:|r el nombre '" .. tostring(name) ..
		         "' no empieza por RTS; sin eso son globales sueltas. Corregido.")
		name = "RTS" .. tostring(name)
	end

	local win = setmetatable({}, { __index = Proto })
	win.name = name

	local f = CreateFrame("Frame", name, UIParent)
	win.frame = f
	f:Hide()
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)

	-- La escala de pixel de la HUD, para que 1 unidad de este fichero sea 1
	-- pixel fisico y el arte no se interpole.
	if ns.HUD and ns.HUD.ScaleFrame then ns.HUD:ScaleFrame(f) end

	if ns.Skin then ns.Skin:Dress(f) end

	-- Arrastrar por el TITULO y no por toda la ventana: si toda la ventana
	-- arrastra, coger un objeto de una bolsa mueve el panel.
	local bar = CreateFrame("Frame", name .. "Title", f)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD)
	bar:SetHeight(TITLE_H - PAD)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local st = Store(name)
		st.x, st.y = Normalize(f)
	end)
	win.titleBar = bar

	win.titleText = ns.W:Text(bar, ns.W.FONT.normal)
	win.titleText:SetPoint("LEFT", bar, "LEFT", 4, 0)
	win.titleText:SetText(title or name)

	local close = CreateFrame("Button", name .. "Close", bar)
	close:SetWidth(CLOSE)
	close:SetHeight(CLOSE)
	close:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	local x1 = close:CreateTexture(nil, "ARTWORK")
	x1:SetAllPoints()
	x1:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
	local hl = close:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	hl:SetBlendMode("ADD")
	close:SetScript("OnClick", function() win:Close() end)
	ns.W:Tip(close, "Cerrar", "Tambien con Escape.")

	-- El contenido. Los inquilinos dibujan aqui dentro y no tocan `f`.
	local body = CreateFrame("Frame", name .. "Body", f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_H)
	win.body = body

	-- Escape la cierra. `UISpecialFrames` necesita el nombre global, que es otra
	-- razon por la que la ventana se crea con nombre y no anonima.
	table.insert(UISpecialFrames, name)

	local st = Store(name)
	win:SetSize(st.w or w or 900, st.h or h or 560)

	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", tonumber(st.x) or 0, tonumber(st.y) or 0)
	if OffScreen(f) then
		st.x, st.y = nil, nil
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		ns.Print("|cffffff00ventana " .. name ..
		         ":|r estaba guardada fuera de pantalla; recentrada.")
	end

	windows[name] = win
	table.insert(order, win)
	return win
end

function W:Get(name)
	return windows[name]
end

--- Entrar y salir del modo RTS ---------------------------------------------

-- Nada. Ver el punto 3 de la cabecera: una ventana solo se abre porque alguien
-- la pide.
function W:Enter()
end

function W:Leave()
	for _, win in ipairs(order) do
		win:Close()
	end
end

--- `/rts win` --------------------------------------------------------------

function W:Report()
	if #order == 0 then
		ns.Print("ventanas: ninguna creada todavia.")
		return
	end
	for _, win in ipairs(order) do
		local st = Store(win.name)
		ns.Print(string.format("%s  %dx%d  %s  sitio %s,%s",
			win.name, win.w or 0, win.h or 0,
			win:IsOpen() and "|cff00ff00abierta|r" or "cerrada",
			tostring(st.x or "centro"), tostring(st.y or "centro")))
	end
end

function W:ResetAll()
	for _, win in ipairs(order) do win:ResetPosition() end
	ns.Print("ventanas: todas al centro.")
end

-- Se apunta EL GESTOR, no cada ventana. `Bar:Register` llama `Enter`/`Leave`, y
-- una ventana que aun no se ha creado no puede registrarse -- las tres se crean
-- la primera vez que se piden, no al cargar.
ns.Bar:Register(W)
