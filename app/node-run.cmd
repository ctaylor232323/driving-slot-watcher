@echo off
REM Runs a node script from this folder without needing node on PATH.
REM Used by the installer wizard, which may run before PATH has caught up.
cd /d "%~dp0"

set "NODEEXE="
for %%I in (node.exe) do if not "%%~$PATH:I"=="" set "NODEEXE=%%~$PATH:I"
if not defined NODEEXE if exist "%ProgramFiles%\nodejs\node.exe" set "NODEEXE=%ProgramFiles%\nodejs\node.exe"
if not defined NODEEXE if exist "%ProgramFiles(x86)%\nodejs\node.exe" set "NODEEXE=%ProgramFiles(x86)%\nodejs\node.exe"
if not defined NODEEXE if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" set "NODEEXE=%LOCALAPPDATA%\Programs\nodejs\node.exe"

if not defined NODEEXE (
  echo Node.js could not be found.
  exit /b 9
)

"%NODEEXE%" %*
