# Brief — Panel central de control de personajes

> **ESTADO 2026-09-02: implementado (etapa 5n), probado (`PRUEBAS-18`) y luego
> BORRADO junto con toda la sala.** Ver `UI-RTS-SALA.md` §13. Se va a repensar
> el centro de la HUD de cero, así que este brief vuelve a ser **entrada**, no
> especificación cumplida.
>
> **No se relee en limpio.** Se implementó entero y el juego contestó a la mitad
> de sus puntos abiertos. Lo que sigue debajo es el texto original, sin tocar; lo
> que el juego ya contestó está en el apartado 0, y esas respuestas **no dependen
> del diseño** — son del cliente y de playerbots, así que siguen valiendo para
> cualquier sala que se construya encima.

## 0. Lo que ya contestó el juego, y no hay que volver a preguntar

Ordenado por lo que más caro sería redescubrir.

| Punto del brief | Respuesta, y dónde está | Cuesta |
|---|---|---|
| §3 "arrastrar habilidades desde el libro" | **Imposible para un bot**, y no es rodeable: tu libro sólo tiene TUS hechizos, `PickupSpell` no inventa los del mago. La fuente que sí existe es la barra de acciones del propio bot (`BARS`, sigue en mod-rts). Se llena **eligiendo**, no arrastrando. | §11.2 |
| §4 "el rol condiciona el comportamiento" | **Ya existe**: `tank`, `dps`, `heal`, `cc` son estrategias registradas por clase en mod-playerbots, y `passive` la que ya usaba mod-rts. Cuáles tiene cada clase **se le pregunta al servidor** (`GetSupportedStrategies`), nunca una tabla de clases escrita a mano. | §11.4 |
| §4 roles excluyentes | `tank`/`dps`/`heal` los excluye el SERVIDOR, así que un botón **no se enciende al pulsarlo**: se manda y se dibuja lo que conteste. | §11.4 |
| §5 "después vuelve a su target anterior" | **No hay que implementarlo.** `CastAs` con un guid explícito no escribe la selección del bot, así que su siguiente vuelta de IA elige objetivo como siempre. Es el comportamiento por defecto. | §11.1 |
| §5 foco persistente | **Maquinaria de playerbots**: un hostil es `AttackBot`, un amigo es la lista `focus heal targets` + su estrategia. Verbo `PFOCUS`, sigue en mod-rts. La alternativa obvia (reafirmar `SetSelection` cada tick) pelea con el targeting del bot. | §11.5 |
| §5 lanzar | `CastSpellByName` está **protegida**, y un botón seguro no vale porque su hechizo cambia con la selección y eso está bloqueado EN COMBATE. Los dos caminos van por el servidor: `CAST` (bot) y `SELFCAST` (tú). | §11.6 |
| §7 "¿el clic derecho debe funcionar en el mundo?" | Sí, y **shift + clic derecho ya está cogido** desde la etapa 5l: encadena un punto de ruta. Darle un segundo significado según lo que hubiera bajo el cursor haría que encadenar una ruta dependiera de la puntería. | §13 / `RTSMode.lua` |
| §7 feedback visual del apuntado | Se dibuja en **los tres** paneles o no se ve como una orden. Puntual y foco se distinguen por **color y grosor**, no por opacidad: un velo a alfa 0,35 contra barras a 0,95 se lee como "no pasó nada". | §12.2 |
| §7 persistencia | Por **nombre de personaje**. Y hay que tirar la clave al cargar cuando el diseño cambie: las SavedVariables no olvidan nada. | §13.5 |
| §2 fila de targets | La lista `TGTS` (verbo vivo en mod-rts) es lo único que ve más allá de lo que el cliente tiene a mano: por cada objetivo del grupo da guid, vida, si es hostil y **cuántos de los tuyos van a por él**. Sin mod-rts sale sólo tu objetivo. | §13.1 |

**Y una trampa de cliente que costó una ronda y no es de diseño:**
`GetActionInfo` no garantiza devolver un id de hechizo — puede devolver el
índice del libro, y pasárselo a `GetSpellInfo` **no da error**: devuelve otro
hechizo cualquiera, con nombre e icono. Se contrasta contra `GetActionTexture`,
que es la única fuente que no puede mentir. (§12, etapa 5o.)

## 0.1 Lo que el brief pedía y NO se llegó a resolver

Sigue abierto, y sigue siendo la parte difícil:

- **Configuración de los slots de rol** (§4, §7). Nunca pasó de "los que la
  clase soporta". El brief pedía slots que el jugador *define y guarda*.
- **Roles para la selección de grupo completo** (§4). No se construyó.
- **Cola de órdenes puntuales** (§7): profundidad, y feedback de la habilidad
  "congelada" esperando el tick.
- **Fila de targets: criterio de orden** (§7) y qué pasa cuando entran o mueren
  enemigos. Se dibujaba en el orden en que llegaba `TGTS`, que no es una
  decisión.
- **La sala mide 344 de alto y eso no se negocia** (§11.3). Lo fija el arte.
  Cualquier rediseño reparte esos 344, no más. Con las cuatro bandas de la etapa
  5n la fila de enemigos bajó de dos filas a una — de treinta objetivos visibles
  a catorce. Ése es el tipo de factura que hay que pagar a sabiendas.

---

## 1. Objetivo

Ampliar el HUD de control (ya existe la parte superior: avatar grande del héroe + 4 avatares/barras de compañeros) con una **sección central** que permita, durante el combate, dar órdenes granulares a cada miembro del grupo sin perder el control global: que el grupo esté centrado en un objetivo mientras un personaje concreto hace algo distinto contra otro objetivo.

## 2. Layout de la sección central

De arriba a abajo:

1. **Fila de targets** — todos los enemigos actualmente en combate, con sus barras de vida y datos asociados. Mismo tratamiento visual que la fila superior de compañeros.
2. **Línea separadora.**
3. **Fila de habilidades** — ~6 slots (los que quepan) con las habilidades del personaje seleccionado.
4. **Fila de roles** — 4–5 botones anchos, tipo interfaz WoW clásico: rectángulo alargado con texto dentro, poca altura.

## 3. Barra de habilidades

- Son **habilidades/hechizos**, no comandos de bot.
- Los slots empiezan **vacíos**. El jugador arrastra habilidades desde el libro de talentos/habilidades al slot que quiera.
- El loadout es **por personaje**: al seleccionar a otro compañero, se muestra su propia configuración.
- Con **el grupo entero seleccionado**, la barra de habilidades queda **vacía** (posible uso futuro: acciones de grupo).

## 4. Botones de rol

- Slots configurables que el jugador define y guarda (ej.: *Curar*, *CC*, *Tanquear*, *DPS*).
- El rol condiciona el comportamiento automático del personaje: "Curar" hace que se centre en curar (al grupo, al target, según se defina); "CC" hace que controle a la unidad indicada; etc.
- Existen roles **por personaje** y roles **para la selección de grupo completo**.
- El mecanismo concreto de configuración de cada slot queda pendiente de definir.

## 5. Modelo de selección y órdenes

Este es el núcleo del sistema. Reglas finales:

| Input | Dónde | Efecto |
|---|---|---|
| Clic izquierdo sobre personaje | Mundo o HUD | Selecciona ese personaje (selección individual) |
| Doble clic izquierdo sobre personaje | Mundo o HUD | Selecciona a **todos** los personajes |
| Clic derecho sobre un target | HUD | **Orden puntual**: la habilidad que se pulse a continuación queda encolada y se lanza contra ese target en el siguiente tick; después el personaje **vuelve a su target anterior** y continúa su rotación normal |
| Doble clic derecho sobre un target | HUD | **Cambio de foco persistente**: ese target pasa a ser el objetivo del personaje, que ejecuta su rol/rotación contra él hasta nueva orden |

Condiciones:

- Las órdenes de clic derecho **solo están disponibles con un único compañero seleccionado**.
- El target puede ser **enemigo o aliado** (el healer puede "targetear" al tanque).
- Seleccionar un target **no cambia la selección de personaje**: mientras no se haga clic sobre otro personaje, sigo controlando al mismo.

### Ejemplos de uso previstos

- Selecciono al cazador → veo sus habilidades → clic derecho a un mob concreto → pulso un hechizo → lo lanza contra ese mob en el próximo tick y vuelve a lo que estaba.
- Selecciono al healer → clic derecho al tanque → lanza una curación al tanque y sigue haciendo DPS.
- Selecciono al healer → doble clic derecho al tanque → se centra en el tanque de forma persistente (curas/protección) hasta nueva orden.
- El rogue se centra en mantener a raya a un mob concreto mientras el resto del grupo ataca a otro.

## 6. Descartado

Queda **fuera** el esquema de "selección dura" con perfil rojo para el personaje principal y perfil amarillo para secundarios añadidos vía shift-clic o doble clic. Se sustituye por el modelo de la sección 5.

## 7. Puntos abiertos

- **Alcance del clic derecho**: se especificó "en el HUD". ¿Debe funcionar también sobre unidades en el mundo?
- **Feedback visual de selección**: color/perfil para el personaje seleccionado, para la selección de grupo y para el target asignado a un personaje. Sin definir.
- **Configuración de los slots de rol**: cómo se editan y qué opciones ofrecen.
- **Cola de órdenes puntuales**: ¿profundidad 1 (una nueva orden sobrescribe la anterior)? ¿Feedback visual de la habilidad "congelada" a la espera del tick?
- **Persistencia**: ¿los loadouts de habilidades y roles se guardan por personaje individual o por clase/especialización?
- **Fila de targets**: criterio de orden y comportamiento cuando entran o mueren enemigos.
