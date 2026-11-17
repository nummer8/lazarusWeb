@echo off
REM HTTPS startup with the bundled private-CA certificate.
REM Usage: start-ssl.bat [LAN-IP]   (default 192.168.1.74)
setlocal
set "IP=%~1"
if "%IP%"=="" set "IP=192.168.1.74"
if not exist "%~dp0cert\server.crt" call "%~dp0..\..\cert-ca\make-lan-cert.bat" "%~dp0cert" %IP% || exit /b 1
cd /d "%~dp0"
mobile_demo.exe --port=8445 --ssl --ssl-host=%IP% --ssl-cert=cert\server.crt --ssl-key=cert\server.key %*
