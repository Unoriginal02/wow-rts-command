# Revisión de arquitectura, 2026-09-02

Escrito antes de repensar el centro de la HUD, y con esa pregunta en la cabeza:
**¿está el proyecto en condiciones de crecer por ahí?**

La respuesta corta es **sí, y con una reserva concreta**: el reparto de la barra
(`Bar.lua`) es un buen contrato y la sala nueva se puede colgar de él sin tocar
nada. Lo que no está listo es la **capa de abajo** — cómo un panel habla con el
servidor y con el DLL. Hoy eso pasa por sitios que no son suyos, y el módulo que
más va a apoyarse en ello es justo el que se va a escribir.

Todos los números de aquí están medidos sobre el árbol de hoy, no estimados. Los
comandos que los sacan están escritos para poder repetirlos.

---

## 0. Resumen

> **ESTADO 2026-09-02, addon 0.50.0: hechos los §2, §3 y §4** — los tres
> primeros del §13. El **§14** cuenta qué cambió y las dos cosas que aparecieron
> por el camino. El §1 sigue pendiente y es el siguiente.

| # | Hallazgo | Bloquea | Estado |
|---|---|---|---|
| 1 | `Bridge.lua` es una costura que nadie usa: 98 lecturas crudas de `RTS_*` en 8 ficheros | **Sí** | pendiente |
| 2 | `Camera.lua` es la capa de transporte de todo el proyecto | **Sí** | **hecho** (§14) |
| 3 | `HasServer()` es una promesa, y cada quien se escribe su propia espera | **Sí** | **hecho** (§14) |
| 4 | `Bar:Panels()` es una lista a mano; `Bar:OnLayout` sí es un registro | **Sí**, barato | **hecho** (§14) |
| 5 | `RTSMode.lua` hace ocho cosas | No, pero encarece todo | pendiente |
| 6 | `Core.lua`: cadena de 39 ramas + orden de arranque a mano | No, pero cada módulo nuevo lo toca dos veces | pendiente |
| 7 | SavedVariables: 34 claves planas, 16 ficheros, sin versión | No, pero ya ha costado cuatro purgas | pendiente |
| 8 | 20 `OnUpdate` en 12 ficheros; `W:Every` existe y tiene UN usuario | No | pendiente |
| 9 | El número de protocolo del DLL está escrito en dos sitios | No, pero es una bomba de relojería | pendiente |
| 10 | `check_addon.py` no mira `Bindings.xml` | No | pendiente |

**Lo que NO hay que tocar** está en el §12. Es tan importante como la lista de
arriba: hay tres o cuatro decisiones aquí que están bien y que un "vamos a
modularizar" mal dirigido rompería.

---

## 1. `Bridge.lua` es una costura que nadie usa

Es el hallazgo más grave y el que más barato sale de arreglar ahora.

`Bridge.lua` se declara a sí mismo la capa de capacidades nativas: *"the DLL
PUSHES instead — it sets plain Lua globals (RTS_Ready, RTS_PX, ...). We read
those globals; nothing is called across the boundary."* Expone **8 funciones**.

La realidad, medida:

    grep -rn "RTS_[A-Z]" addon/*.lua | grep -v "^addon/Bridge.lua"

**98 líneas de código, en 8 ficheros, leen los globales del DLL directamente:**

| fichero | lecturas | qué lee |
|---|---|---|
| `Markers.lua` | 37 | la base de cámara entera (pos, fwd, right, up, fov, aspect) |
| `Core.lua` | 21 | el volcado de `/rts native` |
| `Channel.lua` | 14 | la lista de unidades y `RTS_PROTO`/`RTS_UGEN` |
| `RTSMode.lua` | 12 | la lista de unidades y la cámara |
| `Camera.lua` | 5 | el vector de avance (detección de giro) |
| `Calib.lua` | 4 | la proyección |
| `SelectionRing.lua` | 3 | `RTS_PROTO` |
| `Route.lua` | 2 | posiciones |

### La prueba de que la costura está rota es su propia documentación

`Bridge.lua:53` dice, hoy:

    -- Per-unit world position is not available in the push model yet (the DLL
    -- would need to know which GUID to publish). Returns nil until the request
    -- channel exists; callers already branch on nil.
    function B:GetUnitWorldPosition(_, _)
        return nil

Y **cuatro ficheros parsean la lista de unidades a mano** para obtener
exactamente eso — `Channel`, `Core`, `Markers` y `RTSMode` recorren `RTS_UN` y
`_G["RTS_U" .. i .. "G"]` y sus hermanos. La función de la costura dice "esto no
existe todavía" mientras cuatro módulos lo usan por su cuenta.

No es que la costura esté incompleta. Es que **se la rodeó y nadie volvió a
mirarla**, así que ahora miente.

### Qué cuesta

1. **Cambiar el DLL toca 8 ficheros.** El formato de la lista de unidades
   (`RTS_U<i>G/X/Y/Z/T`) es un contrato entre el DLL y cuatro parsers escritos a
   mano. Publicar un campo más, o cambiar el orden, son cuatro ediciones y
   ninguna da error si se olvida una: devuelve `nil` y se dibuja nada, que es el
   fallo silencioso que este proyecto persigue desde la etapa 5i.

2. **La degradación sin DLL la garantiza `Bridge` y sólo `Bridge`.** Cada uno de
   sus 8 métodos empieza con `if RTS_Ready ~= 1 then return nil end`. Los 98
   lectores crudos tienen que acordarse cada uno. Y **eso ya costó una sesión
   entera** — está escrito en `RTSMode.lua`:

   > *SIN DLL EL MODO RTS SE DEGRADA EN SILENCIO, Y ESO COSTO UNA SESION ENTERA.
   > (...) Se lee como tres fallos distintos y no lo es.*

   El aviso que se añadió entonces es correcto, pero es un **cartel**, no una
   costura: sigue habiendo 98 sitios donde se puede leer un global del DLL sin
   comprobar que el DLL está.

3. **La sala nueva va a querer todo eso.** Posición de una unidad para dibujar
   algo sobre ella, la proyección, la lista de lo que hay a la vista. Si se
   escribe leyendo globales crudos, son 98 → 120, y el problema crece con cada
   panel.

### Qué haría

No reescribir `Markers.lua`. Es matemática de proyección y está en su sitio —
**es el consumidor legítimo de la base de cámara**. Lo que falta es que sea el
*único*, y que la lista de unidades tenga un dueño:

    ns.Bridge:Camera()        -- pos, fwd, right, up, fov, aspect, o nil
    ns.Bridge:Units()         -- lista { guid, x, y, z, kind }, o {} sin DLL
    ns.Bridge:UnitPos(guid)   -- lo que hoy miente devolviendo nil
    ns.Bridge:Protocol()      -- el §9

`Markers` se queda con la matemática y le pide la base a `Bridge`. `Channel`,
`Core` y `RTSMode` dejan de tener un parser cada uno. **Es mecánico y no cambia
comportamiento**, que es la clase de refactor que se puede hacer sin una ronda
de pruebas detrás.

---

## 2. `Camera.lua` es la capa de transporte de todo el proyecto

`ns.SendServer` — el canal addon → mod-rts que usan `Orders`, `Marks`, `Route` y
`RTSMode` — está definido en `Camera.lua:249`. Y el sentido de vuelta también:
el `CHAT_MSG_ADDON` lo escucha un frame creado en `Camera:Create()`, y su
manejador es una cadena de **12 `message:match`** que reparte a `RTSMode`,
`Orders`, `Flare`, `Route` y `Marks`.

También vive ahí el `PLAYER_LEAVING_WORLD` que le dice a `Marks` que olvide sus
dynobjects.

Nada de eso es de la cámara. Está ahí por historia: la cámara fue lo primero que
habló con mod-rts, y el canal se quedó donde nació.

**Por qué importa ahora y no antes.** La sala nueva va a ser el mayor consumidor
de mensajes de servidor del addon — objetivos, barras, roles y foco eran ya
siete verbos. Cada uno de ellos significa, hoy, **editar `Camera.lua`**. Y
cuando se borraron, significó editar `Camera.lua` otra vez. El módulo que menos
tiene que ver con la sala es el que más cambia cada vez que la sala cambia.

**Qué haría.** Un `Link.lua` (o `Server.lua`) con el frame, el `Send` y un
registro:

    ns.Link:On("TGTS", function(rest) ... end)
    ns.Link:Send("TGTS")

`Camera.lua` se queda con `CAM ...` y con `OnState`/`OnOffset`, que sí son
suyos. **Ya existe el patrón dos veces en el proyecto** (`Selection:Subscribe`,
`Bar:OnLayout`), así que no hay que inventar nada: es el mismo registro con
`pcall`.

Y hay un beneficio que no es de limpieza: hoy un verbo desconocido **cae al
final de la cadena y se ignora en silencio**. Con un registro se puede decir
*"llegó `ROLES` y no lo escucha nadie"*, que es exactamente el diagnóstico que
hará falta mientras se construye la sala nueva contra verbos que ya existen.

---

## 3. `HasServer()` es una promesa, y cada quien se escribe su espera

`Orders:HasServer()` se pone a `true` con la **primera respuesta** de mod-rts, o
sea que es falso durante el primer segundo — incluso teniendo mod-rts delante.
Ya está documentado dos veces, la segunda diciendo *"y ya van dos"*.

Hoy quedan dos copias literales del mismo bucle:

    grep -rn "HasServer() or .*acc > " addon/*.lua
    # RTSMode.lua:992   ApplyLootAllSoon
    # RTSMode.lua:1165  el recordatorio de Marks

Y **había dos más** en `Skills.lua` y `Roles.lua`, borradas hoy con ellos. O sea
cuatro copias de `si el servidor contesta o han pasado 2,5 s`. La quinta la va a
escribir la sala nueva, porque lo primero que hará al seleccionar a alguien es
pedirle algo al servidor.

**Qué haría.** Una función, cinco líneas:

    ns.WhenServer(fn, timeout)   -- llama a fn en cuanto conteste, o al vencer

Es el arreglo más barato de esta lista y el que más veces se ha pagado.

---

## 4. `Bar:Panels()` es una lista a mano

Medio contrato está bien hecho y medio no, y es fácil no darse cuenta.

**Bien:** `B:SlotFrame(key)`, `B:Cells(key)` y `B:OnLayout(fn)` son un contrato
de verdad. `OnLayout` es un registro con `pcall`, así que un panel que reviente
no se lleva la barra por delante. `Panel.lua` y `Rails.lua` lo usan limpiamente
y **no se tocaron al vaciar la sala** — que es la prueba de que el contrato
aísla.

**Mal:** entrar y salir no pasa por ahí. `Bar.lua` tiene una lista escrita:

    local function Panels()
        return { ns.Panel, ns.Rails }
    end

Su propio comentario dice por qué existe — *"añadir un panel no debería obligar
a tocar `Enter` y `Leave` por separado"* — y resuelve la mitad del problema (una
lista en vez de dos llamadas sueltas) dejando la otra: **añadir un panel sigue
obligando a editar `Bar.lua`**. Y el panel tiene que estar cargado antes en el
`.toc`, o `ns.Panel` es `nil` en ese instante.

**Qué haría.** Que el panel se apunte él:

    ns.Bar:Register(P)   -- desde el propio módulo, al final del fichero

Es una línea de cambio en `Bar.lua` y elimina el único sitio donde la sala nueva
tendría que tocar el fichero del arte. Con cinco o seis paneles por delante,
paga solo.

---

## 5. `RTSMode.lua` hace ocho cosas

1.348 líneas, y al menos ocho responsabilidades:

| líneas | qué |
|---|---|
| 50–58 | el roster seleccionable |
| 59–233 | *picking*: hover, hostiles, criatura más cercana, `KindOf` |
| 234–248 | selección por caja |
| 250–495 | interpretación de gestos (clic izq/der, arrastre, detección de giro) |
| 497–886 | captura de ratón |
| 887–1030 | **política de botín** (libre, `LOOT 1`) |
| 1032–1115 | **selfbot** |
| 1117–1290 | ciclo del modo (`Toggle`, `LeaveWorld`, `LeaveChrome`) |
| 1288–1348 | diagnósticos de picking |

El botín y el selfbot no tienen nada que ver con el ratón. Están ahí porque
`Toggle()` los aplica al entrar — o sea, por el **orden de arranque**, no por el
tema.

**No lo pondría en la ruta crítica del rediseño.** La sala nueva no toca esto, y
partirlo es la clase de refactor que rompe algo sutil: el orden de `LeaveWorld`
antes que `LeaveChrome` está razonado línea a línea y es correcto. Pero es la
razón de que *"¿dónde va esto?"* sea una pregunta difícil en este addon: hay un
fichero que es donde va todo lo que no tiene sitio, y eso crece solo.

Si se toca alguna vez, la línea de corte limpia es sacar **botín** y **selfbot**
a sus ficheros y que `Toggle` los llame. Son dos bloques autocontenidos con su
propia persistencia.

---

## 6. `Core.lua`: 39 ramas y un orden de arranque a mano

    grep -c 'elseif cmd ==' addon/Core.lua   # 39

La cadena va de la línea 322 a la 870. Cada módulo nuevo con comandos la edita,
y el arranque (`Core.lua:84-92`) es una secuencia escrita de `ns.X:Create()`
donde el **orden importa** y no está declarado en ninguna parte — se deduce de
los comentarios (`HUD` antes que `Chrome`, porque saca el Minimap del cluster
antes de que Chrome esconda el cluster entero).

Es el mismo patrón que el §2: un fichero central que hay que tocar por cada
módulo. Y el mismo arreglo: que el módulo se apunte.

    ns.Cmd:Register("bar", handler, "ayuda de una línea")

Con el añadido de que **la ayuda vive hoy en una tabla separada de los
manejadores** (`HELP` arriba, las ramas abajo), así que se pueden desincronizar
— y de hecho hubo que tocarlas por separado al vaciar la sala: las líneas de
ayuda en un sitio del fichero y las ramas en otro.

**Prioridad baja.** Funciona, y 39 ramas siguen siendo legibles. Pero es la
segunda mitad de la pregunta del §4: *¿qué tiene que editar alguien que añade un
módulo?* Hoy: el `.toc`, `Core.lua` dos veces y `Bar.lua`. Debería ser el
`.toc`.

---

## 7. SavedVariables: 34 claves planas, sin versión

**34 claves de primer nivel vivas, escritas desde 16 ficheros**, sin espacio de
nombres y sin sello de versión.

Esto **ya ha costado cuatro veces**, todas documentadas:

- `grow = 688` (etapa 5j) — un valor de una versión anterior que como número de
  copias no significaba nada, y que sin acotarlo **al leer** habría dado una
  barra de ocho paneles diminutos sin nada que dijera por qué.
- `camHold` — sobrevivió a la función que lo leía y **rearmaba una función
  borrada** en cada entrada al modo RTS.
- `railCropGen` (etapa 5o) — hizo falta inventar un **sello de generación por
  clave**, porque lo guardado era un índice válido cuyo *significado* había
  cambiado. Comprobar el rango no basta cuando lo que se mueve es lo que el
  número quiere decir.
- Y hoy, la cuarta: cinco claves de la sala tiradas a mano en `Core.lua`.

El `railCropGen` es la señal que importa: **ya se construyó a mano, para una
clave, el mecanismo que hace falta para todas.**

**Qué haría.** Lo mínimo que cierra el patrón:

    RTSCommandDB.version = 3      -- sube cuando cambia el significado de algo
    RTSCommandDB.bar = { ... }    -- una tabla por módulo, ya lo hacen 6 de 16

y una migración en `Core.lua` que borre lo que no reconozca. Hoy hay seis
módulos que ya agrupan (`bar`, `hud`, `skin`, `flareCfg`, `routeCfg`,
`camFrame`) y diez que no. No es urgente, pero es el fallo que más veces se ha
repetido en todo el proyecto.

---

## 8. Veinte `OnUpdate` y un latido compartido con un solo usuario

    grep -rn 'SetScript("OnUpdate"' addon/*.lua | wc -l   # 20, en 12 ficheros

`Widgets.lua:219` tiene `W:Every(fn)`, un latido compartido de 5 Hz con `pcall`
por suscriptor, y su comentario explica exactamente por qué:

> *UN SOLO OnUpdate, no uno por panel. Cinco OnUpdate con su propio acumulador
> son cinco sitios donde ajustar el ritmo y cinco veces el coste de la llamada.*

Tenía cinco usuarios. Cuatro eran paneles de la sala. **Hoy le queda uno**
(`Standby.lua`), y los otros 19 `OnUpdate` del addon nunca lo usaron. La mitad
sí necesitan ser suyos — la cámara y el ratón corren a 100 Hz — pero `Route`,
`Markers`, `Chrome` y `Channel` son sondeos periódicos que podrían compartirlo.

**No es un problema de rendimiento** a esta escala; es que el ritmo de refresco
está en 20 sitios. Lo apunto porque la sala nueva va a añadir varios, y sería
buen momento para que nazcan ya en el latido.

---

## 9. El número de protocolo del DLL, en dos sitios

    Channel.lua:61         local PROTOCOL = 3
    Channel.lua:115        if RTS_PROTO ~= PROTOCOL then return nil end
    SelectionRing.lua:121  if RTS_PROTO and RTS_PROTO ~= 3 then   -- <- literal

El diseño del canal es explícito en que **los dos lados se niegan a decodificar
el protocolo del otro**, *"así que una instalación a medias se queda callada en
vez de disparar mal"*. Es la decisión correcta.

Pero el número está escrito dos veces y una de ellas es un literal. Al subir a
4, `Channel` se callará y `SelectionRing` seguirá creyendo que el 3 es el bueno
— o al revés. **Es una constante duplicada dentro de la única comprobación cuyo
trabajo es detectar una desincronización.**

Arreglo: `ns.Bridge:Protocol()`, o una constante exportada. Cinco minutos.

---

## 10. `check_addon.py` debería mirar `Bindings.xml`

Encontrado hoy: diez `RTSCOMMAND_SLOT1..10` apuntando a
`RTSCommand_CommandSlot`, una global inexistente desde que se borró
`CommandMode.lua` el 24 de agosto. Da un error de Lua al pulsar la tecla, y sólo
si el jugador la había asignado.

    for f in $(grep -o "RTSCommand_[A-Za-z]*" addon/Bindings.xml | sort -u); do
      grep -q "^function $f" addon/Core.lua || echo "MISSING: $f"
    done

Misma familia que las dos comprobaciones que se le añadieron en la etapa 5m: un
fallo que no da error hasta que es tarde, y que el comprobador puede ver gratis.

---

## 11. El lado C++ está mejor que el Lua

Merece decirse, porque la intuición sería la contraria.

`mod_rts.cpp` son 1.241 líneas con un `if (verb == ...)` de unos 30 verbos —
misma forma que el §2 y el §6. **Pero delega de verdad**: los cuatro espacios de
nombres (`rts::camera`, `rts::orders`, `rts::command`, `rts::marks`) están en sus
propios ficheros con cabecera, `mod_rts.cpp` es transporte y despacho, y los
ganchos de ciclo de vida (`OnPlayerLogout`, `OnPlayerUpdateZone`) llaman a los
cuatro por igual.

O sea: la separación que le falta al addon, el módulo de servidor sí la tiene.
El despacho largo es un inconveniente de lectura, no un acoplamiento — añadir un
verbo toca `mod_rts.cpp` y **un** fichero de dominio, no cuatro.

**No lo tocaría.** Son 4.400 líneas que funcionan, y el §13 del documento de la
sala explica por qué los verbos huérfanos se quedan.

---

## 12. Lo que NO hay que tocar

Tan importante como la lista de arriba. Un "vamos a modularizar" mal dirigido
rompe esto:

- **El contrato de `Bar.lua`** (`SlotFrame`/`Cells`/`OnLayout`). Es lo mejor
  diseñado del addon, y la prueba está en que vaciar la sala **no tocó ni
  `Panel.lua` ni `Rails.lua`**. La sala nueva se cuelga de ahí tal cual.
- **`Selection:Subscribe`.** Un registro con `pcall`, bien hecho, y el sitio
  correcto para que la sala nueva se entere de los cambios.
- **La regla dura de capturar y devolver** (`Camera` con sus CVars, `Chrome` con
  los frames de Blizzard). Está aplicada con cuidado y con los casos de combate
  resueltos. No es burocracia: cada una de esas líneas viene de un fallo real.
- **La salida en dos mitades** (`LeaveWorld` / `LeaveChrome`) y su guarda de
  cancelación. El orden está razonado línea a línea.
- **`sim/`.** Los guiones de Python que reproducen la aritmética fuera del juego
  han cazado cinco fallos antes de compilar. Cualquier reparto nuevo de la sala
  se simula ahí primero.
- **Los comentarios.** Este addon documenta el *porqué* — incluidos los intentos
  fallidos — mejor que la mayoría del software profesional. Un refactor que los
  pierda destruye más valor del que crea. Al mover código, se mueve su
  comentario.

---

## 13. Qué haría antes de rellenar la sala

Por orden de rentabilidad. Los cuatro primeros son **mecánicos y sin cambio de
comportamiento**: no necesitan ronda de pruebas, sólo `check_addon.py` y un
arranque.

| | Qué | Por qué ahora | Tamaño |
|---|---|---|---|
| 1 | **`ns.WhenServer(fn)`** (§3) | Cuatro copias escritas; la quinta la escribe la sala nueva | 5 líneas |
| 2 | **`Link.lua`: sacar el canal de `Camera`** (§2) | La sala nueva es el mayor consumidor de verbos del addon | ~1 h |
| 3 | **`Bar:Register(panel)`** (§4) | Es el único sitio donde la sala nueva tendría que editar el fichero del arte | 15 min |
| 4 | **`Bridge`: cámara, lista de unidades y protocolo** (§1, §9) | 98 lecturas crudas crecen con cada panel nuevo | ~2 h |
| 5 | `check_addon.py` mira `Bindings.xml` (§10) | Gratis, y hoy ha encontrado uno | 15 min |
| 6 | SavedVariables con versión (§7) | Cuatro purgas ya; la sala nueva guardará configuración | ~1 h |
| 7 | Sacar botín y selfbot de `RTSMode` (§5) | Sólo si se va a tocar `RTSMode` de todas formas | — |
| 8 | `Cmd:Register` (§6) | Cómodo, no urgente | — |

**El 1, 2 y 3 son los que cambian cómo se escribe la sala nueva.** Los demás
pueden esperar a que haya algo que probar.

Y una recomendación de método, que sale de las últimas cinco etapas: **el
rediseño de la sala se simula en `sim/bar_layout.py` antes de compilar nada.**
Ha cazado un fallo en cada ronda desde la 5k, incluida la de hoy, y es la única
prueba de este proyecto que no necesita entrar al juego.

El presupuesto con el que se empieza, que el propio guión imprime ya:

| `grow` | sala, dibujo | sala, píxeles en 2560x1440 |
|---|---|---|
| 1 | 710 x 344 | 399 x 193 |
| 2 | 1222 x 344 | 687 x 193 |
| 3 | 1734 x 344 | 975 x 193 |
| **4** (el que sale a pantalla completa) | **2246 x 344** | **1263 x 193** |
| 5 | 2758 x 344 | 1551 x 193 |

**El alto no depende de `grow` y nunca lo hará** — lo fija el arte. Es la
restricción dura del rediseño, y el guión la comprueba con un `assert` para que
no se descubra a mitad de camino.

---

## 14. Lo hecho, 2026-09-02. Addon 0.50.0

Los tres primeros del §13. **Nada de esto cambia lo que hace el addon** — es
mover código y unificar cuatro copias de un bucle — salvo un fallo real que
apareció por el camino y que sí lo cambia (14.4).

### 14.1 `Link.lua`: el canal, fuera de la cámara (§2)

Fichero nuevo, segundo del `.toc`. Se lleva `ns.SendServer`, el frame de
`CHAT_MSG_ADDON`, `serverSeen`, `serverVersion` y el `debug` del canal. Los doce
verbos que `Camera.lua` repartía se han ido **cada uno a su dueño**:

| verbo | ahora vive en |
|---|---|
| `CAM`, `CAMPOS` | `Camera.lua` (los suyos de verdad) |
| `WHAT` | `RTSMode.lua` |
| `DID` | `Orders.lua` |
| `POS`, `GROUNDAT`, `GROUNDNO` | `Route.lua` |
| `MARKAT`, `MARKQ`, `MARKERR`, `MARKNO` | `Marks.lua` |
| `VER` | `Link.lua` |

Y con ellos se fue el `PLAYER_LEAVING_WORLD` que le decía a `Marks` que olvidara
sus dynobjects: estaba en el frame del canal, o sea en el único fichero donde
`Marks` no pinta nada. Ahora `Marks` tiene su propio frame para eso.

**El reparto es por VERBO, no por expresión regular.** La versión anterior
probaba doce regex completas en orden; ahora se corta la primera palabra y se
busca en una tabla. Además de ser más barato, da lo que la cadena no podía dar:
**decir que llegó un verbo que no escucha nadie** (`/rts debug`). Eso importa
justo ahora — mod-rts sigue contestando siete verbos de la sala borrada que se
van a volver a usar al rediseñarla.

### 14.2 Dos trampas del transporte, y una la introduje yo

- **Nos susurramos a nosotros mismos, así que oímos de vuelta cada petición.**
  Mi primera versión marcaba `serverSeen` con *cualquier* mensaje entrante — o
  sea que nuestro propio `VERSION` rebotando lo habría puesto a cierto **sin
  mod-rts instalado**, y entonces `Orders` mandaría por un canal que no escucha
  nadie en vez de caer al respaldo por chat. Silencioso y total. Cazado antes de
  compilar, releyendo lo que el propio fichero decía del transporte.

  El arreglo es la tabla `REPLY_ONLY`: ocho verbos que **nosotros no decimos
  nunca**. Comprobado contra la lista real de lo que manda el addon — cero
  solapes.

- **Cuatro verbos se dicen igual en los dos sentidos** (`CAM`, `POS`, `WHAT`,
  `MARKQ`), así que "casa con un manejador" tampoco vale como prueba: nuestro
  propio `WHAT <guid>` casa con el manejador de `WHAT`. Lo que los distingue es
  el FORMATO, y por eso cada manejador valida el suyo — que es exactamente lo
  que hacían las regex de antes sin que se notara que ése era su segundo
  trabajo. Los cuatro están comprobados uno a uno.

### 14.3 `WhenServer` y `Bar:Register` (§3, §4)

`ns.Link:WhenServer(fn)` sustituye las **cuatro copias** del mismo
`si contesta o han pasado 2,5 s` (dos vivas, dos que se fueron con la sala). Con
dos cosas que las copias no tenían: **reutiliza los frames** — sin mod-rts, cada
entrada en modo RTS creaba uno que giraba y se quedaba muerto para siempre — y
le dice a `fn` si contestó o si venció el plazo, que es lo que necesita quien
tiene camino de respaldo.

La guarda de `R.active` del botín **se queda en el llamante** y no subió a la
función común: si sales del modo mientras se espera, la estrategia de botín ya
no se quiere. Es específica de ese sitio.

`Bar:Register(m)` cierra la otra mitad del contrato de la barra: `Panel.lua` y
`Rails.lua` **se apuntan solos** desde su propio fichero. `Bar.lua` ya no nombra
a ningún panel, así que la sala nueva no tiene que tocar el fichero del arte.

### 14.4 Y un fallo de verdad, que estaba ahí desde antes

Al mudar el canal apareció que `Camera:Create()` terminaba con:

    self.frame = f      -- f es el frame de eventos

y `C.frame` **es la tabla de encuadre** — `tilt`, `zoom`, `fov`, `shadow` y los
dos topes de zoom — que ese mismo `Create` acababa de rellenar desde las
SavedVariables. La machacaba entera. Lo que rompía, en silencio:

- **`cfg.fov` salía nil**, así que el CVar prestado se escribía a 0, que
  significa *"no toques el FOV"*. **La cámara isométrica de la etapa 5g no se
  aplicaba nunca.**
- `cfg.maxFactor` y `cfg.distanceMax` nil: los topes de zoom no subían.
- `cfg.shadow` nil: las sombras de la etapa 5o no se ponían.
- `cfg.tilt`/`cfg.zoom` nil en el camino **sin** encuadre guardado.

**Por qué nadie lo vio en cuatro etapas, que es la parte que vale:** con un
encuadre guardado, `C:Frame()` sale por `SetView(VIEW_SLOT)` antes de llegar a
usar tilt y zoom — así que la cámara se veía bien. Y `C:Report()` lee
`tonumber(f.tilt) or tonumber(d.tilt)`, o sea que **caía a `DEFAULTS` y
imprimía los valores correctos mientras no se aplicaba ninguno**.

Un lector que miente en la dirección tranquilizadora es peor que uno que no
existe. Es la misma forma que `check_addon.py` diciendo "los 28 ficheros están
bien" sobre una cadena rota (etapa 5m), y que `GetActionInfo` devolviendo un
hechizo cualquiera en vez de un error (etapa 5o).

El frame se llama ahora `self.events`. **Es lo único de esta sesión que cambia
comportamiento en juego, y hay que mirarlo:** el FOV, los topes de zoom y las
sombras deberían aplicarse ahora y llevaban tiempo sin hacerlo.

### 14.5 `sim/load_order.py`, nuevo

Que los paneles se apunten solos quita un acoplamiento y **a cambio crea una
dependencia de orden**: `ns.Bar:Register(P)` corre al CARGAR `Panel.lua`, así
que si el `.toc` lo pusiera antes que `Bar.lua` sería un `nil` — y un error al
cargar se lleva por delante todo lo que venga detrás, no sólo ese módulo.

`check_addon.py` no lo puede ver: mira cada fichero por separado, y ésta es una
pregunta sobre los 24 **en el orden en que los carga el juego**. El guion nuevo
recorre el `.toc` comprobando que todo `ns.X` usado en ámbito de fichero ya
existe. Hoy: 29 usos, todos correctos.

Dos detalles que costaron una pasada:

- **El cuerpo de una función no cuenta.** La primera versión daba cinco falsos
  positivos en `Orders.lua`, todos dentro del manejador de `DID` — que corre
  cuando llega el mensaje, no al cargar. Un falso positivo aquí sería peor que
  no tener guion: se aprende a ignorarlo.
- **Tiene dientes**, comprobado moviendo `Panel.lua` delante de `Bar.lua`: dice
  `Panel.lua -> ns.Bar no existe todavía`. Se rompió a propósito una vez, como
  `route_advance.py`.

### 14.6 Qué NO está verificado

Nada de esto se ha visto en juego. Lo que sí se ha comprobado desde fuera:

- `check_addon.py`: los 24 ficheros.
- `sim/load_order.py`: el orden del `.toc` aguanta.
- Los otros tres `sim/` siguen pasando.
- Cero referencias colgando a lo movido (`ns.Camera.debug`, `.serverVersion`,
  `.serverSeen`, `Panels()`, `message:match`).
- `REPLY_ONLY` contra la lista real de verbos que manda el addon: sin solapes.
- Los cuatro verbos de doble sentido validan su formato.

Lo que hay que mirar en juego, por orden de riesgo:

1. **El FOV, los topes de zoom y las sombras** (14.4) — es lo único que cambia
   de comportamiento, y cambia hacia lo que siempre debió hacer.
2. Que `server module attached` siga saliendo al entrar, y **que no salga** si
   se arranca sin mod-rts.
3. Que las marcas de suelo, las rutas, el botín y `/rts version` sigan igual —
   son los verbos que cambiaron de fichero.
