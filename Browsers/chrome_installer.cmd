@echo off
:: Silent Google Chrome installer (Tiny11 Builder - Ultimate Edition).
:: Staged by -Browser Chrome and run once at the first sign-in by
:: %WINDIR%\Setup\Tiny11\FirstLogon.cmd, which already waits for the network.
:: The online installer picks x64 or ARM64 itself. Output goes to firstlogon.log.

setlocal
set "CHROME_URL=https://dl.google.com/chrome/install/latest/chrome_installer.exe"
set "CHROME_TMP=%TEMP%\chrome_installer.exe"

echo [Chrome] Downloading...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; for ($i = 1; $i -le 3; $i++) { try { Invoke-WebRequest -Uri $env:CHROME_URL -OutFile $env:CHROME_TMP -UseBasicParsing -ErrorAction Stop; exit 0 } catch { Start-Sleep -Seconds (10 * $i) } }; exit 1"
if errorlevel 1 (
    echo [Chrome] ERROR: download failed.
    exit /b 1
)

echo [Chrome] Installing silently...
"%CHROME_TMP%" /silent /install
set "RC=%ERRORLEVEL%"
del /q "%CHROME_TMP%" >nul 2>&1
if not "%RC%"=="0" (
    echo [Chrome] WARNING: installer exit code %RC%.
    exit /b %RC%
)
echo [Chrome] Installed.
endlocal
exit /b 0
