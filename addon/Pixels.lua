--[[
	Pixels.lua -- la escala de pixel, y nada mas.

	Es lo UNICO que queda de `HUD.lua`, que se descarto entero el 2026-09-13
	con el rediseno de la interfaz. La HUD llevaba cuatro cosas y tres se han
	ido con su motivo:

	  - la linea de mensajes estilo WC3, que existia porque `Chrome` escondia el
	    chat y sin ella `ns.Print` no llegaba a ninguna parte. El chat ya no se
	    esconde, asi que sobra -- y con ella se va el envoltorio de `ns.Print`,
	    que era la unica linea del addon que reescribia una funcion ajena.
	  - la huella de medir (el panel del minimapa y la tira de la barra), que
	    era el sustituto provisional mientras no habia arte.
	  - el secuestro del Minimap. Vuelve a su sitio de siempre, en su
	    MinimapCluster, sin que nadie lo toque.

	LO QUE SE QUEDA ES LA CUENTA, porque la piden cuatro ventanas propias
	(`Window`, `Bags`, `Quests`, `Npc`) y el visor de arte, y porque el dia que
	la barra se vista de arte la va a volver a pedir.

	WoW no dibuja en pixeles, dibuja en unidades: la pantalla mide 768 unidades
	de alto a escala 1. Con 1440 px y uiScale 0.86, una unidad son 1.61 pixeles
	fisicos -- o sea que una textura de 512 se estira a 826 e interpola. Un
	frame escalado a 768/altoFisico tiene dentro 1 unidad = 1 pixel, y el arte
	sale nitido. El resto del juego conserva su uiScale intacto; no se toca.

	`ns.Pixels:ScaleFrame(f)` le pone esa escala a cualquier frame, contra la
	de SU padre, sea cual sea. `ns.Pixels:Host()` da el contenedor de pantalla
	completa que ya la lleva puesta, que es donde cuelga la barra de abajo.
]]

local ADDON, ns = ...

local P = {}
ns.Pixels = P

local host

--- El alto fisico de verdad ------------------------------------------------
--
-- `gxResolution` da la del ESCRITORIO, no la de la ventana: en ventana sin
-- bordes el escritorio puede ni siquiera tener la misma forma. La relacion de
-- aspecto de UIParent SI es la de la ventana real -- su alto en unidades es
-- fijo y su ancho cambia con la forma -- asi que el alto verdadero sale del
-- ancho. Se asume que la ventana ocupa todo el ancho, que es lo que hace
-- maximizada; `/rts pixels` ensena los dos numeros y se ve enseguida.
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

local function Measure()
	local w, h = PhysicalSize()
	P.screenW = w
	P.pixels = h
	P.pixel = h and (768 / h) or 1
	return w, h
end

-- La escala que le toca a `f` para que dentro de el 1 unidad = 1 pixel. Se
-- calcula contra la escala efectiva de SU padre, asi que vale colgado de donde
-- sea, y se acota: una escala de 0 deja el frame invisible sin decir nada.
function P:ScaleFrame(f)
	if not self.pixels then Measure() end
	local pixel = self.pixel or 1
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
-- Un boton mide 36 unidades, y en pixeles fisicos eso es
-- 36 * escalaEfectiva * (altoFisico/768).
function P:ActionButtonPixels()
	local btn = _G["ActionButton1"]
	local units = (btn and btn:GetWidth()) or 36
	if not units or units < 4 then units = 36 end
	local sc = (btn and btn:GetEffectiveScale()) or UIParent:GetEffectiveScale() or 1
	return units * sc * ((self.pixels or 768) / 768)
end

--- El contenedor -----------------------------------------------------------

function P:Host()
	return host
end

function P:Create()
	if host then return end

	host = CreateFrame("Frame", "RTSPixels", UIParent)
	host:SetFrameStrata("MEDIUM")
	host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
	host:EnableMouse(false)

	ns.Skin:Load()
	Measure()
	self:ScaleFrame(host)

	-- Cambiar de resolucion en caliente invalida la escala de pixel entera.
	local ev = CreateFrame("Frame", "RTSPixelsEvents")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:SetScript("OnEvent", function()
		Measure()
		P:ScaleFrame(host)
		if ns.Dock then ns.Dock:Layout() end
	end)
end

function P:Report()
	local w, h = PhysicalSize()
	ns.Print(("|cffffff00pixeles|r pantalla %sx%s, escala de pixel %.3f"):format(
		tostring(w), tostring(h), self.pixel or 1))
	ns.Print(("  un boton de accion mide %.1f px"):format(self:ActionButtonPixels()))
end
