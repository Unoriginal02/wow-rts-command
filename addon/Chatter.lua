--[[
	Chatter.lua -- esconde el volcado de menus de los bots, y lo guarda.

	=== QUE ES LO QUE SE ESCONDE ==========================================

	mod-playerbots le COPIA A CADA BOT lo que tu haces con un NPC: tu cliente
	manda "hablar con Keldas" y el modulo reenvia ese paquete a los cinco
	(`PlayerbotAI.cpp`, `masterIncomingPacketHandlers.AddHandler(CMSG_GOSSIP_HELLO)`).
	Los cinco le dan los buenos dias y te susurran su menu entero:

	    [Bob] susurra: --- Keldas ---
	    [Bob] susurra: Ah friend, I only help hunters and their pets.
	    [Bob] susurra: [0] How do I train my pet?

	Con cuatro bots eso son veinte lineas por cada NPC al que te acerques, y se
	come la pantalla justo cuando estas leyendo lo que dice el NPC de verdad.

	NO SE PUEDE APAGAR EN EL SERVIDOR. El `silent` de `GossipHelloAction` esta a
	falso en el codigo del modulo y no hay opcion en `playerbots.conf`; y ese
	modulo es ajeno, asi que se apaga donde si es nuestro: en el chat.

	=== POR QUE HACE FALTA UNA VENTANA DE TIEMPO ==========================

	Dos de las tres lineas se reconocen por su forma -- `--- Nombre ---` y
	`[0] Lo que sea` -- y la tercera NO: es el texto del NPC, que es prosa
	cualquiera y puede decir lo que le de la gana. Una expresion regular no la
	distingue de un bot contestandote.

	Lo que si la distingue es CUANDO llega: el volcado es una rafaga, todas las
	lineas del mismo bot en el mismo segundo. Asi que la cabecera abre una
	ventana de dos segundos para ESE bot y lo que caiga dentro se va con ella.

	El precio esta escrito a proposito: si un bot te contesta otra cosa dentro
	de esos dos segundos, se pierde tambien. Es el caso raro y es el momento en
	el que menos importa.

	=== NO SE TIRA, SE GUARDA =============================================

	`/rts chat ver` ensena lo ultimo que se escondio. Sin eso, "filtrar" seria
	perder -- y lo que hay ahi dentro es justamente lo que hace falta para
	contestarle al NPC (`talk <numero>` quiere el numero del corchete).
]]

local ADDON, ns = ...

local C = {}
ns.Chatter = C

C.on = true

local WINDOW = 2       -- segundos de rafaga
local KEEP   = 40      -- lineas guardadas

local openUntil = {}   -- bot -> hasta cuando dura su rafaga
local kept = {}        -- las escondidas, las ultimas KEEP
local total = 0        -- cuantas van en toda la sesion

--- Quien es un bot -------------------------------------------------------
--
-- Solo se filtra a los del GRUPO. Un susurro de una persona no se toca ni por
-- error, aunque empiece por tres guiones: esconderle un mensaje a alguien que
-- te esta hablando es mucho peor que ver veinte lineas de menu.
--
-- El nombre llega a veces con reino pegado ("Bob-Reino"), asi que se corta.

local function IsBot(sender)
	if not sender or sender == "" then return false end
	local name = sender:match("^[^%-]+") or sender
	for _, m in ipairs(ns.Selection:GetRoster()) do
		if m.name == name then return true end
	end
	return false
end

local function Remember(sender, msg)
	total = total + 1
	table.insert(kept, { who = sender, text = msg })
	while #kept > KEEP do table.remove(kept, 1) end
end

--- El filtro -------------------------------------------------------------

local function Filter(frame, event, msg, sender, ...)
	if not C.on then return false end
	if type(msg) ~= "string" or not IsBot(sender) then return false end

	local now = GetTime()
	local header = msg:match("^%-%-%-%s.+%s%-%-%-$") ~= nil
	local item   = msg:match("^%[%d+%]%s") ~= nil
	local inside = (openUntil[sender] or 0) > now

	if not (header or item or inside) then return false end

	-- La ventana se estira con cada linea escondida: el volcado de un menu
	-- largo tarda mas de dos segundos en salir entero por el limite de ritmo
	-- del chat, y cortarlo por la mitad deja media rafaga en pantalla, que es
	-- lo peor de los dos mundos.
	openUntil[sender] = now + WINDOW
	Remember(sender, msg)
	return true
end

function C:Wire()
	if self.wired then return end
	self.wired = true
	ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", Filter)
end

--- Decirlo y recuperarlo -------------------------------------------------

function C:Report(sub)
	sub = (sub or ""):lower()

	if sub == "on" or sub == "si" then
		self.on = true
		ns.Print("chat: |cff00ff00escondiendo|r el volcado de menus de los bots.")
		return
	end

	if sub == "off" or sub == "no" then
		self.on = false
		ns.Print("chat: |cffff8800todo a la vista|r, incluidos los menus de los bots.")
		return
	end

	if sub == "ver" or sub == "show" then
		if #kept == 0 then
			ns.Print("chat: no se ha escondido nada todavia.")
			return
		end
		ns.Print(("|cffffff00lo ultimo escondido|r (%d de %d):"):format(#kept, total))
		for _, k in ipairs(kept) do
			ns.Print(("  |cff9482c9[%s]|r %s"):format(k.who, k.text))
		end
		ns.Print("Para contestarle al NPC: selecciona al bot y " ..
			"|cffffff00/rtscmd talk <numero>|r, el del corchete.")
		return
	end

	ns.Print(("|cffffff00chat|r: el volcado de menus de los bots esta %s. " ..
		"%d linea(s) escondidas."):format(
		self.on and "|cff00ff00escondido|r" or "|cffff8800a la vista|r", total))
	ns.Print("|cffffff00/rts chat ver|r lo ensena  " ..
		"|cffffff00off|r lo deja salir  |cffffff00on|r lo vuelve a esconder")
end

C:Wire()
