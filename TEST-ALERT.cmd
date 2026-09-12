@echo off
title Driving Lesson Slot Watcher - Test Alert
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check-Slots.ps1" -TestAlert
if errorlevel 1 (
  echo.
  echo Something went wrong. The message above says what.
  pause
)
