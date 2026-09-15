@echo off
:: Tiny11 Builder Ultimate Edition - Launcher with Admin Check
:: From the reforged fork approach: ensures admin + execution policy before launching
:: setwindowstyle: minimized to avoid flicker
:: color: use a readable scheme (defaults to system)

:: --- Check for administrator ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo =============================================
    echo  Tiny11 Builder - Elevated permissions required
    echo =============================================
    echo.
    echo This script must be run as Administrator.
    echo Right-click and choose "Run as administrator",
    echo or press any key to auto-elevate...
    echo.
    pause >nul
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '/elevated'"
    exit /b
)

:: --- Verify PowerShell exists ---
where powershell >nul 2>&1
if %errorlevel% NEQ 0 (
    echo PowerShell not found. Please install .NET / PowerShell and retry.
    pause
    exit /b 1
)

:: --- Set window title ---
title Tiny11 Builder - Ultimate Edition

:: --- Launch the appropriate builder ---
:: Pass any command-line args through to the script.
:: Default: regular maker. Use -BuildCore to launch coremaker instead.
setlocal EnableDelayedExpansion

set "SCRIPT_ARGS=%*"

echo.
echo === Tiny11 Builder - Ultimate Edition ===
echo.
echo Which builder do you want to run?
echo   [1] tiny11maker.ps1  - Standard serviceable image (recommended)
echo   [2] tiny11Coremaker.ps1 - Ultra-trimmed Core image (not serviceable, VM-only)
echo.
echo Keys 1-2 to choose, or press Enter for the default (1).
echo.

choice /c 12 /n /cs /t 10 /d 1 >nul 2>&1
if %errorlevel% EQU 1 (
    set "SCRIPT=tiny11maker.ps1"
) else if %errorlevel% EQU 2 (
    set "SCRIPT=tiny11Coremaker.ps1"
) else (
    set "SCRIPT=tiny11maker.ps1"
)

:: Quick mode: if -BuildCore is in args, use coremaker
echo %SCRIPT_ARGS% | findstr /i "core" >nul 2>&1 && set "SCRIPT=tiny11Coremaker.ps1"

echo.
echo Launching: %SCRIPT% %SCRIPT_ARGS%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0%SCRIPT%" %SCRIPT_ARGS%

endlocal
