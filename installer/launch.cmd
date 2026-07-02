@echo off
set APPDIR=%~1
set LOGFILE=C:\bg-dashboard-install.log
echo === launch.cmd started %DATE% %TIME% >> "%LOGFILE%"
echo AppDir: %APPDIR% >> "%LOGFILE%"
echo Launching setup.ps1... >> "%LOGFILE%"
powershell.exe -ExecutionPolicy Bypass -File "%APPDIR%\installer\setup.ps1" -AppDir "%APPDIR%" -InstallNSSM -InstallWireshark >> "%LOGFILE%" 2>&1
echo setup.ps1 exited with code %ERRORLEVEL% >> "%LOGFILE%"
