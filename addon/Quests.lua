--[[
	Quests.lua -- el boton COMPARTIR del registro nativo, pero forzando.

	No hay ventana propia. Se abre el registro de misiones de siempre, se
	selecciona una y se pulsa "Compartir": en vez de mandarle a cada companero
	una invitacion que su IA ignora, el servidor **se la da**.

	=== POR QUE NO HAY VENTANA, QUE ES LA SEGUNDA VEZ QUE SE DECIDE ==========

	La primera version enseñaba las misiones del PNJ que pinchabas. La segunda
	enseñaba las tuyas con una fila de puntos por companero. Las dos se vieron en
	pantalla y las dos sobraban por el mismo motivo: **el registro de misiones ya
	existe, ya sabe dibujar una mision, y el jugador ya sabe usarlo**. Lo unico
	que le faltaba era que el boton de compartir sirviera para algo con un grupo
	de bots.

	Asi que no se dibuja una lista: se le cambia el trabajo a un boton que ya
	esta puesto. Cero pixeles nuevos.

	=== EL BOTON ES DE BLIZZARD Y NO ESTA PROTEGIDO =========================

	`QuestLogFramePushQuestButton`, un `Button` corriente que hereda
	`UIPanelButtonTemplate` (`QuestLogFrame.xml:181`, leido del MPQ del cliente,
	no recordado). Su `OnClick` es una linea: `QuestLogPushQuest()`. Ni el boton
	ni `QuestLogFrame` llevan `protected`, asi que se le puede cambiar el script.

	Quien lo apaga es `QuestLogControlPanel_UpdateState`
	(`QuestLogFrame.lua:984`), que exige `GetQuestLogPushable()` y grupo. La
	primera condicion es justo la que sobra aqui -- una mision no compartible se
	puede forzar igual -- asi que se engancha esa funcion con `hooksecurefunc` y
	se vuelve a encender DESPUES de que ella decida. Es el mismo patron que el
	repintado del nombre en el marco de Blizzard (0.62.0): despues de la suya,
	para tener la ultima palabra.

	=== SIN mod-rts NO SE PIERDE NADA ======================================

	Si el servidor no contesta, o si no hay compañeros, el boton hace lo que
	hacia: `QuestLogPushQuest()`. Se guarda el comportamiento original en vez de
	reemplazarlo a ciegas -- misma regla dura que `Camera.lua` con sus CVars y
	`Chrome.lua` con los frames de Blizzard.

	=== LO QUE HACE EL SERVIDOR, Y LO QUE NO ===============================

	`QSHARE` -> `rts::quests::Share`. Por cada companero de la lista:

	  * si ya la lleva o ya la hizo, NO se le toca y se dice;
	  * si le falta la cadena, se le marcan como recompensadas las anteriores;
	  * y luego se le da.

	SOLO SE FUERZA LA CADENA. Nivel, clase, raza, reputacion y registro lleno se
	respetan y se DICEN por el chat: son motivos distintos de "no te siguio", y
	taparlos convertiria un boton honesto en uno que a veces hace algo que no
	entiendes. El porque entero, con las lineas del nucleo, esta en `RtsQuests.h`.

	=== LAS DOS MITADES ESPERAN A UN CLICK TUYO, Y ESA ES LA REGLA ==========

	Pedido en estas palabras: *"I approach an NPC -> then read the quest -> if
	it is interesting i press accept (...) IF I PRESSED THE ACCEPT BUTTON, then
	it is when other players also get the quest (...) wait until i press
	COMPLETE, then bots get their quest reward"*.

	Asi que el grupo va detras de un boton TUYO y de nada mas:

	  * ACEPTAR   -> gancho en `AcceptQuest` / `ConfirmAcceptQuest`, y un
	                 `QUEST_ACCEPTED` que llegue sin eso no se reparte.
	  * ENTREGAR  -> gancho en `GetQuestReward`, que es el boton final del panel
	                 de recompensa. Ni el "Continuar" del panel de progreso
	                 (`CompleteQuest()`, que no cobra) ni cerrar la ventana
	                 disparan nada.
	  * ABANDONAR -> gancho en `AbandonQuest`, o sea el SI del cartel de
	                 confirmacion. Es la tercera y faltaba entera: lo que tu
	                 tirabas se quedaba en los cuatro bots.

	Las dos secciones de abajo lo cuentan entero. Lo que importa aqui es lo que
	se QUITO para que fuera cierto, porque eran dos cosas y solo una era nuestra:

	  1. Nuestra entrega colgaba de `QUEST_FINISHED`, que significa *"se cerro el
	     dialogo"* y nada mas -- asi que abrir la ventana de un PNJ y cerrarla
	     entregaba por el grupo. Estaba escrito como comportamiento esperado en
	     `PRUEBAS-25` J11: no fue un descuido, fue una decision equivocada.
	  2. La estrategia `quest` de mod-playerbots entrega sola al ABRIR la
	     ventana, y con `SyncQuestWithPlayer` ademas completa la mision del bot
	     antes de cobrarla. Se apaga desde mod-rts (`SetGroupAI`), y el porque
	     entero, con las lineas, esta en `RtsQuests.h`.

	=== EL FORZADO (`/rts quests force`) ===================================

	De serie la entrega solo alcanza a quien tuviera la mision hecha; con el
	forzado alcanza a todo el que se pueda ayudar -- se le da la mision si no la
	lleva, se le completan los objetos que le falten, se le pone en hecha y
	cobra. El servidor elige la recompensa POR CLASE (`BestReward`), asi que
	cuatro clases no acaban con el mismo objeto.

	La lista que se manda son TODOS tus companeros: la clasificacion fina la
	hace el servidor, que es el unico que ve nivel, clase y hueco de bolsa, y
	que contesta una linea por cada uno que se quede fuera.

	Y NO puede cobrarse dos veces por mucho que se repita el gesto:
	`Player::RewardQuest` va detras de `CanRewardQuest`, y un
	`GetQuestRewardStatus` cierto la corta.

	=== NO HACE FALTA ESTAR AL LADO, Y ESO NO ES UN TRUCO ===================

	Ninguna funcion de mision del nucleo comprueba distancia: la unica puerta
	esta en los manejadores de opcode, y esos son una defensa contra un cliente
	que miente sobre donde esta. mod-playerbots ya lo explota igual desde
	siempre. Ver `RtsQuests.h`.
]]

local ADDON, ns = ...

local Q = {}
ns.Quests = Q

-- Estados, tal cual los manda `RtsQuests.h`. Aqui solo se usan para el tooltip
-- del boton, que es lo unico que se dibuja de todo esto.
local ST = {
	[0] = { c = "|cff9a9a9a", word = "no le vale" },
	[1] = { c = "|cffffd100", word = "puede cogerla" },
	[2] = { c = "|cffdddddd", word = "la lleva" },
	[3] = { c = "|cff33ff55", word = "lista para entregar" },
	[4] = { c = "|cff55aa66", word = "ya la hizo" },
}

-- Los que el boton puede arreglar: no la llevan. `ya la hizo` no, porque
-- volver a darsela no es ponerle al dia de nada.
local PENDING = { [0] = true, [1] = true }

local AUTO_REWARD = 255

--- Estado ------------------------------------------------------------------

local who = {}          -- questId -> { {name=, status=}, ... }
local asked = nil       -- de que mision se pidio lo ultimo
local wired = false

--- Utilidades --------------------------------------------------------------

local function HexOf(guid)
	return (tostring(guid or ""):gsub("^0[xX]", ""))
end

-- EL ID DE UNA MISION EN 3.3.5a NO ES UNA LLAMADA. No hay `GetQuestID()` en
-- este cliente; lo unico que lo lleva es el ENLACE del registro, que devuelve
-- "|Hquest:1234:5|h[Titulo]|h". Si vuelve nil -- una cabecera seleccionada, o
-- el registro aun sin actualizar -- no se manda nada, que es mejor que mandar
-- un id inventado.
local function QuestIdFromLog(index)
	if not index or index <= 0 then return nil end
	local link = GetQuestLink(index)
	if not link then return nil end
	return tonumber(link:match("quest:(%d+)"))
end

local function Selected()
	return QuestIdFromLog(GetQuestLogSelection())
end

-- Todos menos tu.
local function Others()
	local out = {}
	for _, u in ipairs(ns.Selection:GetRoster()) do
		table.insert(out, u.name)
	end
	return out
end

-- A quien le falta, segun lo ultimo que dijo el servidor. Sin respuesta todavia
-- se mandan TODOS: el servidor se salta solo a quien ya la tenga, asi que el
-- peor caso de no saber es un viaje de mas y ningun efecto de mas.
local function Pending(questId)
	local list = who[questId]
	if not list then return Others() end

	local out = {}
	for _, m in ipairs(list) do
		if PENDING[m.status] then table.insert(out, m.name) end
	end
	return out
end

--- El canal ----------------------------------------------------------------

function Q:AskWho(questId)
	if not questId or not ns.Link:HasServer() then return end
	asked = questId
	ns.SendServer("QWHO " .. questId)
end

--- El boton del registro nativo --------------------------------------------

local original = nil    -- lo que hacia antes de que lo tocaramos

local function Tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Compartir a la fuerza")

	local id = Selected()
	if not id then
		GameTooltip:AddLine("Selecciona una mision.", 1, 0.5, 0.2)
		GameTooltip:Show()
		return
	end

	if not ns.Link:HasServer() then
		GameTooltip:AddLine("Sin mod-rts: hara el compartir normal.", 1, 0.5, 0.2)
		GameTooltip:Show()
		return
	end

	GameTooltip:AddLine("Se la doy a quien no la lleve, marcandole las", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("anteriores de la cadena si le faltan.", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ")

	local list = who[id]
	if not list then
		GameTooltip:AddLine("preguntando quien la lleva...", 0.6, 0.6, 0.6)
	elseif #list == 0 then
		GameTooltip:AddLine("no tienes compañeros en el grupo.", 1, 0.5, 0.2)
	else
		for _, m in ipairs(list) do
			local s = ST[m.status] or ST[0]
			GameTooltip:AddLine(m.name .. ": " .. s.c .. s.word .. "|r")
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Nivel, clase y raza se respetan: a quien no le", 0.7, 0.55, 0.2)
	GameTooltip:AddLine("valga se queda fuera y te lo digo por el chat.", 0.7, 0.55, 0.2)
	GameTooltip:Show()
end

local function OnClick(self, button)
	local id = Selected()

	-- SIN MOD-RTS O SIN GRUPO, LO DE SIEMPRE. Se llama a lo que el boton hacia
	-- antes, capturado al engancharlo, en vez de suponer que era
	-- `QuestLogPushQuest` -- que hoy lo es y manana lo decide otro addon.
	if not id or not ns.Link:HasServer() then
		if original then original(self, button) end
		return
	end

	local names = Pending(id)
	if #names == 0 then
		ns.Print("|cff33ccffmisiones:|r todo el grupo la lleva ya.")
		return
	end

	ns.SendServer(("QSHARE %d %s"):format(id, table.concat(names, ";")))
	PlaySound("igQuestLogOpen")
end

function Q:WireButton()
	local b = QuestLogFramePushQuestButton
	if not b or original then return end

	original = b:GetScript("OnClick")
	b:SetScript("OnClick", OnClick)
	b:SetScript("OnEnter", Tooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- BLIZZARD LO APAGA Y NOSOTROS LO VOLVEMOS A ENCENDER, DESPUES.
	-- `QuestLogControlPanel_UpdateState` exige `GetQuestLogPushable()`, que es
	-- justo la condicion que aqui sobra: una mision que el juego no deja
	-- compartir se puede forzar igual. Se engancha con `hooksecurefunc` para
	-- correr detras de la suya y tener la ultima palabra.
	--
	-- Y de paso es el sitio donde enterarse de que ha cambiado la seleccion:
	-- `QuestLog_SetSelection` la llama (`QuestLogFrame.lua:741`) y
	-- `QuestLog_Update` tambien (:509), asi que un solo gancho cubre los dos.
	if type(QuestLogControlPanel_UpdateState) ~= "function" then
		ns.Print("|cffff8800misiones:|r este cliente no tiene " ..
		         "QuestLogControlPanel_UpdateState; el boton se quedara apagado " ..
		         "cuando el juego lo apague.")
		return
	end

	hooksecurefunc("QuestLogControlPanel_UpdateState", function()
		local id = Selected()
		if not id then return end

		if ns.Link:HasServer() and #Others() > 0 then
			QuestLogFramePushQuestButton:Enable()
		end

		-- Solo si ha cambiado: esta funcion corre en cada refresco del registro
		-- y preguntar por lo mismo treinta veces seguidas es ruido en un canal
		-- de 255 caracteres.
		if id ~= asked then Q:AskWho(id) end
	end)
end

--- Seguir al heroe automaticamente -----------------------------------------
--
-- `PRUEBAS-20` B: *"al coger una mision con el heroe, si el resto del grupo
-- puede cogerla / devolverla, ya deberia hacerlo de forma automatica, sin
-- entrar en el nuevo panel"*.
--
-- Es lo que convierte esto en una comodidad de verdad: juegas como siempre,
-- hablas con el PNJ como siempre, y el grupo va detras. El boton de compartir
-- es para los casos raros -- el bot que no te siguio -- no el camino normal.
--
-- === LAS DOS MITADES NO SE HACEN IGUAL, Y NO POR CAPRICHO =================
--
-- ACEPTAR es reversible y no gasta nada, asi que se hace en el acto y para
-- todos: `QUEST_ACCEPTED` da el indice del registro, de ahi sale el id, y el
-- servidor ya se encarga de saltarse a quien no pueda.
--
-- ENTREGAR sí gasta: da objetos que no se devuelven. Asi que NO se dispara al
-- entregar tu (no hay evento fiable con el id en 3.3.5a de todas formas), sino
-- al CERRAR la conversacion: se le pregunta al PNJ que tiene, y se entrega solo
-- lo que este listo. Con eleccion de recompensa se manda `AUTO_REWARD` y el
-- servidor elige por cada uno segun su clase.
--
-- === Y ACEPTAR TIENE QUE HABERLO HECHO TU ================================
--
-- Reportado asi: *"al hablar con el npc, me ha cogido la quest tal cual, y se
-- la ha entregado al resto (...) necesito poder hablar con el NPC, leer la
-- quest, Y AL ACEPTARLA MANUALMENTE, entonces si, que se le transfiera"*.
--
-- EL REPARTO AL GRUPO NO ERA EL PROBLEMA. Cuelga de `QUEST_ACCEPTED`, o sea de
-- que la mision entre de verdad en TU registro; lo que fallaba es que entraba
-- sola, antes de que hubiera nada que leer.
--
-- QUIEN LA ACEPTA NO SE HA PODIDO DEMOSTRAR LEYENDO, Y ESO SE DICE EN VEZ DE
-- ADIVINARLO. Buscado en los cuatro sitios donde podia estar:
--
--   * el addon no llama a `AcceptQuest` en ninguna linea;
--   * mod-rts solo anade misiones a los NOMBRES que le manda el cliente, y esa
--     lista es `Others()`, que excluye al heroe por construccion;
--   * las estrategias por defecto de playerbots tampoco: la que responde a
--     "gossip hello" es `quest` -> `TalkToQuestGiverAction`, que ENTREGA lo
--     completado pero para `QUEST_STATUS_NONE` solo escribe "Available". La
--     que si acepta, `AcceptAllQuestsAction`, cuelga de la estrategia
--     `accept all quests`, que no la pone ni `AiFactory` ni la conf;
--   * y el `QuestFrame.lua` de ESTE cliente (sacado del MPQ, no recordado)
--     solo enseña el panel de detalle.
--
-- El unico camino general que queda es `Player::SendPreparedQuest`
-- (`PlayerQuest.cpp:144`), y solo para misiones con la bandera AUTO_ACCEPT.
--
-- Asi que la puerta se pone EN LO QUE SI CONTROLAMOS, y ella nombra al
-- culpable: se enganchan las dos unicas funciones con las que este cliente
-- acepta a mano -- `AcceptQuest` (el boton del dialogo, y el popup de
-- `StaticPopup.lua:281`) y `ConfirmAcceptQuest` (una mision compartida) -- y un
-- `QUEST_ACCEPTED` que llegue sin que ninguna se haya llamado NO se pasa al
-- grupo, y se dice que entro sola.
--
-- Misma regla que el resto del proyecto: una lectura estatica que no convence
-- vale una prueba barata, no maquinaria encima.

local follow = CreateFrame("Frame", "RTSQuestsFollow")

-- Cuando pulsaste tu. `QUEST_ACCEPTED` llega despues del viaje al servidor, que
-- en local son milisegundos; dos segundos es holgura de sobra sin llegar a
-- tragarse la mision siguiente.
local lastManual = 0
local MANUAL_WINDOW = 2.0

-- EL INDICE QUE TRAE `QUEST_ACCEPTED` NO ES DE FIAR, Y ESTO COSTO UNA RONDA.
--
-- Sintoma: aceptas "La protectora de los bosques" y el servidor contesta que
-- los cuatro companeros la rechazan porque "no es de su clase". Esa mision es
-- la 458, y su `quest_template_addon.AllowableClasses` es **0** -- consultado
-- en la base de datos, no supuesto. Y `Player::SatisfyQuestClass` empieza con
-- `if (reqClass == 0) return true`. O sea que era IMPOSIBLE que ese fuera el
-- motivo... para esa mision. Luego el id que se mando era de otra.
--
-- El `arg1` del evento es un INDICE del registro, y la copia que Lua consulta
-- con `GetQuestLink` se refresca en `QUEST_LOG_UPDATE`, que llega despues. Asi
-- que en ese instante el indice puede apuntar a lo que habia antes ahi -- y
-- entonces se comparte una mision cualquiera, con un motivo de rechazo que
-- describe correctamente a la mision equivocada. La peor forma de mentir: el
-- mensaje era cierto y aun asi enganaba.
--
-- LA MISION SE IDENTIFICA POR DIFERENCIA DEL REGISTRO, y es el tercer intento.
--
-- El primero uso el indice del evento: mal, por lo de arriba. El segundo uso el
-- titulo del panel leido DENTRO del gancho de `AcceptQuest` -- y `hooksecurefunc`
-- corre DESPUES de la original, o sea despues de que el cliente haya cerrado el
-- dialogo. Es EXACTAMENTE la trampa que ya se habia arreglado en el abandono una
-- vuelta antes, repetida por no mirarla: `GetTitleText()` ahi no es el titulo
-- que leiste.
--
-- Asi que no se identifica la mision por nada que el cliente pueda haber
-- cambiado ya: se mira QUE MISION ES NUEVA EN TU REGISTRO. Se guarda el conjunto
-- de ids que llevabas y, cuando el registro se refresca despues de que pulses
-- Aceptar, la que no estaba es la que acabas de coger. Sin titulos, sin indices,
-- sin ventanas de tiempo, y funciona igual para una mision que empieza en un
-- objeto o que te llega compartida.
--
-- SE ESPERA A `QUEST_LOG_UPDATE` Y NO A `QUEST_ACCEPTED`, que es la otra mitad:
-- el registro que Lua consulta no esta escrito cuando llega el segundo. Por eso
-- todos los intentos anteriores leian datos viejos.
local logSet = nil        -- ids que llevabas la ultima vez que se miro
local shareUntil = nil    -- pulsaste Aceptar: la proxima mision nueva es tuya
local turnUntil = nil     -- pulsaste Completar: la proxima que desaparezca
local questNpc = nil      -- con quien hablas, capturado mientras `questnpc` vale

-- El plazo no es para acertar el instante -- eso lo hace la diferencia -- sino
-- para que un Aceptar que el servidor rechace no deje armado el reparto de la
-- siguiente mision que entre por cualquier otro camino.
local ACCEPT_WINDOW = 10.0

local function LogSnapshot()
	local t = {}
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, _, isHeader = GetQuestLogTitle(i)
		if not isHeader then
			local id = QuestIdFromLog(i)
			if id then t[id] = title or "" end
		end
	end
	return t
end

-- LA VERSION DE mod-rts QUE HACE FALTA, Y POR QUE SE COMPRUEBA A GRITOS.
--
-- Un verbo que el servidor no conoce NO DA ERROR: no contesta. Asi que un
-- worldserver que no se ha reiniciado se comporta exactamente igual que un
-- fallo en el addon -- el gesto sale, no pasa nada, y no hay nada que mirar.
-- Eso ya se ha cobrado una ronda entera: `QDROP` se mando contra un servidor
-- que no lo tenia y se leyo como "abandonar no funciona".
--
-- 0.45.0 es la primera con `QAI` (apagar la IA de misiones de los bots) y
-- `QDROP` (abandonar por el grupo).
local NEED_MINOR = 45
local nagged = false

local function ServerTooOld()
	if not ns.Link:HasServer() then return false end
	if ns.Link:ServerAtLeast(NEED_MINOR) then return false end

	if not nagged then
		nagged = true
		ns.Print(("|cffff0000misiones: mod-rts es %s y hace falta 0.%d.0.|r"):format(
			tostring(ns.Link.serverVersion), NEED_MINOR))
		ns.Print("El worldserver no se ha reiniciado con la version nueva. Hasta que")
		ns.Print("lo hagas, los bots entregaran solos y no abandonaran contigo.")
	end
	return true
end

-- EL INTERRUPTOR DE "SEGUIR AL HEROE" ESTA BORRADO, NO APAGADO.
--
-- *"I had to activate /rts quests auto. when the fuck did i ask for that?"* --
-- y es exacto: nunca se pidio. Lo que se pidio es que al aceptar tu, el grupo
-- coja la mision. Un interruptor encima de eso solo puede hacer una cosa mala,
-- y la hizo: estaba guardado en OFF de una ronda de pruebas vieja, y desde
-- entonces bloqueaba el reparto entero con un `return` mudo -- o sea que las
-- tres vueltas siguientes se fueron buscando el fallo en el sitio equivocado.
--
-- La clave se tira al cargar (`Core.lua`). Es la octava purga de este addon,
-- despues de `grow = 688`, `camHold`, `railCropGen`, las de la sala, `slots` y
-- `bright`, y por la misma razon de siempre: las SavedVariables no olvidan
-- ninguna clave y sobreviven a la version que la escribio.

-- FORZAR LA ENTREGA. Va aparte del automatico y no dentro, porque son dos
-- decisiones distintas: "que el grupo vaya detras de mi" y "que lo haga aunque
-- no hayan hecho el trabajo". Se puede querer la primera sin la segunda.
function Q:Force(on)
	if on ~= nil then
		RTSCommandDB.questForce = on and true or false
	end
	if RTSCommandDB.questForce == nil then RTSCommandDB.questForce = true end
	return RTSCommandDB.questForce
end

function Q:WireFollow()
	-- LOS DOS GANCHOS VAN AUNQUE EL SEGUIMIENTO ESTE APAGADO: `lastManual` es un
	-- dato sobre TI, no sobre el reparto, y sirve igual para el aviso.
	-- `hooksecurefunc` sobre una funcion de C es legal y es lo que ya se hace con
	-- `PlayerFrame_Update` (0.62.0). Se comprueba que existan porque una funcion
	-- que no esta no da error al engancharla: da error al llamar al gancho.
	-- Los dos ARMAN el reparto; cual mision es lo decide la diferencia del
	-- registro, no lo que se pueda leer en este instante.
	local function Armed()
		lastManual = GetTime()
		shareUntil = GetTime() + ACCEPT_WINDOW
	end

	if type(AcceptQuest) == "function" then
		hooksecurefunc("AcceptQuest", Armed)
	end
	if type(ConfirmAcceptQuest) == "function" then
		hooksecurefunc("ConfirmAcceptQuest", Armed)
	end

	follow:RegisterEvent("QUEST_ACCEPTED")
	follow:RegisterEvent("QUEST_LOG_UPDATE")
	follow:RegisterEvent("QUEST_DETAIL")
	follow:RegisterEvent("QUEST_PROGRESS")
	follow:RegisterEvent("QUEST_COMPLETE")
	follow:RegisterEvent("PLAYER_ENTERING_WORLD")
	follow:RegisterEvent("PARTY_MEMBERS_CHANGED")
	follow:SetScript("OnEvent", function(_, event, arg1)
		-- UN CAMBIO DE GRUPO INVALIDA TODO LO GUARDADO. La lista dice quien la
		-- lleva, y "quien" acaba de cambiar: sin esto el tooltip nombraria a un
		-- bot que ya no esta, y el boton se la mandaria.
		if event == "PARTY_MEMBERS_CHANGED" then
			who, asked = {}, nil
			return
		end

		-- Al entrar al mundo el registro aun no esta, asi que la foto se toma en
		-- el primer refresco y no aqui. Lo unico que hace falta es olvidar la de
		-- la sesion anterior.
		if event == "PLAYER_ENTERING_WORLD" then
			logSet, shareUntil = nil, nil
			return
		end

		-- LA PUERTA: solo se reparte lo que aceptaste TU. Este evento NO reparte
		-- -- el registro que Lua consulta aun no esta escrito -- solo avisa de lo
		-- que entra sin que lo pidas.
		--
		-- EL AVISO VA ANTES DE TODAS LAS GUARDAS: un testigo condicionado no es
		-- un testigo.
		if event == "QUEST_ACCEPTED" then
			if GetTime() - lastManual > MANUAL_WINDOW then
				shareUntil = nil
				ns.Print(("|cffff8800misiones:|r %s entro sola, sin que la aceptaras."):format(
					GetQuestLogTitle(arg1) or "una mision"))
				ns.Print("No la paso al grupo. Si sigue pasando con |cffffff00Quests.IgnoreAutoAccept = 1|r,")
				ns.Print("el que la acepta no es el nucleo y hay que mirar otra cosa.")
			end
			return
		end

		-- EL PNJ SE CAPTURA AQUI Y NO EN EL GANCHO DEL BOTON: `questnpc` solo
		-- es una unidad valida mientras la ventana esta abierta, y para cuando
		-- corre un `hooksecurefunc` puede haberse cerrado ya.
		if event == "QUEST_DETAIL" or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
			questNpc = UnitGUID("questnpc") or UnitGUID("npc") or UnitGUID("target") or questNpc
			return
		end

		if event ~= "QUEST_LOG_UPDATE" then return end

		local now = LogSnapshot()

		-- La primera foto de la sesion no reparte nada: sin nada con que
		-- comparar, TODAS tus misiones serian nuevas.
		if not logSet then
			logSet = now
			return
		end

		local fresh, gone = {}, {}
		for id, title in pairs(now) do
			if not logSet[id] then fresh[id] = title end
		end
		for id, title in pairs(logSet) do
			if not now[id] then gone[id] = title end
		end
		logSet = now

		-- LO QUE SALE DEL REGISTRO ES LO QUE ENTREGASTE, y solo cuenta si acabas
		-- de pulsar Completar. Abandonar tambien saca una mision, pero ese gesto
		-- no arma `turnUntil` y ademas tiene su propio camino.
		if turnUntil and GetTime() <= turnUntil and next(gone) then
			turnUntil = nil
			if ns.Link:HasServer() and not ServerTooOld() and questNpc then
				for id, title in pairs(gone) do
					ns.Print(("|cff33ccffmisiones:|r entregando |cffffd100%s|r por el grupo."):format(
						title ~= "" and title or ("mision " .. id)))
					Q:TurnInForGroup(id, HexOf(questNpc))
				end
			end
		end

		if not shareUntil or GetTime() > shareUntil then return end
		if not next(fresh) then return end
		shareUntil = nil

		-- LAS GUARDAS VAN AQUI Y CADA UNA DICE ALGO. Un reparto que no ocurre y
		-- no se explica es indistinguible de un fallo, y eso ya ha costado
		-- varias vueltas.
		if not ns.Link:HasServer() then
			ns.Print("|cffff8800misiones:|r mod-rts no contesta; el grupo no la coge.")
			return
		end
		if ServerTooOld() then return end

		local names = Others()
		if #names == 0 then return end

		-- SE MANDA `QSHARE`, QUE ES LO MISMO QUE PULSAR COMPARTIR.
		--
		-- Pedido asi: *"al aceptar una quest hay que darsela al resto, como si le
		-- dieramos al boton de compartir, y con las normas que nosotros hemos
		-- creado"*.
		--
		-- `QACCEPT` hacia menos: comprobaba que ESE PNJ da la mision y se la daba
		-- a quien pudiera. `QSHARE` es la version con las normas -- `CatchUpEach`
		-- -- que al bot descolgado le marca las anteriores de la cadena antes de
		-- darsela y contesta una linea por cada uno que se quede fuera. Y no
		-- necesita PNJ, asi que tambien vale para una mision que empieza en un
		-- objeto o que te llega compartida.
		for id, title in pairs(fresh) do
			ns.Print(("|cff33ccffmisiones:|r dando |cffffd100%s|r al grupo."):format(
				title ~= "" and title or ("mision " .. id)))
			ns.SendServer(("QSHARE %d %s"):format(id, table.concat(names, ";")))
		end
	end)
end

--- ENTREGAR: SOLO CUANDO PULSAS TU -----------------------------------------
--
-- Reportado asi: *"i tried to turn a quest and bots auto turned it
-- automatically while i didnt even press the complete button (...) any time i
-- opened the npc's quest window the log said the bots turned the quest (...)
-- wait until i press COMPLETE, then bots get their quest reward"*.
--
-- Habia DOS cosas entregando solas y las dos se han quitado. La otra es de
-- mod-playerbots y esta escrita en `RtsQuests.h` (`SetGroupAI`); esta era
-- nuestra:
--
-- LA VERSION ANTERIOR COLGABA DE `QUEST_FINISHED`, QUE SIGNIFICA "SE CERRO EL
-- DIALOGO" Y NADA MAS. Abrir la ventana de un PNJ y cerrarla sin tocar nada
-- disparaba la entrega del grupo, porque cerrar es lo unico que ese evento
-- sabe. Estaba incluso escrito como comportamiento esperado en `PRUEBAS-25`
-- J11 -- o sea que no era un descuido, era una decision equivocada, y el juego
-- la ha contestado.
--
-- === QUE SUSTITUYE A ESO, Y POR QUE ES EXACTO ===========================
--
-- `GetQuestReward(indiceDeRecompensa)` es LA funcion que el cliente llama
-- cuando pulsas el boton final del panel de recompensa
-- (`QuestFrame.lua:103`, leido del MPQ de este cliente). No hay ninguna otra:
-- el "Continuar" del panel de progreso es `CompleteQuest()`, que no cobra
-- nada. Asi que engancharla es, literalmente, "cuando pulsa COMPLETAR".
--
-- EL ID SALE DEL PROPIO CLIENTE, QUE ES LO UNICO QUE NO PUEDE DESCUADRAR. En
-- 3.3.5a no hay `GetQuestID()`, y mientras el panel de recompensa esta abierto
-- la mision SIGUE en tu registro -- se va al cobrarla -- asi que se busca por
-- titulo: `GetTitleText()` (lo que pone el panel) contra `GetQuestLogTitle(i)`
-- (lo que pone el registro). Las dos cadenas las escribe el mismo cliente en
-- el mismo idioma, que es la razon de no comparar contra el titulo que manda
-- el servidor: ese sale del `Quest.dbc` en INGLES aunque juegues en espanol
-- (comprobado en la etapa del libro de hechizos), y la comparacion fallaria
-- siempre sin dar error.
--
-- Y EL PNJ ES `questnpc`, que es una unidad valida justo mientras esa ventana
-- esta abierta (`QuestFrame.lua:60`). Por eso todo esto se lee DENTRO del
-- gancho y no un tick despues.
--
-- === EL ORDEN DE LOS DOS PAQUETES NO ES CASUALIDAD =======================
--
-- `hooksecurefunc` corre DESPUES de la original, asi que el
-- `CMSG_QUESTGIVER_CHOOSE_REWARD` del cliente sale antes que nuestro mensaje.
-- Una sesion conserva el orden, asi que cuando el servidor lee el `QTURN` tu
-- entrega ya esta hecha -- que es la condicion que `TurnIn` comprueba para
-- dejar forzar (`master->GetQuestRewardStatus`). Al reves, el forzado se
-- caeria en silencio y solo cobrarian los que ya la tuvieran lista.
function Q:TurnInForGroup(questId, npcHex)
	local names = Others()
	if #names == 0 then return end

	local force = Q:Force()

	-- EL LARGO SE MIRA AQUI Y NO SOLO EN `Link:Send`. Alli se avisa y se
	-- descarta el mensaje entero, y aqui eso serian bots sin cobrar una
	-- recompensa que ya no se puede repetir. Con cuatro companeros no se llega
	-- ni de lejos al tope; con nombres largos y un grupo grande, si.
	local function Body(list)
		return ("QTURN %s %d %d %s %d"):format(
			npcHex, questId, AUTO_REWARD, table.concat(list, ";"), force and 1 or 0)
	end

	local body = Body(names)
	while #body > ns.Link.LIMIT and #names > 1 do
		table.remove(names)
		body = Body(names)
	end

	ns.SendServer(body)
	if force then ns.Print("  |cffffd100(forzada: cobran aunque no la llevaran hecha)|r") end
end

--- ABANDONAR: LA TERCERA MITAD ---------------------------------------------
--
-- *"si abandono una quest el resto la conservan (...) quiero tener el mismo
-- registro de misiones"*. Aceptar y entregar iban juntos desde el principio;
-- tirar una mision no, asi que una que tu soltabas se quedaba en los cuatro
-- bots para siempre y los registros se separaban un poco mas cada dia.
--
-- `AbandonQuest()` es la funcion que llama el SI del cartel de confirmacion
-- (`StaticPopup.lua:1703` y `:1716`, las dos variantes -- con objetos y sin
-- ellos). Antes de eso, el registro ya ha llamado a `SetAbandonQuest()`, asi
-- que `GetAbandonQuestName()` dice cual es y la mision AUN esta en tu registro:
-- se va cuando el servidor procesa la peticion, que ocurre despues.
--
-- Mismo truco que la entrega para el id, y por el mismo motivo: el titulo lo
-- escribe el cliente en los dos sitios, asi que comparar sus dos cadenas no
-- puede fallar por idioma. El del servidor si -- ese sale del DBC en ingles.
function Q:WireAbandon()
	if type(AbandonQuest) ~= "function" then
		ns.Print("|cffff8800misiones:|r este cliente no tiene AbandonQuest; " ..
		         "el grupo no soltara las misiones contigo.")
		return
	end

	-- EL ID SE COGE EN `SetAbandonQuest`, NO EN `AbandonQuest`, Y ESA ES LA
	-- CORRECCION DE ESTA VUELTA.
	--
	-- La primera version leia `GetAbandonQuestName()` DENTRO del gancho de
	-- `AbandonQuest`, y `hooksecurefunc` corre DESPUES de la original -- o sea
	-- despues de que el cliente haya mandado la peticion y, por lo que se ve,
	-- despues de que haya soltado su objetivo de abandono. Nombre nil, `return`,
	-- y ni un mensaje: abandonar "no hacia nada".
	--
	-- `SetAbandonQuest()` es lo que llama el boton Abandonar del registro
	-- (`QuestLogFrame.lua:739`) ANTES de sacar el cartel de confirmacion, asi que
	-- ahi el nombre esta puesto y la mision sigue en el registro. Se resuelve el
	-- id en ese instante y se guarda.
	--
	-- No basta con guardarlo: hay que BORRARLO al usarlo. Si no, cancelar el
	-- cartel dejaria el id cargado y el siguiente abandono -- de otra mision --
	-- soltaria la de antes en los bots.
	local pending = nil

	if type(SetAbandonQuest) == "function" then
		hooksecurefunc("SetAbandonQuest", function()
			pending = nil

			local name = GetAbandonQuestName and GetAbandonQuestName()
			if not name or name == "" then return end

			for i = 1, GetNumQuestLogEntries() do
				local title, _, _, _, isHeader = GetQuestLogTitle(i)
				if not isHeader and title == name then
					pending = QuestIdFromLog(i)
					return
				end
			end
		end)
	end

	hooksecurefunc("AbandonQuest", function()
		local id = pending
		pending = nil

		if not ns.Link:HasServer() then return end
		if ServerTooOld() then return end

		local names = Others()
		if #names == 0 then return end

		-- SE DICE CUANDO NO SE PUEDE, y no es ruido: "los bots no la han soltado"
		-- y "el gancho no llego a correr" se ven exactamente igual desde el
		-- juego, y distinguirlos ya ha costado una ronda.
		if not id then
			ns.Print("|cffff8800misiones:|r no he podido identificar la mision " ..
			         "que abandonas; los bots la conservan.")
			return
		end

		ns.SendServer(("QDROP %d %s"):format(id, table.concat(names, ";")))
	end)
end

-- LA ENTREGA SE IDENTIFICA IGUAL QUE EL ACEPTAR: POR DIFERENCIA DEL REGISTRO.
--
-- Al cobrar, la mision SALE de tu registro, asi que la que desaparece es la que
-- entregaste. Antes se buscaba por el titulo del panel leido dentro del gancho
-- de `GetQuestReward` -- y ese gancho corre DESPUES de la llamada, con el panel
-- ya cerrado. La misma trampa que el abandono y que el aceptar; aqui se cierra
-- de la misma forma y por el mismo sitio.
--
-- EL PNJ SE CAPTURA CUANDO `questnpc` EXISTE DE VERDAD, que es mientras la
-- ventana esta abierta -- o sea en los eventos del panel, no en el gancho del
-- boton. `QUEST_COMPLETE` es el que saca el panel de recompensa.
function Q:WireTurnIn()
	if type(GetQuestReward) ~= "function" then
		ns.Print("|cffff8800misiones:|r este cliente no tiene GetQuestReward; " ..
		         "el grupo no podra entregar contigo.")
		return
	end

	hooksecurefunc("GetQuestReward", function()
		turnUntil = GetTime() + ACCEPT_WINDOW
	end)
end

--- Ciclo -------------------------------------------------------------------

function Q:Create()
	if wired then return end
	wired = true

	self:WireButton()
	self:WireFollow()
	self:WireTurnIn()
	self:WireAbandon()

	ns.Link:On("QWHO", function(rest)
		-- DOS SENTIDOS: la peticion es `QWHO <id>` y la respuesta
		-- `QWHO <id> <lista>`. Se distinguen por el NUMERO DE CAMPOS, igual que
		-- `BAGS`; sin el segundo, esto es nuestro propio eco.
		local id, list = rest:match("^(%d+)%s+(.+)$")
		if not id then return end

		id = tonumber(id)
		who[id] = {}
		if list ~= "-" then
			for name, s in list:gmatch("([^,:]+):(%d+)") do
				table.insert(who[id], { name = name, status = tonumber(s) })
			end
		end

		-- Si el raton sigue encima, el tooltip esta pintado con lo de antes.
		if GameTooltip:IsShown() and GameTooltip:GetOwner() == QuestLogFramePushQuestButton then
			Tooltip(QuestLogFramePushQuestButton)
		end
	end)

	--- Resultados ---------------------------------------------------------

	ns.Link:On("QDONE", function(rest)
		-- LAS CINCO LETRAS. La `C` ya falto una vez -- `QCATCH` contestaba con
		-- ella y el patron solo aceptaba `[AT]`, asi que el resultado no se
		-- imprimia nunca -- y un mensaje que no sale es indistinguible de una
		-- orden que no llego. Al anadir `QDROP` toca la `D`.
		local kind, id, ok, bad = rest:match("^([ATCSD])%s+(%d+)%s+(%d+)%s+(%d+)$")
		if not kind then return end

		local verb = (kind == "A" and "aceptada")
		          or (kind == "T" and "entregada")
		          or (kind == "D" and "abandonada")
		          or "dada"
		ns.Print(("|cff33ccffmisiones:|r %s por %s%s"):format(
			verb, ok, tonumber(bad) > 0 and (", " .. bad .. " no pudieron") or ""))
	end)

	ns.Link:On("QERR", function(rest)
		local id, why = rest:match("^(%d+)%s+(.+)$")
		if not id then return end
		ns.Print("|cffff8800misiones:|r " .. why)
	end)
end

-- `/rts quests` y el boton del panel: abrir el registro nativo.
--
-- `ToggleQuestLog` es una funcion de C y esta en la misma familia que
-- `ToggleWorldMap`, que la etapa 5l confirmo PROTEGIDA en juego. `ShowUIPanel`
-- y `HideUIPanel` no lo estan -- son Lua corriente en `UIParent.lua:1922` y
-- `:1937`, leido del MPQ -- y `QuestLogFrame` es un `<Frame>` sin `protected`.
-- Asi que se abre por ahi y no por el atajo que parece el obvio.
function Q:Open()
	self:Create()
	if QuestLogFrame:IsShown() then
		HideUIPanel(QuestLogFrame)
	else
		ShowUIPanel(QuestLogFrame)
	end
end
