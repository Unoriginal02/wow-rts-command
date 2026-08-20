# Plantilla: la barra inferior del modo RTS

Guía de corte para dibujar el arte de la barra de abajo a mano: **qué mide cada
sección y en qué ficheros se parte**. Escrito 2026-08-19.

Es la continuación de `UI-RTS-ESTUDIO.md`. El estudio dice qué hay que saber
antes de dibujar; esto son las medidas concretas, ya derivadas, para poder abrir
el editor de imagen hoy.

Pantalla de referencia: **2560x1440**, `uiScale 0.86`. La HUD lleva su propia
escala de píxel, así que **todos los números de este documento son píxeles
físicos** y dentro de la HUD 1 unidad = 1 píxel.

---

## 1. Las dos cifras, y de dónde salen

No están elegidas a ojo. Salen de cruzar la regla dura del estudio (apartado
1.1: texturas potencia de dos, máximo 512) con las constantes que ya tiene
`HUD.lua`:

```
HeightForCell(px) = TOP + BOTTOM + ROWS*px + CELLGAP*(ROWS-1)
                  =  30  +   24   +  3*px  +    5*2
```

| botón | barra | ¿potencia de dos? |
|---|---|---|
| 62 px (lo medido de `ActionButton1` en tu pantalla) | 250 px | no / no |
| **64 px** | **256 px** | **sí / sí** |

**Botón 64 -> barra 256, exacto.** Y eso decide todo lo demás:

- Una textura de 64x64 dibujada a 64x64 no se interpola. Una de 62 sí.
- 256 es el alto de la barra *y* un tamaño legal de fichero, así que una pieza
  de 256 de alto se dibuja a su tamaño nativo.
- 62 -> 64 son 2 píxeles de diferencia sobre el botón que tienes calibrado en la
  retina. No se ve. Los 6 px que crece la barra, tampoco.

**Esto contesta `PRUEBAS-9` B3.** La prueba pedía un número decidido mirando; la
regla de potencias de dos lo da mejor. Lo que queda de B3 es sólo confirmar que
un botón de 64 no se siente pequeño al lado de la barra de acciones del juego —
un sí o un no, no una medida.

> **La regla, en una línea:** el fichero es potencia de dos **y** se dibuja a su
> tamaño nativo. Las dos cosas. Cumplir sólo la primera y estirar la pieza al
> colocarla da exactamente la misma borrosidad que incumplirla.

### 1.1 El precio de fijar 256, dicho ahora

`H:Fit()` deriva hoy la altura del botón de la barra de acciones, que cambia con
la resolución y el `uiScale`. **Con arte propio eso ya no puede mandar**: si Fit
devuelve 250 o 274, el arte de 256 se estira y se pierde todo lo anterior.

Cuando existan los ficheros, la altura se **fija** en 256 (`/rts ui height 256`)
y `fit` pasa a ser un diagnóstico, no la autoridad. La consecuencia es real y
conviene aceptarla a propósito: a 1440 la barra ocupa el 17.8% del alto, y a
1080 la misma barra de 256 px ocupa el 23.7%. Se ve más grande en pantallas más
pequeñas. La alternativa — reescalar — cambia nitidez por proporción, y en un
arte dibujado a mano la nitidez vale más.

(Arreglo elegante para más adelante: que `Fit()` no devuelva cualquier número,
sino que **encaje** al más cercano de {32, 64, 128} px de botón -> {160, 256,
448} px de barra. Así sigue adaptándose y sigue siendo 1:1. Son cuatro líneas y
no hacen falta para dibujar.)

### 1.2 El lienzo NO hay que llenarlo

La regla de potencias de dos es del **fichero**, no del dibujo. Lo que sobra se
deja transparente y no pasa absolutamente nada.

**La prueba está en esta carpeta:** `halo-01.tga` es un aro *redondo* dentro de
un fichero *cuadrado* de 256x256. Las cuatro esquinas están vacías — un 21% de
lienzo tirado — y carga y funciona desde la Etapa 5c.

Lo que sí manda es la otra mitad de la regla del apartado 1: **el trozo se dibuja
a su tamaño nativo.** Un fichero de 64x256 con contenido sólo en 48 px de ancho,
metido en un frame de 64x256, sale 1:1 igual de bien. El tamaño del **fichero** y
el tamaño de lo **dibujado** son cosas distintas.

Lo único que cuesta el relleno transparente son bytes:

| fichero | bytes | si sólo usas... | desperdicio |
|---|---|---|---|
| 64 x 256 | 65 580 | 48 de ancho | 16 KB |
| 512 x 256 | 524 332 | 310 de ancho | 207 KB |

Con siete u ocho piezas eso da igual. Con setenta, no — y entonces se empaqueta
(ver abajo).

**Así que cuando una sección no mida potencia de dos, hay tres salidas, y la
elección es de ARTE, no de formato:**

1. **Ficheros separados.** Cada pieza en su fichero, cada uno potencia de dos,
   desperdicio casi cero. **Vale cuando cada pieza tiene su propio borde**, o sea
   cuando se leen como dos objetos puestos al lado.
2. **Un fichero con relleno.** La sección entera en el fichero potencia de dos
   siguiente, y lo que sobra transparente. **Hace falta cuando un solo borde
   envuelve las dos cosas** — si están *soldadas*, el borde tiene que ser continuo,
   y un borde continuo partido en dos ficheros deja costura. El desperdicio es el
   precio de no tener costura.
3. **Atlas + `SetTexCoord`.** Varias piezas empaquetadas en un 512x512 y cada
   frame se queda con su rectángulo. Es lo que menos memoria gasta y lo que
   recomienda el apartado 6 del estudio para muchas piezas.
   **Con arte propio esto NO es adivinar**: `Skin.lua` evita `TexCoord` porque
   recortar las hojas *de Blizzard* a ciegas es adivinar coordenadas, pero las
   tuyas las has cortado tú y sabes el rectángulo al píxel. La regla de no
   adivinar sigue en pie; simplemente aquí no aplica.

**La pregunta que decide, en una línea:** ¿un solo borde envuelve las dos cosas, o
cada una lleva el suyo? Soldadas -> un fichero con relleno. Separadas -> dos
ficheros.

### 1.3 La escala completa de potencias de dos

Los únicos lados legales, y lo que pesa cada uno en TGA de 32 bits
(`18 + ancho*alto*4 + 26`):

| lado | lienzo cuadrado | bytes | para qué sirve aquí |
|---|---|---|---|
| **1** | 1 x 1 | 48 | un píxel de color plano, para rellenos |
| **2** | 2 x 2 | 60 | — |
| **4** | 4 x 4 | 108 | — |
| **8** | 8 x 8 | 300 | líneas y separadores en mosaico |
| **16** | 16 x 16 | 1 068 | esquinas y remaches pequeños |
| **32** | 32 x 32 | 4 140 | **botón del raíl** (`btn-32`) |
| **64** | 64 x 64 | 16 428 | **ranura de la rejilla** (`slot`) |
| **128** | 128 x 128 | 65 580 | **aro de retrato** (`ring-128`) |
| **256** | 256 x 256 | 262 188 | **marco del mapa, extremos y relleno del centro** |
| **512** | 512 x 512 | 1 048 620 | el techo. Sólo si hace falta un atlas |

**512 es el máximo** según el apartado 1.1 del estudio. Nada de este plan lo
necesita, así que el techo no se ha vuelto a comprobar contra este cliente: si
alguna vez hace falta pasar de ahí, se prueba antes de dibujar.

**Los dos lados van por separado y no tienen que ser iguales.** Cualquier
combinación de la columna de la izquierda es legal:

| fichero | bytes | típico de |
|---|---|---|
| 512 x 512 | 1 048 620 | atlas |
| 512 x 256 | 524 332 | una sección entera con relleno |
| 512 x 128 | 262 188 | una tira ancha y baja |
| 512 x 64 | 131 116 | un separador largo |
| 512 x 32 | 65 580 | una línea decorativa |
| 256 x 256 | 262 188 | marco de panel |
| 256 x 64 | 65 580 | una pestaña |
| 128 x 64 | 32 812 | una placa de nombre |
| **64 x 256** | **65 580** | **el raíl de botones — alto y estrecho** |
| 64 x 32 | 8 236 | una flecha |

### 1.4 Tabla de redondeo: contenido -> fichero

Lo que hay que consultar cuando una medida no cuadre. **Se sube al siguiente
lado legal y el resto va transparente** (apartado 1.2):

| contenido | fichero | desperdicio | |
|---|---|---|---|
| 48 (raíl) | **64** | 16 px (25%) | 16 KB, nada |
| 56 | **64** | 8 px (12%) | |
| 96 | **128** | 32 px (25%) | por esto los retratos son de 128 |
| 192 (hueco del mapa) | **256** | 64 px (25%) | ese "desperdicio" es el borde de 32+32 |
| 202 (rejilla 3x3) | **256** | 54 px (21%) | |
| 224 (hueco útil) | **256** | 32 px (12%) | |
| 271 (carta 4x3) | **512** | 241 px (47%) | por esto la carta no va en fichero propio |
| 310 (sección izq.) | **512** | 202 px (39%) | el precio de soldar raíl y marco |
| 480 | **512** | 32 px (6%) | |
| 672 (fila de 5 retratos) | 1024 | — | **pasa de 512: hay que trocear** |
| 1280 (panel central) | 2048 | — | **pasa de 512: hay que trocear** |
| 2560 (banda entera) | 4096 | — | **pasa de 512: hay que trocear** |

**La lectura útil de esta tabla:** el desperdicio no crece poco a poco, salta.
Entre 257 y 512 pagas un fichero de 512 igual, así que **una medida de 260 cuesta
lo mismo que una de 510** — si te pasas de 256 aunque sea por 4 px, aprovecha
hasta 512. Y en cuanto pasas de 512 el redondeo deja de ser una opción: hay que
trocear, que es exactamente por lo que el panel central va en tres piezas.

---

## 2. La distribución: tres islas, no una banda

**Tres paneles separados, con mundo entre ellos.** Minimapa pegado a la
izquierda, acciones de bots pegado a la derecha, control del grupo centrado.

Es lo que recomienda el apartado 6 del estudio (WC3 y SC2 anclan al
centro-abajo y dejan ver el mundo a los lados) y además es lo que hace el arte
dibujable: a 2560 de ancho, una banda continua obliga al centro a medir ~2000
px, y ninguna textura pasa de 512.

**Lo importante: elegir islas o banda continua NO cambia la lista de ficheros.**
El panel central mide 1280, que ya pasa de 512, así que va en tres piezas de
todos modos — dos extremos fijos y un relleno en mosaico. Estirar ese relleno de
768 a 1464 px es cambiar un número, no redibujar nada. Por eso el corte de abajo
sirve para las dos, y la decisión se puede tomar viéndolo en pantalla.

Cada isla de los extremos lleva además un **raíl** de botones pequeños de 32 px
pegado a su lado exterior: a la izquierda, los del mapa (zoom, rastreo, mapa del
mundo); a la derecha, los iconos de juego del apartado 5.5 del estudio (bolsas,
personaje, hechizos, talentos). Son la misma pieza espejada, así que **un solo
fichero viste los dos** (`SetTexCoord(1,0,0,1)` lo voltea, gratis).

Poner raíl también a la derecha no es adorno: es lo que devuelve la simetría
después de añadir el de la izquierda, y de paso le da casa a los iconos de juego,
que hasta ahora no la tenían.

```
2560 x 1440                                            1 unidad = 1 px
+---------------------------------------------------------------------+
|                                                                     |
|                          ( mundo )                                  |
|                                                                     |
| +-+--------+        +--------------------------+        +--------+-+ |
| |o|        |        |   CONTROL DEL GRUPO      |        |        |o| |
| |o| MINI   |        |   1280 x 256             |        |  BOTS  |o| |
| |o| 256    |        |                          |        |  256   |o| |
| |o|        |        |                          |        |        |o| |
| +-+--------+        +--------------------------+        +--------+-+ |
+---------------------------------------------------------------------+
 22 48   256    308             1280              308   256    48  22
 pad                                                              pad
    <--- 310 --->                                     <--- 310 --->
```

| | x inicio | x fin | ancho | alto |
|---|---|---|---|---|
| margen (`pad`) | 0 | 22 | 22 | — |
| raíl del mapa | 22 | 70 | 48 | 256 |
| hueco | 70 | 76 | 6 | — |
| minimapa | 76 | 332 | 256 | 256 |
| hueco (mundo) | 332 | 640 | 308 | — |
| control del grupo | 640 | 1920 | 1280 | 256 |
| hueco (mundo) | 1920 | 2228 | 308 | — |
| acciones de bots | 2228 | 2484 | 256 | 256 |
| hueco | 2484 | 2490 | 6 | — |
| raíl de iconos de juego | 2490 | 2538 | 48 | 256 |
| margen (`pad`) | 2538 | 2560 | 22 | — |

Vertical: todo apoya en `y = 22` y llega a `y = 278`. La barra ocupa el **17.8%**
del alto de pantalla; con su margen, el 19.3%.

**Variante banda continua**, si al verlo te gusta más: el panel central crece
hasta tocar a sus vecinos (1976 px con `gap` de 14). El relleno pasa de 3 a 5.72
repeticiones y no se toca ni un fichero.

---

## 3. Sección por sección

### 3.1 Minimapa y su raíl — 310 px de ancho, dos ficheros

```
   raíl 48         marco del minimapa 256
 +--------+   +----------------------------+
 |        |   |                            |   ^ borde 32
 |  +--+  |   |   +--------------------+   |   v
 |  |32|  |   |   |                    |   |   ^
 |  +--+  |   |   |                    |   |   |
 |  |32|  |   |   |   hueco del mapa   |   |   |
 |  +--+  |   |   |     192 x 192      |   |  192
 |  |32|  |   |   |                    |   |   |
 |  +--+  |   |   |    (192 = 3 x 64)  |   |   |
 |  |32|  |   |   |                    |   |   |
 |  +--+  |   |   +--------------------+   |   v
 |  |32|  |   |                            |   ^ borde 32
 |        |   |                            |   v
 +--------+   +----------------------------+
   64 px          256 px de ancho
   de fichero
```

**El alto de 256 sale de tres trozos, no de los botones solos:**

| | raíl | marco del mapa |
|---|---|---|
| borde de arriba | 32 | 32 |
| centro | **columna 192** | **hueco 192** |
| borde de abajo | 32 | 32 |
| **total** | **256** | **256** |

Y la columna de 192 es `5 x 32 = 160` de botón **más** `4 x 8 = 32` de huecos.
Los botones por sí solos miden 160; son los huecos los que la llevan a 192.

Que la columna mida lo mismo que el hueco del mapa, y que las dos lleven el mismo
borde de 32, es lo que hace que el raíl alinee arriba y abajo con el mapa. No está
elegido a ojo: sale de las medidas que ya había.

- **`mini-frame.tga` — 256x256.** El marco entero, con el hueco central
  **transparente (alfa 0)**, porque se dibuja *encima* del minimapa: así el
  borde monta sobre el canto del mapa y no queda una costura.
- **`rail.tga` — 64x256, contenido en 48.** El raíl: borde 8 + hueco de 32 +
  borde 8. Los 16 px que sobran del fichero van transparentes, y eso son 16 KB —
  ver 1.2. **Este mismo fichero viste el raíl de la derecha, espejado** con
  `SetTexCoord(1, 0, 0, 1)`. Si tu dibujo ya es simétrico, ni eso hace falta.
- **`btn-32.tga` — 32x32.** La ranura del botón pequeño. Es la hermana chica de
  `slot.tga`; los iconos de dentro salen de `Interface\Icons\`.

**Por qué DOS ficheros y no uno de 512x256.** Aquí aplica la regla de 1.2: si el
raíl y el marco del mapa llevan **cada uno su borde**, van separados y el
desperdicio es de 16 KB. Si los dibujas **soldados**, con un solo borde
envolviendo los dos, entonces tienen que ir en un único fichero de 512x256 (207
KB de relleno) o el borde saldría partido. **Lo decides al dibujar el boceto de
2560x256; el código se adapta a las dos.**
- **`mini-mask.tga` — 256x256, opcional.** La máscara recorta el mapa. Blanco =
  se ve, negro/transparente = no. Un cuadrado con las esquinas cortadas o
  redondeadas es de dónde sale el aire de SC2. Hoy el código usa
  `Buttons\WHITE8X8`, que es el cuadrado pelado.
- El borde de 32 no es obligatorio, es lo que deja 192 de hueco — y 192 es 3x64,
  así que casa con la rejilla del resto. Si lo haces más gordo, el mapa se ve más
  pequeño: `Minimap` se **escala**, no se redimensiona (cambiar su tamaño cambia
  cuánto mundo se ve; escalarlo, no).

### 3.2 Control del grupo — 1280 x 256, tres ficheros

El de "crowd control": quién está seleccionado, el grupo, y qué se le puede
ordenar. Distribución de WC3, de izquierda a derecha.

```
|<-256 fijo->|<---- 768 en mosaico (3 x 256) ---->|<-256 fijo->|
+------------+------------------------------------+------------+
| borde 16                                            borde 16 |
|  +-------+   +---+ +---+ +---+ +---+ +---+   +--+--+--+--+   |
|  | SELEC |   | 1 | | 2 | | 3 | | 4 | | 5 |   |  |  |  |  |   |
|  | 128   |   +---+ +---+ +---+ +---+ +---+   +--+--+--+--+   |
|  | x128  |    retratos del grupo, 128 c/u    |  |  |  |  |   |
|  +-------+                                   +--+--+--+--+   |
|   nombre                                     |  |  |  |  |   |
|   vida                                       +--+--+--+--+   |
|                                               carta 4x3      |
+------------+------------------------------------+------------+
   128    24            672              24          271
```

Presupuesto interior — panel 1280, borde 16 por lado, **hueco útil 1248 x 224**:

| bloque | cuenta | ancho | alto |
|---|---|---|---|
| unidad seleccionada | aro 128 + texto debajo | 128 | 168 |
| hueco | | 24 | |
| retratos del grupo | 5 x 128 + 4 x 8 | 672 | 128 |
| hueco | | 24 | |
| carta de comandos 4x3 | 4 x 64 + 3 x 5 | 271 | 202 |
| **gastado** | | **1119** | máx. 202 |
| **holgura** | | **129** | 22 |

Los 129 px que sobran son a propósito: caben una tira de estado, huecos más
anchos, o un sexto retrato. Dibujarlos apretados es lo que obliga a rehacer.

- **`mid-left.tga` — 256x256.** Extremo izquierdo con su borde.
- **`mid-fill.tga` — 256x256.** Se repite en horizontal (`SetHorizTile(true)`).
  **Su columna de píxeles izquierda tiene que empalmar con la derecha**, o se ve
  una raya vertical cada 256 px. Es el único fichero con una regla propia.
- **`mid-right.tga` — 256x256.** Extremo derecho con su borde.

**Por qué 128 y no 96 en los retratos.** 96 no es potencia de dos: viviría en un
fichero de 128 dibujado a 96, o sea interpolado. Con 128 el retrato es 1:1 y
además es el tamaño que hace que la fila de cinco mida 672 y quepa holgada. Si
prefieres retratos pequeños, el otro tamaño legal es 64 (fila de 344), y entonces
el panel entero se puede bajar a 1024.

### 3.3 Acciones de bots — 256 x 256, un fichero

```
+----------------------------+ 256
| borde 16    ACCIONES       |
|   +----+ +----+ +----+     |
|   | 64 | | 64 | | 64 |     |
|   +----+ +----+ +----+     |   3 x 3 = 9 acciones
|   +----+ +----+ +----+     |   202 x 202 de contenido
|   |    | |    | |    |     |
|   +----+ +----+ +----+     |
|   +----+ +----+ +----+     |
|   |    | |    | |    |     |
|   +----+ +----+ +----+     |
+----------------------------+
```

Hueco útil 224 x 224, contenido 202 x 202, holgura 22. Nueve botones para
`follow` `stay` `attack` `pull` `flee` `formation` `guard` `grind` `max dps`.
Todo eso son comandos de chat, así que son botones normales y sin restricción de
combate — el apartado 5.4 del estudio: la sección más fácil de las cinco.

**El coste de querer doce, dicho antes de dibujar:** cuatro columnas de 64 miden
271, que no cabe en 224. Y bajar el botón a 52 para que quepa rompe el 1:1. Así
que doce botones significa **panel de 512 de ancho** (el siguiente tamaño legal),
no de 300. Las salidas son tres: quedarse en 9, ir a un panel de 512x256, o poner
dos paneles de 256 uno al lado del otro y tener 18.

---

## 4. La lista de ficheros

Todos: **TGA de 32 bits sin comprimir** (ver apartado 5).

| fichero | tamaño | qué es | ¿obligatorio? |
|---|---|---|---|
| `mini-frame.tga` | 256 x 256 | marco del minimapa, hueco transparente | sí |
| `mini-mask.tga` | 256 x 256 | máscara del mapa (blanco = visible) | no |
| `rail.tga` | 64 x 256 | raíl de botones pequeños, contenido en 48 — **sirve para los dos lados, espejado** | sí |
| `btn-32.tga` | 32 x 32 | ranura del botón pequeño del raíl | sí |
| `mid-left.tga` | 256 x 256 | extremo izquierdo del panel central | sí |
| `mid-fill.tga` | 256 x 256 | relleno en mosaico — **empalma consigo mismo** | sí |
| `mid-right.tga` | 256 x 256 | extremo derecho del panel central | sí |
| `acts-frame.tga` | 256 x 256 | panel de acciones de bots | sí |
| `slot.tga` | 64 x 64 | ranura de botón, la de toda rejilla | sí |
| `slot-hi.tga` | 64 x 64 | ranura con el ratón encima | no |
| `slot-down.tga` | 64 x 64 | ranura pulsada | no |
| `ring-128.tga` | 128 x 128 | aro de retrato (grupo y selección) | sí |

**Nueve obligatorios, doce con todo.** Unos 1.8 MB en TGA. Dos tamaños de ranura
(64 y 32) y un solo aro sirven para todas las secciones a propósito: menos
ficheros que rehacer cuando cambie el estilo.

Ninguno de los doce llega a 512 en ningún lado, así que **ninguno necesita
`TexCoord`** — salvo el volteo del raíl, que es un espejo, no un recorte. Si algún
día quieres empaquetarlos en un atlas por memoria (apartado 1.2, opción 3), caben
los doce en dos ficheros de 512x512 y el corte no cambia.

---

## 5. Cómo dibujarlo, y cómo exportarlo

### 5.1 Dibuja el conjunto, corta después

**No dibujes las piezas una a una.** Abre un lienzo de **2560 x 256** — la banda
entera a lo ancho de tu pantalla — y píntala como si fuera continua, con guías en
las x de la tabla del apartado 2. Cuando te guste, recorta las piezas de ahí.

Es la única forma de que el arte case: la iluminación, el desgaste de la piedra y
el grosor del reborde tienen que ser los mismos en los tres paneles, y eso a
trozos separados no sale.

Para `mid-fill.tga`, recorta una franja de 256 de una zona que ya se repita sola,
y comprueba la costura pegándola dos veces al lado antes de darla por buena.

### 5.2 Exportar

Verificado leyendo la cabecera de `halo-01.tga`, que es la que ya carga en el
juego:

```
byte  2 = 2     imagen truecolor SIN COMPRIMIR   <- lo que más falla
bytes 12-15     256 x 256
byte 16 = 32    32 bits por píxel
byte 17 = 8     8 bits de alfa
tamaño = 18 (cabecera) + ancho*alto*4 + 26 (pie TGA 2.0)
```

Al exportar: **32 bits con alfa, compresión RLE DESACTIVADA.** El RLE es la
casilla que casi todos los editores traen marcada, y un TGA comprimido **no da
error: no carga**. Si una pieza sale invisible, esa casilla es la primera cosa
que mirar.

Comprobación sin abrir el juego — el tamaño en bytes tiene que ser exacto:

| tamaño | bytes |
|---|---|
| 256 x 256 | 262 188 |
| 128 x 128 | 65 580 |
| 64 x 64 | 16 428 |

Si un fichero pesa menos, va comprimido. (Sin pie TGA 2.0 son 26 bytes menos y
también carga; lo que no puede es pesar mucho menos.)

### 5.3 Dónde van y cómo se llaman

Se editan en el repo y viajan con `Deploy_Addon.bat`, que es `robocopy /MIR` y se
lleva las subcarpetas:

```
C:\Server\rts-project\addon\art\*.tga
        -> D:\GAMES\WOW WOTLK\Interface\AddOns\RTSCommand\art\
```

Y se piden así, con `\\` dobles porque es Lua y **sin extensión**:

```lua
"Interface\\AddOns\\RTSCommand\\art\\mini-frame"
```

**Una ruta que no existe no da error: dibuja nada.** Es la lección de `/rts art`
y aquí muerde igual — un fichero mal nombrado se lee como un fallo de anclaje. Si
una pieza no sale, comprueba el nombre antes de mover un ancla.

---

## 6. Lo que hay que cambiar en el código cuando existan los ficheros

Que no sea una sorpresa: **el arte propio no entra por donde entra el actual.**

1. **`SetBackdrop` no sirve para esto.** `Skin.lua` viste los paneles con
   `bgFile` + `edgeFile`, y el `edgeFile` de WoW es una hoja con los ocho trozos
   del borde en una disposición interna concreta que **no está documentada en
   este proyecto y no la vamos a adivinar** — es exactamente el error que costó
   una compilación en la Etapa 5e. Con piezas propias se colocan texturas
   explícitas y se ancla cada una a mano: control total, cero coordenadas
   adivinadas, y no hace falta `TexCoord` porque cada fichero es una pieza. Es un
   camino nuevo en `Skin.lua`, ~40 líneas, y lo añado cuando existan los
   ficheros. (Si prefieres usar `SetBackdrop`, entonces lo primero es
   **verificar el formato de la hoja contra una textura del cliente**, no dibujar
   contra lo que diga internet.)
2. **El nivel de dibujo del minimapa se invierte.** Hoy `GrabMinimap()` pone
   `Minimap` tres niveles por encima de su panel, justo para que el borde del
   backdrop no tape el mapa. Con un marco propio dibujado *encima* del mapa hace
   falta lo contrario: un frame de overlay por encima del `Minimap`. Una línea.
3. **La altura se fija.** `/rts ui height 256`, y `autoFit` se queda en `false`
   (ver 1.1).
4. **`/rts ui centre <px>`** no existe todavía: hoy el panel central es `strip`
   estirado de borde a borde. Pasar a tres islas es reanclar en `Layout()`.

Nada de esto bloquea dibujar. Los cuatro son cambios de código sobre medidas que
este documento ya fija.

---

## 7. Lo que este documento NO decide

- **El estilo.** Piedra y oro tipo WC3, metal tipo SC2, o algo tuyo. Las medidas
  valen para los tres.
- **Los iconos de las acciones.** El cliente tiene cientos en
  `Interface\Icons\`, gratis y del tamaño correcto. Ver `/rts art`.
- **Los retratos de enemigos** (estudio 5.2). No están en la banda; cuando toque,
  salen del mismo corte — `ring-128` ya sirve. (Los **iconos de juego** del 5.5 sí
  tienen sitio ya: el raíl de la derecha.)
- **Qué botón va en cada hueco del raíl.** Hay cinco por lado y las candidatas
  son más de cinco; se decide usándolo.
- **Si al final es banda continua o tres islas.** Se decide viéndolo, y no cambia
  ni un fichero (apartado 2).

---

## 8. LO QUE SE CONSTRUYÓ DE VERDAD — 2026-08-19

Los apartados 1 a 7 son la propuesta. Esto es el arte que existe, **medido de los
ficheros**, y manda sobre la propuesta donde discrepen. Se deja lo anterior tal
cual porque el razonamiento sigue valiendo; lo que cambia son tres decisiones que
tomó el dibujo.

> **Los apartados 8.1 a 8.3 los sustituye el 9.** Se dejan porque el
> razonamiento sigue valiendo, y porque dos de sus conclusiones -- que la pieza
> central no empalmaba consigo misma y que el paso del rail era fraccionario --
> son justo lo que arreglo la segunda exportacion. Conviene ver contra que.

### 8.1 Las siete piezas

Exportadas de la herramienta de diseño como `Frame N.png` y convertidas con
`rts-tools\Convertir_Arte.py`, que es también el único sitio donde vive esta
correspondencia:

| origen | fichero | tamaño | x en la barra | qué es |
|---|---|---|---|---|
| Frame 4 | `bar-rail-left.tga` | 64 x 256 | 0 | raíl izquierdo |
| Frame 3 | `bar-minimap.tga` | 256 x 256 | 64 | panel del minimapa |
| Frame 7 | `bar-wedge-left.tga` | 128 x 256 | 320 | cuña de bajada |
| Frame 9 | `bar-centre.tga` | 512 x 256 | 448 | panel central |
| Frame 8 | `bar-wedge-right.tga` | 64 x 256 | 960 | cuña de subida |
| Frame 6 | `bar-card.tga` | 256 x 256 | 1024 | carta de comandos |
| Frame 5 | `bar-rail-right.tga` | 64 x 256 | 1280 | raíl derecho |

**Los siete a 256 de alto y los siete potencia de dos en los dos lados**, sin
nada que redondear. Cabecera TGA idéntica a `halo-01.tga` (tipo 2, 32 bpp,
descriptor 8, origen abajo-izquierda) y peso exacto en bytes.

### 8.2 Las tres cosas que cambió el arte

1. **La barra es de ancho FIJO: 1344 x 256, centrada abajo.** No es una banda
   continua y no se estira. La razón no es de gusto: `bar-centre` **no empalma
   consigo mismo** — su columna izquierda es borde y la derecha es hueco, 176 de
   256 filas distintas — así que no es un relleno repetible sino una pieza fija.
   Comprobado columna a columna antes de convertir. En 2560 quedan **608 px de
   mundo a cada lado**, que es exactamente lo que recomienda el apartado 6 del
   estudio.
2. **Borde de 16 y hueco de 224, no 32 y 192.** Y en los tres paneles igual, lo
   cual es más sistema del que proponía el apartado 3. La columna del raíl mide
   también 224, así que alinea con el hueco del mapa igual que buscaba el
   apartado 3.1 — sólo que con otra cifra.
3. **Seis botones de raíl, no cinco.** `6 x 32` de botón más `5 x 6.4` de hueco =
   224. **El paso es fraccionario (38.4) y hay que dejarlo así**: redondear el
   hueco a 6 desalinea el último botón 2 px respecto al arte, y ese error no se
   ve en el código, se ve en pantalla.

### 8.3 Los huecos útiles, medidos

Coordenadas en píxeles desde la esquina arriba-izquierda de la barra de 1344.
Sacadas escaneando los PNG por el relleno gris, no mirando el dibujo:

| hueco | x | y | tamaño | para |
|---|---|---|---|---|
| minimapa | 80 | 16 | 224 x 224 | el `Minimap` reparentado |
| centro | 464 | 64 | 496 x 176 | retratos del grupo y selección |
| carta | 1040 | 16 | 224 x 224 | rejilla 4x4 |
| raíl izq. | 24 | 16 | 32 x 224 | 6 botones, paso 38.4 |
| raíl der. | 1288 | 16 | 32 x 224 | 6 botones, paso 38.4 |

**El centro arranca en y=64, no en y=0**, y eso es el escalón de la silueta: el
panel central se dibuja 64 px más bajo que los extremos, y esos 64 px son
transparentes para que se vea el mundo. Es lo que le da el perfil de WC3.

**Un aviso sobre la carta:** el hueco de 224 entre 4 columnas da celdas de **56**,
que no es potencia de dos. Para el marco no importa (es arte plano), pero un icono
de 64x64 dibujado a 56 sí se interpola. Con iconos apenas se nota; si llega a
molestar, la salida es un hueco de 256 (panel de 288) y no tocar el icono.

### 8.4 Lo que hace el código hoy

**Entrar en modo RTS carga el arte directamente.** `RTSMode.lua` llama a
`ns.Bar:Enter()` justo después de `ns.HUD:Enter()` y antes de `ns.Chrome:Enter()`.
La huella de medir ya no se ve nunca: era el sustituto mientras no había arte.

Eso obligó a un cambio que no era obvio: **el `Minimap` vivía DENTRO de la
huella**, así que esconderla lo escondía con ella. Ahora `HUD.lua` expone
`HostMinimap(frame, inner)` y `Bar.lua` le pasa su propio hueco de 224x224.
El camino de vuelta no se ha tocado — `ReleaseMinimap` sigue devolviéndolo al
padre de Blizzard que guardó `miniWas` — así que **alojarlo en otro sitio no añade
una ruta nueva de restauración**, que es el fallo grave que persigue la prueba A2.

Y el hueco del mapa se dibuja **por encima** del panel, porque `bar-minimap` es
opaco: alfa 255 en los 65 536 píxeles, medido. Si fuera transparente valdría al
revés, pero no lo es.

`addon\Bar.lua`, `/rts bar`:

- dibuja las siete piezas a tamaño nativo, en un frame de 1344x256 con la escala
  de píxel que le pide a `HUD:ScaleFrame`, centrado abajo (`/rts bar pad <px>`)
- `/rts bar guides` superpone los límites de cada pieza, los huecos útiles, los
  huecos del raíl y un cuadrado de referencia de 64 px, para juzgar el 1:1 mirando
- `/rts bar status` dice **si cargaron los siete ficheros**. Hace falta porque una
  ruta que no existe no da error, dibuja nada — y de paso contesta la prueba C1 de
  `PRUEBAS-9`: si `GetTexture()` devuelve nil, sirve de oráculo
- **no toca el ratón** (`EnableMouse(false)` en todo), para no romper la caja de
  selección por esa zona — prueba B6
- aparta la huella de `HUD.lua` mientras está puesto, pero **deja la línea de
  mensajes**: con el chat escondido por `Chrome.lua` es el único canal de
  diagnóstico que hay

**Lo que NO hace todavía:** no hay botones. Los raíles, la carta 4x4 y el hueco
central son dibujo; las coordenadas de sus celdas están en `SLOTS` y en `RAIL`
listas para colgarles algo, pero nada responde al ratón. El siguiente paso
natural es el raíl derecho o la carta, que son comandos de chat y por tanto
botones normales sin restricción de combate (estudio 5.4).

---

## 9. LA SEGUNDA EXPORTACIÓN — 2026-08-19

Siete piezas nuevas, exportadas ya con nombre propio (`left-map.png`,
`middle-grow.png`, …) en vez de `Frame N.png`. Convertidas con
`rts-tools\Convertir_Arte.py`, que ahora **copia también el PNG a
`rts-project\art-src`**: la carpeta de descargas se vacía y no está en git, así
que si el único original vive ahí, dentro de un mes el TGA es lo único que queda
y ya no se puede ni reexportar ni comparar.

> **Las medidas de la §9 son las del arte 1x, y el §10 las dobla todas.** La
> forma no cambia: siguen siendo las mismas siete piezas, los mismos huecos y
> las mismas proporciones, multiplicado todo por dos. Lo que el §10 sí sustituye
> del todo es el 9.5, la regla de tamaño.

### 9.1 Las piezas

| fichero | tamaño | x (con `grow`=1) | qué es |
|---|---|---|---|
| `left-bar.tga` | 64 x 256 | 0 | raíl izquierdo |
| — hueco de 8 — | | 64 | |
| `left-map.tga` | 256 x 256 | 72 | panel del minimapa |
| `left-hero-portrait.tga` | 256 x 256 | 328 | retrato del héroe y sus datos |
| `middle-grow.tga` | 256 x 256 | 584 | **panel central, repetible** |
| `right-embellishment.tga` | 64 x 256 | 840 | cuña de cierre |
| `right-bot-actions.tga` | 256 x 256 | 904 | carta de comandos |
| — hueco de 8 — | | 1160 | |
| `right-bar.tga` | 64 x 256 | 1168 | raíl derecho |

Ancho total **1232** con una copia del central, **+256 por copia**. Alto 256.
Los siete potencia de dos en los dos lados, cabecera TGA idéntica a la que ya
funcionaba (tipo 2, 32 bpp, descriptor 0x08, filas de abajo a arriba, BGRA) y
**comprobada leyendo el TGA de vuelta y comparándolo píxel a píxel con el PNG**
antes de instalarlo. Un TGA que el cliente no entiende no da error: no dibuja
nada, igual que una ruta de textura inexistente.

### 9.2 Las tres cosas que cambió esta exportación

1. **Los raíles van SUELTOS, 8 px separados; el resto se toca.** Es la única
   separación que hay en toda la barra, y está escrita como un `gap` en la tabla
   de piezas en vez de sumada a mano en las coordenadas.
2. **`middle-grow` SÍ empalma consigo mismo, y por eso la barra ya no es de
   ancho fijo.** Es lo contrario de lo que decía el 8.2: aquel `bar-centre`
   tenía borde a la izquierda y hueco a la derecha, así que dos copias dejaban
   costura. Éste llega de borde a borde — el gris ocupa los 256 de ancho y las
   bandas turquesa de arriba y abajo cruzan enteras — así que la barra crece por
   ahí, y sólo por ahí: `/rts bar grow <n>`, de 1 a 8.
3. **El paso del raíl ya es entero: 36.** Botones de 32 en y=22, 58, 94, 130,
   166 y 202. Desaparece el 38.4 fraccionario del 8.2 y con él la nota de no
   redondearlo.

### 9.3 Los huecos útiles, medidos

Escaneando el relleno gris de los PNG, pieza por pieza. Relativos **a su pieza**,
que es como están en `SLOTS`; su x en la barra sale de dónde acabó la anterior,
nunca escrita.

| hueco | pieza | dx, dy | celda | rejilla | para |
|---|---|---|---|---|---|
| `minimap` | `left-map` | 16, 16 | 224 x 224 | — | el `Minimap` reparentado |
| `portrait` | `left-hero-portrait` | 16, 64 | 128 x 128 | — | retrato del héroe |
| `info` | `left-hero-portrait` | 160, 64 | 96 x 176 | — | datos, a su derecha |
| `vitals` | `left-hero-portrait` | 16, 200 | 128 x 8 | 3, paso 16 | vida / maná / … |
| `party` | `middle-grow` | 0, 64 | 304 x 176 | crece +256 | retratos del grupo |
| `card` | `right-bot-actions` | 16, 16 | 56 x 56 | 4x4, paso 56 | carta de comandos |
| `rail-left` | `left-bar` | 16, 22 | 32 x 32 | 6, paso 36 | botones sueltos |
| `rail-right` | `right-bar` | 16, 22 | 32 x 32 | 6, paso 36 | botones sueltos |

**`party` es el único hueco que abarca varias piezas**: empieza en la primera
copia del central y llega 48 px dentro de la cuña, así que mide 304 con una
copia y 560 con dos. En la tabla se declara con `toPiece`/`toDx` en vez de con
un ancho, y eso es lo que hace que `grow` no obligue a tocar ningún otro número.

**La carta es 4x4 de celdas de 56**, pegadas sin hueco (16 + 4x56 = 240, más 16
de borde = 256). El damero del dibujo no es decoración: es lo que hace visible la
rejilla antes de que haya botones. Sigue en pie el aviso del 8.3 — 56 no es
potencia de dos, así que un icono de 64 se interpola.

**El escalón de la silueta ahora es de 48, no de 64.** `middle-grow` es
transparente hasta y=48, y `left-hero-portrait` y `right-embellishment` suben con
una diagonal desde ahí hasta y=0; el mapa y la carta ocupan los 256 enteros. Es
lo que da el perfil de WC3, y como las siete piezas miden 256 de alto y se
dibujan todas pegadas arriba, sale solo.

### 9.4 El conversor

`rts-tools\Convertir_Arte.py`, con botón `Convertir_Arte.bat`. Lee los PNG de
`Descargas\ui` — u otra carpeta pasada como argumento —, los guarda en `art-src`
y escribe el TGA en `addon\art`. Rechaza lo que no sea potencia de dos hasta 512.
El nombre del TGA es el del PNG, así que **la correspondencia entre origen y
fichero dejó de existir como tabla que mantener**, que es lo que estaba mal en el
8.1.

### 9.5 El alto lo pone `share`, el ancho lo acota `side`

La barra está **centrada abajo y es de proporción fija**, así que sólo hay un
grado de libertad: la escala. `share` la fija — 20% del alto de pantalla, que es
lo que ya estaba decidido — y de ahí sale el ancho solo.

**`side` es el margen de cada lado y es un número distinto de `pad`.** Antes
`pad` hacía los dos papeles con 22 px: como separación al suelo está bien, como
margen lateral no es nada, y dejaba que la barra llegase a rozar los bordes en
cuanto crecía. Ahora `pad` es sólo el suelo, en píxeles, y `side` sólo los
lados, en **fracción del ancho de pantalla** — por lo mismo que `share`: "el 8%"
quiere decir lo mismo en cualquier resolución y "205 px" sólo en ésta.

**Lo que hace de verdad es acotar, no mover.** Mientras el hueco real sea mayor
que el pedido no cambia nada. En 2560 x 1440, con el 20% de alto y una copia del
panel central, el arte mide 1340 px y quedan **610 px de mundo a cada lado, el
24%** — muy por encima del 8% pedido. El tope empieza a morder a partir de
`grow = 4`, y es lo único que impide que crecer acabe pegando el arte al borde:

| `grow` | arte | escala | hueco por lado |
|---|---|---|---|
| 1 | 1232 | 1.088 | 610 px |
| 2 | 1488 | 1.088 | 471 px |
| 3 | 1744 | 1.088 | 332 px |
| 4 | 2000 | 1.075 ← recortado | 205 px |
| 5 | 2256 | 0.953 ← recortado | 205 px |

`/rts bar status` imprime el hueco real y el pedido uno al lado del otro, y dice
cuál de los dos manda. Hace falta porque un tope que no está mordiendo es
invisible, y sin ese renglón subirlo parece no hacer nada.

### 9.6 Lo guardado se acota AL LEERLO

Las SavedVariables de este cliente traían un **`grow = 688`** escrito por una
versión anterior. Un fichero de SavedVariables no olvida: guarda cualquier clave
que se haya escrito alguna vez y sobrevive a la versión del addon que la
escribió, así que acotar sólo dentro de los `Set*` no sirve — ésos únicamente
corren cuando el jugador teclea el comando, y el valor malo entra por el otro
lado.

Y **no todo se acota igual**. Pasarse de la raya en `share` o `side` es una
intención exagerada que se puede recortar: pediste el 70% del alto, te doy el
60%. Un `grow` de 688 no es una intención, es basura — recortarlo al máximo
daría ocho paneles diminutos, que se ve mal *y además parece deliberado*. Por
eso `grow` lleva `strict` y vuelve al valor de fábrica en vez de al tope.

Lo descartado **se imprime**. Un ajuste guardado que se ignora en silencio es el
mismo fallo que una textura que no carga sin decirlo.

También quedaba un `scale = 1.872` de haber usado `/rts bar wide` sobre el arte
viejo de 1344 — inerte, porque `auto = true` hace que mande `share`, pero es
justo el tipo de resto que conviene ver escrito antes de que confunda a alguien.

---

## 10. EL ARTE 2x Y LA REGLA DE ANCHO — 2026-08-19

Sustituye al 9.5, que duró unas horas. Dos cambios, y el primero es la causa del
segundo.

### 10.1 El arte se dobló porque las texturas del juego son grandes

Las piezas de la §9 medían 256 de alto. Al empezar a vestirlas con **texturas
del propio cliente** — que es el plan desde el principio, miles de piezas a coste
cero — se vio que el arte del cliente es bastante mayor que eso: un borde o una
ranura de WoW metida en un panel de 256 sale desproporcionada. **Doblando el
arte, las piezas del cliente encajan.**

Así que la exportación nueva es **exactamente 2x** — comprobado zona por zona
contra las medidas de la §9, no supuesto: las siete piezas y los ocho huecos
salen todos multiplicados por dos, sin un píxel de deriva. Sigue todo dentro de
potencia de dos hasta 512, que es el techo del cliente:

| pieza | antes | ahora |
|---|---|---|
| raíles | 64 x 256 | **128 x 512** |
| paneles | 256 x 256 | **512 x 512** |
| cuña | 64 x 256 | **128 x 512** |
| hueco de los raíles | 8 | **16** |
| barra entera | 1232 x 256 | **2464 x 512** |

**Y se dibuja REDUCIDO, a x0.83 en 2560.** Es la dirección buena: reducir sale
nítido y ampliar es lo que emborrona. La barra ya no amplía nunca, cosa que
antes sí hacía — el 20% de alto pedía x1.09 sobre el arte de 256.

Los números del código son los del **dibujo**, no los de pantalla. La escala los
baja al final, en un solo sitio.

> **El 10.2 lo sustituye el §11.** Duró menos que el 9.5. Se deja porque el
> resultado que produjo — barra al 30% del alto, y crecer encogiéndola — es la
> mejor explicación de por qué el reparto del §11 es el bueno.

### 10.2 El ancho manda y el alto sale solo

`share` — "la barra ocupa el 20% del alto" — **se retira**. La regla nueva es
**`side`: el margen de cada lado en fracción del ancho de pantalla**, 10% por
defecto, o sea el 80% central para el arte.

No es un knob más sino el mismo en el otro eje, y por eso el anterior se va: la
barra está centrada y es de proporción fija, así que **fijar un lado ya fija el
otro**. Tener dos mandos para un solo grado de libertad sólo sirve para que uno
de los dos mienta — que es exactamente lo que pasaba: `share` pedía el alto y
`side` acotaba el ancho, y cuál de los dos ganaba dependía de la resolución y de
`grow`.

**Lo que cuesta, dicho antes de que sorprenda.** En 2560 x 1440 el 80% del ancho
son 2048 px, y con la proporción del dibujo eso da **426 px de alto: el 29,6% de
la pantalla**, contra el ~20% de antes. Es más consola de la que recomienda el
apartado 6 del estudio, y es la consecuencia directa de pedir el 80%. El mando
para bajarlo es subir el margen:

| `side` | ancho del arte | barra | alto |
|---|---|---|---|
| 10% | 80% | 2048 x 426 | 29,6% |
| 13% | 74% | 1894 x 394 | 27,3% |
| **16%** | **68%** | **1741 x 362** | **25,1%** — el de WC3 |

**`grow` cambió de significado, y conviene saberlo.** Con el ancho clavado,
repetir el panel central ya no ensancha la barra: mete más arte en el mismo
hueco, así que **la encoge**. Con `side` al 10%: `grow`=1 → 426 px de alto,
`grow`=2 → 352, `grow`=3 → 301. Es coherente — más paneles, cada uno más
pequeño, como una consola de RTS con más unidades — pero es lo contrario de lo
que hacía ayer.

`/rts bar status` imprime las dos cifras, la que se pide y la que sale, con el
alto marcado como consecuencia. El renglón existe porque **el número que no se
pide es justo el que sorprende**.

### 10.3 Los comandos

| comando | qué hace |
|---|---|
| `/rts bar side <%>` | margen a cada lado. **El knob de tamaño.** 10, 13, 16 |
| `/rts bar grow <n>` | copias del panel central, 1–8. Ahora encoge la barra |
| `/rts bar scale <n>` | escala a mano; apaga el llenado |
| `/rts bar wide` | vuelve a llenar el ancho |
| `/rts bar pad <px>` | separación al **suelo**, y sólo eso |
| `/rts bar guides` | los límites de cada pieza y cada celda encima del arte |
| `/rts bar status` | medidas, y si las siete piezas cargaron |

`/rts bar share` sigue contestando, pero para decir que el alto ya no se pide y
dónde está ahora el mando. Es el comando que uno teclea por costumbre, y un "no
reconocido" no lleva a ninguna parte.

---

## 11. EL REPARTO BUENO: EL ALTO ES LA ESCALA, EL ANCHO SON LOS PANELES

Sustituye al 10.2. El arte 2x del 10.1 se queda tal cual.

### 11.1 Dos mandos, dos cosas

```
1. share = 0.20 del alto de pantalla   ->  sale la ESCALA
2. con esa escala, cuántas copias del panel central hacen falta
   para dejar side = 0.10 de margen a cada lado   ->  sale GROW
```

En el §10 puse que `share` y `side` no podían convivir, porque la barra es de
proporción fija y fijar un lado ya fija el otro. **Eso era cierto sólo mientras
`grow` estuviera a mano.** Repetir el panel central cambia la proporción del
dibujo, así que es un grado de libertad de verdad — y con dos grados de libertad
caben dos mandos sin que ninguno mienta. El error del §10 no fue tener dos
knobs: fue pedirle a la escala que hiciera el trabajo del ancho, con `grow`
mirando.

Se ve en el resultado. Con la regla del §10 la barra salía a **426 px de alto,
el 30% de la pantalla**, y crecer la encogía. Con ésta sale a **288 px, el 20%
clavado**, y crecer la ensancha, que es lo que la palabra significa.

**No hay pez que se muerda la cola** porque la escala sale del **alto**, que no
depende del ancho del arte. El orden es: escala → cuántos paneles → `BAR_W`.
Al revés no se podría resolver.

### 11.2 `grow` es discreto, así que el margen nunca es el pedido

Cada copia son 512 px de dibujo, o sea ~280 px de pantalla. El margen salta de
uno en uno y casi nunca cae en el 10% clavado. Se elige **la cuenta que más se
acerca**, con un suelo (`minSide`, 4,5%) por debajo del cual no se acepta ninguna.

En 2560 x 1440 a pantalla completa, con el alto al 20% (escala x0.5625):

| paneles | arte | barra | margen |
|---|---|---|---|
| 1 | 2464 | 1386 px | 22,9% |
| 2 | 2976 | 1674 px | 17,3% |
| **3** | **3488** | **1962 px** | **11,7%** ← elegido |
| 4 | 4000 | 2250 px | 6,1% |
| 5 | 4512 | 2538 px | 0,4% — no cabe |

En ventana maximizada el alto útil es ~1392, la escala baja a x0.5438 y entonces
**gana 4 paneles con un 7,5% de margen**. Las dos respuestas son correctas: son
los dos escalones que rodean al 10% pedido, y cuál gana depende de la altura real
de la ventana. Por eso el margen se imprime siempre.

**Los empates se rompen hacia abajo.** Entre dos cuentas igual de cerca gana la
de menos paneles: deja más mundo visible, y pasarse de ancho es el único de los
dos errores que se ve como arte cortado.

**La elección se hace por el MARGEN que sale, no por el ancho que falta.** No es
lo mismo: el suelo `minSide` es una condición sobre el margen, así que medir en
esa unidad deja el descarte en una línea en vez de en una conversión.

### 11.3 Los comandos

| comando | qué hace |
|---|---|
| `/rts bar share <%>` | **el alto**, en % de pantalla. Es la escala. 20, 22, 25 |
| `/rts bar side <%>` | **el margen** que se quiere. Decide los paneles; no recorta |
| `/rts bar grow <n>` | fija los paneles a mano. `auto` devuelve la elección |
| `/rts bar scale <n>` | escala a mano; apaga el derivado del alto |
| `/rts bar wide` | el margen mínimo, o sea todo lo ancho que quepa |
| `/rts bar pad <px>` | separación al **suelo**, y sólo eso |
| `/rts bar status` | medidas, vecinos de `grow`, y si las siete piezas cargaron |

Cada cambio de medida imprime el mismo renglón: paneles, tamaño en píxeles, alto
**pedido y obtenido**, margen **pedido y obtenido**, y la escala. Con `grow`
discreto, suponer cualquiera de esas cifras es la única forma de llevarse una
sorpresa.

`/rts bar status` añade **qué pasaría con un panel más y con uno menos**. Es la
pregunta que se hace uno nada más ver el margen que salió, y contestarla ahí
evita probar a ciegas.

---

## 12. EL RETRATO 3D DEL HÉROE — 2026-08-19

`Portrait.lua`, en el hueco `portrait` de `left-hero-portrait` (256x256 de arte,
144 px en pantalla con la escala de hoy). **Construido, no visto todavía en
juego.**

### 12.1 Es un modelo, no una imagen

`CreateFrame("PlayerModel", …)` + `SetUnit("player")`: el mismo widget con el
que el cliente dibuja tu personaje en la ficha. Vive — animaciones de reposo,
equipo puesto, montura. La alternativa de una línea era `SetPortraitTexture`,
que es un recorte 2D fijo de la cara, y no es lo que pide una consola de RTS.

### 12.2 Los huecos de la barra ahora pueden alojar

`SLOTS` gana `host = true`. Un hueco con esa marca tiene, además del rectángulo
medido, un `Frame` de verdad donde otro módulo mete lo suyo. El minimapa ya
funcionaba así con un frame escrito a mano; ahora son dos y sale de la tabla.
`B:SlotFrame(key)` lo devuelve.

Se mueven y se reescalan con la barra, y van **por encima** del arte, porque las
piezas son opacas donde está el hueco — el mismo tropiezo que costó el minimapa
la primera vez.

### 12.3 Lo que este fichero no da por supuesto

El widget `Model` de 3.3.5a **no tiene la misma lista de métodos** que el de las
versiones modernas, y casi toda la documentación que se encuentra es de las
nuevas. Así que nada se llama a pelo: todo pasa por un `Try` que comprueba que
el método exista y se traga el fallo, y **`/rts portrait status` imprime cuáles
existen de verdad en este cliente** y cuáles contestaron.

Es la lección de `nameplateMaxDistance` y de `gxWindowedResolution` — comprobar
contra el cliente, no contra internet — sólo que aquí la comprobación se puede
dejar puesta en vez de hacerla una vez y escribirla en un documento.

La apuesta era **`SetCamera(1)`**, la cámara de retrato que traen los modelos de
personaje. **No hace nada en este cliente** — visto en juego: sale el cuerpo
entero, igual que con la 0. Así que el encuadre se hace a mano y `cam` se queda
en 0.

### 12.3.1 Los dos signos que nadie sabe

`SetPosition(a, b, c)` mueve el modelo delante de la cámara, pero en 3.3.5a no
está documentado **si el primer eje acerca o aleja, ni si el tercero sube o
baja**. Y `SetModelScale` escala desde los **pies**, así que ampliar manda la
cabeza fuera del cuadro y hay que compensar — otra vez sin saber en qué
dirección. Son dos incógnitas de signo y una de método: ocho combinaciones.

Se puede razonar mal durante media hora o se puede mirar. Hay una tabla de
**siete encuadres** — las cuatro combinaciones de signo, dos que usan escala en
vez de acercar, y una mixta — y **`/rts portrait try`** pasa al siguiente y lo
deja aplicado y guardado. La correcta se reconoce en cuanto sale.

Es la misma decisión que el círculo de selección de la etapa 5e: una lectura
estática convincente valía **una** prueba barata en juego, no dos compilaciones
de maquinaria encima.

**Y la escala va antes que la posición**, siempre. Como `SetModelScale` mueve la
cabeza, posicionar primero hace que escalar deshaga el centrado — y entonces el
resultado depende del orden en que toques los mandos, que es justo lo que hace
imposible encuadrar nada a ojo.

### 12.4 Dos cosas que lo romperían si no estuvieran

- **`SetUnit` rehace el modelo y borra cámara, posición y giro.** Todo lo demás
  va DESPUÉS de él, siempre. Ponerlo antes es el fallo típico: se ajusta el
  encuadre, algo refresca el modelo y el encuadre desaparece sin que nada haya
  dado error.
- **El cliente vacía el modelo, y el evento llega antes que el modelo.** Una
  pantalla de carga lo deja en blanco; se rearma con `PLAYER_ENTERING_WORLD` y
  `UNIT_MODEL_CHANGED`, pero justo al terminar de cargar el modelo todavía no se
  puede pedir. Van además **dos reintentos con retraso** (0,5 s y 2 s). No
  cuestan nada y son la diferencia entre un retrato y un cuadro gris.

Y `EnableMouse(false)`, como todo lo de la barra: un `Model` captura clicks si se
le deja, y está justo encima de la zona donde la caja de selección no puede
fallar (prueba B6).

### 12.5 Los comandos

`/rts portrait` solo enseña el estado. `cam <0|1>`, `zoom <n>`, `x <n>`, `y <n>`,
`facing <grados>`, `scale <n>`, `light on|off`, `refresh`, `default`. Todos en
vivo y guardados — el encuadre de un modelo 3D se busca mirándolo, no
calculándolo.

---

## 13. LA TERCERA EXPORTACIÓN — 2026-08-20

Cuatro piezas en vez de siete (dos se usan dos veces, una espejada) y la sala
llena: retrato 3D, barras del héroe, barras del grupo, fila de enemigos, carta de
acciones, nueve órdenes globales y los dos raíles de botones.

Está escrito aparte, en **`UI-RTS-SALA.md`**, porque no es una corrección de este
documento: es la continuación. Aquí se decidió la ALTURA de la barra y cómo se
parte el arte; allí, qué hay dentro y de dónde sale cada número.

Lo que este documento se lleva por delante:

- **La tabla de piezas del apartado 9 ya no vale.** `bar-centre`,
  `left-hero-portrait`, `left-map`, `right-bot-actions` y `right-embellishment`
  no existen; sus TGA están borrados del repo. Lo que hay es `left-bar`,
  `minimap`, `middle` y `ramp`.
- **La rejilla 4x3 de la carta tampoco.** Ahora son dos filas de tantas columnas
  como quepan (13x2 en esta pantalla), y las órdenes globales van en una rejilla
  3x3 propia en el panel cuadrado de la derecha.
- **El ancho sigue siendo `1568 + 512N`** con la misma mecánica del apartado 11
  (el alto es la escala, el ancho son los paneles). Solo han cambiado los
  sumandos.
