--[[--------------------------------------------------------------------------
	Rails.lua -- los botones pequenos del cliente, en las dos barras verticales

	LOS DOS RAILES DE LOS EXTREMOS ERAN REMATE Y AHORA SON EL SITIO DE ESOS
	BOTONES. Izquierda los del mapa (mapa del mundo, rastreo, correo,
	calendario, acercar, alejar), que es el lado donde esta el minimapa; derecha
	la coleccion del personaje (ficha, hechizos, talentos, misiones, menu,
	bolsas), que es el lado de las ordenes.

	NO SON BOTONES NUESTROS: son los de Blizzard, alojados. `ToggleWorldMap`,
	`ToggleTalentFrame`, `ToggleSpellBook`, `ToggleQuestLog` y `ToggleGameMenu`
	estan PROTEGIDAS en 3.3.5a, asi que un boton propio que las llame da
	"blocked from an action only available to the Blizzard UI" y da igual que el
	click sea de verdad. Se le cambia el padre al boton del cliente y el click lo
	recibe el, en su codigo, sin nada nuestro por medio. Confirmado en juego en
	PRUEBAS-13 (A3, A4): funciona, y vuelven bien a su sitio al salir (A6-A8).

	EL NOMBRE DEL FRAME NO SE ADIVINA, SE PRUEBA. Cada hueco lleva una LISTA de
	nombres candidatos y se queda con el primero que exista, porque un nombre mal
	escrito -- como una ruta de textura que no existe -- no da error: no dibuja
	nada. `/rts rails` dice cual se resolvio y cual falta.

	EL TAMANO SALE DE LA FORMA DEL RAIL, no de un gusto. El hueco mide 78 de
	ancho por 452 de alto en unidades de dibujo, o sea que el ancho sobra (un
	boton mide 28) y el ALTO es lo escaso: seis a tamano nativo serian 348 px de
	pantalla en un rail de 254. Asi que se escala por la celda. `/rts rails
	scale <k>` lo fuerza a mano y `/rts rails` imprime los pixeles de pantalla
	que salen, para que el numero se vea en vez de discutirlo.

	LOS CINCO MICRO-BOTONES SON 1:2 Y LA CELDA ES CASI CUADRADA, asi que
	respetar su proporcion los dejaba a la MITAD de ancho que la bolsa -- visto
	en juego en PRUEBAS-16 (A2), y es la forma del arte, no un fallo de reparto.
	Un arte de 28x58 metido en una celda de 78x70 se topa con el alto y deja 50
	unidades de ancho sin usar.

	SE RECORTA EL GLIFO Y SE DIBUJA CUADRADO, y la parte que importa es COMO:

	  - NO SE TOCA EL ARTE DEL CLIENTE. Ni un SetTexCoord ni un anclaje en sus
	    texturas. Recolocar las texturas de un boton de Blizzard es facil de
	    hacer y dificil de DESHACER -- habria que guardar y devolver los
	    anclajes y tamanos de cuatro capas por boton -- y dejar la interfaz de
	    Blizzard un poco rara para siempre es exactamente lo que la regla dura
	    de este proyecto prohibe.
	  - EL BOTON DEL CLIENTE SE QUEDA, invisible (`SetAlpha(0)`) y del tamano de
	    la celda. Sigue recibiendo el click en su propio codigo, que es lo unico
	    que hace que esto funcione con `ToggleTalentFrame` y compania
	    protegidas; y el alfa no afecta al raton, asi que la diana es la celda
	    entera. El tooltip tambien sigue siendo el suyo.
	  - EL GLIFO LO DIBUJAMOS NOSOTROS con la ruta que le preguntamos a EL
	    (`GetNormalTexture():GetTexture()`), que es la regla de la etapa 5k: no
	    comprobar la constante, no tener constante.
	  - LO QUE SE DEVUELVE SON CUATRO ESCALARES: tamano, alfa, escala y los
	    margenes de click. Todo lo demas se queda como estaba porque no se toco.

	EL RECORTE NO SE ADIVINA DEL TODO, PERO CASI. El cliente da la primera
	pista el solo: estos botones traen `HitRectInsets` con 19 de margen ABAJO
	sobre 58 de alto, o sea que el propio cliente declara que el tercio inferior
	del arte es pedestal y no boton. Queda el cuadrado de arriba, que es donde
	esta el glifo. Aun asi hay cinco ventanas candidatas en una tabla y
	`/rts rails crop` pasa a la siguiente dejandola aplicada y guardada -- misma
	decision que los siete encuadres del retrato en la etapa 5j: una lectura
	convincente vale UNA prueba barata en juego, no maquinaria encima.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local R = {}
ns.Rails = R

R.active = false

--- Que va en cada rail ----------------------------------------------------
--
-- `names` en orden de preferencia. `short` es solo para `/rts rails`: aqui NO
-- hay etiquetas debajo -- en 78 unidades de ancho no cabe una palabra, y los
-- botones del cliente ya traen su propio tooltip.

-- `crop = true` = micro-boton 1:2, se le recorta el glifo y se dibuja cuadrado.
-- La bolsa NO lo lleva: ya es cuadrada y es la unica que salio bien en A2, asi
-- que es la referencia y no la que hay que arreglar.
local CHAR = {
	{ short = "Ficha",    names = { "CharacterMicroButton" }, crop = true },
	{ short = "Hechizos", names = { "SpellbookMicroButton" }, crop = true },
	{ short = "Talentos", names = { "TalentMicroButton" },    crop = true },
	{ short = "Misiones", names = { "QuestLogMicroButton" },  crop = true },
	{ short = "Menu",     names = { "MainMenuMicroButton" },  crop = true },
	{ short = "Bolsas",   names = { "MainMenuBarBackpackButton" } },
}

local MAP = {
	{ short = "Mapa",     names = { "MiniMapWorldMapButton", "WorldMapMicroButton" } },
	{ short = "Rastreo",  names = { "MiniMapTracking", "MiniMapTrackingFrame",
	                                "MiniMapTrackingButton" } },
	{ short = "Correo",   names = { "MiniMapMailFrame" } },
	{ short = "Fecha",    names = { "GameTimeFrame" } },
	{ short = "Acercar",  names = { "MinimapZoomIn" } },
	{ short = "Alejar",   names = { "MinimapZoomOut" } },
}

-- QUIEN VA EN QUE RAIL SE DECIDE AQUI Y EN UN SOLO SITIO. Las dos listas se
-- llaman por lo que SON (mapa, personaje) y no por donde estan, asi que
-- cambiarlas de lado es cambiar estas dos lineas y nada mas -- que es
-- exactamente lo que hizo falta el 2026-08-23.
local RAILS = {
	{ key = "railL", label = "mapa",      list = MAP },
	{ key = "railR", label = "personaje", list = CHAR },
}

local hosts = {}     -- key de rail -> Frame anfitrion
local kept  = {}     -- nombre de frame -> como estaba antes de que lo tocaramos
local dots  = {}     -- key .. i -> marca roja de "ese frame no existe"
local glyph = {}     -- nombre de frame -> nuestra textura del glifo

-- Escala forzada a mano, 0 = derivada de la celda.
R.scale = 0

--- LAS VENTANAS CANDIDATAS ------------------------------------------------
--
-- Cada una es {izq, der, arriba, abajo} en coordenadas de textura (0..1) sobre
-- el arte del micro-boton. El ancho va entero en todas: el arte es estrecho ya,
-- y lo que sobra esta ABAJO -- que es lo que dice el propio cliente con sus
-- `HitRectInsets` de 19 sobre 58, o sea que el 0,672 de arriba es boton y el
-- resto pedestal.
--
-- La 1 es la apuesta: un cuadrado desde arriba (28 de 58 = 0,483), que es lo
-- que hace que salgan del tamano exacto de la bolsa. Las otras cuatro existen
-- porque DONDE cae el glifo dentro de ese arte es lo unico que no se puede leer
-- desde fuera del juego, y una ronda de pruebas por intento sale carisima al
-- lado de un comando que las pasa en vivo.
--
-- LA VENTANA POR DEFECTO CAMBIO DE LADO EL 2026-08-27, y el porque merece
-- quedarse escrito porque el razonamiento de arriba era convincente y falso.
--
-- PRUEBAS-18 A1: "has recortado los iconos del rail derecho, pero has usado el
-- lado que no era y ahora se ven transparentes". Transparente no es "salio el
-- pedestal en vez del glifo": es que ahi no hay pixeles. O sea que la mitad con
-- dibujo es la de ABAJO, y el `HitRectInsets` de 19 -- que decia que el tercio
-- inferior no es pulsable -- no significaba lo que se dedujo de el.
--
-- Y esa es la leccion, otra vez la misma: `HitRectInsets` dice donde se puede
-- PULSAR, no donde esta el DIBUJO. Encadenar las dos cosas ("no es pulsable,
-- luego es pedestal, luego el glifo esta arriba") es razonar por analogia sobre
-- el cliente, que es exactamente lo que este proyecto lleva cuatro etapas
-- aprendiendo a no hacer. La constante era comprobable y no se comprobo.
--
-- Asi que ahora las candidatas van ancladas ABAJO y la 1 es la apuesta nueva.
-- Las de arriba se quedan al final: no cuestan nada, y si el arte resulta
-- llevar algo aprovechable ahi, `/rts rails crop` lo encuentra sin recompilar.
local CROPS = {
	{ 0, 1, 0.517, 1.000, why = "cuadrado desde ABAJO" },
	{ 0, 1, 0.422, 0.905, why = "cuadrado un poco mas arriba" },
	{ 0, 1, 0.328, 1.000, why = "abajo, mas alto que ancho (1,4:1)" },
	{ 0, 1, 0.259, 0.741, why = "cuadrado centrado en el arte" },
	{ 0, 1, 0.000, 1.000, why = "sin recortar (el 1:2 de siempre)" },
	{ 0, 1, 0.000, 0.483, why = "cuadrado desde arriba (el que salio vacio)" },
	{ 0, 1, 0.000, 0.672, why = "arriba sin el tercio de abajo" },
}

-- El sello de la tabla. Se sube cada vez que cambia el SIGNIFICADO de un
-- indice, no cada vez que se anade una entrada al final.
local CROP_GEN = 2

R.crop = 1

--- Resolver, guardar, alojar, devolver ------------------------------------

local function Resolve(spec)
	for _, n in ipairs(spec.names) do
		local f = _G[n]
		if f then
			spec.frame = n
			return f
		end
	end
	spec.frame = nil
	return nil
end

-- Como estaba ANTES. Entero -- padre, todos los anclajes, escala, estrato,
-- nivel y si se veia -- porque devolverlo "aproximadamente" es justo lo que
-- deja la interfaz de Blizzard un poco rara para siempre. Misma regla dura que
-- Camera con sus CVars y Chrome con los frames.
local function Capture(f)
	local pts = {}
	for i = 1, f:GetNumPoints() do
		local a, rel, b, dx, dy = f:GetPoint(i)
		pts[i] = { a, rel, b, dx or 0, dy or 0 }
	end
	-- Y LOS CUATRO ESCALARES QUE EL RECORTE CAMBIA. Van aqui y no en el camino
	-- del recorte porque `Capture` corre UNA vez, la primera: guardarlos donde
	-- se usan seria guardarlos en la segunda vuelta, cuando ya estan cambiados,
	-- y entonces "como estaba antes" seria "como lo dejamos".
	local k = {
		parent = f:GetParent(), points = pts, scale = f:GetScale(),
		strata = f:GetFrameStrata(), level = f:GetFrameLevel(), shown = f:IsShown(),
		w = f:GetWidth(), h = f:GetHeight(), alpha = f:GetAlpha(),
	}
	if type(f.GetHitRectInsets) == "function" then
		local l, r, t, b = f:GetHitRectInsets()
		k.hit = { l or 0, r or 0, t or 0, b or 0 }
	end
	return k
end

-- El boton del cliente pasa a ser una DIANA INVISIBLE del tamano de la celda y
-- el glifo lo dibujamos nosotros, recortado del mismo arte que el usa. Ver la
-- cabecera: nada de sus texturas se toca, asi que devolverlo son cuatro
-- escalares.
local function CropPark(spec, f, host, cell, w, h)
	local c = CROPS[R.crop] or CROPS[1]
	local l, r, t, b = c[1], c[2], c[3], c[4]

	-- ESCALA 1 A PROPOSITO: con el boton a su escala natural los
	-- desplazamientos de `SetPoint` van en unidades del anfitrion y no hay que
	-- dividir por nada. La escala existia para agrandar un arte que ahora
	-- agranda la textura, asi que aqui ya no tiene trabajo.
	f:SetScale(1)
	f:SetSize(cell.w, cell.h)
	f:SetAlpha(0)

	-- LOS MARGENES DE CLICK SE ANULAN. Son ABSOLUTOS (19 abajo), asi que sobre
	-- un boton redimensionado a la celda dejarian casi la mitad sin responder --
	-- y un boton que se ve y no se pulsa es peor que uno pequeno.
	if type(f.SetHitRectInsets) == "function" then f:SetHitRectInsets(0, 0, 0, 0) end

	f:SetPoint("CENTER", host, "TOPLEFT",
		cell.x + cell.w * 0.5, -(cell.y + cell.h * 0.5))

	-- LA RUTA SE LE PREGUNTA A EL. Es literalmente el dibujo que el cliente
	-- tiene en pantalla ahora mismo, asi que no puede estar mal -- y una ruta
	-- escrita a mano que no existe no da error: no dibuja nada.
	local nt = f.GetNormalTexture and f:GetNormalTexture()
	local path = nt and nt.GetTexture and nt:GetTexture()

	-- NADA DE `SetParent` sobre la textura. Un `spec` pertenece a UN rail, asi
	-- que su anfitrion no cambia nunca y la textura se crea ya en el suyo --
	-- que ademas evita apostar a que `Texture:SetParent` exista en 3.3.5a, que
	-- es de las que hay que comprobar contra el cliente y no contra internet.
	local g = glyph[spec.frame]
	if not g then
		g = host:CreateTexture(nil, "ARTWORK")
		glyph[spec.frame] = g
	end

	if not path then
		-- SIN ARTE SE VUELVE AL CAMINO DE ANTES, entero. Dejar el boton visible
		-- pero ya estirado a la celda seria lo peor de las dos opciones: el arte
		-- 1:2 deformado a cuadrado. Asi que se le devuelve su tamano y se ajusta
		-- por proporcion, que es exactamente lo que hacen los del otro rail.
		g:Hide()
		spec.noArt = true

		f:SetSize(w, h)
		f:SetAlpha(kept[spec.frame].alpha or 1)
		local kn = R.scale
		if not kn or kn <= 0 then kn = math.min(cell.w / w, cell.h / h) end
		f:SetScale(kn)
		f:ClearAllPoints()
		f:SetPoint("CENTER", host, "TOPLEFT",
			(cell.x + cell.w * 0.5) / kn, -(cell.y + cell.h * 0.5) / kn)
		spec.k, spec.w, spec.h = kn, w, h
		return
	end
	spec.noArt = nil

	g:SetTexture(path)
	g:SetTexCoord(l, r, t, b)

	-- LA PROPORCION DEL RECORTE, no la del arte. El trozo mide (w*ancho) por
	-- (h*alto) en unidades del boton, y se mete en la celda por el lado que peor
	-- va -- igual que antes, solo que ahora el trozo es casi cuadrado y por eso
	-- llena la celda en vez de quedarse a la mitad.
	local sw = w * math.max(0.01, r - l)
	local sh = h * math.max(0.01, b - t)
	local k = R.scale
	if not k or k <= 0 then k = math.min(cell.w / sw, cell.h / sh) end

	g:ClearAllPoints()
	g:SetSize(sw * k, sh * k)
	g:SetPoint("CENTER", host, "TOPLEFT",
		cell.x + cell.w * 0.5, -(cell.y + cell.h * 0.5))
	g:Show()

	spec.k, spec.w, spec.h = k, sw, sh
end

-- Lo guardado se apunta la PRIMERA vez y se borra al devolverlo. Si en la
-- segunda vuelta se guardara "como estaba" cuando ya estaba movido, se
-- quedarian en el rail para siempre.
local function Park(spec, host, cell)
	local f = Resolve(spec)
	spec.found = f ~= nil
	if not f then
		spec.parked = false
		return false
	end

	local key = spec.frame
	if not kept[key] then kept[key] = Capture(f) end

	local ok, err = pcall(function()
		f:SetParent(host)
		f:ClearAllPoints()

		-- EL TAMANO NATIVO SALE DE LO GUARDADO, no del frame. Una segunda vuelta
		-- (cambiar `grow`, cambiar de resolucion) lo encuentra ya redimensionado
		-- por la vuelta anterior, y medir eso seria medir nuestro propio
		-- resultado -- que se encoge un poco mas en cada redistribucion.
		local w = kept[key].w or f:GetWidth()
		local h = kept[key].h or f:GetHeight()

		if spec.crop then
			CropPark(spec, f, host, cell, w, h)
		else
			-- Por el lado que peor va, que aqui es SIEMPRE el alto: un boton
			-- mide 28x58 y la celda 78x70, asi que el ancho sobra con holgura y
			-- el alto no llega. Se calcula igual por los dos lados para que siga
			-- siendo correcto si el rail cambia de forma.
			local k = R.scale
			if not k or k <= 0 then
				k = 1
				if w and h and w > 0 and h > 0 then
					k = math.min(cell.w / w, cell.h / h)
				end
			end
			f:SetScale(k)
			spec.k, spec.w, spec.h = k, w, h

			-- OJO CON LAS UNIDADES: los desplazamientos de SetPoint van en la
			-- escala DEL HIJO, no en la del padre. Sin dividir por k, un boton
			-- escalado x1,2 aterriza a 1,2 veces la distancia pedida -- fuera
			-- del rail.
			f:SetPoint("CENTER", host, "TOPLEFT",
				(cell.x + cell.w * 0.5) / k, -(cell.y + cell.h * 0.5) / k)
		end

		-- El arte del rail es OPACO donde esta el hueco, asi que lo alojado va
		-- por encima o no se ve. Mismo tropiezo que costo el minimapa.
		f:SetFrameStrata(host:GetFrameStrata())
		f:SetFrameLevel(host:GetFrameLevel() + 5)
		f:Show()
	end)

	spec.parked = ok
	if not ok then
		spec.err = tostring(err)
		ns.Print(("|cffff0000No se pudo alojar %s|r: %s"):format(key, spec.err))
	end
	return ok
end

local function Unpark(spec)
	local key = spec.frame
	local f = key and _G[key]
	local k = key and kept[key]
	if not f or not k then return end
	kept[key] = nil
	spec.parked = false

	local g = glyph[key]
	if g then g:Hide() end

	pcall(function()
		f:SetParent(k.parent)
		f:ClearAllPoints()
		for _, pt in ipairs(k.points) do
			if pt[2] then
				f:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
			else
				f:SetPoint(pt[1], pt[4], pt[5])
			end
		end
		f:SetScale(k.scale)
		f:SetFrameStrata(k.strata)
		f:SetFrameLevel(k.level)

		-- Los cuatro escalares del recorte. Se devuelven SIEMPRE, tambien a los
		-- que no lo llevan: `Capture` los guardo tal cual, asi que ponerlos de
		-- vuelta es una identidad para esos y una reparacion para los otros --
		-- y una rama menos que pueda olvidarse.
		if k.w and k.h then f:SetSize(k.w, k.h) end
		if k.alpha then f:SetAlpha(k.alpha) end
		if k.hit and type(f.SetHitRectInsets) == "function" then
			f:SetHitRectInsets(k.hit[1], k.hit[2], k.hit[3], k.hit[4])
		end

		if k.shown then f:Show() else f:Hide() end
	end)
end

--- Un hueco que no se pudo llenar ----------------------------------------
--
-- Un frame que no existe con ninguno de sus nombres dejaria la casilla vacia y
-- callada, que es el fallo silencioso que este proyecto persigue desde la etapa
-- 5i. Una marca roja en su sitio, y `/rts rails` dice el nombre.
local function Dot(key, i, host, cell, show)
	local id = key .. i
	local t = dots[id]
	if not t then
		t = host:CreateTexture(nil, "OVERLAY")
		t:SetTexture(1, 0.2, 0.2, 0.7)
		dots[id] = t
	end
	if not show then t:Hide() return end
	t:ClearAllPoints()
	t:SetPoint("CENTER", host, "TOPLEFT", cell.x + cell.w * 0.5, -(cell.y + cell.h * 0.5))
	t:SetSize(10, 10)
	t:Show()
end

--- Distribuir -------------------------------------------------------------

function R:Layout()
	if not self.active then return end

	for _, rail in ipairs(RAILS) do
		local host = hosts[rail.key]
		if host then
			local cells = ns.Bar:Cells(rail.key)
			for i, spec in ipairs(rail.list) do
				local c = cells[i]
				if c then
					local ok = Park(spec, host, c)
					Dot(rail.key, i, host, c, not spec.found)
					if not ok and spec.found then Dot(rail.key, i, host, c, true) end
				else
					-- Menos celdas que botones: el rail se ha quedado corto.
					-- No se aloja nada ahi, que es mejor que un boton flotando
					-- sobre el arte.
					Unpark(spec)
					Dot(rail.key, i, host, { x = 0, y = 0, w = 0, h = 0 }, false)
				end
			end
			host:Show()
		end
	end
end

--- Entrar y salir ---------------------------------------------------------

function R:Enter()
	hosts.railL = ns.Bar:SlotFrame("railL")
	hosts.railR = ns.Bar:SlotFrame("railR")
	if not hosts.railL and not hosts.railR then return end

	self.active = true
	self:Layout()

	if not self.wired then
		self.wired = true
		-- Cambiar `grow` o la resolucion cambia el TAMANO de la celda, asi que
		-- la escala de cada boton cambia con ella. Colocarlos una vez y
		-- olvidarse los dejaria del tamano de la primera vez.
		ns.Bar:OnLayout(function() R:Layout() end)
	end
end

function R:Leave()
	self.active = false

	-- Los botones vuelven a donde estaban ANTES de esconder los railes: si el
	-- padre siguiera siendo nuestro anfitrion, un Hide() sobre el se los
	-- llevaria por delante y volverian invisibles al salir del modo RTS -- que
	-- es peor que el fallo que esto arregla.
	for _, rail in ipairs(RAILS) do
		for _, spec in ipairs(rail.list) do Unpark(spec) end
	end
	for _, t in pairs(dots) do t:Hide() end
	for _, t in pairs(glyph) do t:Hide() end
	for _, f in pairs(hosts) do if f then f:Hide() end end
end

--- Los mandos -------------------------------------------------------------

function R:SetScale(arg)
	local n = tonumber(arg)
	if arg == "auto" or arg == "0" then
		self.scale = 0
		ns.Print("railes: escala |cffffff00automatica|r (la celda decide).")
	elseif n and n >= 0.3 and n <= 4 then
		self.scale = n
		ns.Print(("railes: escala |cffffff00%.2f|r a mano."):format(n))
	else
		ns.Print("Uso: |cffffff00/rts rails scale <0.3-4|auto>|r")
		return
	end
	RTSCommandDB.railScale = self.scale
	self:Layout()
	self:Status()
end

-- LA VENTANA DEL GLIFO. Sin argumento pasa a la siguiente y la deja aplicada,
-- que es el gesto util: mirar, decidir, seguir. Con dos numeros la fija a mano,
-- porque en cuanto una de las cinco se acerca lo que falta es afinarla y no
-- elegir otra vez de la lista.
function R:SetCrop(arg)
	arg = tostring(arg or ""):lower()

	local t, b = arg:match("^([%d%.]+)%s+([%d%.]+)$")
	if t then
		t, b = tonumber(t), tonumber(b)
		if not t or not b or b <= t or t < 0 or b > 1 then
			ns.Print("|cffff0000Ventana mala.|r Arriba y abajo entre 0 y 1, y " ..
				"abajo mayor que arriba.")
			return
		end
		-- Se mete al FINAL de la lista y se elige, para que el numero afinado
		-- sobreviva a un `/rts rails crop` de mas y se pueda comparar con las
		-- cinco de fabrica sin perderlo.
		CROPS[#CROPS + 1] = { 0, 1, t, b, why = "a mano" }
		self.crop = #CROPS
	elseif arg == "" or arg == "next" or arg == "siguiente" then
		self.crop = (self.crop % #CROPS) + 1
	else
		local n = tonumber(arg)
		if n and CROPS[n] then
			self.crop = n
		else
			ns.Print(("Uso: |cffffff00/rts rails crop [1-%d|<arriba> <abajo>]|r " ..
				"(sin nada, pasa a la siguiente)"):format(#CROPS))
			return
		end
	end

	RTSCommandDB.railCrop = self.crop
	RTSCommandDB.railCropGen = CROP_GEN
	self:Layout()

	local c = CROPS[self.crop]
	ns.Print(("railes: ventana |cffffff00%d/%d|r -- %s (arriba %.3f, abajo %.3f)."):format(
		self.crop, #CROPS, c.why, c[3], c[4]))
	ns.Print("Si el glifo sale cortado o descentrado: |cffffff00/rts rails crop|r " ..
		"otra vez, o |cffffff00/rts rails crop <arriba> <abajo>|r. " ..
		"Dime la buena y la bajo al codigo como la 1.")
end

-- Pixeles FISICOS de una medida en unidades del boton ya alojado. La cuenta es
-- la misma que HUD:ActionButtonPixels -- unidades * escalaEfectiva *
-- (altoFisico/768) -- y esta escrita una vez aqui porque es el numero que se
-- discute cuando alguien dice que los botones son pequenos.
local function Px(f, units)
	if not f or not units then return nil end
	local sc = f:GetEffectiveScale() or 1
	local phys = (ns.HUD and ns.HUD.pixels) or 768
	return units * sc * (phys / 768)
end

function R:Status()
	ns.Print(("railes: mapa a la |cffffff00izquierda|r, personaje a la " ..
		"|cffffff00derecha|r. Escala %s."):format(
		(self.scale and self.scale > 0) and ("%.2f a mano"):format(self.scale) or "automatica"))

	for _, rail in ipairs(RAILS) do
		local host = hosts[rail.key]
		local cells = host and ns.Bar:Cells(rail.key) or {}
		local c = cells[1]
		ns.Print(("|cff88ccff%s|r (%s): %d celdas de %s"):format(
			rail.key, rail.label, #cells,
			c and ("%dx%d de dibujo"):format(c.w, c.h) or "?"))

		for i, spec in ipairs(rail.list) do
			local px = ""
			local f = spec.frame and _G[spec.frame]
			local pw, ph = Px(f, spec.w), Px(f, spec.h)
			if pw and ph then px = ("  ~%dx%d px"):format(pw, ph) end
			ns.Print(("   %d |cffffff00%-9s|r %s%s"):format(i, spec.short,
				spec.frame and ("|cff00ff00" .. spec.frame .. "|r" ..
					(spec.parked and " alojado" or " |cffff8800sin alojar|r"))
				or ("|cffff0000no existe: " .. table.concat(spec.names, " / ") .. "|r"),
				px))
			if spec.err then ns.Print("      |cffff0000" .. spec.err .. "|r") end
		end
	end
	local c = CROPS[self.crop] or CROPS[1]
	ns.Print(("ventana del glifo: |cffffff00%d/%d|r -- %s (arriba %.3f, abajo %.3f). " ..
		"Solo la usan los cinco micro-botones; la bolsa va entera."):format(
		self.crop, #CROPS, c.why, c[3], c[4]))

	ns.Print("Si uno sale |cffff0000no existe|r, el nombre esta mal y se cambia " ..
		"en CHAR/MAP, en Rails.lua. El tamano: |cffffff00/rts rails scale <k>|r, " ..
		"el recorte: |cffffff00/rts rails crop|r.")
end

function R:Load()
	local n = tonumber(RTSCommandDB and RTSCommandDB.railScale)
	-- Acotado AL LEERLO, no solo al escribirlo: las SavedVariables no olvidan
	-- ninguna clave y sobreviven a la version que la escribio.
	if n and n >= 0.3 and n <= 4 then self.scale = n else self.scale = 0 end

	-- La ventana igual, y aqui importa mas: lo guardado es un INDICE en una
	-- tabla que puede haber cambiado de tamano entre versiones. Un 7 de una
	-- lista que hoy tiene cinco no es un valor exagerado que se recorte, es
	-- basura, y vuelve al de fabrica -- misma distincion que `share` y `grow`.
	--
	-- Y UN INDICE VALIDO PUEDE SEGUIR SIENDO BASURA, que es el caso de hoy: el
	-- 2026-08-27 la tabla cambio de LADO -- las mismas cinco posiciones, otras
	-- ventanas -- asi que un 3 guardado ayer sigue estando dentro de rango y ya
	-- no significa lo mismo. Comprobar el rango no basta cuando lo que cambia es
	-- el SIGNIFICADO, asi que la tabla lleva sello y lo guardado con otro sello
	-- se tira. Misma familia que el `grow = 688` de la etapa 5j y que el
	-- `camHold` que sobrevivio a la funcion que lo leia.
	local c = tonumber(RTSCommandDB and RTSCommandDB.railCrop)
	if c and CROPS[c] and RTSCommandDB.railCropGen == CROP_GEN then
		self.crop = c
	else
		self.crop = 1
	end
	if RTSCommandDB then RTSCommandDB.railCropGen = CROP_GEN end
end

-- SE APUNTA SOLO. `Bar` no nombra a ningun panel desde 2026-09-02: llama a
-- `Enter`/`Leave` sobre los que se hayan registrado, asi que anadir uno nuevo
-- ya no obliga a editar el fichero del arte. Ver `Bar:Register`.
ns.Bar:Register(R)

