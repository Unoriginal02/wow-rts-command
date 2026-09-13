--[[
	QuestBook.lua -- el registro de misiones de TODO el grupo.

	Lo unico que no se podia ver. Tus misiones las dibuja el registro del juego
	desde 2004; las de tus cuatro companeros no las dibuja nadie, y hasta ahora
	la unica forma de saber si un bot llevaba una mision era plantarse delante
	del PNJ que la da y mirar su fila en la ventana del NPC.

	=== POR QUE ESTA SI ES UNA VENTANA, Y `Quests.lua` NO ====================

	`Quests.lua` decidio dos veces NO dibujar nada, y tenia razon las dos: lo que
	ensenaba eran TUS misiones, y de eso ya hay una ventana hecha que el jugador
	sabe usar. Lo unico que le faltaba era que el boton de compartir sirviera con
	un grupo de bots, y eso son cero pixeles nuevos.

	Aqui el contenido es otro. El registro del juego no puede ensenar el registro
	de otro personaje -- no hay API, y el cliente ni siquiera tiene esos datos --
	asi que o es ventana o no existe. Es el mismo criterio que dejo pasar las
	bolsas del grupo y la ventana del entrenador.

	=== EL SCROLL ES UN `ScrollFrame`, Y LA PRIMERA VERSION NO LO ERA ========

	Es el fallo que se vio en pantalla: *"el contenido pasa por encima del titulo
	y la ventana, y es infinito"*. La primera version movia un frame contenedor
	con `SetPoint`, que es lo que hace `Npc.lua`, y ahi no se nota porque su
	lista es corta.

	**En 3.3.5a un frame hijo NO se recorta contra su padre.** Esta escrito en
	este proyecto desde la etapa 5k y `Bags.lua` lo dice con todas las letras en
	su propia cabecera de distribucion -- *"un panel con las casillas dentro y
	desplazadas hacia arriba las ensenaria igual, por encima de la cabecera y
	fuera del marco"*. Es literalmente el sintoma, descrito antes de que pasara,
	en un fichero de al lado.

	`ScrollFrame` es el unico tipo de frame que SI recorta a su hijo. Y el tope
	del desplazamiento no sale gratis con el: hay que acotarlo contra el alto del
	contenido, que es lo que quita el "infinito".

	=== LA FORMA: UNA FICHA POR PERSONAJE ==================================

	Pedido asi, y contra la otra opcion que estaba encima de la mesa (una fila
	por mision con los nombres de quien la lleva). El de ahora es mas largo y
	repite titulos, y a cambio ensena **el registro de cada uno tal cual es**,
	que es la pregunta que se hace de verdad: que lleva este.

	Cada personaje es una ficha con su retrato y su nombre en color de clase --
	el mismo lenguaje que la barra de control y las bolsas, para que la ventana
	no parezca de otro addon. Dentro, las misiones van por zona, y las de CLASE
	tienen su propio grupo al principio: una mision de clase no se hace donde
	estas, se hace donde este tu entrenador, y mezclarla con las de la zona la
	esconde justo cuando hace falta verla.

	El maestro sale como uno mas, arriba del todo.

	=== EL BOTON FORZAR LA DA POR HECHA Y COBRADA ===========================

	Sin PNJ y sin ir a ningun sitio: objetivos por cumplidos, los objetos que
	falten a la bolsa, recompensa elegida por `BestReward` y fuera del registro.

	Es mas ancho que el forzado de `TurnIn`, que exige un PNJ delante y ademas
	solo alcanza a lo que TU ya entregaste. Aquella puerta existe porque su
	disparador es "se cerro el dialogo", que no dice de cual -- o sea que sin
	ella habria completado misiones que no eran. Aqui el disparador es un boton
	de una fila que NOMBRA la mision y NOMBRA al personaje, asi que no hay nada
	que adivinar y no hay de que protegerse. El porque entero, en `RtsQuests.h`.

	Lo que NO se salta sigue siendo `CanRewardQuest`: bolsa llena, diarias y el
	oro de las que cuestan dinero.
]]

local ADDON, ns = ...

local Q = {}
ns.QuestBook = Q

--- Medidas, en unidades de DIBUJO ------------------------------------------
--
-- La ventana lleva la escala de pixel de la HUD, asi que 1 unidad de aqui es 1
-- pixel fisico. Los tamanos salen de eso y no de un gusto: el retrato es el
-- mismo 36 que cabe en la cabecera de una ficha sin empujar el nombre.

local W        = 940    -- ancho de la ventana
local PAD      = 10
local BAR_H    = 30     -- la barra de arriba: cuenta y "Releer"
local VIEW_H   = 620    -- lo que se VE del contenido; el resto, con la rueda
local CARD_PAD = 8
local PORT     = 36     -- el retrato de la ficha
local HEAD_H   = PORT + CARD_PAD * 2
local ROW_H    = 30     -- una mision
local ZONE_H   = 26     -- un encabezado de zona
local BTN_W    = 120
local BTN_H    = 24
local STEP     = ROW_H  -- lo que mueve un diente de la rueda

--- Estado ------------------------------------------------------------------

local win, view, inner, header
local cards = {}

-- Lo que llega del servidor. `staging` se llena entre `QLOGZ`/`QLOG` y
-- `QLOGEND`, y solo entonces pasa a `data`: dibujar a medio volcado deja la
-- ventana parpadeando con listas incompletas.
local data    = { zones = {}, quests = {} }
local staging = nil

local ST_READY = 3

--- Pedir -------------------------------------------------------------------

function Q:Ask()
	staging = { zones = {}, quests = {} }
	ns.SendServer("QLOG")
end

--- Piezas ------------------------------------------------------------------

-- El `unit` del roster que corresponde a un nombre, o nil.
--
-- Hace falta para el retrato: `SetPortraitTexture` quiere una unidad, y el
-- servidor manda nombres. Un bot que se haya ido del grupo entre el volcado y
-- el dibujado devuelve nil, y entonces la ficha sale sin cara en vez de romper.
local function UnitOf(name)
	for _, u in ipairs(ns.Selection:GetRosterWithPlayer()) do
		if u.name == name then return u.unit, u.isPlayer end
	end
	return nil, false
end

--- Las fichas --------------------------------------------------------------

local function NewRow(card, i)
	local r = card.rows[i]
	if r then return r end

	r = CreateFrame("Frame", nil, card)

	r.label = ns.W:Text(r, ns.W.FONT.small)
	r.label:SetPoint("LEFT", r, "LEFT", 0, 0)

	r.state = ns.W:Text(r, ns.W.FONT.tiny)
	r.state:SetPoint("RIGHT", r, "RIGHT", BTN_W + 12, 0)

	-- La raya de un encabezado de zona. Se crea con la fila y se esconde, igual
	-- que el boton: crear texturas al pintar deja una nueva por repintado, y una
	-- textura no se puede destruir.
	r.rule = r:CreateTexture(nil, "ARTWORK")
	r.rule:SetTexture(1, 0.82, 0, 0.18)
	r.rule:SetHeight(1)
	r.rule:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2)
	r.rule:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 2)

	r.force = CreateFrame("Button", nil, r)
	r.force:SetWidth(BTN_W)
	r.force:SetHeight(BTN_H)
	r.force:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	if ns.Skin then ns.Skin:Dress(r.force, true) end
	r.force.label = ns.W:Text(r.force, ns.W.FONT.tiny)
	r.force.label:SetPoint("CENTER", r.force, "CENTER", 0, 0)
	r.force.label:SetText("Forzar")
	ns.W:Tip(r.force, "Forzar",
		"La da por hecha Y COBRADA ahi mismo, sin ir al PNJ.\n" ..
		"Objetivos cumplidos, los objetos que falten a la bolsa,\n" ..
		"y la recompensa se elige sola por clase y stats.\n\n" ..
		"No se salta la bolsa llena, las diarias, ni el oro\n" ..
		"de las misiones que cuestan dinero.")

	card.rows[i] = r
	return r
end

local function PaintZone(r, zone, count)
	r:SetHeight(ZONE_H)
	r.label:SetFont(GameFontNormal:GetFont(), ns.W.FONT.tiny, "OUTLINE")
	r.label:SetTextColor(1, 0.82, 0)
	r.label:SetText(("%s  |cff888888(%d)|r"):format(zone, count))
	r.state:SetText("")
	r.rule:Show()
	r.force:Hide()
end

local function PaintQuest(r, e)
	r:SetHeight(ROW_H)
	r.label:SetFont(GameFontNormal:GetFont(), ns.W.FONT.small, "OUTLINE")
	r.label:SetText("   " .. e.title)

	if e.status == ST_READY then
		r.label:SetTextColor(1, 0.82, 0)
		r.state:SetText("|cffffcc00lista|r")
	else
		r.label:SetTextColor(0.88, 0.88, 0.88)
		r.state:SetText("|cff888888en curso|r")
	end

	r.rule:Hide()
	r.force:Show()
	r.force:SetScript("OnClick", function()
		ns.SendServer(("QFORCE %d %s"):format(e.questId, e.name))
	end)
end

local function NewCard(i)
	local c = cards[i]
	if c then return c end

	c = CreateFrame("Frame", "RTSQuestBookCard" .. i, inner)
	c:SetWidth(W - PAD * 2)

	-- El mismo revestimiento que las columnas de las bolsas y la consola, para
	-- que esto no parezca una ventana de otro addon. `Skin` lo apunta en su
	-- lista, asi que `/rts skin` lo cambia en vivo con todo lo demas.
	if ns.Skin then ns.Skin:Dress(c, true) end

	c.portrait = c:CreateTexture(nil, "ARTWORK")
	c.portrait:SetWidth(PORT)
	c.portrait:SetHeight(PORT)
	c.portrait:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -CARD_PAD)
	ns.W:Border(c, c.portrait, PORT)

	c.name = ns.W:Text(c, ns.W.FONT.normal)
	c.name:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + PORT + 10, -CARD_PAD - 2)

	c.count = ns.W:Text(c, ns.W.FONT.tiny)
	c.count:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD + PORT + 10, -CARD_PAD - 24)

	c.rows = {}
	cards[i] = c
	return c
end

--- Agrupar -----------------------------------------------------------------

-- Lo que hay que dibujar, en orden, ya agrupado.
--
-- Se construye entero antes de pintar nada. La alternativa -- decidir el grupo
-- mientras se recorre -- obliga a mirar hacia atras para saber si el nombre de
-- la zona ya se escribio, y ahi es exactamente donde se cuelan los encabezados
-- repetidos y los grupos vacios.
local function Plan()
	local byPerson, people = {}, {}

	for _, e in ipairs(data.quests) do
		if not byPerson[e.name] then
			byPerson[e.name] = {}
			table.insert(people, e.name)
		end

		-- Las de clase van a un cajon con nombre fijo y no a la zona que
		-- tuvieran: son su propio grupo, y el servidor ya las manda sin zona.
		local key = e.classQuest and "\1Clase" or (data.zones[e.zid] or "Sin zona")
		byPerson[e.name][key] = byPerson[e.name][key] or {}
		table.insert(byPerson[e.name][key], e)
	end

	local out = {}
	for _, name in ipairs(people) do
		local blocks, total = {}, 0

		-- El `\1` delante de "Clase" es lo que la deja ordenada la primera sin
		-- un caso especial en la comparacion: ordena antes que cualquier letra.
		-- Se quita al escribirla.
		local keys = {}
		for key in pairs(byPerson[name]) do table.insert(keys, key) end
		table.sort(keys)

		for _, key in ipairs(keys) do
			local list = byPerson[name][key]
			table.sort(list, function(a, b) return a.title < b.title end)
			total = total + #list
			table.insert(blocks, { zone = (key:gsub("^\1", "")), list = list })
		end

		table.insert(out, { name = name, blocks = blocks, total = total })
	end

	return out
end

--- Dibujar -----------------------------------------------------------------

-- Acota el desplazamiento contra el alto real del contenido.
--
-- Va en su propia funcion porque lo llaman DOS sitios y tienen que decidir
-- igual: la rueda y el repintado. Sin el segundo, releer una lista mas corta
-- deja la vista donde estaba y la ficha se queda fuera de pantalla.
local function ClampScroll(contentH)
	local maxScroll = math.max(0, contentH - VIEW_H)
	if view:GetVerticalScroll() > maxScroll then
		view:SetVerticalScroll(maxScroll)
	end
	view.maxScroll = maxScroll
end

function Q:Layout()
	if not win or not win:IsOpen() then return end

	local plan = Plan()
	local y = 0

	for i, p in ipairs(plan) do
		local c = NewCard(i)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -y)
		c:Show()

		local unit, isPlayer = UnitOf(p.name)
		if unit and UnitExists(unit) then
			SetPortraitTexture(c.portrait, unit)
		else
			c.portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end

		local col = isPlayer and { 1, 0.85, 0.4 }
			or (unit and ns.W:ClassColor(unit)) or { 1, 1, 1 }
		c.name:SetText(p.name)
		c.name:SetTextColor(col[1] or col.r or 1, col[2] or col.g or 1, col[3] or col.b or 1)
		c.count:SetText(("|cff888888%d mision(es)|r"):format(p.total))

		-- Las filas de esta ficha, en un solo recorrido: el encabezado de cada
		-- zona y debajo sus misiones.
		local n, ry = 0, HEAD_H
		for _, b in ipairs(p.blocks) do
			n = n + 1
			local r = NewRow(c, n)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -ry)
			r:SetWidth(W - PAD * 2 - CARD_PAD * 2)
			r:Show()
			PaintZone(r, b.zone, #b.list)
			ry = ry + ZONE_H

			for _, e in ipairs(b.list) do
				n = n + 1
				local q = NewRow(c, n)
				q:ClearAllPoints()
				q:SetPoint("TOPLEFT", c, "TOPLEFT", CARD_PAD, -ry)
				q:SetWidth(W - PAD * 2 - CARD_PAD * 2)
				q:Show()
				PaintQuest(q, e)
				ry = ry + ROW_H
			end
		end
		for k = n + 1, #c.rows do c.rows[k]:Hide() end

		c:SetHeight(ry + CARD_PAD)
		y = y + ry + CARD_PAD + PAD
	end

	for i = #plan + 1, #cards do cards[i]:Hide() end

	if #plan == 0 then
		header:SetText("|cff888888Nadie del grupo lleva ninguna mision.|r")
	else
		header:SetText(("%d mision(es) entre %d personaje(s)."):format(#data.quests, #plan))
	end

	-- El hijo del `ScrollFrame` NUNCA mide menos que la ventana. Con un hijo mas
	-- bajo, 3.3.5a deja de contestar a la rueda y la vista se queda pegada.
	inner:SetHeight(math.max(VIEW_H, y))
	ClampScroll(y)
end

--- Ciclo -------------------------------------------------------------------

function Q:Create()
	if win then return end

	local H = 46 + PAD + BAR_H + PAD + VIEW_H + PAD
	win = ns.Window:New("RTSQuestBook", "Misiones del grupo", W, H)

	-- Y SE FIJA OTRA VEZ, PORQUE EL GUARDADO GANA AL PEDIDO.
	--
	-- `W:New` hace `SetSize(st.w or w, st.h or h)`, o sea que un tamano en las
	-- SavedVariables pisa el que se le pasa. La primera version de esta ventana
	-- lo recalculaba en cada `Layout` segun el contenido, asi que ahi dentro hay
	-- un alto viejo -- y con el, la ventana saldria de un tamano y el hueco que
	-- recorta de otro: contenido cortado a media ficha, o un agujero debajo.
	--
	-- Aqui el tamano no es una preferencia del jugador: estas ventanas no se
	-- redimensionan, y lo guardado es solo lo ultimo que escribio el inquilino.
	-- Asi que se manda. Misma leccion que el `grow = 688` y que el `pitch` de la
	-- camara libre: un valor guardado gana siempre, y hay que decidir si eso es
	-- lo que quieres.
	win:SetSize(W, H)

	local body = win:Body()

	local bar = CreateFrame("Frame", "RTSQuestBookBar", body)
	bar:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, 0)
	bar:SetWidth(W - PAD * 2)
	bar:SetHeight(BAR_H)

	header = ns.W:Text(bar, ns.W.FONT.small)
	header:SetPoint("LEFT", bar, "LEFT", 0, 0)

	local refresh = CreateFrame("Button", nil, bar)
	refresh:SetWidth(BTN_W)
	refresh:SetHeight(BTN_H)
	refresh:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	if ns.Skin then ns.Skin:Dress(refresh, true) end
	refresh.label = ns.W:Text(refresh, ns.W.FONT.tiny)
	refresh.label:SetPoint("CENTER", refresh, "CENTER", 0, 0)
	refresh.label:SetText("Releer")
	ns.W:Tip(refresh, "Releer", "Vuelve a pedirle al servidor los registros.")
	refresh:SetScript("OnClick", function() Q:Ask() end)

	-- LA VENTANA QUE RECORTA. Ver la cabecera: es el unico frame de 3.3.5a que
	-- recorta a su hijo, y sin el las fichas se dibujan por encima del titulo.
	view = CreateFrame("ScrollFrame", "RTSQuestBookView", body)
	view:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -PAD)
	view:SetWidth(W - PAD * 2)
	view:SetHeight(VIEW_H)

	inner = CreateFrame("Frame", "RTSQuestBookInner", view)
	inner:SetWidth(W - PAD * 2)
	inner:SetHeight(VIEW_H)
	view:SetScrollChild(inner)

	view.maxScroll = 0
	view:EnableMouseWheel(true)
	view:SetScript("OnMouseWheel", function(self, delta)
		local at = self:GetVerticalScroll() - delta * STEP
		if at < 0 then at = 0 end
		if at > (self.maxScroll or 0) then at = self.maxScroll or 0 end
		self:SetVerticalScroll(at)
	end)

	-- El nombre de una zona, una vez cada una. Llega ANTES que las filas que la
	-- usan, por construccion del lado del servidor.
	ns.Link:On("QLOGZ", function(rest)
		local zid, name = rest:match("^(%d+)%s+(%S.*)$")
		if not zid or not staging then return end
		staging.zones[tonumber(zid)] = name
	end)

	-- "QLOG <nombre> <questId> <estado> <clase> <zid> <titulo>".
	--
	-- EL DISCRIMINANTE DE LOS DOS SENTIDOS ES QUE LA PETICION VA VACIA: mandamos
	-- "QLOG" a secas. El patron no casa cuando no hay nada detras del verbo, asi
	-- que el eco de nuestra propia peticion no entra como una fila basura. Es la
	-- misma precaucion que `Npc.lua` toma con TRAINER y VENDOR.
	ns.Link:On("QLOG", function(rest)
		if not staging then return end

		local name, id, st, cls, zid, title =
			rest:match("^(%S+)%s+(%d+)%s+(%d+)%s+([01])%s+(%d+)%s+(%S.*)$")
		if not name then return end

		table.insert(staging.quests, {
			name       = name,
			questId    = tonumber(id),
			status     = tonumber(st),
			classQuest = cls == "1",
			zid        = tonumber(zid),
			title      = title,
		})
	end)

	ns.Link:On("QLOGEND", function()
		if not staging then return end
		data, staging = staging, nil
		Q:Layout()
	end)

	-- El servidor contesta a `QFORCE` con la misma forma que a compartir y
	-- entregar. Solo nos toca la F; las otras letras son de otros botones y ya
	-- tienen quien las escuche.
	ns.Link:On("QDONE", function(rest)
		local what = rest:match("^(%S+)")
		if what ~= "F" then return end
		-- El detalle por personaje ya lo ha escrito el servidor en el chat. Aqui
		-- solo hay que volver a leer, porque una mision cobrada SALE del registro
		-- y la fila tiene que irse con ella.
		Q:Ask()
	end)
end

function Q:Open()
	self:Create()
	win:Open()
	self:Ask()
	self:Layout()
end

function Q:Toggle()
	self:Create()
	if win:IsOpen() then win:Close() else self:Open() end
end
