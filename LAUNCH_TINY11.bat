@echo off
:: Tiny11 Builder - Ultimate Edition : launcher
:: Double-click to pick the GUI or a console builder. Elevates itself, runs
:: PowerShell 5.1 with -ExecutionPolicy Bypass (no system-wide policy change)
:: and unblocks the downloaded scripts so Windows does not prompt for each one.
:: Extra arguments are passed to the console builders, e.g.
::   LAUNCH_TINY11.bat 2 -ISO D:\Win11.iso -Edition Pro -Yes
setlocal

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
title Tiny11 Builder - Ultimate Edition
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1,*.psm1,*.psd1,*.cmd | Unblock-File" >nul 2>&1

set "CHOICE_ARG=%~1"
if "%CHOICE_ARG%"=="1" goto gui
if "%CHOICE_ARG%"=="2" (shift & goto standard)
if "%CHOICE_ARG%"=="3" (shift & goto core)

echo.
echo  ==============================================
echo    Tiny11 Builder - Ultimate Edition
echo  ==============================================
echo.
echo    [1] Graphical builder (recommended)
echo    [2] Standard builder in the console  (serviceable, daily use)
echo    [3] Core builder in the console      (smallest, VMs only, not serviceable)
echo.
choice /c 123 /n /t 30 /d 1 /m "  Choose 1-3 (default 1 in 30 s): "
if errorlevel 3 goto core
if errorlevel 2 goto standard

:gui
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "%~dp0tiny11gui.ps1"
goto end

:standard
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0tiny11maker.ps1" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto end

:core
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0tiny11Coremaker.ps1" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto end

:end
endlocal
