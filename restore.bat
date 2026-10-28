@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0debloat.ps1" -Action Restore
set ERR=%ERRORLEVEL%
echo.
pause
exit /b %ERR%
