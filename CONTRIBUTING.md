# Contributing

Thanks for helping. This project extends [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder)
with ideas from 15 community forks (see the [README credits](README.md#history-and-credits)).
Improvements of any size are welcome: new tweaks, package names for new Windows builds, bug fixes,
GUI polish, docs.

## Ground rules

1. **Never touch the host.** Everything the builders change lives in the mounted image or in its
   offline hives (`HKLM\zSOFTWARE`, `zSYSTEM`, `zNTUSER`, `zDEFAULT`, `zCOMPONENTS`).
   `Set-RegistryValue` / `Remove-RegistryValue` enforce this: they refuse other paths and hives
   that are not loaded. Do not bypass them with raw `reg.exe` or `Set-ItemProperty`.
2. **Offline hives have no `CurrentControlSet`**: use `ControlSet001`.
3. **Windows PowerShell 5.1 is the runtime.**
   - Save `.ps1/.psm1/.psd1` files as UTF-8 **with BOM**; `.gitattributes` keeps CRLF line endings.
   - Never write `& tool 2>$null` in code that runs with `$ErrorActionPreference = 'Stop'`: PS 5.1
     turns the stderr line into a terminating error. Use `Invoke-Native`.
4. **Fail early, degrade gracefully.**
   - Validate options before the long work starts.
   - A single tweak or app that fails is a counted warning.
   - A failed mount, commit, export or ISO step is fatal, and the trap then cleans up.
5. **Keep the GUI and the command line equivalent.** Every GUI control maps to a builder parameter
   through `ConvertTo-GuiBuildRequest`, and the Build tab shows the resulting command line.

## Where things go

| Change | File |
|---|---|
| Registry tweak | [`data/tweaks.psd1`](data/tweaks.psd1): add a line to a group, or a new group with a `When` flag |
| New preset flag | `Get-PresetFlagNames`, `Resolve-BuildPreset` and `Get-PresetFlagSection` in `lib/tiny11utils.psm1`, all four `presets/*.json`, and `Get-GuiFlagInfo` (label and hint) in `lib/tiny11gui.psm1` |
| New builder parameter | Both builders' `param()` blocks and comment help, `ConvertTo-GuiBuildRequest`, a control in `Show-Tiny11BuilderForm`, and the README option tables |
| App removed by default | [`removePackage.txt`](removePackage.txt): a prefix, under the right `# ---` section. No optional utilities and no protected packages (the tests check both). |
| Optional app (`-Keep`/`-Remove`) | `Get-OptionalUtilities` |
| Answer-file behaviour | `New-UnattendXml`. The tests hold an allow-list of valid settings per pass, so extend it deliberately. |
| Build step shared by both builders | a stage function in `lib/tiny11utils.psm1` (`Invoke-*Stage`, `Export-FinalInstallImage`, `New-Tiny11Iso`) |
| GUI | `lib/tiny11gui.psm1`: pure logic in the "Pure helpers" region (unit-tested), controls in `Show-Tiny11BuilderForm` |

## Before you open a pull request

```powershell
.\scripts\update-generated.ps1    # docs/TWEAKS.md, docs/APPS.md, reference answer files, manifests
.\scripts\parse-check.ps1         # everything parses, every command resolves
.\scripts\test-core-helpers.ps1   # ~1,750 checks, including the GUI (no admin rights, no ISO)
.\scripts\linter.ps1              # PSScriptAnalyzer
.\scripts\update-screenshots.ps1  # only if the window changed
```

CI runs the first four on Windows PowerShell 5.1 and fails when a generated file is stale.

The tests never run a real build. When you change build behaviour:

- run a real build in a VM (a dry run first, then a full build), or from the GUI;
- attach the `tiny11.iso.json` manifest, or name the Windows build you tested, in the pull request.

### Testing the GUI without a build

`Show-Tiny11BuilderForm` has three hooks for tests:

- `-PreviewPath` / `-PreviewTab` render a tab to a PNG with `DrawToBitmap`. This is window-only
  rendering, never a screen grab.
- `-AutoRun Build` together with `-BuilderOverride scripts\fixtures\fake-builder.ps1` and `-Quiet`
  drives a complete build through the real window and launcher. The fixture only prints a log;
  it never touches the system.
- `-InitialState` pre-fills the window from a state object (`Get-GuiDefaultState`).

## Studying forks

Reference forks live in `repos/`, which is git-ignored. Clone new ones as `repos/<owner>_<name>`.
Credit the source of any idea you port in the commit message and in `CHANGELOG.md`.

## History

`main` keeps the full upstream history. Please send focused commits with clear messages rather than
large squashes, so every change stays traceable back to the original project.
