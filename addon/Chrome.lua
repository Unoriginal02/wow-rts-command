--[[
	Chrome.lua -- la opcion B del estudio: ocultado selectivo.

	`UIParent:Hide()` (opcion A) se lleva por delante el botin, el gossip, las
	bolsas, las ventanas emergentes y el menu de escape -- es decir, deja el
	modo RTS injugable hasta que las diez ventanas esten reparentadas. Aqui se
	esconde SOLO lo que estorba, una lista enumerada a mano, y todo lo demas
	sigue funcionando solo.

	La regla dura de siempre: el modo RTS solo afecta al modo RTS. De cada
	frame se guarda si estaba visible ANTES de tocarlo y se le devuelve ese
	mismo estado al salir -- no un Show() a ciegas, que encenderia barras que
	el jugador tenia apagadas en las opciones.

	Tres cosas que no son obvias y que decidieron la forma del fichero:

	- Un frame protegido NO se puede esconder en combate. PlayerFrame,
	  MainMenuBar y las barras de accion lo son, y un Hide() sobre ellos dentro
	  de combate suelta el clasico "blocked from an action only available to
	  the Blizzard UI". Cada entrada lleva su bandera `p`, y las protegidas se
	  aplazan a PLAYER_REGEN_ENABLED igual que Camera.lua aplaza sus teclas.
	- Blizzard vuelve a encender cosas por su cuenta. Salir de un vehiculo,
	  cambiar de zona o una alerta reponen MainMenuBar o PlayerFrame. Un barrido
	  cada medio segundo los vuelve a esconder mientras el modo esta activo. Es
	  mas barato que pelearse con los eventos que lo provocan.
	- El tooltip no se esconde con Hide(). Se vuelve a mostrar en cada
	  mouseover, asi que se engancha su OnShow. Por eso es el unico caso
	  especial de la tabla.

	El chat entra en la lista porque estaba rodeado en el boceto, y eso deja al
	addon sin su canal de diagnostico -- que es justo lo que el estudio marcaba
	como "no opcional". La respuesta es la linea de mensajes de HUD.lua, que
	replica ns.Print sobre el mundo. Si algo va mal y hace falta el chat de
	verdad: /rts ui chat.
]]

local ADDON, ns = ...

local C = {}
ns.Chrome = C

C.active = false

--- Que se esconde ----------------------------------------------------------
--
-- `n` nombre global, `s` conjunto al que pertenece (lo que se enciende y apaga
-- desde el comando), `p` protegido -> no se puede tocar en combate.
--
-- Un nombre que no exista en este cliente simplemente se ignora: la lista lleva
-- frames de clases concretas (runas, totems, formas) y de situaciones concretas
-- (vehiculos), y comprobar cada uno a mano seria peor que dejar que falte.

local ITEMS = {
	-- Arriba izquierda: tu marco, el del objetivo y los del grupo.
	-- Solo los padres: PetFrame, RuneFrame, ComboFrame y los "del objetivo del
	-- objetivo" son hijos suyos y se van con ellos. Enumerarlos ademas solo
	-- servia para devolver alguno en un estado ya caducado al salir.
	{ n = "PlayerFrame",            s = "player", p = true  },
	{ n = "TargetFrame",            s = "target", p = true  },
	{ n = "FocusFrame",             s = "target", p = true  },
	{ n = "PartyMemberFrame1",      s = "party",  p = true  },
	{ n = "PartyMemberFrame2",      s = "party",  p = true  },
	{ n = "PartyMemberFrame3",      s = "party",  p = true  },
	{ n = "PartyMemberFrame4",      s = "party",  p = true  },
	{ n = "PartyMemberBackground",  s = "party"             },
	-- Los de banda los crea Blizzard_RaidUI cuando hace falta, asi que lo
	-- normal es que no existan: la tabla ignora un nombre que no este, y
	-- enumerarlos aqui es lo que hace que el conjunto `party` cumpla lo que
	-- dice su etiqueta el dia que se vuelva a encender.
	{ n = "RaidPulloutFrame1",      s = "party"             },
	{ n = "RaidPulloutFrame2",      s = "party"             },
	{ n = "RaidPulloutFrame3",      s = "party"             },
	{ n = "RaidPulloutFrame4",      s = "party"             },
	{ n = "RaidPulloutFrame5",      s = "party"             },
	{ n = "RaidPulloutFrame6",      s = "party"             },
	{ n = "RaidPulloutFrame7",      s = "party"             },
	{ n = "RaidPulloutFrame8",      s = "party"             },
	{ n = "CastingBarFrame",        s = "cast"              },
	{ n = "PetCastingBarFrame",     s = "cast"              },
	{ n = "MirrorTimer1",           s = "cast"              },
	{ n = "MirrorTimer2",           s = "cast"              },
	{ n = "MirrorTimer3",           s = "cast"              },

	-- Buffs y debuffs, arriba a la derecha bajo el minimapa.
	{ n = "BuffFrame",              s = "buffs"             },
	{ n = "ConsolidatedBuffs",      s = "buffs"             },
	{ n = "TemporaryEnchantFrame",  s = "buffs"             },

	-- Arriba derecha: el minimapa entero (reloj, tracking, correo, zoom).
	-- HUD.lua saca el Minimap de aqui ANTES de que esto se esconda, asi que
	-- esconder el cluster no se lleva el mapa: se lleva su marco y sus botones,
	-- que es lo que se queria.
	{ n = "MinimapCluster",         s = "minimap"           },
	{ n = "BattlefieldMinimap",     s = "minimap"           },

	-- Barras de accion: el fondo de la pantalla y las dos columnas de la
	-- derecha. MainMenuBar arrastra la barra de XP, las bolsas y el menu de
	-- iconos, que son hijos suyos.
	{ n = "MainMenuBar",              s = "bars", p = true },
	{ n = "MainMenuBarArtFrame",      s = "bars", p = true },
	{ n = "MultiBarBottomLeft",       s = "bars", p = true },
	{ n = "MultiBarBottomRight",      s = "bars", p = true },
	-- LAS DOS VERTICALES DE LA DERECHA SON SU PROPIO CONJUNTO desde 2026-09-11,
	-- y de fabrica SE QUEDAN. Son el sitio donde el jugador pone sus macros de
	-- ordenes a los bots (`/rts macros`), o sea que esconderlas con el resto de
	-- barras dejaba el modo RTS sin el unico hueco de la interfaz de Blizzard
	-- que aqui hace falta. Son hijas de UIParent -- comprobado en
	-- `MultiActionBars.xml` del cliente -- asi que esconder `MainMenuBar` no se
	-- las lleva, y `MultiBarLeft` cuelga de `MultiBarRight`: mover una mueve las
	-- dos. Ver el bloque de LEVANTAR mas abajo.
	{ n = "MultiBarLeft",             s = "side", p = true },
	{ n = "MultiBarRight",            s = "side", p = true },
	{ n = "ShapeshiftBarFrame",       s = "bars", p = true },
	{ n = "PetActionBarFrame",        s = "bars", p = true },
	{ n = "BonusActionBarFrame",      s = "bars", p = true },
	{ n = "MultiCastActionBarFrame",  s = "bars", p = true },
	{ n = "VehicleMenuBar",           s = "bars", p = true },
	{ n = "MainMenuBarVehicleLeaveButton", s = "bars", p = true },
	{ n = "ExhaustionTick",           s = "bars"           },
	{ n = "ReputationWatchBar",       s = "bars"           },

	-- Abajo izquierda: chat, pestanas y los botones de voz.
	-- (las siete ventanas se anaden mas abajo en un bucle)
	{ n = "ChatFrameMenuButton",               s = "chat" },
	{ n = "ChatFrameChannelButton",            s = "chat" },
	{ n = "ChatFrameToggleVoiceDeafenButton",  s = "chat" },
	{ n = "ChatFrameToggleVoiceMuteButton",    s = "chat" },
	{ n = "GeneralDockManager",                s = "chat" },
	{ n = "CombatLogQuickButtonFrame_Custom",  s = "chat" },

	-- Derecha: seguimiento de misiones, durabilidad, avisos de zona.
	{ n = "QuestWatchFrame",         s = "quest"  },
	{ n = "QuestTimerFrame",         s = "quest"  },
	{ n = "DurabilityFrame",         s = "misc"   },
	{ n = "TicketStatusFrame",       s = "misc"   },
	{ n = "WorldStateAlwaysUpFrame", s = "misc"   },

	-- Abajo derecha: el tooltip de unidad. Caso especial -- se vuelve a
	-- mostrar en cada mouseover, asi que Hide() no basta.
	{ n = "GameTooltip",             s = "tooltip", special = "tooltip" },
}

for i = 1, 7 do
	table.insert(ITEMS, { n = "ChatFrame" .. i,          s = "chat" })
	table.insert(ITEMS, { n = "ChatFrame" .. i .. "Tab", s = "chat" })
end

-- Orden y etiqueta de cada conjunto, para /rts ui y para el informe. Una tabla
-- aparte porque pairs() no tiene orden y la lista tiene que salir siempre igual.
local SETS = {
	{ k = "player",  d = "tu marco, mascota, runas" },
	{ k = "target",  d = "objetivo, objetivo del objetivo, foco" },
	{ k = "party",   d = "marcos de los companeros" },
	{ k = "cast",    d = "barra de casteo y temporizadores" },
	{ k = "buffs",   d = "buffs y debuffs" },
	{ k = "minimap", d = "minimapa de Blizzard (el nuestro lo sustituye)" },
	{ k = "bars",    d = "barras de accion, bolsas, XP, menu de iconos" },
	{ k = "side",    d = "las dos verticales de la derecha (de fabrica SE QUEDAN)" },
	{ k = "chat",    d = "ventanas de chat y sus botones" },
	{ k = "quest",   d = "seguimiento de misiones" },
	{ k = "misc",    d = "durabilidad, avisos, marcadores de zona" },
	{ k = "tooltip", d = "tooltip de unidad (de fabrica SE QUEDA)" },
}

C.SETS = SETS

-- ESCONDIDOS POR DEFECTO, INCLUIDOS TU MARCO Y LOS DEL GRUPO desde 2026-09-06.
--
-- Estuvieron a la vista desde el 2026-09-02 por un motivo que ya no existe: la
-- sala del centro se habia vaciado para redisenarla, y con ella se fue lo unico
-- que decia tu vida, tu poder y la del grupo -- esconder ademas los marcos de
-- Blizzard habria dejado el modo RTS sin NINGUN estado en pantalla. El
-- comentario de entonces lo decia entero: *"donde acaben viviendo es una
-- decision del rediseno de la sala, no de este fichero"*.
--
-- La sala se lleno el 2026-09-04: el retrato del heroe con su vida y su poder, y
-- la columna de cinco con la de cada companero. La razon de la excepcion se
-- cumplio, asi que la excepcion se va -- y ahora eran DOS dibujos de lo mismo,
-- uno encima del otro.
--
-- EL OBJETIVO TAMBIEN SE ESCONDE desde 2026-09-11, pedido por el jugador.
-- Estaba a la vista porque la sala ensena el objetivo del BOT seleccionado, que
-- no es el tuyo, asi que no habia duplicado que quitar -- pero la razon para
-- dejarlo puesto era que no estorbaba, y estorba. El objetivo del objetivo y el
-- foco son hijos suyos y se van con el.
--
-- Se quedan de fabrica dos:
--
--   `side`, las dos barras verticales de la derecha, que son donde el jugador
--   pone sus macros de mando (`/rts macros`).
--
--   `tooltip`, el rotulo de unidad de abajo a la derecha, DESDE 2026-09-13 y
--   pedido por el jugador. Entro en la lista con el resto del cromo por ser
--   cromo, y esa razon era floja: no ocupa sitio fijo, no duplica nada de la
--   sala y es lo UNICO que dice quien es el bicho que tienes debajo del raton
--   -- nivel, faccion, si es un vendedor. El modo RTS es un modo de mando y
--   mandar sobre algo sin nombre no se puede.
--
-- Se siguen pudiendo cambiar todos con /rts ui <conjunto>.
local SHOW_BY_DEFAULT = { side = true, tooltip = true }

-- Se sube cuando cambia lo que significa una clave guardada de `uiHide`.
--
-- A 3 el 2026-09-06: `player` y `party` cambian de valor de fabrica, y una
-- preferencia guardada bajo el defecto viejo los dejaria a la vista para
-- siempre sin que nada lo explicara. Es la misma purga que `railCropGen`.
--
-- A 4 el 2026-09-11: `target` pasa a esconderse y NACE `side`. Las dos barras
-- verticales estaban dentro de `bars`, asi que quien tuviera `bars` guardado
-- (encendido o apagado) llevaria ese valor a un conjunto que ya no significa lo
-- mismo. Es exactamente el caso que el sello existe para cubrir: comparar el
-- rango no basta cuando lo que cambia es lo que la clave SIGNIFICA.
--
-- A 5 el 2026-09-13: `tooltip` pasa a quedarse. Aqui no cambia lo que la clave
-- significa, cambia el valor de fabrica -- el mismo caso que `player` y `party`
-- en la generacion 3 -- y sin subir el sello quien haya entrado alguna vez en
-- modo RTS llevaria el `true` viejo guardado y seguiria sin tooltip para
-- siempre, buscando el fallo en el codigo que ya esta arreglado.
local UIHIDE_GEN = 5

C.hide = {}
for _, s in ipairs(SETS) do C.hide[s.k] = not SHOW_BY_DEFAULT[s.k] end

--- Aparcar y devolver ------------------------------------------------------

local parked = {}       -- [nombre] = { shown = bool }
local pending = false   -- queda algo protegido por aplicar cuando salga el combate

-- El asomo del chat. Ver Peek() mas abajo: mientras esta puesto, el conjunto
-- `chat` se comporta como si no estuviera en la lista, sin tocar la
-- preferencia guardada.
C.peek = false
local peekUntil = nil
local PEEK_LINGER = 8   -- segundos que se queda el chat despues de escribir

local function Wanted(item)
	if not C.active then return false end
	if item.s == "chat" and C.peek then return false end
	return C.hide[item.s] and true or false
end

-- Devuelven false si no se ha podido tocar por combate, para que el que llama
-- sepa que queda trabajo pendiente.
local function Park(item)
	if parked[item.n] then return true end
	local f = _G[item.n]
	if not f then return true end
	if item.p and InCombatLockdown() then return false end
	parked[item.n] = { shown = f:IsShown() }
	f:Hide()
	return true
end

local function Unpark(item)
	local rec = parked[item.n]
	if not rec then return true end
	local f = _G[item.n]
	if not f then parked[item.n] = nil return true end
	if item.p and InCombatLockdown() then return false end
	-- El estado de ANTES, no un Show() a ciegas: una barra que el jugador tenia
	-- apagada en las opciones tiene que seguir apagada al salir.
	if rec.shown then f:Show() else f:Hide() end
	parked[item.n] = nil
	return true
end

--- LEVANTAR LAS DOS VERTICALES SOBRE LA CONSOLA ---------------------------
--
-- Dejarlas visibles no basta: `MultiBarRight` esta anclada a 98 pixeles del
-- borde de abajo (`MultiActionBars.xml` del cliente) y la consola ocupa el 20%
-- del alto de pantalla, o sea unos 216 en 1080p. Los tres botones de abajo de
-- cada columna quedan DETRAS de la barra -- visibles a medias y sin poder
-- pulsarlos, que es la version cara de "esta puesto pero no funciona".
--
-- Asi que se sube el ancla justo por encima de la consola mientras dure el modo
-- RTS, y se devuelve al salir. Capturar y devolver, como todo lo demas de este
-- fichero: se guarda el punto EXACTO que tenia antes del primer cambio.
--
-- `MultiBarLeft` cuelga de `MultiBarRight`, asi que mover una mueve las dos.
-- Y solo se mueve SI HACE FALTA: con una consola baja, o con las barras ya
-- colocadas mas arriba por el propio jugador, no se toca nada.
--
-- Es un frame protegido: en combate no se puede mover, asi que devuelve false
-- y el aplazamiento a PLAYER_REGEN_ENABLED que ya existe se encarga.

local LIFT_ANCHOR = "MultiBarRight"
local LIFT_GAP = 10        -- pixeles entre el techo de la consola y la barra

local lifted = nil         -- { point, rel, relPoint, x, y } de ANTES de tocarla
local liftedTo = nil       -- el y que se aplico, para no reescribirlo cada tick

-- El techo de la consola, en las coordenadas de `frame`. Sin esto sale mal en
-- cuanto la barra tiene escala propia, que la tiene: `HUD:ScaleFrame` se la
-- pone y `ArtScale` la multiplica.
local function ConsoleTopIn(frame)
	local bar = _G.RTSBar
	if not bar or not bar:IsShown() then return nil end
	local top = bar:GetTop()
	if not top then return nil end
	local es = frame:GetEffectiveScale()
	if not es or es == 0 then return nil end
	return top * bar:GetEffectiveScale() / es
end

local function LiftDown()
	if not lifted then return true end
	local f = _G[LIFT_ANCHOR]
	if not f then lifted, liftedTo = nil, nil return true end
	if InCombatLockdown() then return false end
	f:ClearAllPoints()
	f:SetPoint(lifted[1], lifted[2] or f:GetParent(), lifted[3] or lifted[1],
		lifted[4] or 0, lifted[5] or 0)
	lifted, liftedTo = nil, nil
	return true
end

local function LiftUp()
	local f = _G[LIFT_ANCHOR]
	if not f then return true end

	-- Un ancla con varios puntos no es la de fabrica: la ha movido otro addon y
	-- devolverla seria adivinar. Se deja en paz.
	if f:GetNumPoints() ~= 1 then return true end

	local want = ConsoleTopIn(f)
	if not want then return true end
	want = want + LIFT_GAP

	local p, rel, rp, x, y = f:GetPoint(1)
	if not p then return true end

	-- Ya esta por encima por su cuenta: no hay nada que levantar. Se compara
	-- contra el sitio ORIGINAL cuando ya lo hemos movido nosotros, no contra el
	-- sitio al que lo movimos -- si no, bajar la consola no lo bajaria nunca.
	local base = lifted and lifted[5] or y or 0
	if base >= want then return LiftDown() end

	-- Nada que hacer solo si el sitio que queremos no ha cambiado Y la barra
	-- sigue puesta ahi. Mirar solo lo nuestro daria por hecho que nadie mas
	-- la ha movido, y Blizzard recoloca frames por su cuenta.
	if liftedTo and math.abs(liftedTo - want) < 1
	   and y and math.abs(y - want) < 1 then
		return true
	end
	if InCombatLockdown() then return false end

	if not lifted then lifted = { p, rel, rp, x, y } end
	f:ClearAllPoints()
	f:SetPoint(lifted[1], lifted[2] or f:GetParent(), lifted[3] or lifted[1],
		lifted[4] or 0, want)
	liftedTo = want
	return true
end

-- Levantada mientras el modo esta activo Y las dos barras se quedan a la vista.
-- Si el jugador las esconde con `/rts ui side` no hay nada que levantar.
local function ApplyLift()
	if C.active and not C.hide.side then return LiftUp() end
	return LiftDown()
end

--- QUE TOOLTIP ES EL DE UNIDAD -------------------------------------------
--
-- El conjunto `tooltip` dice "tooltip de unidad", y eso es lo unico que tenia
-- que esconder: el rotulo que sale sobre un bicho del mundo, que es cromo de
-- Blizzard igual que el marco del objetivo.
--
-- LA REGLA ANTERIOR ERA LA CONTRARIA: se escondia TODO lo que no fuera nuestro.
-- `GameTooltip` es un objeto UNICO, asi que esa regla no se llevaba solo el
-- tooltip del mundo -- se llevaba el del botin, el del vendedor, el de la
-- ficha, el de la bolsa de Blizzard y el del boton de compartir mision del
-- registro. Ventanas que el modo RTS deja a la vista a proposito (`Chrome`
-- esconde una lista escrita a mano y el botin no esta en ella) y que sin
-- tooltip no sirven para nada: un cadaver con cuatro iconos y ni un nombre.
--
-- El sintoma llega siempre igual de lejos de la causa -- "no hay tooltip" se
-- lee como "no se escribio" -- y ya paso una vez con la barra de control
-- (PRUEBAS-18 C4, el motivo por el que nacio `ns.IsOurs`). Aquello arreglo
-- media excepcion; esta es la otra mitad.
--
-- EL DUENO ES QUIEN LO SEPARA. Cualquier tooltip que salga porque el raton
-- esta encima de un frame tiene por dueno ESE frame: el boton del botin, la
-- casilla del vendedor, el micro-boton del rail. El del mundo no tiene frame
-- debajo, asi que el cliente lo ancla por defecto y su dueno es `UIParent`
-- -- es el mismo `GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)` que
-- cualquier addon de tooltips engancha para moverlo de sitio.
--
-- `WorldFrame` y el dueno vacio entran por si acaso: los dos significan lo
-- mismo (nadie lo pidio desde un frame de interfaz) y ninguno es una ventana.
local function IsWorldTip(tip)
	local owner = tip:GetOwner()
	return owner == nil or owner == UIParent or owner == WorldFrame
end

--- EL TOOLTIP DE UNIDAD, POR ENCIMA DE LA CONSOLA -------------------------
--
-- Sale abajo a la derecha -- `GameTooltip_SetDefaultAnchor` lo clava en la
-- esquina -- y ahi es donde esta la consola: el rotulo caia ENCIMA de las
-- ordenes, tapando media rejilla justo cuando estas mirando al bicho al que se
-- las vas a dar. Se sube al mismo sitio al que se suben las dos barras
-- verticales, con el mismo hueco, que es lo que hace que los tres se alineen
-- sin que nadie lo calcule dos veces.
--
-- SE RECONOCE POR EL ANCLA, NO POR EL DUENO. Lo que hay que subir es todo lo
-- que este aparcado en la esquina de abajo a la derecha, venga de donde venga:
-- el del mundo y cualquier otro que use el ancla por defecto acaban igual de
-- tapados. Y un tooltip que no este en esa esquina es que alguien lo puso a
-- mano en otro sitio -- suyo es, no se toca.
--
-- NO HAY NADA QUE DEVOLVER al salir del modo: el ancla se vuelve a escribir
-- entera en cada aparicion, asi que en cuanto esto deja de correr el tooltip
-- vuelve solo a su esquina.
--
-- La `x` se respeta TAL CUAL viene. Es `CONTAINER_OFFSET_X`, que el cliente ya
-- mueve segun cuantas barras verticales haya a la derecha: escribirla nosotros
-- seria volver a resolver -- peor -- algo que ya viene resuelto.
local TIP_GAP = 10   -- pixeles entre el techo de la consola y el tooltip

local function LiftWorldTip(tip)
	if not C.active or not tip or not tip.GetNumPoints then return end
	if tip:GetNumPoints() ~= 1 then return end

	-- `rel` vacio es `UIParent` igual: el tooltip cuelga de el, y un ancla sin
	-- `relativeTo` se lee contra el padre. Lo que descarta de verdad es un ancla
	-- a OTRO frame, que significa que alguien lo puso a mano.
	local point, rel, relPoint, x, y = tip:GetPoint(1)
	if relPoint ~= "BOTTOMRIGHT" then return end
	if rel and rel ~= UIParent then return end
	rel = rel or UIParent

	local want = ConsoleTopIn(tip)
	if not want then return end
	want = want + TIP_GAP

	-- Ya esta por encima: puede ser que la consola sea baja o que el jugador la
	-- tenga escondida. Subirlo igualmente seria bajarlo.
	if (y or 0) >= want then return end

	tip:ClearAllPoints()
	tip:SetPoint(point, rel, relPoint, x or 0, want)
end

-- Un unico sitio que decide, para cada frame, si deberia estar aparcado ahora
-- mismo. Entrar, salir, encender un conjunto y el aviso de fin de combate son
-- todos la misma operacion, que es lo que impide que se desincronicen.
function C:Apply()
	local blocked = false
	for _, item in ipairs(ITEMS) do
		if item.special ~= "tooltip" then
			local ok
			if Wanted(item) then ok = Park(item) else ok = Unpark(item) end
			if not ok then blocked = true end
		end
	end

	if not ApplyLift() then blocked = true end

	if self.active and self.hide.tooltip and GameTooltip:IsShown()
	   and IsWorldTip(GameTooltip) then
		GameTooltip:Hide()
	end

	pending = blocked
	return not blocked
end

--- El barrido --------------------------------------------------------------
-- Blizzard repone MainMenuBar al salir de un vehiculo, PlayerFrame en algunos
-- cambios de zona, y los marcos de grupo cada vez que entra o sale un bot.
-- Perseguir cada evento seria una lista que se queda corta; medio segundo de
-- barrido no se nota y no se queda corto nunca.

local sweeper

local function EnsureSweeper()
	if sweeper then return end
	sweeper = CreateFrame("Frame", "RTSChromeSweeper")
	sweeper:Hide()
	local acc = 0
	sweeper:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		if not C.active then return end
		-- El asomo caduca aqui, en el mismo tick que repone lo demas.
		if C.peek and peekUntil and GetTime() > peekUntil then
			C.peek, peekUntil = false, nil
			C:Apply()
		end

		-- La consola cambia de alto con `/rts bar share` y con la resolucion,
		-- asi que a que altura van las dos verticales se revisa cada barrido.
		-- Cuesta una resta salvo el tick en que de verdad cambia.
		ApplyLift()

		for _, item in ipairs(ITEMS) do
			-- Wanted y no C.hide: mientras el chat esta asomado NO se le puede
			-- volver a esconder por debajo, o desapareceria a media frase.
			if item.special ~= "tooltip" and Wanted(item) then
				local f = _G[item.n]
				if f and f:IsShown() and not (item.p and InCombatLockdown()) then
					-- Si vuelve a aparecer sin haber pasado por Park (Blizzard
					-- lo repuso), se anota igual para poder devolverlo luego.
					if not parked[item.n] then parked[item.n] = { shown = true } end
					f:Hide()
				end
			end
		end
	end)
end

--- Entrar y salir ----------------------------------------------------------

function C:Enter()
	if self.active then return end
	EnsureSweeper()
	self.active = true
	sweeper:Show()
	self:Apply()
	if pending then
		ns.Print("Parte de la interfaz es protegida y estas en combate: " ..
			"se esconde en cuanto salgas de el.")
	end
end

--- El chat asomado al escribir ---------------------------------------------
--
-- LA CAJA DE TEXTO ES HIJA DE ChatFrame1. Esconder el chat la esconde con el,
-- asi que al pulsar Intro se escribia A CIEGAS: ni lo que tecleabas ni la
-- respuesta. No es un detalle estetico, es no poder hablar.
--
-- La solucion no es reparentar la caja -- Blizzard la reancla ella sola cada
-- vez que la activa, y esa pelea no se gana. Se engancha `ChatFrame_OpenChat`,
-- que es la funcion que llama la tecla Intro, y se deja el chat A LA VISTA
-- mientras dure la conversacion; al soltar el foco se queda unos segundos mas
-- para poder leer la respuesta, y luego se va solo.
--
-- Enganchar la funcion global en vez del OnEditFocusGained de la caja es lo
-- que hace que funcione: un frame invisible no coge el foco, asi que su propio
-- script podria no llegar a dispararse nunca.

function C:Peek()
	peekUntil = nil
	if not self.peek then
		self.peek = true
		self:Apply()
	end
end

function C:PeekEnd()
	peekUntil = GetTime() + PEEK_LINGER
end

function C:Leave()
	if not self.active then return end
	self.active = false
	self.peek, peekUntil = false, nil
	if sweeper then sweeper:Hide() end
	self:Apply()
	if pending then
		ns.Print("|cffffff00Parte de la interfaz vuelve al salir de combate|r " ..
			"-- un frame protegido no se puede tocar dentro.")
	end
end

--- Encender y apagar un conjunto suelto ------------------------------------

function C:SetHidden(key, want)
	if self.hide[key] == nil then return false end
	if want == nil then want = not self.hide[key] end
	self.hide[key] = want and true or false
	RTSCommandDB.uiHide = RTSCommandDB.uiHide or {}
	RTSCommandDB.uiHide[key] = self.hide[key]
	self:Apply()
	return true
end

function C:Status()
	ns.Print(("interfaz de Blizzard: %s"):format(
		self.active and "|cff00ff00oculta (modo RTS)|r" or "|cffffff00normal|r"))
	for _, s in ipairs(SETS) do
		local total, present = 0, 0
		for _, item in ipairs(ITEMS) do
			if item.s == s.k then
				total = total + 1
				if _G[item.n] then present = present + 1 end
			end
		end
		ns.Print(("  |cffffff00%-8s|r %s  (%d/%d frames) - %s"):format(
			s.k,
			self.hide[s.k] and "|cffff4040ocultar|r" or "|cff40ff40dejar|r",
			present, total, s.d))
	end
	ns.Print("|cffffff00/rts ui <conjunto>|r enciende o apaga uno; el cambio se guarda.")
end

--- Que ha quedado encendido ------------------------------------------------
--
-- Cuando algo sigue viendose en modo RTS, la pregunta no es "por que" sino
-- "COMO SE LLAMA": anadirlo a la lista es una linea, pero adivinar el nombre
-- del frame mirando la pantalla es media tarde. Esto los enumera.
--
-- Sale compacto a proposito: con el chat escondido solo hay nueve lineas de
-- mensajes, asi que van varios nombres por linea en vez de uno por linea.

function C:What()
	local names = {}
	for _, kid in ipairs({ UIParent:GetChildren() }) do
		local n = kid:GetName()
		if n and kid:IsVisible() and not n:find("^RTS")
			and (kid:GetWidth() or 0) > 24 and (kid:GetHeight() or 0) > 16 then
			table.insert(names, n)
		end
	end
	table.sort(names)

	ns.Print(("%d frames visibles colgados de UIParent:"):format(#names))
	local line = "  "
	for _, n in ipairs(names) do
		if line:len() + n:len() > 68 then
			ns.Print(line)
			line = "  "
		end
		line = line .. n .. "   "
	end
	if line ~= "  " then ns.Print(line) end
	ns.Print("El que sobre de ahi, dimelo y entra en la lista.")
end

--- Cargar la configuracion guardada ----------------------------------------

function C:Create()
	EnsureSweeper()

	-- LO GUARDADO SOBREVIVE AL CAMBIO DE DEFECTO, y aqui eso seria justo el
	-- fallo: quien haya tocado alguna vez /rts ui player|target|party tiene un
	-- `true` guardado de cuando el defecto era esconderlo todo, asi que el
	-- cambio de arriba no se veria y el sintoma seria "los marcos siguen sin
	-- volver". Se tiran esas tres claves UNA vez, con sello de generacion --
	-- comprobar el valor no basta cuando lo que cambia es lo que el valor
	-- significaba. Misma familia que `grow = 688`, `camHold` y `railCropGen`.
	-- LA PURGA TIRA LA TABLA ENTERA, y hasta hoy no lo hacia: borraba solo las
	-- claves de `SHOW_BY_DEFAULT`. Eso funciona mientras esa tabla CREZCA, y se
	-- rompe en silencio en cuanto encoge -- que es justo lo que paso el
	-- 2026-09-06 al sacar de ahi `player` y `party`: sus valores guardados bajo
	-- el defecto viejo habrian sobrevivido a la purga hecha para ellos.
	--
	-- Una generacion significa "lo guardado ya no quiere decir lo mismo", asi
	-- que lo unico coherente es no fiarse de nada de lo guardado. El precio --
	-- perder los ajustes que el jugador si habia tocado -- se paga DICIENDOLO,
	-- que es la diferencia entre una purga y una perdida.
	if RTSCommandDB.uiHideGen ~= UIHIDE_GEN then
		if type(RTSCommandDB.uiHide) == "table" and next(RTSCommandDB.uiHide) then
			ns.Print("|cff888888ui: los ajustes de que se esconde vuelven a fabrica " ..
			         "(el tooltip de unidad y las dos barras verticales de la " ..
			         "derecha se quedan, el objetivo se esconde; " ..
			         "/rts ui <conjunto> lo cambia).|r")
		end
		RTSCommandDB.uiHide = {}
		RTSCommandDB.uiHideGen = UIHIDE_GEN
	end

	if type(RTSCommandDB.uiHide) == "table" then
		for k, v in pairs(RTSCommandDB.uiHide) do
			if self.hide[k] ~= nil then self.hide[k] = v and true or false end
		end
	end

	-- El tooltip vuelve solo en cada mouseover, asi que no se aparca: se le
	-- niega el OnShow mientras el modo esta activo. Enganchado una sola vez y
	-- para siempre; la condicion vive dentro.
	--
	-- SOLO EL DEL MUNDO, que es lo que `IsWorldTip` decide y ahi esta contado
	-- por que. Todo tooltip que tenga un frame debajo -- el nuestro, el del
	-- botin, el del vendedor -- pasa.
	--
	-- `GetOwner()` sirve porque el `SetOwner` va SIEMPRE antes del `Show`, tanto
	-- en `W:Tip` como en el codigo de Blizzard, asi que para cuando corre este
	-- gancho el dueno ya esta puesto.
	GameTooltip:HookScript("OnShow", function(tip)
		if C.active and C.hide.tooltip and IsWorldTip(tip) then
			tip:Hide()
			return
		end
		LiftWorldTip(tip)
	end)

	-- Y EL SITIO SE CORRIGE DONDE SE ESCRIBE, que es esta funcion: el cliente la
	-- llama en cada raton encima, tambien cuando el tooltip YA ESTA puesto y
	-- solo cambia de bicho -- y en ese caso no hay `OnShow` que valga, asi que
	-- sin este gancho el rotulo se caeria a la esquina en cuanto pasas de un
	-- mob al de al lado sin soltar.
	if type(GameTooltip_SetDefaultAnchor) == "function" then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
			if tip == GameTooltip then LiftWorldTip(tip) end
		end)
	end

	-- Intro. Ver el bloque de Peek: sin esto se escribe a ciegas.
	hooksecurefunc("ChatFrame_OpenChat", function()
		if C.active and C.hide.chat then C:Peek() end
	end)
	for i = 1, 7 do
		local eb = _G["ChatFrame" .. i .. "EditBox"]
		if eb then
			eb:HookScript("OnEditFocusLost", function()
				if C.active and C.peek then C:PeekEnd() end
			end)
		end
	end

	-- Un frame protegido no se puede esconder ni devolver dentro de combate.
	-- Lo que quedo a medias se termina en cuanto el combate cae -- el mismo
	-- patron que Camera.lua usa con las teclas.
	local ev = CreateFrame("Frame", "RTSChromeEvents")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function()
		if pending then C:Apply() end
	end)
end
