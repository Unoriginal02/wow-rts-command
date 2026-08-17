# Mudar el servidor a otro ordenador

Todo lo que hay que hacer, en orden. Dos scripts hacen el trabajo:

| Script | Donde se ejecuta | Que hace |
|---|---|---|
| `Mudanza_1_Copiar.ps1` | PC **viejo** | Vuelca al disco externo lo que no se puede reinstalar |
| `Mudanza_2_Instalar.ps1` | PC **nuevo**, como administrador | Restaura eso e instala todos los programas |

---

## 0. Antes de nada: la red de seguridad

`mod-rts` y el addon `RTSCommand` **no estan en ningun repositorio propio** — son
ficheros sueltos dentro de un arbol ajeno. Lo unico que los respalda es
`C:\Server\rts-project`, que es una copia de los tres trozos del proyecto y si
tiene remoto en GitHub (`Unoriginal02/wow-rts-command`).

Actualizalo y subelo antes de mover nada. Si el disco externo se corrompe a
mitad, esto es lo unico que no se puede volver a escribir:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Server\rts-project\sync.ps1
git -C C:\Server\rts-project add -A
git -C C:\Server\rts-project commit -m "Antes de la mudanza"
git -C C:\Server\rts-project push
```

Ojo: `sync.ps1` **no** copia los `.conf`, porque llevan la contrasena de MySQL en
claro. Esos solo viajan en el disco externo.

---

## 1. En el PC viejo

Con el servidor parado (el script aborta si encuentra `mysqld`, `worldserver` o
`authserver` vivos):

```powershell
powershell -ExecutionPolicy Bypass -File C:\Server\rts-tools\Mudanza_1_Copiar.ps1 -Destino E:\MudanzaWoW
```

Necesitas un disco de **64 GB o mas**:

| Que | Tamano | Por que viaja en vez de reinstalarse |
|---|---:|---|
| `C:\Server\dist\data` | 3,1 GB | Los `mmaps` tardan **horas** en generarse |
| `C:\Server\mysql-data` | 2,5 GB | Personajes, cuentas, guilds. Irreemplazable |
| `C:\Server\build` | 4,4 GB | Ahorra 1–2 h de primera compilacion |
| `C:\Server\azerothcore` | 0,9 GB | Lleva `mod-rts`, que no esta en su propio git |
| MySQL 8.4.9 | 0,6 GB | La version **exacta** que escribio `mysql-data` |
| Cliente WoW | 19,5 GB | El `Wow.exe` exacto contra el que estan los offsets |

Opciones: `-SinBuild` (te ahorra 4,4 GB y pagas 1–2 h compilando) y `-SinCliente`
(si mueves el cliente por tu cuenta).

---

## 2. En el PC nuevo

Copia `E:\MudanzaWoW\Server` a `C:\Server`, abre PowerShell **como
administrador** y:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Server\rts-tools\Mudanza_2_Instalar.ps1 -Origen E:\MudanzaWoW
```

Restaura lo demas (MySQL, cliente, memoria de Claude Code) e instala:

- **Visual Studio 2022 Community** + carga «Desarrollo para el escritorio con
  C++». Necesitas los **dos** compiladores: el servidor es x64 y `rts_core.dll`
  es x86 obligatoriamente, porque `Wow.exe` lo es.
- **Git**, **CMake**, **Python 3.12** (para `check_addon.py`), **7-Zip**
- **Boost 1.81.0** en `C:\local\boost_1_81_0` + `BOOST_ROOT`
- **OpenSSL 3.6.3** en `C:\Program Files\OpenSSL-Win64`
- Exclusiones de Defender para `C:\Server`, `C:\local` y el cliente

Boost y OpenSSL se instalan desde los `.exe` que ya viven dentro de `C:\Server`,
**no** desde la web: la version equivocada de una de las dos es la causa numero
uno de que la primera compilacion de AzerothCore falle, y estas son las que ya
funcionan.

Cuando termine, **reinicia** — `BOOST_ROOT` y el `PATH` no cuentan hasta
entonces. Es repetible: si algo falla, vuelve a lanzarlo y los pasos ya hechos se
saltan solos.

---

## 3. Las rutas tienen que ser las mismas

Esto no es manía: hay rutas absolutas metidas en `CMakeCache.txt`, en los `.bat`,
en `sync.ps1` y en el propio `worldserver.conf`.

| Ruta | Quien la exige |
|---|---|
| `C:\Server` | Todo |
| `C:\local\boost_1_81_0` | `CMakeCache.txt` |
| `C:\Program Files\MySQL\MySQL Server 8.4` | `Iniciar_Servidor.bat`, `CMakeCache.txt` |
| `F:\Games\WOW WOTLK` | `Jugar.bat`, `sync.ps1` |

**Si el PC nuevo no tiene unidad F:**, pon el cliente donde puedas, pasa
`-ClienteDestino "D:\Juegos\WOW WOTLK"` al script 2, y luego cambia la ruta en
`Jugar.bat` y en `rts-project\sync.ps1`. Dimelo y te los edito.

---

## 4. La base de datos no hay que montarla

`mysql-data` es el directorio de datos entero, asi que **las bases, el usuario
`acore`, su contrasena y todos los personajes vienen dentro**. En el PC nuevo no
hay que crear bases, ni usuarios, ni importar el mundo, ni tocar los `.conf`.

Por eso MySQL se copia en vez de instalarse: tiene que ser **8.4.x**. Una 8.0 no
abre ese directorio, y una 9.x lo migraria sin vuelta atras. El script comprueba
la version y avisa. Tampoco hay servicio de Windows que registrar —
`Iniciar_Servidor.bat` lanza `mysqld.exe` a mano con `--datadir`, y no existe
ningun `my.ini` que pueda contradecirlo.

---

## 5. Primera compilacion en el PC nuevo

Con `build\` copiado, deberia bastar con recompilar lo que haga falta:

```powershell
cmake --build C:\Server\build --config Release --target worldserver -- /m
```

Si CMake protesta (versión distinta del toolset de MSVC, o de CMake), borra
`C:\Server\build` y configura de cero — son 1–2 horas, no un problema:

```powershell
cmake -S C:\Server\azerothcore -B C:\Server\build -G "Visual Studio 17 2022" -A x64 `
      -DCMAKE_INSTALL_PREFIX=C:/Server/dist -DTOOLS_BUILD=all -DWITH_WARNINGS=OFF `
      -DBOOST_ROOT=C:/local/boost_1_81_0
cmake --build C:\Server\build --config Release --target worldserver -- /m
```

El DLL del cliente es un proyecto aparte y **`-A Win32` no es opcional**:

```powershell
cmake -S C:\Server\rts-client-mod -B C:\Server\rts-client-mod\build -A Win32
cmake --build C:\Server\rts-client-mod\build --config Release
```

---

## 6. Comprobacion, en este orden

Cada paso deja el siguiente en pie, asi que un fallo dice exactamente donde
mirar:

1. `Iniciar_Servidor.bat` → `worldserver` llega a su prompt. Si falla, es MySQL
   o los `.conf`.
2. Login con tu cuenta de siempre, personaje donde lo dejaste → `mysql-data`
   viajo entero.
3. `.playerbots bot add <nombre>` → el bot sigue y responde → `mmaps` bien.
4. `Jugar.bat` + `/rts native` → dice la version de `rts_core`. Si no, es Smart
   App Control o el MD5 del cliente.
5. `python C:\Server\rts-tools\check_addon.py` → sin errores.

---

## 7. Lo que el script no puede hacer por ti

- **Smart App Control.** Si esta activo en el PC nuevo, bloquea `rts_core.dll`
  por no estar firmado — y firmarlo no sirve, esto ya se probo. Se apaga a mano
  en Seguridad de Windows, y es **de un solo sentido**: para volver a activarlo
  hay que reinstalar Windows. El script detecta el estado y avisa.
- **Claude Code.** Instalalo aparte en el PC nuevo. La memoria del proyecto se
  restaura en `%USERPROFILE%\.claude\projects\C--Server`; si el usuario de
  Windows se llama distinto, la ruta cambia sola y no pasa nada.
- **El disco duro.** `C:\Server` mas el cliente son ~31 GB en destino.
