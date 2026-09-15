@echo off
:: Silent Google Chrome installer for the Ultimate Edition.
:: Downloads and installs the latest 64-bit Chrome silently.
:: Inspired by the DFwindows11_builder fork's Browsers folder.

set "CHROME_URL=https://dl.google.com/chrome/install/latest/chrome_installer.exe"
set "CHROME_TMP=%TEMP%\chrome_installer.exe"

echo [Browser Install] Downloading Google Chrome...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Invoke-WebRequest -Uri '%CHROME_URL%' -OutFile '%CHROME_TMP%' -UseBasicParsing -ErrorAction Stop; exit 0 } catch { Write-Error $_.Exception.Message; exit 1 }"

if %ERRORLEVEL% neq 0 (
    echo [Browser Install] ERROR: Failed to download Chrome.
    exit /b 1
)

echo [Browser Install] Installing Google Chrome (silent)...
"%CHROME_TMP%" /silent /install

if %ERRORLEVEL% equ 0 (
    echo [Browser Install] Chrome installed successfully.
) else (
    echo [Browser Install] WARNING: Chrome installer returned exit code %ERRORLEVEL%.
)

del /q "%CHROME_TMP%" 2>nul
exit /b 0
