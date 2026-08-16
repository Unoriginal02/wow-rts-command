@echo off
title Panel de arranque - Servidor WoW
color 0A

echo ============================================
echo   INICIANDO EL SERVIDOR DE WORLD OF WARCRAFT
echo ============================================
echo.

echo [1/3] Iniciando la base de datos (MySQL)...
start "1 - Base de datos (MySQL)" cmd /k "cd /d "C:\Program Files\MySQL\MySQL Server 8.4\bin" && mysqld.exe --datadir=C:/Server/mysql-data --port=3306 --console"
timeout /t 8 /nobreak >nul

echo [2/3] Iniciando el servidor de inicio de sesion (authserver)...
start "2 - Inicio de sesion (authserver)" cmd /k "cd /d C:\Server\dist && authserver.exe"
timeout /t 5 /nobreak >nul

REM Trae la compilacion mas reciente antes de arrancar.
REM Sin esto, un reinicio normal revive la version vieja de worldserver.exe
REM y parece que ninguna correccion ha funcionado.
set NUEVO=C:\Server\build\bin\Release\worldserver.exe
if exist "%NUEVO%" (
    copy /Y "%NUEVO%" "C:\Server\dist\worldserver.exe" >nul 2>&1
    if errorlevel 1 (
        echo    [AVISO] No se pudo copiar la version nueva. Sigue la anterior.
    ) else (
        echo    worldserver.exe actualizado desde build.
    )
)

echo [3/3] Iniciando el mundo del juego (worldserver)...
start "3 - Mundo del juego (worldserver)" cmd /k "cd /d C:\Server\dist && worldserver.exe"
timeout /t 5 /nobreak >nul

echo.
echo ============================================
echo  Listo. Se han abierto 3 ventanas negras:
echo    1 Base de datos
echo    2 Inicio de sesion
echo    3 Mundo del juego
echo.
echo  NO CIERRES esas ventanas mientras jugueis.
echo  Puedes minimizarlas, pero no cerrarlas con la X.
echo  Esta ventana si la puedes cerrar.
echo ============================================
echo.
pause
