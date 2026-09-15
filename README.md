# Tiny11 Builder — Ultimate Edition (2026)

> The ultimate Tiny11 builder fork, combining the best improvements from 14+ reference forks.
> Built on [NairoDorian/tiny11builder_2026](https://github.com/NairoDorian/tiny11builder_2026) as the base,
> enhanced with hardening, modular architecture, GUI, and engineering safeguards from the
> reforged, revamped, v2, and many other community forks.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [GUI Mode (tiny11gui.ps1)](#gui-mode)
  - [Console Mode (tiny11maker.ps1)](#console-mode)
  - [Core / Ultra-Trimmed (tiny11Coremaker.ps1)](#core-mode)
  - [Low-RAM Profile (tiny11LegacyProfile.ps1)](#low-ram-profile)
- [Parameters](#parameters)
- [Build Profiles](#build-profiles)
- [Removed Packages](#removed-packages)
- [Registry Tweaks](#registry-tweaks)
- [Directory Structure](#directory-structure)
- [Project Layout](#project-layout)
- [CI/CD](#cicd)
- [Credits](#credits)

---

## Features

This fork incorporates improvements from the following reference projects (in `repos/`):

| Fork | Key Contributions |
|------|-------------------|
| **NairoDorian/tiny11builder_2026** | Base: two-script architecture (maker + coremaker), autoundate.xml |
| **bedlaj/tiny11builder** | Original ntdevlabs/tiny11builder — foundational debloat + registry tweaks |
| **chrisGrando/tiny11maker-reforged** | Windows Forms GUI, modular design, LAUNCH_TINY11.bat launcher, auto-ISO download, version tracking |
| **vinisebold/tiny11builder-revamped** | lib/tiny11utils.psm1 backbone, C# privilege escalation (AdjPriv.cs), TaskCache ACL takeover, version-gated GUIDs, emergency cleanup trap, interactive package selector |
| **zPoche/tiny11builder-v2** | Multi-arch (amd64 + ARM64), -Custom/-DryRun/-Compress/-Fast flags, pre-flight validation, scratch disk checks, robocopy ISO copy, dynamic autoundate patching, stale-mount cleanup |
| **YmlyZA/tiny11builder** | CI workflow, -Keep/-Remove utility flags, -ZeroTouch auto-install, -LOWRAM profile, build summary with stats |
| **prismatecas-ui/tiny11builder** | WPF-style GUI, smart detection, granular app control docs |
| **MOPELotus/tiny11builder** | Lotus profile with local admin, extensive privacy settings, payload/ system, SetupComplete.cmd |
| **DFwindows11_builder** | Browser management (Browsers/), comprehensive removePackage.txt |
| **user129233/tiny11builder** | Enhanced unattended.xml (compact install, RunSynchronous bypass, FirstLogonCommands) |
| **bluecloud122/tiny11builder** | tiny11LegacyProfile.ps1 (1 GB-class low-RAM profile) |
| **keepitupkitty/tiny11builder** | Latest Appx package IDs (24H2-compatible) |
| **SamHimmy/tiny11builder** | Latest Appx package IDs |
| **AhmedLolyProductions/Loly11** | Additional package removal entries |
| **namnguyen97x/tiny-auto-builder** | Preset system (default/gaming/minimal-vm/privacy-plus) |

### Core Improvements

- **Modular architecture**: Shared utility module (`lib/tiny11utils.psm1`) with C#-backed privilege
  escalation (`AdjPriv.cs` pattern via inline C#) and GUI module (`lib/tiny11gui.psm1`)
- **Windows Forms GUI** (`tiny11gui.ps1`): Two-stage wizard for ISO/drive selection and edition
  selection, real-time splash screen, auto-drive detection
- **Engineering safeguards**: Pre-flight validation (image index, scratch disk NTFS, free space ≥
  1.5× image size), DISM exit-code assertion (`Assert-CommandExitCode`), tracked registry
  hive loading/unloading with safe unload wrappers
- **TaskCache ACL takeover**: Takes ownership of the ScheduleTaskCache registry key before
  deleting scheduled-task entries (version-gated GUIDs for 24H2 vs older)
- **Version-gated logic**: Conditional package removal and task GUIDs based on build version
  (e.g., `SuggestedApps` removal only on non-24H2 builds)
- **Multi-architecture support**: Detects host architecture and selects the correct
  `autounattend.xml` (amd64 vs arm64)
- **Emergency cleanup trap**: `trap` block guarantees registry hives are unloaded and mount
  points are cleaned up on any error
- **Enhanced autounattend.xml**: RunSynchronous TPM/SecureBoot/RAM bypass (user129233 fork),
  compact install, local admin + AutoLogon, FirstLogonCommands
- **Dynamic autoundate.xml**: Patches the image index into the answer file and supports
  custom user/password/timezone
- **Auto ISO mounting**: Accepts an ISO file path (auto-mounts) or a mounted drive letter
- **Stale mount cleanup**: Cleans up previous scratch directories before building
- **ISO auto-ejection**: Ejects the source ISO after the build (when auto-mounted)
- **Robocopy**: Uses robocopy for efficient ISO file copying

### Build Flags

| Flag | Description |
|------|-------------|
| `-ISO <path>` | Path to Windows 11 ISO file **or** a mounted drive letter (e.g. `D:`) |
| `-Index <N>` | Image index to use from install.wim/esd (auto-selected on first eligible if omitted) |
| `-Profile <LOWRAM\|Legacy>` | Use a reduced tweak/profile mode |
| `-Custom` | Interactive console menu to select which apps to remove |
| `-DryRun` | Preview without modifying the image (no mount, no tweaks) |
| `-Compress <recovery\|max\|fast\|none>` | ESD compression level for the final image (default: `recovery`) |
| `-Fast` | Skip DISM component cleanup to speed up the build |
| `-KeepApps` | Keep all Appx packages (skip removal) |
| `-Remove` | Remove all Appx packages (default behavior) |
| `-ZeroTouch` | Generate a zero-touch autoundate.xml with local admin + AutoLogon |
| `-Yes` | Skip all confirmation prompts (non-interactive) |
| `-User <name>` | Local admin account username for autoundate.xml |
| `-Password <pw>` | Local admin account password for autoundate.xml |
| `-TimeZone <tz>` | Time zone for autoundate.xml (default: `UTC`) |
| `-SCRATCH <drive>` | Override the scratch disk drive letter |
| `-Preset <name>` | Build preset: Default, Gaming, Minimal-VM, PrivacyPlus |
| `-Language <lcid>` | Override language detection |

---

## Prerequisites

- **Windows 10/11** (x64 or ARM64) with administrator privileges
- **Windows ADK** + **WinPE Add-on** (for `oscdimg.exe`)
  - Auto-detects ADK path via registry (`KitsRoot10` / `WinSDKPath`)
  - Falls back to Microsoft-hosted download if not found
- **PowerShell 5.1+** (or PowerShell 7 on Windows)
- **~35 GB free disk space** on the system drive
- **~20 GB free** on a scratch disk (must be NTFS, with at least 1.5× the image size free)
- **Internet access** (for downloading oscdimg.exe if ADK is not installed)
- A **Windows 11 ISO** (from Microsoft's official site)

---

## Quick Start

### GUI Mode (Recommended for interactive use)
```bat
LAUNCH_TINY11.bat
```

### Console Mode (Regular build)
```bat
LAUNCH_TINY11.bat
```
Or directly:
```powershell
.\tiny11maker.ps1 -ISO "D:\sources\install.esd" -Index 1 -Yes
.\tiny11maker.ps1 -ISO "C:\iso\Windows11.iso" -Yes
.\tiny11maker.ps1 -ISO "D:" -Compress recovery -Yes
```

### Core Mode (Ultra-trimmed for VMs)
```powershell
.\tiny11Coremaker.ps1 -ISO "D:\sources\install.esd" -Yes
```

---

## Usage

### GUI Mode

`tiny11gui.ps1` provides an interactive Windows Forms wizard:

1. **Stage 1 - Mount Mode**: Choose to browse for an ISO file or select an already-mounted drive
2. **Stage 2 - Edition Selection**: Select the Windows 11 edition (Home, Pro, etc.)
3. The wizard then launches the appropriate builder script with the chosen parameters

The GUI auto-detects mounted drives and supports real-time log monitoring.

### Console Mode

```powershell
.\tiny11maker.ps1 -ISO "path:\to\install.esd" -Index 1 -Profile LOWRAM
```

The script will:
1. Validate prerequisites (ADK, disk space, NTFS)
2. Clean up stale mounts
3. Copy the ISO contents to a scratch directory (using robocopy)
4. Mount the install image
5. Remove selected Appx packages (or all by default)
6. Apply all registry tweaks (tweaks, privacy, Edge, OneDrive, OOBE)
7. Take ownership of and clean TaskCache registry entries
8. Perform DISM cleanup (unless `-Fast`)
9. Dismount and export the image as ESD (with configurable compression)
10. Mount and patch boot.wim (system requirements bypass)
11. Copy the (patched) autoundate.xml
12. Create the bootable ISO

### Core Mode

`tiny11Coremaker.ps1` is the aggressive builder for virtual machines:
- Removes system packages (language features, IE, WordPad, TabletPC, etc.)
- Removes WinRE
- Trims WinSxS (preserving essentials)
- Removes Edge and OneDrive entirely
- Applies all registry tweaks
- Post-OOBE Windows Update blocking via `SetupComplete.cmd`
- Disables Windows Defender
- ESD export with recovery compression
- ISO creation

### Low-RAM Profile

The low-RAM profile (`tiny11LegacyProfile.ps1`) is automatically applied when `-Profile LOWRAM` is specified. It applies additional memory-saving tweaks ideal for 1-2 GB RAM VMs:
- Disables WinSearch service
- Disables SysMain service
- Disables WSearch journal
- Reduces UI animations and visual effects
- Disables various background tasks and services

---

## Parameters

| Parameter | Description |
|-----------|-------------|
| `ISO` | Path to ISO file or mounted drive letter |
| `Index` | Image index (auto-selected if omitted) |
| `Profile` | `LOWRAM` or `Legacy` |
| `Custom` | Interactive package selector |
| `DryRun` | Preview only (no changes) |
| `Compress` | `recovery`, `max`, `fast`, or `none` |
| `Fast` | Skip DISM cleanup |
| `Keep` | Keep all packages |
| `Remove` | Remove all packages |
| `ZeroTouch` | Zero-touch autoundate.xml |
| `Yes` | Non-interactive |
| `User` | Admin username |
| `Password` | Admin password |
| `TimeZone` | Time zone (default UTC) |
| `SCRATCH` | Override scratch disk |
| `Language` | Override language detection |

---

## Build Profiles

| Profile | Description | Target |
|---------|-------------|--------|
| **Standard** (default) | Full debloat + hardening + tweaks | Daily driver |
| **Core** (tiny11Coremaker) | Aggressive VM-focused trim | Virtual machines |
| **LowRAM** (`-Profile LOWRAM`) | Standard + memory-saving tweaks | 1-2 GB RAM VMs |
| **Legacy** | Reduced scope for older builds | Compatibility testing |

### Presets (`-Preset` flag, from namnguyen97x/tiny-auto-builder)

Presets control which optional debloat, privacy, and performance tweaks are applied.
Each preset is a JSON file in `presets/`.

| Preset | Description | Edge | Defender | Store | AI/Copilot | Perf |
|--------|-------------|------|----------|-------|------------|------|
| **Default** | Balanced debloat for daily use | Remove | Keep | Keep | Remove | Standard |
| **Gaming** | Low latency, maximum gaming perf | Remove | Keep | Keep | Remove | Ultimate + mouse accel off |
| **Minimal-VM** | Ultra-light for testing/lab VMs | Remove | Remove | Remove | Remove | Ultimate |
| **PrivacyPlus** | Maximum privacy/hardening (AME-inspired) | Remove | Remove | Keep | Remove | Fast shutdown |

```powershell
.\tiny11maker.ps1 -ISO D -SCRATCH D -Preset Gaming -Yes
```

---

## Removed Packages

The package removal list is externalized in **`removePackage.txt`**. Each line is a package
family name. Comments start with `#`. Empty lines are ignored.

```powershell
# View the current list
Get-Content removePackage.txt

# Add a custom package to remove
"MyCompany.MyApp" | Add-Content removePackage.txt

# Remove a package from the list
(Get-Content removePackage.txt) -notmatch "MyCompany.MyApp" | Set-Content removePackage.txt
```

See `docs/lista_de_apps.md` for a human-readable description of all removed packages.

---

## Registry Tweaks

All registry tweaks are applied offline to the mounted `SOFTWARE` and `SYSTEM` hives. Key
categories:

- **System Requirements**: Bypass TPM, Secure Boot, RAM, CPU, and storage checks
- **Appx Packages**: Force removal of staged packages
- **Sponsored Apps**: Disable Windows Spotlight, Start ads, OneDrive prompts
- **OOBE**: Skip privacy settings, EULA, account setup
- **Edge**: Remove Edge (Core), disable preloading
- **OneDrive**: Remove OneDrive (Core), disable file sync
- **Telemetry**: Disable DiagTrack, dmwmi, WNP, compatibility telemetry
- **Search**: Disable Search Highlights, Bing integration, web search
- **AI/Recall** (24H2+): Disable AIDataAnalysis, AICopilot, Recall
- **DevHome/Outlook/Teams/Copilot**: Disable pre-installation of these apps
- **TaskBar**: Center task icons (optional), small taskbar buttons
- **Explorer**: Remove 3D Objects, This PC entries; show hidden files
- **Delivery Optimization**: Disable P2P download
- **BitLocker**: Disable Device Encryption
- **Reserved Storage**: Disable
- **Chat**: Disable chat from taskbar
- **Windows Update**: Post-OOBE blocking (Core mode only)

---

## Directory Structure

```text
tiny11builder_26/
├── .github/
│   ├── FUNDING.yml
│   └── workflows/
│       └── ci.yml              # CI: syntax, lint, XML/JSON, unit tests
├── docs/
│   ├── lista_de_apps.md        # App removal reference
│   └── lista_simples_apps.txt  # Machine-readable package list
├── payload/
│   ├── README.md
│   ├── SetupComplete.cmd       # Post-login automation (MOPELotus fork)
│   ├── packages/               # Optional installer scripts
│   ├── VCRedist/               # VC++ redistributables
│   ├── DotNet/                 # .NET Desktop Runtime
│   ├── DirectX/                 # DirectX 9.0c
│   ├── Fonts/                   # Custom fonts
│   ├── Wallpapers/              # Custom wallpapers
│   ├── PowerShell/             # Latest PowerShell MSI
│   └── Store/                  # Microsoft Store (LTSC)
├── Browsers/
│   ├── README.md               # Browser management docs
│   ├── chrome_installer.cmd    # Silent Chrome installer
│   └── firefox_installer.cmd   # Silent Firefox installer
├── lib/
│   ├── AdjPriv.cs              # C# privilege helper reference
│   ├── tiny11utils.psm1        # Shared utility functions (45 functions)
│   ├── tiny11utils.psd1        # Module manifest
│   ├── tiny11gui.psm1          # Windows Forms GUI module
│   └── tiny11gui.psd1          # Module manifest
├── presets/
│   ├── default.json            # Balanced debloat (namnguyen97x fork)
│   ├── gaming.json             # Gaming optimization
│   ├── minimal-vm.json         # Ultra-light VM
│   └── privacy-plus.json       # Maximum privacy/hardening
├── resources/
│   ├── T11M_icon.ico           # Application icon
│   └── T11M_splash.png         # Splash screen
├── repos/                      # Reference forks (gitignored)
├── scripts/
│   ├── linter.ps1              # PSScriptAnalyzer lint
│   ├── parse-check.ps1         # Parse + function resolution check
│   └── test-core-helpers.ps1   # Unit tests for utility functions
├── .gitignore
├── LICENSE
├── CHANGELOG.md                # Version history
├── CONTRIBUTING.md             # Contributor guide
├── LAUNCH_TINY11.bat           # Admin-check launcher
├── Run.bat                     # UAC elevation wrapper
├── tiny11maker.ps1             # Main builder script
├── tiny11Coremaker.ps1         # Core / ultra-trimmed builder
├── tiny11gui.ps1               # GUI entry point
├── tiny11LegacyProfile.ps1     # Low-RAM profile
├── removePackage.txt           # Externalized package list
├── autounattend.xml            # Enhanced OOBE answer file
├── autounattend-arm64.xml      # ARM64 answer file
└── README.md                   # This file
```

---

## Project Layout

```
                         ┌──────────────┐
                         │  tiny11gui.ps1  │ ◄── GUI entry point
                         │  (WinForms)    │
                         └──────┬─────────┘
                                │ launches
                ┌───────────────┴───────────────┐
                ▼                               ▼
       ┌──────────────┐              ┌─────────────────┐
       │ tiny11maker   │              │ tiny11Coremaker │
       │     .ps1      │              │      .ps1       │
       │ (Standard)    │              │ (Core/VM)       │
       └──────┬────────┘              └────────┬────────┘
              │ imports                         │ imports
              ▼                                 ▼
       ┌──────────────────────────────────────────┐
       │        lib/tiny11utils.psm1               │
       │  (DISM helpers, registry, privileges,    │
       │   ISO handling, pre-flight checks)        │
       └──────────────────────────────────────────┘
```

---

## Scripts

Validation and testing scripts in `scripts/` (from YmlyZA fork):

| Script | Purpose |
|--------|---------|
| `scripts/linter.ps1` | Runs PSScriptAnalyzer for code quality (if installed) |
| `scripts/parse-check.ps1` | Validates PowerShell syntax, function resolution, and module exports |
| `scripts/test-core-helpers.ps1` | Unit tests for utility functions (Format-BuildSummary, Test-RobocopySucceeded, New-UnattendXml, etc.) |

Run all validations:
```powershell
.\scripts\parse-check.ps1
.\scripts\test-core-helpers.ps1
```

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) validates:
1. **PowerShell syntax** for all `.ps1/.psm1` files (excludes `repos/`)
2. **Function resolution** (`scripts/parse-check.ps1`) — ensures all called functions exist
3. **Unit tests** (`scripts/test-core-helpers.ps1`) — validates utility functions
4. **XML validity** of `autounattend.xml` and `autounattend-arm64.xml`
5. **JSON validity** of preset files (`presets/*.json`)
6. **removePackage.txt** package count validation

---

## Credits

This ultimate fork was built by studying the following projects (all cloned in `repos/`):

| No. | Repository | Contributor |
|-----|-----------|-------------|
| 1 | ntdevlabs/tiny11builder | NairoDorian (base repo `tiny11builder_2026`) |
| 2 | DFveloper/DFwindows11_builder | DFveloper |
| 3 | bedlaj/tiny11builder | bedlaj |
| 4 | chrisGrando/tiny11maker-reforged | chrisGrando (Reforged) |
| 5 | vinisebold/tiny11builder-revamped | vinisebold (Revamped) |
| 6 | keepitupkitty/tiny11builder | keepitupkitty |
| 7 | user129233/tiny11builder | user129233 |
| 8 | prismatecas-ui/tiny11builder | prismatecas-ui |
| 9 | MOPELotus/tiny11builder | MOPELotus |
| 10 | AhmedLolyProductions/Loly11 | AhmedLolyProductions |
| 11 | zPoche/tiny11builder-v2 | zPoche (v2) |
| 12 | namnguyen97x/tiny-auto-builder | namnguyen97x |
| 13 | bluecloud122/tiny11builder | bluecloud122 |
| 14 | YmlyZA/tiny11builder | YmlyZA |
| 15 | SamHimmy/tiny11builder | SamHimmy |

**Research-first workflow**: All reference forks were cloned into `repos/` and studied before
building, with the reforged and revamped variants prioritized as the most significantly reworked.

---

## License

This project inherits the MIT license from the upstream tiny11builder projects.
See `LICENSE` file.
