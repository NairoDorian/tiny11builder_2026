# Contributing

Thanks for helping. This project builds on the upstream tiny11builder and 15
community forks (see the README credits); improvements of any size are welcome.

## Ground rules

1. **Never touch the host.** Everything the builders change lives in the
   mounted image or its offline hives (`HKLM\zSOFTWARE`, `zSYSTEM`, `zNTUSER`,
   `zDEFAULT`, `zCOMPONENTS`). `Set-RegistryValue` / `Remove-RegistryValue`
   enforce this; do not bypass them with raw `reg.exe` or `Set-ItemProperty`.
2. **Offline hives have no `CurrentControlSet`.** Use `ControlSet001`.
3. **Windows PowerShell 5.1** is the runtime. Save `.ps1/.psm1/.psd1` files as
   UTF-8 *with BOM* and CRLF (`.gitattributes` handles line endings).
4. **No `& tool 2>$null`** in scripts running with `$ErrorActionPreference='Stop'`:
   PS 5.1 turns the stderr line into a terminating error. Use `Invoke-Native`.
5. Validate options *before* the long work starts; keep individual tweak or app
   failures non-fatal (count a warning), and keep mount/commit/export failures fatal.

## Where things go

| Change | File |
|---|---|
| Registry tweak | [`data/tweaks.psd1`](data/tweaks.psd1): add a line to a group, or a new group with a `When` flag |
| New preset flag | `Get-PresetFlagNames` + `Resolve-BuildPreset` in `lib/tiny11utils.psm1`, and all four `presets/*.json` |
| App removed by default | [`removePackage.txt`](removePackage.txt) (prefix; no optional utilities, no protected packages) |
| Optional app (`-Keep`/`-Remove`) | `Get-OptionalUtilities` |
| Answer-file behaviour | `New-UnattendXml` (the tests hold an allow-list of valid settings per pass) |
| Build step shared by both builders | a stage function in `lib/tiny11utils.psm1` |
| GUI | `lib/tiny11gui.psm1` (`Show-Tiny11BuilderForm -PreviewPath x.png` renders it headless) |

## Before you open a pull request

```powershell
.\scripts\update-generated.ps1   # regenerate docs/, reference answer files, module manifest
.\scripts\parse-check.ps1        # everything parses, every command resolves
.\scripts\test-core-helpers.ps1  # unit tests (no admin, no ISO)
.\scripts\linter.ps1             # PSScriptAnalyzer
```

CI runs the same four on Windows PowerShell 5.1 and fails when a generated file
is stale. If you changed build behaviour, also run a real build in a VM
(`-DryRun` first, then a full build) and mention the Windows build you tested in
the pull request. The `tiny11.iso.json` manifest shows exactly what was applied.

## Studying forks

Reference forks live in `repos/` (git-ignored). Clone new ones as
`repos/<owner>_<name>`, and credit the source of any idea you port in the
commit message and in `CHANGELOG.md`.
