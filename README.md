# RTS Command — copia de seguridad

Capa de control estilo RTS (Warcraft 3 / StarCraft) para un servidor privado de
World of Warcraft 3.3.5a con AzerothCore + mod-playerbots.

**Esto es una COPIA.** No se trabaja aquí. Las tres piezas viven cada una donde
tiene que vivir, y `sync.ps1` las trae a esta carpeta para poder subirlas juntas.

## Qué hay dentro

| Carpeta | Qué es | Dónde vive de verdad |
|---|---|---|
| `addon/` | Addon Lua: selección, órdenes, cámara, command card | `F:\Games\WOW WOTLK\Interface\AddOns\RTSCommand` |
| `rts-client-mod/` | `rts_core.dll` — coordenadas de mundo, raycast del cursor, cámara, círculos nativos | `C:\Server\rts-client-mod` |
| `mod-rts/` | Módulo de servidor: cámara poseída, despacho de órdenes, command mode | `C:\Server\azerothcore\modules\mod-rts` |
| `docs/` | `CLAUDE.md` (el documento de diseño) y las listas `PRUEBAS-N.txt` | `C:\Server` |
| `scripts/` | `.bat` de arranque | `C:\Server` |

Las tres se comunican así:

```
Cliente WoW  <->  worldserver (+ mod-rts)  <->  MySQL
     ^
     +-- addon RTSCommand   (UI, selección, órdenes)
     +-- rts_core.dll       (solo local: coordenadas, raycast, círculos)
```

## Actualizar la copia

```powershell
powershell -ExecutionPolicy Bypass -File .\sync.ps1
git add -A
git commit -m "backup"
git push
```

## Qué NO se sube, y por qué

- **`worldserver.conf`, `authserver.conf`, `dbimport.conf`** — llevan el usuario
  y la contraseña de MySQL en texto plano. Nunca entran aquí. La plantilla del
  módulo (`mod-rts/conf/mod_rts.conf.dist`) sí, porque solo trae ajustes de
  cámara.
- **`build/`, `dist/`, binarios, logs** — se regeneran compilando.
- **El fork de AzerothCore** — tiene su propio remoto
  (`mod-playerbots/azerothcore-wotlk`, rama `Playerbot`). Aquí solo va nuestro
  módulo.
- **`mysql-data/`** — son las bases de datos, no código.

## Para restaurar

Copia cada carpeta a su sitio (columna derecha de la tabla), y después:

- addon: recargar el cliente
- `mod-rts`: recompilar el target `worldserver` y copiar el binario a `dist`
- `rts-client-mod`: recompilar en **Win32** (`Wow.exe` es x86) e inyectar

`docs/CLAUDE.md` explica el porqué de cada decisión, incluidos los callejones
sin salida, que es la parte que más cuesta redescubrir.
