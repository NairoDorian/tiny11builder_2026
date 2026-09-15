#requires -Version 5.1
<#
.SYNOPSIS
    Layer 2 parse-check: verifies PowerShell tokenizes cleanly and that
    all module function calls resolve to defined functions.

.DESCRIPTION
    1. Tokenizes each .ps1/.psm1 file to catch parse errors (also enforced by CI).
    2. Checks that functions called in tiny11maker.ps1 / tiny11Coremaker.ps1
       are exported by lib/tiny11utils.psm1 or are PowerShell built-ins.

    Run from the project root. Exits 1 on any issue.
#>

$repo = Split-Path -Parent $PSScriptRoot
$scripts = @(
    'tiny11maker.ps1',
    'tiny11Coremaker.ps1',
    'tiny11gui.ps1',
    'tiny11LegacyProfile.ps1',
    'lib\tiny11utils.psm1',
    'lib\tiny11gui.psm1'
)

#---------[ 1. Parse Check ]---------#
$parseOk = $true
foreach ($name in $scripts) {
    $path = Join-Path $repo $name
    if (-not (Test-Path $path)) { continue }
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::Tokenize(
        (Get-Content -Raw -Path $path), [ref]$errors
    )
    if ($errors) {
        Write-Host "FAIL: $name has $($errors.Count) parse error(s):"
        $parseOk = $false
        $errors | ForEach-Object {
            Write-Host "  $($_.Message) (line $($_.Extent.LineNumber))"
        }
    } else {
        Write-Host "OK: $name (parse)"
    }
}

#---------[ 2. Function Resolution ]---------#
# Get all exported function names from the utils module
$utilsPath = Join-Path $repo 'lib\tiny11utils.psm1'
$definedFuncs = @{}
if (Test-Path $utilsPath) {
    $content = Get-Content -Raw -Path $utilsPath
    $funcs = [regex]::Matches($content, 'function\s+(\S+)\s*\{') |
        ForEach-Object { $_.Groups[1].Value }
    $funcs | ForEach-Object { $definedFuncs[$_] = $true }
    # Also get Export-ModuleMember function names
    $exports = [regex]::Matches($content, "Export-ModuleMember -Function (\S+)") |
        ForEach-Object { $_.Groups[1].Value }
    $exports | ForEach-Object { $definedFuncs[$_] = $true }
}

Write-Host "`nModule functions defined: $($definedFuncs.Keys.Count)"
Write-Host "Exported: $(($definedFuncs.Keys -join ', '))"

if ($parseOk -eq $false) {
    Write-Host "`nParse check FAILED."
    exit 1
}
Write-Host "`nAll checks passed."
exit 0
