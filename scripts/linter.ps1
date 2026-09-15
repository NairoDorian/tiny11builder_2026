#requires -Version 5.1
<#
.SYNOPSIS
    Layer 1 lint of the tiny11 builder scripts with PSScriptAnalyzer.

.DESCRIPTION
    Installs PSScriptAnalyzer for the current user if it is missing, then
    reports only high-signal findings: the stylistic rules listed in $ignore
    are suppressed because this is an interactive installer (it uses Write-Host
    deliberately, calls native tools by alias, etc.). Exits 1 if any
    high-signal finding remains.

    Adapted from the YmlyZA/tiny11builder fork.
#>
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "Installing PSScriptAnalyzer (CurrentUser scope)..."
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}
Import-Module PSScriptAnalyzer

# Rules intentionally ignored - all stylistic, not correctness.
$ignore = @(
    'PSAvoidUsingWriteHost',
    'PSUseShouldProcessForStateChangingFunctions',
    'PSAvoidUsingCmdletAliases',
    'PSUseSingularNouns',
    'PSAvoidTrailingWhitespace',
    'PSUseApprovedVerbs',
    # New-UnattendXml intentionally takes a username/password and writes a plaintext
    # password into the generated answer file (throwaway test images) - by design.
    'PSAvoidUsingUsernameAndPasswordParams',
    'PSAvoidUsingPlainTextForPassword'
)

$any = $false
foreach ($name in 'tiny11maker.ps1', 'tiny11Coremaker.ps1') {
    $path = Join-Path $repo $name
    if (-not (Test-Path $path)) { Write-Host "skip: $name not found"; continue }

    $findings = Invoke-ScriptAnalyzer -Path $path -Severity Warning, Error |
        Where-Object { $ignore -notcontains $_.RuleName }

    Write-Host "===== $name : $($findings.Count) high-signal finding(s) ====="
    if ($findings) {
        $any = $true
        $findings | Sort-Object Line | Format-Table Line, Severity, RuleName, Message -AutoSize -Wrap
    } else {
        Write-Host "       none (stylistic rules suppressed)"
    }
}

if ($any) { exit 1 }
