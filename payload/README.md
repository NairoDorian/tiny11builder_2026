# Payload and installed-system hooks

Updated 2026-10-05. These scripts are **staged into the offline image** during the build and run on the newly installed Windows. They are not permission to change the live build host. See [PROJECT_GUIDE.md](../docs/PROJECT_GUIDE.md) and [WORKING_NOTES.md](../docs/WORKING_NOTES.md).

## SetupComplete: SYSTEM, before first sign-in

Enable `-Payload` (GUI Extras) to include files from [packages/](packages/). The current selection helper copies **top-level files except README.md**; it does not recursively copy nested directories. Companion installers/data at that level are copied as well, but only top-level `.cmd` and `.ps1` scripts are executed.

`Install-ImagePayload` creates `%WINDIR%\Setup\Scripts\SetupComplete.cmd`. An existing OEM hook is moved to `%WINDIR%\Setup\Tiny11\SetupComplete.oem.cmd` and chained first. The generated hook then runs catalog FirstBoot commands and staged package scripts:

1. OEM hook and catalog commands, in generated order.
2. All matching `packages\*.cmd` files.
3. All matching `packages\*.ps1` files through installed Windows PowerShell 5.1.

CMD wildcard enumeration is used within each script type. Prefixes help name/order scripts within a group, but there is no single sorted sequence interleaving `.cmd` and `.ps1`; put tightly dependent operations in one explicit orchestrator script instead of assuming `10-x.ps1` precedes `20-y.cmd`. Runtime hook output is appended to `%WINDIR%\Setup\Tiny11\setupcomplete.log`; the hook continues to other scripts rather than making each package failure fatal to the builder.

Scripts run as SYSTEM, with no user signed in and possibly no network. Use silent offline installers, handle their exit codes explicitly, avoid prompts and keep work bounded: target Windows waits for SetupComplete. Companion files are addressed with `%~dp0` or `$PSScriptRoot`. Nested payload folders need an intentional selection/staging change; merely adding a folder here will not include it.

## FirstLogon: first user's session

`%WINDIR%\Setup\Tiny11\FirstLogon.cmd` waits for network availability, runs staged first-logon `.cmd` then `.ps1` scripts (currently optional [browser installers](../Browsers/README.md)), and deletes selected cached answer files. Its log is `%WINDIR%\Setup\Tiny11\firstlogon.log`. This is separate from SetupComplete and from ISO-build timing.

Generated/custom answer files can contain account secrets; Base64 obfuscation is not encryption. The built-in cleanup targets Panther/Sysprep answer-file locations but is not proof that every other custom copy was erased. GUI profile exports omit the password; inspect custom payloads/logs before publishing them.

## Example package

```bat
:: packages\10-power.cmd -- runs only on the NEW installed Windows
@echo off
powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
if errorlevel 1 exit /b 1
exit /b 0
```

This is an optional target-system customization example, not a command to run on the current host. Put dependencies/required ordering inside the script. The builder's own target-system tweak commands are generated from the catalog, not edited by changing reference autounattend files.

Office is not bundled. Older fork notes mentioned installer-specific unattended failures such as VC++ 2005; those are historical reports, not a reproduced current compatibility matrix. Test any chosen payload on a disposable target and report actual installer/version/exit behavior. The current audit does not claim browser/payload execution passed a complete VM installation.
