# Changelog

All notable changes to the Tiny11 Builder Ultimate Edition are documented here.
This project is built from **NairoDorian/tiny11builder_2026** as the base,
incorporating improvements from 14+ community forks.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [2026.09.1] - 2026-09-23 - Round 5: the GUI becomes the main builder

### Added
- **Tabbed builder window with every option** (`lib/tiny11gui.psm1`), in seven tabs:
  - **Source**: editions with build, architecture, language and size.
  - **Preset & features**: every preset flag as a checkbox; load/save
    preset files; changed flags become a custom preset automatically.
  - **Apps**: the grouped removal list with checkboxes, your own prefixes,
    import/export, optional apps, keep everything. Entries a preset flag
    overrides (Xbox with "Keep Xbox") are greyed.
  - **Tweaks**: all catalog groups; uncheck to skip, check a greyed group to
    enable its flag; per-group value viewer.
  - **Setup & account**:
    - local admin with password confirmation, or account created in OOBE;
    - locale picker, time zone list, computer name;
    - zero-touch and custom answer file;
    - preview or save the generated `autounattend.xml`.
  - **Extras**: .NET 3.5, driver folder with `.inf` count, browser, payload
    file list, low-RAM, driver updates, Defender exclusion.
  - **Build**: plan, validation, the copyable equivalent command line.
- **Builds run inside the window**:
  - A hidden, non-interactive `powershell.exe` runs the builder with `-Yes`.
  - Its output is streamed into a colour-coded log with stage progress and
    elapsed time.
  - **Cancel** kills the process tree, then discards the mounted image and
    unloads the hives.
  - Arguments (including the password) travel through a CLIXML file that
    the launcher deletes immediately.
- **Validation before building**: missing ISO or edition, password mismatch,
  invalid user/computer name or locale, missing folders, not enough space on
  the work drive. Warnings cover zero-touch, Core, no antivirus, WebView2 and
  Mark-of-the-Web.
- **Profiles**: save/load the whole configuration; the last session is
  remembered in `gui-settings.json` (never the password).
- `ConvertTo-PresetJson` / `Get-PresetFlagSection` in the utils module (the
  inverse of `ConvertFrom-PresetJson`).
- **Tests**:
  - ~55 GUI checks: state -> builder arguments, validation, tweak toggling,
    progress parsing, settings round-trip, log tailing;
  - the launcher run against `scripts/fixtures/fake-builder.ps1` (exit code
    and output capture, args file deleted);
  - the whole window driven end to end with `-AutoRun` and the fake builder;
  - every tab rendered.
- The generator also maintains `lib/tiny11gui.psd1`; per-tab screenshots are in `docs/`.

### Fixed (found by the new tests and renders)
- The progress-stage table was flattened by PowerShell array unrolling, so the
  progress bar received character codes.
- WinForms raises `ItemChecked` for every ListView item when the handle is
  created, which silently skipped tweak groups. The handler is now idempotent.
- Controls anchored to the bottom grew past their tab page; ampersands in group
  titles were swallowed as mnemonics; truncated labels.

---
## [2026.09] - 2026-09-23 - Round 4: correctness audit, shared build library, catalog-driven tweaks

A full audit of the builders against all 15 reference forks (all re-pulled; the
upstream ntdevlabs repository was added to `repos/`) found that several
headline features never ran and that some defaults would break a real build.
Both builders were rebuilt on a tested shared library.

### Fixed - builds that failed or silently did nothing
- **ESD-only ISOs always failed**: `install.esd` was deleted before it was
  converted. The builders now export only the chosen edition, straight from the
  source `install.wim`/`install.esd`, which is also faster and needs less space.
- **Mount failed on a first run**: `Initialize-ScratchWorkspace` never created
  the mount folder when it did not exist.
- **`Apply-ExtendedTweaks` aborted every build**: it wrote to `HKLM\z\...` and
  `CurrentControlSet`, which do not exist offline; mouse/keyboard, firewall,
  driver-blocklist and power-plan values used wrong keys or formats. It was
  replaced by the tweak catalog (below).
- **`-User`, `-Password`, `-TimeZone`, `-ZeroTouch` did nothing**: the static
  answer file was always copied. The answer file is now generated per build.
- **The static `autounattend.xml` would stop Windows Setup**: the local account
  was in the `offlineServicing` pass, `<Power>` is not a Shell-Setup setting,
  `<ComputerName>` and `<DisableAutoDaylightTime>` sat in `oobeSystem`, and there
  was an invented `c:offlineClient` element. `New-UnattendXml` also used a wrong
  `wcm` namespace.
- **`-Keep` / `-Remove` had no effect**: they were resolved after apps had
  already been removed, and `removePackage.txt` removed Terminal and Notepad
  anyway.
- **24H2 detection never worked**: the version was queried from `HKLM\zSOFTWARE`
  before the hive was loaded. It is now read from the WIM metadata.
- **TaskCache GUIDs were hard-coded**: those GUIDs differ per image, so they
  never matched. Tasks are now resolved by path through `TaskCache\Tree`.
- **Language packages and capabilities never matched**: they used 2-letter
  codes and prefixes as full identities, and targeted the `Basic` language
  features. They are now matched against what is installed, and
  spell-check/typing are kept.
- **`recovery` compression was never used**: it silently became `max`.
  `recovery` now produces `install.esd`.
- **PS 5.1 hazard**: `& tool 2>$null` throws under `$ErrorActionPreference='Stop'`
  as soon as the tool writes to stderr. All quiet native calls now go through
  `Invoke-Native`.
- **Wrong registry keys**: TIPC, InputPersonalization and Personalization
  settings; the Notepad AI policy (`Policies\WindowsNotepad`); per-user search
  highlights; and the real `UScheduler_Oobe` trigger keys for Outlook and Dev Home.
- **Core**: one failing `/Remove-Package` aborted the build; the WinSxS swap
  could fail silently, leaving both copies in the image; `$input` was used as a
  variable; Defender and Windows Update both set `SettingsPageVisibility`, so
  the second overwrote the first.
- **Regular build**: no longer deletes Edge WebView from WinSxS, which damaged
  serviceability.
- **Misc**: `removePackage.txt` had typos (`Microsoft.Windows.CrossDevice`,
  `...Edge.Stable_8wekyb3d8bbwe!App`); GUI crashed on PS 5.1 (`Join-Path` with
  two child paths) and assumed contiguous edition indexes; build summary
  dropped hours; arguments with spaces/quotes/empty values broke the UAC
  relaunch; `takeown /D Y` and `Administrators` only worked on English Windows.

### Added
- **`data/tweaks.psd1`**: one catalog of every registry change, in 28 groups
  switched by preset flags. It is validated by tests, documented automatically in
  `docs/TWEAKS.md`, and `-SkipTweak` can leave groups out. New groups:
  - 24H2/25H2 AI: Recall, Click to Do, Settings agent, generative-AI app
    access, Paint/Notepad/Edge AI.
  - Widgets/News, Bing search, "finish setting up" nags, the personal-data-export
    OOBE page, the first-logon animation.
  - GameDVR (no more `ms-gamingoverlay` pop-ups), Edge Active Setup/updater
    services, OneDrive Run keys, Defender cloud reporting.
  - A valid telemetry firewall rule and a real Ultimate Performance plan
    (applied at first boot).
- **Deprovisioning**: removed apps are also marked deprovisioned, so feature
  updates do not reinstall them.
- **Answer-file generator**:
  - no account at all with `-InteractiveOobe`;
  - `-Locale` (or ask in OOBE, instead of forcing en-US keyboards);
  - `-ComputerName`, passwords stored Base64 (not plain text), and
    `net accounts /maxpwage:UNLIMITED`;
  - BypassNRO in the specialize pass, `DynamicUpdate` off;
  - answer files deleted after the first sign-in.
- **New options**:
  - `-Edition Pro`, `-EnableNetFx3` (Standard too), `-DriverPath` (install +
    Setup images), `-Browser Firefox|Chrome` (at first sign-in, waits for the
    network);
  - `-Payload` (whole `payload\packages` folder), `-NoPrompt` (efisys_noprompt),
    `-OutputIso`, `-PackageList`, `-UnattendFile`;
  - `-DefenderExclusion` (opt-in, reverted), `-Compress max`, custom
    `-Preset file.json`.
- **Build artifacts**: `<iso>.json` manifest (source, options, flags, removed
  apps, tweak groups) and `<iso>.sha256`. ISO volume label such as
  `TINY11_25H2_AMD64`. ARM64 ISOs are UEFI-only (`-bootdata:1`).
- **Robustness**:
  - retrying hive unload and dismount;
  - recovery from stale hives and mount points before a build;
  - mount sanity check, ISO minimum-size check, retrying install-image
    replacement;
  - `oscdimg` located through the ADK registry key; the downloaded copy is
    pinned by SHA-256.
- **Safety**: the registry helpers refuse any path outside the offline `HKLM\z*`
  hives, and refuse to write unless such a hive is actually loaded.
- **GUI**: one window with source, edition, Standard/Core, preset, compression,
  browser, work drive, output path, account, time zone, locale, options and
  optional apps. `-PreviewPath` renders it headless, for CI and docs.
- **Protected apps**: winget, frameworks and codecs are never removed; the Store
  and the Windows Security app go only with Minimal-VM/Core.
- **Tooling**:
  - ~1700-check test suite: data validation, answer-file allow-list, mocked
    build stages, static lint;
  - `parse-check.ps1` now resolves every command;
  - `update-generated.ps1` produces `docs/TWEAKS.md`, `docs/APPS.md`, the
    reference answer files and the module manifest;
  - linter over all files;
  - CI on Windows PowerShell 5.1; `.gitattributes` (CRLF).

### Changed
- Both builders share the same stages (`Invoke-AppRemovalStage`,
  `Invoke-RegistryStage`, `Export-FinalInstallImage`, `Invoke-BootImageStage`,
  `New-Tiny11Iso`). Core's default preset is `Minimal-VM`.
- Presets:
  - UTC hardware clock is opt-in everywhere;
  - Mark-of-the-Web is kept except in Minimal-VM;
  - PrivacyPlus keeps Defender on but disables cloud reporting;
  - Gaming keeps the Xbox stack;
  - WebView2 is kept except in Minimal-VM/Core.
- App matching uses name prefixes instead of substrings. Optional utilities
  moved out of `removePackage.txt`.
- The mid-build "disable driver updates?" prompt became `-DisableDriverUpdates`.
  Core asks its questions before the build starts.
- ISO mount state is passed as an object, not through `$Global:` variables.
- Logs go to `logs\`.

### Removed
- `payload/SetupComplete.cmd` (generated per build now), `docs/lista_de_apps.md`
  and `docs/lista_simples_apps.txt` (replaced by the generated `docs/APPS.md`),
  the hard-coded TaskCache GUID lists, and the unused helpers
  `Resolve-InstallImageIndex`, `Resolve-OscdimgSource`,
  `Test-ImageIndexAvailable`, `Test-ScratchDiskSpace` and `Unload-LoadedRegistries`.
- `tiny11LegacyProfile.ps1` is now a shim over the `LowRam` catalog group.

### Known limitations
- No end-to-end ISO build was run for this round: it needs an elevated session
  and a Windows ISO. Everything below that level is covered by the test suite.

---
## [26.09.2026] - Ultimate Edition Initial Build

### Overview
Complete rearchitecture of the tiny11builder ecosystem, combining the best
improvements from 14+ reference forks while fixing bugs inherited from the
NairoDorian base. Built using a research-then-build workflow: all reference
forks were cloned into `repos/` and studied (reforged + revamped prioritized).

### Added

#### Modular Architecture
- **`lib/tiny11utils.psm1`** — 45 utility functions extracted into a shared module
  (inspired by the revamped fork's `lib/tiny11utils.psm1`)
- **`lib/tiny11gui.psm1`** — Windows Forms GUI module (ported from the reforged
  fork's `tiny11gui.psm1`)
- **`lib/AdjPriv.cs`** — C# privilege helper reference for TrustedInstaller
  ownership escalation (from reforged/rearmed forks)
- **`lib/tiny11utils.psd1`**, **`lib/tiny11gui.psd1`** — Module manifests for
  proper PowerShell module integration

#### Builder Script Enhancements (`tiny11maker.ps1`)
- **Presets system** (`-Preset` parameter) with 4 profiles: Default, Gaming,
  Minimal-VM, PrivacyPlus (from namnguyen97x/tiny-auto-builder)
- **Interactive package selector** (`-Custom`) via `Show-PackageSelector` with
  console TUI (from vinisebold/revamped, zPoche v2)
- **Dry-run mode** (`-DryRun`) to preview without modifying the image
- **Configurable compression** (`-Compress recovery|fast|none`)
- **Fast mode** (`-Fast`) to skip DISM component cleanup
- **Zero-touch install** (`-ZeroTouch`) with dynamic autounattend.xml generation
- **Low-RAM profile** (`-LowRam`) for 1 GB-class machines
- **Keep/Remove flags** (`-KeepApps`) for custom package overrides
- **Auto ISO mounting** — accepts either a drive letter or an `.iso` file path
  (auto-mounts with `Mount-DiskImage`)
- **Auto-download oscdimg.exe** if Windows ADK is not installed
- **Auto-download autounattend.xml** if missing (from reforged)
- **Stale-mount cleanup** — cleans up previous scratch directories before building
- **ISO auto-ejection** — ejects the source ISO after build when auto-mounted
- **Robocopy** for efficient ISO file copying
- **Build summary** with elapsed time, ISO size, apps removed, and warning count
- **NTFS filesystem verification** for the scratch disk
- **Scratch disk space validation** (≥ 1.5× image size)

#### Hardened TaskCache Cleanup (from revamped)
- **ACL takeover** of the `ScheduleTaskCache` registry key before deletion
  (takes ownership from TrustedInstaller)
- **Version-gated TaskCache GUIDs** — different GUID sets for 24H2 builds vs
  older builds (per PR #289 from the revamped fork)
- **Safe task file deletion** — removes both task definition files AND
  TaskCache registry entries

#### Privilege Escalation
- **C#-backed `Enable-Privilege`** via inline Add-Type code (AdjPriv.cs) for
  `SeTakeOwnershipPrivilege`, `SeSecurityPrivilege`, etc.
  (from revamped/reforged)

#### Emergency Cleanup Trap
- **`trap` block** guarantees registry hives are unloaded and mount points
  are cleaned up on any error (from revamped/zPoche v2)
- **`Invoke-SafeDismountImage`** — safe wrapper around `Dismount-WindowsImage`
- **`Invoke-SafeOfflineRegistryUnload`** — safe wrapper around `reg.exe Unload`
- **`Invoke-ScriptCleanupOnFailure`** — guaranteed cleanup of scratch dirs
- **Tracked registry hives** — `Invoke-RegLoad`/`Invoke-RegUnload` track
  loaded hives for safe cleanup

#### GUI Mode (`tiny11gui.ps1`)
- **Windows Forms wizard** with two-stage flow: mount mode → edition selection
  (from reforged)
- **Splash screen** with application icon and version info
- **Auto-detection** of mounted drives containing Windows setup images
- **Auto-elevation** — self-relaunches as admin if not elevated
- **Execution policy fix** — prompts to set Bypass if restricted

#### Core Builder (`tiny11Coremaker.ps1`)
- **Bug fixes** from the NairoDorian base:
  - Fixed `$ScratchDisk` variable error in registry loading section
  - Fixed `"$mainOSDrive\scratchdir"` WinSxS rename path bug
  - Fixed `>null` → `> $null` output redirection
  - Fixed hardcoded `C:\scratchdir` path
- **Modular function integration** — uses `Set-RegistryValue`,
  `Remove-RegistryValue` from the utils module
- **Architecture-aware** WinSxS preservation list
- **WinRE removal**
- **Post-OOBE Windows Update blocking** via `SetupComplete.cmd` RunOnce entries
- **Windows Defender disabling**
- **ESD export** with recovery compression

#### Low-RAM Profile (`tiny11LegacyProfile.ps1`)
- 1 GB-class low-RAM profile with memory-saving tweaks
  (ported from bluecloud122/tiny11builder)

#### Enhanced `autounattend.xml`
- **RunSynchronous TPM/SecureBoot/RAM bypass** (from user129233) — critical for
  hardware compatibility during Windows Setup's windowsPE phase
- **Compact install** — reduced ISO size (from zPoche v2)
- **Local admin account** creation with AutoLogon
- **OOBE bypass** — skips EULA, network, account, privacy screens
- **FirstLogonCommands** — disables AutoLogon after first login, applies
  network bypass registry tweak
- **Multi-architecture** — amd64 + arm64 variants
- **Dynamic autounattend.xml generation** via `New-UnattendXml` function

#### Package Management
- **Externalized `removePackage.txt`** — human-readable, comment-supported
  (from revamped/zPoche v2)
- **Comprehensive package list** combining entries from DFwindows11_builder,
  zPoche v2, revamped, and 24H2-compatible IDs from keepitupkitty/SamHimmy
- **AI/Copilot packages** — removes Copilot, Recall, DevHome, WindowsAI (24H2+)
- **`docs/lista_de_apps.md`** — human-readable package reference
- **`docs/lista_simples_apps.txt`** — machine-readable removal list

#### Payload System
- **`payload/SetupComplete.cmd`** — runs after first login (from MOPELotus)
- **`payload/` subdirectories** — Fonts, DirectX, VCRedist, DotNet, PowerShell,
  Store, Wallpapers, XboxInstaller
- **`payload/README.md`** — documentation for payload structure

#### Browser Management
- **`Browsers/` directory** with browser installer scripts and documentation
  (from DFwindows11_builder)

#### CI/CD
- **`.github/workflows/ci.yml`** — validates PowerShell syntax, XML, and JSON
  (from YmlyZA)
- **`scripts/linter.ps1`** — PSScriptAnalyzer with high-signal rules only
- **`scripts/parse-check.ps1`** — static parse + function resolution check
- **`scripts/test-core-helpers.ps1`** — unit tests for utility functions
- **`scripts/test-core-helpers.ps1`** — AST-based tests for pure functions

#### Documentation
- **`README.md`** — comprehensive documentation with feature matrix, usage,
  parameters, presets, and per-fork attribution
- **`CHANGELOG.md`** — this file
- **`CONTRIBUTING.md`** — contributor guide

### Fixed
- **`$ScratchDisk` variable** — base script referenced undefined `$ScratchDisk`
  in the registry loading section
- **Syntax error** — `"Prevent installation of New Outlook":` (string + colon)
  instead of `Write-Output`
- **`>null`** — incorrect output redirection instead of `> $null`
- **WinSxS rename** — `-NewName` used full path instead of just the folder name
- **Hardcoded paths** — `C:\scratchdir` replaced with variables
- **`offlineClient` namespace** — added `xmlns:c` declaration for the
  `c:offlineClient` element in autounattend.xml
- **Autounattend.xml naming** — fixed inconsistency between `autounattend.xml` and
   `autounattend.xml` filenames

#### Post-Build Bug Fixes
- **`Apply-ExtendedTweaks -Preset`** — the function had no `-Preset` parameter;
  the maker and coremaker both called it with `-Preset $preset`, which would
  throw a parameter binding error at runtime. Added a `[hashtable]$Preset`
  parameter with backward-compatible key-name aliasing (DisableThirdParty→
  DisableThirdPartyTelemetry, EnableUltimatePerf→EnableUltimatePerformance).
- **`Show-PackageSelector -DefaultAll`** — the `-DefaultAll` parameter did not
  exist on the function and would throw a binding error. Removed the invalid
  argument (the function already defaults all items to selected).
- **`$SplashPictureBox` scope** — `tiny11gui.ps1` referenced this variable
  outside the function that created it (`$null`). Changed to a `Global`-scoped
  variable set inside `Invoke-MainForm`.
- **`autounattend.xml` cleanup** — both maker and coremaker unconditionally
  deleted the source `autounattend.xml` on cleanup. The maker now only removes
  it if it was auto-downloaded during this run; the coremaker never deletes it.
- **`$PSScriptRoot` in module** — `Resolve-AutounattendFile`, `Test-Prerequisites`,
  `Initialize-Oscdimg`, and the cleanup function used `$PSScriptRoot` which
  resolves to `lib/` when called from the module. Added `$repoRoot` (parent of
  `lib/`) and updated all data-file path references.
- **Module manifest `FunctionsToExport`** — 5 functions (`Get-MaxParallelJobs`,
  `Get-OptionalCapabilitiesToRemove`, `Get-AdditionalWindowsPackagesToRemove`,
  `Remove-BloatwareFiles`, `Apply-ExtendedTweaks`) were missing from the
  manifest, preventing proper module import via manifest.
- **`KeepApps` parameter semantics** — the parameter was `[string[]]` that added
  packages to the removal list, contradicting its name and the README ("skip
  ALL Appx package removal"). Changed to `[switch]` that skips all Appx removal.
  Updated help text, usage, and UAC-relaunch forwarding in both scripts.
- **Preset key mismatches** — `Resolve-BuildPreset` used `EnableUltimatePerf`
  and `DisableThirdParty` while `Apply-ExtendedTweaks` expected
  `EnableUltimatePerformance` and `DisableThirdPartyTelemetry`. `EnableDriverBlocklist`
  was missing from all presets entirely. Standardized all key names and added
  the missing field.
- **JSON preset loading** — presets were hardcoded as hashtables despite JSON
  files existing in `presets/`. The hardcoded defaults drifted from the JSON
  (e.g., Gaming had `BlockFirewallTelemetry = $false` but JSON had `true`).
  Rewrote `Resolve-BuildPreset` to load from JSON with hardcoded fallback.
- **Duplicate `Microsoft.YourPhone`** — appeared twice in `removePackage.txt`.
- **Coremaker UAC parameter forwarding** — the admin-relaunch block was missing
  `-Preset` (and the maker was missing `-Preset`, `-Keep`, `-Remove`, `-TimeZone`).
- **Coremaker build summary** — `Format-BuildSummary` was called with hardcoded
  `AppsRemoved=0` / `AppsTotal=0`. Added proper tracking of removed/total app
   counts and per-package error handling with warning increments.
- **GUI state variable scope** — `tiny11gui.psm1` variables (`$WINDOW_CLOSED`,
  `$MODE_SELECT`, `$SCREEN_STAGE`, `$AppVersion`) were at `Scope Script` (with
  `AllScope` removed) but `tiny11gui.ps1` (the parent scope) reads them without
  `$Script:` prefix. `AllScope` at Script scope does not propagate to the parent
  importing scope, so the GUI could never detect form closure, mode selection,
  or reset the screen stage. Changed all four to `Scope Global` and updated all
  `$Script:` references in module functions to `$Global:`. `$SplashPictureBox` was
  already Global and serves as the correct pattern.
- **Coremaker architecture validation** — `tiny11Coremaker.ps1` did not validate the
  detected `$architecture` (no null check after the detection loop). If architecture
  detection failed, the script would silently fall through to amd64 defaults,
  potentially producing a broken arm64 ISO. Added the same guard that
  `tiny11maker.ps1` already had.
- **`dism /English` quoting** — `tiny11maker.ps1` called `dism /English /Get-Intl` with
  unquoted arguments while `tiny11Coremaker.ps1` used `'/English'`. Standardized to
  `& 'dism' '/English' '/Get-Intl'` in the maker for cross-script consistency.

---

## [Base] NairoDorian/tiny11builder_2026

The upstream base is the ntdevlabs tiny11builder, which provides:
- `tiny11maker.ps1` — regular builder (serviceable image)
- `tiny11Coremaker.ps1` — core builder (ultra-trimmed for VMs)
- `autounattend.xml` — OOBE bypass answer file
- Release date: 09-07-25
