# RTS Command

Capa de control estilo RTS (Warcraft 3 / StarCraft) para un servidor privado de
World of Warcraft 3.3.5a con AzerothCore + mod-playerbots.

**Aquí se trabaja.** Esta carpeta es el original de las tres piezas del
proyecto. Lo que hay en el WoW y dentro de AzerothCore son copias desplegadas.

## Qué hay dentro

| Carpeta | Qué es | Se despliega a |
|---|---|---|
| `addon/` | Addon Lua: selección, órdenes, cámara, command card | `D:\GAMES\WOW WOTLK\Interface\AddOns\RTSCommand` |
| `mod-rts/` | Módulo de servidor: cámara poseída, despacho de órdenes, command mode | `C:\Server\azerothcore\modules\mod-rts` |
| `rts-client-mod/` | `rts_core.dll` — coordenadas de mundo, raycast del cursor, cámara, círculos nativos | no se despliega: se compila aquí mismo |
| `scripts/` | `.bat` de arranque | copia manual desde `C:\Server` |

Las tres piezas se comunican así:

```
Cliente WoW  <->  worldserver (+ mod-rts)  <->  MySQL
     ^
     +-- addon RTSCommand   (UI, selección, órdenes)
     +-- rts_core.dll       (solo local: coordenadas, raycast, círculos)
```

## Desplegar

Un solo sentido, siempre: de aquí hacia fuera. Nunca al revés.

| Botón | Qué hace | Después hay que |
|---|---|---|
| `C:\Server\rts-tools\Deploy_Addon.bat` | `addon/` → carpeta del WoW | `/reload` en el juego |
| `C:\Server\rts-tools\Deploy_Mod.bat` | `mod-rts/` → AzerothCore | recompilar `worldserver` |

El DLL no tiene botón porque no se mueve de sitio:

```powershell
cmake --build C:\Server\rts-project\rts-client-mod\build --config Release
```

Y se inyecta con `C:\Server\rts-tools\Jugar.bat`.

## Por qué un solo sentido

Antes había un `sync.ps1` que recogía las tres piezas desde donde vivían, y esta
carpeta era solo una copia de seguridad. Existían los dos sentidos, y eso
significaba que en cualquier momento no estaba claro cuál era la versión buena.

El 16/08/2026 costó una tarde: el addon se editó hasta las 22:06, el último
`sync` había sido a las 19:04, y al mudar el servidor a otro ordenador se
instaló la copia de las 19:04. Faltaban 247 líneas de `RTSMode.lua`, entre ellas
`CameraTurned()` — justo la función que hace funcionar la selección por caja. El
síntoma fue "lo nuevo no funciona en el ordenador nuevo", y no había ni un error
que lo delatara.

Con un solo original y un solo sentido, ese fallo no se puede dar: si el juego
va viejo, es que falta desplegar, y se arregla con un botón.

## Qué NO se sube, y por qué

- **`worldserver.conf`, `authserver.conf`, `dbimport.conf`** — llevan el usuario
  y la contraseña de MySQL en texto plano. Nunca entran aquí. La plantilla del
  módulo (`mod-rts/conf/mod_rts.conf.dist`) sí, porque solo trae ajustes de
  cámara.
- **`build/`, binarios, logs** — se regeneran compilando.
- **El fork de AzerothCore** — tiene su propio remoto
  (`mod-playerbots/azerothcore-wotlk`, rama `Playerbot`). Aquí solo va nuestro
  módulo.
- **`mysql-data/`** — son las bases de datos, no código.

## En otro ordenador

```
git pull
```

y después los dos botones de deploy, más compilar el DLL y el `worldserver`.

El porqué de cada decisión, callejones sin salida incluidos, está en los
comentarios del fichero que la implementa. `docs/` existió y se borró a propósito
(`4c2b163`): unas notas que ya no coinciden con el binario son un sitio cómodo
donde confirmar una idea equivocada sin abrir el código.
