@echo off
title Driving Lesson Slot Watcher - Alerts
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-PushAlerts.ps1" 
if errorlevel 1 (
  echo.
  echo Something went wrong. The message above says what.
  pause
)
