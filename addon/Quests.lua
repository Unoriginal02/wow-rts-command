--[[
	Quests.lua -- todas las misiones de un NPC, y quien del grupo puede cogerlas.

	Es lo del video: pinchas un NPC y ves de un vistazo sus misiones y, por cada
	una, un punto de color por personaje -- puede cogerla, la lleva, la tiene
	lista, ya la hizo, no le vale. Un boton la acepta o la entrega para todos.

	=== LOS NOMBRES FLOTANDO SOBRE EL NPC NO SE COPIAN ======================

	En el video los nombres de los bots flotan sobre la cabeza del NPC. Ese
	desarrollador ha reescrito el cliente; nosotros dibujariamos eso proyectando
	un texto de interfaz sobre el mundo, y eso ya se probo en la etapa 5e: una
	textura de interfaz NO TIENE PROFUNDIDAD, asi que se dibuja encima de la
	colina que deberia taparla, y ademas nada con la camara porque la camara que
	publica el DLL nunca es la del frame que se esta dibujando.

	La ventana se lee mejor y no miente. Si alguna vez hay una forma de dibujar
	de verdad en el mundo, esto es un candidato -- pero entonces sera con el
	mecanismo bueno y no con el que ya perdio una vez.

	=== NO HACE FALTA ESTAR AL LADO, Y ESO NO ES UN TRUCO ===================

	El servidor acepta y entrega sin comprobar distancia porque **las funciones
	de mision del nucleo no comprueban distancia**: la unica puerta esta en los
	manejadores de opcode, y esos son una defensa contra un cliente que miente
	sobre donde esta. mod-playerbots ya lo explota igual desde siempre. El porque
	entero esta en `RtsQuests.h`.

	=== POR QUE ABRE CON EL CLICK IZQUIERDO ================================

	El derecho ya significa "ve y habla con el", que abre el dialogo de verdad
	del cliente. El izquierdo sobre algo que no es tuyo no hacia NADA desde que
	se borro la fila de enemigos, asi que estaba libre.

	Y no hace falta preguntar antes si el bicho tiene misiones: se pide la lista
	y el servidor contesta `NPCQEND <guid> 0` si no tiene. Un lobo cuesta un
	paquete de ida y otro de vuelta, y a cambio no hay que mantener una segunda
	clasificacion en el cliente que podria discrepar de la del servidor.
]]

local ADDON, ns = ...

local Q = {}
ns.Quests = Q

--- Medidas, en unidades de DIBUJO ------------------------------------------

local ROW    = 62      -- alto de una fila de mision
local DOT    = 20      -- diametro de un punto de estado
local BTN_W  = 150
local BTN_H  = 42
local PAD    = 10
local NAMEW  = 620     -- lo que se reserva para el titulo

-- Estados, tal cual los manda `RtsQuests.h`. Los colores se leen de reojo, que
-- es lo unico que hace util una fila de puntos.
local ST = {
	[0] = { c = { 0.35, 0.35, 0.38 }, tip = "no le vale (nivel, clase, cadena o registro lleno)" },
	[1] = { c = { 1.00, 0.82, 0.00 }, tip = "puede cogerla" },
	[2] = { c = { 0.85, 0.85, 0.90 }, tip = "la lleva, sin terminar" },
	[3] = { c = { 0.10, 1.00, 0.25 }, tip = "lista para entregar" },
	[4] = { c = { 0.20, 0.40, 0.25 }, tip = "ya la hizo" },
}

local F_CHOICE, F_GIVES, F_TAKES = 1, 2, 4

--- Estado ------------------------------------------------------------------

local win, sheet
local npcGuid, npcName          -- a quien estamos mirando
local staging, offers = nil, {}
local rows = {}
local chosen = {}               -- questId -> indice de recompensa elegido

--- Utilidades --------------------------------------------------------------

local function HexOf(guid)
	return (tostring(guid or ""):gsub("^0[xX]", ""))
end

local function Members(o, wanted)
	local out = {}
	for _, m in ipairs(o.members or {}) do
		if m.status == wanted then table.insert(out, m.name) end
	end
	return out
end

--- El canal ----------------------------------------------------------------

function Q:Ask(guid, name)
	local hex = HexOf(guid)
	if hex == "" or hex == "0" then return end

	if not ns.Link:HasServer() then return end

	npcGuid, npcName = hex, name
	staging = { list = {}, byId = {} }
	ns.SendServer("NPCQ " .. hex)
end

local function Stage(hex)
	if hex ~= npcGuid then return nil end
	staging = staging or { list = {}, byId = {} }
	return staging
end

--- Dibujo ------------------------------------------------------------------

local function NewRow(index)
	local r = rows[index]
	if r then return r end

	r = CreateFrame("Frame", "RTSQuestRow" .. index, sheet)
	r:SetHeight(ROW)

	r.title = ns.W:Text(r, ns.W.FONT.normal)
	r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -4)
	r.title:SetWidth(NAMEW)
	r.title:SetJustifyH("LEFT")

	r.dots = {}
	r.rewards = {}

	r.accept = CreateFrame("Button", nil, r)
	r.accept:SetWidth(BTN_W)
	r.accept:SetHeight(BTN_H)
	if ns.Skin then ns.Skin:Dress(r.accept, true) end
	r.accept.label = ns.W:Text(r.accept, ns.W.FONT.small)
	r.accept.label:SetPoint("CENTER", r.accept, "CENTER", 0, 0)

	r.turn = CreateFrame("Button", nil, r)
	r.turn:SetWidth(BTN_W)
	r.turn:SetHeight(BTN_H)
	if ns.Skin then ns.Skin:Dress(r.turn, true) end
	r.turn.label = ns.W:Text(r.turn, ns.W.FONT.small)
	r.turn.label:SetPoint("CENTER", r.turn, "CENTER", 0, 0)

	rows[index] = r
	return r
end

local function PaintDots(r, o)
	local n = 0
	for i, m in ipairs(o.members or {}) do
		n = i
		local d = r.dots[i]
		if not d then
			d = CreateFrame("Button", nil, r)
			d:SetWidth(DOT)
			d:SetHeight(DOT)
			d.tex = d:CreateTexture(nil, "ARTWORK")
			d.tex:SetAllPoints()
			d.label = ns.W:Text(d, ns.W.FONT.tiny)
			d.label:SetPoint("LEFT", d, "RIGHT", 4, 0)
			r.dots[i] = d
		end

		local s = ST[m.status] or ST[0]
		d.tex:SetTexture(s.c[1], s.c[2], s.c[3], 1)
		d.label:SetText(m.name)
		d.label:SetTextColor(s.c[1], s.c[2], s.c[3])
		ns.W:Tip(d, m.name, s.tip)
		d:SetPoint("TOPLEFT", r, "TOPLEFT", (i - 1) * 150, -30)
		d:Show()
	end
	for i = n + 1, #r.dots do r.dots[i]:Hide() end
end

-- Las recompensas a elegir. Se dibujan SOLO cuando alguien puede entregar: una
-- fila de iconos para elegir en una mision que nadie tiene lista es ruido, y
-- ademas invita a elegir algo que no va a usarse.
local function PaintRewards(r, o, ready)
	local n = 0
	if ns.W:Flag(o.flags, F_CHOICE) and #ready > 0 then
		for i, itemId in ipairs(o.choices or {}) do
			n = i
			local b = r.rewards[i]
			if not b then
				b = ns.W:Button(r, 40)
				r.rewards[i] = b
			end
			local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
			if texture then
				b.icon:SetTexture(texture)
			else
				b.icon:SetTexture(0.4, 0.4, 0.45, 1)
				-- Misma trampa que en las bolsas: `GetItemInfo` devuelve nil sin
				-- error para un objeto que el cliente no conoce. Se pide y se
				-- vuelve a dibujar en el siguiente refresco.
				GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			end
			b.questId, b.index = o.questId, i - 1
			b:SetPoint("TOPLEFT", r, "TOPLEFT", NAMEW + 10 + (i - 1) * 46, -4)
			b:SetScript("OnClick", function(self)
				chosen[self.questId] = self.index
				Q:Layout()
			end)
			ns.W:Tip(b, GetItemInfo(itemId) or ("objeto " .. itemId),
			         chosen[o.questId] == (i - 1) and "ELEGIDA" or "click para elegir esta")
			b:SetAlpha(chosen[o.questId] == (i - 1) and 1 or 0.45)
			b:Show()
		end
	end
	for i = n + 1, #r.rewards do r.rewards[i]:Hide() end
	return n
end

function Q:Layout()
	if not win or not win:IsOpen() then return end

	win:SetTitle("Misiones de " .. (npcName or "?"))

	local y = 0
	for i, o in ipairs(offers) do
		local r = NewRow(i)
		r:SetPoint("TOPLEFT", sheet, "TOPLEFT", 0, -y)
		r:SetWidth(NAMEW + 420)
		r:Show()

		local can   = Members(o, 1)
		local ready = Members(o, 3)

		r.title:SetText(("|cffffd100[%d]|r %s"):format(o.level or 0, o.title or "?"))

		PaintDots(r, o)
		local nrew = PaintRewards(r, o, ready)

		-- ACEPTAR
		if ns.W:Flag(o.flags, F_GIVES) and #can > 0 then
			r.accept:Show()
			r.accept.label:SetText(("Aceptar (%d)"):format(#can))
			r.accept:SetPoint("TOPRIGHT", r, "TOPRIGHT", -BTN_W - 8, -8)
			r.accept.questId, r.accept.names = o.questId, table.concat(can, ";")
			r.accept:SetScript("OnClick", function(self)
				ns.SendServer(("QACCEPT %s %d %s"):format(npcGuid, self.questId, self.names))
			end)
			ns.W:Tip(r.accept, "Aceptar para " .. #can,
			         "No hace falta estar al lado: " .. table.concat(can, ", "))
		else
			r.accept:Hide()
		end

		-- ENTREGAR
		if ns.W:Flag(o.flags, F_TAKES) and #ready > 0 then
			local needsPick = ns.W:Flag(o.flags, F_CHOICE)
			                  and chosen[o.questId] == nil and nrew > 0
			r.turn:Show()
			r.turn.label:SetText(needsPick and "Elige premio" or ("Entregar (%d)"):format(#ready))
			r.turn:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -8)
			r.turn.questId, r.turn.names = o.questId, table.concat(ready, ";")
			r.turn.locked = needsPick
			r.turn:SetScript("OnClick", function(self)
				if self.locked then
					ns.Print("|cffff8800misiones:|r esa deja elegir recompensa; pincha una primero.")
					return
				end
				ns.SendServer(("QTURN %s %d %d %s"):format(
					npcGuid, self.questId, chosen[self.questId] or 0, self.names))
			end)
			r.turn:SetAlpha(needsPick and 0.6 or 1)
			ns.W:Tip(r.turn, needsPick and "Falta elegir recompensa" or ("Entregar para " .. #ready),
			         table.concat(ready, ", "))
		else
			r.turn:Hide()
		end

		y = y + ROW + PAD
	end

	for i = #offers + 1, #rows do rows[i]:Hide() end

	local w = PAD * 2 + NAMEW + 420
	local h = 46 + PAD + math.max(ROW, y) + PAD
	local maxH = (ns.HUD and ns.HUD.pixels or 1440) * 0.7
	if h > maxH then h = maxH end
	win:SetSize(w, h)

	sheet:SetWidth(w - PAD * 2)
	sheet:SetHeight(math.max(ROW, y))
end

--- Seguir al heroe automaticamente -----------------------------------------
--
-- `PRUEBAS-20` B: *"al coger una mision con el heroe, si el resto del grupo
-- puede cogerla / devolverla, ya deberia hacerlo de forma automatica, sin
-- entrar en el nuevo panel"*.
--
-- Es lo que convierte esto en una comodidad de verdad: juegas como siempre,
-- hablas con el PNJ como siempre, y el grupo va detras. La ventana pasa a ser
-- para MIRAR y para los casos raros, no el camino normal.
--
-- === LAS DOS MITADES NO SE HACEN IGUAL, Y NO POR CAPRICHO =================
--
-- ACEPTAR es reversible y no gasta nada, asi que se hace en el acto y para
-- todos: `QUEST_ACCEPTED` da el indice del registro, de ahi sale el id, y el
-- servidor ya se encarga de saltarse a quien no pueda.
--
-- ENTREGAR sí gasta: da objetos que no se devuelven. Asi que NO se dispara al
-- entregar tu (no hay evento fiable con el id en 3.3.5a de todas formas), sino
-- al CERRAR la conversacion: se le pregunta al PNJ que tiene, y se entrega solo
-- lo que este listo. Con eleccion de recompensa se manda `AUTO_REWARD` y el
-- servidor elige por cada uno segun su clase -- que es la otra mitad de lo que
-- se pidio, y lo que hace que estas tampoco haya que hacerlas a mano.
--
-- === EL ID DE UNA MISION EN 3.3.5a NO ES UNA LLAMADA =====================
--
-- No hay `GetQuestID()` en este cliente. Lo unico que lo lleva es el ENLACE del
-- registro: `GetQuestLink(i)` devuelve "|Hquest:1234:5|h[Titulo]|h". Se saca de
-- ahi. Si algun dia devuelve nil -- porque el registro aun no se ha
-- actualizado cuando llega el evento -- no se manda nada, que es mejor que
-- mandar un id inventado.
local AUTO_REWARD = 255

local follow = CreateFrame("Frame", "RTSQuestsFollow")

local function QuestIdFromLog(index)
	if not index or index <= 0 then return nil end
	local link = GetQuestLink(index)
	if not link then return nil end
	return tonumber(link:match("quest:(%d+)"))
end

-- Todos menos tu: tu ya la has cogido o entregado por la ventana de siempre.
local function Others()
	local out = {}
	for _, u in ipairs(ns.Selection:GetRoster()) do
		table.insert(out, u.name)
	end
	return out
end

function Q:Auto(on)
	if on ~= nil then
		RTSCommandDB.questAuto = on and true or false
	end
	if RTSCommandDB.questAuto == nil then RTSCommandDB.questAuto = true end
	return RTSCommandDB.questAuto
end

function Q:WireFollow()
	follow:RegisterEvent("QUEST_ACCEPTED")
	follow:RegisterEvent("QUEST_FINISHED")
	follow:SetScript("OnEvent", function(_, event, arg1)
		if not Q:Auto() or not ns.Link:HasServer() then return end

		if event == "QUEST_ACCEPTED" then
			-- El PNJ tiene que ser el que tienes delante AHORA. `"npc"` es una
			-- unidad valida mientras la conversacion esta abierta; cuando se
			-- cierra deja de serlo, y por eso esto se lee aqui y no despues.
			local npc = UnitGUID("npc") or UnitGUID("target")
			local id = QuestIdFromLog(arg1)
			local names = Others()
			if not npc or not id or #names == 0 then return end
			ns.SendServer(("QACCEPT %s %d %s"):format(HexOf(npc), id, table.concat(names, ";")))
			return
		end

		-- QUEST_FINISHED: se acabo la conversacion. Se pregunta que hay y el
		-- manejador de `NPCQEND` entrega lo que este listo.
		local npc = UnitGUID("npc") or UnitGUID("target")
		if not npc then return end
		Q.autoTurnFor = HexOf(npc)
		Q:Create()
		Q:Ask(npc, UnitName("npc") or UnitName("target"))
	end)
end

-- Entregar lo que este listo, sin abrir nada. Se llama desde `NPCQEND` cuando
-- la consulta venia de `QUEST_FINISHED`.
function Q:AutoTurnIn()
	local sent = 0
	for _, o in ipairs(offers) do
		if ns.W:Flag(o.flags, F_TAKES) then
			local ready = Members(o, 3)
			if #ready > 0 then
				ns.SendServer(("QTURN %s %d %d %s"):format(
					npcGuid, o.questId, AUTO_REWARD, table.concat(ready, ";")))
				sent = sent + 1
			end
		end
	end
	if sent > 0 then
		ns.Print(("|cff33ccffmisiones:|r entregando %d por el grupo."):format(sent))
	end
end

--- Ciclo -------------------------------------------------------------------

function Q:Create()
	if win then return end

	win = ns.Window:New("RTSQuests", "Misiones", 1100, 400)
	sheet = CreateFrame("Frame", "RTSQuestsSheet", win:Body())
	sheet:SetPoint("TOPLEFT", win:Body(), "TOPLEFT", PAD, 0)
	sheet:SetWidth(1)
	sheet:SetHeight(1)

	self:WireFollow()

	ns.Link:On("NPCQ", function(rest)
		-- DOS SENTIDOS: mandamos "NPCQ <hex>" y nos lo oimos de vuelta. La
		-- respuesta se distingue porque trae una LETRA de tipo detras del guid.
		local hex, kind, payload = rest:match("^(%x+)%s+([QS])%s+(.+)$")
		if not hex then return end

		local st = Stage(hex)
		if not st then return end

		if kind == "Q" then
			-- EL TITULO ES EL RESTO DE LA LINEA, y por eso todos los campos
			-- nuevos van delante: un titulo lleva espacios y comas, y cualquier
			-- separador que se le ponga detras acaba apareciendo dentro de un
			-- titulo algun dia.
			local id, flags, level, choices, title =
				payload:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(.+)$")
			if not id then return end

			id = tonumber(id)
			local o = st.byId[id]
			if not o then
				o = { questId = id, members = {}, choices = {} }
				st.byId[id] = o
				table.insert(st.list, o)
			end
			o.flags, o.level, o.title = tonumber(flags), tonumber(level), title
			o.choices = {}
			if choices ~= "-" then
				for n in choices:gmatch("%d+") do table.insert(o.choices, tonumber(n)) end
			end

		else -- "S"
			local id, list = payload:match("^(%d+)%s+(.+)$")
			if not id then return end
			id = tonumber(id)
			local o = st.byId[id]
			if not o then
				o = { questId = id, members = {}, choices = {} }
				st.byId[id] = o
				table.insert(st.list, o)
			end
			o.members = {}
			for name, s in list:gmatch("([^,:]+):(%d+)") do
				table.insert(o.members, { name = name, status = tonumber(s) })
			end
		end
	end)

	ns.Link:On("NPCQEND", function(rest)
		local hex, count = rest:match("^(%x+)%s+(%d+)$")
		if not hex or hex ~= npcGuid then return end

		offers = (staging and staging.list) or {}
		staging = nil

		-- ¿Esta consulta venia de cerrar una conversacion? Entonces se entrega y
		-- NO se abre la ventana: el jugador acaba de cerrar una, y abrirle otra
		-- encima seria justo lo contrario de lo que pidio.
		if Q.autoTurnFor == hex then
			Q.autoTurnFor = nil
			Q:AutoTurnIn()
			return
		end

		if tonumber(count) == 0 then
			-- Sin misiones no se abre nada, y tampoco se dice nada: pinchar un
			-- lobo no deberia escribir una linea en el chat.
			if win:IsOpen() and #offers == 0 then win:Close() end
			return
		end

		win:Open()
		Q:Layout()
	end)

	ns.Link:On("QDONE", function(rest)
		local kind, id, ok, bad = rest:match("^([AT])%s+(%d+)%s+(%d+)%s+(%d+)$")
		if not kind then return end
		local verb = (kind == "A") and "aceptada" or "entregada"
		ns.Print(("|cff33ccffmisiones:|r %s por %s%s"):format(
			verb, ok, tonumber(bad) > 0 and (", " .. bad .. " no pudieron") or ""))
		chosen[tonumber(id)] = nil
	end)

	ns.Link:On("QERR", function(rest)
		local id, why = rest:match("^(%d+)%s+(.+)$")
		if not id then return end
		ns.Print("|cffff8800misiones:|r " .. why)
	end)
end

-- Se llama desde `RTSMode:OnLeftClick` cuando pinchas algo que no es tuyo.
function Q:Poke(guid, name)
	self:Create()
	self:Ask(guid, name)
end
