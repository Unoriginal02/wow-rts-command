# Mudar el servidor a otro ordenador

A mano, en orden. Los scripts que hacian esto (`Mudanza_1_Copiar.ps1`,
`Mudanza_2_Instalar.ps1`, `Instalar_En_PC_Nuevo.bat`) se borraron el 2026-08-17:
la mudanza se hace una vez cada mucho, y mantener 22 KB de automatizacion
correcta entre mudanza y mudanza costaba mas que copiar carpetas a mano. Lo que
si merecia la pena guardar era el **porque** de cada paso, y eso es este fichero.

---

## 0. Antes de nada: la red de seguridad

`C:\Server\rts-project` es el original de las tres piezas (addon, `mod-rts`,
`rts-client-mod`) y tiene remoto en GitHub (`Unoriginal02/wow-rts-command`).
Subelo antes de mover nada. Si el disco externo se corrompe a mitad, esto es lo
unico que no se puede volver a escribir:

```powershell
git -C C:\Server\rts-project add -A
git -C C:\Server\rts-project commit -m "Antes de la mudanza"
git -C C:\Server\rts-project push
```

Dos cosas **no** viajan en GitHub y solo estan en el disco externo:

- Los `.conf` del servidor — llevan la contrasena de MySQL en claro, por eso
  estan en `.gitignore`.
- `C:\Server\rts-tools` — los .bat y .ps1 estan fuera del repo a proposito.

---

## 1. En el PC viejo: que copiar

Con el servidor **parado** (ni `mysqld`, ni `worldserver`, ni `authserver`
vivos — copiar `mysql-data` en caliente da una base corrupta).

Necesitas un disco de **64 GB o mas**. Copia estas carpetas tal cual:

| Que | Tamano | Por que viaja en vez de reinstalarse |
|---|---:|---|
| `C:\Server\dist\data` | 3,1 GB | Los `mmaps` tardan **horas** en generarse |
| `C:\Server\mysql-data` | 2,5 GB | Personajes, cuentas, guilds. Irreemplazable |
| `C:\Server\build` | 4,4 GB | Ahorra 1–2 h de primera compilacion |
| `C:\Server\azerothcore` | 0,9 GB | Lleva `modules\mod-rts` ya desplegado |
| `C:\Server\rts-project` | pequeno | El original. Tambien esta en GitHub |
| `C:\Server\rts-tools` | pequeno | Los botones. **No** esta en GitHub |
| `C:\Server\dist` (resto) | — | Binarios y los `.conf` con la contrasena |
| `C:\Program Files\MySQL\MySQL Server 8.4` | 0,6 GB | La version **exacta** que escribio `mysql-data` |
| `F:\Games\WOW WOTLK` | 19,5 GB | El `Wow.exe` exacto contra el que estan los offsets |
| `%USERPROFILE%\.claude\projects\C--Server` | pequeno | Memoria de Claude Code |

`build\` es opcional: te ahorra 4,4 GB de copia y pagas 1–2 h compilando.

Usa `robocopy /MIR` en vez de arrastrar con el raton: se reanuda si lo cortas y
no se atraganta con rutas largas.

```powershell
robocopy C:\Server E:\MudanzaWoW\Server /MIR /R:2 /W:2 /MT:16
```

---

## 2. En el PC nuevo: que instalar

Copia `E:\MudanzaWoW\Server` a `C:\Server` y luego lanza:

```
C:\Server\rts-tools\Instalar_Requisitos.bat
```

Pide permisos de administrador solo y hace todo lo de este apartado. Es
repetible: comprueba cada cosa y se salta lo que ya este. Si falla algo, dice
exactamente que bajar y donde ponerlo, lo arreglas y lo vuelves a lanzar.

Lo que hace, por si hay que hacerlo a mano:

**Programas** (`winget install --id <id> -e`):

| Programa | id de winget |
|---|---|
| Visual Studio 2022 Community | `Microsoft.VisualStudio.2022.Community` |
| Git para Windows | `Git.Git` |
| CMake | `Kitware.CMake` |
| Python 3.12 (para `check_addon.py`) | `Python.Python.3.12` |
| 7-Zip | `7zip.7zip` |

Visual Studio necesita la carga **«Desarrollo para el escritorio con C++»**, y
dentro de ella los **dos** compiladores: el servidor es x64 y `rts_core.dll` es
x86 obligatoriamente, porque `Wow.exe` lo es.

**Boost 1.81.0 y OpenSSL 3.6.3.** Antes viajaban como `.exe` dentro de
`C:\Server`; se borraron el 2026-08-17 porque son 437 MB de descarga gratuita.
Bajalos otra vez — **las versiones no son negociables**, una version equivocada
de cualquiera de las dos es la causa numero uno de que la primera compilacion de
AzerothCore falle:

- `boost_1_81_0-msvc-14.3-64.exe` — binarios de Boost en SourceForge,
  `boost-binaries/1.81.0`. Instalar en `C:\local\boost_1_81_0`.
- `Win64OpenSSL-3_6_3.exe` — slproweb.com, la version **completa**, no la
  «Light». Instalar en `C:\Program Files\OpenSSL-Win64`, con las DLL en el
  directorio de binarios de OpenSSL.

**`BOOST_ROOT` a nivel de MAQUINA**, no de usuario:

```powershell
[Environment]::SetEnvironmentVariable("BOOST_ROOT", "C:\local\boost_1_81_0", "Machine")
```

En el PC viejo estaba solo a nivel de usuario y CMake no lo veia al compilar
desde otro contexto. A nivel de maquina funciona en los dos casos.

**Exclusiones de Defender** para `C:\Server`, `C:\local` y la carpeta del
cliente. Ademas de casi partir por la mitad el tiempo de compilacion, evita que
el heuristico se coma el inyector:

```powershell
Add-MpPreference -ExclusionPath "C:\Server"
```

**Reinicia** cuando termines. `BOOST_ROOT` y el `PATH` no cuentan hasta entonces.

---

## 3. Las rutas tienen que ser las mismas

Esto no es mania: hay rutas absolutas metidas en `CMakeCache.txt`, en los `.bat`
de `rts-tools` y en el propio `worldserver.conf`.

| Ruta | Quien la exige |
|---|---|
| `C:\Server` | Todo |
| `C:\local\boost_1_81_0` | `CMakeCache.txt` |
| `C:\Program Files\MySQL\MySQL Server 8.4` | `Iniciar_Servidor.bat`, `CMakeCache.txt` |
| `F:\Games\WOW WOTLK` | `Jugar.bat`, `Deploy_Addon.bat` |

**Si el PC nuevo no tiene unidad F:**, pon el cliente donde puedas y hay que
cambiar la ruta en `rts-tools\Jugar.bat` y en `rts-tools\Deploy_Addon.bat`.
Dimelo y te los edito — es un `set` en cada uno.

---

## 4. La base de datos no hay que montarla

`mysql-data` es el directorio de datos entero, asi que **las bases, el usuario
`acore`, su contrasena y todos los personajes vienen dentro**. En el PC nuevo no
hay que crear bases, ni usuarios, ni importar el mundo, ni tocar los `.conf`.

Por eso MySQL se **copia** en vez de instalarse: tiene que ser **8.4.x**. Una 8.0
no abre ese directorio, y una 9.x lo migraria sin vuelta atras. Comprueba la
version antes de arrancar nada:

```powershell
& "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysqld.exe" --version
```

Tampoco hay servicio de Windows que registrar — `Iniciar_Servidor.bat` lanza
`mysqld.exe` a mano con `--datadir`, y no existe ningun `my.ini` que pueda
contradecirlo.

---

## 5. Primera compilacion en el PC nuevo

Con `build\` copiado, deberia bastar con recompilar lo que haga falta:

```powershell
cmake --build C:\Server\build --config Release --target worldserver -- /m
```

Si CMake protesta (version distinta del toolset de MSVC, o de CMake), borra
`C:\Server\build` y configura de cero — son 1–2 horas, no un problema:

```powershell
cmake -S C:\Server\azerothcore -B C:\Server\build -G "Visual Studio 17 2022" -A x64 `
      -DCMAKE_INSTALL_PREFIX=C:/Server/dist -DTOOLS_BUILD=all -DWITH_WARNINGS=OFF `
      -DBOOST_ROOT=C:/local/boost_1_81_0
cmake --build C:\Server\build --config Release --target worldserver -- /m
```

El DLL del cliente es un proyecto aparte y **`-A Win32` no es opcional**:

```powershell
cmake -S C:\Server\rts-project\rts-client-mod -B C:\Server\rts-project\rts-client-mod\build -A Win32
cmake --build C:\Server\rts-project\rts-client-mod\build --config Release
```

---

## 6. Comprobacion, en este orden

Cada paso deja el siguiente en pie, asi que un fallo dice exactamente donde
mirar:

1. `rts-tools\Iniciar_Servidor.bat` → `worldserver` llega a su prompt. Si falla,
   es MySQL o los `.conf`.
2. Login con tu cuenta de siempre, personaje donde lo dejaste → `mysql-data`
   viajo entero.
3. `.playerbots bot add <nombre>` → el bot sigue y responde → `mmaps` bien.
4. `rts-tools\Jugar.bat` + `/rts native` → dice la version de `rts_core`. Si no,
   es Smart App Control o el MD5 del cliente.
5. `python C:\Server\rts-tools\check_addon.py` → sin errores.

El `Wow.exe` tiene que seguir siendo el mismo binario, porque los offsets de
`rts_core` estan verificados contra el:

```powershell
(Get-FileHash "F:\Games\WOW WOTLK\Wow.exe" -Algorithm MD5).Hash
# 45892BDEDD0AD70AED4CCD22D9FB5984
```

---

## 7. Lo que hay que hacer a mano si o si

- **Smart App Control.** Si esta activo en el PC nuevo, bloquea `rts_core.dll`
  por no estar firmado — y firmarlo no sirve, esto ya se probo. Se apaga a mano
  en Seguridad de Windows, y es **de un solo sentido**: para volver a activarlo
  hay que reinstalar Windows.
- **Claude Code.** Instalalo aparte. La memoria del proyecto se restaura en
  `%USERPROFILE%\.claude\projects\C--Server`; si el usuario de Windows se llama
  distinto, la ruta cambia sola y no pasa nada.
- **El disco duro.** `C:\Server` mas el cliente son ~31 GB en destino.
