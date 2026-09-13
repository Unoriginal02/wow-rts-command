--[[
	Widgets.lua -- las cuatro piezas que todos los paneles repiten.

	Una barra de estado, un texto, un boton de icono y el color de clase. Nada
	mas. Existe porque los paneles las necesitaban todas, y la alternativa era la
	misma docena de lineas copiada cinco veces -- que es como se acaba con cinco
	fuentes distintas y cuatro texturas de barra distintas en la misma pantalla.

	TODAS LAS MEDIDAS SON PIXELES FISICOS, no unidades de pantalla. Todo lo que
	usa esto cuelga del contenedor de `Pixels.lua`, donde una unidad es un pixel,
	asi que en una pantalla de 1440 un texto de 22 se ve como uno de 12. Los
	tamanos de aqui estan elegidos para eso, y por eso hay `ns.W.FONT` en vez de
	un numero suelto en cada panel.

	EL COLOR DE CLASE SE PREGUNTA POR TOKEN, NO POR NOMBRE. `RAID_CLASS_COLORS`
	esta indexado por el token en ingles ("MAGE"), que es el SEGUNDO valor que
	devuelve UnitClass -- el primero esta traducido y no vale como clave. Con el
	cliente en espanol el primero es "Mago" y la tabla devuelve nil, que se ve
	como "todas las barras grises" y no como un error.
]]

local ADDON, ns = ...

local W = {}
ns.W = W

-- Tamanos de fuente en pixeles de DIBUJO. ~2x lo que se quiere ver.
W.FONT = { tiny = 18, small = 22, normal = 26, big = 32 }

-- La textura de barra del propio cliente. Lisa, con un brillo suave arriba, y
-- es la que el jugador ya tiene en la retina de los marcos de objetivo.
W.BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

-- EL MARCO DE "SELECCIONADO", EN UN SOLO SITIO. El retrato del heroe lo dibujaba
-- de 2 y las filas del grupo de 1, y estos son pixeles de DIBUJO: a la escala de
-- la barra, uno es medio pixel de pantalla. La fila seleccionada no se
-- distinguia de las demas. Un grosor suelto por panel es como se acaba con tres
-- marcas que dicen lo mismo con distinta voz.
W.SELECT = { r = 1, g = 0.92, b = 0.45, a = 1, thick = 4 }

--- Colores ----------------------------------------------------------------

local GREY = { r = 0.55, g = 0.55, b = 0.58 }

-- El color de la clase de una unidad. Devuelve gris si no se sabe, nunca nil:
-- un color que falta tiene que verse como "no lo se", no reventar el que lo usa.
function W:ClassColor(unit)
	if not unit or not UnitExists(unit) then return GREY end
	-- PARA TI NO SE LE PREGUNTA AL CLIENTE. `UnitClass("player")` lee un byte
	-- estatico que rellena la pantalla de seleccion de personaje, asi que tras
	-- un cambio devuelve la clase con la que ARRANCASTE la sesion -- un mago con
	-- el color del guerrero. Esta desensamblado en `Bridge.lua`.
	local token
	if ns.IsMe and ns.IsMe(unit) then
		token = ns.MyClass()
	else
		token = select(2, UnitClass(unit))
	end
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	return c or GREY
end

-- El color de un tipo de poder. `PowerBarColor` existe en 3.3.5a pero no cubre
-- los tipos raros, asi que la tabla es propia y corta -- son los cinco que un
-- personaje jugable puede tener en WotLK.
local POWER = {
	[0] = { r = 0.20, g = 0.40, b = 0.90 },   -- mana
	[1] = { r = 0.80, g = 0.20, b = 0.20 },   -- ira
	[2] = { r = 1.00, g = 0.60, b = 0.20 },   -- concentracion
	[3] = { r = 0.95, g = 0.90, b = 0.30 },   -- energia
	[6] = { r = 0.00, g = 0.70, b = 0.90 },   -- poder runico
}

function W:PowerColor(unit)
	local t = unit and UnitPowerType and UnitPowerType(unit) or 0
	return POWER[t] or POWER[0]
end

--- Numeros ----------------------------------------------------------------

-- 18400 -> "18,4k". En una barra de 256 px de dibujo no cabe "18400 / 23150" a
-- un tamano legible, y el numero exacto no es lo que se mira de un vistazo.
-- ¿ESTA PUESTA ESTA BANDERA? Sin `bit`, y eso es deliberado.
--
-- `bit.band` existe en 3.3.5a. Pero no lo usaba NI UN FICHERO de este addon
-- antes de las bolsas y las misiones, y este proyecto lleva cinco etapas
-- pagando la misma factura -- `nameplateMaxDistance`, `gxWindowedResolution`,
-- `SetCamera(1)`, `GetActionInfo` -- que siempre es la misma: dar por buena una
-- llamada del cliente sin comprobarla, y que al fallar **no de error**. Aqui
-- fallaria como banderas que nunca estan puestas: un objeto vinculado que se
-- deja coger, una mision con eleccion cuyo boton no pregunta.
--
-- La aritmetica no puede fallar y es exacta para potencias de dos, que es todo
-- lo que hay en los dos protocolos. Cuatro lineas contra una comprobacion
-- pendiente.
function W:Flag(value, flag)
	value = tonumber(value) or 0
	flag = tonumber(flag) or 0
	if flag <= 0 then return false end
	return math.floor(value / flag) % 2 == 1
end

function W:Short(n)
	n = tonumber(n) or 0
	if n >= 1000000 then return ("%.1fM"):format(n / 1000000) end
	if n >= 10000 then return ("%.0fk"):format(n / 1000) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n))
end

--- Piezas -----------------------------------------------------------------

function W:Text(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(GameFontNormal:GetFont(), size or W.FONT.small, "OUTLINE")
	fs:SetTextColor(1, 1, 1)
	return fs
end

-- UN BORDE DE UNA RAYA ALREDEDOR DE ALGO, normalmente un retrato.
--
-- Cuatro texturas y no un aro de los del cliente: las de Blizzard vienen con su
-- propio recorte y un `SetTexCoord` a ciegas es adivinar. Es la misma decision,
-- por el mismo motivo, que ya tomo `Frames.lua` con el aro de su retrato -- y
-- por eso sale aqui, que es donde deja de ser la tercera copia.
--
-- `anchor` es la textura o el frame al que se le pone el marco; `size` su lado.
-- Se devuelven las cuatro rayas para poder recolorearlas.
function W:Border(parent, anchor, size, r, g, b, a)
	r, g, b, a = r or 0.45, g or 0.45, b or 0.5, a or 0.9
	local e = {}
	for i = 1, 4 do
		e[i] = parent:CreateTexture(nil, "OVERLAY")
		e[i]:SetTexture(r, g, b, a)
	end
	e[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
	e[1]:SetWidth(size + 2) e[1]:SetHeight(1)
	e[2]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -1, -1)
	e[2]:SetWidth(size + 2) e[2]:SetHeight(1)
	e[3]:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
	e[3]:SetWidth(1) e[3]:SetHeight(size + 2)
	e[4]:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 1, 1)
	e[4]:SetWidth(1) e[4]:SetHeight(size + 2)
	return e
end

-- Una barra de estado con fondo negro y, si se pide, un texto encima. El fondo
-- NO es opcional: sin el, una barra vacia es un agujero en el arte y no se
-- distingue de una barra que no existe.
function W:Bar(parent, withText)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(W.BAR_TEX)
	b:SetMinMaxValues(0, 1)
	b:SetValue(1)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(0, 0, 0, 0.7)

	if withText then
		b.text = self:Text(b, W.FONT.small)
		b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
		b.right = self:Text(b, W.FONT.small)
		b.right:SetPoint("RIGHT", b, "RIGHT", -6, 0)
	end

	return b
end

-- Poner una barra a una fraccion sin repetir la division ni el caso de max=0,
-- que es lo que devuelve una unidad que acaba de aparecer.
function W:Fill(b, cur, max)
	local frac = (max and max > 0) and (cur / max) or 0
	if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
	b:SetValue(frac)
	return frac
end

function W:Color(b, c)
	if c then b:SetStatusBarColor(c.r, c.g, c.b) end
end

-- Un boton de icono, del tamano que le digan. El recorte de 0.07 quita el borde
-- que traen dibujado los iconos del cliente, para que quede a ras como los de la
-- barra de acciones.
--
-- NO USA PLANTILLA. `ActionButtonTemplate` arrastra la maquinaria de hechizos y
-- ademas es un frame PROTEGIDO: heredarlo aqui seria pedir que Blizzard bloquee
-- la mitad de lo que hace este addon. Estos botones mandan texto por el canal de
-- ordenes, que no esta protegido.
-- `template` existe por la bandeja de macros: un macro solo se puede lanzar
-- desde un `SecureActionButtonTemplate` (`RunMacro` esta protegida), y lo demas
-- -- el fondo, el icono, el resalte -- es exactamente igual que en un boton
-- corriente. Pasarlo aqui evita tener dos funciones que dibujan lo mismo.
function W:Button(parent, size, icon, template)
	local b = CreateFrame("Button", nil, parent, template)
	b:SetWidth(size)
	b:SetHeight(size)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetTexture(0, 0, 0, 0.55)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if icon then b.icon:SetTexture(icon) end

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	b.label = self:Text(b, W.FONT.tiny)
	b.label:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
	b.label:SetJustifyH("CENTER")

	return b
end

-- UNA BARRA ANCHA CON SU NOMBRE ESCRITO -- un MACRO.
--
-- Es la otra forma de boton de esta consola, y la diferencia con `W:Button` no
-- es de tamano sino de que se lee: un icono se RECONOCE y un macro se LEE. La
-- rejilla 4x4 lleva quince ordenes fijas que acabas conociendo por el dibujo;
-- un macro es algo que el jugador ha puesto ahi y puede cambiar manana, asi que
-- su nombre tiene que estar delante.
--
-- SIN ICONO DESDE LA 0.77.0, y a peticion: *"no quiero los botones con icono,
-- seran textos"* (`PRUEBAS-23`, seccion E). Llevaba uno pequeno a la izquierda
-- "como pista"; en pantalla lo que hacia era quitarle a la etiqueta el tercio
-- que mas falta le hace, para poner cuatro dibujos que a ese tamano no se
-- reconocen.
--
-- EL ICONO SIGUE EN LA TABLA DE ACCIONES, porque el desplegable de eleccion si
-- lo usa: ahi hay once opciones en una lista vertical y el dibujo ayuda a
-- encontrar la que buscas. Misma pieza, dos sitios, dos respuestas -- y esta
-- bien que sean distintas.
function W:Wide(parent, w, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w)
	b:SetHeight(h)

	-- UN BORDE FINO, y son DOS texturas y no cinco: la de abajo ocupa el boton
	-- entero con el color del borde, y la oscura se mete `EDGE` por dentro. Lo
	-- que asoma es el marco. Cuatro rayas darian lo mismo y habria que
	-- recolocarlas en cada `WideSize`.
	--
	-- Sale del boceto retocado del 2026-09-05, medido: un pixel de pantalla de
	-- (87,67,118) alrededor de cada macro. Sin el, cuatro rectangulos oscuros
	-- sobre un panel oscuro se leen como huecos y no como botones -- que es
	-- justo lo que se pierde al quitarles el icono.
	local EDGE = 2

	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetAllPoints()
	b.edge:SetTexture(0.55, 0.47, 0.72, 0.75)

	b.bg = b:CreateTexture(nil, "BORDER")
	b.bg:SetPoint("TOPLEFT", b, "TOPLEFT", EDGE, -EDGE)
	b.bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -EDGE, EDGE)
	b.bg:SetTexture(0, 0, 0, 0.55)

	local pad = 3

	-- EL TEXTO SE ANCLA A LOS DOS LADOS, no se le da un ancho. Un FontString de
	-- ancho fijo en 3.3.5a NO recorta: parte en dos lineas y deja la segunda a
	-- medias contra el borde (`SetWordWrap` no existe). Anclado izquierda y
	-- derecha dentro de un alto de una linea, lo que sobra se recorta solo.
	--
	-- CENTRADO ahora que ocupa la barra entera: alineado a la izquierda y sin
	-- icono delante, las cuatro etiquetas quedaban pegadas al borde.
	b.label = self:Text(b, W.FONT.small)
	b.label:SetPoint("LEFT", b, "LEFT", 8, 0)
	b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
	b.label:SetJustifyH("CENTER")
	b.label:SetHeight(h - pad * 2)

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	return b
end

-- Recolocar una barra ancha sin recrearla.
function W:WideSize(b, w, h)
	local pad = 3
	b:SetWidth(w)
	b:SetHeight(h)
	b.label:SetHeight(h - pad * 2)
end

-- Encender y apagar un boton dejandolo VISIBLE pero apagado, que es distinto de
-- esconderlo: una casilla vacia significa "no hay orden aqui" y una apagada
-- "esta orden necesita algo que no tienes".
function W:Enable(b, on)
	if on then
		b:Enable()
		b.icon:SetVertexColor(1, 1, 1)
		b.icon:SetAlpha(1)
	else
		b:Disable()
		b.icon:SetVertexColor(0.4, 0.4, 0.4)
		b.icon:SetAlpha(0.7)
	end
end

-- El tooltip de un boton, en dos lineas. Repetido en los cuatro paneles con
-- ordenes, asi que vive aqui.
--
-- EL TEXTO SE GUARDA EN EL BOTON Y LOS SCRIPTS SE PONEN UNA SOLA VEZ. Se llama
-- desde los refrescos -- la fila de enemigos la llama por cada cuadrado cinco
-- veces por segundo -- y crear dos cierres nuevos en cada llamada son cientos de
-- funciones por segundo que solo existen para ser recogidas por el GC. Los
-- manejadores leen `self.tipTitle`, asi que cambiar el texto no necesita
-- cambiar el script.
function W:Tip(b, title, body)
	b.tipTitle, b.tipBody = title, body
	if b.tipWired then return end
	b.tipWired = true

	b:SetScript("OnEnter", function(self)
		if not self.tipTitle then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		-- `SetOwner` NO borra las lineas anteriores, y con `AddLine` eso
		-- significa que el tooltip crece cada vez que se pasa por encima. Es el
		-- fallo que arrastro `CommandCard.lua` desde la etapa 5a hasta que se
		-- borro; aqui va con ClearLines desde el principio.
		GameTooltip:ClearLines()
		GameTooltip:AddLine(self.tipTitle)
		if self.tipBody then
			GameTooltip:AddLine(self.tipBody, 0.8, 0.8, 0.8, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--- Latido -----------------------------------------------------------------

-- Un temporizador compartido. Los paneles quieren refrescar vida, poder y
-- estado varias veces por segundo, y hacerlo con eventos son cuarenta registros
-- (UNIT_HEALTH, UNIT_MANA, UNIT_RAGE, UNIT_ENERGY, UNIT_RUNIC_POWER,
-- UNIT_MAXMANA...) que aun asi no cubren "el bot se ha movido".
--
-- UN SOLO OnUpdate, no uno por panel. Cinco OnUpdate con su propio acumulador
-- son cinco sitios donde ajustar el ritmo y cinco veces el coste de la llamada.
local ticks = {}
local acc = 0
local heart

function W:Every(fn)
	table.insert(ticks, fn)
	if not heart then
		heart = CreateFrame("Frame", "RTSWidgetHeartbeat")
		heart:SetScript("OnUpdate", function(_, e)
			acc = acc + e
			if acc < 0.2 then return end
			acc = 0
			for _, f in ipairs(ticks) do
				-- Un panel que falle no puede parar el latido de los demas.
				pcall(f)
			end
		end)
	end
end
