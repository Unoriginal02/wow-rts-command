--[[
	Chain.lua -- ataque encadenado. Marcas 1, 2, 3, 4 y el grupo va en ese orden.

	=== LOS NUMEROS SON LOS ICONOS DE BANDA DEL CLIENTE =====================

	Y eso no es un apano: es lo unico que se dibuja sobre el modelo con la
	profundidad correcta. Un numero pintado proyectando la posicion del bicho a
	un pixel de la interfaz no tiene profundidad -- se dibuja encima de la colina
	que deberia taparlo -- y ademas nada con la camara, porque la camara que
	publica el DLL nunca es la del frame que se esta dibujando. Eso ya se perdio
	una vez, en la etapa 5e, y esta escrito.

	Los iconos de banda los coloca el cliente en su propio bucle a partir de la
	posicion del mundo, igual que las placas de nombre: siguen perfectamente
	porque no se sigue nada.

	El precio: son OCHO y son los mismos que usa la banda. Ocho enemigos
	encadenados es mas de lo que nadie encadena.

	=== EL GESTO: SHIFT + CLICK IZQUIERDO SOBRE UN HOSTIL ==================

	Estaba libre y es el sitio correcto. Los tres vecinos ya estaban cogidos y
	cada uno por un motivo escrito:

	  * click izquierdo a secas sobre algo que no es tuyo -> preguntar sus
	    misiones (arriba, en este mismo bloque de `RTSMode`);
	  * click derecho -> la orden de siempre, que el servidor clasifica;
	  * SHIFT + click derecho -> encadenar un punto de ruta, desde la etapa 5l.
	    Y ese no se puede compartir: darle un segundo significado segun lo que
	    hubiera bajo el cursor haria que encadenar una ruta dependiera de con
	    cuanta punteria pasaste por encima de un lobo. Esta decidido por escrito
	    desde entonces.

	Ademas, shift + izquierdo sobre un hostil era EXACTAMENTE el gesto de fijar
	un bicho en la fila de enemigos, que se borro con la sala. `RTSMode.lua` dejo
	escrito que esta era la linea donde se enganchaba.

	=== `SetRaidTarget` O `SetRaidTargetIcon`: SE PRUEBAN LAS DOS ==========

	Es la regla de este proyecto desde `nameplateMaxDistance`: comprobar contra
	el cliente, no contra internet. Aqui ni siquiera hace falta acertar de
	antemano -- se llama a la que exista, y si ninguna hace nada, `/rts chain`
	lo dice en vez de dejar una cadena sin numeros que parece rota.
]]

local ADDON, ns = ...

local C = {}
ns.Chain = C

local MAX = 8      -- los iconos de banda del cliente, ni uno mas

C.list = {}        -- { {guid, name}, ... } en orden
C.current = nil    -- guid del de turno, segun el servidor

--- Marcar ------------------------------------------------------------------

-- Poner el icono N sobre lo que el raton tenga encima AHORA.
--
-- Solo funciona sobre `mouseover`, y por eso se llama en el mismo instante del
-- click y no despues: en 3.3.5a no hay forma de poner un icono sobre un guid
-- suelto, tiene que ser una unidad que el cliente pueda nombrar.
local function SetIcon(unit, index)
	if type(SetRaidTargetIcon) == "function" then
		SetRaidTargetIcon(unit, index)
		return true
	end
	if type(SetRaidTarget) == "function" then
		SetRaidTarget(unit, index)
		return true
	end
	return false
end

local function ClearIcon(unit)
	if type(SetRaidTargetIcon) == "function" then
		SetRaidTargetIcon(unit, 0)
	elseif type(SetRaidTarget) == "function" then
		SetRaidTarget(unit, 0)
	end
end

local function HexOf(guid)
	return (tostring(guid or ""):gsub("^0[xX]", ""))
end

--- La cadena ---------------------------------------------------------------

function C:IndexOf(guid)
	for i, e in ipairs(self.list) do
		if e.guid == guid then return i end
	end
	return nil
end

-- Manda la lista ENTERA. Ver `RtsChain.h`: un protocolo incremental necesita
-- que las dos partes coincidan sobre el estado, y aqui el estado lo mueve el
-- mundo (el bicho se muere, huye, lo mata otro).
function C:Push()
	local sel = ns.Selection:Get()
	if #sel == 0 then
		ns.Print("|cffff8800cadena:|r no hay nadie seleccionado.")
		return
	end
	if #self.list == 0 then
		ns.SendServer("CHAINOFF")
		return
	end

	local guids = {}
	for _, e in ipairs(self.list) do table.insert(guids, HexOf(e.guid)) end
	ns.SendServer(("CHAIN %s %s"):format(table.concat(guids, ";"), table.concat(sel, ";")))
end

-- El gesto. `unit` es el token que el cliente tiene ahora mismo bajo el raton
-- ("mouseover"), y hace falta para el icono.
function C:Add(guid, name, unit)
	if not guid then return end

	local at = self:IndexOf(guid)
	if at then
		-- Ya estaba: se quita. Es lo que espera cualquiera de un gesto que
		-- anade, y evita tener que inventar un segundo gesto para quitar.
		table.remove(self.list, at)
		if unit then ClearIcon(unit) end
		self:Renumber()
		self:Push()
		ns.Print(("|cffffd100cadena:|r fuera %s (%d)"):format(name or "?", #self.list))
		return
	end

	if #self.list >= MAX then
		ns.Print(("|cffff8800cadena:|r solo hay %d iconos de banda; quita alguno."):format(MAX))
		return
	end

	table.insert(self.list, { guid = guid, name = name })
	if unit and not SetIcon(unit, #self.list) then
		ns.Print("|cffff8800cadena:|r este cliente no deja poner iconos de banda; " ..
		         "la cadena funciona, pero sin numeros.")
	end
	self:Push()
	ns.Print(("|cffffd100cadena %d:|r %s"):format(#self.list, name or "?"))
end

-- Renumerar despues de quitar uno. Los iconos SOLO se pueden reponer sobre
-- unidades que el cliente sepa nombrar ahora mismo, asi que esto arregla lo que
-- puede y deja lo demas: un numero viejo sobre un bicho lejano es feo, pero
-- inventarse un token para llegar a el no se puede.
function C:Renumber()
	for i, e in ipairs(self.list) do
		if UnitExists("target") and UnitGUID("target") == e.guid then
			SetIcon("target", i)
		elseif UnitExists("mouseover") and UnitGUID("mouseover") == e.guid then
			SetIcon("mouseover", i)
		end
	end
end

function C:Clear(quiet)
	if #self.list == 0 then return end
	self.list = {}
	self.current = nil
	ns.SendServer("CHAINOFF")
	if not quiet then ns.Print("|cff888888cadena: limpia.|r") end
end

function C:Report()
	if #self.list == 0 then
		ns.Print("cadena: vacia. Shift + click izquierdo sobre un enemigo para encadenar.")
		return
	end
	for i, e in ipairs(self.list) do
		local mark = (e.guid == self.current) and " |cff00ff00<- ahora|r" or ""
		ns.Print(("  %d. %s%s"):format(i, e.name or "?", mark))
	end
end

--- El canal ----------------------------------------------------------------

function C:Create()
	if self.created then return end
	self.created = true

	ns.Link:On("CHAINAT", function(rest)
		local done, total, hex = rest:match("^(%d+)%s+(%d+)%s+(%x+)$")
		if not done then return end
		C.current = "0x" .. string.upper(string.rep("0", 16 - #hex) .. hex)
		-- El guid que publica el DLL viene como "0x00000000000012AB", asi que se
		-- rellena a 16 para poder comparar. Sin esto la comparacion falla en
		-- silencio y "<- ahora" no sale nunca, que se lee como que la cadena no
		-- avanza cuando en realidad avanza perfectamente.
	end)

	ns.Link:On("CHAINEND", function()
		C.list = {}
		C.current = nil
	end)
end
