-- Body.lua -- LA SONDA DEL CUERPO. Instrumento, no funcion.
--
-- El heroe se vuelve invisible en cuanto su jugador lleva PLAYER_FLAGS_UBER,
-- que es uno de los dos flags que abren la camara de comentarista. La cadena
-- esta desensamblada de ESTE Wow.exe y escrita en `rts-client-mod/src/
-- Offsets.h`; el resumen es que un "emite esta unidad" por unidad
-- (0x0073A890) le pregunta a 0x006DE980 con ESE jugador y se salta la emision
-- si contesta que si. Los bots no llevan los flags: por eso desaparece el tuyo
-- y ellos no, y por eso forzar el predicado el 2026-09-08 escondio a todos.
--
-- Este fichero no arregla nada. Contesta dos preguntas, cada una con su
-- interruptor, para poder decidir la forma de la cura ANTES de construirla:
--
--   /rts body flags on    ¿bastan los flags, sin servidor ni camara de por
--                         medio, para que el heroe desaparezca?
--   /rts body skip on     con los flags puestos, ¿reaparece anulando ESE
--                         salto -- dos bytes, un solo sitio de llamada?
--
-- Las dos combinaciones que importan:
--   1  -> flags puestos, sin parche   => se espera heroe INVISIBLE
--   5  -> flags puestos, con parche   => si el heroe se VE, la cura son 2 bytes
--   2  -> flags borrados cada tick    => el deshacer, y la prueba de la otra
--                                        cura posible (la ventana de flags)
--
-- Va apagado de fabrica y no se guarda en disco A PROPOSITO. Una sonda con su
-- interruptor guardado es el `camHold` del 2026-08-23: la funcion se escondio,
-- el ajuste sobrevivio, y se rearmaba sola en cada sesion.

local ADDON, ns = ...

local B = {}
ns.Body = B

local CVAR = "rtsBody"

local FLAGS_ON  = 1
local FLAGS_OFF = 2
local SKIP      = 4
local REPORT    = 8
local INVERT    = 16
local UBER_ONLY = 32    -- solo el bit 19, sin el 22
local COMM_ONLY = 64    -- solo el bit 22, sin el 19
local NO_FIX    = 8192  -- desarmar el arreglo automatico (para volver a ver el fallo)
local BLINK_OFF = 16384 -- apagar el parpadeo. CANDIDATO, no cura
local ACT_FIX   = 32768 -- devolver "puedo atacar" (el bit 19 lo veta)

-- Se crea si no esta. `SetCVar` sobre un nombre que no existe NO DA ERROR: no
-- hace nada. Es como el canal del FOV llevaba tres etapas fallando en silencio,
-- asi que aqui se comprueba y se canta.
local function Ensure()
	if GetCVar(CVAR) ~= nil then return true end
	if type(RegisterCVar) == "function" then
		RegisterCVar(CVAR, "0")
	end
	if GetCVar(CVAR) ~= nil then return true end
	ns.Print("|cffff0000body:|r no puedo crear el CVar |cffffff00" .. CVAR ..
	         "|r; la sonda no puede hablar con el DLL.")
	return false
end

local function Get()
	local v = tonumber(GetCVar(CVAR) or "0") or 0
	if v < 0 then v = 0 end
	return v
end

local function Set(v)
	if not Ensure() then return end
	SetCVar(CVAR, tostring(v))
	B:Report()
end

local function Bit(v, mask, on)
	if on then
		if v % (mask * 2) >= mask then return v end
		return v + mask
	end
	if v % (mask * 2) >= mask then return v - mask end
	return v
end

local function Has(v, mask)
	return v % (mask * 2) >= mask
end

-- El codigo de sitio viaja en los bits 7+ del CVar. Estas viven aqui arriba
-- porque `B:Report` las usa y `B:Sites` esta doscientas lineas mas abajo: la
-- version anterior las declaraba junto a `B:Sites` y `check_addon.py` la paro
-- en seco -- una era una llamada a nil y la otra una global muda.
local SITE_SHIFT = 128    -- 2^7
local SITES_ALL  = 63

local function SiteCode(v)
	return math.floor(v / SITE_SHIFT) % 64
end

local function SetSite(v, code)
	local rest = v % SITE_SHIFT
	local high = math.floor(v / SITE_SHIFT / 64) * 64
	return rest + (high + code) * SITE_SHIFT
end

function B:Report()
	if GetCVar(CVAR) == nil then
		ns.Print("|cffff0000body:|r el CVar |cffffff00" .. CVAR ..
		         "|r no existe todavia.")
		return
	end
	local v = Get()
	local dll = (RTS_Ready == 1)
	ns.Print(("body: modo |cffffff00%d|r  flags=%s  parche=%s  informe=%s  DLL=%s"):format(
		v,
		Has(v, FLAGS_OFF) and "|cffff8000BORRAR|r"
			or (Has(v, UBER_ONLY) and "|cff00ff00SOLO UBER|r"
			or (Has(v, COMM_ONLY) and "|cff00ff00SOLO COMM|r"
			or (Has(v, FLAGS_ON) and "|cff00ff00PONER|r" or "no tocar"))),
		Has(v, SKIP) and "|cff00ff00si|r" or "no",
		Has(v, REPORT) and "si" or "no",
		dll and "|cff00ff00inyectado|r" or "|cffff0000AUSENTE|r"))
	local code = SiteCode(v)
	if code == SITES_ALL then
		ns.Print("  sitios del predicado: |cffff8000LOS DIECIOCHO apagados|r")
	elseif code > 0 then
		ns.Print(("  sitios del predicado: |cffff8000apagado el %d|r"):format(code - 1))
	end
	if Has(v, ACT_FIX) then
		ns.Print("  espada: |cff00ff00veredicto del bit 19 anulado|r (puedes atacar)")
	end
	if not dll then
		ns.Print("  |cffff0000Sin el DLL la sonda no hace absolutamente nada.|r " ..
		         "Se abre con 2-Jugar.bat.")
	end
end

-- ESTAS DOS VIVEN AQUI ARRIBA Y NO JUNTO A `Park`, QUE ES DONDE ESTABAN.
-- `B:Flags` las escribe y el `OnUpdate` las lee; declaradas mas abajo, lo que
-- Flags escribia era una GLOBAL con el mismo nombre y el bucle leia la local,
-- que valia 0 para siempre. O sea: `flags on` NO APARCABA NUNCA la camara y la
-- prueba seguia siendo imposible de mirar -- sin un error, sin una linea en
-- ningun log. Es el fallo de la funcion local usada antes de declararse, pero
-- en variable, que es la version muda: una funcion que aun no existe al menos
-- revienta. `check_addon.py` ahora lo caza (2026-09-09).
local parkTries = 0
local parkNext  = 0

-- La comprobacion honesta del aparcado: lo que se PIDIO, para compararlo un
-- tick despues con lo que el DLL lee de la camara de verdad.
local checkAt
local checkX, checkY, checkZ

function B:Flags(on)
	local v = Get()
	-- Los modos de un bit son EXCLUYENTES con este: si no se limpiaran, un
	-- `flags on` detras de un `flags uber` dejaria pedidas las dos cosas y el
	-- DLL tendria que desempatar. Un interruptor que depende del orden en que
	-- se tecleo es un interruptor que miente.
	v = Bit(v, UBER_ONLY, false)
	v = Bit(v, COMM_ONLY, false)
	if on then
		v = Bit(v, FLAGS_OFF, false)
		v = Bit(v, FLAGS_ON, true)
	else
		v = Bit(v, FLAGS_ON, false)
		v = Bit(v, FLAGS_OFF, true)
	end
	Set(v)

	-- La puerta la abre el DLL en su siguiente tick (33 Hz), no aqui, asi que
	-- aparcar en esta misma linea llegaria antes que el permiso. Se reintenta
	-- durante dos segundos y se calla hasta que uno cuela.
	if on then
		parkTries = 8
		parkNext = 0
	else
		parkTries = 0
	end
end

-- UN BIT SOLO, QUE ES LO QUE FALTABA MEDIR.
--
-- `flags on` pone los DOS a la vez, asi que A1 -- "los flags son la causa" --
-- no dice cual de los dos. Y esa diferencia manda: el bit 19 ya tiene un
-- segundo consumidor conocido (`0x00729740`, el predicado de 28 llamantes que
-- mata el mouseover), mientras que el 22 solo lo mira la banda del
-- comentarista. Son dos busquedas distintas.
--
-- LO BUENO DE ESTA PRUEBA ES QUE NO NECESITA LA CAMARA. Un bit solo no abre la
-- puerta del comentarista, asi que la camara se queda donde esta y te miras en
-- tercera persona como siempre. Ni aparcar, ni puerta, ni reintentos: se ve o
-- no se ve.
function B:OneBit(which)
	local v = Get()
	v = Bit(v, FLAGS_ON, false)
	v = Bit(v, FLAGS_OFF, false)
	v = Bit(v, UBER_ONLY, which == "uber")
	v = Bit(v, COMM_ONLY, which == "comm")
	Set(v)
	ns.Print(("|cffff8000body:|r solo |cffffff00%s|r. Mirate en tercera persona: " ..
	          "¿desapareces?"):format(
		which == "uber" and "PLAYER_FLAGS_UBER (bit 19)"
		                or "PLAYER_FLAGS_COMMENTATOR2 (bit 22)"))
	ns.Print("  |cffffff00/rts body flags off|r para volver.")
end

-- APAGAR LOS SITIOS DE LLAMADA DEL PREDICADO, DE UNO EN UNO.
--
-- `0x006DE980` contesta "este jugador es espectador" y tiene DIECIOCHO sitios
-- de llamada. Forzar el predicado entero ya se probo el 2026-09-08 y dejo la
-- pantalla sin nadie: le decia al cliente que todo jugador era espectador.
-- Apagar UN sitio son cinco bytes, es local, y los otros diecisiete siguen
-- contestando la verdad.
--
-- Con los dos flags puestos el heroe SI desaparece -- medido, no supuesto -- o
-- sea que el mecanismo esta vivo delante de nosotros y se puede acorralar:
--
--   sites all  -> ¿vuelves?  no -> el predicado NO es el mecanismo y se busca
--                            un test de los dos bits escrito a mano en otro
--                            sitio. si -> esta entre los dieciocho, y se parte
--                            por la mitad.
--   site <n>   -> el que te devuelva es EL llamante.
--
-- El codigo viaja en los bits 7+ del mismo CVar. Un solo canal: con dos, una
-- prueba puede quedarse a medias con uno puesto y el otro no, y nada lo dice.
function B:Sites(code)
	local v = SetSite(Get(), code)
	Set(v)

	-- SIN LOS FLAGS PUESTOS ESTA PRUEBA NO MIDE NADA, Y LO PEOR ES QUE SALE
	-- BIEN. El predicado contesta `false` en todas partes cuando no estan los
	-- dos bits, asi que eres visible igual y CUALQUIER sitio parece devolverte
	-- el modelo: dieciocho falsos positivos seguidos, todos convincentes.
	--
	-- Paso el 2026-09-09: un `reset` entre medias dejo los flags neutros y la
	-- vuelta entera de sitios 11..18 se corrio sobre un heroe que nunca estuvo
	-- escondido. El comando obedecia y no medía nada, que es la peor forma de
	-- fallar. Ahora lo dice.
	if code ~= 0 and not Has(v, FLAGS_ON) then
		ns.Print("|cffff0000body: LOS FLAGS NO ESTAN PUESTOS.|r Sin ellos eres " ..
		         "visible de todas formas y esto no mide nada.")
		ns.Print("  |cffffff00/rts body flags on|r primero, y luego los sitios: " ..
		         "el codigo de sitio no toca los flags, asi que se ponen UNA vez.")
		return
	end
	if code == 0 then
		ns.Print("body: los dieciocho sitios de llamada devueltos.")
	elseif code == SITES_ALL then
		ns.Print("|cffff8000body:|r los DIECIOCHO apagados. Con los flags puestos, " ..
		         "¿vuelve tu modelo?")
		ns.Print("  |cff00ff00si|r -> el escondite esta entre ellos y lo partimos por la mitad.")
		ns.Print("  |cffff0000no|r -> el predicado no es el mecanismo. Otra cosa lee los dos bits.")
	else
		ns.Print(("|cffff8000body:|r apagado SOLO el sitio |cffffff00%d|r de 18. " ..
		          "¿vuelve tu modelo?"):format(code - 1))
	end
	ns.Print("  el log dice la direccion exacta que se toco.")
end

-- EL ARREGLO SE ARMA SOLO, ASI QUE ESTO ES PARA DESARMARLO.
--
-- El DLL apaga 0x006E085C en cuanto el jugador LLEVA los dos flags, los haya
-- puesto la sonda o el servidor. Este interruptor existe para poder volver a
-- ver el fallo: una cura sin forma de apagarla no se puede volver a medir el
-- dia que el sintoma cambie de sitio, y entonces lo unico que queda es
-- recompilar a ciegas.
function B:NoFix(on)
	Set(Bit(Get(), NO_FIX, on and true or false))
	ns.Print(on and "|cffff8000body:|r arreglo DESARMADO -- vuelves a ser invisible con los flags."
	             or "|cff00ff00body:|r arreglo armado (es lo normal).")
end

-- EL PARPADEO, Y ARRANCA APAGADO PORQUE ES UN CANDIDATO.
--
-- Con los flags puestos, el resalte del raton y el circulo de destino parpadean
-- a la vez, y el circulo alterna entre dos posiciones. 0x0073DAB0 tiene esa
-- forma exacta: un conmutador de 500 ms detras del OTRO predicado
-- (0x00729740), con su `sete` y su `sub edx, 0x1f4`.
--
-- El ritmo cuadra y el mecanismo cuadra, y eso no es lo mismo que ser la causa.
-- Por eso es un interruptor y no un arreglo: se apaga, se mira, y el juego
-- contesta. Si no era, se descarta en diez segundos en vez de en una ronda.
function B:Blink(on)
	Set(Bit(Get(), BLINK_OFF, on and true or false))
	if on then
		ns.Print("|cffff8000body:|r parpadeo apagado (0x0073DB42). " ..
		         "¿Sigue vibrando el circulo de destino?")
		ns.Print("  |cff00ff00no|r -> era eso. |cffff0000si|r -> es otro sitio y se busca igual.")
	else
		ns.Print("body: parpadeo devuelto a como estaba.")
	end
end

-- LA ESPADA: DEVOLVER "PUEDO ATACAR".
--
-- `PLAYER_FLAGS_UBER` -- el bit 19, el que la camara libre NO puede no poner --
-- corta en seco el predicado 0x00729740, que es el de `UnitCanAttack`. Con la
-- camara puesta `UnitCanAttack("player", loquesea)` es falso, asi que el
-- cliente no dibuja la espada al pasar por encima de un bicho y el boton
-- derecho no ataca. El icono de mision y la bolsa de botin salen porque van por
-- otro predicado, y esa asimetria es justo la firma del bit 19.
--
-- El arreglo es un byte en el veredicto (`je` -> `jmp`), y esta descrito entero
-- en `rts-client-mod/src/Offsets.h`. Aqui solo esta el interruptor.
--
-- ARRANCA APAGADO. Es un parche de bytes sobre el cliente y todavia no se ha
-- visto funcionar en juego: esa es la regla, y las dos veces que se incumplio
-- el primer contacto del jugador con la ronda fue un fallo nuevo puesto encima
-- de lo que venia a arreglar.
function B:Attack(on)
	Set(Bit(Get(), ACT_FIX, on and true or false))
	if on then
		ns.Print("|cff00ff00body:|r veredicto del bit 19 anulado (0x00729762).")
		ns.Print("  Pasa el raton por encima de un bicho: |cffffff00¿sale la espada?|r")
		ns.Print("  |cff00ff00si|r -> era eso y el arreglo pasa a armarse solo.")
		ns.Print("  |cffff0000no|r -> no es el unico sitio; el predicado tiene 37 llamantes.")
	else
		ns.Print("body: veredicto del bit 19 devuelto (sin espada, como hasta hoy).")
	end
end

function B:FlagsAuto()
	-- Ni poner ni borrar: dejar los flags como esten. Es el estado neutro, y
	-- hace falta para probar la cura de la ventana sin que la sonda pelee.
	local v = Get()
	v = Bit(v, FLAGS_ON, false)
	v = Bit(v, FLAGS_OFF, false)
	v = Bit(v, UBER_ONLY, false)
	v = Bit(v, COMM_ONLY, false)
	Set(v)
end

function B:Skip(on)
	Set(Bit(Get(), SKIP, on and true or false))
end

function B:Log(on)
	Set(Bit(Get(), REPORT, on and true or false))
end

-- El diagnostico de "que se lo trague todo". Fuerza el salto para TODAS las
-- unidades, y lo que se mira son LOS BOTS, no el heroe:
--
--   desaparecen  -> 0x0073A890 es la emision del modelo y el salto es su
--                   puerta. Entonces al heroe lo esconde algo MAS, ademas.
--   no pasa nada -> esa funcion no dibuja el modelo y la lectura estatica
--                   entera esta mal. Se empieza en otro sitio.
--
-- Anular el salto no basta para ver al heroe (probado en juego), y desde el
-- heroe esas dos explicaciones se ven igual. Esto las separa.
function B:Invert(on)
	Set(Bit(Get(), INVERT, on and true or false))
	if on then
		ns.Print("|cffff8000body:|r mira a los BOTS, no a ti. ¿Desaparecen sus modelos?")
	end
end

-- APAGAR NO ES DEJAR DE PEDIR, Y ESE FUE EL FALLO DE LA PRIMERA VERSION.
-- El modo 0 significa "no toques los flags", asi que `reset` los dejaba
-- PUESTOS: el cliente seguia creyendose espectador -- camara despegada
-- incluida -- y el unico deshacer real era `flags off` o relogear. Y encima el
-- paso 3 de la ayuda decia que reset lo dejaba todo como estaba.
--
-- Ahora reset PIDE BORRAR y solo despues se queda neutro, dandole al DLL
-- tiempo de sobra para su tick (33 Hz). Es la misma forma que la regla dura de
-- capturar y devolver: el deshacer tiene que deshacer, no dejar de insistir.
local clearUntil

-- APARCAR LA CAMARA SOBRE TU CUERPO, Y ESTO NO ES UNA COMODIDAD: SIN ESTO LA
-- SONDA NO SE PUEDE CONTESTAR.
--
-- Con los flags puestos el cliente se cree espectador y la camara se va a la
-- posicion del estado de comentarista, que nadie ha escrito nunca -- o sea
-- ~(0,0,0). Medido en juego: camara en (35, -15, 32) con el heroe en
-- (10326, 830, 1326), 10.300 yardas. Volar hasta alli no es una opcion, asi
-- que la pregunta "¿ha desaparecido mi modelo?" era literalmente imposible de
-- mirar. La sonda podia decir que si y que no sin que nadie lo viera.
--
-- Los flags que la sonda pone son justamente los que ABREN la puerta de
-- `CommentatorSetCamera`, asi que colocarla es Lua corriente: ni recompilar el
-- DLL ni reinyectar.
--
-- Se pone ENCIMA mirando hacia abajo a proposito. El yaw de esa funcion tiene
-- una convencion que no se puede leer del binario (`docs/CAMARA-LIBRE.md` §6),
-- asi que se conserva el que haya y no se depende de el: desde arriba tu
-- cuerpo sale en medio de la pantalla apunte el yaw donde apunte. `pitch`
-- POSITIVO mira hacia abajo -- con negativo apunta al cielo.
local HEIGHT = 12.0
local PITCH  = 70.0
local FOV    = 70.0     -- el rango legal es 1..120; un 0 se recorta a ~1 y
                        -- deja la pantalla morada

local function Park(quiet)
	if type(CommentatorSetCamera) ~= "function" then
		ns.Print("|cffff0000body:|r este cliente no tiene CommentatorSetCamera.")
		return false
	end
	if RTS_HasPos ~= 1 or not RTS_PX then
		if not quiet then
			ns.Print("|cffff0000body:|r el DLL no publica tu posicion todavia.")
		end
		return false
	end

	-- LA PUERTA SE COMPRUEBA, NO SE SUPONE, Y ESTE ERA EL FALLO.
	--
	-- `pcall(CommentatorSetCamera, ...)` devuelve true TAMBIEN CON LA PUERTA
	-- CERRADA: la funcion existe, se la llama, mira los flags, no hace nada y
	-- vuelve sin error. O sea que el primer intento -- el del frame siguiente a
	-- escribir el CVar, cuando el DLL todavia no ha puesto los flags en su tick
	-- de 33 Hz -- decia "aparcada" y APAGABA LOS REINTENTOS. La camara se
	-- quedaba donde el cliente la deja al creerse espectador y la sonda seguia
	-- sin poder mirarse. Otro lector que miente en la direccion tranquilizadora.
	--
	-- El test bueno lo da `CommentatorGetCamera`: devuelve los seis numeros con
	-- la puerta abierta y NADA con la puerta cerrada. Y de paso trae el yaw
	-- vivo, que es el que se conserva.
	local ok, cx, _, _, y = pcall(CommentatorGetCamera)
	if not ok or type(cx) ~= "number" or type(y) ~= "number" then
		if not quiet then
			ns.Print("|cffff0000body:|r la puerta sigue cerrada " ..
			         "(CommentatorGetCamera no contesta). ¿Estan puestos los flags?")
		end
		return false
	end

	local tx, ty, tz = RTS_PX, RTS_PY, RTS_PZ + HEIGHT
	local ok2 = pcall(CommentatorSetCamera, tx, ty, tz, y, PITCH, FOV)
	if not ok2 then
		if not quiet then
			ns.Print("|cffff0000body:|r CommentatorSetCamera fallo.")
		end
		return false
	end

	-- Y LA PRUEBA DE QUE SE MOVIO NO ES LO QUE DEVUELVE GetCamera -- eso lee los
	-- globales del estado de comentarista, o sea LO QUE LE ACABAS DE PEDIR
	-- (`CAMARA-LIBRE.md` §11). El testigo honesto es `RTS_Cam*`, que el DLL saca
	-- de la camara activa por su cuenta y llega un tick mas tarde. Se comprueba
	-- sola y CANTA LA DISTANCIA, que es lo que convierte "aparezco en otro
	-- sitio" en un numero.
	checkAt = GetTime() + 0.4
	checkX, checkY, checkZ = tx, ty, tz

	ns.Print(("body: pedida camara en (%.0f, %.0f, %.0f). Comprobando..."):format(tx, ty, tz))
	return true
end

function B:Look()
	-- Reintenta igual que `flags on`: si la puerta esta cerrada porque acabas de
	-- escribir el CVar, un solo intento se pierde por 30 ms.
	parkTries = 0
	if Park(false) then return end
	parkTries = 8
	parkNext = GetTime() + 0.25
end

function B:Off()
	if not Ensure() then return end
	SetCVar(CVAR, tostring(FLAGS_OFF))
	clearUntil = GetTime() + 1.5
	ns.Print("body: borrando los flags... (neutro en 1,5 s)")
end

function B:Help()
	ns.Print("|cffffff00Sonda del cuerpo|r -- por que el heroe desaparece con la camara libre.")
	ns.Print("  |cff00ff00/rts body|r                 estado")
	ns.Print("  |cff00ff00/rts body flags on|off|r    escribe o borra los dos flags cada tick")
	ns.Print("  |cff00ff00/rts body flags auto|r      no los toca (estado neutro)")
	ns.Print("  |cff00ff00/rts body flags uber|r      SOLO el bit 19, sin camara")
	ns.Print("  |cff00ff00/rts body flags comm|r      SOLO el bit 22, sin camara")
	ns.Print("  |cff00ff00/rts body skip on|off|r     anula el salto que se salta tu modelo")
	ns.Print("  |cff00ff00/rts body look|r           aparca la camara sobre tu cuerpo")
	ns.Print("  |cff00ff00/rts body log on|off|r      una linea por segundo a rts_core.log")
	ns.Print("  |cff00ff00/rts body blink on|off|r    apaga el parpadeo (candidato)")
	ns.Print("  |cff00ff00/rts body attack on|off|r   devuelve la espada y el click derecho")
	ns.Print("  |cff00ff00/rts body nofix on|off|r    desarma el arreglo, para ver el fallo")
	ns.Print("  |cff00ff00/rts body sites all|off|r   apaga los 18 llamantes del predicado")
	ns.Print("  |cff00ff00/rts body site 0..17|r     apaga SOLO ese llamante")
	ns.Print("  |cff00ff00/rts body reset|r           todo apagado")
	ns.Print(" ")
	ns.Print("Secuencia de la prueba, en este orden:")
	ns.Print("  1. |cffffff00/rts body log on|r  y luego |cffffff00flags on|r")
	ns.Print("     -> se espera que TU MODELO DESAPAREZCA. Si no, los flags no")
	ns.Print("        son la causa y todo lo demas de esta sonda sobra.")
	ns.Print("  2. |cffffff00/rts body skip on|r  (con los flags todavia puestos)")
	ns.Print("     -> si REAPARECES, la cura son dos bytes y esta encontrada.")
	ns.Print("  3. |cffffff00/rts body reset|r  para dejarlo todo como estaba.")
	ns.Print(" ")
	ns.Print("|cffff8000Con los flags puestos la CAMARA SE DESPEGA|r y se puede mover:")
	ns.Print("  el cliente entero se cree espectador, no solo el trozo que dibuja")
	ns.Print("  tu modelo. Es esperado. |cffffff00reset|r lo devuelve, y un relogueo")
	ns.Print("  tambien -- los flags viven solo en la memoria del cliente.")
end

-- UN `/reload` NO LIMPIA LA MEMORIA DEL CLIENTE, asi que los flags sobreviven
-- a la recarga de la interfaz -- solo un logout los devuelve, porque entonces
-- el campo lo vuelve a mandar el servidor. Por eso al cargar se PIDE BORRAR y
-- no se pone neutro: neutro sobre unos flags pegados de la sesion anterior es
-- exactamente el `camHold` del 2026-08-23, un instrumento que se rearma solo.
--
-- Que la sonda arranque apagada sigue siendo la regla; lo que cambia es que
-- "apagada" ahora significa borrando, no callada.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
	if not Ensure() then return end
	SetCVar(CVAR, tostring(FLAGS_OFF))
	clearUntil = GetTime() + 1.5
end)

f:SetScript("OnUpdate", function()
	if clearUntil and GetTime() >= clearUntil then
		clearUntil = nil
		if GetCVar(CVAR) ~= nil then SetCVar(CVAR, "0") end
	end

	if parkTries > 0 and GetTime() >= parkNext then
		parkNext = GetTime() + 0.25
		parkTries = parkTries - 1
		if Park(parkTries > 0) then parkTries = 0 end
	end

	if checkAt and GetTime() >= checkAt then
		checkAt = nil
		if RTS_HasCam ~= 1 or not RTS_CamX then
			ns.Print("|cffff0000body:|r el DLL no lee la camara, " ..
			         "no puedo comprobar donde acabo. Mira rts_core.log.")
		else
			local dx = RTS_CamX - checkX
			local dy = RTS_CamY - checkY
			local dz = RTS_CamZ - checkZ
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d < 5 then
				ns.Print(("|cff00ff00body: camara aparcada sobre tu cuerpo|r " ..
				          "(%.1f yardas de lo pedido)."):format(d))
			else
				ns.Print(("|cffff0000body: LA CAMARA NO ESTA DONDE SE PIDIO|r -- " ..
				          "%.0f yardas de diferencia."):format(d))
				ns.Print(("  pedida (%.0f, %.0f, %.0f)  real (%.0f, %.0f, %.0f)"):format(
					checkX, checkY, checkZ, RTS_CamX, RTS_CamY, RTS_CamZ))
				ns.Print("  |cffffff00/rts body look|r vuelve a intentarlo.")
			end
		end
	end
end)
