--[[
	Macros.lua -- las ordenes a los bots, como macros del juego.

	EL CATALOGO ESTA EN `Actions.lua` Y ESTE FICHERO LO COPIA A MACROS DEL
	JUEGO. Desde que la bandeja sabe lanzar las ordenes por su cuenta -- con
	icono propio y sin gastar macros -- esto ya no es el camino normal para
	usarlas: es el camino para SACARLAS DEL ADDON. Un macro de verdad se puede
	poner en una barra del juego, se le puede asignar una tecla y se puede
	arrastrar a donde sea; una orden nuestra vive solo en la bandeja.

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

--- El catalogo, que ya no vive aqui --------------------------------------
--
-- ESTE FICHERO DEJA DE SER EL DUENO DE LAS ORDENES. La lista se ha mudado
-- entera a `Actions.lua`, que es quien la ensena en el desplegable de la
-- bandeja y quien la lanza. Aqui se sigue leyendo para lo unico que un macro
-- de verdad hace y una orden nuestra no: existir FUERA del addon -- en una
-- barra del juego, con su tecla, o para arrastrarlo a donde sea.
--
-- Se pide por FUNCION y no se copia a una local al cargar: asi da igual el
-- orden de los ficheros en el `.toc`, que es la clase de dependencia que no
-- avisa cuando se rompe -- simplemente sale un catalogo vacio.

local function Catalogue()
	return (ns.Actions and ns.Actions.LIST) or {}
end

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

-- El cuerpo del macro es EL MISMO TEXTO que lanza la orden desde la bandeja, y
-- por eso lo escribe `Actions.lua` y no este fichero: dos sitios componiendo
-- las mismas lineas se separan el dia que una cambia.
local function BodyOf(entry)
	return ns.Actions:Body(entry)
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

--- NO HAY PODA AUTOMATICA, Y ESTA ES LA CICATRIZ --------------------------
--
-- El 2026-09-14 `Build` borraba, antes de crear, todo macro "mio" que ya no
-- estuviera en el catalogo. La idea era buena -- el catalogo como unica verdad,
-- sin huerfanos -- y la REGLA era mala: "mio" se decidia con `IsOurs`, o sea
-- *cualquier macro cuyo cuerpo lleve `/rts` o `/rtscmd` dentro*.
--
-- Eso no distingue lo que este addon creo de lo que el JUGADOR se escribio con
-- nuestros comandos. Y el jugador tenia cuatro suyos -- `/rts command`,
-- `/rts mode`, `Playerbots add` (que empieza por `/rts` y sigue con comandos de
-- GM) y `Traerlos` (`/rtscmd summon`) -- que entraban en esa red y se fueron con
-- los veintidos del recorte, sin haberlos creado nosotros nunca.
--
-- LA LECCION, escrita donde se cometio: un addon puede crear y puede
-- ACTUALIZAR lo que creo, pero **borrar lo que no ha creado no es suyo**, y
-- "parece mio" no es "es mio". Para poder borrar con derecho haria falta
-- guardar que macros creamos nosotros, nombre a nombre, y aun asi un nombre
-- repetido lo volveria ambiguo.
--
-- Asi que no se borra nada. Quitar una entrada del catalogo deja de crearla y
-- ya esta; el macro que sobre lo borra el jugador desde `/macro`, que es de
-- donde no se puede equivocar nadie.
--
-- (`M:Clear()` sigue existiendo y sigue borrando por `IsOurs` -- pero eso lo
-- pide el jugador a proposito, escribiendolo, y dice cuantos se lleva.)

function M:Build()
	if InCombatLockdown() then
		ns.Print("|cffff8800macros:|r en combate no. Sal de la pelea y repite.")
		return
	end

	local amax = Limits()
	local made, upd, skipped, full = 0, 0, 0, 0
	local noIcon = {}

	for _, e in ipairs(Catalogue()) do
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

	-- DONDE PONERLOS CAMBIO EL 2026-09-13. Antes era "las dos barras verticales
	-- de la derecha", porque el modo RTS las dejaba a la vista a proposito para
	-- esto. Ahora las esconde con el resto de barras de accion y el sitio es la
	-- BANDEJA: diez casillas propias, que es adonde fue a parar la rejilla 4x4.
	ns.Print("Abre |cffffff00/macro|r y arrastralos a las |cffffff00diez casillas|r " ..
		"de abajo a la derecha, en modo RTS.")

	-- Y SE DICE CUANTOS SON, porque el catalogo ya roza el limite de la cuenta:
	-- 35 de 36. Con dos macros propios del jugador, los ultimos del catalogo no
	-- caben -- y eso sale por `full`, pero solo DESPUES de intentarlo. Decirlo
	-- antes es la diferencia entre entenderlo y pensar que el comando falla.
	local amax2 = Limits()
	ns.Print(("|cff888888El catalogo son %d macros y la cuenta admite %d.|r")
		:format(#Catalogue(), amax2))
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
	ns.Print(("catalogo: %d macros. |cffffff00/rts macros|r los crea."):format(#Catalogue()))
	for _, e in ipairs(Catalogue()) do
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
