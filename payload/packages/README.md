# Payload Packages

Place optional installer scripts here. Each `.cmd` or `.ps1` file in this
directory is automatically executed during the first Windows login via
`SetupComplete.cmd`.

Example installers:
- `dotnet-desktop-runtime.ps1` — .NET Desktop Runtime silent install
- `vc-redist-x64.ps1` — VC++ redistributable silent install
- `powerplan-balanced.cmd` — Apply a power plan
