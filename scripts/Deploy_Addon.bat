@echo off
title Deploy Addon - RTSCommand
color 0A

REM Lleva el addon del ORIGINAL a la carpeta del WoW.
REM
REM   ORIGINAL:  C:\Server\rts-project\addon        <- aqui se trabaja
REM   COPIA:     F:\...\Interface\AddOns\RTSCommand <- aqui lo lee el juego
REM
REM Un solo sentido, siempre el mismo. Si el juego no hace lo que esperas,
REM lo primero es darle a esto.

set ORIGEN=C:\Server\rts-project\addon
set DESTINO=F:\Games\WOW WOTLK\Interface\AddOns\RTSCommand

echo ============================================
echo   DEPLOY ADDON
echo ============================================
echo.

if not exist "%ORIGEN%" (
    echo [ERROR] No encuentro %ORIGEN%
    pause
    exit /b 1
)

echo   %ORIGEN%
echo      hacia
echo   %DESTINO%
echo.

REM /MIR: el destino queda EXACTAMENTE igual que el origen, incluidos borrados.
REM Es seguro aqui porque en la carpeta del addon no hay nada generado --
REM la configuracion guardada del addon vive en WTF\, no aqui.
robocopy "%ORIGEN%" "%DESTINO%" /MIR /R:2 /W:2 /NFL /NDL /NJH /NJS /NP

if errorlevel 8 (
    echo.
    echo [ERROR] La copia ha fallado.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Hecho. En el juego:  /reload
echo  (o cierra y abre el WoW)
echo ============================================
echo.
pause
