# Plan de ataque: bolsas compartidas, questeo multiple y control de personajes

> **SUPERADO 2026-09-03. NO SE SIGUE ESTE DOCUMENTO.** Se escribio sin comprobar
> el codigo y **dos de sus conclusiones son falsas**, comprobadas abriendo los
> ficheros:
>
> - El apartado **E** daba por imposible interactuar como el bot sin reescribir
>   el cliente. Es API publica del nucleo (`Trainer.h`): esta hecho y funciona.
>   Ver `mod-rts/src/RtsNpc.h`.
> - El **2.2** decia "83 llamadas en 4 ficheros". Son dos: `RtsCamera.*`,
>   `RtsMarks.*`, `mod_rts.cpp` y las cuatro cabeceras ya estaban limpios.
>
> Lo construido esta en `CLAUDE.md` (Stage 7) y la ronda de pruebas en
> `PRUEBAS-20.txt`. **Se conserva porque su apartado 1 -- que ese desarrollador
> ha reescrito el cliente, y que eso decide que se puede copiar -- sigue siendo
> el marco correcto.** Un documento viejo que no dice que lo es manda a arreglar
> cosas ya arregladas; por eso este aviso y no un borrado.


Escrito 2026-09-02, a partir del vídeo del otro desarrollador (`asd.txt`).

---

## 1. Lo primero: él juega con otra baraja

En el vídeo dice, en el minuto 4:44: *"I don't plan on doing Lua support"*, y en
el 5:46: *"the client needs still a lot of work"*.

**Ese hombre ha reescrito el cliente de WoW.** No usa addons. Por eso puede
poner los nombres de los bots flotando sobre un NPC, cambiar el cursor, y
dibujar la interfaz de bolsas como le da la gana.

Nosotros vamos con el cliente original de Blizzard y un addon. Eso decide qué se
puede copiar y qué no:

| Lo que hace | ¿Podemos? |
|---|---|
| Mostrar información nueva (quests, bolsas de los bots, quién puede coger qué) | **Sí.** El servidor nos la manda y la dibujamos en la consola |
| Comandos nuevos (aceptar quest para todo el grupo, pasar un objeto de un bot a otro) | **Sí.** Lo hace el servidor, nosotros sólo pedimos |
| Texto flotando sobre un NPC en el mundo 3D | **A medias.** Se puede proyectar (ya lo hacemos con las rutas), pero se dibuja encima de las colinas. Mejor en la consola |
| Abrir la ventana de un vendedor o entrenador "como si fueras el bot" | **No, no barato.** Esas ventanas las abre el cliente cuando el servidor le habla a TU personaje. Ver §6 |

**Conclusión: el 80% de lo del vídeo lo podemos hacer.** Lo caro es sólo el
último punto, y tiene un sustituto del 80% del valor por el 10% del coste.

---

## 2. La regla que no se rompe: que se pueda actualizar

Esto es lo que pediste y es lo que manda en todo el plan.

### 2.1 La buena noticia

**Las dos cosas que más te interesan — bolsas y quests — no necesitan playerbots
para nada.** Se hacen con las funciones del propio AzerothCore, que llevan años
sin cambiar de nombre. Comprobado abriendo el código, no de memoria:

- Quests: `CanTakeQuest`, `CanAddQuest`, `AddQuest`, `CanRewardQuest`,
  `RewardQuest`, `GetQuestStatus` — todas en `Player.h`.
- Quién da qué quest: `GetCreatureQuestRelationBounds` en `ObjectMgr.h`.
- Objetos: `GetItemByPos`, `GetItemByGuid`, `CanStoreItem`, `StoreItem`,
  `DestroyItemCount` — todas en `Player.h`.

Un bot de playerbots **es un `Player` normal** para el servidor. Así que darle
un objeto o una quest a un bot es exactamente el mismo código que dárselo a un
jugador de verdad.

### 2.2 Lo que sí toca playerbots, y cómo se blinda

Hoy mod-rts tiene **83 llamadas a playerbots repartidas en 4 ficheros**
(`RtsOrders.cpp` 40, `RtsCommandMode.cpp` 38, y sus cabeceras). Si playerbots
cambia un nombre, hay que buscar por 4 sitios y entender qué hacía cada uno.

**Arreglo: un solo fichero `RtsBotApi.cpp` que sea la única puerta.** Todo lo
demás de mod-rts llama a *ese*, nunca a playerbots directamente. Con eso:

- Una actualización de playerbots que rompa algo **da error de compilación en un
  fichero**, no en cuatro. Se arregla en una tarde en vez de en un día.
- Se ve de un vistazo cuánto dependemos de ellos. Hoy no se ve.
- Las features nuevas de este plan casi no lo tocan.

Es medio día de trabajo y es lo que hace que el resto del plan sea seguro.

### 2.3 Las cuatro reglas

1. **Nunca editar AzerothCore ni playerbots.** Ya es la norma; sigue siéndolo.
2. **Preferir las funciones del core a las de playerbots** siempre que haya
   elección. El core es estable; playerbots se mueve.
3. **Todo lo de playerbots pasa por `RtsBotApi`.** Sin excepciones.
4. **Nada de tocar la base de datos del mundo.** Se borra entera en cada
   actualización. Si algún día hace falta guardar algo nuestro, va en la base de
   datos de personajes con nombres que empiecen por `rts_`.

---

## 3. Las features, ordenadas por lo que cuestan

De más barato y seguro a más caro.

| # | Feature | Necesita playerbots | Riesgo al actualizar |
|---|---|---|---|
| A | Bolsas compartidas | **No** | ninguno |
| B | Questeo múltiple | **No** | ninguno |
| C | Control de personajes (el centro de la consola) | sí, lo de siempre | bajo |
| D | Ayudante de quests (a dónde ir) | **No** | ninguno |
| E | Interactuar como el bot (vendedor, entrenador) | sí, y más | **alto** |

### A. Bolsas compartidas

Pulsas una tecla y ves las bolsas de todos. Arrastras un objeto de un bot a otro
y se mueve al momento, sin ventana de intercambio.

- **Servidor:** un verbo que devuelve el contenido de las bolsas de un bot, y
  otro que mueve un objeto de A a B. Todo con funciones del core.
- **Addon:** un panel que se abre y se cierra, con arrastrar y soltar.
- **Ojo con dos cosas:** que el destino tenga hueco (el core ya lo dice con
  `CanStoreItem`, sólo hay que hacerle caso y avisar), y que un objeto equipado
  o vinculado no se pueda mover sin más.

### B. Questeo múltiple

Es lo del vídeo: pinchas un NPC y ves **todas** sus quests y, por cada una, qué
bots pueden cogerla, cuáles ya la llevan y cuáles pueden entregarla. Un botón
las acepta o entrega para todo el grupo, sin tener que estar al lado.

- **Servidor:** dado el NPC, sacar sus quests y preguntar a cada miembro del
  grupo su estado. Luego aceptar o entregar en bucle. Todo core.
- **Addon:** un panel con una fila por quest y unos puntitos de colores por bot.
- **Lo de los nombres flotando sobre el NPC:** yo empezaría por enseñarlo en la
  consola cuando apuntas al NPC. Es gratis, se lee mejor, y no tiene el problema
  de dibujarse encima de las colinas. Si luego lo quieres flotando, la
  maquinaria de proyección ya existe.
- **Decisión que hay que tomar:** las quests con opción de recompensa (elegir
  entre dos objetos). Para el grupo entero eso es un lío. Propuesta: entregar
  automáticamente las que no tienen elección, y las que sí, marcarlas y
  entregarlas de una en una.

### C. Control de personajes — el centro de la consola

Es lo que ya estás rediseñando. Del vídeo merecen copiarse cuatro cosas:

1. **Tab pasa al siguiente del grupo** sin perder la selección.
2. **Barra de habilidades del seleccionado**, con 6 huecos rápidos. (Esto ya
   existía; se borró para rehacerlo.)
3. **Pulsar una habilidad pregunta a quién**, y con Alt se lanza sobre ti
   directamente. Es la convención de siempre y se entiende sola.
4. **Ataque encadenado:** marcas enemigos 1, 2, 3, 4 y el grupo va a por ellos
   en ese orden.

De estos, el 1 y el 3 son sólo addon. El 2 y el 4 usan lo que ya hay.

### D. Ayudante de quests

Dónde está lo que te falta matar o coger. El servidor tiene esos datos
(`QuestPOI`) y nosotros ya sabemos poner marcadores en el suelo.

Bueno, barato, y **no depende de playerbots**. Pero es lo que menos cambia el
juego de los cuatro, así que va el último de los baratos.

### E. Interactuar como el bot

Lo caro. Abrir el entrenador o el vendedor "siendo" el bot no se puede hacer
limpio con cliente estándar: esas ventanas las abre el cliente cuando el
servidor le habla a **tu** personaje, y hacer que se crea que es otro es meterse
donde no se debe.

**El sustituto, que da casi todo el valor:** botones que hacen la acción sin
ventana. *"Que aprenda todo lo que pueda de este entrenador"*, *"que venda toda
la basura gris"*, *"que repare"*. El servidor lo hace en bucle, tú ves el
resultado. Sin ventana, pero sin tener que ir uno por uno.

**Recomendación: aplazarlo** hasta que A, B y C estén hechas.

---

## 4. En qué orden

| | Qué | Cuánto |
|---|---|---|
| 0 | `RtsBotApi.cpp` — el cortafuegos de actualizaciones | medio día |
| 1 | Decidir el reparto del centro de la consola | una sesión de diseño |
| 2 | **C** — control de personajes | lo más largo |
| 3 | **A** — bolsas compartidas | medio |
| 4 | **B** — questeo múltiple | medio |
| 5 | **D** — ayudante de quests | corto |
| 6 | **E** — el sustituto de interactuar | corto |

**El paso 0 va primero** porque es lo que pediste: que actualizar no duela. Es
barato y no se vuelve a tocar.

**El paso 1 va antes de construir nada** porque las bolsas y las quests van a
querer sitio en pantalla, y el centro de la consola mide lo que mide: **344 de
alto por unos 2246 de ancho** (los números salen de `sim/bar_layout.py`). Hay
que decidir **qué vive ahí siempre** (tú, el grupo, los enemigos) y **qué es un
panel que se abre y se cierra** (bolsas, quests). Si no se decide antes, la
tercera feature no cabe y hay que rehacer las dos anteriores.

Mi propuesta para el paso 1, para discutir:

- **Fijo en la consola:** tú a la izquierda, el grupo, los enemigos, la barra de
  habilidades del seleccionado.
- **Panel que se abre encima:** bolsas (con una tecla) y quests (al apuntar a un
  NPC que tenga).

---

## 5. Antes de empezar: el arreglo pendiente

De la revisión de arquitectura queda uno de los tres grandes sin hacer: **§1,
`Bridge.lua`**. Hoy 98 líneas repartidas por 8 ficheros hablan con la DLL a
pelo, en vez de por su sitio.

No bloquea nada de este plan — ni las bolsas ni las quests tocan la DLL. Pero
crece con cada panel nuevo, así que cuanto más tarde se haga, más cuesta.
Decisión tuya: hacerlo ahora (unas 2 horas) o dejarlo.

---

## 6. Lo que este plan NO promete

- **Interactuar como el bot con ventanas de verdad** (§E). No con cliente
  estándar.
- **Texto flotante sobre los NPCs del mundo** igual que en el vídeo. Se puede
  aproximar; no se puede igualar sin cliente propio.
- **Que una actualización de playerbots nunca rompa nada.** Lo que promete el
  paso 0 es que cuando rompa, se arregle en un fichero y en una tarde — no que
  no pase.
