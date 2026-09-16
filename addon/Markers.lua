--[[
	Markers.lua -- visible world markers via world->screen projection.

	rts_core.dll publishes the camera basis (position + forward/right/up +
	fov/aspect). With that we can project any world point to a screen pixel and
	park a texture there, so the player finally SEES something on the ground.

	The projection convention (whether fov is vertical, and the sign of the
	right/up axes) is not certain up front, so the tunables below can be flipped
	and reloaded with /console reloadui -- no DLL rebuild needed.

	First visible test: a ring of markers on the ground around the player. If it
	renders as a circle centred on your character, the projection is correct.
]]

local ADDON, ns = ...

local M = {}
ns.Markers = M

-- Projection scale factors (1/tan(hfov/2), 1/tan(vfov/2)). Defaults from the
-- horizontal-FOV starting guess; /rts cal measures the exact values.
M.SX = 1.0
M.SY = 1.7778

-- === projection intrinsics =================================================
-- The client's camera "right" row is actually the geometric LEFT (verified from
-- the logged matrix: forward x up = -right), so the sideways axis is negated.
local RIGHT_SIGN = -1
local UP_SIGN    = 1

-- RTS_CamFov (camera struct +0x40, 1.5708 = 90 deg) is the DIAGONAL field of
-- view. Not horizontal, not vertical. That one fact explains every earlier miss:
-- read as horizontal it gives SX=1.0, which is 13% short ("close but still
-- short"); read as vertical it gives 0.5625, which is 0.49x of the truth
-- ("landed about halfway"). The cursor reticle never exposed it because a
-- project/unproject round-trip cancels any scale error.
--
-- So the scales are derived, not calibrated. With the diagonal half-angle d/2:
--   tan(vfov/2) = tan(d/2) / sqrt(1 + aspect^2)
--   SY = 1/tan(vfov/2)      SX = SY / aspect
-- and SX/SY are locked to each other by geometry rather than convention: the
-- render aspect equals the display aspect, so pixels are square and the focal
-- length in pixels is the same on both axes (SX*w == SY*h).
--
-- Deriving beats storing a fitted constant: it follows a resolution change, and
-- it follows the FOV itself, which the client alters for some effects.
-- Confirmed against 900+ measured samples: derived SX 1.1473 vs measured 1.1404
-- and 1.1266 in two independent runs (~1%, inside this method's noise).
-- /rts cal is now a verification tool; /rts cal apply overrides if ever needed.
-- ===========================================================================

M.autoIntrinsics = true

-- Scales computed from the live camera and window. Nil if the camera is not
-- published yet. Always computes, so it stays comparable against a measurement
-- even when an override is active.
function M:Derived()
	local w, h = GetScreenWidth(), GetScreenHeight()
	local fov = RTS_CamFov
	if not fov or fov <= 0.01 or not h or h <= 0 then return nil end

	local aspect = w / h
	local tv = math.tan(fov * 0.5) / math.sqrt(1 + aspect * aspect)
	if tv <= 1e-6 then return nil end

	local sy = 1 / tv
	return sy / aspect, sy
end

-- Cuanto puede alejarse una calibracion de la escala DERIVADA antes de que sea
-- basura. La derivada sale del FOV que publica el DLL y de la forma de la
-- pantalla, o sea de geometria; una medida buena cae a un pelo de ella (1.1404
-- medido contra 1.1473 derivado, un 0.6%). Un 25% no es un error de medida: es
-- otra cosa.
local OVERRIDE_TOL = 0.25

-- Horizontal and vertical ndc scale actually used for projection.
function M:Intrinsics()
	-- UNA CALIBRACION GUARDADA SE COMPRUEBA ANTES DE CREERLA, y no al
	-- guardarla: se guarda una vez y se lee treinta veces por segundo durante
	-- meses, y el `Set` solo corre cuando el jugador teclea. Sexta vez en este
	-- addon (`grow = 688`, `camHold`, `railCropGen`, la sala, `slots`).
	--
	-- Aqui hacia falta de verdad: `Markers:Calibrate` -- la tecla de calibrar --
	-- resuelve la escala con UNA sola muestra, suponiendo que el cursor estaba
	-- exactamente encima de la unidad seleccionada cuando se pulso. Si no lo
	-- estaba, escribe una escala mala y la deja puesta PARA SIEMPRE, con
	-- `forceScale` guardado. Reportado como *"pulse G para calibrar no se que y
	-- algo se fue a la mierda"*, con la proyeccion desviada desde entonces.
	--
	-- No se puede comprobar al cargar porque la derivada necesita el FOV del
	-- DLL, que llega despues. Se comprueba la primera vez que hay con que.
	if not self.overrideChecked and not self.autoIntrinsics then
		local dx, dy = self:Derived()
		if dx and dy and dx > 0 and dy > 0 then
			self.overrideChecked = true
			local off = math.max(math.abs((self.SX or 0) / dx - 1),
			                     math.abs((self.SY or 0) / dy - 1))
			if off > OVERRIDE_TOL then
				ns.Print(("|cffff8800proyeccion:|r la calibracion guardada se " ..
				          "aparta un %d%% de la derivada del FOV. Descartada."):format(
					math.floor(off * 100)))
				ns.Print("|cff888888Era casi seguro un /rts cal o una tecla de " ..
				         "calibrar con el cursor fuera de la unidad.|r")
				self:UseDerived()
			end
		end
	end

	if self.autoIntrinsics then
		local sx, sy = self:Derived()
		if sx then return sx, sy end
	end
	return self.SX, self.SY
end

-- Volver a la escala derivada y olvidar la guardada. Un solo sitio, porque lo
-- llaman la comprobacion de arriba, `/rts cal auto` y el rechazo de una
-- calibracion imposible.
function M:UseDerived()
	self.autoIntrinsics = true
	self.DEPTH_BIAS = 0
	if RTSCommandDB then
		RTSCommandDB.forceScale = nil
		RTSCommandDB.DEPTH_BIAS = 0
		RTSCommandDB.SX = nil
		RTSCommandDB.SY = nil
	end
end

M.RIGHT_SIGN = RIGHT_SIGN
M.UP_SIGN    = UP_SIGN

-- Displacement of the true eye from the camera struct's stored position, along
-- the view axis. Zero unless /rts cal measures otherwise; it exists because a
-- stored position that is not the eye produces a depth error that no scale can
-- absorb. See Calib.lua.
M.DEPTH_BIAS = 0

-- The effective eye: the point rays actually originate from.
function M:Eye()
	local d = self.DEPTH_BIAS or 0
	return RTS_CamX - RTS_CamFwdX * d,
	       RTS_CamY - RTS_CamFwdY * d,
	       RTS_CamZ - RTS_CamFwdZ * d
end

-- Camera-space coordinates of a world point: depth along forward, plus the
-- sideways and vertical offsets with the axis-sign convention already applied.
-- Single source of truth -- Project, the inverse, and the calibrator all use it.
-- Pass raw=true to get the unbiased depth, which is what a fit must be run on.
function M:CamCoords(wx, wy, wz, raw)
	if RTS_HasCam ~= 1 then return nil end

	local dx = wx - RTS_CamX
	local dy = wy - RTS_CamY
	local dz = wz - RTS_CamZ

	local depth = dx * RTS_CamFwdX + dy * RTS_CamFwdY + dz * RTS_CamFwdZ
	if not raw then depth = depth + (self.DEPTH_BIAS or 0) end
	if depth <= 0.01 then return nil end   -- behind the camera

	local rc = (dx * RTS_CamRightX + dy * RTS_CamRightY + dz * RTS_CamRightZ) * RIGHT_SIGN
	local uc = (dx * RTS_CamUpX    + dy * RTS_CamUpY    + dz * RTS_CamUpZ)    * UP_SIGN
	return depth, rc, uc
end

-- World point -> screen pixel (WoW origin = bottom-left, y up).
function M:Project(wx, wy, wz)
	local depth, rc, uc = self:CamCoords(wx, wy, wz)
	if not depth then return nil end

	local SX, SY = self:Intrinsics()
	local ndcx = (rc / depth) * SX
	local ndcy = (uc / depth) * SY

	local w, h = GetScreenWidth(), GetScreenHeight()
	return (ndcx * 0.5 + 0.5) * w, (ndcy * 0.5 + 0.5) * h
end

-- El cursor en unidades de UIParent, que es el espacio en el que Project
-- devuelve sus pixeles. Un solo sitio lo convierte: el desproyectado y la
-- comprobacion del impacto del DLL tienen que medir contra lo MISMO o la
-- comprobacion mediria su propia diferencia de unidades.
function M:CursorPixel()
	local mx, my = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	return mx / s, my / s
end

-- Lo ultimo que dijo la comprobacion del punto de suelo, para /rts aim. No es
-- adorno: distingue las dos formas de fallar del rayo del DLL, que se ven igual
-- en pantalla y se arreglan en sitios distintos.
--
--   * el impacto se proyecta SIEMPRE cerca del mismo pixel, pase el cursor por
--     donde pase  ->  el DLL esta leyendo otro cursor (el cliente se lo mueve).
--   * el impacto se proyecta en el cursor ENCOGIDO hacia el centro, con un
--     factor estable  ->  el DLL abre el abanico de rayos con un tamano de
--     ventana o un fov que no son los del fotograma.
--
-- `tol` en unidades de UIParent. Generoso a proposito: un impacto bueno cae a
-- uno o dos pixeles, y lo unico que lo separa de ahi es que la camara se haya
-- movido en los 33 ms que el impacto lleva de retraso.
M.aim = { tol = 60, on = false, ok = nil, how = "?", d = nil }

-- EL RAYO DEL CURSOR: origen y direccion, en coordenadas de mundo.
--
-- Es la unica parte de "donde he pinchado" que el cliente sabe con exactitud, y
-- son las dos mitades buenas de este addon: el pixel lo dice Lua (que no se
-- entera de que el cliente le haya cogido el raton) y la base de la camara la
-- publica rts_core cada fotograma. Lo que falta -- cortar el rayo contra el
-- suelo -- no se puede hacer aqui, porque en Lua no hay mapa; eso lo contesta
-- mod-rts, que si lo tiene. Ver `GROUND` en mod_rts.cpp.
function M:CursorRay()
	if RTS_HasCam ~= 1 then return nil end

	local mx, my = self:CursorPixel()
	local w, h = GetScreenWidth(), GetScreenHeight()
	local ndcx = (mx / w) * 2 - 1
	local ndcy = (my / h) * 2 - 1

	local SX, SY = self:Intrinsics()
	local a = ndcx / (SX * RIGHT_SIGN)
	local b = ndcy / (SY * UP_SIGN)

	local dx = RTS_CamFwdX + RTS_CamRightX * a + RTS_CamUpX * b
	local dy = RTS_CamFwdY + RTS_CamRightY * a + RTS_CamUpY * b
	local dz = RTS_CamFwdZ + RTS_CamRightZ * a + RTS_CamUpZ * b

	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-6 then return nil end

	local ex, ey, ez = self:Eye()
	return ex, ey, ez, dx / len, dy / len, dz / len
end

-- Inverse of Project: the ground point under the mouse cursor.
--
-- The cursor is unprojected onto a horizontal plane, and the whole question is
-- what height that plane sits at. It used to be the PLAYER's Z, which is exact
-- on flat ground beside your character and wrong everywhere else. The detached
-- RTS camera made that unusable -- the camera can be a hundred yards from the
-- character whose Z the plane was pinned to.
--
-- So the height now comes from rts_core's terrain raycast (RTS_CurZ), which is
-- the client's own picking function aimed down the cursor ray. The plane is
-- anchored at the real ground height under the cursor, and unprojecting is
-- still done per frame in Lua so the reticle stays locked to the mouse instead
-- of lagging the DLL's 30 Hz publish.
--
-- Uses the same SX/SY as Project, so it stays a true inverse of it.
function M:CursorGroundPoint()
	if RTS_HasCam ~= 1 then return nil end

	-- EL DLL YA SABE LA RESPUESTA EXACTA, Y ESTA FUNCION LA TIRABA A LA BASURA.
	--
	-- `RTS_CurX/Y/Z` es el punto donde la funcion de picking DEL PROPIO CLIENTE
	-- corta el terreno bajo el cursor. Es el sitio, no una estimacion. Lo que
	-- habia aqui se quedaba solo con la Z de ese punto, la usaba como altura de
	-- un PLANO horizontal, y devolvia donde el rayo del cursor cruza ese plano.
	--
	-- Eso introduce dos errores que se vieron en juego:
	--
	--   * en X/Y, el plano no es el terreno. Si el suelo sube o baja, el corte
	--     con el plano no es el corte con el suelo, y la diferencia crece con la
	--     distancia y con la pendiente -- "de lejos el punto no queda donde lo
	--     puse".
	--   * en Z, cuando el rayo NO acertaba (`RTS_CurHit == 0`) se caia a `RTS_PZ`,
	--     la altura DEL JUGADOR. Con la camara despegada mirando a un valle o a
	--     una colina a cien yardas, eso no se parece en nada a la altura de
	--     aquello -- y como esa Z se manda como destino, los bots acababan
	--     flotando a la altura del marcador.
	--
	-- Asi que si hay impacto, se devuelve el impacto: exacto por construccion,
	-- sin plano y sin deriva.
	--
	-- PERO SOLO SI ESE PUNTO ESTA DEBAJO DEL CURSOR, Y HAY QUE COMPROBARLO.
	--
	-- El rayo lo tira el DLL con el cursor de WINDOWS (`GetCursorPos`) leido en
	-- su vuelta de 30 Hz. Ese cursor no siempre es el que el jugador cree que
	-- esta usando: mientras el cliente se queda con el raton -- que es lo que
	-- pasa con un boton apretado -- lo mueve el, y lo que el DLL lee entonces no
	-- es a donde apunta nadie. El fallo no es un error pequeno de unas yardas:
	-- es un punto de otro sitio. En juego se vio como "solo funciona un trozo
	-- pequeno en medio de la pantalla, y si pincho mas lejos la marca se me
	-- viene al centro".
	--
	-- La comprobacion es gratis y no puede discrepar del resto del addon: un
	-- punto que este SOBRE el rayo del cursor se proyecta EXACTAMENTE en el
	-- pixel del cursor, sea cual sea su distancia -- proyectar es el inverso de
	-- desproyectar. Asi que se proyecta el impacto y se mira donde cae. Si cae
	-- encima del cursor, el DLL uso nuestro cursor y su respuesta es exacta; si
	-- cae lejos, uso otro y se tira.
	--
	-- Lo que queda cuando se tira NO es lo de antes del todo: el plano se ancla
	-- en la Z del impacto (suelo de verdad, aunque sea de otro punto de la
	-- vista) y solo cae a la Z DEL JUGADOR si no hubo impacto ninguno.
	local mx, my = self:CursorPixel()
	local planeZ

	if RTS_CurHit == 1 then
		local px, py = self:Project(RTS_CurX, RTS_CurY, RTS_CurZ)
		if px then
			local d = math.sqrt((px - mx) ^ 2 + (py - my) ^ 2)
			self.aim.d, self.aim.px, self.aim.py = d, px, py
			self.aim.mx, self.aim.my = mx, my
			self.aim.ok = d <= self.aim.tol
			if self.aim.ok then
				self.aim.how = "DLL"
				return RTS_CurX, RTS_CurY, RTS_CurZ
			end
		else
			self.aim.ok, self.aim.d = false, nil
		end
		planeZ = RTS_CurZ
		self.aim.how = "plano(z del impacto)"
	else
		self.aim.ok, self.aim.d, self.aim.px = false, nil, nil
		self.aim.how = "plano(z del jugador)"
	end

	if not planeZ then
		if RTS_HasPos == 1 then
			planeZ = RTS_PZ      -- sin DLL, o el rayo solo encontro cielo
		else
			return nil
		end
	end

	local w, h = GetScreenWidth(), GetScreenHeight()
	local ndcx = (mx / w) * 2 - 1
	local ndcy = (my / h) * 2 - 1

	-- Ray coefficients along the camera's right/up axes, per unit depth.
	local SX, SY = self:Intrinsics()
	local a = ndcx / (SX * RIGHT_SIGN)
	local b = ndcy / (SY * UP_SIGN)

	local dx = RTS_CamFwdX + RTS_CamRightX * a + RTS_CamUpX * b
	local dy = RTS_CamFwdY + RTS_CamRightY * a + RTS_CamUpY * b
	local dz = RTS_CamFwdZ + RTS_CamRightZ * a + RTS_CamUpZ * b

	if math.abs(dz) < 1e-6 then return nil end

	-- Rays leave the effective eye, which is the stored camera position only
	-- while DEPTH_BIAS is zero.
	local ex, ey, ez = self:Eye()
	local k = (planeZ - ez) / dz
	if k <= 0 then return nil end

	return ex + dx * k, ey + dy * k, ez + dz * k
end

-- EL PUNTO DE LA PULSACION, que no es el mismo que el punto del cursor.
--
-- `CursorGroundPoint` de aqui arriba contesta "donde apunta el raton AHORA", y
-- para eso esta bien: es lo que dibuja el reticulo, cada fotograma. Una ORDEN
-- pregunta otra cosa -- "donde estaba apuntando cuando apreto" -- y las dos
-- respuestas se separan justo en el momento en que importa:
--
--   * el rayo continuo lo tira el DLL desde el cursor de WINDOWS, y mientras el
--     cliente tiene el raton cogido -- que es lo que hace un boton apretado --
--     ese cursor lo mueve el. El rayo sale hacia donde no apunta nadie.
--   * y llega con hasta un tick de retraso, que con la camara paneando es
--     bastante suelo.
--
-- Desde rts_core 0.30.0 el DLL casca el rayo EN EL MENSAJE del boton: con el
-- pixel que trae el propio mensaje, con la camara del fotograma que el jugador
-- estaba mirando, y antes de que el cliente reparta el click -- asi que cuando
-- nuestro OnMouseDown corre, la respuesta a ESA pulsacion ya es un global.
--
-- Aqui no hay proyeccion, ni escala, ni tolerancia, ni plano: no hay nada que
-- estimar. O el DLL vio la pulsacion, y entonces el punto es exacto por
-- construccion, o no la vio y esto devuelve nil para que el camino de siempre
-- siga siendo el que contesta.
--
-- EL NUMERO DE SECUENCIA ES LA COMPROBACION, y es la unica que hace falta: si
-- no ha subido desde la ultima pulsacion que consumimos, este mensaje no ha
-- llegado -- cliente sin DLL, o un cliente que no entrega el raton por la cola
-- de ventanas -- y devolver el disparo anterior seria mandar la orden al sitio
-- del click de antes.
function M:ClickShot(button)
	local seq = tonumber(RTS_ClkSeq)
	if not seq then return nil end
	if seq == self.lastShotSeq then return nil end       -- esta pulsacion no se vio
	self.lastShotSeq = seq

	local want = (button == "LeftButton") and 1 or 2
	if tonumber(RTS_ClkBtn) ~= want then return nil end

	local shot = {
		seq = seq,
		ox = RTS_ClkOX, oy = RTS_ClkOY, oz = RTS_ClkOZ,
		dx = RTS_ClkDX, dy = RTS_ClkDY, dz = RTS_ClkDZ,
	}
	-- El rayo vale aunque no cortara nada: es con lo que se le pregunta al
	-- servidor, que si tiene mapa. Solo el PUNTO depende de que acertara.
	if RTS_ClkHit == 1 then
		shot.x, shot.y, shot.z = RTS_ClkX, RTS_ClkY, RTS_ClkZ
	end
	if type(shot.ox) ~= "number" or type(shot.dx) ~= "number" then return nil end

	if self.aim.on then
		ns.Print(("|cff88ccffclick|r #%d btn%d en %s,%s -> %s"):format(
			seq, tonumber(RTS_ClkBtn) or 0, tostring(RTS_ClkPx), tostring(RTS_ClkPy),
			shot.x and ("|cff00ff00%.1f %.1f %.1f|r"):format(shot.x, shot.y, shot.z)
			       or "|cffffff00sin corte (cielo)|r"))
	end
	return shot
end

-- Solve SX/SY exactly from the currently selected unit + current cursor.
-- Put the cursor on the unit's feet (the game draws it at its true position),
-- and this derives the projection scale that maps that world point to that
-- pixel. One measurement fully determines the intrinsics.
function M:Calibrate()
	local sel = ns.Selection:Get()
	if #sel ~= 1 then
		ns.Print("|cffff0000Calibrate:|r select exactly ONE unit first.")
		return
	end
	local unit = ns.Selection:UnitFor(sel[1])
	local guid = unit and UnitGUID(unit)
	local bx, by, bz
	if guid then bx, by, bz = self:UnitWorld(guid) end
	if not bx then
		ns.Print(("|cffff0000Calibrate:|r no world position for %s (token=%s).")
			:format(tostring(sel[1]), tostring(unit)))
		return
	end
	if RTS_HasCam ~= 1 then return end

	local depth, rc, uc = self:CamCoords(bx, by, bz, true)
	if not depth or rc == 0 or uc == 0 then
		ns.Print("|cffff0000Calibrate:|r bad geometry, try a unit off to the side.")
		return
	end

	local mx, my = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	local w, h = GetScreenWidth(), GetScreenHeight()
	local ndcx = ((mx / s) / w) * 2 - 1
	local ndcy = ((my / s) / h) * 2 - 1

	local sx = ndcx / (rc / depth)
	local sy = ndcy / (uc / depth)

	-- SE RECHAZA UNA MEDIDA IMPOSIBLE EN VEZ DE GUARDARLA.
	--
	-- Esto resuelve la escala con UNA muestra y supone que el cursor estaba
	-- justo encima de la unidad al pulsar la tecla. Si no lo estaba -- que es lo
	-- normal cuando la tecla se pulsa sin saber lo que hace -- el resultado es
	-- basura, se guarda, y la proyeccion queda desviada hasta que alguien
	-- adivine que fue eso. Ya paso.
	--
	-- La derivada del FOV es geometria y no depende de la punteria, asi que
	-- sirve de arbitro: una medida buena cae a menos del 1% de ella.
	local dx, dy = self:Derived()
	if dx and dy and dx > 0 and dy > 0 then
		local off = math.max(math.abs(sx / dx - 1), math.abs(sy / dy - 1))
		if off > OVERRIDE_TOL then
			ns.Print(("|cffff0000Calibrate:|r sale un %d%% de la escala derivada " ..
			          "del FOV -- eso no es una medida, es el cursor fuera de %s."):format(
				math.floor(off * 100), tostring(sel[1])))
			ns.Print("|cff888888Nada guardado. Pon el cursor ENCIMA del modelo y " ..
			         "vuelve a pulsar, o dejalo como esta.|r")
			return
		end
	end

	self.SX, self.SY = sx, sy
	self.DEPTH_BIAS = 0        -- this is a pure-scale solve; drop any fitted bias
	self.autoIntrinsics = false -- an explicit override of the derived scales
	self.overrideChecked = true -- reciEn comprobada contra la derivada

	RTSCommandDB.SX, RTSCommandDB.SY = self.SX, self.SY
	RTSCommandDB.DEPTH_BIAS = 0
	RTSCommandDB.forceScale = true
	ns.Print(("|cff00ff00Calibrated|r SX=%.4f SY=%.4f (guardado). " ..
	          "|cffffff00/rts cal auto|r lo deshace."):format(self.SX, self.SY))
end

--- Marker pool -------------------------------------------------------------

local pool = {}
local overlay

local function Overlay()
	if overlay then return overlay end
	overlay = CreateFrame("Frame", "RTSMarkerOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("HIGH")
	return overlay
end

local function GetMarker(i)
	if pool[i] then return pool[i] end
	local t = Overlay():CreateTexture(nil, "OVERLAY")
	-- Solid white square we tint per marker -- clean and unambiguous, unlike the
	-- minimap blip atlas (which packed two coloured blips into one cell).
	t:SetTexture("Interface\\Buttons\\WHITE8X8")
	t:Hide()
	pool[i] = t
	return t
end

local function PlaceMarker(i, wx, wy, wz, r, g, b, size)
	local t = GetMarker(i)
	local sx, sy = M:Project(wx, wy, wz)
	if not sx then t:Hide() return false end

	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	t:SetVertexColor(r or 1, g or 1, b or 0)
	t:SetWidth(size or 16)
	t:SetHeight(size or 16)
	t:Show()
	return true
end

--- Head markers ------------------------------------------------------------
-- A triangle floating over a unit's head. The art is the raid-target atlas --
-- icon 4 is already the green triangle -- but drawn by us as a plain texture at
-- a size we choose, instead of the client's in-world icon, which cannot be
-- scaled and swallows the screen up close.
--
-- Size shrinks with distance like a real world object, but is clamped at both
-- ends: unclamped it is a speck across a field and a billboard in melee range.

local TRI_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
-- Atlas is 4x2 cells of 0.25; icon 4 (triangle) is the last cell of the top row.
local TRI_L, TRI_R, TRI_T, TRI_B = 0.75, 1.0, 0.0, 0.25

-- PARKED 2026-08-14. Your own units are marked by the green model tint the DLL
-- applies (rts_core >= 0.6.0), which the client renders and occludes properly,
-- so the head triangle is off by default. The code stays because it is the only
-- way to mark something the client will not tint -- a creature, a corpse, a
-- destination -- and `/rts tri` brings it back. Bumping `version` discards saved
-- settings from earlier defaults.
M.tri = {
	version = 3,
	enabled = false,   -- parked: the green model tint marks your units instead
	mobs    = false,   -- creatures (published type 3) -- diagnostic only
	sel     = true,    -- units selected in the addon
	height  = 2.6,     -- yards above the unit's feet
	scale   = 700,     -- pixel size at 1 yard; divided by distance
	min     = 12,
	max     = 40,
}

local tripool = {}

local function GetTriangle(i)
	if tripool[i] then return tripool[i] end
	local t = Overlay():CreateTexture(nil, "OVERLAY")
	t:SetTexture(TRI_TEXTURE)
	t:SetTexCoord(TRI_L, TRI_R, TRI_T, TRI_B)
	t:Hide()
	tripool[i] = t
	return t
end

-- Places triangle `i` over (wx,wy,wz). Returns the next free index, unchanged
-- if the point is behind the camera.
local function PlaceTriangle(i, wx, wy, wz)
	local depth = M:CamCoords(wx, wy, wz)
	if not depth then return i end
	local sx, sy = M:Project(wx, wy, wz)
	if not sx then return i end

	local cfg = M.tri
	local size = cfg.scale / depth
	if size < cfg.min then size = cfg.min elseif size > cfg.max then size = cfg.max end

	local t = GetTriangle(i)
	t:ClearAllPoints()
	t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	t:SetWidth(size)
	t:SetHeight(size)
	t:Show()
	return i + 1
end

-- Guids currently selected in the addon, as a set.
local function SelectedGuids()
	local set = {}
	for _, name in ipairs(ns.Selection:Get()) do
		local unit = ns.Selection:UnitFor(name)
		local guid = unit and UnitGUID(unit)
		if guid then set[string.upper(guid)] = true end
	end
	return set
end

--- Unit position lookup ----------------------------------------------------
-- The DLL publishes the nearest units -- players AND creatures -- as
-- RTS_U{i}G/X/Y/Z/T + RTS_UN. The nearest units are the ones published, but the
-- list is then ordered by guid so the indices stay put while units move around
-- each other -- see Channel.lua. Build a guid -> position map so we
-- can find any unit's world spot. T is 4 for players, 3 for creatures, and nil
-- against a DLL older than 0.5.0 (in which case only players are published).

local function NormGuid(g)
	if not g then return nil end
	return string.upper(g)
end

local function BuildUnitMap()
	local map = {}
	local count = RTS_UN or 0
	for i = 1, count do
		local g = _G["RTS_U" .. i .. "G"]
		if g then
			map[NormGuid(g)] = {
				x = _G["RTS_U" .. i .. "X"],
				y = _G["RTS_U" .. i .. "Y"],
				z = _G["RTS_U" .. i .. "Z"],
				t = _G["RTS_U" .. i .. "T"],   -- 3 = creature, 4 = player
			}
		end
	end
	return map
end

--- Motion prediction -------------------------------------------------------
-- The DLL publishes unit positions at ~30 Hz; a moving model renders at 60 fps
-- and gets ahead of the last published sample, so a ring drawn at the raw
-- published position visibly trails. We track the last two DISTINCT samples per
-- unit, derive a velocity, and extrapolate to "now" so the ring sits on the
-- moving model. Extrapolation is clamped so a sudden stop overshoots only
-- briefly before the next sample corrects it.

M.track = {}

function M:SampleUnits()
	local now = GetTime()
	local map = BuildUnitMap()
	-- forget units no longer published
	for guid in pairs(self.track) do
		if not map[guid] then self.track[guid] = nil end
	end
	for guid, pos in pairs(map) do
		local t = self.track[guid]
		if not t then
			self.track[guid] = {
				px = pos.x, py = pos.y, pz = pos.z, pt = now,
				cx = pos.x, cy = pos.y, cz = pos.z, ct = now,
			}
		elseif pos.x ~= t.cx or pos.y ~= t.cy or pos.z ~= t.cz then
			t.px, t.py, t.pz, t.pt = t.cx, t.cy, t.cz, t.ct
			t.cx, t.cy, t.cz, t.ct = pos.x, pos.y, pos.z, now
		end
	end
	return map
end

function M:PredictedPos(guid)
	local t = self.track[NormGuid(guid)]
	if not t then return nil end

	local dt = t.ct - t.pt
	local vx, vy, vz = 0, 0, 0
	if dt > 0.001 then
		vx = (t.cx - t.px) / dt
		vy = (t.cy - t.py) / dt
		vz = (t.cz - t.pz) / dt
	end

	local ahead = GetTime() - t.ct
	if ahead > 0.20 then ahead = 0.20 end   -- cap overshoot on stops

	return t.cx + vx * ahead, t.cy + vy * ahead, t.cz + vz * ahead
end

--- Cursor reticle ----------------------------------------------------------
-- Rings under selected units were removed in favour of the head triangles: a
-- ground ring reads as clutter at the feet of a group and is hard to see over
-- grass, while a triangle sits clear of the model. DrawRing survives because
-- the cursor aim point still uses it.

local RING_POINTS = 14
local RING_RADIUS = 1.6   -- yards; a tight ring hugging the unit's feet

-- Draws a ring of dots on the ground at (wx,wy,wz). Returns the next marker idx.
local function DrawRing(idx, wx, wy, wz, r, g, b, size)
	for k = 0, RING_POINTS - 1 do
		local a = (k / RING_POINTS) * 2 * math.pi
		PlaceMarker(idx, wx + math.cos(a) * RING_RADIUS,
		                 wy + math.sin(a) * RING_RADIUS, wz, r, g, b, size or 7)
		idx = idx + 1
	end
	return idx
end

--- Cursor halo -------------------------------------------------------------
-- The aim point for orders, coloured by what the click would DO, so the meaning
-- is readable without clicking to find out. The colour comes from the client's
-- own mouseover, which is the same judgement the client makes when it decides
-- which cursor to show, so the halo and the cursor can never disagree.

-- The art is white so SetVertexColor can tint it; style 0 is the dot ring that
-- predates the textures and still works if a file goes missing.
--
-- Style 1 needs no rotating to "face the camera": the quad is screen-aligned, so
-- its bottom edge is by construction the edge nearest the viewer, whichever way
-- the camera is pointing. Rotation would only be needed to align the halo with
-- something in the WORLD, like the player's facing.
M.halo = {
	style  = 1,
	size   = 3.0,       -- yards across
	colors = {
		move     = { 0.20, 1.00, 0.30 },
		attack   = { 1.00, 0.20, 0.20 },
		interact = { 1.00, 0.65, 0.10 },
	},
	styles = {
		[0] = { name = "dot ring" },
		-- ADD for the glow: it is light, and light adds to what is behind it.
		[1] = { name = "diffuse arc",
		        texture = "Interface\\AddOns\\RTSCommand\\halo-01.tga",
		        blend = "ADD" },
		-- BLEND for the solid ring: ADD would wash out its translucent fill.
		[2] = { name = "ring",
		        texture = "Interface\\AddOns\\RTSCommand\\halo-02.tga",
		        blend = "BLEND" },
	},
}

local haloTex
local haloStyle   -- which style haloTex is currently configured for

-- What a click at the cursor would mean right now.
function M:CursorMode()
	if UnitExists("mouseover") then
		if UnitCanAttack("player", "mouseover") then return "attack" end
		return "interact"
	end

	-- No mouseover means RTS mode, where the catcher frame hides it. Fall back
	-- to the projected pick plus the server's verdict on what that guid is.
	if ns.RTSMode and ns.RTSMode.active then
		local mx, my = GetCursorPosition()
		local s = UIParent:GetEffectiveScale()
		local hit = ns.RTSMode:HostileAt(mx / s, my / s)
		if hit then
			local kind = ns.RTSMode:KindOf(hit.guid)
			if kind == 1 then return "attack" end
			if kind == 2 then return "interact" end
		end
	end

	return "move"
end

-- Yards -> pixels at a given depth. The focal length in pixels is SX * width/2,
-- so this is exact rather than a fudge factor, and it follows FOV and resolution.
function M:YardsToPixels(yards, depth)
	local SX = self:Intrinsics()
	return yards * (SX * GetScreenWidth() * 0.5) / depth
end

-- Screen size of a circle of radius `r` yards lying FLAT on the ground at
-- (wx,wy,wz), as (width, height) in pixels.
--
-- A circle on the ground is not a circle on screen: it is an ellipse, squashed
-- vertically by how steeply the camera looks down. Drawing it as a square is
-- what makes a halo read as a sticker on the monitor instead of something lying
-- in the world. So instead of one size, measure two -- how far a yard reaches
-- ACROSS the view and how far it reaches INTO it -- by projecting the four
-- points and reading the distances off the screen. No trigonometry, no
-- assumptions about the camera; whatever the projection does to those points is
-- what happens to the halo.
--
-- The axes come out aligned to the screen because the WoW camera never rolls,
-- which is why plain width/height is enough and no texture-coordinate rotation
-- is involved.
function M:GroundEllipse(wx, wy, wz, r)
	-- Sideways axis: the camera's own right vector, which is already horizontal.
	-- Depth axis: the camera's forward, flattened onto the ground plane.
	local rx, ry = RTS_CamRightX, RTS_CamRightY
	local fx, fy = RTS_CamFwdX, RTS_CamFwdY

	local rl = math.sqrt(rx * rx + ry * ry)
	local fl = math.sqrt(fx * fx + fy * fy)
	-- Looking straight down, forward has no horizontal part left; the ground
	-- axis perpendicular to `right` is then any horizontal direction, and this
	-- one keeps the two axes square.
	if fl < 1e-4 then fx, fy, fl = -ry, rx, rl end
	if rl < 1e-4 then return nil end

	rx, ry = rx / rl * r, ry / rl * r
	fx, fy = fx / fl * r, fy / fl * r

	local ax, ay = self:Project(wx + rx, wy + ry, wz)
	local bx, by = self:Project(wx - rx, wy - ry, wz)
	local cx, cy = self:Project(wx + fx, wy + fy, wz)
	local dx, dy = self:Project(wx - fx, wy - fy, wz)
	if not (ax and bx and cx and dx) then return nil end

	local w = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	local h = math.sqrt((cx - dx) ^ 2 + (cy - dy) ^ 2)
	return w, h
end

-- Draws the halo at (wx,wy,wz). Returns the next free dot-pool index; the
-- textured path consumes none.
function M:DrawHalo(idx, wx, wy, wz)
	local c = self.halo.colors[self:CursorMode()] or self.halo.colors.move
	local style = self.halo.styles[self.halo.style] or self.halo.styles[0]

	if not style.texture then
		if haloTex then haloTex:Hide() end
		PlaceMarker(idx, wx, wy, wz, c[1], c[2], c[3], 14)
		return DrawRing(idx + 1, wx, wy, wz, c[1], c[2], c[3], 6)
	end

	if not haloTex then
		haloTex = Overlay():CreateTexture(nil, "ARTWORK")
	end
	if haloStyle ~= self.halo.style then
		haloStyle = self.halo.style
		haloTex:SetTexture(style.texture)
		haloTex:SetBlendMode(style.blend or "BLEND")
	end

	local depth = self:CamCoords(wx, wy, wz)
	local sx, sy = self:Project(wx, wy, wz)
	if not sx or not depth then haloTex:Hide() return idx end

	-- Perspective: wide across the view, short into it. Falls back to a circle
	-- only if a corner of the measurement went behind the camera.
	local w, h = self:GroundEllipse(wx, wy, wz, self.halo.size * 0.5)
	if not w then
		w = self:YardsToPixels(self.halo.size, depth)
		h = w
	end
	if h < 2 then h = 2 end   -- edge-on: keep a visible sliver rather than nothing

	haloTex:ClearAllPoints()
	haloTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx, sy)
	haloTex:SetWidth(w)
	haloTex:SetHeight(h)
	haloTex:SetVertexColor(c[1], c[2], c[3])
	haloTex:Show()
	return idx
end

function M:Update()
	self:UpdateTriangles(self.lastMap)
	if not self.enabled then return end

	local idx = 1

	local cx, cy, cz = self:CursorGroundPoint()
	if cx then
		self.cursor = { x = cx, y = cy, z = cz }
		idx = self:DrawHalo(idx, cx, cy, cz)
	else
		self.cursor = nil
		if haloTex then haloTex:Hide() end
	end

	for j = idx, #pool do pool[j]:Hide() end
end

-- A triangle over every mob, and over whatever you have selected. Positions are
-- the predicted ones, so the marker tracks a moving model instead of trailing
-- it by up to a publish interval.
function M:UpdateTriangles(map)
	local idx = 1
	local cfg = self.tri

	if cfg.enabled then
		local selected = cfg.sel and SelectedGuids() or nil
		for guid, pos in pairs(map or BuildUnitMap()) do
			local wanted = (cfg.mobs and pos.t == 3) or (selected and selected[guid])
			if wanted and pos.x then
				local x, y, z = self:PredictedPos(guid)
				if not x then x, y, z = pos.x, pos.y, pos.z end
				idx = PlaceTriangle(idx, x, y, z + cfg.height)
			end
		end
	end

	for j = idx, #tripool do tripool[j]:Hide() end
end

function M:ToggleTriangles()
	self.tri.enabled = not self.tri.enabled
	RTSCommandDB.tri = self.tri
	ns.Print("head triangles " .. (self.tri.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- The last computed cursor ground point, for order dispatch.
function M:GetCursorPoint()
	if self.cursor then return self.cursor.x, self.cursor.y, self.cursor.z end
	return self:CursorGroundPoint()
end

-- World position the DLL last published for a unit GUID, or nil.
function M:UnitWorld(guid)
	local pos = BuildUnitMap()[NormGuid(guid)]
	if pos and pos.x then return pos.x, pos.y, pos.z end
	return nil
end

-- Screen pixel for a unit GUID (its projected world position), or nil.
function M:UnitScreen(guid)
	local x, y, z = self:UnitWorld(guid)
	if not x then return nil end
	return self:Project(x, y, z)
end

--- Lifecycle ---------------------------------------------------------------

function M:Create()
	Overlay()
	-- OFF by default, 2026-08-16. A halo following the mouse pointer is not
	-- wanted: the cursor already says where it is, and once the ground circles
	-- under the units are the client's own, a UI blob tracking the pointer is
	-- the only thing left on screen that visibly swims. The aim point is still
	-- computed either way -- orders use CursorGroundPoint, not the drawing --
	-- so this only stops it being painted. /rts markers brings it back.
	self.enabled = false
	if RTSCommandDB and type(RTSCommandDB.markers) == "boolean" then
		self.enabled = RTSCommandDB.markers
	end

	-- Restore saved triangle settings field by field, so a saved table from an
	-- older version cannot drop a key the code now expects.
	if RTSCommandDB then
		if RTSCommandDB.halo and self.halo.styles[RTSCommandDB.halo] then
			self.halo.style = RTSCommandDB.halo
		end
		if RTSCommandDB.haloSize then self.halo.size = RTSCommandDB.haloSize end
	end

	local saved = RTSCommandDB and RTSCommandDB.tri
	if type(saved) == "table" and saved.version == self.tri.version then
		for k, v in pairs(self.tri) do
			if type(saved[k]) == type(v) then self.tri[k] = saved[k] end
		end
	end

	-- Two different rates on purpose. Sampling unit positions faster than the DLL
	-- publishes them buys nothing and allocates a table per pass, so it stays at
	-- the publish rate. DRAWING, though, has to happen every frame: the camera
	-- moves every frame, and a marker redrawn at 30 fps against a world rendered
	-- at 60+ visibly swims sideways whenever you turn. Motion prediction fills in
	-- the unit's position between samples.
	local acc, aimAcc = 0, 0
	Overlay():SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc >= 0.03 then
			acc = 0
			M.lastMap = M:SampleUnits()
		end
		M:Update()

		if M.aim.on then
			aimAcc = aimAcc + e
			if aimAcc >= 1 then
				aimAcc = 0
				M:AimLine()
			end
		end
	end)
end

--- La punteria: por que el punto de suelo sale donde sale --------------------
--
-- Una linea por segundo mientras esta encendido, para poder MOVER el raton y
-- leer el patron. Un solo tiro no distingue las dos averias de arriba: las dos
-- aciertan en el centro de la pantalla.
function M:AimLine()
	if RTS_HasCam ~= 1 then
		ns.Print("aim: |cffff0000sin camara|r (rts_core no publica)")
		return
	end

	local x, y, z = self:CursorGroundPoint()
	local a = self.aim
	local mx, my = self:CursorPixel()
	local w, h = GetScreenWidth(), GetScreenHeight()

	if RTS_CurHit ~= 1 then
		ns.Print(("aim: cursor %d,%d   |cffff8800el DLL no acerto|r (cielo o sin rayo)   -> %s")
			:format(mx, my, a.how))
	else
		-- El factor de encogimiento contra el centro de la pantalla es el numero
		-- que separa las dos averias: constante = fov/ventana mal, disparatado o
		-- sin sentido = otro cursor.
		local cx, cy = w * 0.5, h * 0.5
		local dcur = math.sqrt((mx - cx) ^ 2 + (my - cy) ^ 2)
		local dhit = a.px and math.sqrt((a.px - cx) ^ 2 + (a.py - cy) ^ 2) or 0
		local k = dcur > 1 and (dhit / dcur) or 0
		ns.Print(("aim: cursor %d,%d   impacto->pantalla %d,%d   d=%dpx  k=%.2f   %s")
			:format(mx, my, a.px or 0, a.py or 0, a.d or -1, k,
				a.ok and "|cff00ff00EXACTO|r" or "|cffff0000RECHAZADO|r"))
	end

	if x then
		local dist = math.sqrt((x - RTS_CamX) ^ 2 + (y - RTS_CamY) ^ 2 + (z - RTS_CamZ) ^ 2)
		ns.Print(("     punto %s: %.1f %.1f %.1f   a %.0f yardas de la camara")
			:format(a.how, x, y, z, dist))
	else
		ns.Print("     |cffff0000sin punto|r: ni impacto ni plano.")
	end
end

function M:AimToggle(arg)
	local n = tonumber(arg)
	if n then
		self.aim.tol = math.max(2, math.min(400, n))
		ns.Print(("aim: tolerancia |cffffff00%d|r unidades de UIParent."):format(self.aim.tol))
		return
	end

	self.aim.on = not self.aim.on
	if self.aim.on then
		ns.Print("|cff00ff00aim ON|r: una linea por segundo. Mueve el raton por la pantalla " ..
			"-- centro, esquinas, bordes -- y mira el patron.")
		ns.Print("  |cffffff00/rts aim <n>|r cambia la tolerancia, |cffffff00/rts aim|r lo apaga.")
		self:AimLine()
	else
		ns.Print("|cffff0000aim OFF|r")
	end
end

function M:Toggle()
	self.enabled = not self.enabled
	RTSCommandDB.markers = self.enabled
	if not self.enabled then
		for _, t in ipairs(pool) do t:Hide() end
		if haloTex then haloTex:Hide() end
	end
	ns.Print("cursor reticle " .. (self.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end
