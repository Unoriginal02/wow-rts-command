# La tercera exportación: cuatro piezas, siete paneles y la sala llena

> **LA SALA ESTÁ VACÍA DESDE 2026-09-02. Ver §13.** Los siete módulos que la
> llenaban están borrados y este documento se ha quedado siendo la HISTORIA de
> cómo se llenó, no la descripción de lo que hay. Se conserva entero y a
> propósito: el §13 sólo dice qué se fue y qué se aprendió, y lo de arriba es lo
> que hay que releer antes de volver a llenarla — sobre todo el §3 (el reparto),
> el §5 y el §11.8 (las trampas del cliente) y el §12 (lo que dijo el juego).
>
> Lo que **sigue siendo verdad hoy**: el arte (§1), los huecos medidos (§2), el
> mecanismo de reparto (§3 salvo los anchos), `Panel` y `Rails`, y todas las
> lecciones. Lo que **ya no existe**: `Portrait`, `Vitals`, `Roster`, `Foes`,
> `Skills`, `Roles` y `Targets`.

Escrito 2026-08-20. **Revisado 2026-08-22 con lo que dijo `PRUEBAS-10`**, que es
la primera vez que esto se vio en juego: las medidas que cambiaron están
corregidas aquí mismo y el §10 cuenta qué cambió y por qué. Continúa
`UI-RTS-PLANTILLA.md`, que llega hasta la segunda exportación (siete TGA, la
barra vacía con la huella de la rejilla dibujada). Esto es lo que la llena.

Pantalla de referencia: **2560x1440**, `uiScale 0.86`. Todos los números son
**píxeles de dibujo** (el arte es 2x y se dibuja reducido) salvo donde diga
"px de pantalla".

---

## 1. El arte: cuatro ficheros, y dos se usan dos veces

| fichero | tamaño | de qué es |
|---|---|---|
| `left-bar.tga` | 128x512 | el remate de los extremos (fue el raíl de botones) |
| `minimap.tga` | 512x512 | el panel cuadrado: minimapa, y otra vez para las órdenes |
| `middle.tga` | 512x512 | la sala; es la única pieza que **empalma consigo misma** |
| `ramp.tga` | 128x512 | el hombro, que baja del alto completo al alto de la sala |

La barra, de izquierda a derecha:

```
left-bar 128 | minimap 512 | ramp 128 | middle 512 xN | ramp' 128 |
minimap 512 | left-bar' 128                           = 1536 + 512N
```

Los dos huecos de 16 que separaban los raíles **están a cero desde 2026-08-22**
(`PRUEBAS-10` A1: "las barras laterales separadas deberían tocarse"). `GAP`
sigue siendo un solo número en `Bar.lua` por si vuelve a quererse.

`'` = espejada con `SetTexCoord(1, 0, 0, 1)`.

**Espejar en vez de exportar más piezas** no es solo por el tamaño (de 7 TGA y
4,2 MB a 4 y 2,6 MB). Es que un espejo **no puede desincronizarse del original**:
dos ficheros dibujados a mano que deberían ser iguales, sí. El precio es que el
hueco útil de una pieza espejada no está donde dice el escaneo sino en su
reflejo, y eso vive escrito en la tabla `HOLE` de `Bar.lua` con las dos
variantes, no recalculado a mano cada vez.

**Con N=4 en esta pantalla:** barra de **3584 x 512** de dibujo, escala
**x0.5625** (el 20% de 1440), o sea **2016 x 288 px de pantalla**, margen
**10,6%** a cada lado. En ventana maximizada (~1392 de alto útil) también salen
4 paneles y 11,9% de margen.

## 2. Los huecos, medidos y no elegidos

Reproducible: por cada PNG de `art-src`, desde el centro de la pieza hacia fuera
hasta el primer píxel con luminancia > 70 (el bisel) o alfa 0.

| pieza | hueco x | ancho | hueco y | alto |
|---|---|---|---|---|
| `left-bar` | 29 | 78 | 30 | 452 |
| `left-bar` espejada | 21 | 78 | 30 | 452 |
| `minimap` | 19 | 474 | 30 | 452 |
| `ramp` | 21 | 107 | 122 | 360 |
| `ramp` espejada | 0 | 107 | 122 | 360 |
| `middle` | 0 | 512 | 122 | 360 |

Dos cosas que se leen de esta tabla y deciden todo lo demás:

- **Los paneles altos y la sala comparten el borde de abajo** (fila 481), así que
  la sala está más arriba pero acaba a la misma altura. Es lo que hace que el
  hombro sea una pieza y no un empalme.
- **El hueco del `minimap` NO es cuadrado**: 474x452. Escalar el minimapa al
  *ancho* del hueco lo saca 22 px por arriba y por abajo, y un frame hijo no se
  recorta en 3.3.5a, así que se comería el borde del arte por los dos lados. Se
  le pasa el lado de la **celda** (452), que es el cuadrado ya centrado dentro
  del hueco. Costó cero porque se vio en la tabla; habría costado una pasada por
  el juego si no.

## 3. El reparto de la sala, que es lo único decidido

La sala mide 360 de alto y `214 + 512*N` de ancho — 2262 con N=4. Dentro, con 8
de margen y 16 entre bloques (**medidas de 2026-08-22**):

| bloque | x (rel. `ramp-left`) | y | tamaño | rejilla |
|---|---|---|---|---|
| retrato 3D | 29 | 130 | 330x256 | — |
| barras del héroe | 29 | 394 | 330x80 | 4 renglones |
| grupo | 375 | 130 | 300x344 | 1x4, celda 300x80 |
| enemigos | 691 | 130 | *lo que sobre* x222 | 15x**2**, celda 96x106 |
| divisor | 691 | 360 | *lo que sobre* x3 | — |
| acciones | 691 | 371 | *lo que sobre* x103 | 14x**1**, celda 103x103 |

**El héroe es MÁS ancho que una fila del grupo, y eso es la jerarquía.** Antes
era al revés — retrato de 256 al lado de filas de 440 — y se leía como que el
grupo importaba más que tú. Ahora 330 contra 300, con la fila del grupo por
debajo del retrato, que es la regla que se pidió.

**Los dos primeros bloques son de ancho FIJO y el tercero se estira, y esa es la
decisión.** Un retrato que crece con la resolución se ve mal, y una barra de vida
de 900 px no dice más que una de 300. Lo que gana con el sitio es *cuántos
enemigos caben* y *cuántas acciones*, así que esos dos son los que cuentan
columnas contra el ancho (`fill = "cols"`). Nadie escribe el 15 ni el 14.

**El bloque de la derecha se reparte de ABAJO A ARRIBA.** La carta bajó a una
sola fila (§10), así que se fija su alto pegado al suelo de la sala y todo lo que
sobra por encima es de los enemigos, que pasan de una fila a dos. Escrito en ese
orden en `Bar.lua` porque es el que expresa la decisión.

En píxeles de pantalla a x0.5625: retrato **186x144**, fila de grupo **169x45**,
cuadrado de enemigo **54**, botón de acción **58** (el de la barra de acciones
del juego mide 62 — se eligió para que se parezca), botón de las órdenes
globales **62**.

### La rejilla se centra sola

`dx`/`dy` siguen siendo el hueco del arte tal como salió del escaneo, y la
rejilla de dentro se centra en él (o se pega a un lado con `align`). Es lo que
permite comprobar un número de la tabla contra el PNG un mes después; un `dx`
ajustado a mano ya no se puede comprobar contra nada.

### Un área que no cabe no tiene celdas

Con `grow` a 1 el bloque de la derecha se queda en **48 px** de ancho. `SlotGrid`
devuelve 0 columnas, `Cells` una lista vacía y los paneles esconden sus botones —
en vez de dejar uno flotando encima de la rampa. La barra se ve pequeña, que es
exactamente lo que se pidió.

**"No cabe" es que no cabe una CELDA, no que el ancho sea negativo**, y esa
corrección es de 2026-08-22. Antes bastaba con `w <= 0` porque con las medidas
viejas ese bloque salía negativo por 18 px *de casualidad*. Al estrechar las
filas del grupo pasó a medir 48 — positivo, pero menos que una celda — y el
`if cols < 1 then cols = 1` que había debajo habría puesto un botón de 103 px en
un hueco de 48. La condición buena era siempre la de "cabe una celda entera", en
las dos direcciones y también para las rejillas de tamaño fijo. Lo cazó la misma
simulación fuera del juego que ya había cazado dos fallos en la ronda anterior:
**el reparto vuelve a comprobarse en un script de treinta líneas cada vez que se
toca un número, y esa es la práctica que hay que conservar de todo esto.**

## 4. Los módulos de contenido

`Bar.lua` ya no dibuja nada de dentro. Tiene el arte, las áreas y las celdas, y
tres funciones que usa todo lo demás:

```
B:SlotFrame(key)   el Frame de un área -- el padre de lo que se dibuje ahí
B:Cells(key)       las celdas, en coordenadas DEL MARCO (x derecha, y abajo)
B:OnLayout(fn)     avisar cuando la barra se ha vuelto a distribuir
```

`OnLayout` no es un detalle: cambiar `grow`, `share` o la resolución cambia el
**número** de celdas, no solo su tamaño, así que el contenido no se puede
colocar una vez y olvidarse.

| módulo | dónde | qué hace |
|---|---|---|
| `Widgets.lua` | — | barra de estado, texto, botón, color de clase y **un solo latido** de 5 Hz compartido |
| `Portrait.lua` | retrato | ya existía; ahora su hueco está en la sala |
| `Vitals.lua` | barras del héroe | vida, poder, recurso de clase, experiencia |
| `Roster.lua` | grupo | una fila por compañero; **click selecciona** |
| `Foes.lua` | objetivos | los hostiles de `TGTS` + tu objetivo; click = atacar |
| `Card.lua` | acciones | **BORRADO 2026-08-24**, ver §11.7: su banda es ahora la de habilidades y sus órdenes las hace el panel 4x4 |
| `Skills.lua` | habilidades | los huecos por personaje y los dos clicks derechos (§11) |
| `Roles.lua` | roles | las estrategias de combate que la clase del bot soporta (§11) |
| `Panel.lua` | órdenes 4x4 | 15 órdenes, a la selección o al grupo, y **salir del modo RTS** |
| `Route.lua` | el mundo | las rutas de shift + click derecho, dibujadas en el suelo |

`Rails.lua` **está borrado** desde 2026-08-22, con `UnitBar.lua` y
`CommandCard.lua`. El §10 dice por qué.

### `Panel` y la fila de órdenes de `Card` no son lo mismo

Y es toda la diferencia entre dos rejillas útiles y una repetida: la carta manda
a lo que tengas **seleccionado** (`Orders:Send`), el panel de la derecha manda al
**grupo entero** pase lo que pase (`Orders:Broadcast`).

## 5. Tres cosas que se comprobaron contra el cliente, no contra internet

Es la regla que ya costó `nameplateMaxDistance`, `gxWindowedResolution` y
`SetCamera(1)`. Aquí se aplicó tres veces **antes** de la primera pasada por el
juego, que es lo que se pretendía aprender de aquellas.

- **Los iconos de los raíles se le PEDÍAN al cliente**, y la técnica sigue siendo
  buena aunque el panel ya no exista: en vez de escribir doce rutas de memoria se
  hacía `MainMenuBarBackpackButton:GetNormalTexture():GetTexture()`, que no puede
  estar mal porque es literalmente el dibujo que hay en pantalla. Lo que falló no
  fue eso sino lo que había detrás del botón (§10).
- **`GetComboPoints` no tiene una firma, tiene dos.** La documentación de fuera
  dice `GetComboPoints()` y este cliente la quiere `("player", "target")`.
  Llamarla mal **no da error**: devuelve nil y los puntos no aparecen nunca. Se
  prueban las dos una vez, se recuerda la que contesta un número.
- **`SetRaidTarget` o `SetRaidTargetIcon`**, la que exista. Se coge con
  `SetRaidTarget or SetRaidTargetIcon` en vez de elegir una y descubrir que no
  está cuando el botón no haga nada.

## 6. Los iconos de hechizo son por CATEGORÍA, a propósito

Cincuenta hechizos serían cincuenta rutas escritas de memoria, y con el fallo
silencioso de arriba **la lista de rutas es la parte que se rompe** — y encima
parece un fallo de anclaje. Hay **diez** rutas, todas de iconos de toda la vida,
y cada hechizo dice a qué categoría pertenece: controlar, interrumpir, curar,
escudo, veneno, pegar, frenar, provocar. Debajo de cada botón va la etiqueta, así
que incluso si una ruta fallara el botón sigue diciendo lo que hace.

Los hechizos son **cinco por clase y todos de 3.3.5a**. Nada de poder sagrado, ni
Hex, ni fragmentos como pips: eso es de Cataclysm en adelante y aquí sería un
`cast` que el bot ignora en silencio.

## 7. Las marcas: playerbots ya tenía la mitad del gesto hecho

"Pedirle al mago que convierta en oveja al bicho con la luna" parecía la petición
más rara de la lista y no necesitaba nada nuevo. Comprobado en la fuente del
módulo (`RtiValue.cpp`, `RtiTargetValue.h`): cada bot tiene **dos** marcas.

| valor | por defecto | para qué |
|---|---|---|
| `rti <marca>` | `skull` | el que hay que matar |
| `rti cc <marca>` | `moon` | el que hay que dejar fuera de combate |

La IA de cada clase ya sabe que el objetivo de `rti cc` es el que se controla. Y
los nombres que acepta son `star circle diamond triangle moon square cross
skull`, en ese orden, que coincide uno a uno con los iconos 1..8 del cliente.

Así que un botón de marca hace las dos mitades del gesto de un RTS:

- **click**: pone el icono en tu objetivo (para que se vea) y manda
  `rti <marca>` a la selección.
- **click derecho**: lo mismo con `rti cc <marca>`.

## 8. Lo que se apartó, y la regla de siempre

`UnitBar` (retratos flotantes), `CommandCard` (rejilla 4x3 flotante) y `Targets`
(lista de objetivos) dicen ahora lo mismo que la sala. Se **apartan** al entrar,
no se borran: siguen siendo la interfaz con la barra apagada (`/rts bar`), que es
como se prueba media cosa.

Y se devuelven **al estado en que estaban**, no con un `Show()` a ciegas. Misma
regla dura que `Chrome` con los frames de Blizzard y `Camera` con sus CVars, y
las dos veces que se rompió fue por suponer el estado anterior en vez de
guardarlo.

## 9. Lo que esta ronda NO sabe todavía

- **Nada de esto se ha visto en juego.** La geometría se comprobó simulando el
  reparto fuera del juego (áreas, celdas, solapes y desbordes, a pantalla
  completa y en ventana), así que lo que puede fallar no son las medidas: son las
  llamadas del cliente que no se pueden probar desde fuera.
- **Los enemigos dependen del servidor.** `TGTS` es la única fuente que ve más
  allá de lo que el cliente tiene a mano; sin `mod-rts` cargado, en esa fila sale
  tu objetivo y nada más. No es un fallo del panel, es todo lo que el cliente
  sabe.
- **Los raíles tienen seis casillas y hay más candidatos que casillas.** Lo que
  hay está elegido, no derivado. Cambiarlo es una línea en la tabla `RAILS`.

---

## 10. La revisión de `PRUEBAS-10`, 2026-08-22

Primera vez en juego. La geometría aguantó entera -- que era lo que la simulación
prometía -- y **todo lo que falló fue una llamada del cliente o una decisión de
producto**, que es exactamente el reparto que la ronda anunciaba. Vale la pena
que quede escrito, porque justifica seguir simulando antes de compilar.

### Los raíles: doce botones, tres de ellos imposibles

El mapa no abría (G2), los talentos no abrían (G4) y el menú saltaba con
**"blocked from an action only available to the Blizzard UI"** (G5). Y los
iconos salían diminutos dentro de su casilla (G6).

`Rails.lua` decía, textualmente, *"nada de aquí está protegido: lo que está
protegido son las acciones de COMBATE"*. **Eso es falso en 3.3.5a**:
`ToggleWorldMap`, `ToggleTalentFrame` y `ToggleGameMenu` están protegidas igual
que `TargetUnit`, y no importa que el botón sea nuestro. La frase se escribió
razonando por analogía -- "esto no es combate, luego no estará protegido" -- que
es justo el tipo de afirmación que este proyecto lleva tres etapas aprendiendo a
no hacer. Y lo peor es que **era comprobable con un `/script ToggleWorldMap()`
en cinco segundos**: la regla de "comprobar contra el cliente" se aplicó a los
iconos, que era la parte visible, y no a las funciones, que era la parte que
decidía si el panel servía para algo.

Los iconos pequeños son el mismo panel diciendo lo mismo por otro lado: un
micro-botón es 32x64, la casilla 68x68, y dibujarlo con su proporción deja un
icono de 34 de ancho en un hueco de 68 -- correcto y feo.

**Se borra entero.** Las piezas `left-bar` se quedan como remate del arte
(pegadas, §1). El sitio no se recupera para nada porque estaba en los extremos;
lo que se recupera es la fila que ocupaban las marcas dentro de la sala.

### La carta: dos filas eran una de acciones y otra de otra cosa

`E4`-`E8` marcadas todas "no es lo que pedí". La fila de abajo eran las ocho
marcas de banda más cinco hechizos de la clase del bot seleccionado, y las dos
mitades sobraban por el mismo motivo: **no eran acciones de bot**.

- Las **ocho marcas** eran ocho botones para un gesto que sólo se usa de dos
  maneras -- "id a por ése" y "a ése controladlo". Ahora son **dos**: `Matar`
  (cráneo + `rti`) y `Contro` (luna + `rti cc`). El §7 sigue siendo correcto en
  todo lo que dice de playerbots; lo que cambia es cuántos botones hacen falta
  para usarlo.
- Los **hechizos de clase** eran cincuenta nombres escritos a mano y además sólo
  aparecían con un único bot seleccionado, así que la fila cambiaba de contenido
  según cuántas unidades tuvieras cogidas. Una carta de comandos no hace eso.
  Con ellos se va el §6 entero.

La carta queda en **una fila de doce órdenes de playerbots**, y la fila que
sobra se la lleva la de enemigos, que pasa a dos. Era la otra mitad de la
petición ("con esto tendremos algo más de espacio para los targets activos").

### El panel de la derecha: 4x3, no 3x3

Doce casillas, que es la carta de comandos de WC3. Las tres nuevas son `Cazar`,
`Botín` (`ll all` a todo el grupo) y `Revivir`.

### El retrato: cuerpo entero, y la tabla buscaba lo que no era

`B1`: sale el avatar completo y se quiere el busto. La tabla `FRAMINGS` de la
etapa anterior barría a la vez *el signo* del eje vertical y *el encuadre*, así
que la mitad de sus entradas eran de cuerpo entero -- y el cuerpo entero es
justo lo que sale por defecto, o sea que ninguna de esas podía ser la buena.
Ahora las siete son intentos de busto y lo único que se barre es lo que sigue
sin saberse: el signo y cuánta escala. `/rts portrait try` pasa a la siguiente.

`B6`: el marco amarillo de "seleccionado" estaba en la barra de vida del héroe
y se pidió que se ilumine el **avatar**, que es lo correcto -- en un RTS se
selecciona la unidad, y aquí la unidad es el retrato. Vive en `Portrait.lua`:
un marco de cuatro rayas alrededor del hueco **más** un empujón dorado a la luz
del modelo. Las dos cosas, no una: el marco es lo que se ve de reojo, la luz es
lo que hace que el personaje parezca encendido en vez de rodeado.

### Las guías eran ilegibles, y por la misma razón de siempre

`A4`. Los tamaños de fuente de `LayoutGuides` eran 10 y 11 -- números de
pantalla en un fichero **cuyos números son todos de dibujo**. La barra se dibuja
a x0.5625, así que un 11 acababa siendo seis píxeles. Ya van en 22 y 26, que es
la misma regla que `ns.W.FONT` lleva escrita desde que existe.

### Los tres paneles flotantes: borrados, no apartados

`H1`/`H2`: "no quiero volver a ese modo, ya tenemos hud definitivo".
`UnitBar.lua` y `CommandCard.lua` están borrados; de `Targets.lua` queda **sólo
la mitad de datos** -- la lista `TGTS` que alimenta la fila de enemigos, que no
tenía sustituto. Con ellos se va toda la maquinaria de "apartar y devolver al
estado en que estaban" del §8, que era correcta pero ya no tiene a quién
aplicarse.

Esto invalida el §8 tal como está escrito. La regla dura sigue viva donde
importa: `Chrome` con los frames de Blizzard y `Camera` con sus CVars.

---

## 11. La sección central: objetivos, habilidades y roles, 2026-08-24

El brief `brief-panel-control-personajes.md` pedía llenar la mitad derecha de la
sala con lo que falta para pelear: los objetivos del combate, las habilidades
del personaje que llevas seleccionado y unos botones de rol. Addon **0.47.0**,
mod-rts **0.14.0**. Nada de esto se ha visto en juego; `PRUEBAS-18` es la ronda.

### 11.1 El descubrimiento que cambió el planteamiento

**La mitad de lo que pedía el brief ya estaba construida, en el sitio
equivocado.** `CommandMode.lua` y `RtsCommandMode.cpp` ya hacían tres cosas:

| ya existía | qué es en el brief |
|---|---|
| `ActionBarSpells(bot)` | de dónde salen las habilidades de un compañero |
| `CastAs(bot, id, guid)` | la orden puntual: lanza a un guid **sin tocar** la selección del bot |
| `Aim(bot, guid)` | apuntar |

Vivían en un panel flotante que se abría con `/rts command`, o sea justo la
forma que `PRUEBAS-10` H1/H2 mandó borrar y que sobrevivió por no estar en la
lista de los tres. El trabajo no era escribirlo: era **mudarlo a la sala y
colgarlo de la selección**. `CommandMode.lua` está borrado y el modo ya no
existe -- seleccionar UNA unidad *es* tomar el mando.

Y una consecuencia que vale más que el ahorro: **"después el personaje vuelve a
su target anterior" no hay que implementarlo.** `CastAs` con un guid explícito
no escribe la selección del bot, así que su siguiente vuelta de IA elige
objetivo como siempre. Es el comportamiento por defecto.

### 11.2 Lo que el brief pedía y no puede existir

**Arrastrar habilidades desde el libro al hueco.** Para tu personaje existe;
para un bot no puede existir, y no es una limitación del cliente que se pueda
rodear: tu libro sólo tiene TUS hechizos. La Polimorfia del mago no está en tu
cursor porque no la conoces, y `PickupSpell` no la inventa.

La fuente que sí existe es la **barra de acciones del propio bot**, que además
es la lista buena: son los hechizos que pusiste ahí la última vez que jugaste
ese personaje, en tu orden, sin las cincuenta cosas del libro que nunca
pulsarías. Así que el hueco se llena **eligiendo** -- click derecho, sale su
lista -- en vez de arrastrando. Lo que se pedía (huecos vacíos, configurables,
por personaje) se cumple entero; cambia el gesto.

### 11.3 El reparto: cuatro bandas donde había tres

La sala mide **344 de alto** y eso lo fija el arte, así que subir `share` no
compra filas -- sólo las hace más grandes en pantalla. Dos bandas nuevas salen
de algún sitio, y salen de la fila de enemigos:

| banda | y | alto | rejilla | en 2560 (grow 4) |
|---|---|---|---|---|
| objetivos | 130 | 130 | celda 104x124, `fill` | **14** |
| divisor | 268 | 3 | — | — |
| habilidades | 279 | 111 | celda 103x103, `fill` | **14** |
| roles | 398 | 76 | **sin rejilla** | 2..5 según la clase |

`130 + 8 + 3 + 8 + 111 + 8 + 76 = 344` justos, así que tocar uno se ve
inmediatamente en el de arriba. La fila de enemigos pasa de dos a una: de treinta
objetivos visibles a catorce, **pagado a sabiendas**, y a cambio cada cuadrado
lleva ahora el NOMBRE debajo -- que era la otra mitad de lo que el brief pedía
con "mismo tratamiento visual que la fila de compañeros".

**Los roles no llevan rejilla, y esa es la única diferencia estructural con la
banda de arriba.** Las habilidades son "las que quepan" y por eso `Bar.lua` las
cuenta. Los roles son "los que tenga la clase", entre dos y cinco: una rejilla de
ancho fijo dejaría dos fuera con `grow` 3 y dejaría dos huecos vacíos con `grow`
5. `Cells` sin `cell` devuelve el área entera y `Roles.lua` la parte entre los
que haya.

`sim/bar_layout.py` cubre las dos cosas nuevas: que ninguna banda desborde, y que
un rol salga siempre **más ancho que alto** con 2 a 5 roles en todos los anchos
-- que es la única propiedad que distingue esa fila de una barra de botones. El
peor caso medido es 106x76 con `grow` 2, que es el régimen estrecho en el que ya
está todo lo demás.

### 11.4 Los roles son estrategias de playerbots, y cuáles tiene cada uno se pregunta

`tank`, `dps`, `heal` y `cc` están registradas **por clase** en el propio
mod-playerbots (`DruidAiObjectContext.cpp:34`, `PaladinAiObjectContext.cpp:93-95`
y sus hermanos), y `passive` es la que mod-rts ya usaba para dejar un bot quieto
mientras lanzas por él. O sea que "el rol condiciona el comportamiento
automático" no hay que construirlo: es lo que esas estrategias ya hacen, y lo
único que faltaba era un botón.

**La versión fácil de esto es una tabla de clase a roles en el addon** -- diez
clases por cinco roles escritos de memoria -- y es exactamente el fallo que este
proyecto lleva pagando desde `nameplateMaxDistance`: cuando falla no da error,
deja un botón que no hace nada. Lo contesta el servidor preguntándole a la IA del
bot qué estrategias soporta de verdad
(`AiObjectContext::GetSupportedStrategies`). En `Roles.lua` no hay ninguna lista
de clases; lo único que hay es la traducción del nombre de la estrategia a una
etiqueta, y una estrategia sin traducir sale con su propio nombre en vez de no
salir.

`tank`/`dps`/`heal` son **excluyentes** -- son la postura de combate de la clase,
y playerbots trata su propio comando `co` igual -- mientras `cc` y `passive` son
interruptores independientes. Quien aplica la exclusión es el servidor, y por eso
**un botón no se enciende al pulsarlo**: se manda `ROLE`, el servidor contesta
`ROLES` con el estado completo y de ahí sale el dibujo. Encender una postura
apaga las otras dos, y un botón que se ilumina con su propia petición escondería
justo ese efecto.

### 11.5 Los dos clicks derechos, y las dos son maquinaria de playerbots

| gesto | qué hace | cómo |
|---|---|---|
| click derecho sobre un objetivo | la siguiente habilidad va contra él, y luego el personaje vuelve a lo suyo | `CastAs` con guid explícito |
| doble click derecho | ese objetivo pasa a ser el suyo hasta nueva orden | `PFOCUS` |

`PFOCUS` se reparte en el servidor según a quién apuntes, y **ninguna de las dos
mitades es código nuestro**:

- **hostil** -> `orders::AttackBot`, la acción `attack my target` del propio bot.
  Es pegajosa por construcción: la IA sigue con lo que está atacando.
- **amigo** -> la lista `focus heal targets` de playerbots más la estrategia del
  mismo nombre (`TargetValue.h:161`, `StrategyContext.h:132`). Es literalmente
  "ocúpate de éste", y ya existía porque `focus heal` es un comando de chat.

La alternativa obvia -- reafirmar `SetSelection` en cada tick -- habría peleado
con el propio targeting del bot en empate. Es el mismo error de forma que la
retención de altura de cámara: corregir cada tick lo que otro escribe cada tick.

**El gesto no vive en `Foes.lua`.** El objetivo puede ser un amigo (el sanador
apunta al tanque), así que está en `Skills:TargetClick` y lo llaman la fila de
enemigos, las filas del grupo, el retrato del héroe y sus barras. Un reloj de
doble click por panel haría que pinchar un enemigo y luego un compañero contara
como doble click -- la misma razón por la que `Selection:Click` existe.

**Sólo en el HUD, no en el mundo.** En el mundo el click derecho ya significa
mover / atacar / hablar, que es el gesto central del RTS y que costó tres
intentos cerrar (`PRUEBAS-11` E1-E4). Sobrecargarlo según cuántas unidades
tengas cogidas es cambiarle el significado a lo que ya funciona.

### 11.6 Lanzar: dos caminos, y ninguno es el del cliente

`CastSpellByName` está **protegida** en 3.3.5a, y el rodeo habitual -- un botón
seguro -- no sirve aquí: el contenido de la fila cambia con la selección, y
cambiar los atributos de un botón seguro está **bloqueado en combate**, que es
justo cuando se usa. Los dos caminos van por el servidor:

```
bot    ->  CAST <bot> <id> [guid]     CastAs, por la IA del bot
heroe  ->  SELFCAST <id> [guid]       tu cuerpo lo lleva el servidor
```

`SELFCAST` es nuevo y existe para que la fila **no esté muerta con tu propio
personaje seleccionado**. Va por el servidor y no por el cliente para que las dos
mitades tengan la misma forma, en vez de añadir un segundo mecanismo con sus
propias reglas de combate. Y comprueba que el hechizo case con el objetivo antes
de lanzarlo: sin eso, un hechizo hostil sobre un amigo saldría como un fallo
mudo dentro del sistema de hechizos en vez de como una frase.

### 11.7 La carta de órdenes se fue, y el panel 4x4 hace las dos cosas

La banda que ocupan ahora las habilidades era la fila de trece órdenes de
playerbots dirigidas a la selección. El panel 4x4 de la derecha ya hacía doce de
ellas al grupo entero, así que las dos se juntan: **con algo seleccionado la
orden va a lo seleccionado; sin nada seleccionado va al grupo.**

**Un mismo botón con dos alcances es ambiguo, y por eso el alcance se ve.** Es el
riesgo conocido de haberlas juntado y se paga en pantalla, no en una ronda de
pruebas: las órdenes que respetan la selección salen con la etiqueta en AZUL y su
tooltip dice a cuántos van; en blanco significa grupo entero. Siete de las
dieciséis son globales por naturaleza (Reunir, Botín, Revivir, Formar, Salir y
las dos marcas) y se quedan siempre en blanco, que es lo que hace legible la
regla del resto.

### 11.8 Dos trampas que se vieron antes de compilar

- **`HasServer()` es falso durante el primer segundo.** Sólo se pone a true con
  la PRIMERA respuesta de mod-rts, que es un viaje de ida y vuelta que todavía no
  ha llegado al entrar en modo RTS. Pedir la barra de un bot en ese instante
  encontraba el canal cerrado y **no volvía a intentarlo nunca**, porque el único
  disparador era cambiar de selección. En juego se habría visto como un
  desplegable eternamente en "pidiendo su barra..." que se arregla solo al
  reseleccionar -- intermitente y con una solución que oculta la causa. Las dos
  filas reintentan cada 5 s. Mismo problema que `ApplyLootAllSoon` ya tuvo con
  `HasServer` en la etapa 5m.
- **Anclar una textura a otra textura.** El socket vacío iba con
  `SetAllPoints(b.icon)`, que no está garantizado en 3.3.5a y que si no funciona
  **no da error**: deja la ranura de tamaño cero, o sea un hueco que parece que
  no existe -- y justo en la pieza cuyo trabajo es decir "aquí va algo". Va
  anclado al botón con los mismos márgenes que el icono.

Y una tercera del mismo tipo: el nombre del enemigo se iba a dejar recortado por
un `FontString` de ancho y alto fijos, dando por hecho que el cliente corta lo
que sobra. Lo que hace en 3.3.5a es **partir en dos líneas** y dejar la segunda a
medias contra el borde. `SetWordWrap` no existe en esta versión, así que se
recorta contando letras: feo y exacto, que en esa fila es el orden de prioridades
correcto.

### 11.9 Lo que esta ronda no sabe

- **Nada se ha visto en juego.** La geometría está simulada, el C++ compila y
  enlaza, el addon pasa `check_addon.py` y el desplegado es idéntico al repo. Lo
  que queda por ver son las llamadas del cliente y el comportamiento de los bots.
- **Si `focus heal targets` hace lo que su nombre dice** es la apuesta más grande
  de la ronda. La estrategia y el valor existen y el comando de chat los usa, pero
  qué prioridad le da la IA de cada clase a ese objetivo frente al que se está
  muriendo no se puede leer del código en un rato.
- **`GetActionInfo` sobre las 120 ranuras** es la fuente de tus propios hechizos.
  Devuelve las barras que tengas puestas; una acción de macro o de objeto no
  entra, porque no se puede lanzar por id.

## 12. La revisión de `PRUEBAS-18`, 2026-08-27

Addon **0.48.0**, mod-rts **0.15.0**. `docs/PRUEBAS-19.txt` es la ronda. Lo que
toca a la consola:

### 12.1 No había ni un tooltip, y estaban todos escritos

`W:Tip` los pone en cada botón desde la 5k. **`GameTooltip` es un objeto ÚNICO**:
el mismo que dibuja "Lobo, nivel 8" sobre el mundo es el que usan nuestros
botones. La etapa 5i lo apagó negándole el `OnShow` — correctamente, es cromo de
Blizzard — y se llevó los nuestros por delante.

Ahora `Chrome` mira `GetOwner()`: si el dueño cuelga de `RTSBar` o `RTSHUD`,
pasa. `ns.IsOurs` sube por los padres buscando un nombre que empiece por `RTS`,
así que vale también para los botones **del cliente** reparentados en los railes
— su tooltip nativo vuelve gratis, sin una lista de excepciones que mantener.

La lección no es sobre tooltips: **apagar un objeto global de Blizzard "porque es
suyo" apaga también el uso que le damos nosotros**, y el síntoma aparece en el
sitio que menos lo relaciona.

### 12.2 Las marcas de apuntado existían en un panel de tres

El click derecho sobre una fila del grupo y sobre el retrato del héroe apuntaba
desde la 5n, pero sólo `Foes.lua` lo dibujaba. Una orden que se da y no se ve es
indistinguible de una que no se dio. `Roster` y `Portrait` llevan ahora las dos
marcas, **por dentro** del marco de selección: uno dice QUIÉN manda, el otro
SOBRE QUIÉN, y una fila puede llevar los dos a la vez.

Y la que sí se dibujaba no se veía: el puntual era un **velo a alfa 0,35** sobre
un retrato de colores y el foco cuatro barras a 0,95. La diferencia no estaba en
si la marca se ponía, estaba en cuánta tinta llevaba. Las dos siguen siendo
distinguibles por **color y grosor** — que se leen de reojo — en vez de por
"sólido contra translúcido", que hay que mirar de cerca.

El redibujo del retrato va en el **latido compartido**, no en la suscripción a la
selección: lo apuntado cambia por su cuenta (caduca a los 12 s, o el servidor
contesta un foco), y esperar a que alguien toque la selección dejaría un marco
puesto sobre una orden que ya no existe.

### 12.3 El socket de habilidad: una caja, no dos

La ranura vacía llevaba los mismos 3 de margen que el icono, así que medían lo
mismo y el hueco se leía como una casilla suelta flotando dentro de un rectángulo
negro. Va a ras del botón; el icono se apoya dentro. Es la forma de un botón de
acción de toda la vida, que es la que el ojo ya tiene calibrada.

Sigue **sin** anclarse al icono aunque sería más corto — es el aviso de §11.8, y
no ha dejado de ser cierto por resolverse otra cosa.

### 12.4 `HitRectInsets` dice dónde se pulsa, no dónde está el dibujo

El recorte del glifo de los micro-botones (etapa 5m bis) salió de deducir, de los
19 de margen inferior que declara el cliente, que el tercio de abajo es pedestal
y el glifo está arriba. En juego los recortes salieron **transparentes**, que no
es "salió el pedestal": es que ahí no hay píxeles.

Las ventanas van ancladas abajo y la tabla **lleva sello de generación**: lo
guardado era un índice válido cuyo SIGNIFICADO cambió, y comprobar el rango no
basta cuando lo que se mueve es lo que el número quiere decir.

`sim/bar_layout.py` cubre las siete, y la última ("sin recortar") sigue saliendo
al 48% del ancho de la bolsa **a propósito**: reproduce el fallo original, que es
la única forma de saber que la prueba tiene dientes.

### 12.5 Fijar bichos del mundo en la fila de enemigos

Click izquierdo sobre un hostil lo mete en la consola; **shift + izquierdo suma**.
Se pidió shift + DERECHO y no puede ser: ese gesto encadena puntos de ruta desde
la 5l, y darle un segundo significado según lo que hubiera bajo el cursor haría
que encadenar una ruta dependiera de con cuánta puntería pasaste por encima de un
lobo.

La lista es **aparte de `TGTS`** y tiene que serlo: `TGTS` significa "a esto le
está pegando alguien" y se reemplaza entera dos veces por segundo, así que un
bicho al que aún no ataca nadie desaparecería en medio segundo — justo el que
acabas de pinchar. Los fijados van **al final** de la fila: lo que hay delante es
el combate de verdad, y uno al que empieza a atacar el grupo sube solo porque
entra por la lista del servidor.

**No hay respaldo por proyección**, y es deliberado: la proyección sabe dónde está
una criatura pero no si es hostil (publica el tipo 3, que incluye al tabernero),
y metería PNJs amistosos en una fila cuyo click izquierdo es una orden de ataque.
El click derecho sí puede tirar de ella porque allí clasifica el SERVIDOR.

### 12.6 Lo que esta ronda no sabe

- Nada se ha visto en juego. El C++ compila y enlaza, el addon pasa
  `check_addon.py`, el desplegado es idéntico al repo y los dos simuladores
  pasan.
- **Si el recorte nuevo de los micro-botones es el bueno.** Se sabe que el de
  arriba estaba vacío; que el glifo caiga exactamente en el cuadrado de abajo es
  la apuesta, y por eso hay siete ventanas y un comando que las pasa en vivo.
- **Si `shadowLevel` basta para distinguir unidades.** 3.3.5a no expone tamaño ni
  dureza de la sombra, así que si no basta la respuesta es el círculo nativo bajo
  cada unidad del grupo — que existe desde la 5e, admite color por unidad, y hoy
  sólo lo llevan las seleccionadas. Eso es un estado más en el canal empaquetado,
  o sea recompilar `rts_core`.

---

## 13. La sala se vacía, 2026-09-02

Addon **0.49.0**. No es un arreglo ni una ronda de pruebas: es una decisión de
producto. Se pidió quitar *"toda la lógica y las funciones del medio de la HUD —
el héroe, las barras de los compañeros, las habilidades, los objetivos... todo"*
para **repensar de cero** qué va ahí dentro.

### 13.1 Qué se fue

Ocho ficheros, ~1.400 líneas, **borrados y no apartados**:

| fichero | qué era | por qué se va |
|---|---|---|
| `Portrait.lua` | modelo 3D del héroe | se repiensa |
| `Vitals.lua` | vida / poder / recurso / experiencia | se repiensa |
| `Roster.lua` | las cuatro filas del grupo | se repiensa |
| `Foes.lua` | la fila de objetivos | se repiensa |
| `Skills.lua` | huecos de habilidad, apuntado y foco persistente | se repiensa |
| `Roles.lua` | los botones de rol | se repiensa |
| `Targets.lua` | el sondeo `TGTS`, **sólo datos** | su único consumidor era `Foes` |
| `Focus.lua` | el lector flotante de foco | ver 13.2 |

`Focus.lua` **no estaba en la petición**, y tuvo que irse igualmente. Estaba
dormido desde 2026-08-15 por una sola línea:

```lua
if ns.Targets and ns.Targets.enabled then return end
```

Borrar `Targets` sin más habría hecho que esa condición fuera falsa y **habría
resucitado un panel flotante** — justo la clase de panel que `PRUEBAS-10` H1/H2
mandó borrar. Es el patrón que este proyecto lleva cinco etapas describiendo (un
apaño que sigue en pie después de que desapareciera aquello para lo que estaba),
sólo que **por una vez se vio ANTES de que produjera el síntoma**, porque al
borrar un módulo lo primero que se hizo fue buscar quién lo nombraba.

Ésa es la técnica, y vale más que el caso: **antes de borrar un módulo, `grep`
de su nombre en todo el addon.** No para arreglar las llamadas — eso es
evidente — sino para encontrar a quien lo usaba como *interruptor*.

### 13.2 Lo que se rehízo alrededor

- **`Bar.lua`** — el reparto interior de la sala (`HERO_W`, `PARTY_W`,
  `ROLES_H`, `SKILLS_Y`, `RULE_Y`, `FOES_H`, `HERO_X`, `PARTY_X`, `RIGHT_X`) se
  fue con el contenido. Queda **un solo hueco `hall`**, sin rejilla y sin
  anfitrión: el rectángulo útil, que es el dato que hace falta para decidir. Se
  ve con `/rts bar guides` y `/rts bar` imprime su tamaño.

  Los anchos eran decisiones sobre un contenido que ya no existe. Dejarlos
  puestos habría **predecidido el rediseño** — la próxima sala nacería con un
  bloque de héroe de 330 y cuatro filas de grupo porque estaban ahí, no porque
  se hubieran elegido.

- **`Camera.lua`** — fuera los manejadores de `TGTS`/`TGTEND`, `BARS`/`BARSEND`,
  `ROLES`, `PFOCUS` y `FOCUS`.
- **`Core.lua`** — fuera `/rts portrait`, `/rts skills`, `/rts foes`,
  `/rts roles`, `/rts targets`, `/rts release` y `/rts command`, sus líneas de
  ayuda y las dos globales de teclado que apuntaban a `Skills`.
- **`RTSMode.lua`** — el click izquierdo sobre un hostil ya no fija nada.
- **`Bindings.xml`** — ver 13.4.
- **`sim/bar_layout.py`** — simula el hueco `hall` en vez de las siete bandas.

### 13.3 Los verbos de mod-rts se quedan, y por qué

`CAST`, `SELFCAST`, `PFOCUS`, `ROLE`, `ROLES`, `BARS` y `TGTS` **siguen en
mod-rts**. No hay que recompilar nada.

El razonamiento, escrito para no volver a hacerlo:

1. **No hay tráfico que ignorar.** El sondeo `TGTS` lo hacía `Targets.lua` y la
   petición `BARS` la hacía `Skills.lua`. Sin quien pregunte, el servidor no
   dice nada — no es un canal encendido que haya que silenciar.
2. **Son la mitad de servidor de lo que se va a redisear.** La lección del §11.1
   fue que *la mitad del brief ya estaba construida en el sitio equivocado*.
   Borrar la mitad de servidor ahora garantizaría repetir exactamente ese
   descubrimiento dentro de un mes, y encima costando una recompilación cada
   vez.
3. **Un verbo sin cliente no falla en silencio: no corre.** Es la diferencia con
   una función escondida con su interruptor puesto, que sí se arma sola. La
   regla dura apunta a lo segundo.

Está escrito además en `Camera.lua`, donde estaban los manejadores, que es donde
alguien se hará la pregunta.

### 13.4 Diez teclas llevaban colgando desde agosto

Al quitar `RTSCOMMAND_RELEASE` y `RTSCOMMAND_COMMAND` (que llamaban a `Skills`)
apareció que `Bindings.xml` tenía **diez `RTSCOMMAND_SLOT1..10` apuntando a
`RTSCommand_CommandSlot`, una global que no existe** desde que se borró
`CommandMode.lua` el 2026-08-24. Una tecla así da un error de Lua cada vez que
se pulsa, y sólo si el jugador la había asignado.

No lo habría encontrado nadie mirando: no da error al cargar, ni en el
comprobador, ni en el juego salvo que se pulse. Ahora las 23 restantes se
comprueban contra `Core.lua` con una línea:

```bash
for f in $(grep -o "RTSCommand_[A-Za-z]*" Bindings.xml | sort -u); do
  grep -q "^function $f" Core.lua || echo "MISSING: $f"
done
```

**Merece estar en `check_addon.py`**, y es la primera entrada de la lista de
mejoras: es exactamente la misma familia que las dos comprobaciones que se le
añadieron en la etapa 5m — un fallo que no da error hasta que es tarde.

### 13.5 Las SavedVariables de la sala, tiradas al cargar

`RTSCommandDB.skills`, `.portrait`, `.targets`, `.targetsOn` y `.focus` se
ponen a `nil` en `Core.lua` al cargar. Un fichero de SavedVariables **no olvida
ninguna clave** y sobrevive a la versión que la escribió: es el `grow = 688` de
la etapa 5j y el `camHold` de la cámara borrada, dos veces ya.

Sin esto, el día que la sala se vuelva a llenar se encontraría con el encuadre
de un retrato que no existe y los huecos de habilidad de un diseño anterior.

### 13.6 Lo que queda en pie hoy

Dentro del modo RTS: la cámara, el ratón y sus gestos, la selección, las rutas
con shift, los marcadores de suelo, el botín, el selfbot, `Chrome` (esconder la
interfaz de Blizzard), la línea de mensajes de la HUD, el minimapa, los dos
raíles y la rejilla de órdenes 4x4.

Fuera: **los 344 x (710..2758) píxeles de dibujo del medio.**

Y una consecuencia que hay que tener presente al redisear: mientras dura la
salida aplazada en combate (§ `LeaveChrome`), el consuelo de *"te quedas con la
consola, que lleva tu vida y tu poder"* **ya no es cierto**. Está anotado en
`RTSMode.lua`. Es un argumento a favor de que la sala nueva vuelva a llevar el
estado del héroe.

---

## 14. La sala se llena otra vez: el panel de control de grupo, 2026-09-04

Addon **0.75.0**, mod-rts **0.36.0** (hay que reiniciar el servidor). Construido,
no visto todavía. El encargo es `Downloads/brief-barra-control-grupo.md`.

La sala llevaba vacía desde el 2 de septiembre, a propósito, para no predecidir
lo que iba dentro. Esto es lo que va dentro.

```
┌──────────┬──────────────────────────────────────────────┐
│ LISTA    │  ARRIBA   marcos: personaje / objetivo /     │
│ (héroe   │           objetivo de su objetivo            │
│  primero,├──────────────────────────────────────────────┤
│  x5)     │  ABAJO    huecos de hechizo                  │
│          │           4 botones de acción                │
└──────────┴──────────────────────────────────────────────┘
```

Cinco ficheros nuevos: `Hall.lua` (el reparto y el estado), `Party.lua` (la
columna), `Frames.lua` (los marcos), `Cast.lua` (los huecos y las acciones), y
`sim/hall_layout.py`. `Skills.lua` se reescribe.

### 14.1 LA MITAD DEL BRIEF YA ESTABA CONSTRUIDA, Y ESO SE MIRÓ ANTES

Es la lección de la etapa 5n aplicada a propósito esta vez — *antes de construir
lo que pide un brief, buscar si ya está puesto en otro sitio con otro nombre*.
Cuatro de las nueve cosas que pedía no había que escribirlas:

| lo que pedía el brief | lo que ya había |
|---|---|
| §7 *"analizar el asset, identificar el tramo central repetible y generar una versión recortada que tilee"* | **`middle.tga` ES esa pieza**, y `/rts bar grow <n>` la repite desde el 19 de agosto. Cero trabajo |
| §9.1 *"¿curar en focus existe o hay que programarlo?"* | **`PFOCUS`, compilado desde mod-rts 0.15.0.** Sobre un amigo pone `focus heal targets` y su estrategia, que es IA de playerbots. Faltaba el botón |
| §5 el segundo click sobre el mundo 3D | `Skills:Aiming()` / `AimAt` y el gancho de `RTSMode:OnLeftClick`, desde la etapa 5n |
| §4.1 *"ya existe una versión previa que se puede reaprovechar"* | `Skills.lua` entero, y `Roster.lua` en git para la columna |

### 14.2 EL SIM CAZÓ EL FALLO QUE DECIDIÓ LA FORMA

`sim/hall_layout.py` corrió **antes de escribir una línea de Lua**, y encontró
dos cosas. La cara:

**Las cuatro acciones no cabían al lado de la fila de hechizos.** Puestas a su
derecha competían por el ANCHO, y con la barra estrecha (`grow` 1) el reparto
daba **cero botones** — justo los cuatro que el brief llama caso de uso
prioritario. Con `grow` 2 salían a 73 contra 96 de los hechizos, o sea encogidas
por una razón que no tiene nada que ver con lo que son.

Van **apiladas debajo**. Compiten por el alto, que es fijo (238) y sobra, y
además se leen mejor: una fila de hechizos y una fila de acciones son dos cosas
distintas y en la misma línea parecían la misma.

La otra era mía y del propio guion: la comprobación del borde derecho sumaba los
huecos de botones que no existían, así que decía "se sale" de una fila vacía.

**La prueba tiene dientes**, comprobado: con `FIT_GUARD = False` las cinco
columnas con `grow` 1 salen a 17 px de dibujo en vez de rechazarse, y la
comprobación falla.

### 14.3 Las medidas, y de dónde salen

| pieza | medida (dibujo) | por qué |
|---|---|---|
| columna izquierda | 260 de ancho | el 12% de la sala con `grow` 4. Cabe un nombre a fuente 22 |
| fila de personaje | 65 de alto | 344 / 5 con 4 de separación |
| dentro de la fila | 24 nombre + 31 vida + 6 recurso | el nombre **encima**, no dentro (§3 del brief) |
| banda de marcos | 96 de alto | "el mínimo espacio vertical posible" (§2) |
| hueco de hechizo | hasta 112 | tope: más grande se ve como un cartel |
| botón de acción | hasta 96 | algo menor a propósito: es la fila secundaria |
| suelo de cualquiera | 40 | por debajo no se distingue el icono, y **no se dibuja** |

**La línea de recurso son 6 de dibujo = 3,4 de pantalla**, dentro del "2-4 px"
que pide el brief. Lo comprueba el sim, no el ojo.

### 14.4 §9.2 contestado con números

*"Confirmar que el ancho disponible permite 5 columnas × 4 slots."*

| `grow` | sala | columna | hueco de 4 | de 6 |
|---|---|---|---|---|
| 1 | 710 | 78 | **no cabe** | no cabe |
| 2 | 1222 | 180 | **no cabe** | no cabe |
| 3 | 1734 | 282 | 64 | 40 |
| **4** | **2246** | **385** | **90** | **57** |
| 5 | 2758 | 487 | 112 | 74 |

`grow` 4 es el que sale solo en 2560x1440 a pantalla completa, así que **sí,
holgado**. Por debajo de 3 no caben, y ahí **el panel lo dice y dice qué hacer**
(`/rts bar grow` o `/rts hall slots`) en vez de esconderlas: media consola vacía
sin motivo visible es peor que un mensaje.

### 14.5 LA LUZ CIRCULAR ES DEL CLIENTE, Y SALE GRATIS

El brief pide *"el efecto de luz circular recorriendo el borde, idéntico al
autocast de las mascotas de cazador"*. No hay que dibujarlo. Sacado leyendo el
FrameXML del cliente, no de memoria:

- `AutoCastShineTemplate` (`UIPanelTemplates.xml:699`) son 16 texturas de chispa
  con su `OnLoad`. Es una plantilla **virtual corriente**, no protegida: se
  hereda con `CreateFrame(..., "AutoCastShineTemplate")`.
- `AutoCastShine_AutoCastStart(frame, r, g, b)` la enciende
  (`UIParent.lua:3477`).
- **La animación la mueve `UIParent` en su propio `OnUpdate`**
  (`UIParent.xml:27` → `AutoCastShine_OnUpdate(nil, elapsed)`), recorriendo todas
  las encendidas. No hay que llevar ningún temporizador.

Dos trampas, las dos silenciosas:

- **EL FRAME TIENE QUE TENER NOMBRE.** `AutoCastShine_OnLoad` busca sus chispas
  con `_G[name..i]`. Sin nombre no da error: `self.sparkles` sale con 16 nil
  dentro y no se ve nada.
- **Hay que redimensionarla al botón.** El recorrido de la animación es
  `self:GetWidth()`, así que una luz de 28 sobre un hueco de 90 da la vuelta por
  donde no es.

### 14.6 Lo que NO se puede enseñar, dicho por delante

El brief pide *"avatar, barra de vida, energía/recurso, pet, runas… lo que
corresponda a esa clase"*.

- **El objetivo de un bot y el objetivo de su objetivo SÍ**, y sin servidor:
  `party1target` y `party1targettarget` son unidades válidas en 3.3.5a.
- **La mascota SÍ**: `party1pet`.
- **LAS RUNAS NO.** `GetRuneCooldown(i)` y `GetRuneType(i)` de 3.3.5a **no toman
  unidad** — son siempre las tuyas. No hay forma client-side de leer las runas de
  un caballero de la muerte del grupo.

  Dibujar seis rombos con TUS runas bajo el marco de OTRO sería un dato falso con
  pinta de bueno, que es el modo de fallo que este proyecto persigue desde la
  etapa 5i. Si se quieren de verdad es un verbo de mod-rts, y se hace el día que
  haya un caballero de la muerte en el grupo.

### 14.7 La rejilla 4x4 pierde su doble alcance, y eso deshace una decisión

Del 24 de agosto al 4 de septiembre la rejilla tuvo dos alcances: con algo
seleccionado la orden iba a lo seleccionado, sin nada al grupo. Estaba pensado y
señalizado — etiqueta azul y "→ N seleccionada(s)" en el tooltip.

§6 y §8 del brief lo cierran en el otro sentido: **siempre a todo el grupo**. Y
tiene sentido con la consola nueva delante, que es lo que ha cambiado: **ahora
hay un sitio donde mandar a UNO** — los cuatro botones de acción de la sala.
Antes no lo había, y por eso la rejilla hacía las dos cosas.

Cinco casillas no son órdenes y se quedan como están: Formar abre una lista,
Salir sale del modo, Control cambia o posee a UN personaje por definición, y las
dos marcas ponen un icono en tu objetivo.

### 14.8 Los gestos, todos en una tabla

| dónde | izquierdo | derecho |
|---|---|---|
| fila de la lista | seleccionar (doble = todos, shift = sumar) | **hacer primario** sin seleccionar |
| retrato del marco | seleccionar | — |
| hueco de hechizo | lanzar (o armar si pide objetivo) | **elegir qué hechizo va ahí** |
| botón de acción | ejecutar | **elegir qué acción va ahí** |
| con algo armado | ese es el objetivo | cancelar |

El derecho sobre una fila recupera el gesto del vídeo — *"the command bar for the
next person WITHOUT deselecting"* — que vivía en Tab hasta que se pidió quitarlo
(0.52.0). El **concepto** de primario se quedó entonces y el gesto se fue, así
que hasta hoy la única forma de ver los hechizos de alguien era seleccionarlo a
él solo, o sea soltar al grupo.

### 14.9 Lo guardado

```lua
RTSCommandDB.hall = {
    slots = 4,
    who = { ["Kirinah"] = { spells = {2050, nil, 596, 6}, actions = {"focus", ...} } },
}
```

Por **nombre** porque es la clave que el jugador reconoce y la que usan `BARS` y
`CAST`. **Los agujeros se conservan**: un hueco 3 vacío entre el 2 y el 4 es una
decisión, no un error de compactado.

Y **se acota al LEER**, que es la cuarta vez que hace falta en este addon después
del `grow = 688`, el `camHold` y el `railCropGen`. Un id que `GetSpellInfo` no
resuelve se descarta al cargar y se imprime cuántos.

**La clave vieja `RTSCommandDB.skills` se sigue tirando**, y que el nombre nuevo
sea distinto es lo que deja hacerlo sin pensarlo: reutilizarla habría hecho que
el primer arranque tras actualizar leyera huecos de un formato que ya no es.

### 14.10 Lo que queda por ver en juego

Nada de esto se ha visto. Lo que más probablemente falle, en orden:

1. **La luz circular.** Es la pieza con más supuestos del cliente, y sus dos
   modos de fallo son silenciosos (sin nombre no dibuja; mal dimensionada gira
   por fuera).
2. **`SetStatusBarTexture(r,g,b)`** para la barra plana. Se usa igual que
   `W:Bar` usa `SetTexture` para su fondo, pero sobre un `StatusBar` y no sobre
   una textura.
3. **El reparto con `grow` bajo**, que es donde el sim dice que las columnas se
   rechazan. Hay que ver que el mensaje sale y que no queda nada flotando.
4. **`GetComboPoints`**, que tiene dos firmas y se prueban las dos.
