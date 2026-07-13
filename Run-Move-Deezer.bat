@echo off
rem Launcher for Move-Deezer.ps1 - keep this file in the same folder as the script.
rem %~dp0 = folder where this .bat file is located.
rem Prefers PowerShell 7+ (pwsh.exe) if installed, falls back to Windows PowerShell 5.1.

if not exist "%~dp0Move-Deezer.ps1" (
    echo ERROR: Move-Deezer.ps1 not found next to this launcher.
    echo Make sure both files are in the same folder.
    pause
    exit /b 1
)

where pwsh.exe >nul 2>nul
if %errorlevel%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Move-Deezer.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Move-Deezer.ps1"
)
