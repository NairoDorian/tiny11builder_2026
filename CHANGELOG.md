# Changelog

All notable changes to the Tiny11 Builder Ultimate Edition are documented here.
This project is built from **NairoDorian/tiny11builder_2026** as the base,
incorporating improvements from 14+ community forks.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
- **Zero-touch install** (`-ZeroTouch`) with dynamic autoundate.xml generation
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
- **Dynamic autoundate.xml generation** via `New-UnattendXml` function

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
  `c:offlineClient` element in autoundate.xml
- **Autoundate.xml naming** — fixed inconsistency between `autoundate.xml` and
  `autounattend.xml` filenames

---

## [Base] NairoDorian/tiny11builder_2026

The upstream base is the ntdevlabs tiny11builder, which provides:
- `tiny11maker.ps1` — regular builder (serviceable image)
- `tiny11Coremaker.ps1` — core builder (ultra-trimmed for VMs)
- `autounattend.xml` — OOBE bypass answer file
- Release date: 09-07-25
