@echo off
title Actualizar el mundo del juego (worldserver)
color 0E

REM Reinicia SOLO el worldserver con la version recien compilada.
REM MySQL y el authserver siguen encendidos, asi que no hace falta
REM cerrar y volver a abrir todo el servidor.

set ORIGEN=C:\Server\build\bin\Release\worldserver.exe
set DESTINO=C:\Server\dist\worldserver.exe

echo ============================================
echo   ACTUALIZANDO EL MUNDO DEL JUEGO
echo ============================================
echo.

if not exist "%ORIGEN%" (
    echo [ERROR] No existe %ORIGEN%
    echo Hay que compilar primero.
    echo.
    pause
    exit /b 1
)

echo [1/3] Cerrando el mundo del juego...
REM /F es obligatorio: sin el, worldserver ignora la peticion y no se cierra.
taskkill /F /IM worldserver.exe /T >nul 2>&1

echo [2/3] Copiando la version nueva...
REM Windows tarda un momento en soltar el archivo despues de cerrar el proceso.
REM Antes esto era una espera fija de 3 segundos y, cuando no bastaba, la copia
REM fallaba en silencio: el servidor volvia a arrancar con la version VIEJA y
REM parecia que ninguna correccion habia funcionado. Ahora se reintenta.
set INTENTOS=0
:reintentar
copy /Y "%ORIGEN%" "%DESTINO%" >nul 2>&1
if not errorlevel 1 goto copiado
set /a INTENTOS+=1
if %INTENTOS% GEQ 15 (
    echo.
    echo [ERROR] No se pudo copiar despues de 15 intentos.
    echo         Sigue abierto el mundo del juego?
    echo.
    pause
    exit /b 1
)
timeout /t 1 /nobreak >nul
goto reintentar

:copiado
echo       Copiado correctamente.

echo [3/3] Arrancando el mundo del juego...
start "3 - Mundo del juego (worldserver)" cmd /k "cd /d C:\Server\dist && worldserver.exe"

echo.
echo ============================================
echo  Listo. Comprueba en el juego con:  /rts version
echo ============================================
echo.
timeout /t 6 /nobreak >nul
