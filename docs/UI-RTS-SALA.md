# La tercera exportación: cuatro piezas, siete paneles y la sala llena

Escrito 2026-08-20. Continúa `UI-RTS-PLANTILLA.md`, que llega hasta la segunda
exportación (siete TGA, la barra vacía con la huella de la rejilla dibujada).
Esto es lo que la llena.

Pantalla de referencia: **2560x1440**, `uiScale 0.86`. Todos los números son
**píxeles de dibujo** (el arte es 2x y se dibuja reducido) salvo donde diga
"px de pantalla".

---

## 1. El arte: cuatro ficheros, y dos se usan dos veces

| fichero | tamaño | de qué es |
|---|---|---|
| `left-bar.tga` | 128x512 | el raíl de botones de los extremos |
| `minimap.tga` | 512x512 | el panel cuadrado: minimapa, y otra vez para las órdenes |
| `middle.tga` | 512x512 | la sala; es la única pieza que **empalma consigo misma** |
| `ramp.tga` | 128x512 | el hombro, que baja del alto completo al alto de la sala |

La barra, de izquierda a derecha:

```
left-bar 128 | 16 | minimap 512 | ramp 128 | middle 512 xN | ramp' 128 |
minimap 512 | 16 | left-bar' 128                      = 1568 + 512N
```

`'` = espejada con `SetTexCoord(1, 0, 0, 1)`.

**Espejar en vez de exportar más piezas** no es solo por el tamaño (de 7 TGA y
4,2 MB a 4 y 2,6 MB). Es que un espejo **no puede desincronizarse del original**:
dos ficheros dibujados a mano que deberían ser iguales, sí. El precio es que el
hueco útil de una pieza espejada no está donde dice el escaneo sino en su
reflejo, y eso vive escrito en la tabla `HOLE` de `Bar.lua` con las dos
variantes, no recalculado a mano cada vez.

**Con N=4 en esta pantalla:** barra de **3616 x 512** de dibujo, escala
**x0.5625** (el 20% de 1440), o sea **2034 x 288 px de pantalla**, margen
**10,3%** a cada lado. En ventana maximizada (~1392 de alto útil) también salen
4 paneles y 11,6% de margen.

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
de margen y 16 entre bloques:

| bloque | x (rel. `ramp-left`) | y | tamaño | rejilla |
|---|---|---|---|---|
| retrato 3D | 29 | 130 | 256x256 | — |
| barras del héroe | 29 | 394 | 256x80 | 4 renglones |
| grupo | 301 | 130 | 440x344 | 1x4, celda 440x80 |
| enemigos | 757 | 130 | *lo que sobre* x110 | 14x1, celda 96x110 |
| divisor | 757 | 248 | *lo que sobre* x3 | — |
| acciones | 757 | 259 | *lo que sobre* x215 | 13x2, celda 103x103 |

**Los dos primeros bloques son de ancho FIJO y el tercero se estira, y esa es la
decisión.** Un retrato que crece con la resolución se ve mal, y una barra de vida
de 900 px no dice más que una de 440. Lo que gana con el sitio es *cuántos
enemigos caben* y *cuántas acciones*, así que esos dos son los que cuentan
columnas contra el ancho (`fill = "cols"`). Nadie escribe el 14 ni el 13.

En píxeles de pantalla a x0.5625: retrato **144**, fila de grupo **247x45**,
cuadrado de enemigo **54**, botón de acción **58** (el de la barra de acciones
del juego mide 62 — se eligió para que se parezca), botón de las órdenes
globales **81**, botón de raíl **38**.

### La rejilla se centra sola

`dx`/`dy` siguen siendo el hueco del arte tal como salió del escaneo, y la
rejilla de dentro se centra en él (o se pega a un lado con `align`). Es lo que
permite comprobar un número de la tabla contra el PNG un mes después; un `dx`
ajustado a mano ya no se puede comprobar contra nada.

### Un área que no cabe no tiene celdas

Con `grow` a 1 la sala mide 726 y el bloque de la derecha empieza en el 757: su
ancho sale **negativo**. `SlotGrid` devuelve 0 columnas, `Cells` una lista vacía
y los paneles esconden sus botones — en vez de dejar uno flotando encima de la
rampa. La barra se ve pequeña, que es exactamente lo que se pidió.

## 4. Los siete módulos de contenido

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
| `Foes.lua` | enemigos | los hostiles de `TGTS` + tu objetivo; click = atacar |
| `Card.lua` | acciones | órdenes de la selección + 8 marcas + hechizos de su clase |
| `Panel.lua` | órdenes 3x3 | 8 órdenes al grupo entero y **salir del modo RTS** |
| `Rails.lua` | los dos raíles | minimapa a la izquierda, ventanas del juego a la derecha |

### `Panel` y la fila de órdenes de `Card` no son lo mismo

Y es toda la diferencia entre dos rejillas útiles y una repetida: la carta manda
a lo que tengas **seleccionado** (`Orders:Send`), el panel de la derecha manda al
**grupo entero** pase lo que pase (`Orders:Broadcast`).

## 5. Tres cosas que se comprobaron contra el cliente, no contra internet

Es la regla que ya costó `nameplateMaxDistance`, `gxWindowedResolution` y
`SetCamera(1)`. Aquí se aplicó tres veces **antes** de la primera pasada por el
juego, que es lo que se pretendía aprender de aquellas.

- **Los iconos de los raíles se le PIDEN al cliente.** El cliente está dibujando
  esos doce botones ahora mismo, así que en vez de escribir doce rutas de memoria
  se hace `MainMenuBarBackpackButton:GetNormalTexture():GetTexture()`. Eso no
  puede estar mal: es literalmente el dibujo que hay en pantalla. Escribir
  `Interface\Icons\INV_Misc_Bag_08` es una apuesta, y **una ruta que no existe no
  da error, dibuja nada**. El precio es la forma — los micro-botones son 32x64,
  no cuadrados, así que se dibujan con su proporción dentro de la casilla en vez
  de estirarlos. Si algún frame no estuviera, el botón lleva interrogante y
  `/rts rails` dice cuál.
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
