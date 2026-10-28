@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0debloat.ps1" -Action Debloat
set ERR=%ERRORLEVEL%
echo.
pause
exit /b %ERR%
