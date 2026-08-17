@echo off
title Deploy mod-rts - modulo del servidor
color 0A

REM Lleva el modulo del servidor del ORIGINAL a AzerothCore.
REM
REM   ORIGINAL:  C:\Server\rts-project\mod-rts
REM   COPIA:     C:\Server\azerothcore\modules\mod-rts
REM
REM OJO: esto solo copia el codigo fuente. Para que el servidor lo use
REM hay que RECOMPILAR despues.

set ORIGEN=C:\Server\rts-project\mod-rts
set DESTINO=C:\Server\azerothcore\modules\mod-rts

echo ============================================
echo   DEPLOY MOD-RTS
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

robocopy "%ORIGEN%" "%DESTINO%" /MIR /R:2 /W:2 /NFL /NDL /NJH /NJS /NP

if errorlevel 8 (
    echo.
    echo [ERROR] La copia ha fallado.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Copiado. AHORA HAY QUE RECOMPILAR:
echo.
echo    cmake --build C:\Server\build --config Release --target worldserver -- /m
echo.
echo  Iniciar_Servidor.bat ya recoge el worldserver.exe nuevo el solo.
echo ============================================
echo.
pause
