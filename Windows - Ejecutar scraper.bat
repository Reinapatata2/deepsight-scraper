@echo off
REM Doble clic para lanzar el scraper (el codigo esta en scripts\windows)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\scraper_windows.ps1" %*
echo.
pause
