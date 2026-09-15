@echo off
:: SetupComplete.cmd
:: Executes after Windows setup completes and a user logs in for the first time.
:: Place optional post-install payloads here (e.g. .NET runtimes, VC++ redists).
::
:: This mechanism is inspired by the MOPELotus fork and extended for the
:: Ultimate Edition to support optional payload packages.

setlocal

:: Run all .cmd/.ps1 files in the payload\packages\ directory
for %%f in ("%~dp0packages\*.cmd") do (
    echo [SetupComplete] Running %%f
    call "%%f"
)

for %%f in ("%~dp0packages\*.ps1") do (
    echo [SetupComplete] Running PowerShell: %%f
    powershell -NoProfile -ExecutionPolicy Bypass -File "%%f"
)

:: Launch the optional welcome script if present
if exist "%~dp0welcome.cmd" (
    call "%~dp0welcome.cmd"
)

:: Clean up: self-delete to avoid re-runs on future feature updates
del "%~dp0SetupComplete.cmd"

endlocal
