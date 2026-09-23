# Payload: run your own scripts after installation

Build with `-Payload` (GUI: **Extras** tab, *Run my scripts from payload\packages*):
every file in [`packages/`](packages) is copied into the image, and the top-level
`*.cmd` / `*.ps1` files are executed **once, as SYSTEM, at the end of Windows Setup**
(before the first sign-in), in alphabetical order. The Extras tab lists the scripts it
found and has a button that opens this folder.

## How it works

The builder writes `%WINDIR%\Setup\Scripts\SetupComplete.cmd` into the image
(an existing OEM `SetupComplete.cmd` is preserved and chained first). It runs:

1. the first-boot commands of the tweak catalog (for example the Ultimate
   Performance power plan of the Gaming preset, or disabling `wuauserv` on Core);
2. `%WINDIR%\Setup\Tiny11\packages\*.cmd`, then `*.ps1` (alphabetical order);

and logs everything to `%WINDIR%\Setup\Tiny11\setupcomplete.log`.

A second hook, `%WINDIR%\Setup\Tiny11\FirstLogon.cmd`, runs at the first sign-in
(in the user's session, after waiting for the network). It installs the browser
chosen with `-Browser` and then deletes the cached answer files, which contain
the account password. Its log is `%WINDIR%\Setup\Tiny11\firstlogon.log`.

## Writing a package

- It runs as **SYSTEM** with no user logged on and possibly **no network**:
  prefer offline installers. Every file in `packages/` is copied into the image
  (only the top-level `.cmd`/`.ps1` files are *executed*), so a script can call
  an installer placed next to it: `"%~dp0vc_redist.x64.exe" /install /quiet /norestart`
  or `& "$PSScriptRoot\setup.msi"`.
- Be silent: `/quiet`, `/qn`, `/S`... Nothing can prompt.
- Return quickly; Windows waits for SetupComplete before showing the desktop.
- Exit codes are logged but never stop the other packages.

Examples:

```bat
:: packages\10-power.cmd - balanced plan, no hibernation file
powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
powercfg.exe /hibernate off
```

```powershell
# packages\20-explorer.ps1 - show file extensions for every new user
reg.exe load HKU\T11Default C:\Users\Default\NTUSER.DAT
reg.exe add "HKU\T11Default\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f
reg.exe unload HKU\T11Default
```

Office is intentionally not bundled; install it after setup with the Office
Deployment Tool or Office Tool Plus. VC++ 2005 redistributables are known to
break unattended setup on current builds (noted by the MOPELotus fork).
