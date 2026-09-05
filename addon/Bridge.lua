--[[
	Bridge.lua -- native capability layer.

	WotLK 3.3.5a Lua cannot do three things this addon eventually needs:
	  1. read/steer the camera            (no API at all)
	  2. turn a screen click into a world position (no raycast until Cataclysm)
	  3. project a world position to screen (needed for drag-box selection)

	rts_core.dll will provide those by assigning a table to RTSCommand.Bridge.impl.
	Until then every call here returns nil and the addon degrades to the
	coordinate-free order set (go <name> / stay / follow / attack), which is
	fully functional -- just not click-to-move.

	Nothing outside this file may touch impl directly. Orders and UI ask the
	Bridge and branch on nil. That way the DLL landing is a pure upgrade with
	no changes anywhere else.
]]

local ADDON, ns = ...
RTSCommand = ns

local B = {}
ns.Bridge = B

-- rts_core.dll cannot expose callable C functions to WoW's Lua: the client
-- rejects C function pointers outside Wow.exe (ERROR #134). So the DLL PUSHES
-- instead -- it sets plain Lua globals (RTS_Ready, RTS_PX, ...) ~10x/second via
-- the client's own script execution. We read those globals; nothing is called
-- across the boundary.

B._attached = false

function B:IsNative()
	return RTS_Ready == 1
end

-- Returns true the first time the native side is detected.
function B:TryAttach()
	if self._attached then return false end
	if RTS_Ready ~= 1 then return false end

	self._attached = true
	self.version = RTS_Version or "?"
	return true
end

-- Player world position, or nil if the DLL is absent / not in world yet.
function B:GetPlayerWorldPosition()
	if RTS_Ready ~= 1 or RTS_HasPos ~= 1 then return nil end
	return RTS_PX, RTS_PY, RTS_PZ, RTS_PF
end

-- Per-unit world position is not available in the push model yet (the DLL would
-- need to know which GUID to publish). Returns nil until the request channel
-- exists; callers already branch on nil.
function B:GetUnitWorldPosition(_, _)
	return nil
end

function B:ObjectCount()
	return RTS_N
end

-- Monotonic counter the DLL bumps each publish. Lets us tell "attached and
-- alive" from "attached but the DLL stopped ticking".
function B:Heartbeat()
	return RTS_HB
end

-- Ground point under the mouse cursor as x, y, z world coords, or nil.
-- rts_core 0.8.0+ raycasts the cursor against real terrain and publishes the
-- hit; Markers unprojects onto a plane at that height each frame, so the point
-- is both correct on slopes and locked to the mouse. Without the DLL it falls
-- back to a plane at the player's Z -- fine beside your character, wrong up a
-- hill. This is what makes Move a click-to-move order.
function B:GetCursorWorldPosition()
	if not ns.Markers then return nil end
	return ns.Markers:GetCursorPoint()
end

--- Convenience -------------------------------------------------------------

-- True when we can issue coordinate orders ("go X;Y;Z").
function B:HasWorldCoords()
	return self:GetPlayerWorldPosition() ~= nil
end

--- Como te llamas -----------------------------------------------------------
--
-- `UnitName("player")` NO ES DE FIAR desde que se puede cambiar de personaje sin
-- pasar por la pantalla de seleccion. Visto en juego el 2026-09-03: despues del
-- cambio el cliente sigue ensenando el nombre del personaje anterior, en su
-- marco y en esa llamada. La identidad SI cambia -- el guid es el nuevo y el
-- grupo es el nuevo -- pero el texto va por detras.
--
-- Y no es cosmetico, porque el heroe que dejas vuelve de bot Y SE LLAMA COMO TE
-- LLAMABAS: media docena de sitios del addon comparan nombres para decidir "¿es
-- este mi personaje?", y con el nombre viejo pegado todos contestan que si sobre
-- el bot equivocado. Ademas el canal con el servidor se susurra a uno mismo POR
-- NOMBRE, asi que un nombre rancio lo deja mudo entero.
--
-- El servidor lo dice al terminar el cambio (`SWAPPED`) y ahi se guarda, JUNTO
-- CON EL GUID AL QUE SE REFIERE: sin eso, un cambio seguido de una reconexion
-- dejaria el nombre de otro pegado para siempre. El guid es la unica identidad
-- que no miente -- sale del gestor de objetos del cliente, que es el campo que
-- escribe el `UPDATEFLAG_SELF` -- asi que la anulacion solo vale mientras siga
-- siendo el mismo.
function ns.MyName()
	if ns.serverName and ns.serverNameGuid
	   and ns.serverNameGuid == UnitGUID("player") then
		return ns.serverName
	end
	return UnitName("player")
end

-- Y LA CLASE TIENE EXACTAMENTE EL MISMO DEFECTO, descubierto el 2026-09-05
-- viendo a un mago con el color del guerrero despues de un cambio.
--
-- No era una sospecha: esta desensamblado. `UnitClass` (`0x0060FEC0`) compara su
-- argumento con la cadena "player" igual que `UnitName`, y si acierta NO mira el
-- objeto -- llama a `0x006B1080`, que son dos instrucciones:
--
--     006B1080  mov al, byte ptr [0xC79E89]
--     006B1085  ret
--
-- Un byte estatico. Y esta pegado al del nombre (`0x00C79D18`, via `0x006B1060`)
-- y al de la raza (`0x00C79E8A`, via `0x006B1090`), o sea que son el MISMO
-- bloque: la ficha de "quien soy" que rellena la pantalla de seleccion de
-- personaje -- justo el paso que el cambio se salta.
--
-- ASI QUE LA REGLA ES MAS AMPLIA DE LO QUE DECIA LA 0.62.0: no es que el NOMBRE
-- de "player" mienta tras un cambio, es que **nombre, clase y raza de "player"
-- mienten los tres**, y son los tres campos que el cliente guarda aparte en vez
-- de leer del objeto. Todo lo demas (vida, poder, retrato, hechizos) sale del
-- objeto y es correcto -- que es justo lo que hacia el sintoma tan raro: el
-- retrato era Bob y el nombre Neferite.
--
-- LA CLASE SE APRENDE DEL GRUPO, no del servidor, y por dos razones. Una: el
-- personaje al que saltas ERA un companero tuyo un segundo antes, asi que su
-- `UnitClass("partyN")` -- que si pasa por el objeto -- ya se leyo y es correcto.
-- Dos: asi no hace falta ningun verbo nuevo, ni una tabla de ids de clase
-- escrita a mano, que es la clase de constante que este proyecto paga cara.
--
-- Sin entrada aprendida se cae a `UnitClass("player")`, que es correcto mientras
-- no haya habido un cambio -- o sea siempre, en una sesion normal.
-- SE GUARDA EN DISCO, y hace falta: lo aprendido vive en memoria, asi que un
-- `/reload` despues de un cambio lo perderia -- y entonces el color volveria a
-- estar mal, porque tu propio personaje NO aparece en tu grupo y no hay de
-- donde reaprenderlo. Un `/reload` es ademas lo primero que se hace cuando algo
-- se ve raro, o sea justo el gesto que reintroduciria el fallo.
--
-- La clave es el nombre y el valor un token de clase. Se puede guardar sin
-- pensarlo dos veces porque **la clase de un personaje no cambia nunca**: una
-- entrada vieja no puede quedarse obsoleta, solo sobrar. Es lo contrario del
-- `grow = 688` y del `camHold`, que eran ajustes cuyo significado cambio.
local classOf

local function Learned()
	if classOf then return classOf end
	if type(RTSCommandDB) ~= "table" then return nil end
	RTSCommandDB.classOf = RTSCommandDB.classOf or {}
	classOf = RTSCommandDB.classOf
	return classOf
end

function ns.NoteClass(name, unit)
	if not name or not unit then return end
	local t = Learned()
	if not t then return end
	local token = select(2, UnitClass(unit))
	if token then t[name] = token end
end

function ns.MyClass()
	local mine = ns.MyName()
	local t = Learned()
	if mine and t and t[mine] then return t[mine] end
	return select(2, UnitClass("player"))
end

-- ¿ESTE TOKEN SOY YO? Por guid, nunca por nombre -- la regla de la 0.60.0. Hace
-- falta porque despues de un cambio hay un companero que se llama como te
-- llamabas.
function ns.IsMe(unit)
	if not unit then return false end
	if unit == "player" then return true end
	return UnitIsUnit(unit, "player") and true or false
end

-- El nombre que hay que ENSENAR de un token. Para cualquiera menos tu es el del
-- cliente; para ti es el unico que no miente.
function ns.UnitLabel(unit)
	if ns.IsMe(unit) then return ns.MyName() end
	return UnitName(unit)
end

return B
