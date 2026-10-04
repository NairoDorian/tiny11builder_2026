#requires -Version 5.1
<#
.SYNOPSIS
    PSScriptAnalyzer pass over every script and module, high-signal rules only.

.DESCRIPTION
    Uses pinned PSScriptAnalyzer 1.25.0, cached in the project when missing. Stylistic
    rules that conflict with an interactive, console-driven builder (Write-Host,
    plural nouns, verbs such as Invoke-/Build-, ShouldProcess on internal
    helpers) are suppressed. Exits 1 if any Warning/Error finding remains.

    Adapted from the YmlyZA/tiny11builder fork.
#>
$repo = Split-Path -Parent $PSScriptRoot

$version = '1.25.0'
if (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object Version -eq $version) {
    Import-Module PSScriptAnalyzer -RequiredVersion $version
} else {
    $cache = Join-Path $repo "tools\PSScriptAnalyzer\$version"
    $manifest = Join-Path $cache 'PSScriptAnalyzer.psd1'
    if (-not (Test-Path -LiteralPath $manifest)) {
        $folder = Split-Path -Parent $cache
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $zip = Join-Path $folder "$version.zip"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/$version" -OutFile $zip -UseBasicParsing -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne '14E634C828EB98EFB9F40B2918BA90F139ED5ECCDF663A2A747736D996995D60') { throw 'PSScriptAnalyzer package failed its pinned SHA-256 check.' }
        Expand-Archive -LiteralPath $zip -DestinationPath $cache -Force -ErrorAction Stop
        Remove-Item -LiteralPath $zip -Force
    }
    Import-Module $manifest
}

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

# Limit traversal to source locations; build media can contain hundreds of
# thousands of files and must never be crawled by development checks.
$files = @(Get-ChildItem -LiteralPath $repo -File | Where-Object Extension -in '.ps1','.psm1') +
    @(Get-ChildItem -Path (Join-Path $repo 'lib'),(Join-Path $repo 'scripts') -Recurse -File -Include *.ps1,*.psm1)

$any = $false
foreach ($file in $files) {
    $rel = $file.FullName.Substring($repo.Length + 1)
    # PSScriptAnalyzer occasionally throws an internal NullReferenceException
    # (a race between rules); retry instead of failing the run on it.
    $findings = $null
    for ($attempt = 1; $attempt -le 3 -and $null -eq $findings; $attempt++) {
        try {
            $findings = @(Invoke-ScriptAnalyzer -Path $file.FullName -Severity Warning, Error -ErrorAction Stop |
                Where-Object { $ignore -notcontains $_.RuleName })
        } catch {
            if ($attempt -eq 3) { throw }
            Write-Host "     analyzer error on $rel (attempt $attempt), retrying: $($_.Exception.Message)"
        }
    }
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
