@echo off
title Apagando el servidor
echo Cerrando el servidor por completo, espera unos segundos...
echo.

taskkill /F /IM worldserver.exe /T >nul 2>&1
taskkill /F /IM authserver.exe /T >nul 2>&1
taskkill /F /IM mysqld.exe /T >nul 2>&1

echo Listo, el servidor esta apagado.
echo.
pause
