# Payload Installation Directories

Files placed in these subdirectories are copied into the mounted image's
`$$\\setup\\scripts` folder by `SetupComplete.cmd` during first login.

## Structure

```text
payload/
├── SetupComplete.cmd              # Entry point (runs on first login)
├── README.md                       # This file
├── packages/                       # Place .cmd/.ps1 installers here
│   └── README.md
├── VCRedist/                       # Visual C++ Redistributables
├── DotNet/                         # .NET Desktop Runtimes
├── DirectX/                        # DirectX 9.0c redistributable
├── Fonts/                          # Custom fonts (.ttf/.ttc/.otf)
├── Wallpapers/                     # Custom wallpapers
├── PowerShell/                     # Latest PowerShell MSI
└── Store/                          # Microsoft Store for LTSC
    └── LTSC-Add-MicrosoftStore/
```

## Usage

1. Download the desired installer files into the appropriate subdirectory.
2. The build script copies these into the image via `SetupComplete.cmd`.
3. At first login, `SetupComplete.cmd` runs each installer silently.

VC++ 2005 redistributables are intentionally skipped because their legacy
installers can break unattended setup on current Windows builds (per MOPELotus fork).

Office is intentionally not bundled. Install it later with Office Tool Plus
or another preferred installer after Windows reaches the desktop.
