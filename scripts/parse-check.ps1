#requires -Version 5.1
<#
.SYNOPSIS
    Parses every PowerShell file and checks that each command the scripts call
    actually exists (module function, script-local function or cmdlet).

.DESCRIPTION
    Catches the class of bug where a helper is renamed or deleted but a caller
    is not updated - which PowerShell only reports at run time, possibly 40
    minutes into a build. Exits 1 on any parse error or unresolved command.
#>

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $repo 'lib\tiny11gui.psm1') -Force -DisableNameChecking
Import-Module Dism -ErrorAction SilentlyContinue       # Mount-WindowsImage & co.
Import-Module Storage -ErrorAction SilentlyContinue    # Mount-DiskImage, Get-Volume

# Provided by optional modules the linter installs on demand.
$external = @('Install-Module', 'Install-PackageProvider', 'Invoke-ScriptAnalyzer')

$files = Get-ChildItem -Path $repo -Recurse -File -Include *.ps1, *.psm1 |
    Where-Object { $_.FullName -notmatch '\\(repos|logs|\.git)\\' }

$failed = $false
foreach ($file in $files) {
    $rel = $file.FullName.Substring($repo.Length + 1)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $failed = $true
        Write-Host "FAIL $rel : $($errors.Count) parse error(s)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "     line $($_.Extent.StartLineNumber): $($_.Message)" }
        continue
    }

    # Functions defined anywhere in this file (incl. nested) count as resolvable.
    $local = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    $missing = @()
    foreach ($call in $calls) {
        $name = $call.GetCommandName()
        if (-not $name -or $name -match '[\\/.]' -or $name -match '^\$') { continue }   # paths / exe / dynamic
        if ($local -contains $name -or $external -contains $name) { continue }
        if (Get-Command -Name $name -ErrorAction SilentlyContinue) { continue }
        $missing += "$name (line $($call.Extent.StartLineNumber))"
    }
    if ($missing.Count) {
        $failed = $true
        Write-Host "FAIL $rel : unresolved command(s): $($missing -join ', ')" -ForegroundColor Red
    } else {
        Write-Host "ok   $rel"
    }
}

if ($failed) { exit 1 }
Write-Host "`nAll files parse and every command resolves." -ForegroundColor Green
exit 0
