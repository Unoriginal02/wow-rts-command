--[[
	Portraits.lua -- los marcos de unidad DEL JUEGO, enganchados a la seleccion.

	Desde el rediseno del 2026-09-13 el addon ya no dibuja marcos propios: el
	tuyo, el del objetivo y los cuatro del grupo son los de Blizzard, a la vista.
	Con eso se fue la columna de cinco de la consola, que era donde se pinchaba
	para elegir a quien mandar. Este fichero devuelve ese gesto al sitio donde el
	jugador ya esta mirando.

	    click izquierdo en un marco del grupo  ->  seleccionarlo
	    shift (o control)                      ->  anadir o quitar
	    doble click                            ->  todos
	    click derecho                          ->  el menu de Blizzard, intacto

	Son exactamente las reglas de `Selection:Click`, que es quien las aplica: no
	hay una segunda copia del gesto aqui.

	=== POR QUE `PostClick` Y NO `OnClick` -- ESTO ES LO IMPORTANTE ==========

	Los marcos de unidad son BOTONES SEGUROS: su click lo atiende
	`SecureActionButton_OnClick`, que llama a `TargetUnit`, que esta protegida.

	Y el modelo de contaminacion de WoW no perdona un gancho ahi.
	`HookScript("OnClick", ...)` SUSTITUYE el script por un cierre NUESTRO que
	llama al original por dentro. El original sigue corriendo -- pero ya dentro
	de una ejecucion contaminada por el addon, y la contaminacion no se limpia al
	entrar en una funcion de Blizzard. Resultado: el `TargetUnit` de dentro se
	bloquea EN COMBATE con el clasico *"blocked from an action only available to
	the Blizzard UI"*, y el sintoma es que en cuanto empieza la pelea los marcos
	del grupo dejan de cambiar el objetivo. Un fallo que solo aparece peleando y
	que no se parece a "he enganchado un click".

	`PreClick` y `PostClick` son OTROS scripts, y existen precisamente para esto:
	el despachador del cliente llama `PreClick`, luego `OnClick` -- el de
	Blizzard, sin tocar y sin contaminar -- y luego `PostClick`. Colgarse de
	`PostClick` deja el camino seguro exactamente como estaba.

	La consecuencia, dicha por delante: el click TAMBIEN cambia tu objetivo,
	porque eso es lo que hace el marco y no se le quita. La fila de la consola
	vieja si se comia el click; esta no puede y tampoco deberia.

	=== LA MARCA DE SELECCION NO TOCA EL MARCO ==============================

	Un brillo sobre el RETRATO, dibujado en un frame NUESTRO anclado al suyo. No
	se le mete nada dentro al marco de Blizzard ni se le cambia una textura:
	anclar un frame propio a uno protegido es legal y se puede ensenar y esconder
	en combate, que es justo cuando hace falta.

	EMPEZO SIENDO UN RECUADRO AMARILLO Y DURO UN DIA: *"canta como una almeja"*.
	Y tenia razon por una razon que se puede escribir -- un borde de color pleno
	compite con el arte del marco, que ya es dorado, y la pantalla acaba con
	cinco rectangulos gritando lo mismo. El brillo se lee igual de rapido (es lo
	que el propio cliente usa para "esto esta puesto") y no discute con nada.

	LA TEXTURA ES DEL CLIENTE: `ButtonHilight-Square` en modo ADD, que es la
	misma que llevan de resalte los botones de accion. En ADD no tapa el retrato
	-- lo ILUMINA -- asi que la cara del bot se sigue viendo debajo, y eso importa
	porque el retrato es lo que se mira para saber quien es.

	SE ANCLA AL RETRATO SI LO ENCUENTRA, y si no, al marco entero. El retrato es
	`PlayerPortrait` para el tuyo y `PartyMemberFrame1Portrait` para los del
	grupo -- dos reglas de nombre distintas, que es como se escribe un fallo
	silencioso. Asi que se busca, y `/rts marcos` dice de que se colgo cada uno
	en vez de dejar una marca invisible sin explicacion.
]]

local ADDON, ns = ...

local P = {}
ns.Portraits = P

P.active = false

-- El marco de cada unidad, y el nombre del retrato de dentro cuando existe.
local FRAMES = {
	{ unit = "player", frame = "PlayerFrame",        portrait = "PlayerPortrait" },
	{ unit = "party1", frame = "PartyMemberFrame1",  portrait = "PartyMemberFrame1Portrait" },
	{ unit = "party2", frame = "PartyMemberFrame2",  portrait = "PartyMemberFrame2Portrait" },
	{ unit = "party3", frame = "PartyMemberFrame3",  portrait = "PartyMemberFrame3Portrait" },
	{ unit = "party4", frame = "PartyMemberFrame4",  portrait = "PartyMemberFrame4Portrait" },
}

local marks = {}          -- unit -> { frame = , edges = , anchored = "retrato"|"marco" }
local hooked = false

-- El brillo se sale un poco del retrato a proposito: pegado al borde se lee
-- como parte del marco, y lo que tiene que decir es "este, y no los otros".
local PAD  = 4
local GLOW = "Interface\\Buttons\\ButtonHilight-Square"

--- El nombre del personaje de una unidad, SOLO si esta en el grupo ---------
--
-- Se resuelve contra el censo y no con `UnitName` a secas: en el grupo puede
-- haber un jugador de verdad, y seleccionar a alguien a quien no se le puede
-- mandar nada seria un boton que miente. Si no esta, el click no hace nada mas
-- que lo que ya hizo el marco.
local function NameFor(unit)
	for _, m in ipairs(ns.Selection:GetRosterHeroFirst()) do
		if m.unit == unit then return m.name end
	end
	return nil
end

--- La marca ---------------------------------------------------------------

local function Mark(entry)
	local m = marks[entry.unit]
	if m then return m end

	local host = _G[entry.frame]
	if not host then return nil end

	local anchor = _G[entry.portrait or ""] or host
	local f = CreateFrame("Frame", "RTSPick_" .. entry.unit, UIParent)
	f:SetFrameStrata("HIGH")
	f:EnableMouse(false)
	f:SetPoint("TOPLEFT", anchor, "TOPLEFT", -PAD, PAD)
	f:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", PAD, -PAD)
	f:Hide()

	local glow = f:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	glow:SetTexture(GLOW)
	glow:SetBlendMode("ADD")
	-- Un dorado palido, no el amarillo puro de `W.SELECT`: en ADD el color se
	-- SUMA a lo que hay debajo, asi que un amarillo saturado sobre un retrato
	-- claro lo quema.
	glow:SetVertexColor(1, 0.9, 0.55)
	glow:SetAlpha(0.55)

	m = { frame = f, glow = glow,
	      anchored = (anchor ~= host) and "retrato" or "marco" }
	marks[entry.unit] = m
	return m
end

function P:Refresh()
	for _, entry in ipairs(FRAMES) do
		local m = Mark(entry)
		if m then
			local host = _G[entry.frame]
			local name = self.active and NameFor(entry.unit) or nil
			-- TRES CONDICIONES Y LAS TRES HACEN FALTA: que estemos en modo RTS,
			-- que esa unidad sea del censo, y que su marco este a la vista. La
			-- tercera es la que evita un recuadro amarillo flotando donde
			-- estaria el marco de un companero que se acaba de ir.
			if name and ns.Selection:IsSelected(name)
			   and host and host:IsVisible() then
				m.frame:Show()
			else
				m.frame:Hide()
			end
		end
	end
end

--- El gancho --------------------------------------------------------------

local function Wire()
	if hooked then return end
	hooked = true

	for _, entry in ipairs(FRAMES) do
		local f = _G[entry.frame]
		if f and f.HookScript then
			-- `PostClick`, NUNCA `OnClick`. Ver la cabecera: el porque es la
			-- mitad de este fichero.
			--
			-- Y se comprueba si ya habia uno en vez de dar por hecho que
			-- `HookScript` sabe encadenar sobre nada. En este cliente lo hace
			-- -- se comporta como `SetScript` cuando no hay script previo --
			-- pero es una lectura de memoria, no comprobada contra el, y aqui
			-- fallar significa un error de Lua en el primer click sobre un
			-- marco. Dos lineas y deja de importar quien tenga razon.
			local handler = function(_, button)
				if not P.active then return end
				if button ~= "LeftButton" then return end

				local name = NameFor(entry.unit)
				if not name then return end

				-- UN HECHIZO ARMADO SE COME EL CLICK, igual que en el mundo 3D:
				-- es la mitad de §5 del brief que ocurre sobre un marco. Y es el
				-- gesto que mas se usa -- "que la sanadora cuide del tanque" es
				-- pulsar el hueco con ella cogida y pinchar al tanque aqui.
				if ns.Skills:Aiming() then
					ns.Skills:AimAt(UnitGUID(entry.unit), name,
						UnitCanAttack("player", entry.unit) and true or false)
					return
				end
				if ns.Cast:AimAt(UnitGUID(entry.unit), name) then return end

				ns.Selection:Click(name)
			end

			if f:GetScript("PostClick") then
				f:HookScript("PostClick", handler)
			else
				f:SetScript("PostClick", handler)
			end
		end
	end

	ns.Selection:Subscribe(function() P:Refresh() end)

	-- El grupo cambia y los marcos aparecen y desaparecen con el. La marca se
	-- revisa entonces, o se queda encendida sobre un marco que ya no esta.
	local ev = CreateFrame("Frame", "RTSPortraitEvents")
	ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:SetScript("OnEvent", function() P:Refresh() end)
end

--- Entrar y salir ---------------------------------------------------------

function P:Enter()
	self.active = true
	Wire()
	self:Refresh()
end

function P:Leave()
	self.active = false
	self:Refresh()
end

function P:Report()
	ns.Print("|cffffff00marcos del juego|r -- click izquierdo selecciona:")
	for _, entry in ipairs(FRAMES) do
		local f = _G[entry.frame]
		local m = marks[entry.unit]
		local name = NameFor(entry.unit)
		ns.Print(("  %-20s %s, marca en el %s%s"):format(
			entry.frame,
			f and (f:IsVisible() and "|cff00ff00a la vista|r" or "|cff888888escondido|r")
			  or "|cffff0000no existe|r",
			m and m.anchored or "?",
			name and (" -- " .. name) or ""))
	end
	if not hooked then
		ns.Print("  |cff888888todavia sin enganchar: se engancha al entrar en modo RTS.|r")
	end
end

ns.Dock:Register(P)
