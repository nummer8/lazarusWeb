@echo off
rem Build lazarusWeb service_demo (nogui widgetset, Windows Service capable)
rem keep ASCII + CRLF, cmd.exe chokes on UTF-8 comments
if defined LAZBUILD goto havetool
set LAZBUILD=lazbuild.exe
if exist "%ProgramFiles%\Lazarus\lazbuild.exe" set LAZBUILD=%ProgramFiles%\Lazarus\lazbuild.exe
if exist "%LocalAppData%\Lazarus\lazbuild.exe" set LAZBUILD=%LocalAppData%\Lazarus\lazbuild.exe
if exist "C:\lazarus\lazbuild.exe" set LAZBUILD=C:\lazarus\lazbuild.exe
if exist "C:\111\lazarus\lazbuild.exe" set LAZBUILD=C:\111\lazarus\lazbuild.exe
:havetool
"%LAZBUILD%" -B service_demo.lpi %*
if errorlevel 1 goto end
echo.
echo  foreground:  service_demo.exe --port=8081
echo  install:     service_demo.exe --install   ^(as Administrator^)
echo  start:       sc.exe start lazarusWebService  (PowerShell also works)
:end
