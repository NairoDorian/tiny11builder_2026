# Contributing to Tiny11 Builder — Ultimate Edition

Thank you for your interest in contributing! This fork was built by learning from
14+ reference projects (see [`README.md`](README.md)). Contributions that align
with the project's goals are welcome.

## Development Setup

1. **Windows 10/11** with administrator privileges
2. **PowerShell 5.1+** (or PowerShell 7 on Windows)
3. Windows ADK + WinPE Add-on (for `oscdimg.exe`)
4. Clone the repository:
   ```bat
   git clone https://github.com/NairoDorian/tiny11builder_2026
   cd tiny11builder_2026
   ```

## Reference Forks

All reference forks are kept in the `repos/` directory for study. This directory
is gitignored — it's for local reference only. When studying a new fork:

1. Clone it into `repos/` using a descriptive name (e.g., `repos/author_forkname`)
2. Review its README, scripts, and configuration files
3. Extract applicable improvements into the ultimate fork

## Code Style

- Use **`Write-Host`** for console output (this is an interactive builder)
- Use **`Write-Output`** for data that might be piped
- Use **`Write-Warning`** for non-fatal issues that should be counted
- Use **modular functions**: prefer `Set-RegistryValue`, `Remove-RegistryValue`,
  `Invoke-DismChecked` from `lib/tiny11utils.psm1` over raw `reg.exe` or `dism`
- Use **`$Script:` scope** for variables that need to persist across trap blocks
- Use **`trap` blocks** for emergency cleanup
- Use **`try/catch`** around DISM and registry operations

## Validation

Before submitting changes, run all validation scripts:

```powershell
# 1. Syntax check
.\scripts\parse-check.ps1

# 2. Lint (requires PSScriptAnalyzer)
.\scripts\linter.ps1

# 3. Unit tests
.\scripts\test-core-helpers.ps1
```

All three must pass. The CI workflow runs steps 1 and 2 automatically on push/PR.

## What to Contribute

- **New tweak entries**: Add registry keys to `removePackage.txt` or the tweak
  sections in `tiny11maker.ps1` / `tiny11Coremaker.ps1`
- **New presets**: Add a JSON file to `presets/` and update `Resolve-BuildPreset`
  in `lib/tiny11utils.psm1`
- **Package list updates**: Add/remove entries from `removePackage.txt` when
  new Windows 11 builds add/remove Appx packages
- **TaskCache GUIDs**: Update the version-gated GUID lists in
  `Get-TaskCacheGuidsForBuild` when Microsoft changes scheduled task GUIDs
- **Bug fixes**: The NairoDorian base had several bugs (see CHANGELOG.md) —
  additional fixes are always welcome

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/name`
3. Make your changes
4. Run all validation scripts
5. Commit with a clear message
6. Push and open a PR

## Attribution

When porting code from a reference fork, please note the source in:
- The commit message
- Code comments (e.g., `# from vinisebold/tiny11builder-revamped`)
- `CHANGELOG.md`

## Questions?

Open an issue or check the [README](README.md) for detailed documentation.
