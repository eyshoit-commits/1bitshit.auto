@echo off
setlocal EnableExtensions

cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
    echo FEHLER: git wurde nicht gefunden.
    exit /b 1
)

echo BitShit Update-Bootstrap startet.
echo Hole zuerst die aktuelle Version der Update-Skripte.
git fetch origin --prune
if errorlevel 1 exit /b %errorlevel%

git switch main
if errorlevel 1 exit /b %errorlevel%

git reset --hard origin/main
if errorlevel 1 exit /b %errorlevel%

echo Starte aktualisiertes PowerShell-Skript.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
exit /b %errorlevel%
