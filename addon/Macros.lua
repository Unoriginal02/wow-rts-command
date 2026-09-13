--[[
	Macros.lua -- las ordenes a los bots, como macros del juego.

	DESDE EL 2026-09-13 ESTE FICHERO ES EL UNICO SITIO DONDE HAY ORDENES. La
	rejilla 4x4 de `Panel.lua` llevaba dieciseis escritas en el codigo y se ha
	borrado entera: lo que el jugador pulsa para mandar a sus bots son macros de
	los de verdad, en las ocho casillas de la bandeja (`Tray.lua`). Anadir una
	orden es anadir una linea al catalogo de abajo, y nada mas.

	`/rts macros` crea (o actualiza) los macros del catalogo.
	ARRASTRARLOS A LA BANDEJA ES COSA DEL JUGADOR, una vez. No se colocan solos:
	eso seria `PickupMacro` + `PlaceAction`, `PlaceAction` es de la familia
	protegida y no se ha comprobado en este cliente -- y aqui no se construye
	sobre una lectura sin probar. Si algun dia se comprueba que deja, es una
	linea.

	=== POR DONDE SALE LA ORDEN ===========================================

	Cada macro es una o varias lineas `/rtscmd <comando de playerbots>`.

	`/rtscmd` va A LOS SELECCIONADOS, y si no hay nadie seleccionado va a todo
	el grupo DICIENDOLO. `/rtsall` va siempre a todo el grupo. Las dos pasan por
	`Orders`, o sea que heredan la cola de envio -- cuatro susurros en el mismo
	frame se los come el limite de ritmo del chat del cliente sin un solo error,
	que es el fallo que esa cola existe para no repetir.

	Un macro que hablara por `/p` a pelo tambien funcionaria, y por eso conviene
	saber que NO es lo mismo: iria siempre a los cinco.

	=== LO QUE ESTE CLIENTE PIDE, COMPROBADO CONTRA EL =====================

	Leido de `Blizzard_MacroUI.lua` y `.xml` de ESTE cliente (sacados del
	`patch-esES.MPQ`), no de memoria:

	  CreateMacro(nombre, ICONO, cuerpo, porPersonaje)
	  EditMacro(indice, nombre, ICONO, cuerpo)

	**ICONO ES UN INDICE, NO UNA RUTA.** Es la posicion dentro de la lista de
	iconos de macro del cliente, la que `GetMacroIconInfo(i)` traduce a textura.
	Pasar "Interface\\Icons\\Loquesea" no da error: da un icono vacio, que es el
	modo de fallo silencioso de siempre. Asi que aqui se recorre esa lista UNA
	vez, se guarda nombre -> indice, y lo que no aparezca se queda con la
	interrogacion Y SE DICE por pantalla.

	  MAX_ACCOUNT_MACROS = 36      los de la cuenta (indices 1..36)
	  MAX_CHARACTER_MACROS = 18    los del personaje (indices 37..54)
	  nombre: 16 letras            (`letters="16"` del MacroPopupEditBox)
	  cuerpo: 255 letras           (`letters="255"` del MacroFrameText)

	Se crean en los de la CUENTA: una orden a un bot no depende de que
	personaje lleves.

	=== POR QUE SE ACTUALIZA EN VEZ DE BORRAR Y CREAR ======================

	Una barra de accion guarda el INDICE del macro, no su nombre. Borrar y
	volver a crear recoloca los indices, asi que el boton que el jugador habia
	puesto acabaria apuntando a otro macro -- o a ninguno. Volver a ejecutar
	`/rts macros` tiene que ser gratis, asi que si ya existe uno nuestro con ese
	nombre se le hace `EditMacro` encima y el sitio en la barra se respeta.

	"Uno nuestro" se reconoce porque su cuerpo lleva `/rtscmd`. Un macro del
	jugador que se llame igual NO se toca: se avisa y se salta.
]]

local ADDON, ns = ...

local M = {}
ns.Macros = M

-- Lo que marca un macro como nuestro, y a la vez el canal por el que sale la
-- orden. Las dos cosas son la misma cadena a proposito: no hay forma de tener
-- una sin la otra y que se desincronicen.
local MARK = "/rtscmd"

-- De `Blizzard_MacroUI.lua`. Se leen del cliente si estan (son globales suyas),
-- y si no, de aqui: un numero equivocado aqui se traduce en macros que se
-- crean fuera de rango y no aparecen.
local ACCOUNT_MAX = 36
local CHAR_MAX = 18
local NAME_MAX = 16
local BODY_MAX = 255

--- El catalogo ------------------------------------------------------------
--
-- `cmd` es una lista de comandos de playerbots, uno por linea del macro.
-- NINGUNO ES INVENTADO -- cada uno esta en `ChatCommandHandlerStrategy.cpp` o
-- es un nombre de estrategia de `StrategyContext.h` / `AssistStrategyContext`:
--
--   follow stay attack pull flee "max dps" "tank attack" drink grind
--   revive repair ll s formation                      (comandos)
--   co / nc  +X  -X  ~X  ?  !                         (estrategias)
--
-- `co` toca el motor de COMBATE y `nc` el de FUERA DE COMBATE. Los dos llevan
-- `dps assist` de fabrica (`AiFactory.cpp`, casi todas las clases), asi que un
-- cambio de asistir que solo toque uno se ve como "va solo el ordenado... hasta
-- que golpea". Por eso todos los de asistir mandan las dos lineas.

local MACROS = {
	-- --- Mando basico -------------------------------------------------
	{ name = "Sigueme",  icon = "Ability_Rogue_Sprint",
	  cmd = { "follow" },              d = "vuelve a seguirte" },
	{ name = "Quieto",   icon = "Ability_Warrior_DefensiveStance",
	  cmd = { "stay" },                d = "aguanta donde esta" },
	{ name = "Ataca",    icon = "Ability_Warrior_Cleave",
	  cmd = { "attack" },              d = "ataca TU objetivo" },
	{ name = "Tirar",    icon = "Ability_Hunter_SniperShot",
	  cmd = { "pull" },                d = "abre el combate el (pull)" },
	{ name = "Huye",     icon = "Ability_Rogue_Feint",
	  cmd = { "flee" },                d = "rompe el combate y se aleja" },
	{ name = "A saco",   icon = "Ability_Warrior_InnerRage",
	  cmd = { "max dps" },             d = "quema enfriamientos" },
	{ name = "Tanquea",  icon = "Ability_Defend",
	  cmd = { "tank attack" },         d = "que coja tu objetivo" },
	{ name = "Bebe",     icon = "INV_Drink_07",
	  cmd = { "drink" },               d = "se sienta a comer y beber" },
	{ name = "Cazar",    icon = "Ability_Hunter_MarkedForDeath",
	  cmd = { "grind" },               d = "busca bichos por su cuenta" },

	-- --- Asistir: encenderlo y apagarlo --------------------------------
	--
	-- `dps assist` es lo que hace que un bot elija objetivo de la lista de
	-- QUIEN PELEA CON EL GRUPO (`TargetValue::FindTarget` lee "attackers"), no
	-- de a quien le mandaste tu. Quitarla de los dos motores es lo que se
	-- comprueba con "Ver combate" / "Ver fuera".
	{ name = "Solo",     icon = "Ability_Stealth",
	  cmd = { "co -dps assist,-tank assist", "nc -dps assist,-tank assist" },
	  d = "que NO se apunte a la pelea de los demas" },
	{ name = "Asistir DPS", icon = "Ability_Warrior_BattleShout",
	  cmd = { "co +dps assist", "nc +dps assist" },
	  d = "devuelve el asistir de fabrica" },
	{ name = "Asistir tanq", icon = "Ability_Warrior_ShieldWall",
	  cmd = { "co +tank assist", "nc +tank assist" },
	  d = "que coja lo que ataca al grupo (tanques)" },
	{ name = "Ver combate", icon = "INV_Misc_Note_01",
	  cmd = { "co ?" },
	  d = "te dice sus estrategias EN combate (selecciona a UNO)" },
	{ name = "Ver fuera",   icon = "INV_Misc_Map_01",
	  cmd = { "nc ?" },
	  d = "las de FUERA de combate (selecciona a UNO)" },
	{ name = "Reset IA",    icon = "Spell_Nature_TimeStop",
	  cmd = { "co !", "nc !" },
	  d = "devuelve las estrategias de fabrica de su clase" },
	{ name = "Pasivo",      icon = "Spell_Nature_Sleep",
	  cmd = { "co +passive", "nc +passive" },
	  d = "no hace NADA por su cuenta (sigue obedeciendo)" },
	{ name = "Activo",      icon = "Ability_Hunter_Readiness",
	  cmd = { "co -passive", "nc -passive" },
	  d = "le quita el pasivo" },

	-- --- Botin, dinero y mantenimiento ---------------------------------
	{ name = "Botin todo",  icon = "INV_Misc_Coin_01",
	  cmd = { "ll all" },              d = "recoge todo, grises incluidos" },
	{ name = "Botin normal", icon = "INV_Misc_Bag_08",
	  cmd = { "ll normal" },           d = "solo lo que le sirve" },
	{ name = "Vender gris", icon = "INV_Misc_Gear_01",
	  cmd = { "s gray" },              d = "vende los grises al vendedor" },
	{ name = "Reparar",     icon = "INV_Hammer_20",
	  cmd = { "repair" },              d = "repara su equipo" },
	{ name = "Revivir",     icon = "Spell_Holy_Resurrection",
	  cmd = { "revive" },              d = "vuelve del cementerio" },

	-- --- Formacion -----------------------------------------------------
	{ name = "Formar cerca", icon = "Ability_Warrior_Charge",
	  cmd = { "formation near" },      d = "se te pegan" },
	{ name = "Formar lejos", icon = "Ability_Marksmanship",
	  cmd = { "formation far" },       d = "se abren" },

	-- --- LO QUE NO ES UNA ORDEN A UN BOT --------------------------------
	--
	-- Entran aqui el 2026-09-13, con la rejilla 4x4 de `Panel.lua`. Aquellas
	-- dieciseis casillas eran botones nuestros con la orden escrita dentro;
	-- cuatro de ellas no eran ordenes a bots sino mandos del propio addon --
	-- el candado de la camara, las dos ventanas propias y salir del modo -- y
	-- al borrar la rejilla se quedaban sin sitio.
	--
	-- Son macros como las demas, con la unica diferencia de que su cuerpo es un
	-- comando NUESTRO (`raw`) en vez de uno de playerbots. Asi el jugador los
	-- arrastra a la bandeja igual que el resto y no hay una segunda clase de
	-- boton que explicar.
	--
	-- SALIR COMO MACRO TIENE UN PELIGRO y por eso esta escrito: el modo RTS
	-- esconde las barras de accion, asi que si el jugador no se pone este macro
	-- en la bandeja, la unica forma de salir es la tecla o `/rts`. No se le
	-- puede reservar una casilla a la fuerza -- son suyas -- pero si decirlo.
	{ name = "Candado",  icon = "INV_Misc_Key_03", raw = true,
	  cmd = { "/rts fc lock" },        d = "clava la camara a tu heroe" },
	{ name = "Bolsas",   icon = "INV_Misc_Bag_09", raw = true,
	  cmd = { "/rts bolsas" },         d = "la ventana de bolsas del grupo" },
	{ name = "Misiones", icon = "INV_Misc_Book_09", raw = true,
	  cmd = { "/rts misiones" },       d = "el registro de misiones del grupo" },
	{ name = "Salir RTS", icon = "Spell_Nature_Polymorph", raw = true,
	  cmd = { "/rts" },                d = "sale del modo RTS (o entra)" },

	-- --- Cuidar: la unica orden que necesita un segundo click ------------
	--
	-- `PFOCUS` pone a un bot a cuidar de alguien que ELIGES despues, pinchandolo
	-- en el mundo. Un macro no puede preguntar eso, asi que el macro solo ARMA
	-- el gesto y el addon se encarga del segundo click.
	{ name = "Cuidar",   icon = "Spell_Holy_PrayerOfHealing", raw = true,
	  cmd = { "/rts focus" },          d = "el seleccionado cuida de quien pinches" },
	{ name = "Suelta",   icon = "Spell_Shadow_Teleport", raw = true,
	  cmd = { "/rts unfocus" },        d = "le quita el cuidado" },
}

M.CATALOGUE = MACROS

--- Los iconos: del nombre al indice ---------------------------------------
--
-- Se recorre la lista entera UNA vez y se guarda por nombre de fichero, sin
-- ruta y en mayusculas. Son un par de miles de entradas: un parpadeo, y solo
-- ocurre cuando se crean los macros.

local iconIndex

local function IconIndex()
	if iconIndex then return iconIndex end
	local map = {}

	-- La lista de iconos es del cliente, no del addon de macros, pero cargarlo
	-- no cuesta nada y quita la duda de si estaba disponible todavia.
	if not IsAddOnLoaded("Blizzard_MacroUI") then
		pcall(LoadAddOn, "Blizzard_MacroUI")
	end

	local n = GetNumMacroIcons and GetNumMacroIcons() or 0
	for i = 1, n do
		local tex = GetMacroIconInfo(i)
		if type(tex) == "string" then
			local base = tex:match("[^\\/]+$") or tex
			base = base:upper()
			-- El primero gana: si el mismo nombre sale dos veces da igual cual,
			-- son la misma textura.
			if not map[base] then map[base] = i end
		end
	end

	-- NO SE GUARDA UNA LISTA VACIA. Si todavia no esta (la interfaz acaba de
	-- cargar), cachear el fallo la deja fallando para siempre y los macros
	-- saldrian todos con interrogacion sin que nada lo explicara. Es el mismo
	-- error que cachear un CVar que aun no existe -- el FOV estuvo TRES etapas
	-- muerto por eso. Se vuelve a intentar a la siguiente.
	if n == 0 then return map end
	iconIndex = map
	return iconIndex
end

local function IconFor(name)
	return IconIndex()[(name or ""):upper()]
end

--- Los macros que ya hay --------------------------------------------------

local function Limits()
	local a = _G.MAX_ACCOUNT_MACROS or ACCOUNT_MAX
	local c = _G.MAX_CHARACTER_MACROS or CHAR_MAX
	return a, c
end

-- Recorre los indices REALES de los macros existentes. Los de la cuenta son
-- 1..n; los del personaje empiezan en MAX_ACCOUNT_MACROS+1 siempre, este la
-- cuenta llena o no.
local function EachMacro(fn)
	local amax = Limits()
	local na, nc = GetNumMacros()
	for i = 1, (na or 0) do
		if fn(i) then return i end
	end
	for i = 1, (nc or 0) do
		local idx = amax + i
		if fn(idx) then return idx end
	end
end

-- "Nuestro" es cualquier macro cuyo cuerpo hable por uno de nuestros comandos.
-- `/rtscmd` marca los de orden a bots y `/rts` los del propio addon (candado,
-- ventanas, salir) -- los dos tienen que contar, o `/rts macros` se negaria a
-- actualizar la mitad de su propio catalogo diciendo que es del jugador.
local function IsOurs(body)
	if type(body) ~= "string" then return false end
	return body:find(MARK, 1, true) ~= nil or body:find("/rts", 1, true) ~= nil
end

-- Devuelve indice, esNuestro. Compara por NOMBRE porque es lo unico que sobrevive
-- a que el jugador lo mueva de sitio.
local function FindByName(name)
	local found, mine
	EachMacro(function(i)
		local n, _, body = GetMacroInfo(i)
		if n == name then
			found, mine = i, IsOurs(body)
			return true
		end
	end)
	return found, mine
end

-- `raw` = el cuerpo ya son comandos nuestros, no verbos de playerbots que haya
-- que envolver en `/rtscmd`.
local function BodyOf(entry)
	local lines = {}
	for _, c in ipairs(entry.cmd) do
		table.insert(lines, entry.raw and c or (MARK .. " " .. c))
	end
	return table.concat(lines, "\n")
end

--- Crear y actualizar -----------------------------------------------------

-- SI EL CLIENTE SE NIEGA, QUE SE LEA UNA VEZ Y NO VEINTICUATRO.
--
-- `CreateMacro` y `EditMacro` no estan en la lista de funciones protegidas que
-- este proyecto ha comprobado, pero tampoco se ha comprobado lo contrario -- y
-- entre suponer que si y enterarse con veinticuatro errores rojos iguales,
-- mejor pararse en el primero y decir cual fue.
local function Blocked(name, err)
	ns.Print(("|cffff0000macros:|r el cliente no ha dejado tocar '%s': %s")
		:format(name, tostring(err)))
	ns.Print("Si dice 'blocked', es que la funcion esta protegida en este " ..
		"cliente y los macros hay que crearlos a mano desde |cffffff00/macro|r.")
end

function M:Build()
	if InCombatLockdown() then
		ns.Print("|cffff8800macros:|r en combate no. Sal de la pelea y repite.")
		return
	end

	local amax = Limits()
	local made, upd, skipped, full = 0, 0, 0, 0
	local noIcon = {}

	for _, e in ipairs(MACROS) do
		local body = BodyOf(e)
		local icon = IconFor(e.icon)
		if not icon then
			table.insert(noIcon, e.icon)
			icon = IconFor("INV_Misc_QuestionMark") or 1
		end

		-- Nombre y cuerpo pasan por el mismo recorte que el cliente aplicaria
		-- en silencio. Que se vea aqui en vez de descubrirlo en la ventana.
		local name = e.name
		if name:len() > NAME_MAX then
			ns.Print(("|cffff8800macros:|r '%s' pasa de %d letras, se recorta.")
				:format(name, NAME_MAX))
			name = name:sub(1, NAME_MAX)
		end
		if body:len() > BODY_MAX then
			ns.Print(("|cffff8800macros:|r el cuerpo de '%s' pasa de %d letras y NO se crea.")
				:format(name, BODY_MAX))
			skipped = skipped + 1
		else
			local idx, mine = FindByName(name)
			if idx and not mine then
				ns.Print(("|cffff8800macros:|r ya tienes un macro llamado '%s' " ..
					"que no es mio. No lo toco."):format(name))
				skipped = skipped + 1
			elseif idx then
				local ok, err = pcall(EditMacro, idx, name, icon, body)
				if not ok then return Blocked(name, err) end
				upd = upd + 1
			else
				local na = GetNumMacros()
				if (na or 0) >= amax then
					full = full + 1
				else
					local ok, err = pcall(CreateMacro, name, icon, body, false)
					if not ok then return Blocked(name, err) end
					made = made + 1
				end
			end
		end
	end

	ns.Print(("macros: |cff00ff00%d nuevos|r, %d actualizados%s%s."):format(
		made, upd,
		skipped > 0 and (", |cffff8800" .. skipped .. " saltados|r") or "",
		full > 0 and (", |cffff0000" .. full .. " sin hueco|r") or ""))

	if #noIcon > 0 then
		-- UN ICONO QUE NO ESTA EN LA LISTA NO DA ERROR: da un hueco vacio. Que
		-- lo diga aqui es la diferencia entre arreglarlo en un minuto y mirar
		-- una barra con agujeros preguntandose que se rompio.
		ns.Print("|cffff8800macros:|r sin icono (no estan en la lista del cliente): " ..
			table.concat(noIcon, ", "))
	end
	if full > 0 then
		ns.Print(("Los macros de cuenta son %d y estan llenos. Borra alguno " ..
			"o usa |cffffff00/rts macros clear|r y vuelve a intentarlo."):format(amax))
	end

	ns.Print("Abre |cffffff00/macro|r y arrastralos a las dos barras verticales " ..
		"de la derecha. Se quedan a la vista en modo RTS.")

	-- EL MODO RTS NO ENCIENDE BARRAS QUE EL JUGADOR TIENE APAGADAS, que es la
	-- regla de capturar y devolver mirada del otro lado: `Chrome` deja de
	-- esconderlas, no las inventa. Si estan apagadas en las opciones, los
	-- macros se crean igual y no hay donde ponerlos -- y eso se lee como "los
	-- macros no funcionan". Asi que se dice aqui.
	local right = _G.MultiBarRight
	if right and not right:IsShown() then
		ns.Print("|cffff8800Ojo:|r no tienes encendidas esas barras. " ..
			"Esc -> Interfaz -> Barras de accion -> |cffffff00Barra derecha|r " ..
			"y |cffffff00Barra derecha 2|r.")
	end
end

--- Borrar los nuestros ----------------------------------------------------

function M:Clear()
	if InCombatLockdown() then
		ns.Print("|cffff8800macros:|r en combate no.")
		return
	end

	-- De mayor a menor: borrar recoloca los indices de todo lo que va detras.
	local mine = {}
	EachMacro(function(i)
		local _, _, body = GetMacroInfo(i)
		if IsOurs(body) then table.insert(mine, i) end
	end)
	table.sort(mine, function(a, b) return a > b end)

	for _, i in ipairs(mine) do DeleteMacro(i) end
	ns.Print(("macros: borrados %d mios. Los tuyos no se tocan."):format(#mine))
	if #mine > 0 then
		ns.Print("|cffff8800Ojo:|r borrar recoloca los indices, asi que revisa " ..
			"los botones de la barra.")
	end
end

--- Que hay y que haria ----------------------------------------------------

function M:List()
	ns.Print(("catalogo: %d macros. |cffffff00/rts macros|r los crea."):format(#MACROS))
	for _, e in ipairs(MACROS) do
		local idx, mine = FindByName(e.name)
		local mark = (idx and mine) and "|cff00ff00[puesto]|r"
			or (idx and "|cffff8800[ocupado]|r" or "|cff888888[no]|r")
		ns.Print(("  %s |cffffff00%-13s|r %s  |cff888888%s|r"):format(
			mark, e.name, table.concat(e.cmd, " + "), e.d or ""))
	end
end

function M:Status()
	local amax, cmax = Limits()
	local na, nc = GetNumMacros()
	local n = 0
	EachMacro(function(i)
		local _, _, body = GetMacroInfo(i)
		if IsOurs(body) then n = n + 1 end
	end)
	ns.Print(("macros: %d/%d de cuenta, %d/%d de personaje; %d son mios.")
		:format(na or 0, amax, nc or 0, cmax, n))
	ns.Print(("iconos del cliente: %d en la lista."):format(
		GetNumMacroIcons and GetNumMacroIcons() or 0))
	ns.Print("|cffffff00/rts macros|r crea o actualiza  " ..
		"|cffffff00list|r que hay  |cffffff00clear|r borra los mios")
	ns.Print("Cada uno manda |cffffff00/rtscmd <comando>|r: a los SELECCIONADOS, " ..
		"o a todo el grupo si no hay nadie.")
end

--- Los dos comandos que usan los macros -----------------------------------
--
-- Se registran aqui y no en `Core.lua` porque son el reverso de este fichero:
-- un macro del catalogo no significa nada sin ellos, y separarlos es como se
-- acaba con un verbo que no escucha nadie.

local function Route(text, forceAll)
	text = strtrim(text or "")
	if text == "" then
		ns.Print("|cffffff00/rtscmd <comando>|r - a los seleccionados " ..
			"(o a todo el grupo si no hay nadie).")
		ns.Print("|cffffff00/rtsall <comando>|r - siempre a todo el grupo.")
		return
	end

	local sel = ns.Selection:Get()
	if forceAll or #sel == 0 then
		-- DECIRLO. Una orden que sale a los cinco cuando creias haber ordenado
		-- a uno es justo el sintoma que este catalogo viene a poder tocar.
		if not forceAll then
			ns.Print("|cffffff00sin seleccion|r -> a todo el grupo:")
		end
		ns.Orders:Broadcast(text, "> " .. text .. " (todo el grupo)")
	else
		ns.Orders:Send(text, "> " .. text)
	end
end

SLASH_RTSCMD1 = "/rtscmd"
SLASH_RTSCMD2 = "/rtsc"
SlashCmdList["RTSCMD"] = function(msg) Route(msg, false) end

SLASH_RTSALL1 = "/rtsall"
SlashCmdList["RTSALL"] = function(msg) Route(msg, true) end
