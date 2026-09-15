@echo off
:: Tiny11 Builder Ultimate Edition - Simple UAC Elevation Launcher
:: Launches the main builder with admin rights and bypass execution policy.
:: Usage: Run.bat [-Custom] [-Yes] [-ISO <letter>] [-SCRATCH <letter>] ...

net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '/elevated'"
    exit /b
)

:: Pass all command-line arguments to the builder script
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0tiny11maker.ps1" %*
