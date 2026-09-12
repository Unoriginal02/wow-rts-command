--[[
	Loot.lua -- por que la ventana de botin sale y se va en el mismo parpadeo.

	El sintoma, tal cual se reporto: *"cuando voy a lootear a un bicho me sale
	un frame el loot del bicho y al instante se esconde"*. La sospecha era
	nuestra lista de ocultado. NO LO ES, y eso ya esta cerrado: `LootFrame` no
	aparece NI UNA VEZ en el addon, ni en `rts_core.dll`, ni en `mod-rts`, y
	`Chrome.lua` esconde una lista escrita a mano donde el botin no esta.

	=== LO QUE SE MIDIO EL 2026-09-12 =======================================

	La primera version de esto saco la pila del `OnHide` y salio esto, en orden:

	    LootFrame.lua:75   -> HideUIPanel(self)      (brazo `LOOT_CLOSED`)
	    UIParent.lua:1990  -> HideUIPanel global, escribe un atributo
	    UIParent.lua:1315  -> el delegado lo lee
	    UIParent.lua:1640  -> SetUIPanel("left", nil)
	    UIParent.lua:1564  -> oldFrame:Hide()

	O sea: LA INTERFAZ NO DECIDE NADA. Le llega `LOOT_CLOSED` --
	`SMSG_LOOT_RELEASE_RESPONSE`-- entre 0 y 9 ms despues de abrirse el botin, y
	obedece. Con `auto=0` (nada de autobotin) y `recogidos 0` (ni un hueco
	vaciado): el botin se SUELTA, no se recoge.

	=== Y QUIEN LO SUELTA: TU PROPIA IA =====================================

	La segunda vuelta de la sonda dio los tres numeros que lo cierran: el cierre
	llega entre 80 y 130 ms (no en el mismo frame), el cliente te ve a 4.8 del
	cuerpo (o sea que no cierra por distancia) y la ventana se abre UNA vez (o
	sea que no es un segundo `SendLoot` pisando al primero).

	Ese retraso es un tick de IA, y en modo RTS tu personaje lleva IA: el
	selfbot. El camino, leido en mod-playerbots:

	    SMSG_LOOT_RESPONSE
	      -> disparador "loot response"   (PlayerbotAI.cpp:189)
	      -> accion "store loot"          (WorldPacketHandlerStrategy.cpp:40)
	      -> StoreLootAction::Execute: recorre los objetos, se queda con lo que
	         su estrategia permita -- nada, de ahi el `recogidos 0` -- y ACABE
	         COMO ACABE termina mandando CMSG_LOOT_RELEASE (LootAction.cpp:459).

	Lo que despistaba es que el addon YA le quitaba la estrategia `loot` a tu
	personaje por susurro, justo para que no recogiera sin ventana. Pero `store
	loot` no cuelga de `loot`: cuelga de `default`, el manejador de paquetes que
	lleva todo el que tenga IA. El arreglo esta en `RTSMode.lua`
	(`SelfSoloStrategies`), que ahora tambien manda `nc -default` y `co
	-default`, y ahi esta contado lo que eso se lleva por delante.

	=== QUE SE QUEDA ESTO HACIENDO ==========================================

	No arregla nada: MIDE, y ahora es la alarma de que el arreglo sigue puesto.
	Calla mientras la ventana se queda; habla si vuelve a cerrarse sola sin
	haber recogido nada. Un cierre TUYO no cuenta -- ni si recogiste algo, ni si
	tardaste en cerrarla lo que tarda una persona.
]]

local ADDON, ns = ...

local L = {}
ns.Loot = L

-- Cuanto se espera desde el ULTIMO evento antes de dar el parte. Tiene que
-- aguantar una rafaga entera (cerrar y volver a abrir llegan en el mismo frame)
-- y seguir siendo menos de lo que tarda una persona en cerrar a mano, o un
-- cierre tuyo contaria como anomalia y esto hablaria en cada cadaver.
local SETTLE = 0.6

-- Por encima de esto, cerrar la ventana es cosa tuya y no hay nada que avisar.
-- Generoso a proposito: el fallo cierra a los 100 ms y ni el mas rapido con el
-- raton baja de un segundo y medio, asi que el hueco entre los dos es enorme y
-- no hace falta afinar.
local HUMAN = 1.5

local watch = nil
local ticker = nil

-- Distancia entre tu y el cadaver TAL COMO LA VE EL CLIENTE.
--
-- Las dos posiciones salen del DLL, que lee la memoria del cliente: son lo que
-- el cliente cree, que es justo lo que hace falta aqui. Preguntarle al servidor
-- daria la otra mitad de la discusion y no la discusion.
--
-- El cadaver es el objetivo porque `DoInteract` hace `SetSelection` sobre el
-- antes de mandar el botin, asi que para cuando llega `LOOT_OPENED` el cliente
-- ya lo tiene seleccionado.
local function ClientDistance()
	local px, py, pz = ns.Bridge:GetPlayerWorldPosition()
	if not px then return nil end

	local guid = UnitGUID("target")
	if not guid then return nil end

	local tx, ty, tz = ns.Markers:UnitWorld(guid)
	if not tx then return nil end

	local dx, dy, dz = px - tx, py - ty, pz - tz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function Report()
	local w = watch
	watch = nil
	if ticker then ticker:Hide() end
	if not w then return end

	-- La ventana sigue puesta: es lo que tiene que pasar y no se dice nada.
	if LootFrame and LootFrame:IsShown() then return end

	-- NI UN CIERRE TUYO, que es lo que separa la alarma del ruido. Si vaciaste
	-- algun hueco, o si la ventana aguanto lo que tarda una persona en leerla y
	-- darle a la cruz, esto no es el fallo: es un botin normal.
	if w.cleared > 0 then return end
	if (w.last - w.t0) > HUMAN then return end

	local left = GetNumLootItems and GetNumLootItems() or 0
	ns.Print(("|cffffff00botin|r: %d objetos auto=%s | %s | recogidos %d | " ..
	          "quedan %d | dist %s | RTS %s"):format(
		w.n, tostring(w.auto), table.concat(w.seq, " "), w.cleared, left,
		w.dist and ("%.1f"):format(w.dist) or "?",
		w.rts and "|cff00ff00SI|r" or "|cffffff00NO|r"))

	-- La conclusion, escrita aqui y no en mi cabeza: quien lea esto en juego
	-- tiene que poder decidir sin volver al codigo. El orden importa -- se
	-- descartan primero las dos causas que NO son la conocida.
	if w.auto == 1 or (w.n > 0 and w.cleared >= w.n) then
		ns.Print("  |cff40ff40es el AUTOBOTIN|r: lo recogio el cliente solo " ..
		         "(|cffffff00/console autoLootDefault 0|r lo apaga).")
	elseif w.opens > 1 then
		ns.Print("  |cffff4040se abrio dos veces|r: el segundo SendLoot suelta el " ..
		         "primero. Son nuestra orden y el CMSG_LOOT del cliente a la vez.")
	elseif w.dist and w.dist > 5 then
		ns.Print(("  |cffff4040el cliente te cree a %.1f del cadaver|r: cierra el " ..
		          "botin porque para el estas lejos."):format(w.dist))
	else
		-- La de siempre. Si vuelve a salir es que el susurro no llego: el
		-- comando de playerbots no contesta, asi que la unica forma de
		-- comprobarlo es volver a mandarlo.
		ns.Print("  |cffff4040lo ha soltado tu propia IA|r (store loot). " ..
		         "|cffffff00/rts self|r dos veces vuelve a mandar los susurros.")
	end
end

local function EnsureTicker()
	if ticker then return end
	ticker = CreateFrame("Frame", "RTSLootWatch")
	ticker:Hide()
	ticker:SetScript("OnUpdate", function()
		if not watch then ticker:Hide() return end
		if GetTime() - watch.last < SETTLE then return end
		Report()
	end)
end

function L:Create()
	EnsureTicker()

	local ev = CreateFrame("Frame", "RTSLootEvents")
	ev:RegisterEvent("LOOT_OPENED")
	ev:RegisterEvent("LOOT_CLOSED")
	ev:RegisterEvent("LOOT_SLOT_CLEARED")
	ev:SetScript("OnEvent", function(_, event, arg1)
		local now = GetTime()

		if event == "LOOT_OPENED" then
			-- UNA SOLA MEDIDA POR CADAVER, y por eso el reloj no se reinicia en
			-- la segunda apertura: abrir, cerrar y volver a abrir es UN suceso
			-- con tres partes, y partirlo en dos partes lo haria ilegible --
			-- que es lo que hacia la version anterior.
			if not watch then
				watch = {
					t0 = now,
					n = GetNumLootItems and GetNumLootItems() or 0,
					auto = arg1,
					cleared = 0,
					opens = 0,
					seq = {},
					-- EL CONTROL. Sin esto no se puede separar "lo hace el modo
					-- RTS" de "lo hace este servidor siempre", que son dos
					-- arreglos en dos sitios distintos.
					rts = ns.RTSMode and ns.RTSMode.active or false,
					dist = ClientDistance(),
				}
			end
			watch.opens = watch.opens + 1
			watch.n = math.max(watch.n, GetNumLootItems and GetNumLootItems() or 0)
			table.insert(watch.seq, ("O@%d"):format(math.floor((now - watch.t0) * 1000 + 0.5)))
			watch.last = now
			ticker:Show()

		elseif not watch then
			return

		elseif event == "LOOT_SLOT_CLEARED" then
			watch.cleared = watch.cleared + 1
			watch.last = now

		elseif event == "LOOT_CLOSED" then
			table.insert(watch.seq, ("C@%d"):format(math.floor((now - watch.t0) * 1000 + 0.5)))
			watch.last = now
		end
	end)
end
