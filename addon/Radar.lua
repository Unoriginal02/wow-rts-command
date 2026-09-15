--[[
	Radar.lua -- el punto del MAPA DEL MUNDO que dice donde esta la camara.

	En modo RTS la camara se va a volar y el personaje se queda donde estaba,
	asi que abrir el mapa no contesta la pregunta que uno tiene: no marca donde
	estas MIRANDO, marca donde tienes el cuerpo. Esto pone ahi un punto ambar en
	la posicion de la camara. Nada mas.

	EMPEZO EN EL MINIMAPA Y AHI NO VALIA. El 2026-09-15 se hizo primero sobre el
	minimapa, que era el camino barato -- una resta de posiciones y la escala del
	zoom, sin necesidad de saber en que zona estas. Se descarto el mismo dia: el
	minimapa alcanza 200 o 400 yardas, y una camara RTS se sale de eso en dos
	segundos, asi que el punto vivia pegado al borde diciendo poco mas que "por
	ahi". El mapa grande es el que tiene sitio para la respuesta.

	=== LO QUE HACE FALTA, Y DE DONDE SALE ==================================

	El DLL publica la camara en coordenadas del MUNDO (`RTS_CamX/Y`, yardas), y
	el mapa quiere una coordenada NORMALIZADA de 0 a 1 dentro de la zona que se
	esta ensenando. Pasar de una a otra necesita el rectangulo de esa zona en
	yardas, y ESO NO LO DA NINGUNA API de este cliente: es el motivo por el que
	existe Astrolabe, la libreria que TomTom y Carbonite llevan dentro solo para
	arrastrar esa tabla a mano.

	Pero el cliente SI lo tiene, en `DBFilesClient\WorldMapArea.dbc`, que es de
	donde sale la tabla de abajo -- leida del `patch-esES-3.MPQ` de este cliente,
	no copiada de ningun addon. Cada fila trae, por este orden:

	    id, mapID, areaID, areaName, locLeft, locRight, locTop, locBottom, ...

	y `areaName` es exactamente la cadena que devuelve `GetMapInfo()` -- con sus
	erratas incluidas, que es la prueba de que son el mismo dato: Orgrimmar se
	llama "Ogrimmar" en los dos sitios.

	En coordenadas del mundo de este cliente +X es NORTE y +Y es OESTE, asi que
	los cuatro numeros del DBC son:

	    izquierda / derecha  ->  el eje Y (oeste-este), o sea el ANCHO del mapa
	    arriba    / abajo    ->  el eje X (norte-sur),  o sea el ALTO

	    mx = (izquierda - camY) / ancho
	    my = (arriba    - camX) / alto

	Que la lectura de los campos es la correcta lo dijo la propia tabla antes de
	escribir una linea de Lua: las 105 filas que traen rectangulo dan ancho/alto
	= 1.50 clavado, que es la proporcion de todas las imagenes de mapa del
	cliente (1002 x 668). Con los campos cruzados saldria 0.67.

	=== Y ADEMAS SE COMPRUEBA SOLA, CADA FRAME =============================

	La misma cuenta se le hace AL HEROE, cuya posicion normalizada el cliente si
	da (`GetPlayerMapPosition`). Si las dos no coinciden, el punto no se dibuja.

	Eso cubre de una vez los dos modos de fallar, que desde fuera se ven igual:
	que la fila de la tabla no sea la que toca, y que el jugador haya paseado el
	mapa hasta OTRA zona -- donde las coordenadas de la camara no significan
	nada. Un punto que se esconde es honesto; un punto en el sitio equivocado de
	un mapa que no es se lee como una posicion buena.

	=== LO QUE NO CUBRE ====================================================

	Los mapas por PLANTAS (mazmorras, Dalaran) van por otro DBC y otras
	coordenadas, asi que ahi no hay punto. Son tres filas sin rectangulo en el
	propio WorldMapArea -- Dalaran, TheNexus y UtgardeKeep -- mas todo lo que
	tenga `GetCurrentMapDungeonLevel() > 0`. `/rts punto` lo dice con su nombre
	en vez de dejarte mirando un mapa sin punto.
]]

local ADDON, ns = ...

local R = {}
ns.Radar = R

R.enabled = true

--- El rectangulo de cada mapa, en yardas ----------------------------------
--
-- { locLeft, locTop, locLeft - locRight, locTop - locBottom }
--   la Y del borde oeste, la X del borde norte, el ancho y el alto.
--
-- Sacada de `DBFilesClient\WorldMapArea.dbc` del cliente (ver la cabecera).
-- Las tres filas que el DBC trae con el rectangulo a cero -- Dalaran, TheNexus
-- y UtgardeKeep, que son mapas por plantas -- no estan: ahi la cuenta seria una
-- division por cero, y no tenerlas es lo que hace que el punto se esconda solo.

local ZONE = {
	["Ahnkahet"]           = {     -233.3,     850.0,     972.9,    647.9 },
	["Alterac"]            = {      783.3,    1500.0,    2800.0,   1866.7 },
	["AlteracValley"]      = {     1781.2,    1085.4,    4237.5,   2825.0 },
	["Arathi"]             = {     -866.7,    -133.3,    3600.0,   2400.0 },
	["ArathiBasin"]        = {     1858.3,    1508.3,    1756.2,   1170.8 },
	["Ashenvale"]          = {     1700.0,    4672.9,    5766.7,   3843.7 },
	["Aszhara"]            = {    -3277.1,    5341.7,    5070.8,   3381.2 },
	["Azeroth"]            = {    18172.0,   11176.3,   40741.2,  27149.7 },
	["AzjolNerub"]         = {     1020.8,     872.9,    1072.9,    714.6 },
	["AzuremystIsle"]      = {   -10500.0,   -2793.8,    4070.8,   2714.6 },
	["Badlands"]           = {    -2079.2,   -5889.6,    2487.5,   1658.3 },
	["Barrens"]            = {     2622.9,    1612.5,   10133.3,   6756.2 },
	["BladesEdgeMountains"]= {     8845.8,    4408.3,    5425.0,   3616.7 },
	["BlastedLands"]       = {    -1241.7,  -10566.7,    3350.0,   2233.3 },
	["BloodmystIsle"]      = {   -10075.0,    -758.3,    3262.5,   2175.0 },
	["BoreanTundra"]       = {     8570.8,    4897.9,    5764.6,   3843.7 },
	["BurningSteppes"]     = {     -266.7,   -7031.2,    2929.2,   1952.1 },
	["CoTStratholme"]      = {     2152.1,    2297.9,    1825.0,   1216.7 },
	["CrystalsongForest"]  = {     1443.8,    6502.1,    2722.9,   1814.6 },
	["Darkshore"]          = {     2941.7,    8333.3,    6550.0,   4366.7 },
	["Darnassis"]          = {     2938.4,   10238.3,    1058.3,    705.7 },
	["DeadwindPass"]       = {     -833.3,   -9866.7,    2500.0,   1666.7 },
	["Desolace"]           = {     4233.3,     452.1,    4495.8,   2997.9 },
	["Dragonblight"]       = {     3627.1,    5575.0,    5608.3,   3739.6 },
	["DrakTharonKeep"]     = {     -377.1,    -168.8,     627.1,    418.8 },
	["DunMorogh"]          = {     1802.1,   -3877.1,    4925.0,   3283.3 },
	["Durotar"]            = {    -1962.5,    1808.3,    5287.5,   3525.0 },
	["Duskwood"]           = {      833.3,   -9716.7,    2700.0,   1800.0 },
	["Dustwallow"]         = {     -975.0,   -2033.3,    5250.0,   3500.0 },
	["EasternPlaguelands"] = {    -2287.5,    3704.2,    4031.2,   2687.5 },
	["Elwynn"]             = {     1535.4,   -7939.6,    3470.8,   2314.6 },
	["EversongWoods"]      = {    -4487.5,   11041.7,    4925.0,   3283.3 },
	["Expansion01"]        = {    12996.0,    5821.4,   17464.1,  11642.7 },
	["Felwood"]            = {     1641.7,    7133.3,    5750.0,   3833.3 },
	["Feralas"]            = {     5441.7,   -2366.7,    6950.0,   4633.3 },
	["Ghostlands"]         = {    -5283.3,    8266.7,    3300.0,   2200.0 },
	["GrizzlyHills"]       = {    -1110.4,    5516.7,    5250.0,   3500.0 },
	["Gundrak"]            = {     1310.4,    2122.9,    1143.7,    762.5 },
	["HallsofLightning"]   = {     2500.0,    2200.0,    3400.0,   2266.7 },
	["HallsofReflection"]  = {     7033.3,    6466.7,   13000.0,   8666.7 },
	["Hellfire"]           = {     5539.6,    1481.2,    5164.6,   3443.7 },
	["Hilsbrad"]           = {     1066.7,     400.0,    3200.0,   2133.3 },
	["Hinterlands"]        = {    -1575.0,    1466.7,    3850.0,   2566.7 },
	["HowlingFjord"]       = {    -1397.9,    3116.7,    6045.8,   4031.2 },
	["HrothgarsLanding"]   = {     2797.9,   10781.2,    3677.1,   2452.1 },
	["IcecrownCitadel"]    = {     6366.7,    5933.3,   12200.0,   8133.3 },
	["IcecrownGlacier"]    = {     5443.8,    9427.1,    6270.8,   4181.2 },
	["Ironforge"]          = {     -713.6,   -4569.2,     790.6,    527.6 },
	["IsleofConquest"]     = {      525.0,    1708.3,    2650.0,   1766.7 },
	["Kalimdor"]           = {    17066.6,   12799.9,   36799.8,  24533.2 },
	["LakeWintergrasp"]    = {     4329.2,    5716.7,    2975.0,   1983.3 },
	["LochModan"]          = {    -1993.7,   -4487.5,    2758.3,   1839.6 },
	["Moonglade"]          = {    -1381.2,    8491.7,    2308.3,   1539.6 },
	["Mulgore"]            = {     2047.9,    -272.9,    5137.5,   3425.0 },
	["Nagrand"]            = {    10295.8,      41.7,    5525.0,   3683.3 },
	["Naxxramas"]          = {    -2520.8,    3597.9,    1856.2,   1237.5 },
	["Netherstorm"]        = {     5483.3,    5456.2,    5575.0,   3716.7 },
	["NetherstormArena"]   = {     2660.4,    2918.8,    2270.8,   1514.6 },
	["Nexus80"]            = {     2337.5,    1956.2,    2600.0,   1733.3 },
	["Northrend"]          = {     9217.2,   10593.4,   17751.4,  11834.3 },
	["Ogrimmar"]           = {    -3680.6,    2273.9,    1402.6,    935.4 },
	["PitofSaron"]         = {      839.6,    1256.2,    1533.3,   1022.9 },
	["Redridge"]           = {    -1570.8,   -8575.0,    2170.8,   1447.9 },
	["ScarletEnclave"]     = {    -4047.9,    3087.5,    3162.5,   2108.3 },
	["SearingGorge"]       = {     -322.9,   -6100.0,    2231.2,   1487.5 },
	["ShadowmoonValley"]   = {     4225.0,   -1947.9,    5500.0,   3666.7 },
	["ShattrathCity"]      = {     6135.3,   -1474.0,    1306.2,    870.8 },
	["SholazarBasin"]      = {     6929.2,    7287.5,    4356.2,   2904.2 },
	["Silithus"]           = {     2537.5,   -5958.3,    3483.3,   2322.9 },
	["SilvermoonCity"]     = {    -6400.8,   10153.7,    1211.5,    806.8 },
	["Silverpine"]         = {     3450.0,    1666.7,    4200.0,   2800.0 },
	["StonetalonMountains"]= {     3245.8,    2916.7,    4883.3,   3256.2 },
	["Stormwind"]          = {     1722.9,   -7995.8,    1737.5,   1158.3 },
	["StrandoftheAncients"]= {      787.5,    1883.3,    1743.7,   1162.5 },
	["Stranglethorn"]      = {     2220.8,  -11168.8,    6381.2,   4254.2 },
	["Sunwell"]            = {    -5302.1,   13568.7,    3327.1,   2218.7 },
	["SwampOfSorrows"]     = {    -2222.9,   -9620.8,    2293.8,   1529.2 },
	["Tanaris"]            = {     -218.7,   -5875.0,    6900.0,   4600.0 },
	["Teldrassil"]         = {     3814.6,   11831.2,    5091.7,   3393.8 },
	["TerokkarForest"]     = {     7083.3,   -1000.0,    5400.0,   3600.0 },
	["TheArgentColiseum"]  = {     2100.0,    2200.0,    2600.0,   1733.3 },
	["TheExodar"]          = {   -11066.4,   -3609.7,    1056.8,    704.7 },
	["TheEyeofEternity"]   = {     2766.7,    2200.0,    3400.0,   2266.7 },
	["TheForgeofSouls"]    = {     7033.3,    6466.7,   11400.0,   7600.0 },
	["TheObsidianSanctum"] = {     1133.3,    3616.7,    1162.5,    775.0 },
	["TheRubySanctum"]     = {      902.1,    3429.2,     752.1,    502.1 },
	["TheStormPeaks"]      = {     1841.7,   10197.9,    7112.5,   4741.7 },
	["ThousandNeedles"]    = {     -433.3,   -3966.7,    4400.0,   2933.3 },
	["ThunderBluff"]       = {      516.7,    -850.0,    1043.7,    695.8 },
	["Tirisfal"]           = {     3033.3,    3837.5,    4518.7,   3012.5 },
	["Ulduar"]             = {     1583.3,    1168.8,    3287.5,   2191.7 },
	["Ulduar77"]           = {     2766.7,    2200.0,    3400.0,   2266.7 },
	["Undercity"]          = {      873.2,    1877.9,     959.4,    640.1 },
	["UngoroCrater"]       = {      533.3,   -5966.7,    3700.0,   2466.7 },
	["UtgardePinnacle"]    = {     3275.0,    2166.7,    6550.0,   4366.7 },
	["VaultofArchavon"]    = {     1033.3,     600.0,    2600.0,   1733.3 },
	["VioletHold"]         = {      983.3,    2006.2,     383.3,    256.2 },
	["WarsongGulch"]       = {     2041.7,    1627.1,    1145.8,    764.6 },
	["WesternPlaguelands"] = {      416.7,    3366.7,    4300.0,   2866.7 },
	["Westfall"]           = {     3016.7,   -9400.0,    3500.0,   2333.3 },
	["Wetlands"]           = {     -389.6,   -2147.9,    4135.4,   2756.2 },
	["Winterspring"]       = {     -316.7,    8533.3,    7100.0,   4733.3 },
	["Zangarmarsh"]        = {     9475.0,    1935.4,    5027.1,   3352.1 },
	["ZulDrak"]            = {     -600.0,    7668.7,    4993.8,   3329.2 },
}

--- La cuenta --------------------------------------------------------------

local DOT   = "Interface\\AddOns\\RTSCommand\\art\\punto.tga"
local SIZE  = 16         -- lado del punto, en unidades del mapa
local AGREE = 0.02       -- lo que se le tolera al heroe entre la cuenta y el cliente

-- Ambar: no se confunde con la flecha del heroe ni con los iconos de mision,
-- que son los otros dos que hay encima del mapa.
local COLOR = { 1.0, 0.82, 0.25 }

local dot

-- De yardas del mundo a la coordenada 0..1 del mapa que se esta ensenando.
local function ToMap(z, wx, wy)
	if not z then return nil end
	return (z[1] - wy) / z[3], (z[2] - wx) / z[4]
end

-- El mapa de ahora, si es uno de los que se pueden calcular. El segundo valor
-- es POR QUE no, para que el informe pueda decirlo con su nombre.
local function Zone()
	if type(GetCurrentMapDungeonLevel) == "function" then
		local ok, lvl = pcall(GetCurrentMapDungeonLevel)
		if ok and (tonumber(lvl) or 0) > 0 then return nil, "plantas" end
	end
	local name = GetMapInfo()
	if not name then return nil, "sin mapa" end
	local z = ZONE[name]
	if not z then return nil, name end
	return z, name
end

local function CamPos()
	if RTS_Ready ~= 1 or RTS_HasCam ~= 1 then return nil end
	local x, y = RTS_CamX, RTS_CamY
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

local function HeroPos()
	if RTS_Ready ~= 1 or RTS_HasPos ~= 1 then return nil end
	local x, y = RTS_PX, RTS_PY
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

-- La comprobacion de la cabecera: la misma cuenta sobre el heroe tiene que dar
-- lo que el cliente dice del heroe. Devuelve el error, o nil si no se puede
-- comprobar -- y sin comprobacion no se dibuja.
local function HeroError(z)
	local hx, hy = HeroPos()
	if not hx then return nil end
	local cx, cy = GetPlayerMapPosition("player")
	if type(cx) ~= "number" or type(cy) ~= "number" then return nil end
	-- 0,0 es lo que devuelve el cliente cuando el heroe NO esta en el mapa que
	-- se ensena. No es una esquina, es un "no se".
	if cx == 0 and cy == 0 then return nil end
	local mx, my = ToMap(z, hx, hy)
	return math.max(math.abs(mx - cx), math.abs(my - cy))
end

--- El dibujo --------------------------------------------------------------

local function Build()
	if dot then return end
	dot = WorldMapDetailFrame:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(DOT)
	dot:SetWidth(SIZE)
	dot:SetHeight(SIZE)
	-- El disco de la textura es BLANCO y el aro de fuera NEGRO, asi que el
	-- tinte solo pinta el disco: multiplicar negro por un color sigue dando
	-- negro. Por eso el punto se lee igual sobre mar, nieve o desierto.
	dot:SetVertexColor(COLOR[1], COLOR[2], COLOR[3])
	dot:Hide()
end

local function Place()
	local z = Zone()
	if not z then dot:Hide() return end

	local err = HeroError(z)
	if not err or err > AGREE then dot:Hide() return end

	local cx, cy = CamPos()
	if not cx then dot:Hide() return end

	local mx, my = ToMap(z, cx, cy)
	if mx < 0 or mx > 1 or my < 0 or my > 1 then dot:Hide() return end

	-- El mismo anclaje que usa Blizzard para la flecha del heroe
	-- (`WorldMapFrame.lua`): desde la esquina de arriba a la izquierda del marco
	-- del dibujo, que es el que se escala con el mapa. Por eso el punto no se
	-- descuadra con el mapa en ventana.
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT",
		mx * WorldMapDetailFrame:GetWidth(),
		-my * WorldMapDetailFrame:GetHeight())
	dot:Show()
end

--- El tick ----------------------------------------------------------------

local ticker

local function EnsureTicker()
	if ticker then return end
	Build()
	ticker = CreateFrame("Frame", "RTSRadarTicker")
	local acc = 0
	ticker:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		-- El DLL publica a 33 Hz: mirar mas a menudo no ensena nada nuevo.
		if acc < 0.03 then return end
		acc = 0
		if not R.enabled or not WorldMapFrame:IsShown()
		   or not (ns.FreeCam and ns.FreeCam.active) then
			if dot:IsShown() then dot:Hide() end
			return
		end
		Place()
	end)
end

function R:Create()
	if type(RTSCommandDB.radar) == "boolean" then self.enabled = RTSCommandDB.radar end
	EnsureTicker()
end

function R:Set(on)
	self.enabled = on and true or false
	RTSCommandDB.radar = self.enabled
	EnsureTicker()
	if not self.enabled and dot then dot:Hide() end
	ns.Print("punto de la camara en el mapa: " ..
		(self.enabled and "|cff00ff00SI|r" or "|cffff0000NO|r"))
end

function R:Toggle()
	self:Set(not self.enabled)
end

--- Por que no se ve -------------------------------------------------------
--
-- Son cinco condiciones y todas acaban igual -- no hay punto -- asi que el
-- informe las enumera por separado en vez de contestar si o no.

function R:Status()
	ns.Print(("punto de la camara en el mapa: %s"):format(
		self.enabled and "|cff00ff00si|r" or "|cffff0000no|r"))

	if not (ns.FreeCam and ns.FreeCam.active) then
		ns.Print("  |cff888888la camara libre esta apagada: sin ella la vista va " ..
		         "pegada al heroe y el punto seria su flecha.|r")
	end

	local z, why = Zone()
	if not z then
		if why == "plantas" then
			ns.Print("  |cffff8800este mapa va por plantas|r -- las mazmorras y " ..
			         "Dalaran usan otro DBC y otras coordenadas.")
		elseif why == "sin mapa" then
			ns.Print("  |cff888888no hay ningun mapa de zona abierto.|r")
		else
			ns.Print(("  |cffff8800'%s' no esta en la tabla|r de WorldMapArea."):format(
				tostring(why)))
		end
		return
	end

	ns.Print(("  mapa |cffffff00%s|r: %.0f x %.0f yardas"):format(why, z[3], z[4]))

	local err = HeroError(z)
	if not err then
		ns.Print("  |cffff8800no se puede comprobar|r -- o falta el DLL, o tu heroe " ..
		         "no esta en el mapa que tienes abierto.")
	else
		ns.Print(("  comprobacion sobre tu heroe: |cff%s%.4f|r (se admite %.2f)"):format(
			err <= AGREE and "00ff00" or "ff4040", err, AGREE))
	end

	local cx, cy = CamPos()
	if not cx then
		ns.Print("  |cffff8800sin posicion de camara|r -- sale de RTS_CamX/Y, y hoy no hay.")
	else
		local mx, my = ToMap(z, cx, cy)
		ns.Print(("  camara en |cffffff00%.0f, %.0f|r del mundo -> %.1f%%, %.1f%% del mapa"):format(
			cx, cy, mx * 100, my * 100))
	end

	ns.Print("  |cffffff00/rts punto on|off|r lo enciende y lo apaga.")
end
