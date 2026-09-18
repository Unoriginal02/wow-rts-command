--[[
	Xp.lua -- el dial de experiencia del mundo, visto desde la barra.

	Dos botones en la fila fija de arriba a la derecha (`Tray.lua`) suben y
	bajan la experiencia de CINCUENTA EN CINCUENTA, y lo que queda se escribe
	en el chat. Con las tasas del fichero a 1 -- que es como esta hoy -- el
	dial se lee como el multiplicador entero, asi que el doble esta a dos
	clicks: 100, 150, 200.

	=== LO QUE SE MUEVE NO ESTA AQUI =======================================

	El tanto por ciento vive en el servidor (`mod-rts/src/RtsXp.cpp`) y es un
	MULTIPLICADOR sobre lo que diga `worldserver.conf`: al 110%, una tasa de x5
	pasa a x5,5. Este fichero no calcula nada -- manda la direccion y escribe el
	numero que le contesten.

	Y por eso el numero no se guarda en el addon: un valor nuestro seria una
	segunda copia de algo que ya tiene duenno, y las dos copias se separan la
	primera vez que se toca el dial desde otro sitio -- otro personaje, un
	`.reload config`, un reinicio.

	=== EL PLAZO, QUE ES MEDIA FUNCIONALIDAD ===============================

	Un verbo que mod-rts no conoce **no da error: no contesta**. Es la leccion
	que el modulo lleva escrita desde `CASTQ`, y aqui muerde entero: los dos
	botones son nuevos, el mundo hay que reiniciarlo para que los entienda, y
	pulsarlos contra un worldserver viejo no escribiria ni una linea. Eso se lee
	como un boton roto, no como un servidor por actualizar.

	Asi que cada pulsacion abre un plazo de 2,5 segundos y, si nadie contesta,
	lo dice con todas las letras.
]]

local ADDON, ns = ...

local X = {}
ns.Xp = X

-- La version de mod-rts que conoce el verbo. Solo sale en el aviso del plazo:
-- no se comprueba ANTES de mandar porque `ServerAtLeast` contesta `false`
-- mientras la version no haya llegado, y en los primeros segundos de sesion eso
-- acusaria de viejo a un modulo que esta al dia.
local NEEDS = "0.57"

-- Lo ultimo que dijo el servidor, para saber si un paso ha topado con el tope.
X.percent = nil

local waiting     -- "UP" | "DOWN" | "?" mientras se espera contestacion
local watch       -- el frame del plazo, uno y reutilizado

local function Stop()
	waiting = nil
	if watch then watch:SetScript("OnUpdate", nil) end
end

local function Expect(what)
	waiting = what
	if not watch then watch = CreateFrame("Frame", "RTSXpWatch") end
	watch.acc = 0
	watch:SetScript("OnUpdate", function(f, elapsed)
		f.acc = f.acc + elapsed
		if f.acc < 2.5 then return end
		f:SetScript("OnUpdate", nil)
		if not waiting then return end
		waiting = nil
		ns.Print("|cffff8800XP:|r the server did not answer. This needs " ..
			"|cffffff00mod-rts " .. NEEDS .. "|r -- restart the worldserver.")
	end)
end

local function Send(what)
	ns.SendServer(what == "?" and "XP" or ("XP " .. what))
	Expect(what)
end

--- El mando ---------------------------------------------------------------

-- `+` sube, `-` baja, nada pregunta. Las palabras estan por si se escribe a
-- mano: los botones mandan el signo.
function X:Command(arg)
	local a = (arg or ""):match("^(%S*)"):lower()
	if a == "+" or a == "up" or a == "mas" then
		Send("UP")
	elseif a == "-" or a == "down" or a == "menos" then
		Send("DOWN")
	else
		self:Report()
	end
end

function X:Create()
	if self.created then return end
	self.created = true

	-- NOS SUSURRAMOS A NOSOTROS MISMOS, asi que por aqui pasa tambien nuestro
	-- propio "XP UP" de ida. Se distingue solo: lo que manda el servidor es un
	-- numero y lo que mandamos nosotros no.
	ns.Link:On("XP", function(rest)
		local p = tonumber(rest)
		if not p then return end

		local before, asked = X.percent, waiting
		Stop()
		X.percent = p

		-- QUE EL TOPE SE DIGA. Los limites (50% y 1000%) los pone el servidor,
		-- asi que desde aqui un paso que no mueve nada se ve igual que un paso
		-- que si: mismo numero, misma linea. Sin esta frase, pulsar veinte
		-- veces el menos y ver siempre "10%" parece que el boton falla.
		if before and p == before and (asked == "UP" or asked == "DOWN") then
			ns.Print(("|cffffff00world XP:|r %d%% -- that is as %s as it goes.")
				:format(p, asked == "DOWN" and "low" or "high"))
			return
		end

		ns.Print(("|cffffff00world XP:|r %d%%"):format(p))
	end)
end

-- NO ESCRIBE EL NUMERO, LO PREGUNTA. El que tengamos guardado es de la ultima
-- vez que se pulso un boton, y entre medias ha podido cambiar por otro lado --
-- otro personaje, un `.reload config`. Lo escribe el manejador de arriba cuando
-- llega la contestacion, que es la unica que esta al dia.
function X:Report()
	ns.Print("|cffffff00/rts xp +|r and |cffffff00/rts xp -|r move it 50 at a time. " ..
		"It is a multiplier over |cffffff00worldserver.conf|r -- it applies to the " ..
		"bots as well, and it survives a restart.")
	Send("?")
end
