@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0NovaSplashMaker.ps1"
if errorlevel 1 (
  echo.
  echo Nova Splash Maker exited with an error.
  pause
)
