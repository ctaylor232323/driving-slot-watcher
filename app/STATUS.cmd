@echo off
title Driving Lesson Slot Watcher - Status
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Show-Status.ps1"
echo.
pause
