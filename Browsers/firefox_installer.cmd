@echo off
:: Silent Mozilla Firefox installer (Tiny11 Builder - Ultimate Edition).
:: Staged by -Browser Firefox and run once at the first sign-in by
:: %WINDIR%\Setup\Tiny11\FirstLogon.cmd, which already waits for the network.
:: Picks the ARM64 build on ARM64 Windows. Output goes to firstlogon.log.

setlocal
set "FF_OS=win64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "FF_OS=win64-aarch64"
set "FF_URL=https://download.mozilla.org/?product=firefox-latest-ssl&os=%FF_OS%&lang=en-US"
set "FF_TMP=%TEMP%\firefox_installer.exe"

echo [Firefox] Downloading %FF_OS% build...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; for ($i = 1; $i -le 3; $i++) { try { Invoke-WebRequest -Uri $env:FF_URL -OutFile $env:FF_TMP -UseBasicParsing -ErrorAction Stop; exit 0 } catch { Start-Sleep -Seconds (10 * $i) } }; exit 1"
if errorlevel 1 (
    echo [Firefox] ERROR: download failed.
    exit /b 1
)

echo [Firefox] Installing silently...
"%FF_TMP%" /S
set "RC=%ERRORLEVEL%"
del /q "%FF_TMP%" >nul 2>&1
if not "%RC%"=="0" (
    echo [Firefox] WARNING: installer exit code %RC%.
    exit /b %RC%
)
echo [Firefox] Installed.
endlocal
exit /b 0
