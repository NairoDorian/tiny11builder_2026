# Optional browser at first sign-in

Updated 2026-10-05. See [the project guide](../docs/PROJECT_GUIDE.md) for staging and [working notes](../docs/WORKING_NOTES.md) for the host boundary.

Built-in presets request Edge removal; custom flags can retain it. `-Browser None` is default. Choose `-Browser Firefox` or `-Browser Chrome` (GUI Extras) to stage the corresponding script into `%WINDIR%\Setup\Tiny11\firstlogon\` in the **offline image**. It is executed on the resulting installed Windows at first sign-in by `FirstLogon.cmd`, not on the machine building the ISO.

The generated first-logon hook waits for network availability using repeated ping/delay attempts, then tries the selected script even if the network probe never succeeds. Browser scripts make up to three download attempts with backoff, run the installer silently, remove the downloaded temporary executable and propagate an error/installer exit status into the first-logon log. This is post-install time/network activity, not part of the measured ISO compression speed.

| File | Selection | Current behavior |
|---|---|---|
| `firefox_installer.cmd` | Firefox | Mozilla latest en-US URL; win64 or win64-aarch64 selected from installed system architecture; `/S` |
| `chrome_installer.cmd` | Chrome | Google latest online installer URL; `/silent /install`; target/vendor support is not proved by our x64 ISO fixtures |

Log: `%WINDIR%\Setup\Tiny11\firstlogon.log` on the newly installed system. Without automatic browser staging, App Installer/winget is protected and can be used after installation. These scripts use vendor latest URLs, not version-pinned browser packages; no browser-install test is recorded by the current reference/doc audit.

To add a choice, supply the installer script, update both builder ValidateSets, GUI choice/state translation, validation/tests and this table. Do not execute the installer on this session's live read-only host as a build test. The folder's original idea was studied in DFwindows11_builder; source/reference decisions are in [REFERENCE_REVIEW.md](../docs/REFERENCE_REVIEW.md).
