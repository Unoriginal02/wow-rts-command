# La camara libre del cliente: lo que funcionaba

Escrito el 2026-09-08, **al deshacer el trabajo posterior al commit `4047b84`**
(el del boton Compartir del registro de misiones). Todo lo que hay aqui **estuvo
funcionando y confirmado en juego** el 2026-09-07; nada de esto estaba
commiteado, asi que la vuelta atras se lo lleva. Este fichero existe para poder
reconstruirlo sin volver a investigar.

Es una receta, no un diario. Solo lo que funciono.

---

## 1. El hallazgo: el cliente ya trae una camara libre

`Wow.exe` 3.3.5a build 12340 (MD5 `45892BDEDD0AD70AED4CCD22D9FB5984`) tiene la
camara de comentarista de arena expuesta a Lua. Ocho funciones, todas
localizadas por desensamblado de **este** binario:

| funcion Lua | direccion |
|---|---|
| `CommentatorSetCamera(x, y, z, yaw, pitch, fov)` | `0x0056A0F0` |
| `CommentatorGetCamera()` | `0x0056A2A0` |
| `CommentatorSetCameraCollision(bool)` | `0x0056AB70` |
| `CommentatorFollowPlayer(faction, index)` | `0x00569B50` |
| `CommentatorSetTargetHeightOffset(float)` | — |
| `CommentatorSetMoveSpeed(speed)` | — |
| `CommentatorZoomIn` / `CommentatorZoomOut` | — |

Colocacion por coordenadas de mundo, interruptor de colision de camara y
seguimiento de unidad, **ya escritos por Blizzard**.

### Como se localiza una funcion de Lua del cliente (tecnica reutilizable)

El cliente registra sus funciones en una tabla de pares `{const char*, void*}`.
Se busca la cadena del nombre, luego su direccion como dword, y los cuatro bytes
siguientes son el puntero.

**La tecnica se estreno contra `UnitClass`**, que ya estaba documentada en
`0x0060FEC0`, y dio esa misma direccion. Una tecnica nueva se prueba sobre algo
cuya respuesta ya se conoce, o no se sabe si lo que devuelve es verdad.

---

## 2. La puerta: dos flags de jugador

El predicado que consultan `SetCamera` y `GetCamera` esta en `0x006DE980`:

```
006DE9A6  mov ecx, [player + 0x1008]   ; bloque de campos PLAYER
006DE9AC  mov ecx, [ecx + 8]           ; PLAYER_FLAGS
006DE9AF  shr edx, 0x13                ; bit 19 APAGADO -> return false
006DE9B9  shr ecx, 0x16                ; bit 22 ENCENDIDO -> return true, y ya
006DE9C5  cmp [eax + 8], 4             ; si no, hace falta un mapa de tipo 4 (arena)
```

- **bit 19 = `PLAYER_FLAGS_UBER` (0x00080000): obligatorio.**
- **bit 22 = `PLAYER_FLAGS_COMMENTATOR2` (0x00400000): es lo unico que salta el
  requisito de estar en una arena**, y por eso esto es viable en mundo abierto.

Los dos comprobados contra el enum del propio nucleo (`Player.h:478,481`), no de
memoria. El nucleo ya trae `Player::SetCommentator(bool)` para el bit 22
(`Player.h:1169`).

Servidor, en `rts::camera::Spectate(player, on)`:

```cpp
player->SetPlayerFlag(PLAYER_FLAGS_UBER);
player->SetPlayerFlag(PLAYER_FLAGS_COMMENTATOR2);
```

Y al apagar se quitan los dos **sin condicion**, tambien desde `Abandon` y desde
el logout: `PLAYER_FLAGS_UBER` puesto y olvidado es estado del jugador que
sobrevive a la sesion.

> **Precio conocido de estos flags, dicho para que no sorprenda:** mientras esten
> puestos el cliente no resuelve mouseover ni objetivo contra nada. La causa es
> `0x00729740`, un predicado con 28 llamantes que devuelve false en cuanto el
> jugador local tiene el bit 19. Se convive con ello; **no se arregla parcheando
> `0x006DE980`**, que no es la puerta del modo sino un *"¿soy espectador?"*
> general con dieciocho llamantes.

> **Y ESTOS DOS FLAGS SOBREVIVEN A LA VUELTA ATRAS. Costo una sesion el
> 2026-09-08.** `PLAYER_FLAGS` se GUARDA en `characters.playerFlags`, asi que
> los dos bits quedaron escritos en la base de datos por las sesiones de la
> camara libre. Al deshacer el trabajo posterior a `4047b84` se fue el codigo
> que los quitaba -- `Spectate(false)`, `Abandon`, el gancho de logout -- pero
> **no el estado que ese codigo existia para limpiar**.
>
> El personaje se quedo con `playerFlags = 0x480000` y arrancaba en camara de
> espectador en juego normal: primera persona, el modelo sin dibujar, la camara
> volando y atravesando el suelo. Y **no quedaba una sola linea de codigo capaz
> de explicarlo**, porque toda la que hablaba de estos flags se habia borrado.
> Se leyo, con razon, como un fallo de lo ultimo que se habia instalado.
>
> La cura fue una linea:
>
> ```sql
> UPDATE characters SET playerFlags = playerFlags & ~0x00480000 WHERE online = 0;
> ```
>
> **Con el personaje FUERA del mundo**, o el `Player` en memoria lo vuelve a
> escribir al guardar y el arreglo parece no haber funcionado.
>
> La leccion es la del `camHold` del 2026-08-23 con el mecanismo al reves:
> alli la maquinaria seguia puesta y el AJUSTE guardado la armaba sola; aqui la
> maquinaria se borro y el ESTADO guardado se quedo huerfano. Las dos veces el
> estado persistente sobrevivio al codigo que lo gobernaba. **Antes de revertir
> algo que escribe estado persistente -- flags de jugador, SavedVariables, filas
> de base de datos -- hay que limpiar el estado, no solo el codigo.** Cuando
> esta receta se reconstruya, el `Abandon` incondicional del apartado 8 es lo
> que impide que vuelva a pasar en vivo; lo que no cubre es un revert, y para
> eso esta este parrafo.

---

## 3. Armar el modo: el paquete, y por que va en dos mitades

`CommentatorToggleMode` manda `CMSG_COMMENTATOR_ENABLE` (0x3B5) y espera
`SMSG_COMMENTATOR_STATE_CHANGED` (0x3B6). **No hace falta que el cliente lo
pida** — y ademas no se puede escuchar: `CMSG_COMMENTATOR_ENABLE` es
`STATUS_NEVER` + `Handle_NULL`, y `STATUS_NEVER` ni llega a `CanPacketReceive`.

Asi que lo manda el servidor por su cuenta, en `rts::camera::Arm(player, on)`:

```cpp
WorldPacket data(SMSG_COMMENTATOR_STATE_CHANGED, 8 + 1);
data << player->GetGUID();      // los 8 bytes SIN empaquetar
data << uint8(on ? 1 : 0);
player->GetSession()->SendPacket(&data);
```

- **El guid tiene que ser el del receptor**: el manejador del cliente
  (`0x0056B8A0`) lo compara contra el de su propio objeto de jugador y descarta
  el paquete si no cuadra, en silencio.
- `WorldSession::SendPacket` no valida opcodes de servidor (solo rechaza
  `NULL_OPCODE`), asi que que 0x3B6 este declarado `STATUS_NEVER` no impide
  mandarlo.

**Y VAN EN DOS VERBOS SEPARADOS (`CAM SPEC` y `CAM SPECARM`) POR UNA CARRERA
REAL:** `SetPlayerFlag` no manda nada, solo marca el campo como sucio — la
actualizacion de `PLAYER_FLAGS` sale en el siguiente flush de `Player::Update`,
unos 100 ms despues. `SendPacket` sale AHORA. Si el paquete adelanta a los
flags, el manejador encuentra la puerta cerrada, y **la rama de puerta cerrada no
es un no-op**: salta al mismo sitio que `enable == 0` y mete la camara en modo 1
con el estado que hubiera.

Quien decide que ya se puede armar es el cliente, no un retraso adivinado. La
secuencia del addon:

```
Camera:Spectate(true)                -- "CAM SPEC 1"    -> pone los flags
  -> Camera:WaitGate(12, ok, fail)   -- sondea CommentatorGetCamera() a 4 Hz
     -> FreeCam:Start()              -- coloca la camara ANTES de armar
        -> Camera:Arm(true)          -- "CAM SPECARM 1" -> manda el paquete
```

`WaitGate` funciona porque `CommentatorGetCamera` **devuelve seis numeros si la
puerta esta abierta y nada si no** (la rama cerrada sale sin apilar). Es una
lectura pura, cero riesgo.

Modo 6 = `VIEW_COMMENTATOR`. Los ocho nombres estan en la tabla de cadenas de
`0x00AD213C`: `FIRST_PERSON`, `THIRD_PERSON_A..E`, `VIEW_COMMENTATOR`,
`VIEW_BARBER_SHOP`.

---

## 4. El giro con el raton: NATIVO. No lo hagas tu

Costo cinco intentos y la conclusion es una linea: **cuando el cliente ya hace
algo bien, el trabajo es convivir con el, no reimplementarlo.**

Lo que NO funciona, para no repetirlo:

1. `IsMouseButtonDown("RightButton")` — devuelve **NO** mientras el cliente tiene
   el raton cogido en mouselook.
2. `IsMouselooking()` + `MouselookStop()` — `IsMouselooking` es **false** para el
   arrastre del propio cliente, y `MouselookStop` solo suelta un mouselook que
   haya empezado un addon.
3. El DLL leyendo el raton en crudo por `WM_INPUT` y girando nosotros —
   funcionaba y **se sentia mal por construccion**: el DLL acumula deltas, los
   publica a 67 Hz por una cadena de Lua, y el addon los aplica al frame
   siguiente. Tres etapas de retardo y una cuantizacion.

**Lo que si funciona:** dejar que gire el cliente, que ya lo hace con la
sensibilidad y la inversion que el jugador tiene configuradas.

El truco de convivencia es que `CommentatorSetCamera` toma los seis valores de
golpe, asi que no se puede escribir la posicion sin escribir los angulos:

```lua
-- AdoptLook(): se leen los angulos VIVOS justo antes y se reescriben tal cual.
-- Para la orientacion es un no-op, y deja que el giro del cliente se acumule.
local ok, x, y, z, yaw, pitch, fov = pcall(CommentatorGetCamera)
```

**Se leen con `CommentatorGetCamera` y NO con `RTS_CamFwd*`.** `GetCamera` es
**sincrono** — lee `cam+0x11C` (yaw) y `cam+0x120` (pitch) de la camara activa en
este mismo frame — mientras que los globales del DLL llegan con un tick de
retraso. **Esa eleccion es la que quita la latencia.**

---

## 5. La altura sobre el terreno: la parte que costo mas y la que mejor salio

Esto es lo que el 2026-08-23 se habia declarado imposible por los dos caminos
(servidor = ascensor, cliente = hover necesita gravedad). Con la transformada en
nuestras manos deja de ser un problema de mecanismo y pasa a ser aritmetica.

### 5.1 El suelo se mide BAJO LA CAMARA, no bajo el jugador

Publicado por el DLL como `RTS_CamGroundHit` / `RTS_CamGroundZ`, en el **tick de
camara (~67 Hz)**, no en el completo:

```cpp
constexpr float kCamGroundUp   = 5.0f;
constexpr float kCamGroundDown = 1000.0f;

world::Vec3 gs = {cam.pos[0], cam.pos[1], cam.pos[2] + kCamGroundUp};
world::Vec3 ge = {cam.pos[0], cam.pos[1], cam.pos[2] - kCamGroundDown};
camGroundHit = world::Raycast(gs, ge, &ghit, nullptr);
if (camGroundHit) camGroundZ = ghit.z;
```

Las tres decisiones, con su motivo:

- **Bajo la camara y no bajo el jugador.** El unico suelo que se publicaba antes
  (`RTS_GroundZ`) estaba bajo el personaje, y en una camara RTS la camara pasa la
  mayor parte del tiempo donde el personaje no esta — que es justo cuando hace
  falta.
- **En el tick de camara.** El controlador lo consume por frame: la altura se
  corrige contra el suelo de DONDE ESTA la camara ahora, no de donde estaba hace
  30 ms.
- **El rayo empieza 5 yd ARRIBA y baja 1000.** Arriba porque la camara puede
  estar por debajo del terreno un instante mientras el suavizado la sube, y un
  rayo que empieza dentro del suelo no lo encuentra. Mil yardas abajo porque el
  techo de la altura lo pone el jugador, y un rayo corto deja de contestar justo
  cuando se sube — lo que se ve como que la correccion de altura *"se apaga sola
  a cierta altura"*.

El rayo va por `CGWorldFrame::Intersect` — thunk `0x0077F310` (cuerpo
`0x007A3B70`), flags `0x00100171` (terreno + WMO + M2), `dist` inicializado a
1.0.

### 5.2 ESPACIO y C mueven el OFFSET, no la Z

Es la clave de que se pueda **avanzar y subir a la vez**, que era imposible con
la camara poseida:

```
targetZ = sueloBajoLaCamara + offset
```

Las dos entradas (desplazamiento en el plano y offset vertical) son entradas del
**mismo solver** y se integran en el **mismo frame**, asi que ninguna corta a la
otra. Con la camara Puppet, subir era un `NearTeleportTo` por tick y cada
teleport cancelaba el movimiento que el cliente estaba aplicando.

### 5.3 Sin suelo no se inventa uno

```lua
if ground then
    targetZ = ground + st.offset
else
    -- El rayo puede no contestar en una cueva o sobre agua profunda. Mantener
    -- la Z es lo unico que no pega un salto. Lo que NO se hace es caer al
    -- terreno bajo el JUGADOR, que fue la tentacion obvia: en una camara RTS
    -- ese punto puede estar a cientos de yardas y en otra altura.
    targetZ = st.z
end
```

### 5.4 El suavizado, independiente del frame rate

```lua
local alpha = 1 - math.exp(-c.smoothZ * dt)     -- altura
local ease  = 1 - math.exp(-c.ease    * dt)     -- velocidad en el plano
```

`1 - exp(-k*dt)` y no un `lerp` con constante fija: con `dt` variable un lerp
fijo cambia de dureza con los FPS.

Y un **suelo duro** por debajo del suavizado: `z >= ground + clear`.

### 5.5 Adelante es PLANO, nunca el vector de vista

Es la leccion de la etapa 5f, donde `SetCanFly(true)` era la razon de que la
camara "volara": en modo vuelo el cliente mueve la unidad a lo largo de su VISTA,
asi que mirando al suelo y pulsando W desciendes.

```lua
local function FlatForward()
    if RTS_HasCam ~= 1 then return nil end
    local fx, fy = RTS_CamFwdX, RTS_CamFwdY
    if not fx or not fy then return nil end
    local len = math.sqrt(fx * fx + fy * fy)
    -- Mirando a plomo la proyeccion es casi cero y la direccion deja de estar
    -- definida. No se normaliza una longitud minuscula: no hay adelante, y ese
    -- frame no se avanza -- preferible a salir disparado en una direccion
    -- aleatoria.
    if len < 0.001 then return nil end
    return fx / len, fy / len
end
```

- El vector se le pide al DLL (`RTS_CamFwdX/Y`) en vez de derivarlo del yaw
  propio, **lo que evita la pregunta de cual es la convencion de angulos de
  `CommentatorSetCamera`** — que no se puede leer del binario. El yaw solo se usa
  para GIRAR; la direccion de avance nunca depende de el.
- **El lateral se calcula rotando el adelante 90 grados** (`rx, ry = fy, -fx`) y
  **no** con `RTS_CamRight*`: la fila "right" de la matriz del cliente es la
  IZQUIERDA geometrica (`forward x up = -right`, verificado sobre la matriz
  registrada; `CursorRay.cpp` lleva `kRightSign = -1.0f` por lo mismo).

---

## 6. Los ajustes que quedaron bien, medidos en juego

```lua
speed   = 30.0    -- yardas/segundo en el plano
lift    = 14.0    -- yardas/segundo de offset con ESPACIO y C
turn    = 90.0    -- grados/segundo con Q y E
height  = 30.0    -- offset inicial sobre el suelo
minH    = 4.0
maxH    = 300.0
smoothZ = 8.0     -- k del suavizado de altura (1/s); mas alto, mas seco
pitch   = 45.0    -- grados; POSITIVO MIRA ABAJO
clear   = 2.0     -- margen duro sobre el suelo
yawSign = 1
ease    = 9.0     -- k del arranque/parada en el plano (1/s)
```

**`pitch` POSITIVO mira HACIA ABAJO.** Con -45 la camara apunta al cielo. Es la
convencion de `CommentatorSetCamera` y no se puede leer del binario: el
desensamblado solo ensena que el argumento se multiplica por `DEG2RAD`
(`0x009E2B40`) y se guarda.

Y por eso los ajustes guardados llevan **sello de generacion** (`GEN`): cuando
`pitch` cambio de significado, `-45` seguia estando dentro del rango valido, asi
que cambiar el valor por defecto **no hizo nada** en un cliente que ya lo tenia
guardado. Comparar el rango no basta cuando lo que se mueve es lo que el numero
QUIERE DECIR. Al subir la generacion se tira la tabla entera y se dice.

---

## 7. El FOV en modo comentarista

**En modo 6 el FOV pertenece al estado de la camara de comentarista
(`0x00ACE4E4`) y el cliente lo repone**, asi que la escritura del DLL sobre
`cam+0x40` (el canal `rtsFov`) PIERDE. `/rts cam fov` tiene que ir por
`CommentatorSetCamera`, que es su dueno mientras el modo este armado.

**Y el sexto argumento NO admite 0.** Va en grados y se acota entre los valores de
`0x009E2B40` y `0x00A0FF40`, que leidos del binario son **1 y 120**. El suelo no
es un valor cualquiera: `0.01745329` **es** `DEG2RAD`. Pasar 0 da `0 <= DEG2RAD`,
gana el suelo, y te quedas con **un grado** — una pantalla morada e ilegible.

El error de fondo no fue el numero: fue **traerse una convencion de otro canal**.
En `rtsFov` el 0 significa *"no toques el FOV"*, y eso es una propiedad de ese
canal, no del FOV. Dos caminos al mismo campo con dos significados para el mismo
valor.

---

## 8. Piezas de servidor que hacen falta

- **`rts::camera::Spectate(player, on)`** — pone y quita los dos flags. Al apagar,
  llama tambien a `Arm(player, false)`: la rama `enable == 0` del cliente **no
  pasa por el predicado**, asi que funciona con los flags ya quitados, y es la
  unica salida que tiene el jugador si el modo se quedo armado.
- **`rts::camera::Arm(player, on)`** — manda el paquete.
- **`rts::camera::Abandon(player)`** — quita los flags **sin condicion y antes de
  mirar si habia camara**, y desarma el modo. Enganchado a `OnPlayerLogout` y a
  `OnPlayerBeforeTeleport`.
- **`IsSpectating(player)`** — un `std::set<ObjectGuid>` que llena `Arm`.
  Lo necesita `rts::orders::MoveSelf`, cuya guarda exige que alguien le haya
  quitado el control del cliente al personaje:

  ```cpp
  if (!player->GetCharm() && !player->GetViewpoint() &&
      !rts::camera::IsSpectating(player))
      return fail("the RTS camera is not holding control");
  ```

  Las dos primeras condiciones preguntan por una POSESION, que es como el Puppet
  lo cumplia. La camara de comentarista no posee nada, asi que le quita el
  control por el otro camino (`SetClientControl(player, false)`). **Sin esa
  tercera condicion, jubilar el Puppet deja tu propio heroe inordenable.**

- Y `SetClientControl(player, false)` **solo si no hay nada poseido**
  (`player->GetCharm() != nullptr`): manda `SMSG_CLIENT_CONTROL_UPDATE` con el
  guid del jugador, que es literalmente *"tu unidad activa es esta"*, y eso
  deshace una posesion puesta un instante antes.

---

## 8bis. EL HEROE INVISIBLE: RESUELTO. Cinco bytes.

Escrito el 2026-09-09, y **confirmado en juego**: con los flags puestos el heroe
se ve, tambien desde la camara de comentarista aparcada.

### La cura

```
0x006E085C   call 0x006DE980   ->   31 C0 90 90 90   (xor eax,eax + 3 nop)
```

Un solo sitio de llamada, cinco bytes, mismo tamano, reversible. Lo hace
`rts_core` (`SelfShow.cpp`) y **se arma solo**: la condicion no es "lo hemos
pedido" sino **"el jugador local LLEVA los dos flags"**, asi que cubre igual que
los ponga la sonda o que los ponga el servidor con `rts::camera::Spectate`. Al
quitarse los flags el parche se va solo.

### Por que ahi, y por que no se encontraba leyendo

`0x006E0840` es un metodo VIRTUAL -- **cero `call rel32` le apuntan**, se llama
por vtable. Por eso ningun camino estatico llegaba: se buscaba "quien esconde un
modelo" y ahi no se esconde nada, se **contesta 1**.

```
006E0855  call 0x00730F30            ; calcula el valor
006E085A  mov  ecx, esi
006E085C  call 0x006DE980            ; ¿este jugador es espectador?
006E0861  test al, al
006E0863  je   0x006E0871            ; NO -> sigue evaluando
006E0866  mov  dword ptr [ebx], 1    ; SI -> fuerza el resultado a 1, y sale
006E086E  ret  0xc

006E0871  test dword ptr [esi+0xa30], 0x400000   ; la rama normal tiene sus
006E087D  cmp  dword ptr [esi+0x18b8], 0         ; propias razones para el
006E0884  jne  0x006E0865                        ; mismo *out = 1
```

`ebx` es el tercer argumento, un `int*` de salida. Ser espectador entra por la
puerta de atras en un calculo que ya existia.

El predicado pregunta por `esi`, o sea POR ESA UNIDAD, asi que apagar este sitio
solo cambia la respuesta de quien lleve los flags -- nosotros y nadie mas. Es lo
contrario del parche del 2026-09-08, que reescribio el predicado COMPARTIDO por
sus dieciocho llamantes y dejo la pantalla sin nadie.

### Como se encontro, que es lo reutilizable

**Por eliminacion, no leyendo.** Seis candidatos habian caido antes por lectura
estatica, incluida una cadena entera (`0x0073A890` -> `0x006DE980`) cuyo `jne` se
forzo en las DOS direcciones sin mover un pixel.

1. Barrido de `call rel32` sobre `.text` quedandose con los que apuntan al
   predicado: **18 sitios**, medidos.
2. **Apagarlos TODOS a la vez** con los flags puestos. Vuelve el modelo -> el
   predicado ES el mecanismo. *Esta pregunta iba primero y se hizo la ultima.*
3. De uno en uno hasta que uno solo lo devolvio: el 16.

Cada sitio son cinco bytes con la firma comprobada antes de escribir, y el DLL
los suelta al detach. El instrumento sigue en `/rts body sites all` y
`/rts body site 0..17`.

**Y la trampa que se comio una vuelta:** ocho sitios se probaron con los flags
sin poner. Sin ellos el predicado contesta false en todas partes, eres visible
igual, y CUALQUIER sitio parece devolverte el modelo -- dieciocho falsos
positivos seguidos, todos convincentes, sin un solo error. `B:Sites` ahora se
niega si los flags no estan puestos.

### Lo que NO era

- **No es el bit 19 ni el bit 22 por separado.** Probados solos: ninguno esconde.
  Y no podian: el predicado exige los DOS fuera de arena, asi que esa prueba era
  negativa por construccion. Los dos juntos, o nada.
- **No es `0x0073AAB0`.** Forzado a `nop nop` (no salta nadie) y a `jmp` (saltan
  todos), los dos unicos caminos posibles: nadie desaparece, ni el heroe ni los
  bots. Esa rama no dibuja modelos.

---

## 9. Interiores

`CommentatorSetCameraCollision(false)` — una llamada — hace que la camara
atraviese geometria. Es la respuesta barata para cuevas y edificios.

**Y estuvo escrita sin llamarse desde el 2026-09-03 hasta el 2026-09-10.**
`Camera:CameraCut` existia, colgada de `/rts cam colision`, como algo que
*probar*; entrar en el modo RTS no la llamaba. O sea que la camara libre
colisiono con todo durante toda su vida util y el sintoma —«no puedo entrar en
una casa»— se leyo como un problema de altura, que tambien lo era. **Dos causas,
un solo sintoma, y arreglada una sola la pantalla se ve igual.**

Lo que hace, leido el 2026-09-10 y ya no supuesto:

- El manejador (`0x0056AB70`) escribe 1 o 0 en `0x00ACE4F0`.
- Ese no es un global suelto: es el campo `+0x48` del objeto de comentarista de
  `0x00ACE4A8`. **Buscar la direccion absoluta en `.text` da dos escrituras y
  ninguna lectura, y esa conclusion es falsa** — se lee por base+desplazamiento,
  que la busqueda por literal no ve. Es la version fina de "enumera, no cuentes".
- El lector esta en el recorrido de camara:

```
00568B31  cmp dword ptr [esi + 0x48], 0
00568B43  je  0x568b69                  ; 0 -> se salta el rayo entero
00568B49  push 0x100171                 ; 1 -> rayo contra terreno + WMO + M2
00568B5B  call 0x77f310                 ; CGWorldFrame::Intersect
```

  Las **mismas banderas** que el rayo de suelo del §12. Apagarlo no es un truco
  de dibujo: le quita el rayo de encima a la camara.
- **Arranca encendido.** El global esta a 0 en el fichero, pero `0x0056BC80` —el
  init del objeto— escribe 1 en `+0x48`. Tiene UN solo llamante (`0x0056C150`),
  dentro de la cadena de arranque del cliente (`0x0052B864`), asi que corre una
  vez al abrir el juego. Por eso **basta con apagarlo al entrar**: nadie lo
  vuelve a encender por detras, y no hay que refrescarlo cada tick.
- **Exige los dos flags de jugador.** Sin ellos el manejador se va por
  `je 0x56ac01` y retorna **sin escribir y sin error**. Llamarlo antes de armar
  es una llamada que parece funcionar y no hace nada — el mismo modo de fallo de
  siempre, esta vez dependiente del MOMENTO en vez del cliente.

Desde el addon 1.11.0 lo apaga `FreeCam:Start` (despues de `WaitGate`, o sea con
los flags puestos) y lo devuelve a 1 `FreeCam:Stop` —el valor que escribe el init
del cliente, medido, no supuesto—, antes de que `Spectate(false)` quite los
flags. El mando es `/rts fc noclip`.

Y el rayo del suelo tiene su propio caso de cueva: **si el rayo empieza por
debajo del terreno, el paseo por el campo de alturas no se hace y manda la
interseccion con el modelo**, que es lo unico valido ahi. Sin eso, dentro de una
cueva `pz <= g` es cierto en el primer paso — estas debajo del monte desde el
metro uno — y el rayo contesta la ladera de fuera.

Lo que **no** es alcanzable: cortes por shader. Esta frase estaba escrita a
medias — decia que `M2UseClipPlanes`, `farClipOverride`, `antiportal` y
`TogglePortals` "son comandos de consola, no CVars" y que con `showToolsUI "1"`
se podian probar a mano. **Se han mirado los cuatro el 2026-09-10 y ninguno
sirve**, cada uno por una razon distinta:

| cadena | que es de verdad |
|---|---|
| `M2UseClipPlanes` | CVar, y su descripcion al lado lo dice: *"use clip planes for sorting transparent objects"*. Es ordenacion de transparencias, no un corte de escena |
| `farClipOverride` | CVar de distancia de vision. Recorta el fondo, no el techo |
| `antiportal` | NO es un comando: esta pegada a `.\MapObjRead.cpp` y a `missingwmo.wmo`. Es el nombre de una bandera DENTRO del fichero WMO, que el cliente lee del disco |
| `TogglePortals` | **funcion de Lua registrada, e inerte** |

La ultima es la que habria costado una ronda entera, porque es de las que
funcionan a medias en el peor sentido: `TogglePortals` esta en la tabla de
registro (`0x00AC8228`), asi que existe y se puede llamar sin error. Su puntero
va a `0x008E5250`. Y ahi hay esto:

```
008E5250  xor eax, eax
008E5252  ret
```

Un stub. **Y no es solo ella**: `ToggleCollision` (`0x00AC8230`),
`ToggleCollisionDisplay` (`0x00AC8238`), `TogglePlayerBounds` (`0x00AC8240`) y
`ToggleTris` (`0x00AC8220`) apuntan **las cinco a la misma direccion**. Las
herramientas de depuracion se vaciaron en la compilacion de release y solo
quedaron los nombres.

Es exactamente el modo de fallo de `nearclip` -- la cadena existe, el CVar
existe, el manejador no hace nada -- y del reves que `guildMemberNotify`, donde
la cadena existia y el CVar no. Tercera vez que esta familia muerde, y la unica
forma de verlo es leer el manejador: desde fuera, llamar a `TogglePortals()` no
da error de ninguna clase.

**Lo que si funciona para ver dentro de un edificio es entrar, y hacen falta las
DOS cosas de arriba.** La colision apagada deja pasar la pared; la altura medida
contra el terreno (§12) impide que el tejado la levante. Con una sola de las dos
el sintoma no se mueve: con la colision apagada y el suelo viejo, la camara
atraviesa la pared y aun asi sube al tejado; con el suelo nuevo y la colision
puesta, no sube pero choca. Y estando dentro el cliente recorta el exterior el
solo con sus portales — el corte que se buscaba en §10/§11 lo hace el cliente
gratis. Lo que hacia falta no era cortar, era poder pasar.

---

## 10. Orden de reconstruccion sugerido

1. Servidor: `Spectate` / `Arm` / `Abandon` / `IsSpectating` + los verbos
   `CAM SPEC` y `CAM SPECARM`, y la tercera condicion de `MoveSelf`.
2. DLL: el rayo del suelo bajo la camara -> `RTS_CamGroundHit` / `RTS_CamGroundZ`
   en el tick de camara.
3. Addon: `Camera:Spectate` / `WaitGate` / `Arm` / `SpecPlace`, y el sondeo
   `/rts cam probe` (seis pasos, parando en el primero que no conteste, cada uno
   diciendo que significaria fallar ahi).
4. Addon: el controlador, en cuatro capas — entrada (botones propios por flanco),
   solver (plano + suelo), suavizado (exponencial por dt), aplicar (UNA escritura
   por frame).
5. `AdoptLook` para que el giro sea nativo.

**Y el instrumento que hay que conservar:** `/rts cam probe`. Es lo que convierte
*"la camara no va"* en *"el paso 2 no contesta, o sea que los flags no han
llegado"*.

---

## 11. Un lector que no sirve, para no perder tiempo con el

`CommentatorGetCamera()` **no vale para comprobar si la camara se movio**: lee la
posicion de los globales del estado de comentarista
(`0x00ACE4B4/B8/BC`), o sea **lo que le pediste**, no donde esta la camara de
verdad. Un lector que devuelve tu propia peticion es el modo de fallo que este
proyecto lleva persiguiendo desde `C:Report()` imprimiendo el FOV que no se
aplicaba.

El testigo honesto es **`RTS_CamX/Y/Z`**, que el DLL saca del campo de posicion
de la camara activa (`cam+0x08`) sin pasar por Lua.

Para lo que **si** vale `GetCamera` es para saber si la puerta esta abierta
(seis numeros o nada) y para leer los angulos vivos de forma sincrona, que es
justo lo que hace `AdoptLook`.

---

## 12. "El suelo" no es "lo primero que hay debajo" (2026-09-10)

Las dos cosas se dicen igual y solo son la misma en campo abierto. El rayo del
§5.1 usa las banderas `0x00100171` — terreno **mas** WMO **mas** M2 — asi que lo
que contesta es *lo primero que haya*. Acercando la camara a una casa eso es el
TEJADO: la altura se corregia contra el tejado, la camara subia sola, y entrar
era imposible por construccion. Un cartel de madera hacia lo mismo en pequeno,
un salto de seis yardas y vuelta.

### La misma funcion, otra mascara

`CGWorldFrame::Intersect` tiene exactamente **dos** mitades, y cada una se
enciende con su propia mascara. Del cuerpo en `0x007A3B70`:

```
007A3B8A  test eax, 0x40F300FF   -> call 0x007A30D0    ; objetos
007A3C2E  test eax, 0x40F3010F   -> call 0x007A39F0    ; terreno
```

Cual es cual no se supone, se lee en las dos: `0x007A30D0` mide el largo del
rayo, carga 6000 como tope y recorre una estructura espacial — WMO y doodads;
`0x007A39F0` convierte las dos puntas a indices de casilla con
`fmul [0x00A3FDA0] / fistp` contra el global `0x009E2ACC`, que es la rejilla de
ADT. Terreno.

**El bit `0x100` esta en la segunda mascara y no en la primera**, asi que
`flags = 0x100` no filtra el bloque de objetos: no llega a entrar en el. Es la
unica pareja de bits que separa las dos mitades limpiamente — `0x01..0x80` solo
estan en la de objetos, y `0x0F` y `0x00F30000` estan en las dos, incluido el
`0x00100000` que llevan las banderas de siempre y que por tanto no distingue
nada.

### Se publican las dos, y elige el addon

`rts_core` 0.25.0 lanza el mismo rayo dos veces y publica
`RTS_CamGroundZ` (todo) y `RTS_CamLandZ` (solo terreno). `/rts fc floor 1` usa el
terreno, `0` usa el de siempre. Sustituir el que ya habia habria movido el tacto
de la camara sin que nadie lo pidiera, y el de siempre sigue siendo el bueno
para sobrevolar un pueblo sin meterse en nada.

Con `floor 1` **el rayo de terreno puede no contestar**, y ahi no es un fallo:
dentro de una cueva el ADT esta agujereado a proposito. Se cae al solido, que en
ese sitio es el suelo de la cueva — la respuesta correcta, no una degradada. Y
es tambien lo que pasa con un `rts_core` viejo, que no publica la variable en
absoluto: la camara se porta como antes en vez de quedarse sin altura.
`/rts fc` lo dice con todas las letras si el DLL es viejo, porque si no
`floor 1` se comporta igual que `floor 0` y parece que el ajuste no hace nada.

### Y un escalon no es una cuesta

Aunque no haya tejados, el terreno tambien tiene bordes. El suavizado del §5.4
trabaja sobre el ERROR de la camara y un error no dice de donde viene: seis
yardas de error son las mismas subiendo una loma que cruzando por encima de un
poste. Lo que si los separa es **cuanto corre el suelo** — una cuesta a toda
velocidad son ~20 yd/s, el borde de un escalon son seis yardas EN UN FRAME.

Asi que hay un filtro **delante** del suavizado, sobre la senal de suelo:
persigue al suelo medido con la velocidad limitada, y el limite baja con el
tamano del escalon.

```
v = climb / (1 + (escalon/soft)^2),  nunca menos de slow
```

Tres cosas de este filtro no son evidentes y las tres las encontro
`sim/ground_filter.py`, no el juego:

1. **El freno se decide con el tamano del escalon, no con lo que quede de el.**
   Escrito con "lo que queda" — que es lo natural — cada subida se ACELERA al
   acercarse: las ultimas dos yardas de un escalon de quince se hacian a
   25 yd/s, casi el doble de lo que sube el jugador a mano. El mismo tiron que
   se venia a quitar, mudado al final del recorrido. "Esto es un escalon" es una
   propiedad del suceso, no de la distancia que queda ahora, asi que se recuerda
   (`pend`, el mayor desnivel visto desde la ultima vez que el filtro se puso al
   dia) y se borra al ponerse al dia.
2. **Hace falta un tope de retraso, y sale del offset.** Un escalon seguido de
   una cuesta larga deja el freno puesto y el filtro no alcanza nunca: sin tope
   el desnivel crece sin final y la camara acaba rescatada por el suelo duro,
   pegada al terreno. El tope no es una constante nueva — si el suelo real no
   debe acercarse a la camara mas de `clear`, y la camara vuela a `offset` sobre
   el suelo filtrado, el filtrado no puede quedarse mas de `offset - clear` por
   debajo del real. Y **solo hacia arriba**: hacia abajo el retraso no es
   peligroso, es la vista.
3. **El suelo duro se mide contra el suelo real**, no contra el filtrado. Que no
   sea el tiron de siempre otra vez lo garantiza el tope, no la suerte: con el
   tope puesto el `if` no llega a dispararse mientras manda el filtro. Sin el,
   los dos se pelearian cada frame, uno frenando y el otro empujando.

Lo que **no** arregla, y es honesto decirlo: un escalon **mas alto que la altura
de vuelo**. Cruzando el borde de un acantilado de 60 yardas volando a 30, el
frame en que se cruza la camara ya esta DENTRO de la roca — el rayo solo mira
hacia abajo, asi que el acantilado no se ve venir, se descubre estando dentro.
Ahi el tiron es la unica salida y es para lo que existe `clear`.

---

## 13. LA ESPADA Y EL ATAQUE: tres puertas, y el mismo bit detras (2026-09-11)

Sintoma: con la camara libre puesta, pasar el raton por encima de un enemigo no
sacaba la espada y el boton derecho no atacaba. El icono de mision y la bolsa de
botin SI salian -- eso es lo que hizo el caso legible, porque significa que el
cursor y la accion del boton derecho funcionaban y lo que estaba cortado era
solo *atacar*.

Y fuera del modo RTS el boton derecho ataca bien. O sea que el mecanismo estaba
entero y lo rompia nuestro propio estado.

**Eran TRES puertas, y `PLAYER_FLAGS_UBER` esta detras de las tres.** Ese es el
bit 19, el que el cliente EXIGE para abrir la camara de comentarista
(`0x006DE980`), asi que no se puede simplemente no ponerlo.

Abrir una sola no cambia nada en pantalla, y eso costo dos rondas: se leyo la
primera entera en el binario, se parcheo, se probo, y no se movio un pixel.
**Media cura no se distingue de una cura equivocada.**

### Puerta 1 -- el cursor, en el cliente

`0x004F7A50` decide el cursor de lo que hay bajo el raton. Para el de ataque:

```
004F7F81  push ebx / mov ecx, edi
004F7F84  call 0x00729A70          ; ¿puedo atacar a esto?
004F7F89  test al, al / je -> sin cursor
...
004F7FC0  jp 0x004F7AE3            ; -> push 4  = cursor "Attack"
004F7FC6  push 0x1e                ; = "UnableAttack" (fuera de alcance)
```

`0x00729A70` acaba llamando a `0x00729740`, que es el predicado de
`UnitCanAttack` -- la funcion Lua esta en `0x0060D730` y lo llama en
`0x0060D786`. Y ese predicado empieza asi:

```
0072974C  shr ecx, 4 ; test cl, 1   ; ¿el SUJETO es un jugador?
00729752  je  0x0072976B
0072975D  shr eax, 0x13 ; test al,1 ; bit 19 = PLAYER_FLAGS_UBER
00729762  je  0x0072976B            ; apagado -> sigue evaluando
00729764  xor al, al                ; ENCENDIDO -> FALSO, y ya
```

Con el bit puesto, `UnitCanAttack("player", loquesea)` es **falso para todo**.
El icono de mision y el botin se salvan porque van por otro predicado
(`UnitCanCooperate` usa `0x00729B30`).

Cura: un byte, `0x00729762` `je` -> `jmp`. En `rts_core`, armado con los flags.
Ver `Offsets.h`, `kCanActUberJe`.

### Puerta 2 -- el mismo cursor, unas lineas mas abajo

```
004F7FA5  cmp dword ptr [0x00BCFB8C], 0
004F7FAC  je  -> sin cursor
```

Ese global lo escribe `0x00520FE0` con el bit 10 de `[unidad + 0xa30]`, que
enciende y apaga `SMSG_CLIENT_CONTROL_UPDATE` (`0x0071C930`). Y **el ataque de
verdad muere en el mismo global**: el `AttackTarget` de Lua (`0x0051A650`) baja
a `0x0072C2B0`, que lo vuelve a mirar en `0x0072C3E9`.

O sea que `SetClientControl(player, false)` -- la linea que `camera::Arm` metio
el 2026-09-10 al jubilar el Puppet -- apagaba el cursor y el ataque de un golpe.

Cura: no quitarle el control al cliente de fabrica. `CAM CTRL 1` lo vuelve a
quitar, porque era lo que permitia que el servidor condujera tu propio heroe.
Es un trato con dos mitades, no un fallo.

### Puerta 3 -- el servidor, y esta es la que remata

`Unit::_IsValidAttackTarget`, `Unit.cpp:10762`:

```cpp
if (Player const* playerAttacker = ToPlayer())
{
    if (playerAttacker->HasPlayerFlag(PLAYER_FLAGS_UBER) ||
        playerAttacker->IsSpectator())
        return false;
}
```

**Un jugador con el bit 19 no puede atacar a nada**, y ese es el UNICO uso del
bit en todo el nucleo (enumerado, no supuesto). El bit 22 solo pone una etiqueta
de chat (`Player.cpp:1381`).

El sintoma en pantalla fue el que lo delato: el circulo del bicho se ponia
**rojo un tick y volvia a amarillo**. El cliente empezaba el ataque, el servidor
lo rechazaba aqui, el cliente lo deshacia. *Empieza y se cancela* no es *esta
bloqueado*, y esa diferencia es la que llevo al nucleo en vez de a otro parche
del cliente.

Cura: **cada lado se queda con lo suyo.** El servidor manda solo el bit 22
(`mod-rts 0.48.0`); el bit 19 lo escribe `rts_core` en la memoria del cliente,
armado al ver el bit 22 y reescrito cada tick por si el servidor reenvia el
campo. El predicado del cliente lo lee de ahi y no se entera de nada.

**Consecuencia: la camara libre pasa a necesitar el DLL inyectado.** Sin el, el
bit 19 no existe en ninguna parte y la puerta del cliente no abre nunca --
`CameraOn` se cae al Puppet y lo dice.

## Apendice: direcciones usadas, todas de este `Wow.exe`

| que | direccion |
|---|---|
| world frame (base de la cadena de camara) | `0x00B7436C` |
| camara activa | `*(*(0x00B7436C) + 0x7E20)` |
| posicion de camara | `cam + 0x08` (3 floats) |
| matriz de orientacion | `cam + 0x14` (filas en +0x14 / +0x20 / +0x2C; fila 0 = adelante) |
| FOV (diagonal, radianes) | `cam + 0x40` |
| aspect | `cam + 0x44` |
| modo de camara | `cam + 0xB4` (6 = `VIEW_COMMENTATOR`) |
| yaw vivo / pitch vivo | `cam + 0x11C` / `cam + 0x120` (radianes) |
| tabla de nombres de modo | `0x00AD213C` |
| predicado de la puerta | `0x006DE980` |
| manejador de `SMSG_COMMENTATOR_STATE_CHANGED` | `0x0056B8A0` |
| `CGWorldFrame::Intersect` (thunk) | `0x0077F310`, flags `0x00100171` |
| `Intersect`, cuerpo real | `0x007A3B70` |
| `Intersect`, mitad de objetos (WMO + M2) | `0x007A30D0`, mascara `0x40F300FF` |
| `Intersect`, mitad de terreno | `0x007A39F0`, mascara `0x40F3010F` |
| solo terreno | flags `0x00000100` |
| stub compartido de los cinco `Toggle*` | `0x008E5250` (`xor eax,eax; ret`) |
| `CommentatorSetCameraCollision` (manejador) | `0x0056AB70` |
| objeto de comentarista | `0x00ACE4A8` |
| bandera de colision de camara | `0x00ACE4F0` = objeto `+0x48`, 1 = choca |
| lector de la bandera (recorrido de camara) | `0x00568B31` |
| init que la pone a 1 | `0x0056BC80`, unico llamante `0x0056C150` (arranque) |
| `DEG2RAD` | `0x009E2B40` |
| tope de FOV (120) | `0x00A0FF40` |
| estado de comentarista (pos) | `0x00ACE4B4/B8/BC` |
| estado de comentarista (FOV) | `0x00ACE4E4` |
