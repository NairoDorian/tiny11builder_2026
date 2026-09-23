#requires -Version 5.1
<#
.SYNOPSIS
    PSScriptAnalyzer pass over every script and module, high-signal rules only.

.DESCRIPTION
    Installs PSScriptAnalyzer for the current user when missing. Stylistic
    rules that conflict with an interactive, console-driven builder (Write-Host,
    plural nouns, verbs such as Invoke-/Build-, ShouldProcess on internal
    helpers) are suppressed. Exits 1 if any Warning/Error finding remains.

    Adapted from the YmlyZA/tiny11builder fork.
#>
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "Installing PSScriptAnalyzer (CurrentUser scope)..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module PSScriptAnalyzer

$ignore = @(
    'PSAvoidUsingWriteHost',                        # interactive console tool
    'PSUseShouldProcessForStateChangingFunctions',  # internal helpers, not user cmdlets
    'PSUseSingularNouns',
    'PSUseApprovedVerbs',                           # Build-ProcessArgumentString, Unload-*
    'PSAvoidUsingPlainTextForPassword',             # -Password feeds an answer file by design
    'PSAvoidUsingUsernameAndPasswordParams',
    'PSReviewUnusedParameter',                      # false positives with scriptblock closures
    'PSUseBOMForUnicodeEncodedFile',                # enforced by test-core-helpers.ps1 instead
    'PSAvoidUsingComputerNameHardcoded'             # -ComputerName names the PC being installed, not a remote host
)

$files = Get-ChildItem -Path $repo -Recurse -File -Include *.ps1, *.psm1 |
    Where-Object { $_.FullName -notmatch '\\(repos|logs|\.git)\\' }

$any = $false
foreach ($file in $files) {
    $rel = $file.FullName.Substring($repo.Length + 1)
    $findings = @(Invoke-ScriptAnalyzer -Path $file.FullName -Severity Warning, Error |
        Where-Object { $ignore -notcontains $_.RuleName })
    if ($findings.Count) {
        $any = $true
        Write-Host "===== $rel : $($findings.Count) finding(s) =====" -ForegroundColor Yellow
        $findings | Sort-Object Line | Format-Table Line, Severity, RuleName, Message -AutoSize -Wrap
    } else {
        Write-Host "ok   $rel"
    }
}

if ($any) { exit 1 }
exit 0
