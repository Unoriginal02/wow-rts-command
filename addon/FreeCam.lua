--[[
	FreeCam.lua -- el controlador de la camara RTS.

	Sustituye a la criatura poseida. Las cuatro capas que pedia el brief, en el
	orden en que corren una vez por frame:

	    INPUT     teclas -> intenciones           (botones propios, por flanco)
	    SOLVER    intenciones -> objetivo         (plano horizontal + suelo)
	    SMOOTHING objetivo -> posicion actual     (exponencial por dt)
	    APPLY     una sola escritura              (ns.Camera:SpecPlace)

	=== POR QUE ESTO PUEDE EXISTIR AHORA Y NO ANTES ==========================

	La camara de siempre era una criatura del servidor que el jugador POSEE, asi
	que el cliente era dueño de su posicion y desde el servidor solo se la podia
	mover con `NearTeleportTo` -- que CANCELA el movimiento que el cliente esta
	aplicando. Todo lo que este fichero hace estaba bloqueado por ese hecho:

	  * avanzar y subir a la vez era imposible (cada teleport corta el avance),
	  * la altura sobre el terreno se construyo por los DOS caminos posibles y
	    se borro el 2026-08-23, porque el del servidor es un ascensor y el del
	    cliente (hover) necesita la gravedad encendida, que es justo lo que hace
	    que la camara se quede donde se la pone,
	  * y el suavizado por dt no tenia sentido: no eramos dueños de la
	    transformada, asi que no habia nada que interpolar.

	Con `CommentatorSetCamera` la transformada es NUESTRA -- seis valores, una
	llamada, y se queda puesta (medido en juego: deriva 0.00). Asi que las tres
	dejan de ser problemas de mecanismo y pasan a ser aritmetica.

	=== ADELANTE ES PLANO, NUNCA EL VECTOR DE VISTA =========================

	Es el requisito explicito y es tambien la leccion de la etapa 5f, donde
	`SetCanFly(true)` era la razon de que la camara "volara": en modo vuelo el
	cliente mueve la unidad a lo largo de su VISTA, asi que mirando al suelo y
	pulsando W desciendes.

	Aqui adelante sale del vector de avance de la camara PROYECTADO en el plano
	horizontal y renormalizado, asi que la inclinacion solo cambia lo que VES.
	W/S mueven en el plano que define la altura, que es lo que se pidio.

	Y ese vector se le pide al DLL (`RTS_CamFwdX/Y`) en vez de derivarlo de
	nuestro yaw, lo que evita de golpe la pregunta de cual es la convencion de
	angulos de `CommentatorSetCamera` -- que no se puede leer del binario. El
	yaw solo se usa para GIRAR; la direccion de avance nunca depende de el.

	=== LA ALTURA SE MIDE CONTRA EL SUELO DE DONDE ESTA LA CAMARA ============

	`targetZ = suelo + offset`, con el suelo de `RTS_CamGroundZ` -- un rayo
	vertical que el DLL lanza bajo la camara cada tick. El unico suelo que se
	publicaba antes estaba bajo el JUGADOR, y no sirve: en una camara RTS la
	camara pasa la mayor parte del tiempo donde el personaje no esta, que es
	justamente cuando hace falta.

	ESPACIO y C no mueven la Z: mueven el OFFSET. Por eso se puede avanzar y
	subir a la vez sin que ninguna de las dos cosas corte a la otra -- las dos
	son entradas del mismo solver y se integran en el mismo frame, que es lo que
	el brief pedia en su §7.

	=== "EL SUELO" NO ES "LO PRIMERO QUE HAY DEBAJO" (2026-09-10) ============

	Las dos cosas se dicen igual y solo son la misma en campo abierto. En
	cuanto hay algo construido, lo primero que hay debajo de la camara al
	acercarse a una casa es el TEJADO -- asi que la altura se corregia contra el
	tejado, la camara subia sola y entrar era imposible. Un cartel de madera
	hacia lo mismo en pequeno: un salto de seis yardas y vuelta.

	El DLL publica desde 0.25.0 las DOS alturas -- `RTS_CamGroundZ` (todo) y
	`RTS_CamLandZ` (solo terreno, otra mascara de banderas del mismo rayo del
	cliente) -- y `floor` elige. Con `floor = 1` un tejado deja de ser suelo:
	la camara pasa por encima sin inmutarse y puede bajar hasta DENTRO de la
	casa, donde el cliente ademas dibuja el interior y recorta el exterior el
	solo, que es la version buena del corte que se descarto esta misma manana.

	=== Y UN ESCALON NO ES UNA CUESTA ======================================

	Aunque no haya tejados, el terreno tambien tiene bordes. Un suavizado sobre
	el error de la camara no puede distinguirlos, porque seis yardas de error
	son las mismas en los dos casos. Lo que si los distingue es CUANTO CORRE EL
	SUELO: una cuesta a toda velocidad son ~20 yd/s, el borde de un escalon son
	seis yardas EN UN FRAME -- cientos.

	Asi que hay un filtro DELANTE del suavizado, sobre la senal de suelo, con la
	velocidad limitada y el limite bajando con el tamano del escalon pendiente
	(`climb`, `soft`, `slow`). Una cuesta se sigue de cerca; un escalon apenas
	se empieza, y si te quedas encima acabas subiendo. Cuanto mas alto el
	escalon, mas despacio -- que es exactamente al reves de lo que hace un
	suavizado normal, y es lo que se pidio.

	=== SIN DLL ESTO NO ARRANCA, Y LO DICE ==================================

	Necesita dos cosas que solo el DLL da: el vector de avance y el suelo bajo
	la camara. Sin `rts_core` inyectado no hay ninguna de las dos, asi que el
	controlador se niega a arrancar en vez de dibujar una camara que se va a
	quedar clavada -- un modo degradado que no se anuncia es peor que uno que
	falla.
]]

local ADDON, ns = ...

local F = {}
ns.FreeCam = F

F.active = false

--- Ajustes -----------------------------------------------------------------
--
-- Todos por personaje, porque son de tacto: la velocidad buena depende de la
-- resolucion y de la costumbre, igual que la sensibilidad del raton.
local D = {
	speed   = 30.0,   -- yardas/segundo en el plano
	lift    = 14.0,   -- yardas/segundo de offset con ESPACIO y C
	turn    = 90.0,   -- grados/segundo con Q y E
	height  = 30.0,   -- offset inicial sobre el suelo
	minH    = 4.0,    -- suelo del offset
	maxH    = 300.0,  -- techo del offset
	smoothZ = 8.0,    -- k del suavizado de altura (1/s); mas alto, mas seco
	-- === EL SUELO NO ES LO PRIMERO QUE HAY DEBAJO ========================
	--
	-- `floor = 1` mide contra el TERRENO y nada mas: un tejado, un cartel o la
	-- copa de un arbol dejan de contar como suelo, asi que la camara ni sube
	-- sola al acercarse a una casa ni se queda fuera. `floor = 0` es lo de
	-- antes -- lo primero que choque -- y sirve para sobrevolar un pueblo sin
	-- meterse en ningun sitio.
	floor   = 1,      -- 1 = solo terreno, 0 = lo primero que haya debajo
	-- === Y LA CAMARA NO CHOCA CON NADA ===================================
	--
	-- La camara de comentarista SI colisiona de serie, y con las mismas
	-- banderas que el rayo de suelo -- terreno, edificios y doodads. Es la
	-- segunda mitad de "no puedo entrar en la casa": una la subia al tejado y
	-- la otra la empujaba fuera de la pared.
	--
	-- Con `noclip = 1` se apaga ese rayo al entrar y se vuelve a encender al
	-- salir, asi que lo unico que detiene a la camara es NUESTRO suelo. Todo lo
	-- que hace falta para leer eso en el binario esta en `Camera:SetCollision`.
	noclip  = 1,      -- 1 = atraviesa todo; 0 = colision del cliente, como antes
	-- === Y EL ESCALON SE PERSIGUE DESPACIO, LA CUESTA NO =================
	--
	-- Estas tres son el filtro que separa una cuesta de un salto. La velocidad
	-- con la que el suelo medido persigue al de verdad es
	--
	--     v = climb / (1 + (pendiente/soft)^2),  nunca menos de `slow`
	--
	-- o sea que cuanto MAS grande es el escalon que queda por subir, MAS
	-- despacio se sube -- que es justo al reves de lo que hace un suavizado
	-- normal, y es lo que pedia el jugador: pasar por encima de un cartel no
	-- se nota, y si de verdad quieres subirte a el, esperas.
	climb   = 60.0,   -- yd/s cuando la diferencia es minima (una cuesta)
	soft    = 2.5,    -- yardas; el codo. Mas pequeno, mas quisquilloso
	slow    = 6.0,    -- yd/s; el suelo de esa velocidad (si no, un acantilado
	                  -- de verdad no se subiria nunca)
	-- POSITIVO MIRA HACIA ABAJO, y lo dice el juego, no yo.
	--
	-- Lo puse a -45 razonando "abajo es negativo" y sale al contrario: con -45
	-- la camara apunta al CIELO. Es la convencion de `CommentatorSetCamera`, que
	-- no se puede leer del binario -- el desensamblado solo ensena que el
	-- argumento se multiplica por DEG2RAD y se guarda.
	--
	-- Otra constante de signo adivinada, que es el error que este proyecto lleva
	-- pagando desde los dos signos de `SetPosition` del retrato. Ahi la salida
	-- fue una tabla de siete encuadres para probarlos; aqui basta con haberlo
	-- visto una vez.
	pitch   = 45.0,   -- grados; POSITIVO mira abajo (medido en juego 2026-09-07)
	clear   = 2.0,    -- margen duro sobre el suelo
	-- === Y EL SUELO DURO TAMBIEN TIENE VELOCIDAD (2026-09-12) =============
	--
	-- Sin esto el suelo duro era un `st.z = ground + clear` a pelo: un salto de
	-- OCHENTA yardas en UN frame. Era el unico camino del fichero capaz de
	-- teletransportar la camara, y es el "plop" al cruzar la boca de una cueva.
	--
	-- Y el filtro de escalon de arriba no lo impedia, AL CONTRARIO -- ver el
	-- comentario del tope de retraso. Los dos se saltaban el limitador a la vez
	-- y por el mismo motivo: los dos leen `ground` EN CRUDO.
	--
	-- 40 yd/s es holgado para terreno de verdad: la camara avanza a `speed`
	-- (30), asi que una ladera de 45 grados mueve el suelo 30 yd/s y una de 53
	-- grados 40. Mas empinado que eso es un acantilado, y ahi que la camara se
	-- meta un instante en la roca y salga por arriba es preferible al salto.
	push    = 40.0,   -- yd/s; lo mas deprisa que el suelo duro puede EMPUJAR
	yawSign = 1,      -- si Q y E salen al reves, esto es -1
	ease    = 9.0,    -- k del arranque/parada en el plano (1/s); mas alto, mas seco
}

-- SELLO DE GENERACION, y hace falta porque un ajuste CAMBIO DE SIGNIFICADO.
--
-- La generacion 1 guardaba `pitch = -45` creyendo que negativo miraba abajo. En
-- este cliente es al contrario. Y `-45` sigue estando dentro del rango valido,
-- asi que el acotado de `Cfg()` lo dejaba pasar tal cual: cambiar el valor por
-- defecto a +45 no hizo absolutamente nada en un cliente que ya lo tenia
-- guardado, y la camara siguio mirando al cielo.
--
-- COMPARAR EL RANGO NO BASTA CUANDO LO QUE SE MUEVE ES LO QUE EL NUMERO QUIERE
-- DECIR. Es el caso exacto del `railCropGen` de la etapa 5o -- un indice valido
-- cuyo significado cambio -- y la unica salida coherente es no fiarse de nada
-- de lo guardado: se tira la tabla entera y se dice.
-- GEN 3: el giro con el raton pasa a ser NATIVO, asi que `lookSens` y `lookInv`
-- dejan de existir -- los tenia el addon y ahora los lleva el cliente con tus
-- propios ajustes de raton. Un ajuste que ya no se lee es un mando que gira sin
-- conectar a nada.
local GEN = 3

local function Cfg()
	RTSCommandDB.freeCam = RTSCommandDB.freeCam or {}
	local c = RTSCommandDB.freeCam
	if c.gen ~= GEN then
		-- Se tira TODO y no solo `pitch`. Una generacion significa "lo guardado
		-- ya no quiere decir lo mismo", asi que salvar las claves que "parecen
		-- bien" es volver a decidir a mano lo que la generacion existe para no
		-- tener que decidir. El precio -- perder los ajustes que el jugador si
		-- habia tocado -- se paga diciendolo, que es lo que separa una purga de
		-- una perdida.
		if c.gen ~= nil or c.pitch ~= nil then
			ns.Print("|cffffd100camara RTS:|r ajustes reiniciados (el signo de la " ..
				"inclinacion cambio de significado).")
		end
		RTSCommandDB.freeCam = { gen = GEN }
		c = RTSCommandDB.freeCam
	end
	for k, v in pairs(D) do
		if type(c[k]) ~= "number" then c[k] = v end
	end
	-- LO GUARDADO SE ACOTA AL LEERLO, no solo al escribirlo. Las
	-- SavedVariables sobreviven a la version que las escribio, asi que un
	-- ajuste de una version anterior puede estar fuera de rango y los `Set*`
	-- solo corren cuando el jugador teclea. Misma leccion que el `grow = 688`.
	if c.speed  <= 0 or c.speed  > 300 then c.speed  = D.speed  end
	if c.lift   <= 0 or c.lift   > 200 then c.lift   = D.lift   end
	if c.turn   <= 0 or c.turn   > 720 then c.turn   = D.turn   end
	if c.minH   <  0 or c.minH   > 100 then c.minH   = D.minH   end
	if c.maxH   <= c.minH               then c.maxH   = D.maxH   end
	if c.height < c.minH or c.height > c.maxH then c.height = D.height end
	if c.smoothZ <= 0 or c.smoothZ > 60 then c.smoothZ = D.smoothZ end
	-- `floor` es una eleccion, no una magnitud: cualquier otra cosa es basura y
	-- vuelve al de fabrica en vez de recortarse. Y se compara con 0/1 y no con
	-- `~= 1`, porque un `nil` de una version anterior ya lo ha resuelto el
	-- bucle de arriba y lo que queda aqui es un numero cualquiera.
	if c.floor ~= 0 and c.floor ~= 1 then c.floor = D.floor end
	if c.noclip ~= 0 and c.noclip ~= 1 then c.noclip = D.noclip end
	if c.climb <= 0 or c.climb > 500 then c.climb = D.climb end
	if c.soft  <= 0 or c.soft  > 100 then c.soft  = D.soft  end
	if c.slow  <  0 or c.slow  > 200 then c.slow  = D.slow  end
	-- A cero el suelo duro deja de empujar y la camara se queda enterrada sin
	-- forma de salir, que es peor que el fallo que esto viene a arreglar. Un
	-- valor absurdo es basura y vuelve al de fabrica, no se recorta.
	if c.push  <= 0 or c.push  > 1000 then c.push  = D.push  end
	-- El suelo de la velocidad por encima del techo dejaria el codo sin efecto
	-- y el ajuste `soft` sin nada que hacer -- un mando que gira sin conectar.
	-- Se baja el SUELO y no se sube el techo: bajar `climb` es una intencion
	-- clara ("que todo vaya despacio") y subirsela por detras seria desobedecer.
	if c.slow > c.climb then c.slow = c.climb end
	if c.pitch < -89 or c.pitch > 89    then c.pitch  = D.pitch  end
	if c.clear < 0 or c.clear > 50      then c.clear  = D.clear  end
	if c.yawSign ~= 1 and c.yawSign ~= -1 then c.yawSign = 1 end
	if c.ease <= 0 or c.ease > 60 then c.ease = D.ease end
	return c
end

--- INPUT -------------------------------------------------------------------
--
-- Ocho teclas, con los DOS flancos. Registrar solo la bajada da un evento por
-- pulsacion y ninguna forma de saber que se solto, que es justo lo que un
-- control de mantener-para-mover necesita -- es la misma razon y el mismo
-- mecanismo que ya usaban ESPACIO y C para la camara vieja.
--
-- NO son botones seguros a proposito: nada de lo que hacen esta protegido.

local input = { fwd = false, back = false, left = false, right = false,
                up = false, down = false, yawL = false, yawR = false }

local KEYS = {
	{ key = "W",     field = "fwd"   },
	{ key = "S",     field = "back"  },
	{ key = "A",     field = "left"  },
	{ key = "D",     field = "right" },
	{ key = "SPACE", field = "up"    },
	{ key = "C",     field = "down"  },
	{ key = "Q",     field = "yawL"  },
	{ key = "E",     field = "yawR"  },
}

local buttons = {}
local savedBindings = nil

local function MakeButtons()
	if buttons.fwd then return end
	for _, k in ipairs(KEYS) do
		local name = "RTSFreeCam" .. k.field
		local b = _G[name] or CreateFrame("Button", name, UIParent)
		b:Hide()
		b:RegisterForClicks("AnyDown", "AnyUp")
		local field = k.field
		b:SetScript("OnClick", function(_, _, down)
			input[field] = (down == true)
		end)
		buttons[k.field] = b
	end
end

-- LAS TECLAS SE APUNTAN ANTES DE TOCARLAS Y VUELVEN AL SALIR, que es la regla
-- dura de este proyecto. Las ocho estan ocupadas de fabrica -- WASD es el
-- movimiento, ESPACIO salta, C abre la ficha, Q/E son strafe -- asi que
-- devolverlas no es cortesia: sin eso el jugador se queda sin moverse en juego
-- normal despues de haber entrado una vez en modo RTS.
--
-- `SaveBindings` NO se llama nunca: se restauran en la salida y no se guardan,
-- asi que una recarga, una desconexion o un cierre inesperado dejan intactas
-- las teclas de verdad del jugador.
local function GrabKeys()
	if InCombatLockdown() then
		ns.Print("|cffff8800camara:|r las teclas no se pueden coger en combate.")
		return false
	end
	MakeButtons()
	savedBindings = {}
	for _, k in ipairs(KEYS) do
		savedBindings[k.key] = GetBindingAction(k.key) or ""
		SetBindingClick(k.key, buttons[k.field]:GetName())
	end
	return true
end

local function ReleaseKeys()
	if not savedBindings then return true end
	if InCombatLockdown() then return false end
	for key, action in pairs(savedBindings) do
		if action ~= "" then
			SetBinding(key, action)
		else
			SetBinding(key, nil)
		end
	end
	savedBindings = nil
	for k in pairs(input) do input[k] = false end
	return true
end

--- SOLVER + SMOOTHING ------------------------------------------------------

-- EL PITCH ES ESTADO, NO SOLO AJUSTE: el raton lo cambia (ver `AdoptLook`), asi
-- que el valor de `Cfg().pitch` es solo con lo que se ENTRA.
local st = { x = nil, y = nil, z = nil, yaw = 0, pitch = nil, offset = nil,
             vx = 0, vy = 0,
             -- `gz` es el suelo FILTRADO: el que la camara cree que tiene
             -- debajo, que persigue al medido con una velocidad limitada. Es
             -- estado y no una variable local del tick a proposito -- sin
             -- memoria entre frames no hay filtro, solo un rebautizo del suelo.
             gz = nil, gstep = 0 }

-- Ninguna de las funciones de comentarista se habia llamado nunca en este
-- proyecto, asi que todas pasan por aqui: si una no existe, el controlador
-- sigue funcionando en vez de reventar en cada frame.
-- El avance plano y el suelo, las dos lecturas del DLL en las que se apoya todo
-- lo demas. Van JUNTO A `st` y no cerca del giro a proposito: las he borrado
-- por accidente DOS VECES al reescribir el bloque del raton, porque estaban
-- dentro del rango que sustituia. Aqui no hay nada que reescribir.
local function FlatForward()
	if RTS_HasCam ~= 1 then return nil end
	local fx, fy = RTS_CamFwdX, RTS_CamFwdY
	if not fx or not fy then return nil end
	local len = math.sqrt(fx * fx + fy * fy)
	-- Mirando a plomo hacia abajo la proyeccion es casi cero y la direccion deja
	-- de estar definida. No se normaliza una longitud minuscula: no hay
	-- adelante, y ese frame no se avanza -- preferible a salir disparado en una
	-- direccion aleatoria.
	if len < 0.001 then return nil end
	return fx / len, fy / len
end

-- EL SUELO, Y DE CUAL DE LOS DOS RAYOS SALE.
--
-- El DLL publica dos alturas bajo la camara y la diferencia entre ellas es
-- todo el problema del tejado:
--
--   `RTS_CamGroundZ` -- lo PRIMERO que hay debajo. Un tejado, un cartel, la
--                       copa de un arbol. Es la que habia, y es la buena para
--                       sobrevolar un sitio sin meterse en nada.
--   `RTS_CamLandZ`   -- solo el TERRENO. Lo construido deja de ser suelo, asi
--                       que ni un tejado levanta la camara ni le impide bajar
--                       hasta dentro de la casa.
--
-- Devuelve tambien de donde ha salido, porque "la camara sube sola" y "la
-- camara no baja" son el mismo sintoma con las dos fuentes cambiadas, y
-- distinguirlo mirando la pantalla cuesta una ronda.
local function GroundUnderCamera(c)
	local land  = (RTS_CamLandHit  == 1) and RTS_CamLandZ  or nil
	local solid = (RTS_CamGroundHit == 1) and RTS_CamGroundZ or nil
	if c.floor == 1 then
		if land then return land, "terreno" end
		-- CAER AL SOLIDO NO ES DEGRADARSE AQUI, ES ACERTAR. Dentro de una cueva
		-- el ADT esta agujereado a proposito y el rayo de terreno NO CONTESTA:
		-- el suelo bueno de ese sitio es justamente el solido -- el suelo de la
		-- cueva. Es tambien lo que pasa con un DLL viejo, que no publica
		-- `RTS_CamLandZ` en absoluto, y ahi la camara se porta como antes en vez
		-- de quedarse sin altura.
		if solid then return solid, "solido (sin terreno aqui)" end
		return nil, nil
	end
	if solid then return solid, "solido" end
	return nil, nil
end

-- Un cambio de suelo mas grande que esto NO es un escalon del mundo: es un
-- teleport, un cambio de mapa o el primer frame. Filtrarlo a 6 yd/s dejaria la
-- camara subiendo durante minuto y medio, asi que ahi se salta de golpe.
local GROUND_SNAP = 300.0

local function Try(name, ...)
	local fn = _G[name]
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d, e, f = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d, e, f
end

-- === EL GIRO ES NATIVO. NOSOTROS SOLO LLEVAMOS LA POSICION ===============
--
-- QUINTO INTENTO, y el que sobra es el cuarto: leer el raton en crudo desde el
-- DLL y girar nosotros. Funcionaba y se sentia mal -- **a trompicones, con
-- latencia y demasiado sensible**, y con el eje horizontal invertido. Y tenia
-- que sentirse mal por construccion: el DLL acumula deltas, los publica a 67 Hz
-- por una cadena de Lua, y el addon los aplica al frame siguiente. Tres etapas
-- de retardo y una cuantizacion, para reimplementar algo que el cliente ya hace
-- perfecto.
--
-- Y LA EVIDENCIA DE QUE EL CLIENTE LO HACE BIEN YA LA TENIAMOS, mal leida. En
-- la 1.17.0 el jugador dijo *"ahora he podido mover la camara con el raton pero
-- no con WASD"*. En esa version el controlador estaba CAIDO -- habia borrado
-- `FlatForward` por accidente -- asi que no escribia la camara en absoluto, y
-- el arrastre nativo del cliente movia la camara que se ve. O sea que el giro
-- nativo SI llega a nuestra camara; lo que lo mataba era que yo sobrescribiera
-- los angulos cada frame. Mi conclusion de entonces ("gira otra camara") era
-- falsa, y la saque de una prueba hecha con el controlador muerto.
--
-- Asi que el reparto queda: **el cliente lleva la ORIENTACION, nosotros la
-- POSICION.** El raton derecho es el mouselook de siempre -- con la
-- sensibilidad y la inversion que el jugador ya tiene configuradas, gratis -- y
-- WASD, ESPACIO/C y la altura sobre el terreno siguen siendo nuestros.
--
-- COMO SE CONVIVE, que es lo unico con truco: `CommentatorSetCamera` toma los
-- seis valores de golpe, asi que no se puede escribir la posicion sin escribir
-- los angulos. Se LEEN los vivos justo antes y se vuelven a escribir tal cual:
-- para la orientacion es un no-op y el giro del cliente se acumula solo.
--
-- Se leen con `CommentatorGetCamera`, que es SINCRONO y lee `cam+0x11C`/`+0x120`
-- de la camara activa en este mismo frame -- no `RTS_CamFwd*`, que viene del DLL
-- con un tick de retraso. Esa eleccion es la que quita la latencia.
local function AdoptLook()
	local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
	if not ok or type(yaw) ~= "number" or type(pitch) ~= "number" then return end
	st.yaw = yaw % 360
	if pitch < -89 then pitch = -89 end
	if pitch > 89 then pitch = 89 end
	st.pitch = pitch
end

-- Los botones, del DLL. `IsMouseButtonDown` devuelve NO mientras el cliente
-- tiene el raton cogido, asi que para saber si estan los DOS pulsados no hay
-- otra fuente. Se queda solo para el gesto de avanzar; el giro ya no lo usa.
local function MouseButtons()
	if RTS_MouseRaw ~= 1 then return false, false end
	local b = tonumber(RTS_MouseB) or 0
	return (b % 2) == 1, (math.floor(b / 2) % 2) == 1
end

function F:Step(dt)
	if not self.active then return end
	-- Un frame perdido (carga de zona, alt-tab) puede traer un dt enorme, y
	-- con el la camara pega un salto. Se acota: mas vale ir un poco lento un
	-- frame que teletransportarse.
	if dt <= 0 then return end
	if dt > 0.1 then dt = 0.1 end

	local c = Cfg()

	-- PRIMERO los angulos vivos, DESPUES nuestras teclas. Al reves, el giro de
	-- Q/E de este frame se perderia: la adopcion sobreescribe el yaw entero.
	AdoptLook()
	local mouseLeft, mouseRight = MouseButtons()

	-- --- giro ---------------------------------------------------------
	-- Q y E VAN AL REVES QUE ANTES, a peticion del jugador (2026-09-10).
	--
	-- Se invierte AQUI y no cambiando el defecto de `yawSign`, que era lo obvio
	-- y no habria hecho nada: ese ajuste ya esta guardado a 1 en las
	-- SavedVariables, y lo guardado gana al defecto. Cambiar un valor por
	-- defecto solo alcanza a quien todavia no lo tiene escrito -- la misma
	-- trampa que dejo el `pitch` sin efecto cuando cambio de significado.
	--
	-- `yawSign` sigue significando lo mismo (**-1 si te sale al reves**), asi
	-- que el mando no cambia de sentido bajo los pies de nadie: lo que cambia es
	-- hacia donde gira el sentido "normal".
	local turn = 0
	if input.yawL then turn = turn + 1 end
	if input.yawR then turn = turn - 1 end
	if turn ~= 0 then
		st.yaw = (st.yaw + turn * c.yawSign * c.turn * dt) % 360
	end

	-- --- desplazamiento en el plano -----------------------------------
	local wantX, wantY = 0, 0
	local mx, my = 0, 0
	if input.fwd then my = my + 1 end
	if input.back then my = my - 1 end
	-- IZQUIERDO + DERECHO AVANZA, el gesto de siempre. Los botones vienen del
	-- DLL y no de `IsMouseButtonDown`, que miente durante el arrastre. Va aqui
	-- y no en un sitio aparte porque es una entrada mas del mismo solver: asi
	-- avanzar con el raton y girar a la vez sale gratis, en el mismo frame.
	if mouseLeft and mouseRight then my = my + 1 end
	if input.right then mx = mx + 1 end
	if input.left then mx = mx - 1 end

	if mx ~= 0 or my ~= 0 then
		local fx, fy = FlatForward()
		if fx then
			-- El lateral es el avance girado 90 grados en el plano. NO se usa
			-- `RTS_CamRight*`: el DLL documenta que la fila "right" de la
			-- matriz del cliente es la IZQUIERDA geometrica, y depender de ese
			-- signo aqui seria heredar una trampa que ya esta resuelta en otro
			-- sitio. Un giro de 90 grados no puede tener el signo mal sin que
			-- se vea al instante.
			local rx, ry = fy, -fx
			local dx = fx * my + rx * mx
			local dy = fy * my + ry * mx
			local len = math.sqrt(dx * dx + dy * dy)
			if len > 0.001 then
				-- Se normaliza para que en diagonal no se vaya un 41% mas
				-- rapido, que es el fallo clasico de sumar dos ejes.
				wantX, wantY = dx / len * c.speed, dy / len * c.speed
			end
		end
	end

	-- LA VELOCIDAD SE PERSIGUE, NO SE FIJA, y eso es el easing.
	--
	-- Antes la posicion se movia directamente con la tecla, asi que arrancar y
	-- parar eran escalones -- el "va a trompicones" del informe. Ahora la tecla
	-- pide una velocidad y la de verdad la persigue con el mismo suavizado
	-- exponencial que la altura: `1 - exp(-k*dt)`, independiente del frame rate.
	-- `/rts fc ease` es el mando; mas alto es mas seco.
	local ea = 1 - math.exp(-c.ease * dt)
	st.vx = (st.vx or 0) + (wantX - (st.vx or 0)) * ea
	st.vy = (st.vy or 0) + (wantY - (st.vy or 0)) * ea
	-- Por debajo de un pelo se para del todo: si no, la velocidad tiende a cero
	-- sin llegar nunca y la camara sigue arrastrandose despues de soltar.
	if math.abs(st.vx) < 0.01 then st.vx = 0 end
	if math.abs(st.vy) < 0.01 then st.vy = 0 end
	st.x = st.x + st.vx * dt
	st.y = st.y + st.vy * dt

	-- --- altura: ESPACIO y C mueven el OFFSET, no la Z ----------------
	local lift = 0
	if input.up then lift = lift + 1 end
	if input.down then lift = lift - 1 end
	if lift ~= 0 then
		st.offset = st.offset + lift * c.lift * dt
		if st.offset < c.minH then st.offset = c.minH end
		if st.offset > c.maxH then st.offset = c.maxH end
	end

	-- --- el objetivo y el suavizado -----------------------------------
	local ground = GroundUnderCamera(c)
	local targetZ
	if ground then
		-- EL ESCALON SE FILTRA EN EL SUELO, NO EN LA CAMARA, y esa es la unica
		-- razon de que esto sepa distinguir un cartel de una cuesta.
		--
		-- El suavizado de abajo trabaja sobre el ERROR de la camara, y un error
		-- no dice de donde viene: seis yardas de error son las mismas subiendo
		-- una loma que cruzando por encima de un poste. Lo que si los separa es
		-- CUANTO CORRE EL SUELO: una cuesta a toda velocidad mueve el suelo unas
		-- 20 yd/s, y el borde de un cartel lo mueve seis yardas EN UN FRAME --
		-- cientos de yd/s. Dos ordenes de magnitud, no un matiz.
		--
		-- Asi que el suelo medido persigue al suelo real con una velocidad
		-- limitada, y el limite BAJA con lo que quede por subir:
		--
		--     v = climb / (1 + (pendiente/soft)^2)
		--
		-- Una cuesta se queda a un par de yardas del suelo real y se sigue de
		-- cerca; un escalon de seis apenas se empieza, y cuando el cartel ya ha
		-- pasado el suelo real vuelve a bajar y la diferencia -- ahora minuscula
		-- -- se cierra deprisa. Quedarse quieto encima del cartel si sube: la
		-- velocidad nunca es cero, solo pequena. Eso es literalmente lo que se
		-- pidio -- "si de verdad quiero subirme, solo tengo que esperar".
		--
		-- `slow` es el suelo de esa velocidad y no es cosmetico: sin el, un
		-- acantilado de 60 yardas se subiria a 0.1 yd/s, o sea nunca.
		local gz, pend = st.gz, st.gstep or 0
		local d = gz and (ground - gz) or nil
		if not d or d > GROUND_SNAP or d < -GROUND_SNAP then
			gz, pend = ground, 0
		else
			local ad = (d >= 0) and d or -d
			-- EL FRENO LO DECIDE EL TAMANO DEL ESCALON, NO LO QUE QUEDE DE EL.
			--
			-- Aqui iba `ad` directamente y el simulador lo tumbo en la primera
			-- corrida: con la velocidad atada a lo que FALTA, cada subida se
			-- acelera segun se acerca -- las ultimas dos yardas de un escalon de
			-- quince se hacian a 25 yd/s, casi el doble de lo que sube el
			-- jugador a mano con ESPACIO. O sea el latigazo que veniamos a
			-- quitar, movido al final del recorrido, donde ademas se ve peor
			-- porque llega despues de un tramo lento.
			--
			-- "Esto es un escalon" es una propiedad del SUCESO, no de la
			-- distancia que queda ahora, asi que se recuerda: `pend` es el mayor
			-- desnivel visto desde la ultima vez que el filtro se puso al dia, y
			-- se borra justo al ponerse al dia. Una cuesta no lo levanta -- el
			-- suelo se mueve unas yardas por SEGUNDO y el filtro va sobrado, asi
			-- que el retraso se queda en la fraccion de yarda de un frame.
			if ad > pend then pend = ad end
			local q = pend / c.soft
			local v = c.climb / (1 + q * q)
			if v < c.slow then v = c.slow end
			local step = v * dt
			if ad <= step then
				gz, pend = ground, 0
			elseif d > 0 then
				gz = gz + step
			else
				gz = gz - step
			end
			-- TOPE DE RETRASO HACIA ARRIBA, y no es un ajuste nuevo: SALE DEL
			-- OFFSET. Si el suelo de verdad no debe acercarse a la camara mas de
			-- `clear`, y la camara vuela a `offset` sobre el suelo filtrado,
			-- entonces el filtrado no puede quedarse mas de `offset - clear` por
			-- debajo del real. Ni una constante que inventar ni un mando que
			-- explicar.
			--
			-- Es ademas lo que impide el unico caso feo que quedaba: un escalon
			-- seguido de una cuesta larga deja el freno puesto -- `pend` sigue
			-- alto -- y sin tope la camara se hundiria en la loma hasta que el
			-- suelo duro la rescatara de un tiron. Con el tope no llega a pasar:
			-- el limite se alcanza poco a poco y a partir de ahi el filtro sigue
			-- al suelo a su misma velocidad.
			--
			-- SOLO HACIA ARRIBA. Hacia abajo el retraso no es peligroso, es la
			-- vista: cuando el suelo se acaba, la camara baja despacio y el
			-- terreno se abre debajo. Capar ese lado seria obligarla a caer.
			--
			-- Y EL TOPE SE ALCANZA A UNA VELOCIDAD, NO DE UN SALTO (2026-09-12).
			--
			-- Aqui ponia `gz = ground - cap` a secas, y eso convertia el tope --
			-- que se escribio para que el suelo duro NO tuviera que rescatar a
			-- la camara -- en el atajo que se salta el limitador entero. Con el
			-- offset por defecto (30) el tope son 28 yardas, asi que cualquier
			-- escalon de mas de 28 pasaba de golpe; con el offset bajado a 6.4,
			-- medido en juego el 2026-09-12, son CUATRO YARDAS Y MEDIA, o sea
			-- que el filtro de escalon no filtraba absolutamente nada.
			--
			-- `climb`, `soft` y `slow` quedaban de adorno justo en el caso que
			-- los justifica. Es el modo de fallo de siempre: dos caminos para lo
			-- mismo y el malo manda.
			if d > 0 then
				local cap = st.offset - c.clear
				if cap < 1 then cap = 1 end
				local want = ground - cap
				if want > gz then
					local lim = c.push * dt
					gz = (want - gz > lim) and (gz + lim) or want
				end
			end
		end
		st.gz, st.gstep = gz, pend
		targetZ = gz + st.offset
	else
		-- SIN SUELO NO SE INVENTA UNO. El rayo puede no contestar dentro de una
		-- cueva o sobre agua profunda; mantener la Z es lo unico que no pega un
		-- salto. Lo que NO se hace es caer al terreno bajo el jugador, que fue
		-- la tentacion obvia: en una camara RTS ese punto puede estar a
		-- cientos de yardas y en otra altura.
		targetZ = st.z
		-- Y el suelo filtrado se olvida: cuando el rayo vuelva a contestar sera
		-- en otro sitio, y arrastrar el de antes lo haria parecer un escalon
		-- gigante justo en el frame de la reaparicion.
		st.gz, st.gstep = nil, 0
	end

	-- Suavizado exponencial independiente del frame rate. `1 - exp(-k*dt)` y no
	-- una fraccion fija por frame: con una fraccion fija, a 144 fps la camara
	-- llega tres veces mas rapido que a 45, o sea que el tacto cambiaria con el
	-- rendimiento. Es la formula del §6 del brief.
	--
	-- Sigue estando DESPUES del filtro de suelo y no en su lugar: el limitador
	-- de velocidad deja esquinas -- el frame en que deja de correr al tope se ve
	-- como un tiron -- y esto las redondea. Cada uno hace una cosa: el de arriba
	-- decide CUANTO se sube, este decide como se entra y se sale.
	local alpha = 1 - math.exp(-c.smoothZ * dt)
	st.z = st.z + (targetZ - st.z) * alpha

	-- SUELO DURO, aparte del suavizado. El suavizado es estetica; esto impide
	-- que la camara se meta dentro del terreno mientras persigue una subida
	-- brusca -- que es el caso que el brief describe en su §8 y el unico en el
	-- que el suavizado, por definicion, va por detras.
	--
	-- Y SE MIDE CONTRA EL SUELO DE VERDAD, no contra el filtrado: lo que no
	-- puede pasar es que la camara se meta dentro de una loma REAL.
	--
	-- Que esto no sea el tiron de siempre otra vez lo garantiza el tope de
	-- retraso de arriba, no la suerte: con el tope puesto, el suelo real nunca
	-- puede acercarse a la camara mas de `clear`, asi que este `if` no llega a
	-- dispararse mientras el filtro manda. Sin el tope los dos se pelearian cada
	-- frame -- uno frenando y el otro empujando -- que es la forma exacta de
	-- discusion que este proyecto ya ha perdido dos veces.
	--
	-- Y EMPUJA A UNA VELOCIDAD (2026-09-12). El parrafo de arriba daba por hecho
	-- que este `if` no llega a dispararse mientras el filtro manda, y era falso:
	-- el tope de retraso lo llamaba en cuanto el escalon pasaba de `offset -
	-- clear`, y entonces esta linea movia la camara OCHENTA YARDAS EN UN FRAME.
	-- Enumerados todos los escritores de `st.z`, era el unico teletransporte del
	-- fichero -- lo demas va limitado o suavizado -- asi que es el "plop".
	--
	-- Sigue siendo duro: no negocia con el suavizado, gana siempre. Lo unico que
	-- cambia es que tarda lo que tiene que tardar, y eso convierte un salto que
	-- no se puede ver en una subida que se ve venir y de la que se puede salir
	-- marcha atras.
	if ground and st.z < ground + c.clear then
		local want = ground + c.clear
		local lim = c.push * dt
		st.z = (want - st.z > lim) and (st.z + lim) or want
	end

	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch or c.pitch, nil)
end

--- Arranque y parada -------------------------------------------------------

function F:Start()
	if self.active then return true end

	-- Las dos cosas que solo da el DLL: el avance y el suelo bajo la camara.
	if RTS_Ready ~= 1 then
		ns.Print("|cffff0000camara RTS:|r hace falta rts_core inyectado.")
		ns.Print("  Abre el juego con |cffffff002-Jugar.bat|r.")
		return false
	end

	local px, py, pz
	if RTS_HasPos == 1 then
		px, py, pz = RTS_PX, RTS_PY, RTS_PZ
	end
	if not px then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica tu posicion todavia.")
		return false
	end

	if not GrabKeys() then return false end

	-- UN SOLO DUEÑO DEL MOVIMIENTO. Con el modo libre armado el cliente tambien
	-- conduce la camara con WASD, y aunque nuestros bindings se quedan las
	-- teclas antes de que el las vea, dejarle la velocidad puesta es dejar un
	-- segundo motor encendido esperando a que una tecla se escape. Su unidad
	-- ademas no son yardas/segundo: 20 manda la camara a otro continente.
	Try("CommentatorSetMoveSpeed", 0)

	-- QUE SE VEA MI HEROE, Y SIN ESPERAR A NADIE.
	--
	-- AQUI PEDIA `Channel:SetShowSelf(true)`, el apaño para el heroe invisible
	-- por el canal de publicacion. Se ha ido el 2026-09-10 por dos razones, y
	-- la segunda sola ya bastaba:
	--
	--   * El problema esta resuelto de verdad: `SelfShow.cpp` parchea los cinco
	--     bytes de `0x006E085C` y **se arma solo** con los flags puestos, que es
	--     justo lo que hace `Spectate`. No hay nada que pedir.
	--   * El bit 30 NUNCA tuvo lector. Ningun DLL lo decodifica -- el layout del
	--     protocolo 3 lo lista como libre -- asi que esta llamada no hacia nada
	--     y lo parecia todo.

	local c = Cfg()
	st.offset = c.height
	st.x, st.y = px, py
	st.z = pz + c.height
	-- El suelo filtrado de la ULTIMA vez que se entro no vale: puede ser de
	-- otro continente. A nil, que es lo que hace que el primer tick lo siembre
	-- con la medida de aqui en vez de venir subiendo desde donde estuvieramos.
	st.gz, st.gstep = nil, 0
	-- El yaw arranca en 0 y NO se deriva del que tenga la camara: la convencion
	-- de angulos de `CommentatorSetCamera` no se puede leer del binario, asi que
	-- sembrarlo seria adivinar. El precio es un giro brusco al entrar; el
	-- beneficio es que a partir de ahi todo es consistente, y el avance no
	-- depende del yaw para nada (sale del vector que publica el DLL).
	st.yaw = 0
	st.pitch = c.pitch

	-- QUE NO CHOQUE CON NADA QUE NO SEA NUESTRO SUELO.
	--
	-- Va AQUI y no antes por una razon que no se ve: el manejador del cliente
	-- exige los dos flags de jugador y, si faltan, retorna sin escribir y sin
	-- error. A estas alturas la puerta ya esta abierta -- `WaitGate` ha dejado
	-- pasar -- asi que los flags estan puestos. Llamarlo en `CameraOn`, antes de
	-- `Spectate`, habria sido una llamada que parece funcionar y no hace nada.
	--
	-- Una vez basta: quien lo enciende es el init del objeto de comentarista, y
	-- ese corre UNA VEZ en el arranque del cliente. Nadie lo reescribe por
	-- detras, asi que no hay que refrescarlo cada tick -- que es la forma de
	-- pelea que este proyecto ya ha perdido dos veces.
	if c.noclip == 1 then ns.Camera:SetCollision(false) end

	self.active = true
	ns.Camera:SpecPlace(st.x, st.y, st.z, st.yaw, st.pitch, nil)
	return true
end

function F:Stop()
	if not self.active then return true end
	self.active = false
	-- CAPTURAR Y DEVOLVER, con la unica pega de que aqui no hay de donde
	-- capturar: el cliente no publica un getter de esto. Asi que se devuelve al
	-- valor MEDIDO, no supuesto -- `0x0056BC80` escribe 1 en ese campo al
	-- arrancar el juego, o sea que 1 es como estaba antes de que lo tocaramos.
	--
	-- Y va antes de que nadie quite los flags: `R:CameraOff` llama a esto y solo
	-- despues a `Spectate(false)`. Al reves, esta linea no escribiria nada y la
	-- colision se quedaria apagada para el resto de la sesion.
	ns.Camera:SetCollision(true)
	-- Las teclas pueden no volver en combate; se avisa al llamante para que
	-- pueda reintentarlo al salir de la pelea, igual que hace `Chrome`.
	return ReleaseKeys()
end

-- Para el reintento tras combate.
function F:KeysPending()
	return savedBindings ~= nil
end

function F:ReleaseKeysNow()
	return ReleaseKeys()
end

--- La salida de emergencia ------------------------------------------------
--
-- `/rts fc home` devuelve la camara sobre el heroe.
--
-- Existe porque el fallo de las cuevas tenia DOS mitades y solo una es la
-- aritmetica: la otra es que una vez la camara acaba en un sitio malo **no hay
-- ninguna tecla que la saque**. C solo baja el `offset` (suelo `minH`), y el
-- suelo duro gana; W/A/S/D mueven a ciegas dentro de la roca, donde no hay
-- ninguna referencia para saber hacia donde esta la salida. Literalmente sin
-- vuelta: *"me lleva a un sitio del que no puedo volver"*.
--
-- Va aparte del arreglo del salto a proposito. El arreglo puede estar
-- incompleto -- quedan causas por enumerar -- y esto vale igual sea cual sea la
-- causa, porque no diagnostica nada: solo deshace. Lo mismo que el macro
-- "Reset IA" para las estrategias de los bots.
--
-- Se recolocan las MISMAS cosas que `Start`, ni una mas ni una menos, y ahi
-- entran las dos que se olvidan solas: el suelo filtrado (`gz`) hay que
-- borrarlo o el primer frame en el destino ve un escalon gigante, y la
-- velocidad del plano (`vx`,`vy`) o la camara sale disparada al llegar.
function F:Home()
	if not self.active then
		ns.Print("|cffff8800camara RTS:|r la camara libre no esta activa.")
		return false
	end
	if RTS_HasPos ~= 1 or not RTS_PX then
		ns.Print("|cffff0000camara RTS:|r el DLL no publica tu posicion.")
		return false
	end
	local c = Cfg()
	st.x, st.y = RTS_PX, RTS_PY
	st.offset = c.height
	st.z = RTS_PZ + c.height
	st.gz, st.gstep = nil, 0
	st.vx, st.vy = 0, 0
	ns.Print(("|cff33ccffcamara RTS:|r camara devuelta sobre tu heroe (%.0f %.0f %.0f)."):format(
		st.x, st.y, st.z))
	return true
end

--- Ajustes por comando -----------------------------------------------------

local LABEL = {
	speed = "velocidad en el plano (yd/s)",
	lift = "velocidad de subida (yd/s)",
	turn = "giro (grados/s)",
	height = "altura sobre el suelo (yd)",
	minH = "altura minima (yd)",
	maxH = "altura maxima (yd)",
	smoothZ = "suavizado de altura (k)",
	floor = "que cuenta como suelo: 1 = solo terreno, 0 = lo primero que haya",
	noclip = "1 = la camara atraviesa todo; 0 = colision del cliente",
	climb = "velocidad de seguimiento del suelo con poca diferencia (yd/s)",
	soft = "el codo: a partir de estas yardas de escalon, se frena (yd)",
	slow = "velocidad minima de seguimiento del suelo (yd/s)",
	pitch = "inclinacion de entrada (grados, POSITIVO mira abajo)",
	clear = "margen duro sobre el suelo (yd)",
	push = "lo mas deprisa que el suelo duro puede empujar la camara (yd/s)",
	yawSign = "signo del giro con Q/E (1 o -1)",
	ease = "suavizado del arranque/parada en el plano (k)",
}

function F:Set(key, value)
	local c = Cfg()
	if key == nil or LABEL[key] == nil then
		ns.Print("|cff33ccffcamara RTS:|r ajustes")
		for k in pairs(LABEL) do
			ns.Print(("  |cffffff00%s|r = %s   |cff888888%s|r"):format(
				k, tostring(c[k]), LABEL[k]))
		end
		ns.Print("  |cffffff00/rts fc <ajuste> <valor>|r")
		return
	end
	local n = tonumber(value)
	if not n then
		ns.Print(("|cffff0000camara RTS:|r %s quiere un numero."):format(key))
		return
	end
	c[key] = n
	Cfg()   -- reacota y descarta lo imposible
	if st.offset and (key == "height" or key == "minH" or key == "maxH") then
		st.offset = math.max(c.minH, math.min(c.maxH, st.offset))
	end
	-- El pitch es estado vivo, asi que tocarlo tiene que verse AHORA. Sin esto
	-- `/rts fc pitch 60` no haria nada hasta la siguiente entrada al modo, que
	-- se lee como que el ajuste no funciona.
	if key == "pitch" then st.pitch = Cfg().pitch end
	-- Igual que el pitch: es estado vivo. Sin esto `/rts fc noclip 0` no haria
	-- nada hasta la siguiente entrada al modo, que se lee como que el ajuste no
	-- funciona -- y aqui ademas el sintoma tardaria en verse, porque hay que ir
	-- a buscar una pared.
	if key == "noclip" and self.active then
		ns.Camera:SetCollision(Cfg().noclip == 0)
	end
	ns.Print(("|cff33ccffcamara RTS:|r %s = %s"):format(key, tostring(Cfg()[key])))
end

function F:Report()
	local c = Cfg()
	ns.Print("|cff33ccffcamara RTS:|r " .. (self.active and "|cff00ff00ON|r" or "OFF"))
	if st.x then
		ns.Print(("  pos %.1f %.1f %.1f   yaw %.0f   pitch %.0f   offset %.1f"):format(
			st.x, st.y, st.z, st.yaw, st.pitch or 0, st.offset or 0))
	end
	-- LOS DOS RAYOS, SIEMPRE LOS DOS, y no solo el que este en uso.
	--
	-- La pregunta que se hace delante de una casa es "¿por que sube la camara?",
	-- y se contesta sola en cuanto se ven los dos numeros juntos: si `solido`
	-- esta quince yardas por encima de `terreno`, eso de debajo es un tejado.
	-- Con un solo numero hay que adivinar cual de los dos se esta mirando.
	local land  = (RTS_CamLandHit  == 1) and RTS_CamLandZ  or nil
	local solid = (RTS_CamGroundHit == 1) and RTS_CamGroundZ or nil
	ns.Print(("  suelo: terreno %s   solido %s   |cffffff00en uso: %s|r"):format(
		land and ("%.1f"):format(land) or "|cffff8800--|r",
		solid and ("%.1f"):format(solid) or "|cffff8800--|r",
		c.floor == 1 and "terreno" or "solido"))
	if land == nil and RTS_CamLandHit == nil then
		-- Un DLL viejo no publica la variable EN ABSOLUTO, y eso no se parece en
		-- nada a "el rayo no ha chocado". Sin esta linea, `floor 1` se comporta
		-- exactamente como `floor 0` y parece que el ajuste no hace nada.
		ns.Print("  |cffff8800Este rts_core no publica el terreno|r: hace falta " ..
			"0.25.0 o mas nuevo (recompila e inyecta de nuevo).")
	end
	-- Y LA OTRA MITAD DE "NO PUEDO ENTRAR". Son dos causas distintas con el
	-- mismo sintoma -- el suelo la sube al tejado, la colision la empuja fuera
	-- de la pared -- y arreglada una sola, la pantalla se ve igual.
	ns.Print(("  colision del cliente: %s"):format(
		c.noclip == 1 and "|cff00ff00APAGADA|r (atraviesa todo)"
		              or "|cffff8800encendida|r (choca con paredes y tejados)"))
	local g, src = GroundUnderCamera(c)
	if g then
		ns.Print(("  suelo en uso %.1f (%s)   filtrado %s   separacion %.1f yd"):format(
			g, src,
			st.gz and ("%.1f"):format(st.gz) or "--",
			(st.z or g) - (st.gz or g)))
	else
		ns.Print("  |cffff8800sin suelo|r: el rayo no contesta aqui (¿cueva, agua?).")
	end
	local fx, fy = FlatForward()
	if fx then
		ns.Print(("  adelante plano %.2f %.2f"):format(fx, fy))
	else
		ns.Print("  |cffff8800sin adelante|r: ¿mirando a plomo, o sin camara publicada?")
	end

	-- EL BIT DEL MODELO, PARTIDO EN DOS MITADES.
	--
	-- "No se ve mi heroe" puede fallar en el addon (el bit no se manda) o en el
	-- DLL (llega y el bit de dibujo no es ese). Son dos arreglos distintos en
	-- dos lenguajes distintos, y distinguirlos mirando la pantalla cuesta una
	-- ronda. Esto lo contesta en un comando: si el bit sale puesto y el modelo
	-- sigue invisible, el problema esta aguas abajo.
	local v = ns.Channel.last
	if v then
		local bit30 = (math.floor(v / 2 ^ 30) % 2) == 1
		ns.Print(("  canal = %d, bit30 (verme) = %s"):format(
			v, bit30 and "|cff00ff00SI|r" or "|cffff0000NO|r"))
		if not bit30 then
			ns.Print("  |cffff8800El addon no lo esta pidiendo|r: el fallo es de este lado.")
		else
			ns.Print("  |cff888888Se esta pidiendo. Si no te ves, es el DLL: o el bit")
			ns.Print("  0x800 de +0x7C no es el dibujo, o +0xB8 no es ese objeto.|r")
		end
	else
		ns.Print("  |cffff8800canal sin escribir todavia|r (¿RTS_UGEN, protocolo?).")
	end

end

--- EL INSTRUMENTO DE LA CAMARA ---------------------------------------------
--
-- Existe porque el giro costo CINCO intentos y cada causa estaba en un eslabon
-- distinto, ninguno visible desde la pantalla. Ahora mide las dos cosas que
-- importan del reparto nuevo: que el cliente GIRE (nosotros solo leemos) y que
-- nuestra escritura de posicion no le este pisando el giro.
function F:Mouse()
	ns.Print("|cff33ccffcamara:|r gira con el DERECHO durante 2 segundos...")
	local t, dyaw, dpitch, n = 0, 0, 0, 0
	local y0, p0 = nil, nil
	local sawL, sawR = false, false
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(self2, e)
		t = t + e
		local ok, _, _, _, yaw, pitch = Try("CommentatorGetCamera")
		if ok and type(yaw) == "number" then
			n = n + 1
			if y0 then
				local d = yaw - y0
				if d > 180 then d = d - 360 elseif d < -180 then d = d + 360 end
				dyaw = dyaw + math.abs(d)
				dpitch = dpitch + math.abs(pitch - p0)
			end
			y0, p0 = yaw, pitch
		end
		local l, r = MouseButtons()
		if l then sawL = true end
		if r then sawR = true end
		if t < 2.0 then return end
		self2:SetScript("OnUpdate", nil)
		ns.Print(("  lecturas de angulo: %d   giro acumulado: yaw %.1f, pitch %.1f"):format(
			n, dyaw, dpitch))
		ns.Print(("  botones (del DLL): derecho %s   izquierdo %s"):format(
			sawR and "|cff00ff00SI|r" or "|cffff0000NO|r", sawL and "SI" or "no"))
		if n == 0 then
			ns.Print("  |cffff0000CommentatorGetCamera no contesta|r: la puerta esta")
			ns.Print("  cerrada. |cffffff00/rts cam probe|r dice en que paso.")
		elseif dyaw < 1 and dpitch < 1 then
			ns.Print("  |cffff8800El cliente no gira esta camara|r, o la estamos")
			ns.Print("  pisando. Mira si `ease` o el escritor de posicion tocan")
			ns.Print("  los angulos en vez de reescribir los leidos.")
		else
			ns.Print("  |cff00ff00El giro nativo llega|r. La sensibilidad es la de")
			ns.Print("  tus ajustes de raton de WoW, no la del addon.")
		end
	end)
end

---- El latido ---------------------------------------------------------------

function F:Create()
	local f = CreateFrame("Frame")
	-- Cada frame, y tiene que ser cada frame: el suavizado y la correccion de
	-- altura son por dt y un temporizador mas lento se ve como escalones.
	-- LAS TECLAS TIENEN QUE VOLVER AUNQUE LA SALIDA FUERA EN COMBATE.
	--
	-- `SetBinding` esta bloqueado en combate, asi que un `Stop()` a mitad de
	-- pelea deja WASD apuntando a nuestros botones -- y entonces el jugador
	-- **no puede moverse** en juego normal hasta el siguiente toggle. Es mucho
	-- peor que el caso que lo provoca, y no da ningun error.
	--
	-- Es la misma guarda que `Camera.lua` tiene para Q/E desde que existe, y la
	-- misma costura que `Chrome` usa para los frames protegidos: lo que no se
	-- puede hacer ahora se aplaza al momento en que se puede.
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("PLAYER_LEAVING_WORLD")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LEAVING_WORLD" then
			F.active = false
			return
		end
		if not F.active and F:KeysPending() then
			if F:ReleaseKeysNow() then
				ns.Print("|cff33ccffcamara:|r teclas devueltas al salir del combate.")
			end
		end
	end)

	f:SetScript("OnUpdate", function(_, e)
		if F.active then
			local ok, err = pcall(F.Step, F, e)
			if not ok then
				-- Un error aqui correria en CADA frame y llenaria la pantalla,
				-- asi que el controlador se apaga solo y lo dice una vez.
				F.active = false
				ns.Print("|cffff0000camara RTS:|r " .. tostring(err))
				ns.Print("  controlador detenido para no repetir el error.")
			end
		end
	end)
	self.events = f
end
