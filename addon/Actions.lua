--[[
	Actions.lua -- las ordenes del addon, con su icono propio, y el desplegable
	que las pone en una casilla de la bandeja.

	=== POR QUE DEJAN DE SER MACROS DEL JUEGO =============================

	Hasta hoy la unica forma de tener una orden a mano era crear un MACRO del
	cliente (`/rts macros`) y arrastrarlo a la bandeja. Funciona, y tiene dos
	precios que se pagan cada vez:

	  1. EL ICONO SALE DE LA LISTA DEL CLIENTE. `CreateMacro` no acepta una
	     ruta de textura: acepta el numero de un icono dentro de la lista de
	     macros. O sea que un macro solo puede llevar un dibujo de los que ya
	     trae el juego, y buscarlo es bajar por dos mil casillas sin buscador.
	     No hay ninguno que diga "bolsas del grupo" ni "registro de misiones",
	     porque esas dos cosas no existen en WoW: son nuestras.

	  2. SON 36 Y SON DE LA CUENTA. Cada orden del catalogo ocupaba un hueco de
	     los macros del jugador, y el catalogo llego a comerselos todos.

	Una orden nuestra NO NECESITA SER UN MACRO. `RunMacro` esta protegida, pero
	lo que hay dentro de estos macros no lo esta: `/rts loquesea` lo atiende el
	propio addon y `/rtscmd loquesea` acaba en un susurro. Las dos se pueden
	llamar desde un boton corriente, y un boton corriente admite CUALQUIER
	textura -- las miles del cliente y las nuestras.

	LO QUE SI SIGUE NECESITANDO UN MACRO DE VERDAD es todo lo que tenga un verbo
	PROTEGIDO dentro: `/cast`, `/use`, `/target`. Eso no se puede lanzar desde
	Lua por mucho boton que le pongas. Por eso la bandeja sigue aceptando que le
	arrastres un macro encima -- la postura del guerrero, por ejemplo -- y por
	eso `/rts macros` no se ha ido: una casilla admite las dos cosas.

	=== LOS ICONOS PROPIOS ================================================

	  art = "bolsas"   ->  Interface\AddOns\RTSCommand\art\icons\bolsas.tga
	  icon = "INV_..."  ->  Interface\Icons\INV_...   (uno del cliente)

	Se prefiere `art` si esta. El PNG se deja en la carpeta de iconos del
	escritorio CON EL NOMBRE DE LA ORDEN y `rts-tools\Convertir_Arte.bat` lo
	encaja en 64x64 y escribe el TGA; el original queda en `art-src\icons`.

	UNA RUTA DE TEXTURA QUE NO EXISTE NO DA ERROR: dibuja nada. Asi que el
	fallo de "puse el icono y la casilla salio vacia" es siempre el nombre del
	fichero o que falta desplegar, nunca el codigo -- y por eso el nombre del
	PNG manda y no hay tabla de traduccion en medio.

	LOS NUESTROS NO SE RECORTAN. Los iconos del cliente llevan un borde de
	relleno que todo el mundo recorta al 7% (`SetTexCoord(0.07, 0.93, ...)`);
	los nuestros vienen ya encajados con transparencia alrededor, asi que
	recortarlos les comeria el dibujo.
]]

local ADDON, ns = ...

local A = {}
ns.Actions = A

local ART_DIR = "Interface\\AddOns\\RTSCommand\\art\\icons\\"
local ICON_DIR = "Interface\\Icons\\"

--- El catalogo ------------------------------------------------------------
--
-- `cmd` son las lineas que lanza la orden, en el mismo formato que el cuerpo de
-- un macro. `raw` significa que ya son comandos nuestros; sin el, son verbos de
-- playerbots y se mandan con `/rtscmd`.
--
-- `cmd2` ES LA SEGUNDA ORDEN, la del CLIC DERECHO, y casi ninguna la tiene.
-- Solo vale cuando las dos son la misma cosa vista de dos maneras -- el candado
-- pone la camara SOBRE el heroe con el izquierdo y DENTRO DE SU CABEZA con el
-- derecho -- porque el derecho ya tenia dueno en la bandeja (el desplegable que
-- cambia la casilla), y quitarselo a cambio de cualquier segunda orden seria
-- esconder la unica forma de configurar. En las casillas que la llevan, el
-- desplegable se aparta a MAYUS+derecho y el tooltip lo dice.
--
-- `d2` es su descripcion. Sin `d2` no hay nada que ensenar en el tooltip, asi
-- que una `cmd2` sin `d2` es una funcion escondida -- lo mismo que no tenerla.
--
-- NINGUN VERBO ES INVENTADO: cada uno esta en `ChatCommandHandlerStrategy.cpp`
-- o es un nombre de estrategia de `StrategyContext.h`.
--
-- `g` es el grupo del desplegable. Solo sirve para separarlo visualmente: doce
-- lineas seguidas se leen como una lista de la compra.
--
-- `id` es lo que se GUARDA en la casilla, asi que no se cambia a la ligera:
-- renombrarlo deja las casillas del jugador apuntando a una orden que ya no
-- existe. El nombre visible si se puede cambiar cuando se quiera.

local LIST = {
	-- --- DE PLAYERBOTS, SOLO DOS ---------------------------------------
	--
	-- El catalogo llego a tener veintidos verbos y se recorto a dos el
	-- 2026-09-14, a peticion del jugador: *"de playerbot solo deja seguir y
	-- parar... luego veremos una a una las que vamos anadiendo"*.
	--
	-- Volver a meter uno es una linea aqui. Los verbos siguen todos en
	-- playerbots y `/rtscmd <verbo>` los manda sin necesidad de nada de esto.
	{ id = "invitar", g = "Bots", name = "Traer bots", raw = true,
	  icon = "Spell_Holy_PrayerOfHealing", art = "invitar",
	  cmd = { "/rts invitar" },   d = "mete a tus bots en el grupo" },
	-- SEGUIR Y QUIETO VAN POR EL COMANDO DEL ADDON, no por `/rtscmd`.
	--
	-- Son verbos de playerbots y se podrian susurrar, y asi estaban. La
	-- diferencia es que `/rts follow` y `/rts hold` llegan por mod-rts: sin
	-- linea de chat, sin cola y despertandole la IA, o sea que el bot sale al
	-- momento. Susurrarlos costaba una vuelta de pensamiento suya.
	--
	-- Y respetan la seleccion igual que antes: a los cogidos, o a todo el grupo
	-- si no hay nadie cogido.
	{ id = "sigueme", g = "Bots", name = "Sigueme", raw = true,
	  icon = "Ability_Rogue_Sprint", art = "sigueme",
	  cmd = { "/rts follow" },   d = "vuelve a seguirte" },
	{ id = "quieto",  g = "Bots", name = "Quieto", raw = true,
	  icon = "Ability_Warrior_DefensiveStance", art = "quieto",
	  cmd = { "/rts hold" },     d = "aguanta donde esta" },

	-- --- ORDENES NUESTRAS: las que el addon hace y playerbots no ---------
	--
	-- REUNIR ES TELETRANSPORTARLOS, y esto se corrigio el 2026-09-14: la
	-- casilla mandaba `/rts reunir`, que es la orden de MOVERSE a tu
	-- posicion -- los bots vienen andando, con su camino y su ritmo. Lo que
	-- se queria era traerlos de golpe, que es el verbo `summon` de
	-- playerbots (`SummonAction`: teleporta al bot al lado del maestro).
	--
	-- Los dos siguen existiendo y NO son lo mismo: `/rts reunir` los manda
	-- andando y esta casilla los trae. Si el servidor tiene
	-- `allowSummonInCombat` apagado, en pelea el bot contesta que no puede.
	--
	-- VA A TODO EL GRUPO, MIRE QUIEN MIRE LA SELECCION, y por eso sale por
	-- `/rtsall` y no por `/rtscmd`. Traer es una orden de reunirse: con dos
	-- bots seleccionados, "trae" tendria que traer a los cinco igual, y si
	-- dependiera de la seleccion dejaria a tres tirados sin decirlo -- que es
	-- justo lo que no se ve hasta que los buscas.
	--
	-- Y TRAE MAS SEGUIR, LAS DOS COSAS. Un bot que estaba en `stay` aterriza
	-- a tu lado y se queda ahi clavado: le has movido los pies pero no la
	-- orden. "Traer" significa "venid conmigo", asi que el seguir va dentro
	-- y no en una segunda casilla que haya que acordarse de pulsar.
	{ id = "reunir",  g = "Grupo", name = "Reunir", raw = true,
	  icon = "Spell_Arcane_TeleportOrgrimmar", art = "reunir",
	  cmd = { "/rts traer" },     d = "trae a TODO el grupo y te siguen" },
	-- CRANEO Y LUNA HACEN DOS COSAS DE UNA VEZ -- marcan tu objetivo y mandan
	-- al grupo a por esa marca -- y por eso no son `rti skull` a secas: la
	-- mitad de poner el icono es del cliente y la otra mitad del servidor.
	{ id = "craneo",  g = "Grupo", name = "Craneo", raw = true,
	  icon = "INV_Misc_Bone_HumanSkull_01",
	  cmd = { "/rts craneo" },   d = "craneo en tu objetivo: todos a por el" },
	{ id = "luna",    g = "Grupo", name = "Luna", raw = true,
	  icon = "Spell_Nature_Polymorph",
	  cmd = { "/rts luna" },     d = "luna en tu objetivo: que lo controlen" },
	{ id = "reset",   g = "Grupo", name = "Reset grupo", raw = true,
	  icon = "INV_Misc_PocketWatch_01",
	  cmd = { "/rts reset" },    d = "comportamiento de fabrica a todos" },
	{ id = "control", g = "Grupo", name = "Control", raw = true,
	  icon = "Spell_Shadow_Possession", art = "control",
	  cmd = { "/rts swap" },     d = "te CONVIERTES en el que tengas cogido" },

	-- --- LAS VENTANAS PROPIAS, LA CAMARA Y LA PUERTA ---------------------
	--
	-- SALIR COMO CASILLA TIENE UN PELIGRO y por eso esta escrito: el modo RTS
	-- esconde las barras de accion, asi que si el jugador no se pone "Modo RTS"
	-- en una casilla, la unica forma de salir es la tecla o `/rts mode`.
	{ id = "bolsas",   g = "Ventanas", name = "Bolsas", raw = true,
	  icon = "INV_Misc_Bag_09", art = "bolsas",
	  cmd = { "/rts bolsas" },   d = "las bolsas de TODO el grupo" },
	{ id = "misiones", g = "Ventanas", name = "Misiones", raw = true,
	  icon = "INV_Misc_Book_09",
	  cmd = { "/rts misiones" }, d = "el registro de misiones de TODO el grupo" },
	{ id = "candado",  g = "Ventanas", name = "Candado", raw = true,
	  icon = "INV_Misc_Key_03", art = "candado",
	  cmd = { "/rts fc lock" },  d = "clava la camara a tu heroe",
	  cmd2 = { "/rts fc ojos" },
	  d2 = "engancha la camara sobre el heroe: solo giras (ESPACIO/C suben y bajan)" },
	{ id = "camara",   g = "Ventanas", name = "Camara", raw = true,
	  icon = "INV_Misc_Spyglass_03",
	  cmd = { "/rts fc home" },  d = "devuelve la camara sobre tu heroe" },
	-- `/rts mode` Y NO `/rts` A SECAS: el comando pelado ensena la AYUDA --
	-- sesenta lineas en el chat -- y no toca el modo.
	{ id = "modo",     g = "Ventanas", name = "Modo RTS", raw = true,
	  icon = "Spell_ChargeNegative",
	  cmd = { "/rts mode" },     d = "entra y sale del modo RTS" },
}

A.LIST = LIST

local byId = {}
for _, e in ipairs(LIST) do byId[e.id] = e end

function A:Find(id)
	return id and byId[id] or nil
end

-- Devuelve la ruta y SI ES NUESTRA, que es lo que decide el recorte.
function A:Texture(entry)
	if not entry then return nil, false end
	if entry.art then return ART_DIR .. entry.art .. ".tga", true end
	return ICON_DIR .. (entry.icon or "INV_Misc_QuestionMark"), false
end

-- Pinta el icono de una orden en una textura ya creada. En un solo sitio
-- porque lo piden la casilla y el desplegable, y el recorte se olvida.
function A:Paint(tex, entry)
	local path, mine = self:Texture(entry)
	tex:SetTexture(path or "")
	if mine then
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end
	tex:SetVertexColor(1, 1, 1)
	tex:SetAlpha(1)
end

--- Lanzarlas --------------------------------------------------------------
--
-- Se despacha a MANO y no se busca por todo `SlashCmdList`. Son tres comandos,
-- todos nuestros, y una busqueda generica aceptaria en el catalogo lineas que
-- parecen funcionar y no funcionan -- `/cast`, sin ir mas lejos, que es
-- protegida y desde aqui no se puede lanzar ni aunque se encuentre.

-- Por donde sale una orden de bot. Es la misma cadena con la que `Macros.lua`
-- reconoce sus macros, y por eso no se escribe suelta en cada sitio.
local MARK = "/rtscmd"

local RUNNER = {
	["/rts"]     = "RTSCOMMAND",
	["/rtscmd"]  = "RTSCMD",
	["/rtsc"]    = "RTSCMD",
	["/rtsall"]  = "RTSALL",
}

local function RunLine(line)
	line = strtrim(line or "")
	if line == "" then return end

	local verb, rest = line:match("^(%S+)%s*(.-)$")
	local key = RUNNER[(verb or ""):lower()]
	local fn = key and SlashCmdList[key]
	if not fn then
		ns.Print("|cffff0000ordenes:|r no se de quien es |cffffff00" ..
			tostring(verb) .. "|r. Si lleva /cast o /use, tiene que ser un macro.")
		return
	end
	fn(rest or "")
end

-- LAS LINEAS DE UNA ORDEN, EN UN SOLO SITIO. Las piden dos caminos --
-- lanzarla y escribirla en un macro -- y componerlas dos veces es como se
-- acaba con una bandeja que hace una cosa y un macro del mismo nombre que
-- hace otra.
local function Lines(entry, alt)
	local out = {}
	for _, c in ipairs((alt and entry.cmd2) or entry.cmd) do
		table.insert(out, entry.raw and c or (MARK .. " " .. c))
	end
	return out
end

function A:Run(id, alt)
	local e = self:Find(id)
	if not e then
		ns.Print("|cffff8800ordenes:|r esa casilla apunta a |cffffff00" ..
			tostring(id) .. "|r, que ya no esta en el catalogo. " ..
			"Clic derecho encima para cambiarla.")
		return
	end
	-- Pedir la segunda de una orden que no la tiene no lanza la primera en su
	-- lugar: el jugador pidio otra cosa, y hacerle la que no pidio es peor que
	-- no hacer nada. Quien llama ya ha mirado si existe (`entry.cmd2`).
	if alt and not e.cmd2 then return end
	for _, line in ipairs(Lines(e, alt)) do RunLine(line) end
end

-- El cuerpo escrito: para el tooltip y para los macros de `Macros.lua`.
function A:Body(entry)
	return table.concat(Lines(entry), "\n")
end

--- Traer a los bots ------------------------------------------------------
--
-- `.playerbots bot add <nombres>` es un comando del SERVIDOR, no del addon: se
-- manda como si lo escribieras en el chat -- los que empiezan por punto los
-- atiende el servidor y no llegan a decirse en voz alta. Es el mismo camino que
-- ya usa el selfbot en `RTSMode.lua`, y no se puede hacer de otra forma: el
-- addon no tiene manera de llamar a un comando de GM.
--
-- LOS NOMBRES VAN PEGADOS A LAS COMAS, y esto no es estetica. mod-playerbots
-- parte la lista por comas (`split(charnameStr, ',')`, en `PlayerbotMgr.cpp`) y
-- NO quita los espacios; luego el servidor rechaza cualquier nombre que lleve
-- uno dentro -- `normalizePlayerName` devuelve falso en cuanto ve un espacio.
-- O sea que "Avy, Bob" mete a Avy y deja fuera a Bob, y lo unico que se ve es
-- un "Character ' Bob' not found" perdido entre las demas respuestas. Se junta
-- aqui y no puede escribirse mal.
--
-- LA LISTA ES DEL JUGADOR y se guarda por cuenta, pero viene con la suya
-- puesta: una casilla que hay que configurar antes de servir para algo no sirve
-- para nada. `/rts invitar lista <nombres>` la cambia sin tocar este fichero.

local BOTS = { "Neferite", "Kirinah", "Avy", "Secretaria", "Bob" }

local function Roster()
	local saved = RTSCommandDB and RTSCommandDB.bots
	if type(saved) == "table" and #saved > 0 then return saved end
	return BOTS
end

-- Vale con comas, con espacios o con las dos cosas: lo que separa nombres aqui
-- lo escribe una persona, no un programa.
local function SetRoster(text)
	local out = {}
	for name in tostring(text or ""):gmatch("[^%s,]+") do
		table.insert(out, name)
	end
	if #out == 0 or not RTSCommandDB then return nil end
	RTSCommandDB.bots = out
	return out
end

function A:Invite(rest)
	local sub, tail = strtrim(rest or ""):match("^(%S*)%s*(.-)$")

	if (sub or ""):lower() == "lista" or (sub or ""):lower() == "list" then
		if strtrim(tail or "") ~= "" and not SetRoster(tail) then
			ns.Print("|cffff8800invitar:|r no he entendido ningun nombre ahi.")
			return
		end
		ns.Print("|cffffff00tus bots|r: " .. table.concat(Roster(), ", "))
		ns.Print("Se cambian con |cffffff00/rts invitar lista <nombres>|r.")
		return
	end

	local names = table.concat(Roster(), ",")
	-- DECIR A QUIEN SE LLAMA, porque las respuestas del servidor vienen en
	-- ingles y en desorden ("ok", "player already logged in", "not found") y sin
	-- esta linea no se sabe ni a quien se le estaba hablando.
	ns.Print("|cffffff00trayendo|r: " .. table.concat(Roster(), ", "))
	SendChatMessage(".playerbots bot add " .. names, "SAY")
end

--- Traer al grupo --------------------------------------------------------
--
-- Dos ordenes que son una sola: `summon` los teletransporta a tu lado y
-- `follow` les quita el ancla. Ver el catalogo para el porque de que vayan
-- juntas.
--
-- NO SALE POR `/rtsall follow` sino por el camino del addon, que sabe soltar
-- la ruta dibujada y borrar la marca de "este esta quieto". Un `follow` dicho
-- a pelo por el chat deja las dos cosas puestas, y la siguiente orden de
-- moverse se comporta como si el bot siguiera anclado.

function A:Bring()
	if not ns.Orders:SummonAll() then return end
	ns.Print("|cffffff00traer|r: el grupo a tu lado")
	ns.Orders:FollowAll()
end

--- El desplegable ---------------------------------------------------------
--
-- Es NUESTRO y no `UIDropDownMenu` del cliente, por dos motivos que se ven en
-- cuanto se prueba: el suyo no sabe dibujar un icono en cada linea -- solo
-- texto y una marca de verificacion -- y su ancho y su tipografia son los del
-- juego, no los de esta consola.
--
-- SE CIERRA AL PINCHAR FUERA, y eso es un boton del tamano de la pantalla por
-- debajo del menu. Es la unica forma que hay: un frame no recibe aviso de que
-- han pinchado en otro sitio.

-- EN PIXELES FISICOS, como todo lo que cuelga del contenedor de `Pixels`. Una
-- fila de 22 seria correcta en unidades de pantalla y aqui es media linea de
-- texto: la fuente `small` mide 22 de ALTO. Esta es la trampa que `Widgets`
-- avisa en su cabecera, y se paga en cuanto se copia un numero de otro addon.
local ROW_H   = 30      -- alto de una orden
local HEAD_H  = 24      -- alto de un titulo de grupo
local MENU_W  = 250
local PAD     = 6

local menu, catcher, rows, heads
local pick                -- a quien avisar cuando se elija

local function Close()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end

A.Close = function(self) Close() end

function A:IsOpen()
	return menu and menu:IsShown() and true or false
end

local function Catcher()
	if catcher then return catcher end
	catcher = CreateFrame("Button", "RTSActionMenuCatcher", UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:SetFrameLevel(1)
	catcher:EnableMouse(true)
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", Close)
	catcher:Hide()
	return catcher
end

-- Una linea del menu. El icono a la izquierda y el nombre al lado: en vertical
-- y con doce opciones, el dibujo es lo que se encuentra antes que el texto.
local function Row(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(MENU_W)
	b:SetHeight(ROW_H)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetWidth(ROW_H - 6)
	b.icon:SetHeight(ROW_H - 6)
	b.icon:SetPoint("LEFT", b, "LEFT", 3, 0)

	b.label = ns.W:Text(b, ns.W.FONT.small)
	b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
	b.label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
	b.label:SetJustifyH("LEFT")

	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	return b
end

local function Build()
	if menu then return end

	menu = CreateFrame("Frame", "RTSActionMenu", ns.Pixels:Host() or UIParent)
	menu:SetFrameStrata("DIALOG")
	menu:SetFrameLevel(20)
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	ns.Skin:Dress(menu)
	menu:Hide()

	menu.title = ns.W:Text(menu, ns.W.FONT.small)
	menu.title:SetJustifyH("LEFT")

	rows, heads = {}, {}
end

-- Coloca titulos y lineas de una pasada y devuelve el alto total.
local function Fill(current)
	local inset = ns.Skin:Inset()
	local y = inset
	local nr, nh = 0, 0

	-- LAS DOS ESQUINAS DE ARRIBA, no arriba-izquierda y derecha a secas: un
	-- FontString anclado por TOPLEFT y por RIGHT tiene que cumplir "mi borde
	-- superior aqui" y "mi centro alli" a la vez, y lo resuelve estirandose.
	menu.title:ClearAllPoints()
	menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", inset + 2, -y)
	menu.title:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -inset, -y)
	y = y + HEAD_H + 2

	local group

	local function Place(f, h)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", menu, "TOPLEFT", inset, -y)
		f:Show()
		y = y + h
	end

	for _, e in ipairs(LIST) do
		if e.g ~= group then
			group = e.g
			nh = nh + 1
			local t = heads[nh]
			if not t then
				t = ns.W:Text(menu, ns.W.FONT.tiny)
				t:SetJustifyH("LEFT")
				heads[nh] = t
			end
			t:SetText("|cff88ccff" .. group .. "|r")
			Place(t, HEAD_H)
		end

		nr = nr + 1
		local b = rows[nr]
		if not b then
			b = Row(menu)
			rows[nr] = b
		end
		b.entry = e
		A:Paint(b.icon, e)
		-- LA QUE YA ESTA PUESTA SE MARCA. Sin esto, abrir el menu sobre una
		-- casilla llena no dice cual lleva dentro, y el jugador la cambia sin
		-- querer creyendo que estaba vacia.
		b.label:SetText((e.id == current and "|cffffd100" or "|cffffffff")
			.. e.name .. "|r")
		b:SetScript("OnClick", function(self)
			local fn = pick
			Close()
			if fn then fn(self.entry.id) end
		end)
		ns.W:Tip(b, e.name, e.d)
		Place(b, ROW_H)
	end

	-- VACIAR, SIEMPRE LA ULTIMA. Separada del catalogo por un hueco: no es una
	-- orden, es lo contrario de todas.
	nr = nr + 1
	local clear = rows[nr]
	if not clear then
		clear = Row(menu)
		rows[nr] = clear
	end
	clear.entry = nil
	clear.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	clear.icon:SetTexCoord(0, 1, 0, 1)
	clear.label:SetText("|cffff8888Vaciar la casilla|r")
	clear:SetScript("OnClick", function()
		local fn = pick
		Close()
		if fn then fn(false) end
	end)
	ns.W:Tip(clear, "Vaciar", "Deja la casilla libre.")
	y = y + 4
	Place(clear, ROW_H)

	-- Las sobrantes de una vez anterior. Se esconden, no se destruyen: un frame
	-- en 3.3.5a no se puede destruir y reusarlos es lo unico que evita
	-- fabricar doce cada vez que se abre el menu.
	for i = nr + 1, #rows do rows[i]:Hide() end
	for i = nh + 1, #heads do heads[i]:SetText("") end

	return y + inset
end

-- `anchor` es la casilla. El menu se abre a su IZQUIERDA y HACIA ARRIBA, que es
-- hacia donde hay sitio: la bandeja vive pegada a la esquina de abajo a la
-- derecha, asi que un menu que creciera hacia abajo se saldria de la pantalla
-- entero. `SetClampedToScreen` es la red por si aun asi no cabe.
function A:Open(anchor, title, current, onPick)
	if self:IsOpen() then
		Close()
		-- Volver a pinchar la MISMA casilla lo cierra; otra distinta lo mueve.
		if menu.anchor == anchor then return end
	end

	Build()
	pick = onPick
	menu.anchor = anchor
	menu.title:SetText("|cffffd100" .. (title or "Elige una orden") .. "|r")

	local h = Fill(current)
	menu:SetWidth(MENU_W + ns.Skin:Inset() * 2)
	menu:SetHeight(h)
	menu:ClearAllPoints()
	menu:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -PAD, 0)

	Catcher():Show()
	menu:Show()
end

--- Decirlo por pantalla ---------------------------------------------------
--
-- UNA TEXTURA QUE NO CARGA NO DA ERROR: deja el boton en blanco. Asi que la
-- unica forma de contestar a "algunos iconos no se ven" es preguntarselo al
-- cliente uno por uno, y eso es lo que hace esto.
--
-- El oraculo es el de `/rts art scan`: se le da la ruta a una textura
-- escondida y se le vuelve a preguntar cual tiene. Si devuelve nil, el fichero
-- no esta donde se dice. PUEDE QUE NO SIRVA -- en 3.3.5a no esta claro que
-- `GetTexture()` distinga una ruta buena de una mala -- y por eso el informe
-- dice las dos lecturas en vez de una sola: si todas contestan que si y aun
-- asi hay casillas en blanco, el oraculo miente y la causa es otra.

local probe

local function Loads(path)
	if not probe then
		local f = CreateFrame("Frame")
		f:Hide()
		probe = f:CreateTexture(nil, "ARTWORK")
	end
	probe:SetTexture(nil)
	probe:SetTexture(path)
	return probe:GetTexture() and true or false
end

function A:Report()
	ns.Print("|cffffff00ordenes|r -- lo que cabe en una casilla de la bandeja:")

	local group, bad = nil, {}
	for _, e in ipairs(LIST) do
		if e.g ~= group then
			group = e.g
			ns.Print("  |cff88ccff" .. group .. "|r")
		end

		local path, mine = self:Texture(e)
		local ok = Loads(path)
		if not ok then table.insert(bad, { e = e, path = path }) end

		ns.Print(("    %s%-12s|r %s%s"):format(
			ok and "|cffffffff" or "|cffff4040", e.name, e.d,
			mine and "  |cff888888(icono propio)|r" or ""))
	end

	if #bad > 0 then
		ns.Print(("|cffff4040%d icono(s) no cargan|r:"):format(#bad))
		for _, b in ipairs(bad) do
			ns.Print("    " .. b.path)
		end
		ns.Print("Si es uno |cffffff00propio|r: falta desplegar el addon, o el " ..
			"fichero no se llama igual que el `art` de la orden.")
	else
		ns.Print("Todos los iconos |cff00ff00contestan que si|r.")
		ns.Print("Si aun asi ves una casilla en blanco, es el CLIENTE: una textura " ..
			"que ya se intento cargar se queda como esta toda la sesion. " ..
			"|cffffff00Cierra el WoW y vuelve a entrar|r -- con /reload no basta.")
	end

	ns.Print("Se ponen con |cffffff00clic derecho|r sobre una casilla de la derecha.")
end
