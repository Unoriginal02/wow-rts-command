# Estudio: la UI del modo RTS

Estudio previo para sustituir toda la interfaz de WoW por una HUD de RTS al
estilo WC3 / StarCraft II mientras el modo RTS esté activo.

Escrito 2026-08-16. **No es un plan de implementación todavía**: es lo que hay
que saber *antes* de dibujar una sola textura, porque tres o cuatro de estas
cosas obligan a rehacer arte si se descubren tarde.

Tu equipo actual: **2560x1440**, `uiScale 0.86`, `useUiScale 1`.

---

## 1. Las dos restricciones duras

Estas dos no se negocian y condicionan todo lo demás. Las pongo primero porque
determinan cómo se corta el arte.

### 1.1 Las texturas: potencias de dos, máximo 512

WoW 3.3.5a solo carga texturas de addon que sean:

- **TGA sin comprimir de 32 bits** (24 bits si no lleva alfa) o **BLP**
- con **ambos lados potencia de dos**: 8, 16, 32, 64, 128, 256, **512**
- **no hace falta que sean cuadradas**: 512x128 es válido, 512x64 también

Lo he verificado contra lo que ya te funciona: `halo-01.tga` es 256x256, 32 bits,
tipo 2 (sin comprimir). Ese es el molde.

**La consecuencia importante:** una barra que cruce una pantalla de 2560 px de
ancho **no puede ser una sola textura**. Hay que cortarla. Las dos formas:

- **Troceado fijo** — la barra se parte en piezas de 512 (o 256) de ancho y se
  colocan una al lado de otra. Es lo que hace WC3: si te fijas en la captura, la
  barra tiene módulos que se repiten.
- **9-slice / 3-slice** — esquinas de tamaño fijo y un centro que se estira o se
  repite. Mejor si quieres que la HUD se adapte a distintas anchuras sin rehacer
  arte, que es exactamente tu caso porque no sabes en qué resolución vas a jugar
  siempre.

Recomiendo **3-slice horizontal** para los paneles largos: extremo izquierdo
(512 fijo), centro repetido (256 con `SetHorizTile(true)`), extremo derecho
(512 fijo). Y piezas sueltas para los elementos que no se estiran (marco del
minimapa, marcos de retrato).

### 1.2 El escalado: por qué tu arte se vería borroso

Esta es la que más gente descubre tarde.

WoW no trabaja en píxeles: trabaja en **unidades de UI**. La pantalla mide
**768 unidades de alto** cuando la escala efectiva es 1, independientemente de
la resolución real. De ahí sale la relación:

```
píxeles por unidad = escalaEfectiva × (altoFísico / 768)
```

Con tus 1440 px y `uiScale 0.86`:

```
1 unidad de UI = 0.86 × (1440 / 768) = 1.61 píxeles físicos
```

Es decir: **una textura de 512 px dibujada a 512 unidades se estira a 826
píxeles reales**. Interpolada. Borrosa. Y no hay ajuste de calidad que lo
arregle, porque el problema es de muestreo.

**La solución, y encaja perfectamente con tu regla de que el modo RTS solo
afecte al modo RTS:** darle a *nuestra* HUD su propia escala, la que hace que
una unidad sea un píxel:

```lua
local PIXEL = 768 / 1440        -- 0.5333 en tu equipo
hud:SetScale(PIXEL)
```

Con eso, dibujas el arte en píxeles reales y lo colocas en píxeles reales. Nada
se interpola. El resto del juego conserva su `uiScale 0.86` intacto.

Calculado en vivo, no fijo, para que siga funcionando si cambias de resolución:

```lua
local _, screenHeight = GetPhysicalScreenSize and GetPhysicalScreenSize() or nil, nil
-- 3.3.5a no tiene GetPhysicalScreenSize; se saca del CVar:
local w, h = string.match(GetCVar("gxResolution"), "(%d+)x(%d+)")
local PIXEL = 768 / tonumber(h)
```

---

## 2. Ocultar la UI: qué desaparece y qué no

### 2.1 El mecanismo

```lua
UIParent:Hide()
```

Casi todo lo que ves en pantalla es hijo de `UIParent`, así que se va de una vez.
**`WorldFrame` no es hijo suyo, es hermano** — el mundo 3D se sigue dibujando.
Esa separación es justo la que necesitamos.

### 2.2 Lo que hay que saber antes de hacerlo

**Nuestra propia HUD tiene que colgar de `WorldFrame`, no de `UIParent`.** Si
cuelga de UIParent desaparece con todo lo demás. Y ya tenemos precedente: los
diecisiete ficheros del addon crean sus frames sobre `UIParent`, así que esto es
trabajo real, no un detalle.

Colgar de `WorldFrame` además nos da la escala limpia del apartado 1.2, porque
`WorldFrame` está a escala 1 y no arrastra el `uiScale` del jugador.

**El taint.** Ocultar `UIParent` no está protegido, pero **volver a mostrarlo en
combate sí puede contaminar** frames protegidos y provocar el clásico "blocked
from an action only available to Blizzard's UI" más adelante, en sitios que no
tienen nada que ver. El patrón seguro es el que ya usa `Camera.lua` con las
teclas: si estás en combate, aplazar la restauración a `PLAYER_REGEN_ENABLED`.

**Los errores de Lua y el chat desaparecen.** Incluido nuestro propio
`ns.Print`. Hay que decidir dónde van los mensajes: o se reparenta un
`ChatFrame` a nuestra HUD, o se hace una línea de mensajes propia. No es opcional
— hoy dependemos de ese canal para todo diagnóstico.

---

## 3. Lo que se te ha olvidado (la parte importante)

Esto es lo que quería que saliera del estudio. Ocultar `UIParent` no oculta solo
barras y minimapa: oculta **todas las ventanas con las que interactúas**.

| Ventana | Qué pasa si no se trata |
|---|---|
| **Botín** (`LootFrame`) | Clicas un cadáver, el servidor abre el botín, y no lo ves. Justo lo que acabamos de arreglar deja de funcionar. |
| **Gossip / quest** (`GossipFrame`, `QuestFrame`) | Hablas con un PNJ y no ves el diálogo. Sin quests. |
| **Vendedor** (`MerchantFrame`) | No puedes vender lo que looteas. |
| **Bolsas** (`ContainerFrame1..5`) | Las pides tú explícitamente en tu plan, pero son hijas de UIParent. |
| **Talentos, personaje, hechizos** | Igual. |
| **Menú de escape** (`GameMenuFrame`) | **No puedes desconectarte ni salir.** |
| **Ventanas emergentes** (`StaticPopup`) | Invitaciones de grupo, confirmaciones de borrar objeto, resucitar. Quedan invisibles pero *activas*. |
| **Tooltips** (`GameTooltip`) | Sin tooltips en tus propios botones. |
| **Barra de casteo, buffs/debuffs** | Desaparecen. |
| **Espíritu / liberar** | Si mueres, no ves el botón de liberar espíritu. |

**Esto es la decisión de diseño más grande del proyecto, y hay que tomarla
antes de dibujar nada:**

- **Opción A — ocultar todo y reparentar lo que haga falta.** Se mueven
  `LootFrame`, `GossipFrame`, `MerchantFrame`, bolsas, `GameMenuFrame` y
  `StaticPopup` a nuestra HUD. Control total y estética coherente, pero cada
  ventana es un caso y algunas son protegidas.
- **Opción B — ocultar selectivamente.** En vez de `UIParent:Hide()`, esconder
  solo lo que estorba: `MainMenuBar`, `MinimapCluster`, `PlayerFrame`,
  `TargetFrame`, `PartyMemberFrame1..4`, `BuffFrame`, `CastingBarFrame`,
  `ChatFrame1..7`, `QuestWatchFrame`, `DurabilityFrame`... Más tedioso de
  enumerar, pero **las ventanas siguen funcionando solas** y no hay taint.

Mi recomendación es **empezar por B**. La estética de A es mejor, pero B te deja
un modo RTS jugable *desde el primer día* y puedes ir moviendo ventanas a la
HUD una a una cuando te apetezca. A es un acantilado: hasta que no has
reparentado las diez, el modo no se puede usar.

---

## 4. La restricción funcional: acciones protegidas

Esto no es de arte, es de qué puede hacer la HUD.

**Un addon no puede lanzar un hechizo desde código.** Ni `CastSpellByName` desde
un `OnClick` normal, ni `TargetUnit` para una unidad cualquiera — eso último ya
nos mordió en PRUEBAS-5 y está documentado en `CLAUDE.md`.

Lo único que funciona es un botón con `SecureActionButtonTemplate` y sus
atributos (`type`, `spell`, `unit`, `macrotext`). Y eso trae dos reglas:

1. **No se pueden crear ni modificar botones seguros en combate.** Hay que
   crearlos todos por adelantado, fuera de combate, y solo enseñarlos u
   ocultarlos después.
2. **Los atributos tampoco se cambian en combate.** Una barra que cambia según
   la selección tiene que estar pre-poblada, o cambiar solo fuera de combate.

**Qué implica para tu plan por secciones:**

- Los **iconos de playerbots** (follow, stay, pull) mandan comandos de chat, que
  **no** están protegidos. Botones normales, sin problema.
- Los **comandos de rol** (`co +heal,-dps`) igual: son chat. Sin problema.
- Los **iconos de juego** (talentos, bolsas) llaman a `ToggleTalentFrame`,
  `ToggleBackpack`... algunas son seguras y otras no. Hay que revisarlas una a
  una.
- La **carta de comandos que castea hechizos del bot seleccionado** — que ya
  existe en `CommandCard.lua` — es la única que necesita botones seguros de
  verdad, y ya es la parte más delicada del addon actual.

---

## 5. El plan por secciones, con las pegas de cada una

Tu esquema, y lo que hay que tener en cuenta en cada trozo.

### 5.1 Izquierda — minimapa, reloj, opciones de mapa

`Minimap` es un frame de Blizzard y **se puede reparentar**: `Minimap:SetParent(hud)`.
Sigue funcionando (el motor lo dibuja él).

Pegas:
- El **reloj** (`TimeManagerClockButton`) y los botones de zoom y tracking son
  hijos de `MinimapCluster`, no de `Minimap`. Se reparentan por separado.
- El minimapa es **cuadrado con máscara circular**. WC3 y SC2 lo tienen
  rectangular. Se puede cambiar la máscara con `Minimap:SetMaskTexture()`, y esa
  textura también obedece la regla de potencias de dos.
- Escalar el minimapa cambia la zona visible, no solo su tamaño.

### 5.2 Centro arriba — retratos de la party y de los enemigos

Los retratos de la party salen de `SetPortraitTexture(textura, unidad)`, que ya
usa `UnitBar.lua`. La vida, de `UnitHealth`/`UnitHealthMax`.

Pegas:
- Para los **enemigos** solo tienes tokens fiables de `target`, `focus` y
  `mouseover`. Para "con lo que está peleando el grupo" hace falta la lista que
  ya publica la DLL, o `Targets.lua`, que para eso existe.
- El **retrato 3D** (`PlayerModel`) es más bonito que la textura plana y es lo
  que usa SC2. Tiene coste de rendimiento y hay que probar cuántos aguanta.
- Con la party llena son 5 retratos + N enemigos; conviene un pool fijo de
  frames reutilizados, no crearlos y destruirlos.

### 5.3 Centro abajo — comandos del grupo, del héroe y de la selección

Aquí está la lógica interesante y ya la tienes medio hecha en `CommandCard.lua`
y `Selection.lua`.

Pegas:
- Botones distintos según qué tengas seleccionado: un sanador enseña
  "curar/atacar", un tanque otra cosa. Eso es **cambiar atributos**, así que si
  son botones seguros, no se puede hacer en combate. Si son solo chat (`co
  +heal`), sí se puede y es lo que recomiendo.
- Necesita saber la **clase y especialización** de cada bot. La clase la tienes
  con `UnitClass`. La especialización real no la sabe el cliente para otros
  jugadores — habría que preguntársela a mod-rts, que sí puede leerla.

### 5.4 Derecha — acciones de playerbots

Follow, stay, pull, formaciones. Todo son comandos de chat, así que botones
normales y sin restricción de combate. **Es la sección más fácil de las cinco**
y probablemente por donde empezar para validar el arte.

### 5.5 Derecha abajo — iconos de juego

Talentos, bolsas, personaje, hechizos.

Pegas:
- Si vas por la **opción B** (ocultado selectivo), estos botones solo tienen que
  llamar a `ToggleTalentFrame()` y compañía, y la ventana sale sola.
- Si vas por la **A**, cada ventana hay que reparentarla además.
- `ToggleBackpack` y algunas otras son seguras en ciertas rutas; hay que
  probarlas una por una en combate.

---

## 6. Cosas que ni tú ni el plan mencionabais

- **Ratios de aspecto.** 2560x1440 es 16:9. En 21:9 una HUD anclada a los dos
  extremos deja un centro enorme; anclada al centro deja huecos a los lados.
  WC3 y SC2 anclan **al centro-abajo** y dejan que el mundo se vea a los lados.
  Es lo que recomiendo.
- **Cambiar de resolución en caliente.** Hay que recalcular `PIXEL` y reanclar.
  Evento `DISPLAY_SIZE_CHANGED`.
- **Fuentes.** Si la HUD va a escala de píxel, las fuentes hay que pedirlas en
  tamaño de píxel o saldrán diminutas. `SetFont(ruta, tamaño, "OUTLINE")`.
- **Rendimiento.** Cada textura es una llamada de dibujo. Una HUD de RTS con
  cien piezas y retratos 3D en un cliente de 2010 se nota. Conviene agrupar el
  arte en pocos atlas de 512x512 y usar `SetTexCoord` para recortar, en vez de
  cien ficheros sueltos.
- **El arte en sí.** Tienes dos caminos: dibujarlo, o reaprovechar texturas del
  propio WoW (`Interface\\...`), que son gratis y encajan de estilo. Para un
  primer prototipo jugable, lo segundo; el arte propio después, cuando la
  distribución esté decidida y no vayas a rehacerlo.
- **Guardar la configuración.** Posiciones, escala, qué paneles se ven. Ya
  tienes `RTSCommandDB` para eso.
- **Salir con elegancia.** La HUD debe desaparecer y `UIParent` volver **en el
  mismo estado** en que estaba, incluida la escala. Es tu regla de siempre y
  aquí es más fácil de romper que nunca.

---

## 7. Por dónde empezaría

En este orden, y cada paso es jugable por sí solo:

1. **Un contenedor sobre `WorldFrame` con escala de píxel** y nada dentro.
   Comprobar que se ve nítido y que sale y entra sin dejar rastro.
2. **Ocultado selectivo (opción B)** de las barras y marcos que estorban. Ya
   tienes un modo RTS usable sin haber dibujado nada.
3. **La sección derecha** (acciones de playerbots), que es la más fácil: chat
   puro, sin protegidos. Sirve para validar arte, escala y anclajes.
4. **Minimapa reparentado** a la izquierda.
5. **Retratos** arriba en el centro.
6. **Comandos por rol** abajo en el centro, empezando por los de chat.
7. El **arte propio**, cuando la distribución ya no vaya a cambiar.

Lo que **no** haría: dibujar la barra entera primero. Hasta que no esté decidido
si vas por A o por B, y hasta que no haya un panel funcionando a escala de
píxel en tu monitor, cualquier arte es una apuesta sobre medidas que todavía
pueden cambiar.

---

## 8. La pregunta que hay que contestar antes de nada

> **DECIDIDO 2026-08-19: opción B.** Implementada en `addon/Chrome.lua` (el
> ocultado, con restauración al estado previo) y `addon/HUD.lua` (el contenedor
> a escala de píxel, el minimapa reparentado y la línea de mensajes que
> sustituye al chat escondido). Se maneja con `/rts ui`, y la ronda
> `PRUEBAS-9.txt` es la que decide la altura de la barra de control. El resto
> de este apartado se deja tal cual como registro del razonamiento.

**¿Opción A (ocultar todo y reparentar) u opción B (ocultado selectivo)?**

Todo lo demás se deriva de eso: cuánto arte hace falta, cuántas ventanas hay que
adoptar, y si el modo es usable desde el primer día o solo al final.

Mi voto es B para empezar, con la puerta abierta a mover ventanas a la HUD una a
una. Pero es una decisión de gusto tanto como técnica, y es tuya.
