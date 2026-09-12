# `sim/` — las pruebas que no necesitan el juego

Guiones de Python que reproducen fuera del cliente la parte del addon que es
**aritmética pura**, y le pasan los casos que en juego cuestan una ronda de
pruebas cada uno.

```
python sim\bar_layout.py      el reparto de la barra: areas, celdas, desbordes
python sim\route_advance.py   el avance de las rutas: indices, llegadas, plazos
python sim\ground_filter.py   la altura de la camara libre: escalones y cuestas
python sim\camara_buceo.py    la camara y las capas: cuevas, pisos, el vacio
```

(La lista completa es el contenido de la carpeta; arriba están los tres que más
se usan.)

## Por qué existen

Porque ya han pagado tres veces:

- `bar_layout.py` cazó, **antes de compilar nada**, que el borde de abajo de la
  sala llevaba un píxel de menos y que el hueco del minimapa no es cuadrado
  (etapa 5k). En la 5l cazó que, al estrechar las filas del grupo, el bloque de
  la derecha pasaba de ancho negativo a 48 px — positivo pero menos que una
  celda — y la condición `w <= 0` que lo descartaba dejaba de valer.
- `camara_buceo.py` se escribió al cerrar el plop de las cuevas (12/09/2026) y
  su primera corrida encontró que **tres de sus siete pruebas no tenían
  dientes**: pasaban igual con el código roto. La causa era el modelo del mundo,
  no las pruebas — una sola capa de suelo no sabe decir «roca», y sin roca
  continua la escalera del rayo que arrancaba en `z+5` no se puede construir.
  Con dos rayos (terreno que miente, sólido que no) y un medio continuo, los
  cuatro interruptores tumban cada uno lo suyo: `--sin-criba` deja a la cámara
  sin suelo dentro de la cueva, `--rayo-arriba` le esconde el suelo de abajo al
  soltar la tecla, `--offset-teclas` no deja atravesar nada, y
  `--rayo-arriba --techo-es-suelo` la expulsa **57 yardas** de donde la habías
  puesto.
- `route_advance.py` reproduce el fallo de la etapa 5m: un bot que llega al
  último punto **mientras otro sigue andando**, y entonces se añade un punto con
  shift. Su índice apuntaba al punto nuevo pero nadie se lo había mandado, así
  que medía la llegada contra el punto anterior —donde estaba parado—, se daba
  por llegado y **se saltaba el punto nuevo entero**.

- `ground_filter.py` tumbó **en la primera corrida** el filtro de altura que se
  acababa de escribir: la velocidad de seguimiento dependía de *lo que quedaba*
  del escalón, así que cada subida se aceleraba al final y las últimas dos
  yardas de un escalón de quince se hacían a 25 yd/s — el mismo tirón que venía
  a quitar, movido al final del recorrido. Y luego pidió el tope de retraso, al
  no haber forma de pasar el perfil «una repisa y detrás una cuesta larga».

## Cómo se usan

Se ejecutan **antes** de compilar o de desplegar, no después de que algo falle.
Cuestan un segundo.

Llevan un interruptor para volver al comportamiento anterior y comprobar que la
prueba tiene dientes — `SENT_GUARD = False` en `route_advance.py`, y
`--sin-filtro` / `--sin-pendiente` / `--sin-tope` en `ground_filter.py`. Una prueba que pasa con el código roto no es una prueba, y
la única forma de saberlo es romperlo a propósito una vez.

## Lo que NO cubren

Nada que necesite el cliente: texturas, frames, widgets, funciones protegidas.
Eso es lo que va en `docs/PRUEBAS-N.txt`. La división es deliberada — si algo se
puede comprobar aquí, no debería gastar una ronda de pruebas en juego.

**Y son copias, no el código de verdad.** Reimplementan las reglas del Lua en
Python, así que pueden desincronizarse de él. Cuando se cambien las medidas de
la barra o las reglas de avance, hay que tocar los dos sitios; a cambio, la
comprobación cuesta un segundo en vez de arrancar el servidor, el cliente y una
partida.
