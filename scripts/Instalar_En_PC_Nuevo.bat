@echo off
title Instalar programas - Servidor WoW (PC nuevo)
color 0E

REM Se ejecuta UNA VEZ en el ordenador nuevo, despues de copiar C:\Server.
REM Pide permisos de administrador el solo.

echo ============================================
echo   PREPARAR ESTE ORDENADOR PARA EL SERVIDOR
echo ============================================
echo.

REM Comprueba si ya vamos como administrador.
net session >nul 2>&1
if errorlevel 1 (
    echo Hacen falta permisos de administrador.
    echo Dile que SI a la ventana que va a salir.
    echo.
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Instalando Visual Studio, Git, CMake, Python, Boost y OpenSSL.
echo Esto tarda un buen rato y necesita internet. No cierres la ventana.
echo.

powershell -ExecutionPolicy Bypass -File "C:\Server\Mudanza_2_Instalar.ps1"

echo.
echo ============================================
echo  REINICIA EL ORDENADOR ANTES DE COMPILAR.
echo  Luego ya puedes usar Iniciar_Servidor.bat
echo ============================================
echo.
pause
