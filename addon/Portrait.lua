--[[
	Portrait.lua -- el modelo 3D del heroe, dentro del hueco del retrato.

	No es una imagen: es un `PlayerModel`, el mismo widget con el que el cliente
	dibuja tu personaje en la ficha. Vive, respira, se mueve con las animaciones
	de reposo y cambia solo al cambiarte de equipo o al montar. Un retrato 2D
	(`SetPortraitTexture`) habria sido una linea, pero es un recorte fijo de la
	cara y no es lo que pide una consola de RTS.

	LO QUE ESTE FICHERO NO DA POR SUPUESTO. El widget `Model` de 3.3.5a no tiene
	la misma lista de metodos que el de las versiones modernas, y la
	documentacion que se encuentra por ahi es casi toda de las nuevas. Asi que
	NADA se llama a pelo: todo pasa por `Try`, que comprueba que el metodo
	exista y se traga el fallo, y `/rts portrait status` imprime CUALES existen
	de verdad en este cliente. Es la misma leccion que `nameplateMaxDistance` y
	que `gxWindowedResolution`: comprobar contra el cliente, no contra internet
	-- solo que aqui la comprobacion se puede dejar puesta.

	EL ORDEN IMPORTA Y NO ES EL OBVIO. `SetUnit` REHACE el modelo entero, asi
	que se lleva por delante la camara, la posicion y el giro. Todo lo demas
	tiene que ir DESPUES de el, siempre. Ponerlo antes es el fallo tipico: se
	ajusta el encuadre, se refresca el modelo por cualquier motivo y el encuadre
	desaparece sin que nada haya dado error.

	SE REPONE SOLO, PORQUE EL CLIENTE LO VACIA. Una pantalla de carga deja el
	modelo en blanco, y montar o cambiar de equipo lo rehacen. Se rearma con
	`PLAYER_ENTERING_WORLD` y `UNIT_MODEL_CHANGED`, y ademas con dos reintentos
	con retraso: justo al terminar de cargar el modelo puede no estar listo
	todavia, y el evento llega antes que el modelo. Un reintento no cuesta nada
	y es la diferencia entre un retrato y un cuadro gris.

	NO TOCA EL RATON. Un `Model` captura clicks si se le deja, y esta encima de
	la barra, que es justo la zona donde la caja de seleccion no puede fallar
	(prueba B6). `EnableMouse(false)`, como todo lo demas de la barra.
]]

local ADDON, ns = ...

local P = {}
ns.Portrait = P

P.active = false

-- `cam` 1 era la apuesta: la camara de retrato que traen los modelos de
-- personaje. EN ESTE CLIENTE NO HACE NADA -- se vio en juego, sale el cuerpo
-- entero igual que con la 0. Asi que el encuadre se hace a mano con
-- `SetPosition` y `SetModelScale`, y `cam` se queda en 0, que es la que
-- documenta el cuerpo entero.
--
-- 45 grados de giro es el "2/4" de un retrato: ni de frente ni de perfil.
P.cfg = {
	unit = "player",
	cam = 0, zoom = 1.4, x = 0, y = -0.55,
	facing = math.rad(45), scale = 1, light = true,
	framing = 1,
}

-- LOS DOS SIGNOS QUE NADIE SABE, Y COMO SE AVERIGUAN.
--
-- `Model:SetPosition(a, b, c)` mueve el modelo delante de la camara, pero en
-- 3.3.5a no esta documentado si el primer eje acerca o aleja, ni si el tercero
-- sube o baja. Y `SetModelScale` escala desde los PIES, asi que ampliar manda
-- la cabeza fuera del cuadro y hay que compensar -- otra vez sin saber en que
-- direccion.
--
-- Se puede razonar mal durante media hora o se puede mirar. Esta tabla son las
-- cuatro combinaciones de signo mas las dos que usan escala en vez de acercar;
-- `/rts portrait try` pasa a la siguiente y la deja aplicada y guardada. La
-- correcta se reconoce en cuanto sale, que es exactamente lo que un encuadre
-- necesita y una deduccion no da.
--
-- Es la misma decision que el circulo de seleccion de la etapa 5e: una lectura
-- estatica convincente valia UNA prueba barata en juego, no dos compilaciones
-- de maquinaria encima.
local FRAMINGS = {
	{ zoom =  1.4, y = -0.55, scale = 1,   label = "acercar, bajar" },
	{ zoom = -1.4, y = -0.55, scale = 1,   label = "alejar, bajar" },
	{ zoom =  1.4, y =  0.55, scale = 1,   label = "acercar, subir" },
	{ zoom = -1.4, y =  0.55, scale = 1,   label = "alejar, subir" },
	{ zoom =  0,   y = -1.20, scale = 3,   label = "escalar x3, bajar" },
	{ zoom =  0,   y =  1.20, scale = 3,   label = "escalar x3, subir" },
	{ zoom =  0.7, y = -0.30, scale = 2,   label = "mitad y mitad" },
}

local model, host, ev
local retry = { at = nil, veces = 0 }

-- Que metodos existen de verdad. Se rellena la primera vez que se aplica y lo
-- imprime `status`.
local visto = {}

--- La capa de "existe este metodo?" ---------------------------------------

local function Try(metodo, ...)
	if not model then return false end
	local f = model[metodo]
	if type(f) ~= "function" then
		visto[metodo] = "NO EXISTE"
		return false
	end
	local ok, err = pcall(f, model, ...)
	visto[metodo] = ok and "ok" or ("error: " .. tostring(err))
	return ok
end

-- El giro cambio de nombre entre versiones. Se prueban los dos y se recuerda
-- cual contesto, en vez de elegir uno y esperar.
local function Facing(rad)
	if Try("SetFacing", rad) then return true end
	return Try("SetRotation", rad)
end

--- Armar el modelo ---------------------------------------------------------

local function Apply()
	if not model then return end

	local unit = P.cfg.unit or "player"
	if not UnitExists(unit) then
		Try("ClearModel")
		return
	end

	-- SetUnit PRIMERO: rehace el modelo y borra todo lo de abajo.
	if not Try("SetUnit", unit) then return end

	Try("SetCamera", P.cfg.cam or 0)

	-- ESCALA ANTES QUE POSICION. `SetModelScale` escala desde los pies, asi que
	-- mueve la cabeza; si se posiciona primero, escalar deshace el centrado y
	-- el resultado depende del orden en que se toquen los mandos, que es la
	-- clase de cosa que hace imposible encuadrar nada a ojo.
	Try("SetModelScale", P.cfg.scale or 1)
	Try("SetPosition", P.cfg.zoom or 0, P.cfg.x or 0, P.cfg.y or 0)
	Facing(P.cfg.facing or 0)

	-- Los modelos dentro de un frame nuestro no heredan la luz de la escena, y
	-- sin luz propia salen planos o casi negros segun la zona. Los valores son
	-- los del propio cliente para la ficha de personaje.
	if P.cfg.light then
		Try("SetLight", 1, 0, 0, -1, 0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
	end
end

-- Rearmar dentro de un rato. Existe porque el evento que dice "ya has entrado
-- al mundo" llega ANTES de que el modelo se pueda pedir, asi que aplicar solo
-- en el evento deja el hueco vacio hasta el siguiente cambio de equipo.
local function Retry(segundos)
	retry.at = GetTime() + (segundos or 0.5)
	retry.veces = 0
end

--- Crear -------------------------------------------------------------------

function P:Create()
	if model then return end

	model = CreateFrame("PlayerModel", "RTSHeroPortrait", UIParent)
	model:EnableMouse(false)
	model:Hide()

	if type(RTSCommandDB.portrait) == "table" then
		for _, k in ipairs({ "cam", "zoom", "x", "y", "facing", "scale", "framing" }) do
			local v = tonumber(RTSCommandDB.portrait[k])
			if v then self.cfg[k] = v end
		end
		if type(RTSCommandDB.portrait.light) == "boolean" then
			self.cfg.light = RTSCommandDB.portrait.light
		end
	end

	ev = CreateFrame("Frame", "RTSHeroPortraitEvents")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("UNIT_MODEL_CHANGED")
	ev:RegisterEvent("PLAYER_ALIVE")
	ev:SetScript("OnEvent", function(_, event, arg1)
		if not P.active then return end
		if event == "UNIT_MODEL_CHANGED" and arg1 ~= (P.cfg.unit or "player") then
			return
		end
		Apply()
		Retry(0.5)
	end)

	-- El reintento con retraso. Un OnUpdate en vez de un temporizador porque
	-- 3.3.5a no tiene ninguno, y en vez de uno por evento se lleva uno solo con
	-- un sello de tiempo.
	ev:SetScript("OnUpdate", function()
		if not retry.at or GetTime() < retry.at then return end
		retry.veces = retry.veces + 1
		Apply()
		if retry.veces >= 2 then retry.at = nil else retry.at = GetTime() + 1.5 end
	end)
end

--- Alojarse en la barra ----------------------------------------------------

-- Bar.lua llama con su hueco al entrar y con nil al salir.
function P:Host(frame)
	self:Create()
	host = frame

	if not frame then
		self.active = false
		model:Hide()
		model:SetParent(UIParent)
		model:ClearAllPoints()
		retry.at = nil
		return
	end

	self.active = true
	model:SetParent(frame)
	model:ClearAllPoints()
	model:SetAllPoints(frame)
	-- Por encima del panel, que es opaco donde esta el hueco.
	model:SetFrameLevel(frame:GetFrameLevel() + 1)
	model:Show()
	Apply()
	Retry(0.5)
end

-- La barra se ha recolocado: el hueco puede tener otro tamano. `SetAllPoints`
-- ya lo sigue, asi que esto solo rearma por si el cambio de tamano dejo el
-- modelo en blanco -- que pasa mas de lo que deberia.
function P:Relayout()
	if not self.active then return end
	Retry(0.2)
end

--- Ajustes -----------------------------------------------------------------

local function Save(k, v)
	RTSCommandDB.portrait = RTSCommandDB.portrait or {}
	RTSCommandDB.portrait[k] = v
end

-- Un solo camino para todos los numeros: se guarda, se reaplica y se dice como
-- quedo. Tener uno por knob era copiar cinco veces las mismas cuatro lineas.
function P:Set(k, v)
	self:Create()
	if k == "light" then
		local on = not (tostring(v):lower() == "off" or v == "0" or v == "no")
		self.cfg.light = on
		Save("light", on)
	else
		local n = tonumber(v)
		if not n then return false end
		if k == "facing" then n = math.rad(n) end
		if k == "cam" then n = math.floor(n) end
		self.cfg[k] = n
		Save(k, n)
	end
	Apply()
	self:Report()
	return true
end

-- Aplicar el encuadre n de la tabla. Se guarda como cualquier otro ajuste: lo
-- que se esta viendo es lo que queda, sin un "confirmar" aparte que sirve solo
-- para que se te olvide.
function P:Framing(n)
	self:Create()
	n = tonumber(n)
	if not n then n = (self.cfg.framing or 1) + 1 end
	n = math.floor(n)
	if n < 1 then n = #FRAMINGS end
	if n > #FRAMINGS then n = 1 end

	local f = FRAMINGS[n]
	self.cfg.framing = n
	self.cfg.zoom, self.cfg.y, self.cfg.scale = f.zoom, f.y, f.scale
	Save("framing", n)
	Save("zoom", f.zoom)
	Save("y", f.y)
	Save("scale", f.scale)
	Apply()

	ns.Print(("encuadre |cffffff00%d/%d|r - %s   " ..
		"(zoom %.2f  y %.2f  escala %.1f)   " ..
		"|cffffff00/rts portrait try|r para el siguiente"):format(
		n, #FRAMINGS, f.label, f.zoom, f.y, f.scale))
	return true
end

function P:Reset()
	self:Create()
	self.cfg.cam, self.cfg.x = 0, 0
	self.cfg.facing, self.cfg.light = math.rad(45), true
	self.cfg.framing = 1
	RTSCommandDB.portrait = nil
	local f = FRAMINGS[1]
	self.cfg.zoom, self.cfg.y, self.cfg.scale = f.zoom, f.y, f.scale
	Apply()
	ns.Print("retrato devuelto a las medidas de fabrica.")
end

function P:Refresh()
	self:Create()
	Apply()
	Retry(0.3)
	ns.Print("retrato rearmado.")
end

function P:Report()
	self:Create()
	ns.Print(("retrato: |cffffff00%s|r   camara |cffffff00%d|r   " ..
		"zoom |cffffff00%.2f|r  x |cffffff00%.2f|r  y |cffffff00%.2f|r   " ..
		"giro |cffffff00%.0f|r   escala |cffffff00%.2f|r   luz %s"):format(
		self.cfg.unit or "player", self.cfg.cam or 0,
		self.cfg.zoom or 0, self.cfg.x or 0, self.cfg.y or 0,
		math.deg(self.cfg.facing or 0), self.cfg.scale or 1,
		self.cfg.light and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

	if not self.active then
		ns.Print("|cffff8800sin hueco:|r la barra no esta puesta. |cffffff00/rts bar|r")
	end

	-- Lo unico que de verdad hay que saber de este fichero: que metodos del
	-- widget existen en ESTE cliente. Se responde con hechos, no de memoria.
	local partes = {}
	for _, m in ipairs({ "SetUnit", "SetCamera", "SetModelScale", "SetPosition",
	                     "SetFacing", "SetRotation", "SetLight", "ClearModel" }) do
		local estado = visto[m]
		if estado == nil then
			estado = (type(model[m]) == "function") and "|cff888888sin usar|r"
			                                        or "|cffff0000NO EXISTE|r"
		elseif estado == "ok" then
			estado = "|cff00ff00ok|r"
		else
			estado = "|cffff0000" .. estado .. "|r"
		end
		table.insert(partes, m .. " " .. estado)
	end
	ns.Print("API: " .. table.concat(partes, "   "))

	ns.Print(("encuadre |cffffff00%d/%d|r (%s) - |cffffff00/rts portrait try|r " ..
		"pasa al siguiente"):format(self.cfg.framing or 1, #FRAMINGS,
		FRAMINGS[self.cfg.framing or 1] and FRAMINGS[self.cfg.framing or 1].label
		                                 or "a mano"))

	ns.Print("|cffffff00/rts portrait try|r  |cffffff00facing <grados>|r  " ..
		"|cffffff00zoom <n>|r  |cffffff00y <n>|r  |cffffff00x <n>|r  " ..
		"|cffffff00scale <n>|r  |cffffff00cam <0|1>|r  " ..
		"|cffffff00light on|off|r  |cffffff00refresh|r  |cffffff00default|r")
end
