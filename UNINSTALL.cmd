@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-JellyfinOpenLocation.ps1"
echo.
pause
