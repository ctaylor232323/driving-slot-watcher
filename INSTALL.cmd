@echo off
title Driving Lesson Slot Watcher - Setup
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" 
if errorlevel 1 (
  echo.
  echo Something went wrong. The message above says what.
  pause
)
