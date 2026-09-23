@echo off
:: Tiny11 Builder - Ultimate Edition : run the Standard builder directly.
:: Usage: Run.bat [builder arguments], e.g.
::   Run.bat -ISO D:\Win11_25H2.iso -Edition Pro -Preset Gaming -Yes
:: (tiny11maker.ps1 elevates itself and keeps your arguments.)
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0tiny11maker.ps1" %*
