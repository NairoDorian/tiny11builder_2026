<#
.SYNOPSIS
    Builds a trimmed-down, still serviceable Windows 11 ISO (tiny11).

.DESCRIPTION
    Tiny11 Builder - Ultimate Edition. Takes an official Windows 11 ISO
    (24H2 / 25H2 and older 22H2/23H2 media), exports the chosen edition,
    removes bloat apps, Edge, OneDrive and AI features, applies the offline
    registry catalog (data\tweaks.psd1), bakes in an answer file that skips
    the Microsoft-account/network OOBE and hardware checks, and writes a
    bootable BIOS+UEFI ISO plus a JSON manifest and SHA-256 file.

    The image stays serviceable: Windows Update, language packs and features
    keep working. For the non-serviceable VM variant use tiny11Coremaker.ps1.

    Pipeline
      1. validate options, resolve the source ISO/drive and the edition
      2. copy the ISO tree and export ONLY the chosen edition (works for
         install.wim and install.esd media)
      3. mount, remove provisioned apps / capabilities / Edge / OneDrive
      4. load the offline hives, apply the tweak catalog, remove telemetry tasks
      5. stage answer file + first-boot/first-logon scripts, component cleanup
      6. commit, export as install.esd (default) or install.wim
      7. patch boot.wim (hardware-check bypass, optional drivers)
      8. oscdimg -> ISO, manifest (.json) and checksum (.sha256)

.PARAMETER ISO
    Path to a Windows 11 .iso file, or the drive letter of a mounted ISO (E or E:).

.PARAMETER SCRATCH
    Drive letter for the work folders (default: the drive this script is on). NTFS only.

.PARAMETER Index
    Image index to build. See -Edition for selecting by name.

.PARAMETER Edition
    Edition name instead of -Index, e.g. "Pro", "Home", "Education", "Windows 11 Pro N".

.PARAMETER Preset
    Default, Gaming, Minimal-VM, PrivacyPlus, or a path to your own .json preset.

.PARAMETER Custom
    Pick interactively which provisioned apps to remove (and whether to remove Edge / OneDrive).

.PARAMETER KeepApps
    Skip provisioned-app removal entirely.

.PARAMETER Keep
    Optional utilities to keep: Terminal, Calculator, Notepad, Photos, Paint, Camera,
    SoundRecorder, StickyNotes, Clock, MediaPlayer, MoviesTV, SnippingTool.

.PARAMETER Remove
    Optional utilities to remove (same names as -Keep).

.PARAMETER PackageList
    Use this file instead of removePackage.txt.

.PARAMETER SkipTweak
    Tweak group ids from data\tweaks.psd1 to leave out (see docs/TWEAKS.md).

.PARAMETER LowRam
    Apply the low-RAM (1-2 GB) tweak group.

.PARAMETER DisableDriverUpdates
    Stop Windows Update from installing device drivers.

.PARAMETER EnableNetFx3
    Enable .NET Framework 3.5 from the ISO's sources\sxs folder.

.PARAMETER DriverPath
    Folder of .inf drivers injected into the install and setup images (e.g. Intel RST/VMD).

.PARAMETER Compress
    recovery (install.esd, smallest, default) | max | fast | none.

.PARAMETER Fast
    fast compression and no component cleanup (quick test builds).

.PARAMETER OutputIso
    Output ISO path (default: tiny11.iso next to this script).

.PARAMETER NoPrompt
    ISO boots straight into Setup without "Press any key to boot from CD".

.PARAMETER ZeroTouch
    Fully unattended install that WIPES DISK 0 (UEFI/GPT). VMs / test machines only.

.PARAMETER InteractiveOobe
    Do not create an account; OOBE asks for a local user name instead.

.PARAMETER User
    Local administrator created by the answer file (default: User).

.PARAMETER Password
    Password for -User (default: empty). Stored Base64-obfuscated, deleted after first sign-in.

.PARAMETER TimeZone
    Windows time zone id (default: UTC), e.g. "W. Europe Standard Time".

.PARAMETER Locale
    Language/region/keyboard, e.g. fr-FR. Skips those OOBE pages. Default: ask in OOBE.

.PARAMETER ComputerName
    Computer name (default: Windows picks DESKTOP-XXXXXXX).

.PARAMETER UnattendFile
    Use your own answer file instead of the generated one.

.PARAMETER Browser
    None (default), Firefox or Chrome: installed silently at first sign-in.

.PARAMETER Payload
    Stage payload\packages\*.cmd / *.ps1 to run once at first boot.

.PARAMETER DefenderExclusion
    Temporarily exclude the work folders from the host's Defender scanning (faster builds).

.PARAMETER DryRun
    Validate everything and print the build plan without modifying anything.

.PARAMETER Yes
    Non-interactive: never prompt (requires -ISO, and -Index/-Edition for multi-edition media).

.EXAMPLE
    .\tiny11maker.ps1 -ISO C:\iso\Win11_25H2.iso -Edition Pro -Yes

.EXAMPLE
    .\tiny11maker.ps1 -ISO E -Index 6 -Preset Gaming -Keep Paint,SnippingTool -Browser Firefox

.EXAMPLE
    .\tiny11maker.ps1 -ISO E -Edition Pro -ZeroTouch -NoPrompt -User Bob -Password "P@ss" -Locale en-GB -TimeZone "GMT Standard Time" -Yes

.EXAMPLE
    .\tiny11maker.ps1 -ISO E -DryRun

.NOTES
    Tiny11 Builder - Ultimate Edition (2026). Windows PowerShell 5.1, run as Administrator.
    Based on ntdevlabs/tiny11builder and 15 community forks (see README).
#>

#---------[ Parameters ]---------#
[CmdletBinding()]
param (
    [Parameter(Position = 0)][string]$ISO,
    [Parameter(Position = 1)][ValidatePattern('^[c-zC-Z]:?$')][string]$SCRATCH,
    [int]$Index,
    [string]$Edition,
    [string]$Preset = 'Default',
    [switch]$Custom,
    [switch]$KeepApps,
    [string[]]$Keep = @(),
    [string[]]$Remove = @(),
    [string]$PackageList,
    [string[]]$SkipTweak = @(),
    [switch]$LowRam,
    [switch]$DisableDriverUpdates,
    [switch]$EnableNetFx3,
    [string]$DriverPath,
    [ValidateSet('recovery', 'max', 'fast', 'none')][string]$Compress,
    [switch]$Fast,
    [string]$OutputIso,
    [switch]$NoPrompt,
    [switch]$ZeroTouch,
    [switch]$InteractiveOobe,
    [string]$User = 'User',
    [string]$Password = '',
    [string]$TimeZone = 'UTC',
    [string]$Locale,
    [string]$ComputerName,
    [string]$UnattendFile,
    [ValidateSet('None', 'Firefox', 'Chrome')][string]$Browser = 'None',
    [switch]$Payload,
    [switch]$DefenderExclusion,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$Script:Version = '2026.09'

if ($Help) {
    Get-Help -Full $PSCommandPath
    exit 0
}

#---------[ Module ]---------#
$utilsModulePath = Join-Path $PSScriptRoot 'lib\tiny11utils.psm1'
if (-not (Test-Path -Path $utilsModulePath -PathType Leaf)) {
    Write-Error "Required module not found: $utilsModulePath"
    exit 1
}
Import-Module -Name $utilsModulePath -Force -DisableNameChecking

#---------[ Normalise arguments ]---------#
# Arrays arrive as "a,b" when the script is started with -File (UAC relaunch,
# .bat launchers), so split every list parameter on commas.
$splitList = { param($v) @($v | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$Keep = & $splitList $Keep
$Remove = & $splitList $Remove
$SkipTweak = & $splitList $SkipTweak
if ($ISO) { $ISO = $ISO.Trim().Trim('"') }
if ($ISO -match '^[c-zC-Z]:?\\?$') { $ISO = $ISO.Substring(0, 1) }
if ($SCRATCH) { $SCRATCH = $SCRATCH.Substring(0, 1) }
$ScratchDisk = if ($SCRATCH) { "${SCRATCH}:" } else { (Split-Path -Qualifier $PSScriptRoot) }
if (-not $OutputIso) { $OutputIso = Join-Path $PSScriptRoot 'tiny11.iso' }
if ($ZeroTouch -and -not $PSBoundParameters.ContainsKey('NoPrompt')) { $NoPrompt = $true }

if ($ISO -match '^[c-zC-Z]$' -and $SCRATCH -and $ISO -ieq $SCRATCH) {
    throw "ISO source drive and SCRATCH drive must be different."
}
if ($Yes -and -not $ISO) { throw "-Yes requires -ISO (no interactive prompt available)." }

#---------[ Elevation ]---------#
$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Restarting Tiny11 image creator as administrator in a new window..."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath)
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        $value = $kv.Value
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $argList += "-$($kv.Key)" }
        } elseif ($value -is [array]) {
            if ($value.Count) { $argList += @("-$($kv.Key)", ($value -join ',')) }
        } elseif ("$value" -ne '') {
            $argList += @("-$($kv.Key)", "$value")
        }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'powershell.exe'
    $psi.Arguments = Build-ProcessArgumentString -Arguments $argList
    $psi.Verb = 'runas'
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit 0
}

#---------[ Validate options before touching anything ]---------#
$presetFlags = Resolve-BuildPreset -PresetName $Preset
$buildProfile = Resolve-BuildProfile -Compress $Compress -Fast:$Fast
$utilities = Resolve-OptionalUtilities -Keep $Keep -Remove $Remove
$flags = $presetFlags.Clone()
$flags['LowRam'] = [bool]$LowRam
$flags['DisableDriverUpdates'] = [bool]$DisableDriverUpdates
$flags['DisableWindowsUpdate'] = $false
$null = Get-TweakPlan -Flags $flags -Skip $SkipTweak      # throws on unknown -SkipTweak ids

$packageListPath = if ($PackageList) { $PackageList } else { Join-Path $PSScriptRoot 'removePackage.txt' }
foreach ($pathCheck in @(
        @{ Name = '-PackageList'; Path = $packageListPath },
        @{ Name = '-UnattendFile'; Path = $UnattendFile },
        @{ Name = '-DriverPath'; Path = $DriverPath })) {
    if ($pathCheck.Path -and -not (Test-Path -LiteralPath $pathCheck.Path)) {
        throw "$($pathCheck.Name): '$($pathCheck.Path)' not found."
    }
}
$outputDir = Split-Path -Parent $OutputIso
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) { throw "-OutputIso: folder '$outputDir' does not exist." }
if (-not $UnattendFile) {
    # Validates -User / -ComputerName / -Locale now rather than after 30 minutes of work.
    $null = New-UnattendXml -UserName $User -Password $Password -TimeZone $TimeZone -Locale $Locale `
        -ComputerName $ComputerName -ZeroTouch:$ZeroTouch -InteractiveOobe:$InteractiveOobe
}
if ($ZeroTouch) {
    Write-Warning "-ZeroTouch: the ISO will ERASE DISK 0 automatically during Setup. Use only on VMs / dedicated test machines."
}

#---------[ State for emergency cleanup ]---------#
$Script:buildWarnings = 0
$Script:transcriptStarted = $false
$Script:defenderExclusions = @()
$Script:source = $null
$workRoot = "$ScratchDisk\tiny11"
$mountDir = "$ScratchDisk\scratchdir"

trap {
    Write-Host ""
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray }
    Write-Warning "Cleaning up (unloading hives, discarding the mounted image)..."
    $isoToEject = if ($Script:source -and $Script:source.MountedByScript) { $Script:source.IsoPath } else { $null }
    Invoke-EmergencyCleanup -ScratchDisk $ScratchDisk -IsoImagePath $isoToEject -DefenderExclusions $Script:defenderExclusions
    if ($Script:transcriptStarted) { try { Stop-Transcript | Out-Null } catch { Write-Verbose 'Transcript already stopped.' } }
    exit 1
}

#---------[ Transcript & banner ]---------#
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'No transcript was running.' }
Start-Transcript -Path (Join-Path $logDir "tiny11_$(Get-Date -f yyyyMMdd_HHmmss).log") | Out-Null
$Script:transcriptStarted = $true
$buildStart = Get-Date
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal

$Host.UI.RawUI.WindowTitle = "Tiny11 image creator - Ultimate Edition $Script:Version"
Write-Host "=== Tiny11 image creator - Ultimate Edition $Script:Version ===" -ForegroundColor Cyan
Write-Host "    Preset: $Preset | Compression: $($buildProfile.Compress) | Output: $OutputIso"
Write-Host ""

#---------[ Pre-flight ]---------#
Test-Prerequisites
Clear-StaleBuildState
if ($SCRATCH) { $null = Test-ScratchDiskNtfs -ScratchPath $ScratchDisk }

#---------[ Source & edition ]---------#
$Script:source = Resolve-WindowsSource -IsoParameter $ISO
$DriveLetter = $Script:source.DriveLetter
$sourceImage = if (Test-Path "$DriveLetter\sources\install.wim") { "$DriveLetter\sources\install.wim" } else { "$DriveLetter\sources\install.esd" }
$sourceImages = @(Get-WindowsImage -ImagePath $sourceImage)
$imageIndex = Select-ImageIndex -Images $sourceImages -Index $Index -Edition $Edition -NonInteractive:$Yes
$info = Get-ImageInfo -ImagePath $sourceImage -Index $imageIndex
$architecture = $info.Architecture
$languageCode = $info.Language
Write-Host "Selected: [$imageIndex] $($info.Name) | $($info.DisplayVersion) build $($info.Version) | $architecture | $languageCode"
if ($info.Build -and $info.Build -lt 22000) {
    Write-Warning "Build $($info.Build) is not Windows 11. Continuing, but tweaks target Windows 11."
}
if ($architecture -notin 'amd64', 'arm64') { throw "Unsupported image architecture '$architecture'." }

$requiredBytes = Get-RequiredScratchBytes $info.SizeBytes
$space = Test-SufficientScratch $requiredBytes ([long](Get-PSDrive -Name $ScratchDisk.TrimEnd(':')).Free)
$oscdimg = Find-Oscdimg
$tweakPlan = Get-TweakPlan -Flags $flags -Skip $SkipTweak
$unattendMode = if ($UnattendFile) { "custom file $UnattendFile" }
                elseif ($ZeroTouch) { "ZERO-TOUCH (wipes disk 0), account '$User'" }
                elseif ($InteractiveOobe) { 'interactive OOBE (you create the account)' }
                else { "local admin '$User', online-account pages skipped" }

if ($DryRun) {
    Write-Host ""
    Write-Host "===== DRY RUN - nothing will be modified =====" -ForegroundColor Yellow
    Write-Host "  Source           : $sourceImage"
    Write-Host "  Edition          : [$imageIndex] $($info.Name) ($($info.Edition))"
    Write-Host "  Windows          : $($info.DisplayVersion), build $($info.Version), $architecture, $languageCode"
    Write-Host "  Preset           : $Preset"
    Write-Host "  App removal      : $(if ($KeepApps -or -not $flags.RemoveAppx) { 'skipped' } elseif ($Custom) { 'interactive' } else { "$(@(Read-PackageListFile $packageListPath).Count) prefixes from $(Split-Path $packageListPath -Leaf)" })"
    Write-Host "  Utilities kept   : $($utilities.KeptNames -join ', ')"
    Write-Host "  Edge / OneDrive  : remove Edge=$($flags.RemoveEdge) (WebView2 $(if ($flags.RemoveWebView) { 'removed' } else { 'kept' })), remove OneDrive=$($flags.RemoveOneDrive)"
    Write-Host "  Tweak groups     : $(($tweakPlan | ForEach-Object { $_.Id }) -join ', ')"
    Write-Host "  Answer file      : $unattendMode"
    Write-Host "  Browser / payload: $Browser / $(if ($Payload) { 'payload\packages' } else { 'none' })"
    Write-Host "  .NET 3.5 / drivers: $([bool]$EnableNetFx3) / $(if ($DriverPath) { $DriverPath } else { 'none' })"
    Write-Host "  Compression      : $($buildProfile.Compress) -> sources\$($buildProfile.ImageFileName); cleanup: $(-not $buildProfile.SkipCleanup)"
    Write-Host ("  Scratch space    : {0} GB free on {1}, ~{2} GB needed  [{3}]" -f $space.FreeGB, $ScratchDisk, $space.RequiredGB, $(if ($space.Ok) { 'OK' } else { 'INSUFFICIENT' }))
    Write-Host "  oscdimg          : $($oscdimg.Source) $(if ($oscdimg.Source -eq 'download') { '(will be downloaded, SHA-256 pinned)' } else { $oscdimg.Path })"
    Write-Host "  Output ISO       : $OutputIso$(if ($NoPrompt) { ' (no "press any key")' })"
    Write-Host "===== END DRY RUN =====" -ForegroundColor Yellow
    Dismount-WindowsSource -Source $Script:source
    Stop-Transcript | Out-Null
    if ($space.Ok) { exit 0 } else { exit 1 }
}

if (-not $space.Ok) {
    throw ("Not enough space on {0}: {1} GB free, ~{2} GB needed. Use -SCRATCH to pick another NTFS drive." -f $ScratchDisk, $space.FreeGB, $space.RequiredGB)
}
if ($DefenderExclusion) {
    $Script:defenderExclusions = @(Add-BuildDefenderExclusion -Path @($workRoot, $mountDir))
}

#---------[ Custom mode questions (asked up front, not mid-build) ]---------#
if ($Custom) {
    if ($flags.RemoveEdge) {
        $flags['RemoveEdge'] = (Read-Host 'Remove Microsoft Edge? [Y/n]') -notmatch '^(?i:n|no)$'
    }
    if ($flags.RemoveOneDrive) {
        $flags['RemoveOneDrive'] = (Read-Host 'Remove OneDrive? [Y/n]') -notmatch '^(?i:n|no)$'
    }
}

#---------[ Copy media & export the chosen edition ]---------#
Write-Host "Copying installation media (without the install image)..."
if (Test-Path $workRoot) { Remove-Item -Path $workRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$workRoot\sources" | Out-Null
Invoke-Robocopy -Source "$DriveLetter\" -Destination $workRoot -ExcludeFile @('install.wim', 'install.esd')

Write-Host "Exporting edition $imageIndex from $(Split-Path $sourceImage -Leaf) (this also handles ESD media)..."
$wimFilePath = "$workRoot\sources\install.wim"
Export-WindowsImage -SourceImagePath $sourceImage -SourceIndex $imageIndex -DestinationImagePath $wimFilePath -CompressionType fast | Out-Null
if (-not (Test-Path $wimFilePath)) { throw "Export of the selected edition failed: $wimFilePath was not created." }

Dismount-WindowsSource -Source $Script:source

#---------[ Mount install.wim ]---------#
Write-Host "Mounting the Windows image..."
$null = Initialize-ScratchWorkspace -ScratchRoot $ScratchDisk
Mount-WindowsImage -ImagePath $wimFilePath -Index 1 -Path $mountDir | Out-Null
Assert-MountedImage -MountPath $mountDir

#---------[ Apps, Edge, OneDrive, capabilities ]---------#
$apps = Invoke-AppRemovalStage -MountPath $mountDir -Flags $flags -Utilities $utilities -PackageListPath $packageListPath -Custom:$Custom -KeepApps:$KeepApps
$Script:buildWarnings += $apps.Failures

if ($flags.RemoveEdge) {
    Write-Host "Removing Microsoft Edge$(if ($flags.RemoveWebView) { ' and WebView2' })..."
    Remove-EdgeFiles -MountPath $mountDir -Architecture $architecture -IncludeWebView:([bool]$flags.RemoveWebView)
}
if ($flags.RemoveOneDrive) {
    Write-Host "Removing OneDrive..."
    Remove-OneDriveFiles -MountPath $mountDir
}
if ($flags.RemoveCapabilities) {
    $Script:buildWarnings += Invoke-CapabilityRemovalStage -MountPath $mountDir -LanguageCode $languageCode
}

#---------[ .NET 3.5 / drivers ]---------#
if ($EnableNetFx3) {
    Write-Host "Enabling .NET Framework 3.5 from sources\sxs..."
    try {
        Enable-WindowsOptionalFeature -Path $mountDir -FeatureName NetFx3 -All -Source "$workRoot\sources\sxs" -LimitAccess -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning ".NET 3.5 could not be enabled: $($_.Exception.Message)"
        $Script:buildWarnings++
    }
}
if ($DriverPath) {
    $driverCount = Add-ImageDrivers -MountPath $mountDir -DriverPath $DriverPath
    Write-Host "Injected $driverCount driver(s) into the install image."
}

#---------[ Offline registry ]---------#
$tweaks = Invoke-RegistryStage -MountPath $mountDir -Flags $flags -Skip $SkipTweak -RemovedPackages $apps.Removed
$Script:buildWarnings += $tweaks.Failures

#---------[ Answer file & first-boot scripts ]---------#
$unattendXml = if ($UnattendFile) {
    Set-UnattendImageIndex -Xml (Get-Content -Raw -LiteralPath $UnattendFile) -ImageIndex 1
} else {
    New-UnattendXml -Architecture $architecture -UserName $User -Password $Password -TimeZone $TimeZone `
        -Locale $Locale -ComputerName $ComputerName -ZeroTouch:$ZeroTouch -InteractiveOobe:$InteractiveOobe
}
Write-UnattendFile -Xml $unattendXml -Path "$mountDir\Windows\System32\Sysprep\unattend.xml"
$payloadFiles = Get-Tiny11PayloadFiles -Payload:$Payload -Browser $Browser
Install-ImagePayload -MountPath $mountDir -Commands $tweaks.FirstBoot -PackageFiles $payloadFiles.PackageFiles -FirstLogonFiles $payloadFiles.FirstLogonFiles

#---------[ Component cleanup, commit, export ]---------#
if ($buildProfile.SkipCleanup) {
    Write-Host "Skipping component cleanup (-Fast)."
} elseif (-not (Invoke-ComponentCleanup -MountPath $mountDir -NoResetBase:$EnableNetFx3)) {
    $Script:buildWarnings++
}
Write-Host "Committing and unmounting the Windows image..."
if (-not (Invoke-SafeDismountImage -Path $mountDir -Save)) {
    throw "Failed to commit/unmount the install image."
}
$null = Export-FinalInstallImage -WorkRoot $workRoot -BuildProfile $buildProfile

#---------[ boot.wim, answer file, ISO ]---------#
$Script:buildWarnings += Invoke-BootImageStage -WorkRoot $workRoot -ScratchRoot $ScratchDisk -DriverPath $DriverPath
Write-UnattendFile -Xml $unattendXml -Path "$workRoot\autounattend.xml"
$isoBytes = New-Tiny11Iso -WorkRoot $workRoot -OutputIso $OutputIso -Architecture $architecture `
    -Label "TINY11_$($info.DisplayVersion)_$($architecture.ToUpperInvariant())" -NoPrompt:$NoPrompt

$sha256 = Write-BuildManifest -IsoPath $OutputIso -Data @{
    builder     = "tiny11maker.ps1 $Script:Version"
    source      = @{ image = $sourceImage; index = $imageIndex; name = $info.Name; edition = $info.Edition; version = $info.Version; displayVersion = $info.DisplayVersion; architecture = $architecture; language = $languageCode }
    options     = @{ preset = $Preset; compress = $buildProfile.Compress; custom = [bool]$Custom; keep = $Keep; remove = $Remove; lowRam = [bool]$LowRam; disableDriverUpdates = [bool]$DisableDriverUpdates; netFx3 = [bool]$EnableNetFx3; drivers = [bool]$DriverPath; zeroTouch = [bool]$ZeroTouch; interactiveOobe = [bool]$InteractiveOobe; browser = $Browser; skipTweak = $SkipTweak }
    flags       = $flags
    removedApps = $apps.Removed
    tweakGroups = $tweaks.Applied
    warnings    = $Script:buildWarnings
}

#---------[ Cleanup & summary ]---------#
Write-Host "Cleaning up work folders..."
Remove-Item -Path $workRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue
if ($Script:defenderExclusions) { Remove-BuildDefenderExclusion -Path $Script:defenderExclusions }

Format-BuildSummary -Elapsed ((Get-Date) - $buildStart) -IsoBytes $isoBytes -IsoPath $OutputIso `
    -AppsRemoved $apps.Removed.Count -AppsTotal $apps.Total -Warnings $Script:buildWarnings `
    -Image "$($info.Name) $($info.DisplayVersion) ($architecture)" -Sha256 $sha256 | ForEach-Object { Write-Host $_ -ForegroundColor Green }

Stop-Transcript | Out-Null
if (-not $Yes) { Read-Host "Done. Press Enter to close" | Out-Null }
exit 0
