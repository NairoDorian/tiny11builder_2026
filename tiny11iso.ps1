<#
.SYNOPSIS
    Get and recognize official Windows 11 ISOs, and prepare the build tools for offline use.

.DESCRIPTION
    Everything here is optional. A local ISO always builds, online or offline.

      -Verify <iso>     Hash a local ISO and look it up in Microsoft's published
                        "Verify your download" list (current public release, x64 and
                        ARM64). Informational only: a "not listed" or "offline"
                        result never blocks a build.
      -OpenPage         Open Microsoft's official Windows 11 download page in the
                        browser (pick a language there).
      -Url <link>       Download the direct .iso link copied from that page
                        (valid about 24 hours): progress, automatic resume of an
                        interrupted .part file, SHA-256 recognition. Nothing is
                        overwritten.
      -Auto             Fully automatic, no browser: resolve the current official
                        ISO straight from Microsoft's download service (same
                        handshake as the download page) and download it here
                        (resumable, SHA-256 checked). -Language picks it
                        (default: this Windows' language, English fallback).
      -ListHashes       Print Microsoft's current language -> SHA-256 table.
      -PrepareTools     Download/verify oscdimg (and wimlib on x64) now, so later
                        builds work fully offline.

    Lines starting with __TINY11_PROGRESS__ / __TINY11_RESULT__ are for the GUI.

.PARAMETER Verify
    Local .iso to hash and look up in Microsoft's published list (informational).

.PARAMETER Url
    Direct HTTPS .iso link copied from Microsoft's download page. Only Microsoft
    download hosts are accepted, on every redirect.

.PARAMETER Destination
    Folder (default: Downloads) or full .iso path for -Url / -Auto. Never
    overwritten.

.PARAMETER Sha256
    Optional expected SHA-256 for -Url; a mismatch rejects the file.

.PARAMETER OpenPage
    Open Microsoft's official Windows 11 download page in the default browser.

.PARAMETER ListHashes
    Print Microsoft's current language -> SHA-256 table.

.PARAMETER Architecture
    x64 or arm64 for -OpenPage / -ListHashes / -Auto (default: this PC's
    architecture).

.PARAMETER Language
    Language of the ISO for -Auto (e.g. 'English', 'German'), default: the
    language of this Windows, falling back to English.

.PARAMETER Auto
    Fully automatic download: no browser, no page to click. The script performs
    the same session handshake as Microsoft's download page, asks for the
    current Windows 11 release in the chosen language and downloads the
    official ISO (resumable, SHA-256 checked).

.PARAMETER PrepareTools
    Download and verify oscdimg (and wimlib on x64) now, for offline builds.

.PARAMETER Get
    Assisted download: opens Microsoft's page in the browser, then waits until the
    finished ISO appears in your Downloads folder (or a Microsoft link is copied,
    which is then downloaded here) and checks it. You choose the language and
    click Download on Microsoft's page.

.PARAMETER TimeoutMinutes
    How long -Get waits (default 45).

.EXAMPLE
    .\tiny11iso.ps1 -Verify D:\ISO\Win11_26H2_English_x64.iso
.EXAMPLE
    .\tiny11iso.ps1 -Get
.EXAMPLE
    .\tiny11iso.ps1 -Auto
.EXAMPLE
    .\tiny11iso.ps1 -Auto -Language German -Architecture x64 -Destination D:\ISO
.EXAMPLE
    .\tiny11iso.ps1 -OpenPage
.EXAMPLE
    .\tiny11iso.ps1 -Url 'https://software.download.prss.microsoft.com/...iso?t=...' -Destination D:\ISO
.EXAMPLE
    .\tiny11iso.ps1 -PrepareTools
#>
[CmdletBinding(DefaultParameterSetName = 'Verify')]
param(
    [Parameter(ParameterSetName = 'Verify', Mandatory = $true)][string]$Verify,
    [Parameter(ParameterSetName = 'Download', Mandatory = $true)][string]$Url,
    [Parameter(ParameterSetName = 'Download')][Parameter(ParameterSetName = 'Auto')][string]$Destination = (Get-UserDownloadsFolder),
    [Parameter(ParameterSetName = 'Download')][string]$Sha256,
    [Parameter(ParameterSetName = 'Page', Mandatory = $true)][switch]$OpenPage,
    [Parameter(ParameterSetName = 'List', Mandatory = $true)][switch]$ListHashes,
    [Parameter(ParameterSetName = 'Auto', Mandatory = $true)][switch]$Auto,
    [Parameter(ParameterSetName = 'Auto')][string]$Language,
    [Parameter(ParameterSetName = 'Page')][Parameter(ParameterSetName = 'List')][Parameter(ParameterSetName = 'Auto')][ValidateSet('x64', 'arm64')][string]$Architecture = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
    [Parameter(ParameterSetName = 'Tools', Mandatory = $true)][switch]$PrepareTools,
    [Parameter(ParameterSetName = 'Get', Mandatory = $true)][switch]$Get,
    [Parameter(ParameterSetName = 'Get')][ValidateRange(1, 240)][int]$TimeoutMinutes = 45
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\tiny11download.psm1') -Force -DisableNameChecking

function Write-IsoProgress { param([string]$Stage, [int]$Percent, [string]$Label)
    Write-Host ('__TINY11_PROGRESS__ ' + (@{ Stage = $Stage; Percent = $Percent; Label = $Label } | ConvertTo-Json -Compress)) }
function Write-IsoResult { param($Object) Write-Host ('__TINY11_RESULT__ ' + ($Object | ConvertTo-Json -Compress -Depth 4)) }

switch ($PSCmdlet.ParameterSetName) {
    'Verify' {
        $path = [IO.Path]::GetFullPath($Verify.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "ISO not found: $path" }
        Write-Host "Computing the SHA-256 of $path ..."
        $sha = Get-FileSha256WithProgress -Path $path -OnProgress { param($p) Write-IsoProgress -Stage verify -Percent $p -Label 'Computing SHA-256' }
        Write-Host "SHA-256: $sha"
        Write-Host "Checking Microsoft's published list..."
        $result = Test-WindowsIsoAuthenticity -Path $path -Sha256 $sha
        Write-Host $result.Message
        Write-IsoResult $result
    }
    'Download' {
        Write-Host "Downloading to $Destination ..."
        $report = {
            param($p)
            $view = Format-IsoDownloadProgress -Progress $p
            if ($p.Phase -eq 'verify') { Write-IsoProgress -Stage verify -Percent $view.Percent -Label 'Verifying the download (SHA-256)'; return }
            Write-IsoProgress -Stage download -Percent $view.Percent -Label $view.Text
        }
        $saved = Save-WindowsIsoDownload -Url $Url -Destination $Destination -ExpectedSha256 $Sha256 -OnProgress $report
        Write-Host "Saved $($saved.Path) ($('{0:N0}' -f $saved.Bytes) bytes)."
        if ($saved.Verification) { Write-Host $saved.Verification.Message }
        Write-IsoResult $saved
    }
    'Auto' {
        # Fully automatic: no browser, no page to click. Same handshake as the
        # download page, then the official ISO downloaded here.
        $culture = try { [Globalization.CultureInfo]::CurrentUICulture.Name } catch { '' }
        $languages = Get-OfficialWindowsIsoLanguages -Architecture $Architecture -OnStatus { param($t) Write-Host "  $t" }
        $link = Get-OfficialWindowsIsoDownloadLink -Languages $languages -Language ([string]$Language) -Culture $culture -OnStatus { param($t) Write-Host "  $t" }
        if ($Language -and $link.Language -ne $Language) {
            Write-Host "Note: Microsoft does not currently offer '$Language'; using '$($link.Language)' instead."
        }
        Write-Host "Official ISO: $($link.FileName)"
        if ($link.Description) { Write-Host "Microsoft describes it as: $($link.Description)" }
        $report = {
            param($p)
            $view = Format-IsoDownloadProgress -Progress $p
            if ($p.Phase -eq 'verify') { Write-IsoProgress -Stage verify -Percent $view.Percent -Label 'Verifying the download (SHA-256)'; return }
            Write-IsoProgress -Stage download -Percent $view.Percent -Label $view.Text
        }
        $saved = Save-WindowsIsoDownload -Url $link.Url -Destination $Destination -ExpectedSha256 $link.Sha256 -OnProgress $report
        Write-Host "Saved $($saved.Path) ($('{0:N0}' -f $saved.Bytes) bytes)."
        if ($saved.Verification) { Write-Host $saved.Verification.Message }
        Write-IsoResult $saved
    }
    'Page' {
        $page = Get-OfficialIsoPage -Architecture $Architecture
        Write-Host "Opening $page"
        Start-Process $page
    }
    'Get' {
        # Assisted: Microsoft's page in the person's browser, then automatic pickup.
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $folder = Get-UserDownloadsFolder
        $clipboardAtStart = try { Get-Clipboard -Raw -ErrorAction Stop } catch { '' }
        $baseline = @(Get-ChildItem -LiteralPath $folder -Filter '*.iso' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $sizes = @{}
        Start-Process (Get-OfficialIsoPage -Architecture $arch)
        Write-Host "Microsoft's page is open in your browser ($arch). Choose the multi-edition ISO and your language, then click Download."
        Write-Host "Waiting for the finished ISO in $folder (or a copied Microsoft link). Press Ctrl+C to stop."
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        $found = $null
        while (-not $found -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $clip = try { Get-Clipboard -Raw -ErrorAction Stop } catch { $null }
            if ($clip -eq $clipboardAtStart) { $clip = $null }
            $found = Find-OfficialIsoHandoff -ClipboardText $clip -Baseline $baseline -Folder $folder -SizeMemory $sizes
        }
        if (-not $found) { throw "No finished ISO appeared in $folder within $TimeoutMinutes minutes." }
        if ($found.Kind -eq 'Link') {
            Write-Host 'Microsoft link copied: downloading it here (resumable, SHA-256 checked)...'
            & $PSCommandPath -Url $found.Url -Destination $folder
            exit $LASTEXITCODE
        }
        Write-Host "Found $($found.Path); checking it against Microsoft's published list..."
        & $PSCommandPath -Verify $found.Path
        exit $LASTEXITCODE
    }
    'List' {
        $catalog = Get-WindowsIsoHashCatalog -Architecture $Architecture
        if (-not @($catalog.Entries).Count) { throw "Microsoft's hash list could not be read: $($catalog.Errors -join '; ')" }
        $catalog.Entries | Format-Table Release, Architecture, Language, Sha256 -AutoSize | Out-String -Width 200 | Write-Host
        Write-IsoResult $catalog
    }
    'Tools' {
        Import-Module (Join-Path $PSScriptRoot 'lib\tiny11utils.psm1') -Force -DisableNameChecking
        $oscdimg = Initialize-Oscdimg
        $wimlib = $null
        try { $wimlib = Initialize-Wimlib } catch { Write-Warning "wimlib: $($_.Exception.Message) DISM will be used for compression instead." }
        $ready = Get-BuildToolReadiness
        Write-Host $ready.Summary
        Write-IsoResult ([pscustomobject]@{ Oscdimg = $oscdimg; Wimlib = $wimlib; Summary = $ready.Summary })
    }
}
exit 0
