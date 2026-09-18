--[[
	Talents.lua -- quitar puntos de talento con el boton derecho.

	El juego solo sabe resetear el arbol entero, pagando. Aqui el click derecho
	sobre un talento devuelve UN punto, y el izquierdo sigue siendo el de
	Blizzard -- no se toca, porque ya hace lo que tiene que hacer.

	=== NO SE ENGANCHA EL `OnClick`, SE ENGANCHA EL `OnMouseUp` =============

	Y es la decision que sostiene el fichero. Para que un boton conteste al
	derecho hay que registrarselo (`RegisterForClicks`), y ese registro es de la
	casa: se lo cambiariamos al boton de Blizzard, cuyo manejador -- que no es
	nuestro y cambia entre versiones del cliente -- podria entonces correr
	tambien en el derecho y APRENDER un punto al mismo tiempo que nosotros lo
	quitamos. El gesto haria las dos cosas a la vez y ninguna se veria.

	`OnMouseUp` llega igual sin registrar nada, asi que el boton de Blizzard se
	queda exactamente como estaba.

	=== Y SI HAY UNA PREVISUALIZACION, MANDA ELLA ==========================

	El cliente de 3.3.5 ya trae la vista previa de talentos: puntos que pones
	con el izquierdo y todavia no has confirmado, y que el derecho quita. Eso ya
	funciona y no es cosa nuestra. Cuando `GetTalentInfo` dice que hay rango
	previsualizado por encima del aprendido, este fichero no manda nada y deja
	que el cliente se quite lo suyo.

	=== LOS NOMBRES DEL MARCO SE PREGUNTAN, NO SE SABEN ====================

	La misma regla que `Chain.lua` con `SetRaidTargetIcon`: se prueban los dos
	nombres que ha tenido la ventana de talentos y se usa el que exista. Si no
	existe ninguno, `/rts talents` lo dice con todas las letras en vez de dejar
	un boton derecho que no hace nada.
]]

local ADDON, ns = ...

local T = {}
ns.Talents = T

-- La version de mod-rts que conoce `UNTALENT`.
local NEEDS = "0.58"

-- Los dos nombres que ha llevado la ventana. `PlayerTalentFrame` es el de
-- 3.3.5; el otro es el de antes de la especializacion dual, y esta por si este
-- cliente lleva un FrameXML mas viejo de lo que dice.
local FRAMES = {
	{ frame = "PlayerTalentFrame", button = "PlayerTalentFrameTalent" },
	{ frame = "TalentFrame",       button = "TalentFrameTalent" },
}

-- Cuantos botones se buscan como mucho. El cliente dibuja los que haga falta y
-- para; esto solo es el tope del bucle.
local MAX_BUTTONS = 40

T.found = nil        -- { frame = <Frame>, prefix = "...", n = <cuantos> }
T.hooked = {}

local waiting        -- true mientras se espera contestacion del servidor
local watch

local function Stop()
	waiting = nil
	if watch then watch:SetScript("OnUpdate", nil) end
end

-- El mismo plazo que el dial de experiencia y por el mismo motivo: un verbo que
-- mod-rts no conoce no da error, no contesta.
local function Expect()
	waiting = true
	if not watch then watch = CreateFrame("Frame", "RTSTalentWatch") end
	watch.acc = 0
	watch:SetScript("OnUpdate", function(f, elapsed)
		f.acc = f.acc + elapsed
		if f.acc < 2.5 then return end
		f:SetScript("OnUpdate", nil)
		if not waiting then return end
		waiting = nil
		ns.Print("|cffff8800talents:|r the server did not answer. This needs " ..
			"|cffffff00mod-rts " .. NEEDS .. "|r -- restart the worldserver.")
	end)
end

--- Encontrar la ventana ---------------------------------------------------

local function Discover()
	if T.found then return T.found end

	for _, cand in ipairs(FRAMES) do
		local frame = _G[cand.frame]
		local first = _G[cand.button .. "1"]
		if frame and first then
			local n = 0
			for i = 1, MAX_BUTTONS do
				if not _G[cand.button .. i] then break end
				n = i
			end
			T.found = { frame = frame, prefix = cand.button, n = n }
			return T.found
		end
	end
	return nil
end

--- El gesto ---------------------------------------------------------------

-- Lo que el cliente sabe de la casilla que se acaba de pulsar. Devuelve nil si
-- no contesta, que es lo que separa "aqui no hay talento" de "no me entiendo
-- con esta ventana".
local function InfoFor(button)
	local found = T.found
	if not found then return nil end

	local tab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(found.frame)
	if not tab then return nil end

	local id = button:GetID()
	if not id or id == 0 then return nil end

	-- `previewRank` es el noveno valor en 3.3.5. Si este cliente devolviera
	-- menos, sale nil y se trata como "no hay previsualizacion", que es el caso
	-- normal y el que no rompe nada.
	local name, _, tier, column, rank, maxRank, _, _, previewRank = GetTalentInfo(tab, id)
	if not name then return nil end

	return { tab = tab, tier = tier, column = column, rank = rank or 0,
	         maxRank = maxRank, preview = previewRank or 0, name = name }
end

local function OnRight(button)
	local info = InfoFor(button)
	if not info then
		ns.Print("|cffff8800talents:|r the talent window did not answer. " ..
			"|cffffff00/rts talents|r says what was found.")
		return
	end

	-- La previsualizacion del cliente va primero: ver la cabecera.
	if info.preview > info.rank then return end

	if info.rank == 0 then
		ns.Print(("|cff888888talents:|r %s has no points to take back."):format(info.name))
		return
	end

	ns.SendServer(("UNTALENT %d %d %d"):format(info.tab, info.tier, info.column))
	Expect()
end

local function Hook(found)
	for i = 1, found.n do
		local b = _G[found.prefix .. i]
		if b and not T.hooked[b] then
			T.hooked[b] = true
			-- `HookScript` y no `SetScript`: lo de Blizzard sigue corriendo.
			b:HookScript("OnMouseUp", function(self, click)
				if click == "RightButton" then OnRight(self) end
			end)
		end
	end
end

--- Arranque ---------------------------------------------------------------

function T:Create()
	if self.created then return end
	self.created = true

	ns.Link:On("TALENT", function(rest)
		local code, detail = rest:match("^(%S+)%s*(.*)$")
		if not code then return end
		Stop()

		if code == "OK" then
			local left = tonumber(detail) or 0
			if left > 0 then
				ns.Print(("|cff00ff00talents:|r one point back -- |cffffff00%d|r left there.")
					:format(left))
			else
				ns.Print("|cff00ff00talents:|r one point back -- that talent is empty now.")
			end
		elseif code == "DEP" then
			ns.Print(("|cffff8800talents:|r no -- |cffffff00%s|r hangs off that one. " ..
				"Empty that one first."):format(detail ~= "" and detail or "another talent"))
		elseif code == "ROW" then
			ns.Print(("|cffff8800talents:|r no -- row |cffffff00%s|r would be left " ..
				"without the points it needs. A tree empties from the bottom up.")
				:format(detail ~= "" and detail or "?"))
		elseif code == "NONE" then
			ns.Print("|cff888888talents:|r there is no point there.")
		else
			ns.Print("|cffff8800talents:|r the server did not recognise that talent. " ..
				"|cffffff00/rts talents|r says what this window is.")
		end
	end)

	-- La ventana de talentos se carga cuando se abre, no al entrar al mundo, y
	-- puede estar cargada YA si otro addon la abrio antes. Las dos puertas.
	local ev = CreateFrame("Frame", "RTSTalentEvents")
	ev:RegisterEvent("ADDON_LOADED")
	ev:SetScript("OnEvent", function(_, _, which)
		if which and which ~= "Blizzard_TalentUI" then return end
		local found = Discover()
		if found then Hook(found) end
	end)

	local found = Discover()
	if found then Hook(found) end
end

--- La sonda ---------------------------------------------------------------

function T:Report()
	local found = Discover()
	if not found then
		ns.Print("|cffff0000talents:|r the talent window is not loaded, or it is not " ..
			"called what this addon expects.")
		ns.Print("Open it once (the talents button) and run this again. If it still " ..
			"says this, the button names in |cffffff00Talents.lua|r are the ones to fix.")
		return
	end

	ns.Print(("|cffffff00talents|r -- |cff33ccff%s|r, %d buttons"):format(found.prefix, found.n))

	local tab = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(found.frame)
	ns.Print(("  selected tab: %s"):format(tostring(tab)))

	if tab then
		local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, 1)
		ns.Print(("  first talent: %s  tier %s  col %s  %s/%s"):format(
			tostring(name), tostring(tier), tostring(column),
			tostring(rank), tostring(maxRank)))
	end

	ns.Print("Right-click a talent to take one point back. Left-click is the " ..
		"game's own and is not touched.")
end
