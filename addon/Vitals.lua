--[[
	Vitals.lua -- las barras del heroe, bajo el retrato 3D.

	Cuatro renglones en el hueco `vitals` de la barra:

	  vida      nombre y nivel a la izquierda, cuanta queda a la derecha
	  poder     mana, ira, energia, concentracion o poder runico, con su color
	  recurso   los puntos de combate del picaro/druida o las runas del DK
	  exp       una raya fina, que es lo que se pidio: enterarse sin mirar

	EL HUECO DEL RECURSO DE CLASE SE RESERVA SIEMPRE, tenga la clase recurso o
	no. Es la peticion literal ("keep some space for that") y ademas es lo unico
	que hace que la barra no cambie de forma al cambiar de personaje: si el
	renglon apareciera solo para el picaro, el mago tendria la experiencia doce
	pixeles mas arriba y la barra parecerria mal alineada.

	EN WOTLK SOLO HAY DOS RECURSOS DE ESTOS, y conviene decirlo para no buscar
	los demas: puntos de combate (picaro, druida en forma) y runas (caballero de
	la muerte). El poder sagrado del paladin, la concentracion del cazador como
	barra propia, los fragmentos del brujo como pips -- todo eso es de Cataclysm
	o posterior. La lista de aqui esta completa para 3.3.5a.

	NO SE FIA DE LA FIRMA DE `GetComboPoints`. En 3.3.5a la documentacion de
	fuera dice `GetComboPoints()` sin argumentos y este cliente la quiere con
	`("player", "target")`; llamarla mal no da error, devuelve nil y los puntos
	no aparecen nunca. Se prueban las dos y se queda la que contesta un numero.
	Misma leccion que `nameplateMaxDistance` y `gxWindowedResolution`.

	POLLING, NO EVENTOS. Cubrir vida y poder con eventos son ocho registros
	(UNIT_HEALTH, UNIT_MANA, UNIT_RAGE, UNIT_ENERGY, UNIT_RUNIC_POWER,
	UNIT_MAXMANA, UNIT_DISPLAYPOWER, PLAYER_XP_UPDATE...) y aun asi hay que
	repasarlo al entrar. Cinco veces por segundo desde el latido compartido de
	Widgets cuesta menos que mantener esa lista al dia.
]]

local ADDON, ns = ...

local V = {}
ns.Vitals = V

V.active = false

-- El reparto vertical del hueco. `xp` y `extra` son fijos porque son finos por
-- diseno; vida y poder se llevan lo que sobre, 60/40.
local XP_H  = 5
local EX_H  = 12
local ROW_G = 4

local host, built
local health, power, xp
local pips = {}
local mark = {}

--- Recursos de clase ------------------------------------------------------

local RUNE_COLOR = {
	[1] = { r = 0.85, g = 0.15, b = 0.15 },   -- sangre
	[2] = { r = 0.35, g = 0.75, b = 0.30 },   -- profana
	[3] = { r = 0.25, g = 0.60, b = 0.95 },   -- escarcha
	[4] = { r = 0.70, g = 0.35, b = 0.90 },   -- muerte
}

local COMBO_COLOR = { r = 1.00, g = 0.85, b = 0.20 }

-- Cual de las dos firmas entiende ESTE cliente. Se resuelve una vez y se
-- recuerda, para no pagar dos pcall cinco veces por segundo.
local comboForm

local function ComboPoints()
	if not GetComboPoints then return 0 end

	if comboForm == nil then
		local ok, n = pcall(GetComboPoints, "player", "target")
		if ok and type(n) == "number" then
			comboForm = 2
		else
			ok, n = pcall(GetComboPoints)
			comboForm = (ok and type(n) == "number") and 1 or false
		end
	end

	if comboForm == 2 then
		local ok, n = pcall(GetComboPoints, "player", "target")
		return (ok and n) or 0
	elseif comboForm == 1 then
		local ok, n = pcall(GetComboPoints)
		return (ok and n) or 0
	end
	return 0
end

-- Que recurso lleva esta clase, cuantas casillas y de que color cada una.
-- Devuelve nil si la clase no tiene ninguno, y entonces el renglon se queda
-- vacio pero el sitio sigue reservado.
local function Resource()
	local _, class = UnitClass("player")

	if class == "DEATHKNIGHT" and GetRuneType and GetRuneCount then
		local list = {}
		for i = 1, 6 do
			local tipo = GetRuneType(i)
			-- GetRuneCount devuelve 1 cuando la runa esta lista.
			local lista = (GetRuneCount(i) or 0) > 0
			list[i] = { on = lista, color = RUNE_COLOR[tipo or 1] }
		end
		return list
	end

	if class == "ROGUE" or class == "DRUID" then
		local n = ComboPoints()
		-- El druida solo los tiene en forma de gato/oso, y fuera de forma
		-- devuelve 0: cinco casillas apagadas dicen eso mejor que ninguna.
		local list = {}
		for i = 1, 5 do
			list[i] = { on = i <= n, color = COMBO_COLOR }
		end
		return list
	end

	return nil
end

--- Construccion -----------------------------------------------------------

local function Build()
	if built then return end
	built = true

	health = ns.W:Bar(host, true)
	power  = ns.W:Bar(host, true)
	xp     = ns.W:Bar(host, false)

	-- La experiencia va en dorado sobre negro. Es la unica barra sin texto: en
	-- cinco pixeles de dibujo no cabe, y el tooltip del raton no llega aqui.
	xp:SetStatusBarColor(0.85, 0.70, 0.15)

	for i = 1, 6 do
		local p = ns.W:Bar(host, false)
		p:SetValue(1)
		pips[i] = p
	end

	-- El marco de "el heroe esta seleccionado". Tu personaje es una unidad como
	-- las demas en modo RTS, asi que necesita el mismo aviso que las filas del
	-- grupo -- y con el mismo dibujo, cuatro rayas, para que se lea igual.
	for e = 1, 4 do
		mark[e] = health:CreateTexture(nil, "OVERLAY")
		mark[e]:SetTexture(1, 0.95, 0.5, 0.9)
	end
end

local function MarkBox(on)
	if not on then
		for e = 1, 4 do mark[e]:Hide() end
		return
	end
	local w, h = health:GetWidth(), health:GetHeight()
	local spec = {
		{ w, 1, 0, 0 }, { w, 1, 0, h - 1 },
		{ 1, h, 0, 0 }, { 1, h, w - 1, 0 },
	}
	for e = 1, 4 do
		local d = spec[e]
		mark[e]:SetWidth(d[1])
		mark[e]:SetHeight(d[2])
		mark[e]:ClearAllPoints()
		mark[e]:SetPoint("TOPLEFT", health, "TOPLEFT", d[3], -d[4])
		mark[e]:Show()
	end
end

function V:Layout()
	if not host then return end
	Build()

	local w, h = host:GetWidth(), host:GetHeight()
	if not w or w < 8 or not h or h < 8 then return end

	-- Lo que sobra despues de los dos renglones finos, repartido 60/40.
	local resto = h - XP_H - EX_H - ROW_G * 3
	if resto < 8 then resto = 8 end
	local hh = math.floor(resto * 0.6 + 0.5)
	local ph = resto - hh

	local y = 0
	local function Row(f, alto)
		f:ClearAllPoints()
		f:SetWidth(w)
		f:SetHeight(alto)
		f:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -y)
		y = y + alto + ROW_G
	end

	Row(health, hh)
	Row(power, ph)

	-- Las casillas del recurso: seis como maximo (las runas del DK), y las que
	-- no se usen se esconden. El ancho sale de cuantas haya, no de una constante,
	-- para que cinco puntos de combate llenen el renglon igual que seis runas.
	local list = Resource()
	local n = list and #list or 0
	local exY = y
	if n > 0 then
		local gap = 4
		local pw = math.floor((w - gap * (n - 1)) / n)
		for i = 1, 6 do
			local p = pips[i]
			if i <= n then
				p:ClearAllPoints()
				p:SetWidth(pw)
				p:SetHeight(EX_H)
				p:SetPoint("TOPLEFT", host, "TOPLEFT", (i - 1) * (pw + gap), -exY)
				p:Show()
			else
				p:Hide()
			end
		end
	else
		for i = 1, 6 do pips[i]:Hide() end
	end
	y = y + EX_H + ROW_G

	Row(xp, XP_H)
end

--- Refresco ---------------------------------------------------------------

function V:Refresh()
	if not self.active or not built then return end

	local unit = "player"
	local name = UnitName(unit) or "?"
	local level = UnitLevel(unit) or 0

	-- Vida. El color es el de la clase, igual que en las barras del grupo: en
	-- una pantalla donde todo lo vivo lleva color de clase, una barra verde
	-- suelta se lee como "otra cosa".
	ns.W:Fill(health, UnitHealth(unit), UnitHealthMax(unit))
	ns.W:Color(health, ns.W:ClassColor(unit))
	health.text:SetText(("%s |cffaaaaaa%d|r"):format(name, level))
	if UnitIsDeadOrGhost(unit) then
		health.right:SetText("|cffff4444muerto|r")
	else
		health.right:SetText(ns.W:Short(UnitHealth(unit)))
	end

	-- Poder. Un guerrero fuera de combate tiene 0 de ira y eso es correcto, no
	-- un fallo: la barra vacia es informacion.
	local pmax = UnitManaMax(unit) or 0
	ns.W:Fill(power, UnitMana(unit) or 0, pmax)
	ns.W:Color(power, ns.W:PowerColor(unit))
	power.text:SetText("")
	power.right:SetText(pmax > 0 and ns.W:Short(UnitMana(unit) or 0) or "")

	-- Recurso de clase. Se vuelve a preguntar cada vez porque las runas cambian
	-- de tipo en juego (la de muerte) y los puntos de combate cambian siempre.
	local list = Resource()
	if list then
		local n = #list
		-- Si ha cambiado el NUMERO de casillas hay que recolocarlas, no solo
		-- repintarlas: cinco puntos de combate y seis runas no ocupan lo mismo.
		-- Se compara contra lo ultimo colocado, no contra la clase, porque un
		-- druida que entra en forma pasa de cero casillas a cinco.
		if self.pipCount ~= n then
			self.pipCount = n
			self:Layout()
		end
		for i = 1, 6 do
			local p, rec = pips[i], list[i]
			if rec then
				ns.W:Color(p, rec.color)
				p:SetAlpha(rec.on and 1 or 0.25)
			end
		end
	elseif self.pipCount ~= 0 then
		-- Se quedo sin recurso (el druida saliendo de forma). Las casillas se
		-- van, el hueco se queda.
		self.pipCount = 0
		for i = 1, 6 do pips[i]:Hide() end
	end

	-- Experiencia. A nivel maximo `UnitXPMax` es 0: la raya se apaga en vez de
	-- esconderse, para que el hueco siga siendo el mismo.
	local xmax = UnitXPMax(unit) or 0
	if xmax > 0 then
		ns.W:Fill(xp, UnitXP(unit) or 0, xmax)
		xp:SetAlpha(1)
	else
		xp:SetValue(0)
		xp:SetAlpha(0.3)
	end

	MarkBox(ns.Selection:IsSelected(name))
end

--- Entrar y salir ---------------------------------------------------------

function V:Enter()
	host = ns.Bar:SlotFrame("vitals")
	if not host then return end
	self.active = true
	Build()
	self:Layout()
	self:Refresh()
	host:Show()

	if not self.wired then
		self.wired = true
		ns.Bar:OnLayout(function() V:Layout() end)
		ns.W:Every(function() V:Refresh() end)
	end
end

function V:Leave()
	self.active = false
	if host then host:Hide() end
end
