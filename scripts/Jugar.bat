@echo off
title Jugar - WoW + RTS
color 0B

REM Abre el juego y le inyecta rts_core.dll cuando ya esta cargado,
REM para no tener que ejecutar el inyector a mano cada vez.

set WOW=F:\Games\WOW WOTLK\Wow.exe
set INJECTOR=C:\Server\rts-client-mod\build\bin\injector.exe

echo ============================================
echo   ABRIENDO EL JUEGO
echo ============================================
echo.

if not exist "%WOW%" (
    echo [ERROR] No encuentro %WOW%
    pause
    exit /b 1
)

REM Si ya esta abierto no lo abrimos otra vez; solo inyectamos.
tasklist /FI "IMAGENAME eq Wow.exe" 2>nul | find /I "Wow.exe" >nul
if errorlevel 1 (
    echo [1/2] Abriendo World of Warcraft...
    start "" /D "F:\Games\WOW WOTLK" "%WOW%"
) else (
    echo [1/2] World of Warcraft ya estaba abierto.
)

REM El inyector necesita que el cliente haya terminado de arrancar.
REM 15 segundos cubre la pantalla de inicio sin llegar al login.
echo       Esperando a que cargue...
timeout /t 15 /nobreak >nul

if not exist "%INJECTOR%" (
    echo [ERROR] No encuentro %INJECTOR% -- hay que compilar rts_core.
    pause
    exit /b 1
)

echo [2/2] Inyectando rts_core.dll...
"%INJECTOR%"

echo.
echo ============================================
echo  Listo. En el juego: /rts native
echo  deberia decir la version de rts_core.
echo ============================================
echo.
timeout /t 6 /nobreak >nul
