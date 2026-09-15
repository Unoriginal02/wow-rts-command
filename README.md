# RTS Command

Capa de control estilo RTS (Warcraft 3 / StarCraft) para un servidor privado de
World of Warcraft 3.3.5a con AzerothCore + mod-playerbots.

Coges a tus alts, los metes de bots, y el juego pasa a jugarse desde arriba:
cámara libre, selección por caja, órdenes con el ratón, y la barra de abajo
mandando a todo el grupo. Lo que en WoW no existe —ver las bolsas de un
compañero, su registro de misiones, hablar con el entrenador *siendo él*— se
dibuja aquí.

**Aquí se trabaja.** Esta carpeta es el original de las tres piezas. Lo que hay
en el WoW y dentro de AzerothCore son copias desplegadas.

| Pieza | Versión | Qué es |
|---|---|---|
| `addon/` | 1.31.0 | Addon Lua: interfaz, selección, órdenes, cámara |
| `mod-rts/` | 0.52.0 | Módulo de AzerothCore: órdenes directas a la IA, quests, bolsas, PNJ, swap |
| `rts-client-mod/` | `rts_core.dll` 0.29.0 | Inyectado en el cliente: coordenadas, raycast, efectos nativos |

```
Cliente WoW  <->  worldserver (+ mod-rts + mod-playerbots)  <->  MySQL
     ^
     +-- addon RTSCommand   (interfaz, selección, órdenes)
     +-- rts_core.dll       (solo local: coordenadas, raycast, efectos nativos)
```

---

## Índice

1. [Empezar](#1-empezar)
2. [Dónde está cada cosa](#2-dónde-está-cada-cosa)
3. [Las funciones, por áreas](#3-las-funciones-por-áreas)
4. [Lo que le tocamos al cliente y al núcleo](#4-lo-que-le-tocamos-al-cliente-y-al-núcleo)
5. [Desplegar y compilar](#5-desplegar-y-compilar)
6. [Reglas del repositorio](#6-reglas-del-repositorio)

---

## 1. Empezar

1. `C:\Server\rts-tools\1_Iniciar_Servidor.bat` — levanta el worldserver.
2. `C:\Server\rts-tools\2-Jugar.bat` — abre el WoW **e inyecta `rts_core.dll`**.
   Sin esto no hay cámara libre ni click al suelo: el addon se niega a arrancar
   la cámara en vez de fingir que va.
3. Dentro, con un personaje: pon la orden **Traer bots** en una casilla de la
   bandeja (o escribe `/rts invitar`) y entra en modo RTS con `/rts mode`.
4. `/rts` a secas imprime la ayuda entera, unas sesenta líneas.

La lista de bots que trae `invitar` se cambia con
`/rts invitar lista Neferite,Kirinah,Avy`.

---

## 2. Dónde está cada cosa

### El ratón, en modo RTS

| Gesto | Qué hace |
|---|---|
| Clic izquierdo en una unidad | seleccionarla (**shift** añade o quita) |
| Arrastrar izquierdo en el suelo | selección por caja |
| Clic izquierdo en suelo vacío | deseleccionar |
| **Alt** + clic en una unidad | tomar control directo de ella |
| Clic derecho en el suelo | mandar ahí a la selección |
| Clic derecho en un enemigo | atacarlo |
| Clic derecho en un PNJ | interactuar |
| **Shift** + clic derecho | encadenar un punto de ruta más |
| **Shift** + clic izquierdo en hostil | ponerle número de cadena de ataque (1..8) |
| Arrastrar derecho | girar la cámara (mouselook nativo del cliente) |
| Izquierdo + derecho a la vez | avanzar, el gesto de siempre |
| Clic en un marco de grupo de Blizzard | seleccionarlo, con las mismas reglas |

### El teclado

La cámara libre se queda ocho teclas mientras dura el modo RTS, y **las
devuelve al salir** —se apuntan antes de tocarlas y no se guardan nunca, así
que una desconexión no te deja sin WASD.

| Tecla | En modo RTS |
|---|---|
| `W A S D` | mover la cámara en el plano horizontal |
| `ESPACIO` / `C` | subir y bajar |
| `Q` / `E` | girar |

Lo demás se asigna en **Opciones → Teclas → RTS Command**: entrar y salir del
modo, cámara, seleccionar todo, limpiar selección, las cinco órdenes
(mover/quieto/seguir/atacar/attack-move), seleccionar la unidad 1..8, los diez
huecos de hechizo, las bolsas del grupo, y cuatro grupos de control
(**Alt + tecla** guarda el grupo, la tecla sola lo recupera).

### La barra de abajo

```
+---------------------------------------------------------------+
|              Bob  (dps)                                       |
|        [1][2][3][4][5][6][7][8][9][0]    [M][M][M][M][M]      |
|                                          [M][M][M][M][M]      |
|                                          [bolsas del juego]   |
|                                          [ficha][talentos]... |
+---------------------------------------------------------------+
```

- **En el centro, la unidad.** Con uno cogido (o ninguno, y entonces eres tú):
  su nombre y **diez huecos de hechizo**. Con dos o más: una columna por cabeza
  con un 2x2 de **cuatro** —que son *otra lista*, la de lo que se manda en
  grupo, no los cuatro primeros de los diez.
- **A la derecha, lo tuyo,** y no se mueve nunca: diez casillas, las bolsas y
  el menú de juego.

### Las diez casillas de la bandeja

Cada casilla admite dos cosas distintas:

| Gesto | Qué hace |
|---|---|
| Clic derecho | el desplegable con el catálogo de órdenes del addon |
| Arrastrar un macro encima | pone ese macro (hace falta para `/cast`, `/use`, `/target`) |
| Clic izquierdo | lanza lo que lleve |

El catálogo (`/rts ordenes`) trae: **Traer bots**, **Sígueme**, **Quieto**,
**Reunir**, **Cráneo**, **Luna**, **Reset grupo**, **Control**, **Bolsas**,
**Misiones**, **Candado**, **Cámara** y **Modo RTS**. Los iconos propios son
arte nuestro, no de la lista cerrada del cliente.

> **La excepción:** una orden puede llevar **segunda orden** en el clic derecho.
> Hoy solo la lleva el **Candado**: izquierdo clava la cámara sobre el héroe,
> **derecho la mete dentro de su cabeza**. En esas casillas el desplegable se
> aparta a **Mayús + derecho**, y el tooltip lo dice.

---

## 3. Las funciones, por áreas

Cada fila dice **dónde vive**. El porqué de cada decisión —callejones sin
salida incluidos— está en la cabecera del fichero que la implementa.

### 3.1 La cámara

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| **Cámara libre RTS** — vuela en el plano, sube y baja, sigue el suelo | `/rts mode`, `/rts cam` | `addon/FreeCam.lua` |
| **Candado** — clava la cámara a una distancia fija del héroe y viaja con él | casilla Candado, `/rts fc lock` | `addon/FreeCam.lua` |
| **Primera persona** — la cámara dentro de la cabeza del héroe: solo mirar, no mover | clic **derecho** en el Candado, `/rts fc ojos` | `addon/FreeCam.lua` |
| **Salida de emergencia** — devuelve la cámara sobre tu héroe | `/rts fc home` | `addon/FreeCam.lua` |
| **El suelo no es "lo primero que hay debajo"** — un tejado deja de contar, así que se puede entrar en las casas | `/rts fc floor 1` | `addon/FreeCam.lua` |
| **Filtro de escalón** — una cuesta se sigue de cerca, un escalón se sube despacio | `/rts fc climb/soft/slow` | `addon/FreeCam.lua` |
| **Sin colisión** — la cámara atraviesa geometría (cuevas) | `/rts fc noclip 1` | `addon/Camera.lua` |
| **Punto en el mapa** — dónde está mirando la cámara, en el mapa del mundo | `/rts punto` | `addon/Radar.lua` |
| **Encuadre guardado** — tilt, zoom, FOV, sombras | `/rts cam save/frame/fov/shadow` | `addon/Camera.lua` |
| **Cámara poseída** (el camino viejo, sigue ahí) | `/rts cam` sin DLL | `mod-rts/src/RtsCamera.cpp` |

Los ajustes de tacto (`speed`, `lift`, `turn`, `height`, `smoothZ`, `ease`,
`pitch`, `clear`, `push`, `lockSmooth`, `eyeH`…) son **por personaje** y se
listan con `/rts fc`.

### 3.2 La selección

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| Selección por nombre, no por token | — | `addon/Selection.lua` |
| Caja de selección | arrastrar izquierdo | `addon/RTSMode.lua` |
| Grupos de control (4) | Alt+tecla guarda, tecla recupera | `addon/Selection.lua` |
| **Aro nativo bajo lo seleccionado** — el círculo del propio cliente, con profundidad correcta | `/rts ring` | `addon/SelectionRing.lua` + `rts-client-mod/src/Circle.cpp` |
| **Brillo del modelo por estado** — azul en espera, verde andando, rojo peleando, naranja interactuando | `/rts state`, `/rts ring tint` | `addon/State.lua` + `rts-client-mod/src/Highlight.cpp` |
| Los marcos de unidad del juego seleccionan al pincharlos | clic en el marco | `addon/Portraits.lua` |

### 3.3 Órdenes y movimiento

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| Mover / quieto / seguir / atacar / attack-move | ratón, teclas, `/rts move`, `hold`, `follow`, `attack`, `amove` | `addon/Orders.lua` |
| **Órdenes directas a la IA**, sin pasar por el chat | automático | `mod-rts/src/RtsOrders.cpp` |
| **Rutas de varios puntos** | Shift + clic derecho | `addon/Route.lua` |
| **Marcador de suelo de cada punto**, dibujado por el cliente | `/rts mark next/prev/find/size` | `addon/Marks.lua` + `mod-rts/src/RtsMarks.cpp` |
| **Destello de "ve aquí"** | automático al ordenar | `addon/Flare.lua` |
| **Ataque encadenado** — marcas 1,2,3,4 y van en orden | Shift + clic izquierdo en hostil, `/rts chain` | `addon/Chain.lua` + `mod-rts/src/RtsChain.cpp` |
| Formaciones | `/rts form near/far/melee/queue/chaos/circle/line/shield/arrow` | `addon/Orders.lua` |
| Reunir (andando) y Traer (teletransporte) | `/rts reunir`, `/rts traer` | `addon/Actions.lua` |
| Marcas de cráneo y luna con orden incluida | `/rts craneo`, `/rts luna` | `addon/Core.lua` |
| Cualquier verbo crudo de playerbots | `/rtscmd <cmd>` (selección), `/rtsall` (grupo) | `addon/Orders.lua` |
| **Tu propio personaje pelea con la IA de playerbots** | `/rts self`, `/rts self auto` | `addon/RTSMode.lua` |

### 3.4 Los hechizos

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| Diez huecos configurables por personaje, más cuatro de grupo | clic derecho en un hueco, `/rts skills` | `addon/Skills.lua` (datos) + `addon/Cast.lua` (dibujo) |
| **Cola de hechizos** — pulsar mientras el bot está ocupado lo deja esperando en vez de fallar | automático | `mod-rts/src/RtsQueue.cpp` |
| **Cuidar** — el seleccionado cuida de quien pinches | `/rts focus` / `/rts unfocus` | `addon/Cast.lua` |
| **Lanzar un hechizo COMO el bot** — el servidor lo lanza por él, con su cola y sus comprobaciones | clic en un hueco | `mod-rts/src/RtsCommandMode.cpp` |
| **Su barra de acción de verdad** — la que tú montaste jugando ese personaje, leída de `character_action` | al seleccionarlo | `mod-rts/src/RtsCommandMode.cpp` |
| **Espejo de hechizos** al salir del modo RTS en combate | automático | `addon/Standby.lua` |

> `RtsCommandMode.cpp` guarda además verbos que hoy **no llama nadie** —`AIM`,
> `ROLES`, `TGTS`— de cuando existía la consola de una pieza. Están vivos en el
> servidor y sin boca en el addon: si un día vuelve esa interfaz, el backend ya
> está. No los listo como funciones porque hoy no lo son.

### 3.5 El grupo entero, lo que WoW no enseña

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| **Bolsas de todo el grupo**, y pasar objetos sin ventana de intercambio | `/rts bags`, casilla Bolsas | `addon/Bags.lua` + `mod-rts/src/RtsBags.cpp` |
| **Registro de misiones de todo el grupo** | `/rts quests`, casilla Misiones | `addon/QuestBook.lua` + `mod-rts/src/RtsQuests.cpp` |
| **Compartir misión que funciona** — el servidor se la *da*, no la ofrece | botón Compartir del registro nativo | `addon/Quests.lua` |
| **Al entregar tú, el grupo completa y cobra** | `/rts quests force` | `mod-rts/src/RtsQuests.cpp` |
| **Entrenador y vendedor, siendo el bot** | `/rts npc` | `addon/Npc.lua` + `mod-rts/src/RtsNpc.cpp` |
| Aprender todo lo que el entrenador le vendería | botón en la ventana de PNJ | `mod-rts/src/RtsTrain.cpp` |
| Vender la basura gris, reparar | botones en la ventana de PNJ | `mod-rts/src/RtsNpc.cpp` |
| **Cambiar de personaje sin cerrar sesión** — el que dejas se queda de bot | `/rts swap <nombre>` | `mod-rts/src/RtsSwap.cpp` |
| Botín libre del grupo / que recojan todo | `/rts loot`, `/rts lootall` | `addon/RTSMode.lua`, `addon/Loot.lua` |
| **Esconder el volcado de menús de los bots** (y guardarlo) | `/rts chat`, `/rts chat ver` | `addon/Chatter.lua` |

### 3.6 La interfaz

| Función | Cómo se usa | Dónde vive |
|---|---|---|
| Reparto de la barra de abajo | `/rts dock` | `addon/Dock.lua` |
| Bandeja de diez casillas + bolsas + menú de juego | `/rts tray`, `/rts tray vaciar` | `addon/Tray.lua` |
| Catálogo de órdenes con icono propio | `/rts ordenes` | `addon/Actions.lua` |
| Sacar el catálogo a macros **del juego** (para barras y teclas) | `/rts macros` | `addon/Macros.lua` |
| Ocultado selectivo al entrar en modo RTS (de fábrica, solo las barras de acción) | `/rts ui` | `addon/Chrome.lua` |
| Ventanas flotantes (una implementación, tres inquilinos) | `/rts win`, `/rts win reset` | `addon/Window.lua` |
| Aspecto WC3 o plano, con texturas del propio cliente | `/rts skin`, `/rts skin wall <ruta>` | `addon/Skin.lua` |
| **Visor de texturas del cliente** | `/rts art` | `addon/Art.lua` |
| Escala de píxel | — | `addon/Pixels.lua` |
| Brillo de la marca de selección de los retratos | `/rts marcos brillo 0.9` | `addon/Portraits.lua` |

### 3.7 Diagnóstico

Casi todos existen porque un fallo concreto costó una tarde. Cada uno contesta
**una** pregunta.

| Comando | Qué contesta |
|---|---|
| `/rts native` | ¿está el DLL inyectado y sus offsets son los buenos? |
| `/rts version` | versiones de las tres piezas |
| `/rts cam probe` | ¿sirve la cámara libre del cliente aquí? paso a paso |
| `/rts fc` | estado de la cámara libre: suelo, rayos, colisión, medida del yaw |
| `/rts fc mouse` | ¿llega el giro nativo, o lo estamos pisando? |
| `/rts aim` | por qué el punto de suelo cae donde cae (cursor vs. rayo del DLL) |
| `/rts cal` | mide la proyección (arregla aros que quedan cortos) |
| `/rts turn` | por qué un clic se pierde: mide el giro de cámara contra el umbral |
| `/rts channel` | qué se le está contando al DLL sobre tu selección |
| `/rts pick` | qué hay bajo el cursor |
| `/rts debug` | eco de todo lo que va y viene del módulo de servidor |
| `/rts bars` | qué tiene el SERVIDOR en tus doce primeras casillas de acción |
| `/rts body` | **sonda del cuerpo**: por qué tu héroe se vuelve invisible |

---

## 4. Lo que le tocamos al cliente y al núcleo

Esta es la parte que no se ve. Nada de aquí es un reemplazo: en casi todos los
casos **el juego ya sabía hacerlo** y lo que faltaba era la puerta.

### 4.1 La cámara de comentarista (la "spectator cam")

Este cliente trae una cámara libre completa, con API de Lua, que Blizzard puso
para retransmitir arenas. Es la cámara del modo RTS desde el 2026-09-07.

**Lo que existe de serie:** `CommentatorSetCamera`, `CommentatorGetCamera`,
`CommentatorSetCameraCollision`, `CommentatorSetMoveSpeed`,
`CommentatorFollowPlayer`, `CommentatorSetTargetHeightOffset`,
`CommentatorZoomIn`, `CommentatorZoomOut`.

**La puerta son dos bits de `PLAYER_FLAGS`.** El predicado del cliente en
`0x006DE980` contesta "este jugador es espectador" leyendo el bit 19
(`PLAYER_FLAGS_UBER`, 0x00080000) y el bit 22 (`PLAYER_FLAGS_COMMENTATOR2`,
0x00400000). Con el 19 apagado devuelve `false` y no hay cámara.

| Quién pone qué | Por qué |
|---|---|
| El **servidor** pone el bit 22 | `Player::SetCommentator`, que ya existe en el núcleo. Es el que salta el requisito de estar en un mapa de arena |
| **`rts_core`** escribe el bit 19 en la copia del cliente | el núcleo **se niega a dejar atacar** a quien lleve `UBER` (`Unit.cpp:10762`), así que ponerlo en el servidor te dejaba sin pegar |

**Armar el modo lo hace el servidor.** El cliente pide el modo con
`CMSG_COMMENTATOR_ENABLE` (0x3B5) y espera `SMSG_COMMENTATOR_STATE_CHANGED`
(0x3B6). Ese opcode de entrada es `STATUS_NEVER` en AzerothCore —ni siquiera
llega al manejador— así que el addon lo pide por su propio canal y **mod-rts
manda el 0x3B6** directamente. El manejador del cliente (`0x0056B8A0`) exige
que el GUID sea el suyo, vuelve a pasar por el predicado, y mete la cámara
activa en modo comentarista.

**Y va en dos mitades, que es lo que costó la primera pasada.** `Spectate` pone
los flags; `Arm` manda el paquete. Hacerlo de golpe es una carrera:
`SetPlayerFlag` solo marca el campo sucio (sale ~100 ms después) mientras que
`SendPacket` sale ya. El paquete llegaba primero, el predicado leía los flags
viejos, y la rama de puerta cerrada **no es un no-op**: mete la cámara en modo 1
con el estado que hubiera. En pantalla: la cámara se iba lejísimos y bajo el
suelo. Ahora el addon sondea `CommentatorGetCamera()` —que devuelve seis números
solo con la puerta abierta— y **solo entonces** pide armar.

**El reparto de mandos:**

- **Nosotros llevamos la POSICIÓN.** Una escritura por frame,
  `CommentatorSetCamera(x, y, z, yaw, pitch, fov)`.
- **El cliente lleva la ORIENTACIÓN.** El arrastre derecho es el mouselook de
  siempre, con la sensibilidad y la inversión que ya tiene configuradas el
  jugador. Como `SetCamera` toma los seis valores de golpe, cada frame se
  **leen** los ángulos vivos y se **reescriben tal cual**: para la orientación
  es un no-op y el giro del cliente se acumula solo.
- `CommentatorSetMoveSpeed(0)` apaga el motor de WASD del propio cliente, para
  que no haya dos dueños del movimiento.

**Detalles que costaron una pasada cada uno:**

| Cosa | Lo medido |
|---|---|
| El FOV | sexto argumento, en **grados**, acotado 1..120. Pasar 0 son **un grado** = pantalla morada |
| El *pitch* | **positivo mira abajo**. Es al revés de lo que parece, y no se puede leer del binario |
| La colisión | `CommentatorSetCameraCollision` toma un **número**, no un booleano, aunque su texto de uso diga `bool`. Se devuelve a 1 al salir: es lo que el cliente escribe al arrancar |
| Yaw y pitch vivos | `cam+0x11C` y `cam+0x120`, en radianes, sobre la cámara activa |
| La convención del yaw | **no se puede leer del binario.** Así que la primera persona no la adivina: la mide en vivo comparando el yaw de `CommentatorGetCamera` con el adelante en coordenadas de mundo que publica el DLL |

**El efecto secundario: tu propio modelo desaparece.** Los flags que abren la
cámara también hacen que el cliente deje de emitir tu personaje. El predicado
`0x006DE980` tiene **dieciocho** sitios de llamada (medidos con un barrido de
`call rel32` sobre el `.text`, no supuestos), así que forzar el predicado
escondió a *todo el mundo*. El culpable se encontró **por eliminación**: es el
sitio `[16]`, `0x006E085C`, dentro de una función virtual sin ninguna
referencia estática. `SelfShow.cpp` parchea esos cinco bytes
(`call rel32` → `xor eax,eax` + 3 `nop`, mismo tamaño) para que *ese* llamante
vea "no es espectador", y los otros diecisiete sigan contestando la verdad.

> `addon/Body.lua` es la sonda que lo acorraló, y sigue ahí apagada de fábrica.

**El camino viejo sigue existiendo:** una criatura invisible que el jugador
posee, que es el mecanismo del Ojo de Kilrogg y del Control Mental
(`Player::SetClientControl` → `SetViewpoint` + `SetMover`). Está en
`mod-rts/src/RtsCamera.cpp` y se abandonó porque, poseyendo, **el cliente es el
dueño de la posición** y desde el servidor solo se la mueve con
`NearTeleportTo`, que cancela el movimiento en curso.

### 4.2 Efectos nativos del cliente, reutilizados

Todo lo que dibuja una textura de interfaz en un píxel proyectado **flota**: no
tiene profundidad, se dibuja encima de la colina que debería taparla, y nada de
lado cuando gira la cámara. Así que los marcadores importantes no los dibujamos:
se los pedimos al cliente.

| Qué | Cómo | Dónde |
|---|---|---|
| **Aro de selección** | el cliente guarda **dos** huecos de GUID en el contexto de escena y los drena una vez por frame. Se engancha ese drenaje (`0x004F6F90`), se le deja correr como siempre, y después se le pasan nuestras unidades **de una en una**: cada llamada dibuja un aro más, con su propio código | `rts-client-mod/src/Circle.cpp` |
| **Brillo del modelo** | `CGUnit_SetHighlight` / `ClearHighlight` con sus tres "razones", y el color y la intensidad escritos en el objeto de render (`+0x18C`, `+0x1B8`) | `rts-client-mod/src/Highlight.cpp` |
| **Números de la cadena de ataque** | son los **iconos de banda** del cliente. Los coloca él en su propio bucle a partir de la posición del mundo, igual que las placas de nombre: siguen perfectamente porque no se sigue nada. El precio es que son ocho | `addon/Chain.lua` |
| **Marcador de punto de ruta** | un `DynamicObject` con el visual persistente de un hechizo —lo mismo que una mancha de Consagración—, colocado en el mundo y dibujado por el cliente con profundidad correcta. La lista de candidatos **se construye del almacén de hechizos cargado** (todo hechizo con efecto de aura de área persistente), no de ids escritos de memoria | `mod-rts/src/RtsMarks.cpp` |

Un aro dibujado por nosotros existió, con doce rayos hacia abajo por unidad para
muestrear el terreno, y se aparcó: nunca se leyó como un aro tumbado en el
suelo, y no podía. El código de los rayos sigue en `GroundRing.cpp`.

### 4.3 El raycast: la única cosa que el Lua de 3.3.5a no puede hacer

No hay raycast en la API hasta Cataclysm. El addon lo fingía desproyectando el
cursor sobre un plano a la Z **del jugador**, que es exacto justo al lado de tu
personaje y falso en todo lo demás —cuestas, escaleras, puentes— y la cámara
libre lo empeoró, porque ahora la cámara puede estar a cien yardas de esa Z.

Así que se llama a `CGWorldFrame::Intersect` (`0x0077F310`), **la función de
picking del propio cliente**, la misma con la que decide qué tienes bajo el
ratón. Con dos máscaras de banderas:

- `0x00100171` — todo: terreno, edificios, doodads.
- `0x00000100` — **solo terreno**. Un tejado deja de ser suelo, que es lo que
  permite a la cámara entrar en una casa en vez de subirse encima.

Se usa para el punto bajo el cursor, para las alturas del aro, y para los tres
rayos de la cámara libre (suelo, terreno y techo).

### 4.4 El puente Lua ↔ DLL

**De DLL a addon:** `FrameScript_Execute` (`0x00819210`) ejecuta una cadena de
código Lua en el estado global del cliente, y lo que ejecuta son asignaciones a
globales `RTS_*` que el addon lee. Posición del jugador y su orientación,
cámara (posición, base 3x3, FOV, aspecto), los tres rayos bajo la cámara, el
punto del cursor, y la lista de unidades cercanas.

Cadencia: **100 Hz solo la cámara**, 33 Hz el estado completo. La cámara va más
deprisa porque los marcadores se colocan a partir de ella, y una cámara
obsoleta los arrastra de lado mientras giras.

**De addon a DLL: un CVar.** No hay otra vía. WoW 3.3.5a rechaza punteros a
función C que vivan fuera de `Wow.exe`: llamar a uno lanza el `ERROR #134` y se
lleva el cliente por delante (comprobado por las bravas). Un CVar es memoria
corriente del cliente, Lua puede escribirla con `SetCVar`, y el cliente la
convierte a entero en `CVar+0x30`.

Protocolo 3, 32 bits por tick:

```
bits  0..23   ocho huecos x tres bits de estado
bits 24..26   número de secuencia
bit  27       dibuja el aro nativo
bit  28       además ilumina el modelo
bit  29       diagnóstico: un aro bajo CADA unidad publicada
bit  30       libre
bit  31       inutilizable -- el cliente parsea el valor con un atoi CON SIGNO
```

CVars usados: `enablePVPNotifyAFK` (el canal de selección, **prestado** y con su
valor original guardado y devuelto), `rtsFov` y `rtsBody` (**creados** con
`RegisterCVar`, que existe en este cliente). Que sean propios no es cosmético:
`SetCVar` sobre un nombre que no existe **no da error**, no hace nada —que es
exactamente como un canal anterior estuvo muerto tres etapas sin que se notara.

**El hilo principal:** `MainThreadHook` subclasa el `WndProc` de la ventana de
WoW. Un `WndProc` siempre se despacha en el hilo que creó la ventana, que es el
único hilo donde se puede tocar Lua. Sustituyó a un trampolín sobre `EndScene`
de D3D9 que, bajo la capa `d3d9on12` de Windows 11, enganchaba una vtable que no
era por la que el cliente llama —así que no disparaba nunca.

### 4.5 Frames de Blizzard: prestados, no reimplementados

`Rails.lua` lo intentó con botones propios que llamaban a `ToggleWorldMap`,
`ToggleTalentFrame`, `ToggleGameMenu`… y en juego el mapa no abría, los talentos
no abrían y el menú saltaba con *"blocked from an action only available to the
Blizzard UI"*. Esas funciones están protegidas y **da igual que el botón sea
nuestro**.

| Qué se toma prestado | Cómo |
|---|---|
| Las cuatro bolsas, la mochila y el llavero | reparentados a una fila nuestra y devueltos al salir. Son hijos de `MainMenuBarArtFrame`, así que esconder la barra principal se los llevaba por delante |
| Los diez micro-botones (ficha, hechizos, talentos, misiones…) | igual. Y se engancha `MoveMicroButtons`, porque el cliente los recoloca por su cuenta al entrar en un vehículo |
| Los marcos de jugador, objetivo y grupo | se les engancha el **`PostClick`**, nunca el `OnClick`: enganchar el `OnClick` de un frame seguro mete su `TargetUnit` dentro de una ejecución contaminada y **se bloquea en combate** |
| El registro de misiones | se deja entero y solo se cambia lo que hace el botón Compartir |
| La marca de selección de los retratos | es el resalte del propio cliente en modo aditivo |

Regla dura en todos: **de cada frame se guarda si estaba visible ANTES de
tocarlo** y se le devuelve ese mismo estado. Nada de `Show()` a ciegas, que
encendería barras que el jugador tenía apagadas. Y lo que está protegido no se
toca en combate: se aplaza a `PLAYER_REGEN_ENABLED`.

### 4.6 Núcleo de AzerothCore: su API, con el `Player*` de un bot

Aquí no hay ningún truco, y por poco se descarta por no mirar. Un bot de
playerbots **es un `Player` normal** para el núcleo, y las funciones de dominio
toman un `Player*` cualquiera:

| Se usa | Qué da |
|---|---|
| `Trainer::GetSpells / CanTeachSpell / TeachSpell / IsTrainerValidForPlayer` | la ventana del entrenador entera, calculada **para el bot**. Lo único que hace `WorldSession::SendTrainerList` por encima es empaquetarlo hacia su propia sesión, y eso no hace falta porque la ventana la dibujamos nosotros |
| `CanTakeQuest`, `CanAddQuest`, `AddQuest`, `CanRewardQuest`, `RewardQuest` | aceptar y entregar misiones para varios a la vez. **Ninguna comprueba distancia** —verificado línea a línea en `PlayerQuest.cpp`— así que lo del vídeo (*"you don't have to actually be next to it"*) sale gratis |
| `CanStoreItem` → `MoveItemFromInventory` → `MoveItemToInventory` | pasar un objeto de una bolsa a otra sin ventana de intercambio |
| `LoginQueryHolder` + `HandlePlayerLoginFromDB` | **cambiar de personaje sin cerrar sesión.** Es la misma secuencia pública con la que mod-playerbots mete un bot en el mundo. El servidor se traga el `SMSG_LOGOUT_COMPLETE` (lo único que mandaba el cliente a la pantalla de personajes) y el cliente adopta el objeto nuevo porque llega con `UPDATEFLAG_SELF` |

**`mod-playerbots` es ajeno y no se toca.** Toda la superficie que se le pide
está detrás de un solo fichero, `mod-rts/src/RtsBotApi.cpp`, que es la única
unidad de traducción que incluye una cabecera suya —así que una actualización
suya rompe **un** fichero y no dos de mil líneas. Antes había unas ochenta
llamadas suyas repartidas y mezcladas con lógica nuestra.

Lo que sí se le añade por fuera: las órdenes que das con el ratón le hacen
`SetNextCheckDelay(0)` para que la IA del bot despierte **en el acto** en vez de
esperar a su siguiente vuelta de pensamiento (`nextAICheckDelay`). Es el mismo
mando que playerbots usa consigo mismo, y se pone **solo** en las órdenes que
das tú: en todo lo demás esa espera existe por algo.

### 4.7 Lo que deliberadamente NO se toca

- **El núcleo de AzerothCore.** Todo va en `modules/mod-rts`.
- **`mod-playerbots`.** Se lee, no se edita. Ver `RtsBotApi`.
- **El rol y la postura de un bot.** Los decide playerbots; una postura es un
  hechizo y cabe en uno de sus diez huecos. No hay interfaz de roles, y no es un
  olvido.
- **El chat, el botín, el gossip, las emergentes y el menú de escape.** El modo
  RTS esconde una lista escrita a mano y nada más.
- **Las teclas del jugador.** Se apuntan antes de cogerlas, se devuelven al
  salir, y `SaveBindings` **no se llama nunca**: una recarga o un cierre
  inesperado dejan intactas las de verdad.

---

## 5. Desplegar y compilar

Un solo sentido, siempre: de aquí hacia fuera. Nunca al revés.

| Botón | Qué hace | Después hay que |
|---|---|---|
| `C:\Server\rts-tools\Deploy_Addon.bat` | `addon/` → carpeta del WoW | `/reload` en el juego |
| `C:\Server\rts-tools\Deploy_Mod.bat` | `mod-rts/` → AzerothCore | recompilar `worldserver` |

El DLL no tiene botón porque no se mueve de sitio:

```powershell
cmake --build C:\Server\rts-project\rts-client-mod\build --config Release
```

Y se inyecta con `C:\Server\rts-tools\2-Jugar.bat`.

Antes de dar el addon por bueno: `python C:\Server\rts-tools\check_addon.py`.
Comprueba cuatro cosas, y las tres últimas existen porque la primera no las
coge —cadenas cortas sin cerrar, escapes desconocidos (`"Interface\Icons\X"` se
lee como `InterfaceIconsX`, y **una ruta que no existe no da error: dibuja
nada**) y locales usadas antes de declararse.

El arte propio se convierte con `C:\Server\rts-tools\Convertir_Arte.bat`:
`art-src/` es el original y `addon/art/` el TGA que lee el cliente.

### En otro ordenador

```
git pull
```

y después los dos botones de deploy, más compilar el DLL y el `worldserver`.

---

## 6. Reglas del repositorio

### Por qué un solo sentido

Antes había un `sync.ps1` que recogía las tres piezas desde donde vivían, y esta
carpeta era solo una copia de seguridad. Existían los dos sentidos, y eso
significaba que en cualquier momento no estaba claro cuál era la versión buena.

El 16/08/2026 costó una tarde: el addon se editó hasta las 22:06, el último
`sync` había sido a las 19:04, y al mudar el servidor a otro ordenador se
instaló la copia de las 19:04. Faltaban 247 líneas de `RTSMode.lua`, entre ellas
`CameraTurned()` — justo la función que hace funcionar la selección por caja. El
síntoma fue "lo nuevo no funciona en el ordenador nuevo", y no había ni un error
que lo delatara.

Con un solo original y un solo sentido, ese fallo no se puede dar: si el juego
va viejo, es que falta desplegar, y se arregla con un botón.

### Qué NO se sube, y por qué

- **`worldserver.conf`, `authserver.conf`, `dbimport.conf`** — llevan el usuario
  y la contraseña de MySQL en texto plano. Nunca entran aquí. La plantilla del
  módulo (`mod-rts/conf/mod_rts.conf.dist`) sí, porque solo trae ajustes de
  cámara.
- **`build/`, binarios, logs** — se regeneran compilando.
- **El fork de AzerothCore** — tiene su propio remoto
  (`mod-playerbots/azerothcore-wotlk`, rama `Playerbot`). Aquí solo va nuestro
  módulo.
- **`mysql-data/`** — son las bases de datos, no código.

### Dónde está el porqué de cada cosa

**En la cabecera del fichero que la implementa**, con los callejones sin salida
incluidos. `docs/` existió y se borró a propósito (`4c2b163`): unas notas que ya
no coinciden con el binario son un sitio cómodo donde confirmar una idea
equivocada sin abrir el código.

Las direcciones desensambladas de **este** `Wow.exe` (MD5
`45892BDEDD0AD70AED4CCD22D9FB5984`, build 12340) están en
`rts-client-mod/src/Offsets.h`, cada una con el volcado que la justifica.
