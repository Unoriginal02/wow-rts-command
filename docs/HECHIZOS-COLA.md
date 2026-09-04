# Los tipos de hechizo y la cola — el estudio previo de §5.1

Escrito 2026-09-04, antes de construir la cola de hechizos del
`brief-barra-control-grupo.md`. El brief lo pide explicitamente: *"Antes de
cerrar la logica de la cola hay que inventariar que otros tipos de hechizo
existen en el juego y decidir el comportamiento de cada uno."*

Todo lo de aqui esta **leido en la fuente de este servidor y de este cliente**,
con fichero y linea, no recordado. Donde no he podido comprobar algo lo digo.

---

## 1. LA DECISION DE FONDO: CLASIFICA EL SERVIDOR, NO EL ADDON

La tentacion es escribir en `Skills.lua` una tabla de "estos hechizos necesitan
objetivo" o adivinarlo con `IsHarmfulSpell`. Las dos son la factura que este
proyecto lleva seis etapas pagando — `nameplateMaxDistance`,
`gxWindowedResolution`, `SetCamera(1)`, `GetActionInfo` — y aqui seria peor,
porque:

- **El cliente no conoce los hechizos del bot.** `IsHarmfulSpell` y compania
  toman un nombre o un indice de **tu** libro. La Polimorfia del mago no esta
  en tu libro. Lo unico que el cliente sabe de un id ajeno es lo que
  `GetSpellInfo(id)` saca del DBC: nombre, icono, rango, tiempo de lanzamiento.
  Ni si necesita objetivo, ni si es amistoso.
- **El servidor lo sabe todo y ya tiene las respuestas escritas.** `SpellInfo`
  (`src/server/game/Spells/SpellInfo.cpp`) trae un predicado por cada pregunta
  del brief, y ninguno hay que deducirlo.

Asi que **el verbo `BARS` pasa a devolver, por hechizo, una LETRA DE TIPO**.
El addon no clasifica: dibuja lo que le dicen. Si el dia de manana un hechizo
se comporta raro, la respuesta esta en un solo sitio y es del lado que tiene el
dato.

---

## 2. LA TABLA DE TIPOS

La columna "predicado" es lo que decide, en orden: **la primera que da cierto
gana**. El orden importa — un Renovar es a la vez "positivo" y "necesita
objetivo", y lo que manda para la cola es lo segundo.

| letra | tipo | predicado (SpellInfo.cpp) | segundo click | comportamiento |
|---|---|---|---|---|
| `P` | pasivo / no lanzable | `IsPassive()` :1130 | — | **no entra en un hueco.** Se filtra al construir la lista |
| `S` | solo sobre uno mismo | `IsSelfCast()` :1122 | no pide | se lanza ya, sobre el bot |
| `G` | suelo / area (reticula) | `Targets & TARGET_FLAG_DEST_LOCATION` :359 | opcional | ver §3 |
| `A` | amistoso con objetivo | `NeedsExplicitUnitTarget()` :1065 **y** `IsPositive()` :1269 | **si**, amigo | luz circular hasta el segundo click |
| `H` | hostil con objetivo | `NeedsExplicitUnitTarget()` y no positivo | **si**, hostil | luz circular hasta el segundo click |
| `D` | sobre muerto (resucitar) | `IsRequiringDeadTarget()` :1254 o `IsAllowingDeadTarget()` :1259 | **si**, muerto | ver §4 |
| `T` | totem / objeto colocado | `Totem[0]` o `TotemCategory[0]` no nulo :396,:402 | no pide | como `S`: va al sitio del bot |
| `N` | sin objetivo (grito, aura, postura) | ninguna de las anteriores | no pide | se lanza ya |

Nada de esto es una lista de ids: son siete llamadas sobre el `SpellInfo` que
el servidor ya tiene cargado. **En el addon no hay ninguna tabla de hechizos.**

### Lo que el brief preguntaba, contestado uno a uno

| pregunta del brief | respuesta |
|---|---|
| **Target hostil obligatorio** — ¿el segundo click puede ir sobre un enemigo del mundo 3D? | **Si, y ya funciona.** `RTSMode:OnLeftClick` entrega el guid de lo que haya bajo el cursor a `Skills:AimAt`, sea amigo o enemigo. Lo unico que se anade es rechazar el guid que no case con el tipo (`A` sobre un lobo se avisa y no se manda) |
| **Target de suelo / area** | Ver §3. **No hace falta click en el terreno**: apuntando a una unidad, el hechizo cae en el sitio de esa unidad |
| **Autotarget inteligente** | Es el tipo `N` y **ya esta**: `CastAs` con guid vacio usa el objetivo que el bot ya tenga, y si no tiene ninguno se lanza sobre si mismo (`RtsCommandMode.cpp:143-149`) |
| **Solo sobre uno mismo** | Tipo `S`. Se tratan como "sin target", que es justo lo que el brief proponia |
| **Canalizados** | Ver §5. **No se interrumpe nada**: se espera |
| **Toggles / auras / posturas** | Ver §6. **No se encolan como lanzamiento**, se mandan igual y son idempotentes |
| **Totems y objetos colocados** | Tipo `T`. No requieren posicion en este camino: playerbots los pone donde esta el bot |
| **Disipar / purgar** | Tipo `A` o `H` segun a quien. **No se valida el debuff antes de encolar** — ver §7 |
| **Resucitar** | Tipo `D`. Ver §4 |
| **Consumibles y objetos** | **Fuera de esta barra.** Ver §8 |
| **Hechizos con reagentes** | Ver §9 |

---

## 3. LOS DE SUELO NO NECESITAN UN CLICK EN EL TERRENO

Es el hallazgo que mas simplifica el brief, y sale de leer
`PlayerbotAI::CastSpell` (`Bot/PlayerbotAI.cpp`):

```cpp
else if (spellInfo->Targets & TARGET_FLAG_DEST_LOCATION)
{
    targets.SetDst(*target);        // <-- el destino ES la posicion del objetivo
}
```

O sea: **pasarle una UNIDAD a un hechizo de area lo deja caer donde esta esa
unidad.** Lluvia de fuego sobre el lobo es "apunta al lobo". No hace falta ni
reticula, ni raycast al terreno, ni un gesto nuevo.

Y para el caso en que se quiera un punto pelado del suelo, **el overload existe
ya**: `PlayerbotAI.h:520`, `CastSpell(uint32 spellId, float x, float y, float z,
Item*)`. El addon ya sabe sacar un punto del suelo (`Markers:CursorGroundPoint`,
`GROUNDAT`), asi que el dia que se quiera es un verbo mas, no una maquina nueva.

**Decision: los `G` se comportan como `H`** — piden segundo click, y el segundo
click puede ser una unidad (cae encima) o, si no hay nada, el suelo. Es un solo
gesto para el jugador y dos llamadas distintas por debajo.

---

## 4. RESUCITAR: EL UNICO QUE NO SE ENCOLA

`IsRequiringDeadTarget()` es `SPELL_ATTR3_ONLY_ON_GHOSTS`. Un resucitar exige
objetivo muerto y, fuera de combate, tiene tiempo de lanzamiento largo.

**Decision: se manda y no se reintenta.** Un resucitar que se queda en cola
treinta segundos y sale solo cuando el muerto ya se levanto es peor que uno que
falla y lo dice: el jugador se queda mirando a un sanador que no hace nada
mientras cree que la orden esta dada. Y ya hay un boton de "Revivir" en la
rejilla 4x4 para el caso general.

---

## 5. CANALIZADOS: SE ESPERA, NO SE INTERRUMPE

El brief pregunta si un canalizado se corta para meter el hechizo en cola.
**No.** Dos razones, y la segunda es la que decide:

1. Cortar un canalizado tira el hechizo *y* su recurso. Un jugador que pincha
   una curacion mientras el sanador canaliza no ha dicho "cancela lo que estas
   haciendo".
2. **Es lo que la cola existe para hacer.** El brief dice, literalmente: *"Queda
   en cola hasta que el personaje tenga un tick/hueco disponible. Se lanza en
   cuanto termine el casteo actual."* Esperar ES el comportamiento pedido; la
   pregunta de §5.1 se contesta con la especificacion de §5.

`Unit::IsNonMeleeSpellCast` / `HasUnitState(UNIT_STATE_CASTING)` es la
comprobacion, y no hace falta ni eso: `Spell::prepare` devuelve
`SPELL_FAILED_SPELL_IN_PROGRESS` y la cola reintenta.

---

## 6. TOGGLES, AURAS Y POSTURAS: NO SON UN CASO ESPECIAL

Un sello, un aura de paladin o una postura de guerrero son hechizos normales que
aplican un aura al lanzarse. Lanzarlos otra vez estando puestos no falla de una
forma que estorbe. **No se distingue "activar" de "desactivar"**: se manda el
hechizo y ya.

Lo que si hace falta es **no encolarlos con reintento largo**, porque un aura que
no sale no es una emergencia. Van con el plazo corto (§10).

---

## 7. DISIPAR: NO SE VALIDA EL DEBUFF ANTES DE ENCOLAR

Tentador y equivocado. Para saber si un disipar es valido hay que mirar los
debuffs del objetivo, cruzarlos con la mascara de disipacion del hechizo y con
`DispelMask` — y esa comprobacion **ya la hace el nucleo**, en `Spell::CheckCast`,
que es donde `prepare` acaba.

Duplicarla aqui seria escribir una segunda version de una regla del juego que ya
existe, que es como se acaba teniendo dos respuestas distintas a la misma
pregunta. Se manda, el nucleo dice que no, y la cola trata ese `no` como
permanente (§10).

---

## 8. CONSUMIBLES Y OBJETOS: FUERA DE ESTA BARRA, DE MOMENTO

Un objeto no es un hechizo: se usa con `Player::CastItemUseSpell` o el opcode de
usar objeto, y ademas **se gasta**. La barra de acciones de un bot puede tener
objetos, y `GetActionInfo` los devuelve como `"item"`, no como `"spell"`.

**Decision: la lista de huecos solo admite `type == "spell"`.** Un objeto en la
barra del bot simplemente no aparece como candidato.

El motivo de no hacerlo hoy no es tecnico sino de alcance: un objeto que se gasta
necesita cantidad, cooldown compartido por categoria y un aviso cuando se acaba —
y nada de eso es la barra de hechizos. Queda escrito para que el dia que se pida
no se redescubra que "es que los objetos no son hechizos".

**La ventana de bolsas (`Bags.lua`) ya deja mover objetos entre personajes**, que
es la mitad util del caso.

---

## 9. REAGENTES: SE MANDA IGUAL

`SpellInfo::Reagent[]` / `ReagentCount[]` (`SpellInfo.h:397`) estan ahi y se
podrian mirar. No se hace: **el nucleo ya rechaza el lanzamiento con
`SPELL_FAILED_ITEM_NOT_READY` / `SPELL_FAILED_REAGENTS`**, y esa negativa es la
buena — la nuestra tendria que reimplementar la cuenta de la mochila.

Al llegar el turno y faltar el reagente, es un fallo **permanente** (§10): se
descarta y se dice. Un reintento de treinta segundos no va a hacer aparecer un
runa de invocacion.

---

## 10. LA COLA: QUE ES TRANSITORIO Y QUE ES DEFINITIVO

Esta es la parte que decide si la cola sirve o estorba. Un fallo transitorio se
reintenta; uno definitivo se descarta **y se dice**, porque una orden que
desaparece sin mensaje es indistinguible de una que nunca se dio — que es el
modo de fallo que este proyecto persigue desde la etapa 5i.

### Transitorios — la cola reintenta

| causa | de donde sale | por que pasa |
|---|---|---|
| el bot esta sentado | `!bot->IsStandState()` → `return false` con retraso, `PlayerbotAI.cpp` | **el primer click sobre un bot que come SIEMPRE falla.** Solo esto ya justifica la cola |
| el bot se mueve y el hechizo tiene casteo | `bot->isMoving() && spell->GetCastTime()` | recolocarse en formacion |
| ya esta lanzando o canalizando | `SPELL_FAILED_SPELL_IN_PROGRESS` | §5 |
| enfriamiento, global incluido | `SPELL_FAILED_NOT_READY` | lo normal |
| fuera de alcance | `SPELL_FAILED_OUT_OF_RANGE` | el objetivo se mueve |
| sin linea de vision | `SPELL_FAILED_LINE_OF_SIGHT` | idem |
| sin recurso | `SPELL_FAILED_NO_POWER` | se regenera |
| el bot vuela | `bot->IsFlying()` | montura |

### Definitivos — se descarta y se avisa

| causa | por que no se reintenta |
|---|---|
| el bot no conoce el hechizo | `bot->HasSpell()` en `CastAs`. No va a aprenderlo esperando |
| el objetivo ya no existe o no se ve | un guid que no resuelve. Esperar a que vuelva seria lanzar sobre otra cosa mas tarde |
| el objetivo murio y el hechizo no lo admite | curar a un cadaver no se arregla con tiempo |
| falta reagente | §9 |
| disipar sin nada que disipar | §7 |
| **el jugador cambio de seleccion** | ver abajo |

### Cambiar de seleccion NO cancela la cola

El brief lo pone como pregunta abierta. **La cola es del PERSONAJE, no de la
seleccion.** Encolar una curacion en la sanadora y luego coger al tanque para
mandarle otra cosa es exactamente el gesto de RTS que el brief describe en §4.2
(*"tu esto, tu esto, tu esto"*): si cambiar de seleccion vaciara la cola, ese
gesto seria imposible por construccion.

Lo que si la cancela es **encolar otra cosa en el mismo personaje**: una cola por
personaje, de un solo hueco. Sin esto, cuatro clicks nerviosos son cuatro
hechizos saliendo seguidos diez segundos despues.

### Plazo maximo: dos, y por tipo

**8 segundos para los que piden objetivo** (`A`, `H`, `G`, `D`). Es algo mas que
el global (1,5 s) mas el casteo mas largo de la barra de un bot (~3 s) mas un
margen para recolocarse. Lo que estos esperan de verdad es que el objetivo vuelva
a estar a tiro, y eso tarda.

**3 segundos para los que no** (`S`, `N`, `T`: gritos, auras, posturas, totems).
Lo unico que estos pueden estar esperando es un enfriamiento, que se resuelve en
un par de segundos. Ocho seria tener el icono girando mucho despues de que la
respuesta ya se sepa.

### Y UNA COSA QUE LA COLA TIENE QUE **NO** HACER: ANCLAR AL BOT

`CastAs` llama a `StopMoving()` en cada intento, y hace falta -- moverse cancela
un casteo, y `passive` permite `follow` a proposito (§11.3). Pero reintentar cada
400 ms sobre un objetivo lejano pararia al bot cada 400 ms, y **entonces no
podria acercarse nunca**: la cola convertiria "espera a tenerlo a tiro" en
"quedate quieto para siempre".

Asi que estando FUERA DE ALCANCE no se intenta nada: se deja al bot moverse y se
vuelve a mirar al siguiente intento. Es la unica comprobacion que la cola hace
por su cuenta, y existe porque es la unica que cambia lo que la cola HACE en vez
de lo que dice.

Al vencer se **dice cual y por que**, con el ultimo motivo de fallo que dio el
nucleo. "La curacion no salio: fuera de alcance" es accionable; que no pase nada,
no.

---

## 11. TRES TRAMPAS QUE COSTARIAN UNA RONDA CADA UNA

Encontradas leyendo `PlayerbotAI::CastSpell` entero. Ninguna es teorica.

### 11.1 UN HECHIZO DE MASCOTA NO SE LANZA: ENCIENDE SU AUTOCAST

```cpp
Pet* pet = bot->GetPet();
if (pet && pet->HasSpell(spellId))
{
    ...
    pet->ToggleAutocast(spellInfo, !autocast);
    TellMaster(out);
    return true;              // <-- DEVUELVE EXITO
}
```

Con un cazador o un brujo, un hueco con un hechizo de la mascota **no lanza
nada**: alterna el autocast de la mascota, susurra al maestro y **devuelve
`true`**, o sea que la cola lo da por lanzado. El sintoma en pantalla seria "ese
boton no hace nada" y encima intermitente, porque alterna.

**Guarda: el servidor no ofrece en la lista de `BARS` ningun hechizo que la
mascota del bot conozca.** Se filtra donde se construye la lista, que es el unico
sitio donde da tiempo a saberlo.

### 11.2 LA SELECCION DEL BOT SOLO SE DEVUELVE SI EL LANZAMIENTO SALE

```cpp
ObjectGuid oldSel = bot->GetSelectedUnit() ? ... : ObjectGuid();
bot->SetSelection(target->GetGUID());
...
if (oldSel)
    bot->SetSelection(oldSel);     // solo se llega aqui si prepare() fue OK
```

Dos huecos, y los dos afectan al *"vuelve a su rotacion natural"* del brief:

- **si el lanzamiento FALLA**, se sale por el `return false` de arriba y el bot se
  queda seleccionando nuestro objetivo;
- **si el bot no tenia nada seleccionado**, `oldSel` esta vacio y no se restaura
  nunca.

Esto **corrige lo que `CLAUDE.md` dice de la etapa 5n** (*"`CastAs` con un guid
explicito no escribe la seleccion del bot"*). Si la escribe. En la practica se
nota poco porque la IA reelige objetivo en su siguiente vuelta, pero es la
diferencia entre "por defecto" y "casi siempre", y con la cola reintentando
varias veces el caso de fallo deja de ser raro.

**No se corrige desde mod-rts**: escribir la seleccion detras de playerbots es
exactamente la forma de error de la retencion de altura de camara — corregir cada
tick lo que otro escribe cada tick. Se deja escrito y se mira si molesta.

### 11.3 `passive` PERMITE `follow`, Y SEGUIR CANCELA UN CASTEO

Ya documentado en la etapa 5o y ya arreglado en `CastAs` (`bot->StopMoving()`
antes de lanzar). Se repite aqui porque **la cola vuelve a abrir el caso**: entre
un reintento y el siguiente el bot puede echar a andar otra vez. El `StopMoving`
tiene que correr en **cada intento**, no solo en el primero.

---

## 12. LOS OTROS PUNTOS ABIERTOS DEL BRIEF (§9)

### §9.1 — ¿"curar en focus" existe o hay que programarlo?

**Existe, y esta compilado desde mod-rts 0.15.0.** El verbo es
`PFOCUS <bot> <guid-hex>`, y sobre un objetivo amistoso hace
(`RtsCommandMode.cpp:402-437`):

```cpp
rts::bots::SetFocusHeal(bot, focus);                       // la lista
rts::bots::Change(bot, "+focus heal targets", COMBAT);     // la estrategia
```

Las dos mitades son de playerbots (`TargetValue.h:161`,
`StrategyContext.h:132`), o sea que el comportamiento *"la sanadora se dedica
exclusivamente a curar al tanque"* es de su IA y no una simulacion nuestra. Sobre
un objetivo hostil el mismo verbo hace `AttackBot`, que es pegajoso por
construccion.

**Falta el boton, no la funcion.** Es el candidato numero uno de los cuatro de
§4.1, tal como pide el brief (*"caso de uso prioritario"*).

### §9.2 — ¿caben 5 columnas x 4 slots?

**Si, holgado.** La sala mide `710 + 512*(grow-1)` de ancho por 344 de alto en
pixeles de dibujo. Con `grow 4`, que es lo que sale solo en 2560x1440 a pantalla
completa, son **2246 x 344**. Descontando la columna izquierda quedan ~1840 para
cinco columnas: **368 por personaje**, con los que cuatro huecos caben sin
apretar y seis tambien. Comprobado en `sim/hall_layout.py`, que ademas dice a
partir de que `grow` deja de caber.

### §9.4 — el formato de guardado

```lua
RTSCommandDB.hall = {
    ver   = 1,                        -- SELLO DE GENERACION, ver abajo
    who   = {
        ["Kirinah"] = {
            spells  = { 2050, 2060, nil, 596, 6,  },   -- huecos 1..6, con agujeros
            actions = { "focus", "hold", nil, "follow" },
        },
    },
}
```

Tres decisiones, cada una pagada ya una vez en este proyecto:

- **Por NOMBRE de personaje y no por guid**, porque es la clave que el jugador
  reconoce y la que usan `BARS` y `CAST`. El riesgo conocido (dos personajes con
  el mismo nombre tras un cambio) no aplica aqui: esto es configuracion, no
  identidad — lo peor que pasa es heredar los huecos de un homonimo.
- **`ver` es un sello de generacion, no un rango.** Es la leccion del
  `railCropGen` de la etapa 5o: comprobar que un valor guardado esta dentro de
  limites no basta cuando lo que cambia es **lo que el numero significa**. Si el
  reparto de huecos cambia, sube `ver` y lo viejo se tira.
- **Los agujeros se conservan.** Un hueco 3 vacio entre el 2 y el 4 es una
  decision del jugador, no un error de compactado.

Y lo de siempre: **se acota al LEER**, no solo al escribir
(`grow = 688`, `camHold`, `railCropGen` — tres veces ya). Un id de hechizo que
no resuelve con `GetSpellInfo` se descarta al cargar y se imprime.

---

## 13. LO QUE QUEDA SIN COMPROBAR

Dicho por delante, para que no se lea como cerrado:

- **El tipo `T` (totems) no se ha visto en juego.** La lectura de `Totem[]` es
  correcta, pero si un totem necesita un destino explicito que playerbots no le
  da, saldra como "no salio" y habra que mirarlo. Es un chaman, y en este grupo
  no hay ninguno ahora mismo.
- **`IsPositive()` se apoya en `AttributesCu`**, que el nucleo calcula al
  cargar y corrige a mano para casos raros. Es la fuente buena que hay, pero no
  es infalible: un hechizo mal clasificado saldria pidiendo el objetivo del
  color equivocado. Por eso el rechazo por tipo (§2) **avisa y no bloquea** —
  se dice "eso parece hostil" y se manda igual si insistes.
- **El plazo de 8 s es una estimacion razonada, no medida.** Se ajusta con un
  comando cuando se vea, igual que `grow` y `share`.
