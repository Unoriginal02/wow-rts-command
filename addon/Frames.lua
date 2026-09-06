--[[
	Frames.lua -- la fila de marcos de arriba, en el estado A.

	Tres marcos, de izquierda a derecha, alineados a la izquierda y con el
	minimo alto posible (§2 y §4.1 del brief):

	    [ retrato | nombre     ]  [ enemigo ]  [ su objetivo ]
	    [         | vida       ]
	    [         | recurso    ]
	    [         | mascota    ]

	  1. EL SELECCIONADO -- estilo marco de jugador: retrato, vida, recurso,
	     mascota si tiene, y los puntos de combo si su clase los usa.
	  2. SU OBJETIVO -- el enemigo, a la derecha.
	  3. EL OBJETIVO DE SU OBJETIVO -- solo si existe.

	=== EL OBJETIVO DE UN BOT SE PUEDE MIRAR, Y NO HACIA FALTA SERVIDOR ======

	`party1target` y `party1targettarget` SON unidades validas en 3.3.5a, igual
	que `targettarget` para las tuyas. Asi que los tres marcos salen de la API
	del cliente y no cuesta ni un mensaje.

	Lo compruebo aqui y no lo supongo: `UnitFor(name)` da el token del personaje
	("player" o "partyN") y los otros dos se construyen pegandole "target". Si
	un dia no existieran, `UnitExists` diria que no y el marco se esconde -- que
	es el comportamiento correcto de todos modos.

	=== LAS RUNAS NO SE PUEDEN ENSENAR, Y ESO HAY QUE DECIRLO ================

	El brief pide "pet, runas... lo que corresponda a esa clase". La mascota si
	(`party1pet` existe). Las runas NO: `GetRuneCooldown(i)` y `GetRuneType(i)`
	de 3.3.5a **no toman unidad** -- son siempre las TUYAS. No hay forma
	client-side de leer las runas de un caballero de la muerte del grupo.

	Dibujar seis rombos con TUS runas bajo el marco de OTRO seria peor que no
	dibujarlas: seria un dato falso con pinta de bueno, que es el modo de fallo
	que este proyecto persigue desde la etapa 5i. Si se quieren de verdad, es un
	verbo de mod-rts (el servidor si las tiene) y se anade el dia que haya un
	caballero de la muerte en el grupo.

	Lo que si se ensena de "lo que corresponda a esa clase" es el PODER con su
	color (ira, energia, concentracion, poder runico salen distintos) y los
	PUNTOS DE COMBO, que son los dos que se leen de un vistazo.

	`GetComboPoints` TIENE DOS FIRMAS y este cliente quiere una: fuera dicen
	`GetComboPoints()`, aqui es `("player", "target")`. Llamarla mal no da
	error, devuelve nil y los puntos no aparecen NUNCA. Se prueban las dos.
]]

local ADDON, ns = ...

local F = {}
ns.Frames = F

F.active = false

-- El reparto de un marco de 128 de alto (`TOP_H` en Hall.lua).
--
-- TODO SUBE EN LA 0.77.0 por `PRUEBAS-23`: *"los player frames muy pequenos"*.
-- El marco medio 84 de dibujo, o sea 47 px de pantalla, para meter retrato,
-- nombre, vida, poder y mascota. El marco de jugador del propio cliente mide
-- 100 px de alto y es la medida que el jugador tiene calibrada en la retina --
-- la misma regla que hizo que el alto de la barra se calcara de `ActionButton1`
-- en la etapa 5i.
local PORT   = 104    -- el retrato, cuadrado
local PAD    = 8
local NAME_H = 28
local HP_H   = 34
local PP_H   = 14
local PET_H  = 10
local GAP    = 3

-- LOS TRES MARCOS BAJAN DE TAMANO SEGUN SE ALEJAN DE TI, que es lo que dibuja
-- el boceto: el circulo del tercero es visiblemente mas pequeno que el del
-- segundo. No es decoracion -- es la jerarquia dicha con el tamano, que se lee
-- de reojo: el tuyo importa, el enemigo importa menos, y a quien pega el
-- enemigo es un dato de apoyo.
-- CUANTO BAJAN LOS MARCOS DENTRO DE SU BANDA. Pedido mirandolos: iban pegados
-- al borde de arriba de la sala, y el marco de un personaje pegado al filo del
-- arte se lee como que se ha salido, no como que empieza ahi.
--
-- No crece `TOP_H` para hacerle sitio: la banda ya tiene 20 de sobra sobre los
-- 120 que mide el marco, asi que el aire estaba puesto y solo estaba en el lado
-- que no era. Crecerla ademas dejaria la fila de macros a 2 del suelo.
local FRAME_TOP = 14

local FRAME_W  = 460  -- el del personaje seleccionado
local SMALL_W  = 380  -- su objetivo
local TOT_W    = 300  -- el objetivo de su objetivo
local FRAME_GAP = 20

local host, marcos = nil, {}

--- Piezas -----------------------------------------------------------------

local function Build(key, w)
	local f = CreateFrame("Button", "RTSFrame_" .. key, host)
	f:SetWidth(w)
	f:SetHeight(PORT + PAD * 2)

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetTexture(0, 0, 0, 0.45)

	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:SetWidth(PORT)
	f.portrait:SetHeight(PORT)
	f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)

	-- El aro del retrato: cuatro rayas, como el marco de seleccion. Una textura
	-- de aro de las del cliente vendria con su propio recorte que nadie aqui ha
	-- verificado (`TexCoord` a ciegas es adivinar; ver Skin.lua).
	f.ring = {}
	for e = 1, 4 do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetTexture(0.5, 0.5, 0.55, 0.9)
		f.ring[e] = t
	end

	local x = PAD + PORT + PAD
	f.name = ns.W:Text(f, ns.W.FONT.normal)
	f.name:SetPoint("TOPLEFT", f, "TOPLEFT", x, -PAD)
	f.name:SetWidth(w - x - PAD)
	f.name:SetHeight(NAME_H)
	f.name:SetJustifyH("LEFT")

	f.health = ns.W:Bar(f, true)
	f.health:SetWidth(w - x - PAD)
	f.health:SetHeight(HP_H)
	f.health:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(PAD + NAME_H + GAP))

	f.power = ns.W:Bar(f, false)
	f.power:SetWidth(w - x - PAD)
	f.power:SetHeight(PP_H)
	f.power:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(PAD + NAME_H + GAP + HP_H + GAP))

	f.pet = ns.W:Bar(f, false)
	f.pet:SetWidth(w - x - PAD)
	f.pet:SetHeight(PET_H)
	f.pet:SetPoint("TOPLEFT", f, "TOPLEFT", x,
		-(PAD + NAME_H + GAP + HP_H + GAP + PP_H + GAP))

	-- Los puntos de combo: cinco rombos que solo salen cuando hay alguno.
	f.combo = {}
	for i = 1, 5 do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetTexture("Interface\\ComboFrame\\ComboPoint")
		t:SetWidth(18)
		t:SetHeight(18)
		t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - (5 - i) * 21, PAD)
		t:Hide()
		f.combo[i] = t
	end

	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:SetScript("OnClick", function(self, button)
		if not self.unit or not UnitExists(self.unit) then return end

		-- Un hechizo armado se come el click, igual que en la lista y en el
		-- mundo. Es la tercera boca del mismo gesto de §5.
		if ns.Skills:Aiming() then
			if button == "RightButton" then
				ns.Skills:AimAt(nil)
			else
				ns.Skills:AimAt(UnitGUID(self.unit), ns.UnitLabel(self.unit),
				                UnitCanAttack("player", self.unit) and true or false)
			end
			return
		end

		if ns.Cast:AimAt(button ~= "RightButton" and UnitGUID(self.unit) or nil,
		                 ns.UnitLabel(self.unit)) then
			return
		end

		-- Solo el marco del personaje selecciona. Pinchar el marco del enemigo
		-- no puede seleccionar al enemigo: la seleccion de esta consola es de
		-- los TUYOS, y meter enemigos en ella rompe todo lo que la lee.
		if self.selects and self.unitName then
			ns.Selection:Click(self.unitName)
		end
	end)

	return f
end

local function Ring(f, w, h, r, g, b)
	local t = 2
	local spec = { { w, t, 0, 0 }, { w, t, 0, h - t },
	               { t, h, 0, 0 }, { t, h, w - t, 0 } }
	for e = 1, 4 do
		local d = spec[e]
		local tex = f.ring[e]
		tex:SetTexture(r, g, b, 0.9)
		tex:SetWidth(d[1])
		tex:SetHeight(d[2])
		tex:ClearAllPoints()
		tex:SetPoint("TOPLEFT", f.portrait, "TOPLEFT", d[3], -d[4])
		tex:Show()
	end
end

--- Los puntos de combo ----------------------------------------------------

-- `GetComboPoints` tiene dos firmas y este cliente quiere una. Se prueba la
-- larga primero (que es la de 3.3.5a) y se recuerda cual contesto. Llamarla mal
-- no da error: devuelve nil, y los puntos no salen nunca.
local comboForm

local function Combo(unit)
	if type(GetComboPoints) ~= "function" then return 0 end
	if comboForm ~= "short" then
		local ok, n = pcall(GetComboPoints, unit, unit .. "target")
		if ok and type(n) == "number" then
			comboForm = "long"
			return n
		end
	end
	local ok, n = pcall(GetComboPoints)
	if ok and type(n) == "number" then
		comboForm = "short"
		return n
	end
	return 0
end

--- Refresco ---------------------------------------------------------------

local function Paint(f, unit, selects, unitName)
	if not unit or not UnitExists(unit) then
		f:Hide()
		return false
	end

	f.unit, f.selects, f.unitName = unit, selects, unitName
	f:Show()

	SetPortraitTexture(f.portrait, unit)

	local c = ns.W:ClassColor(unit)
	-- Un enemigo no tiene color de clase util: `ClassColor` devuelve gris para
	-- una criatura, asi que ahi manda la reaccion.
	if not UnitIsPlayer(unit) then
		if UnitCanAttack("player", unit) then
			c = { r = 0.75, g = 0.2, b = 0.2 }
		else
			c = { r = 0.3, g = 0.65, b = 0.3 }
		end
	end

	local dead = UnitIsDeadOrGhost(unit)
	ns.W:Color(f.health, c)
	ns.W:Fill(f.health, dead and 0 or UnitHealth(unit), UnitHealthMax(unit))
	f.health.text:SetText(dead and "|cffff4444muerto|r" or ns.W:Short(UnitHealth(unit)))
	f.health.right:SetText(("%d%%"):format(
		math.floor(100 * (UnitHealth(unit) / math.max(1, UnitHealthMax(unit))))))

	ns.W:Color(f.power, ns.W:PowerColor(unit))
	ns.W:Fill(f.power, UnitMana(unit) or 0, UnitManaMax(unit) or 0)

	local lvl = UnitLevel(unit) or 0
	-- `ns.UnitLabel` Y NO `UnitName`: para TI el cliente devuelve el nombre con
	-- el que arrancaste la sesion, no con el que estas jugando. Se vio como un
	-- marco que ensenaba el retrato, la vida y los hechizos de Bob con el nombre
	-- de Neferite encima. Ver `Bridge.lua`.
	f.name:SetText(("%s |cffaaaaaa%s|r"):format(ns.UnitLabel(unit) or "?",
		lvl > 0 and tostring(lvl) or ""))
	f.name:SetTextColor(c.r, c.g, c.b)

	-- LA MASCOTA. `party1pet` existe en 3.3.5a; para ti es `pet`. Solo se
	-- dibuja si la hay -- una barra vacia permanente bajo un mago dice
	-- "algo falla" y no "no tiene mascota".
	local petUnit = (unit == "player") and "pet" or (unit .. "pet")
	if UnitExists(petUnit) then
		ns.W:Color(f.pet, { r = 0.55, g = 0.75, b = 0.35 })
		ns.W:Fill(f.pet, UnitHealth(petUnit), UnitHealthMax(petUnit))
		f.pet:Show()
	else
		f.pet:Hide()
	end

	local pts = Combo(unit)
	for i = 1, 5 do
		if i <= pts then f.combo[i]:Show() else f.combo[i]:Hide() end
	end

	local sel = unitName and ns.Selection:IsSelected(unitName)
	if sel then
		Ring(f, PORT, PORT, ns.W.SELECT.r, ns.W.SELECT.g, ns.W.SELECT.b)
	else
		Ring(f, PORT, PORT, 0.4, 0.4, 0.45)
	end

	return true
end

function F:Refresh()
	if not self.active or not host then return end
	if ns.Hall:State() ~= "A" then
		for _, f in pairs(marcos) do f:Hide() end
		return
	end

	-- SIN DUENO, NINGUN MARCO. Pasa con la seleccion vacia desde la 0.80.0:
	-- `Hall` no produce el area y su marco esta escondido, asi que esto es
	-- cinturon y tirantes -- pero un marco escondido sigue recibiendo `Show()`
	-- de `Paint`, y el dia que el area vuelva a existir por otro motivo saldrian
	-- tres marcos de nadie.
	local name = ns.Hall:Subject()
	if not name then
		for _, f in pairs(marcos) do f:Hide() end
		return
	end
	local unit = ns.Selection:UnitFor(name)

	Paint(marcos.self, unit, true, name)
	Paint(marcos.target, unit and (unit .. "target"), false, nil)
	Paint(marcos.totarget, unit and (unit .. "targettarget"), false, nil)
end

--- Distribucion -----------------------------------------------------------

function F:Layout()
	if not host then return end
	local r = ns.Hall:Get("top")
	if not r then
		for _, f in pairs(marcos) do f:Hide() end
		return
	end

	marcos.self     = marcos.self     or Build("self", FRAME_W)
	marcos.target   = marcos.target   or Build("target", SMALL_W)
	marcos.totarget = marcos.totarget or Build("totarget", TOT_W)

	-- PEGADOS A LA IZQUIERDA, y esa es la vuelta atras de la 0.78.0.
	--
	-- La 0.77.0 los centro porque el bloque de abajo tampoco llenaba y quedaba
	-- todo a un lado. Ahora la fila de hechizos llena el ancho, asi que el borde
	-- izquierdo de la zona es la referencia: marcos, raya, hechizos y macros
	-- empiezan todos en la misma x. Es la columna de bordes alineados lo que
	-- hace que la zona se lea como un bloque, y centrar la rompia -- ademas de
	-- forma VARIABLE, porque el ancho total dependia de si el bot tenia
	-- objetivo.
	--
	-- Si no caben los tres se dibujan los que quepan: `Paint` esconde lo que no
	-- exista y esto esconde lo que no entre, que son dos motivos distintos para
	-- la misma cosa.
	local x = 0
	for _, key in ipairs({ "self", "target", "totarget" }) do
		local f = marcos[key]
		local w = f:GetWidth()
		if x + w <= r.w then
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", host, "TOPLEFT", x, -FRAME_TOP)
			f.fits = true
			x = x + w + FRAME_GAP
		else
			f.fits = false
			f:Hide()
		end
	end

	self:Refresh()
end

--- Entrar y salir ---------------------------------------------------------

function F:Enter()
	host = ns.Hall:Host("top")
	if not host then return end
	self.active = true
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Hall:OnLayout(function() F:Layout() end)
		ns.W:Every(function() F:Refresh() end)
		ns.Selection:Subscribe(function() F:Refresh() end)
	end

	self:Layout()
end

function F:Leave()
	self.active = false
	for _, f in pairs(marcos) do f:Hide() end
	if host then host:Hide() end
end

ns.Hall:Register(F)
