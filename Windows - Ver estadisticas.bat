@echo off
REM Doble clic para ver las estadisticas (el codigo esta en scripts\windows)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\estadisticas_windows.ps1" %*
echo.
pause
