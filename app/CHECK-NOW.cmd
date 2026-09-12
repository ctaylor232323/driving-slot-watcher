@echo off
title Driving Lesson Slot Watcher - Check Now
cd /d "%~dp0"
echo Checking the scheduling page right now...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check-Slots.ps1" -NoJitter
echo.
pause
