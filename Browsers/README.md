# Browsers

Every preset removes Microsoft Edge, so a fresh tiny11 install has no browser.
You can either:

- install one yourself with `winget install Mozilla.Firefox` (App Installer /
  winget is always kept), or
- let the builder do it: `-Browser Firefox` or `-Browser Chrome` (GUI: **Extras** tab, *Browser*).

With `-Browser`, the matching script in this folder is copied into the image
(`%WINDIR%\Setup\Tiny11\firstlogon\`) and run once at the first sign-in by
`FirstLogon.cmd`. That script waits up to two minutes for a network connection
(Wi-Fi often connects late) and logs to `%WINDIR%\Setup\Tiny11\firstlogon.log`.

| Script | Browser | Notes |
|---|---|---|
| `firefox_installer.cmd` | Mozilla Firefox (latest, en-US) | ARM64 build on ARM64 Windows |
| `chrome_installer.cmd` | Google Chrome (latest) | online installer picks x64/ARM64 |

To add another browser, drop `<name>_installer.cmd` here and add `<name>` to the
`-Browser` `ValidateSet` in `tiny11maker.ps1` / `tiny11Coremaker.ps1` and to the
GUI list in `lib/tiny11gui.psm1`.

Inspired by the DFwindows11_builder fork's Browsers folder.
