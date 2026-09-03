# Dibujar en el suelo: qué hay, qué falta y qué se puede cambiar

Escrito 2026-09-03, a petición de *"mírame si tenemos algún nuevo y mejor método
para pintar cosas nuestras en el suelo — para cambiar los anillos de selección a
otro estilo, o incluso poder dibujar los waypoints en el mundo y no en la
capa"*.

Todo lo de aquí está comprobado abriendo el código, no recordado.

---

## 0. Las dos respuestas cortas

**Los waypoints YA se dibujan en el mundo.** No en la capa de interfaz. Lo hacen
desde la etapa 5m y el mecanismo es `DynamicObject` — el mismo con el que el
cliente dibuja una Consagración en el suelo. Lo que sigue en la capa es
**únicamente la línea de puntos que los une** (`Route.lua`), y eso sí se puede
mudar, con una pega concreta que está en el §3.

**Para el anillo de selección sí hay tres caminos nuevos**, y uno de ellos es
claramente mejor que el actual: **una criatura invisible con el modelo cambiado,
siguiendo a la unidad**. Es la misma jugada que ya hace la cámara RTS, no toca
la base de datos del mundo, y da color, tamaño y estilo arbitrarios. Cuesta
recompilar mod-rts, nada del cliente.

---

## 1. Los cuatro mecanismos que existen hoy, y la verdad de cada uno

| # | Mecanismo | Dónde vive | Profundidad correcta | Sigue a la unidad | Color libre |
|---|---|---|---|---|---|
| 1 | Círculo nativo de selección | `rts_core/Circle.cpp` | **sí** | sí | **no** (§1.1) |
| 2 | Tinte del modelo | `rts_core`, canal CVar | sí (es el modelo) | sí | **sí** |
| 3 | `DynamicObject` | `mod-rts/RtsMarks.cpp` | **sí** | **no** | no |
| 4 | Textura de interfaz proyectada | `Markers.lua`, `Route.lua` | **NO** | no | sí |

### 1.1 Por qué el círculo nativo no cambia de color

Está **pausado, no descartado**, y con dos intentos fallidos detrás
(etapa 5e). `0x00ACC3F8` contiene `0xFF7F7F7F`, el dibujo recibe su dirección, y
el código de apuntado lee ese mismo dword al lado de las tablas de color de
reacción — todo apunta a que es el tinte. **No lo es.** Escribirlo antes de cada
dibujo dio círculos grises; repuntar el `push imm32` del dibujo a un dword
por unidad, que es inmune a *cuándo* se lee el puntero, también dio círculos
grises. El segundo intento elimina la variable del tiempo, así que la dirección
simplemente no es el tinte.

La siguiente pista escrita es sondear los siete argumentos en el sitio de
llamada `0x007E4370` y entrar en `0x007E3E80`. Es trabajo de ingeniería inversa
sobre este binario concreto.

### 1.2 Por qué la capa de interfaz pierde siempre

Dos razones independientes, las dos verificadas en juego:

- **No tiene profundidad.** Se dibuja encima de la colina que debería taparla.
- **Nada al girar.** La cámara que publica el DLL nunca es la del frame que el
  cliente está dibujando, así que hay un frame de desfase permanente.

La etapa 5e lo dejó escrito como regla: *deja de proyectar y deja que el cliente
lo coloque*. Un punto suelto en el suelo se salva porque **no se compara con
nada**; un anillo bajo los pies de un modelo no, porque el ojo lo compara con el
modelo en cada frame.

---

## 2. Waypoints: ya están en el mundo

`Route.lua:852` hace `ns.Marks:Sync(Pending())`, y `Marks` pide a mod-rts un
`DynamicObject` por punto (`RtsMarks.cpp:351`, `CreateDynamicObject`). El
cliente dibuja ahí el visual de área persistente del hechizo elegido — hoy
45848 *"Shield of the Blue"*, escogido a ojo entre 572 candidatos con
`/rts mark next|prev|find`.

Eso es dibujo en el mundo de verdad: profundidad correcta, sin proyección, y con
572 estilos ya navegables sin tocar una línea de código.

**Lo que sigue en la capa de interfaz es la línea de puntos entre waypoints y el
disco de destino.** Y ahí la decisión de la etapa 5l sigue siendo defendible: un
punto en el suelo no se compara con nada, así que el defecto se nota poco.

### 2.1 Si quieres la línea también en el mundo

Es el mismo mecanismo, N veces: una cadena de `DynamicObject` pequeños repartidos
a lo largo de cada tramo. Sin invento.

La pega es concreta y hay que decirla antes: **cada `DynamicObject` es un objeto
del mundo con su paquete de creación**. Una ruta de cuatro tramos con un punto
cada dos metros son ~60 objetos apareciendo y desapareciendo cada vez que
cambias la ruta, contra 4 de ahora. No es catastrófico en un servidor de una
persona, pero es la clase de cosa que se nota en un momento malo. Si se hace,
con separación generosa (5-6 metros) y un tope duro por ruta.

**Recomendación: no.** El coste es real y el defecto que arregla es el que menos
se ve. Está aquí escrito para que no haya que redescubrir que se podía.

---

## 3. El anillo de selección: tres caminos nuevos

### 3.1 Criatura invisible con el modelo cambiado — RECOMENDADO

Una criatura por unidad seleccionada, con el modelo puesto a algo plano, pegada
a los pies y siguiéndola.

**Por qué es el mejor:**

- **Sigue perfectamente.** El movimiento de criatura es de primera clase: el
  cliente lo interpola él solo, igual que interpola a un bot andando. No hay
  nada que sincronizar por frame, que es donde han muerto los otros intentos.
- **Profundidad correcta**, porque es un modelo del mundo.
- **Color, tamaño y modelo son nuestros.** `Unit::SetDisplayId(id, escala)`
  (`Unit.h:1975`) y el tinte por unidad que ya existe.
- **No toca la base de datos del mundo.** Se toma prestada la entrada 15214
  *"Invisible Stalker"* y se le sobrescribe el modelo, que es **exactamente lo
  que ya hace la cámara RTS desde la etapa 6**. La regla 4 del plan
  (*"nada de tocar la base de datos del mundo"*) se respeta entera.
- **Se puede recompilar sin tocar el cliente.** Sólo mod-rts.

**Lo que no se sabe todavía, dicho por delante:** qué `DisplayId` dibuja algo
que parezca un anillo plano. El servidor **sí** carga `CreatureDisplayInfo`
(`DBCStores.h:106`), así que se pueden enumerar todos — pero **no carga la ruta
del modelo**: en `CreatureModelDataEntry` (`DBCStructure.h:801`) el campo
`ModelPath` está comentado. O sea que se puede recorrer la lista pero no leer
los nombres.

Eso no bloquea: es el mismo problema que tuvo el marcador de ruta, y se resolvió
igual — un navegador que va pasando candidatos y se juzga con el ojo
(`/rts mark next|prev|find`). Aquí sería `/rts ring next`. **La máquina de
navegar ya está escrita en `RtsMarks.cpp`**; se copia su forma.

**Coste estimado:** medio día. Una criatura por unidad seleccionada (máximo 5),
recolocada en el tick del mundo, y el navegador de modelos.

**El riesgo real, y no es el que parece:** no es el rendimiento, son las
criaturas huérfanas. Un anillo es una criatura de verdad, y una criatura que se
queda cuando el jugador se desconecta mal es basura en el mundo. Se cierra igual
que la cámara: `ForgetPlayer` en `OnPlayerLogout`, que este módulo ya tiene para
cuatro cosas.

### 3.2 `DynamicObject` bajo cada unidad — más barato, con una incógnita

Es el mecanismo de los waypoints, aplicado a los pies de una unidad. Ventaja
enorme: **los 572 estilos ya están navegables hoy**, sin escribir nada.

La incógnita es si **sigue**. `DynamicObject` hereda de `MovableMapObject`
(`DynamicObject.h:34`), así que el servidor puede reubicarlo. Lo que no está
comprobado es si el **cliente** lo redibuja al moverse: un dynobject normal
nunca se mueve, así que es perfectamente posible que el cliente lo coloque una
vez al crearlo y se olvide. Si es así, la única salida sería borrar y recrear
cada tick, que parpadearía.

**Eso se comprueba en cinco minutos y sin escribir código de producción:** poner
un marcador con `/rts mark`, mover la criatura de la cámara por debajo, y ver si
lo sigue. Vale la pena hacerlo ANTES que el §3.1, porque si sale bien, el §3.1
sobra.

Es exactamente la lección de la etapa 5e: **una lectura estática convincente
vale UNA prueba barata en juego, no dos compilaciones de maquinaria encima.**

### 3.3 Un aura con visual de suelo — lo más barato si existe

Algunos hechizos dejan un visual persistente pegado a la unidad, y el cliente lo
dibuja adjunto al modelo: sigue perfecto por construcción y no cuesta ni un
objeto nuevo — es un aura más.

**No sé cuáles.** Y esto es importante: el servidor carga `sSpellVisualStore`
(`DBCStores.h:187`) pero **no** el contenido de `SpellVisualKit`, que es donde
está el punto de anclaje. Así que desde el servidor no se puede filtrar "los que
dibujan en la base del modelo": habría que ir probando.

Ventaja si aparece uno bueno: es la solución más barata de todas, cero objetos.
Desventaja: un aura se ve en la ficha del personaje y puede interactuar con
mecánicas (dispels, contadores de buffs), lo cual es feo en un sitio que no
debería tener efectos de juego.

**Prioridad baja**, pero apuntado porque cuesta cero descubrirlo si algún día
aparece por casualidad.

---

## 4. Lo que descarto, con el motivo

| Idea | Por qué no |
|---|---|
| `CreateFrame("Model")` en Lua con un .m2 de anillo | Un widget `Model` dibuja en **su propia escena con su propia cámara**. No comparte el búfer de profundidad del mundo, así que compone igual de mal que una textura. Es lo mismo que ya perdió, con más pasos. |
| `SendPlaySpellVisual` (`Unit.h:2031`) | Es **de un disparo**, no persistente. Sirve para un destello de "orden recibida" (que ya hace `Flare.lua`), no para un anillo que dure. |
| Repintar la textura del círculo nativo desde `rts_core` | Requiere encontrar dónde se carga el handle de textura dentro de `vtbl[0x6C]`. Es ingeniería inversa sobre este binario, con el precedente de dos intentos fallidos en la misma zona. **Sólo si el §3.1 y el §3.2 fallan los dos.** |
| Un `GameObject` prestado bajo cada unidad | Funciona y tiene miles de modelos, pero un GameObject **no se mueve** (peor que el dynobject: ni siquiera es `MovableMapObject`). Serviría para waypoints, y ahí ya tenemos algo mejor. |
| Subir `shadowLevel` para distinguir unidades | Ya se hace desde la etapa 5o, y **3.3.5a no expone tamaño ni dureza de la sombra**: es una escala de calidad. No es un mando. |

---

## 5. Qué haría, y en qué orden

1. **La prueba de cinco minutos del §3.2**, antes de escribir nada: ¿sigue un
   `DynamicObject` cuando se le mueve? Si sí, el anillo de selección nuevo son
   dos horas y 572 estilos ya navegables.
2. Si no sigue → **§3.1, la criatura invisible con modelo cambiado**. Medio día,
   sólo mod-rts, y el navegador de modelos copiado de `RtsMarks.cpp`.
3. La línea de ruta se queda en la capa de interfaz (§2.1). El coste no lo vale.
4. El color del círculo nativo sigue pausado. Si el §3.1 sale bien, deja de
   importar: se apaga el círculo nativo y el anillo pasa a ser nuestro.

**Y una nota de método, que es la que más se repite en este proyecto:** los tres
caminos nuevos tienen una incógnita cada uno y las tres se contestan **mirando,
no razonando**. La del §3.2 cuesta cinco minutos. Hacerla primero es lo que
decide si el resto del trabajo hace falta.
