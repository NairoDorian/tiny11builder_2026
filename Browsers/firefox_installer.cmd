@echo off
:: Silent Mozilla Firefox installer for the Ultimate Edition.
:: Downloads and installs the latest 64-bit Firefox silently.

set "FIREFOX_URL=https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
set "FIREFOX_TMP=%TEMP%\firefox_installer.exe"

echo [Browser Install] Downloading Mozilla Firefox...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { Invoke-WebRequest -Uri '%FIREFOX_URL%' -OutFile '%FIREFOX_TMP%' -UseBasicParsing -ErrorAction Stop; exit 0 } catch { Write-Error $_.Exception.Message; exit 1 }"

if %ERRORLEVEL% neq 0 (
    echo [Browser Install] ERROR: Failed to download Firefox.
    exit /b 1
)

echo [Browser Install] Installing Mozilla Firefox (silent)...
"%FIREFOX_TMP%" /S

if %ERRORLEVEL% equ 0 (
    echo [Browser Install] Firefox installed successfully.
) else (
    echo [Browser Install] WARNING: Firefox installer returned exit code %ERRORLEVEL%.
)

del /q "%FIREFOX_TMP%" 2>nul
exit /b 0
