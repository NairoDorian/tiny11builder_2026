<#
.SYNOPSIS
    Builds tiny11 Core: the smallest possible Windows 11 image, for VMs and testing.

.DESCRIPTION
    Everything tiny11maker.ps1 does, plus:
      - removes component packages (IE, Media Player, handwriting/OCR/speech/TTS,
        Defender, WordPad, Steps Recorder, Math Input, extended wallpapers)
      - removes WinRE (no recovery environment / Reset this PC)
      - rebuilds WinSxS keeping only the servicing stack and core assemblies
      - disables Windows Update and Microsoft Defender
      - removes Edge including WebView2

    The result is NOT serviceable: no cumulative updates, language packs or
    optional features can be added afterwards. Use it for disposable VMs,
    CI runners and quick tests - never as a daily-driver OS.

.PARAMETER ISO
    Path to a Windows 11 .iso, or the drive letter of a mounted ISO.

.PARAMETER SCRATCH
    Drive letter for the work folders (default: the drive this script is on). NTFS only.

.PARAMETER Index
    Image index to build.

.PARAMETER Edition
    Edition name instead of -Index, e.g. "Pro".

.PARAMETER Preset
    Preset for the optional tweaks (default: Minimal-VM). Core always removes
    Edge, OneDrive and Defender and disables Windows Update regardless.

.PARAMETER EnableNetFx3
    Enable .NET Framework 3.5 (must happen at build time: the image cannot be
    serviced later). Interactive runs ask; -Yes runs default to no.

.PARAMETER OutputIso
    Output ISO path (default: tiny11core.iso next to this script).

.PARAMETER Help
    Show the full help.

.NOTES
    The remaining parameters (-Keep, -Remove, -KeepApps, -PackageList, -SkipTweak,
    -DriverPath, -Compress, -Fast, -NoPrompt, -ZeroTouch, -InteractiveOobe, -User,
    -Password, -TimeZone, -Locale, -ComputerName, -UnattendFile, -Browser,
    -Payload, -DefenderExclusion, -DryRun, -Yes) behave exactly as in tiny11maker.ps1.

.EXAMPLE
    .\tiny11Coremaker.ps1 -ISO C:\iso\Win11.iso -Edition Pro -Yes

.EXAMPLE
    .\tiny11Coremaker.ps1 -ISO E -Index 1 -ZeroTouch -EnableNetFx3 -Yes
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)][string]$ISO,
    [Parameter(Position = 1)][ValidatePattern('^[c-zC-Z]:?$')][string]$SCRATCH,
    [int]$Index,
    [string]$Edition,
    [string]$Preset = 'Minimal-VM',
    [switch]$KeepApps,
    [string[]]$Keep = @(),
    [string[]]$Remove = @(),
    [string]$PackageList,
    [string[]]$SkipTweak = @(),
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

$utilsModulePath = Join-Path $PSScriptRoot 'lib\tiny11utils.psm1'
if (-not (Test-Path -Path $utilsModulePath -PathType Leaf)) {
    Write-Error "Required module not found: $utilsModulePath"
    exit 1
}
Import-Module -Name $utilsModulePath -Force -DisableNameChecking

#---------[ Normalise arguments ]---------#
$splitList = { param($v) @($v | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$Keep = & $splitList $Keep
$Remove = & $splitList $Remove
$SkipTweak = & $splitList $SkipTweak
if ($ISO) { $ISO = $ISO.Trim().Trim('"') }
if ($ISO -match '^[c-zC-Z]:?\\?$') { $ISO = $ISO.Substring(0, 1) }
if ($SCRATCH) { $SCRATCH = $SCRATCH.Substring(0, 1) }
$ScratchDisk = if ($SCRATCH) { "${SCRATCH}:" } else { (Split-Path -Qualifier $PSScriptRoot) }
if (-not $OutputIso) { $OutputIso = Join-Path $PSScriptRoot 'tiny11core.iso' }
if ($ZeroTouch -and -not $PSBoundParameters.ContainsKey('NoPrompt')) { $NoPrompt = $true }
if ($ISO -match '^[c-zC-Z]$' -and $SCRATCH -and $ISO -ieq $SCRATCH) {
    throw "ISO source drive and SCRATCH drive must be different."
}
if ($Yes -and -not $ISO) { throw "-Yes requires -ISO (no interactive prompt available)." }

#---------[ Elevation ]---------#
$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Restarting Tiny11 Core builder as administrator in a new window..."
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

#---------[ Validate options ]---------#
$flags = (Resolve-BuildPreset -PresetName $Preset).Clone()
# Core invariants, independent of the preset.
foreach ($forced in 'RemoveEdge', 'RemoveWebView', 'RemoveOneDrive', 'RemoveDefender', 'RemoveCapabilities') { $flags[$forced] = $true }
if (-not $KeepApps) { $flags['RemoveAppx'] = $true }
$flags['DisableWindowsUpdate'] = $true
$flags['TuneDefenderCpuLimit'] = $false
$flags['LowRam'] = $false
$flags['DisableDriverUpdates'] = $false
$buildProfile = Resolve-BuildProfile -Compress $Compress -Fast:$Fast
$utilities = Resolve-OptionalUtilities -Keep $Keep -Remove $Remove
$null = Get-TweakPlan -Flags $flags -Skip $SkipTweak
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
    $null = New-UnattendXml -UserName $User -Password $Password -TimeZone $TimeZone -Locale $Locale `
        -ComputerName $ComputerName -ZeroTouch:$ZeroTouch -InteractiveOobe:$InteractiveOobe
}

#---------[ Confirmation & questions ]---------#
Write-Host "=== Tiny11 Core image creator - Ultimate Edition $Script:Version ===" -ForegroundColor Cyan
Write-Host "WARNING: Core images are NOT serviceable: no Windows Update, no language packs," -ForegroundColor Yellow
Write-Host "         no optional features and no WinRE. For VMs and testing only." -ForegroundColor Yellow
if ($ZeroTouch) { Write-Warning "-ZeroTouch: the ISO will ERASE DISK 0 automatically during Setup." }
if (-not $Yes -and -not $DryRun) {
    if ((Read-Host 'Continue? [y/N]') -notmatch '^(?i:y|yes)$') { Write-Host 'Aborted.'; exit 0 }
    if (-not $PSBoundParameters.ContainsKey('EnableNetFx3')) {
        $EnableNetFx3 = (Read-Host 'Enable .NET Framework 3.5? It cannot be added later. [y/N]') -match '^(?i:y|yes)$'
    }
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

$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'No transcript was running.' }
Start-Transcript -Path (Join-Path $logDir "tiny11core_$(Get-Date -f yyyyMMdd_HHmmss).log") | Out-Null
$Script:transcriptStarted = $true
$buildStart = Get-Date
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal
$Host.UI.RawUI.WindowTitle = "Tiny11 Core image creator - Ultimate Edition $Script:Version"

#---------[ Pre-flight, source & edition ]---------#
Test-Prerequisites
Clear-StaleBuildState
if ($SCRATCH) { $null = Test-ScratchDiskNtfs -ScratchPath $ScratchDisk }

$Script:source = Resolve-WindowsSource -IsoParameter $ISO
$DriveLetter = $Script:source.DriveLetter
$sourceImage = if (Test-Path "$DriveLetter\sources\install.wim") { "$DriveLetter\sources\install.wim" } else { "$DriveLetter\sources\install.esd" }
$imageIndex = Select-ImageIndex -Images @(Get-WindowsImage -ImagePath $sourceImage) -Index $Index -Edition $Edition -NonInteractive:$Yes
$info = Get-ImageInfo -ImagePath $sourceImage -Index $imageIndex
$architecture = $info.Architecture
$languageCode = $info.Language
Write-Host "Selected: [$imageIndex] $($info.Name) | $($info.DisplayVersion) build $($info.Version) | $architecture | $languageCode"
if ($architecture -notin 'amd64', 'arm64') { throw "Unsupported image architecture '$architecture'." }

$space = Test-SufficientScratch (Get-RequiredScratchBytes $info.SizeBytes) ([long](Get-PSDrive -Name $ScratchDisk.TrimEnd(':')).Free)
if ($DryRun) {
    Write-Host ""
    Write-Host "===== DRY RUN (Core) - nothing will be modified =====" -ForegroundColor Yellow
    Write-Host "  Edition      : [$imageIndex] $($info.Name), $($info.DisplayVersion) build $($info.Version), $architecture, $languageCode"
    Write-Host "  Preset       : $Preset (+ Core invariants: no Edge/WebView2/OneDrive/Defender/Windows Update/WinRE)"
    Write-Host "  Tweak groups : $((Get-TweakPlan -Flags $flags -Skip $SkipTweak | ForEach-Object { $_.Id }) -join ', ')"
    Write-Host "  .NET 3.5     : $([bool]$EnableNetFx3)"
    Write-Host "  Compression  : $($buildProfile.Compress) -> sources\$($buildProfile.ImageFileName)"
    Write-Host ("  Scratch      : {0} GB free on {1}, ~{2} GB needed  [{3}]" -f $space.FreeGB, $ScratchDisk, $space.RequiredGB, $(if ($space.Ok) { 'OK' } else { 'INSUFFICIENT' }))
    Write-Host "  oscdimg      : $((Find-Oscdimg).Source)"
    Write-Host "  Output ISO   : $OutputIso"
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

#---------[ Copy media & export the chosen edition ]---------#
Write-Host "Copying installation media (without the install image)..."
if (Test-Path $workRoot) { Remove-Item -Path $workRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$workRoot\sources" | Out-Null
Invoke-Robocopy -Source "$DriveLetter\" -Destination $workRoot -ExcludeFile @('install.wim', 'install.esd')
$wimFilePath = "$workRoot\sources\install.wim"
Write-Host "Exporting edition $imageIndex from $(Split-Path $sourceImage -Leaf)..."
Export-WindowsImage -SourceImagePath $sourceImage -SourceIndex $imageIndex -DestinationImagePath $wimFilePath -CompressionType fast | Out-Null
Dismount-WindowsSource -Source $Script:source

#---------[ Mount ]---------#
Write-Host "Mounting the Windows image..."
$null = Initialize-ScratchWorkspace -ScratchRoot $ScratchDisk
Mount-WindowsImage -ImagePath $wimFilePath -Index 1 -Path $mountDir | Out-Null
Assert-MountedImage -MountPath $mountDir

#---------[ Apps & capabilities ]---------#
$apps = Invoke-AppRemovalStage -MountPath $mountDir -Flags $flags -Utilities $utilities -PackageListPath $packageListPath -KeepApps:$KeepApps
$Script:buildWarnings += $apps.Failures
$Script:buildWarnings += Invoke-CapabilityRemovalStage -MountPath $mountDir -LanguageCode $languageCode -Core

#---------[ .NET 3.5 (before WinSxS is trimmed) ]---------#
if ($EnableNetFx3) {
    Write-Host "Enabling .NET Framework 3.5..."
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

#---------[ Component packages ]---------#
Write-Host "Removing component packages..."
$installedPackages = @(Get-WindowsPackage -Path $mountDir | ForEach-Object { $_.PackageName })
foreach ($packageName in (Get-CoreWindowsPackagesToRemove -Installed $installedPackages -LanguageCode $languageCode)) {
    Write-Host "  - $packageName"
    $rc = Invoke-Native -FilePath 'dism.exe' -ArgumentList @('/English', "/Image:$mountDir", '/Remove-Package', "/PackageName:$packageName", '/NoRestart')
    if ($rc -ne 0) {
        Write-Warning "Could not remove $packageName (dism exit $rc)."
        $Script:buildWarnings++
    }
}

#---------[ Edge (incl. WebView2 and its WinSxS payload), OneDrive, WinRE ]---------#
Write-Host "Removing Microsoft Edge and WebView2..."
Remove-EdgeFiles -MountPath $mountDir -Architecture $architecture -IncludeWebView   # WinSxS copies go with the rebuild below
Write-Host "Removing OneDrive..."
Remove-OneDriveFiles -MountPath $mountDir
Write-Host "Removing WinRE..."
$winre = "$mountDir\Windows\System32\Recovery\winre.wim"
if (Test-Path -LiteralPath $winre) {
    if (Remove-ImagePath -Path $winre) {
        New-Item -Path $winre -ItemType File -Force | Out-Null   # zero-byte placeholder keeps Setup happy
    } else {
        Write-Warning "Could not remove winre.wim."
        $Script:buildWarnings++
    }
}

#---------[ WinSxS rebuild ]---------#
Write-Host "Taking ownership of WinSxS (this takes a while)..."
$winSxS = "$mountDir\Windows\WinSxS"
$winSxSEdit = "$mountDir\Windows\WinSxS_edit"
$null = Grant-AdminFullControl -Path $winSxS -Recurse
$keepPatterns = if ($architecture -eq 'amd64') {
    @(
        'x86_microsoft.windows.common-controls_6595b64144ccf1df_*'
        'x86_microsoft.windows.gdiplus_6595b64144ccf1df_*'
        'x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*'
        'x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*'
        'x86_microsoft-windows-s..ngstack-onecorebase_31bf3856ad364e35_*'
        'x86_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*'
        'x86_microsoft-windows-servicingstack_31bf3856ad364e35_*'
        'x86_microsoft-windows-servicingstack-inetsrv_*'
        'x86_microsoft-windows-servicingstack-onecore_*'
        'amd64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*'
        'amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*'
        'amd64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
        'amd64_microsoft.windows.common-controls_6595b64144ccf1df_*'
        'amd64_microsoft.windows.gdiplus_6595b64144ccf1df_*'
        'amd64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*'
        'amd64_microsoft.windows.isolationautomation_6595b64144ccf1df_*'
        'amd64_microsoft-windows-s..stack-inetsrv-extra_31bf3856ad364e35_*'
        'amd64_microsoft-windows-s..stack-msg.resources_31bf3856ad364e35_*'
        'amd64_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*'
        'amd64_microsoft-windows-servicingstack_31bf3856ad364e35_*'
        'amd64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*'
        'amd64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*'
        'amd64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*'
        'Catalogs', 'FileMaps', 'Fusion', 'InstallTemp', 'Manifests'
        'x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*'
        'x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*'
        'x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
    )
} else {
    @(
        'arm64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*'
        'Catalogs', 'FileMaps', 'Fusion', 'InstallTemp', 'Manifests', 'SettingsManifests', 'Temp'
        'x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*'
        'x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*'
        'x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
        'x86_microsoft.windows.common-controls_6595b64144ccf1df_*'
        'x86_microsoft.windows.gdiplus_6595b64144ccf1df_*'
        'x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*'
        'x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*'
        'arm_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
        'arm_microsoft.windows.common-controls_6595b64144ccf1df_*'
        'arm_microsoft.windows.gdiplus_6595b64144ccf1df_*'
        'arm_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*'
        'arm_microsoft.windows.isolationautomation_6595b64144ccf1df_*'
        'arm64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*'
        'arm64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*'
        'arm64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*'
        'arm64_microsoft.windows.common-controls_6595b64144ccf1df_*'
        'arm64_microsoft.windows.gdiplus_6595b64144ccf1df_*'
        'arm64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*'
        'arm64_microsoft.windows.isolationautomation_6595b64144ccf1df_*'
        'arm64_microsoft-windows-servicing-adm_31bf3856ad364e35_*'
        'arm64_microsoft-windows-servicingcommon_31bf3856ad364e35_*'
        'arm64_microsoft-windows-servicing-onecore-uapi_31bf3856ad364e35_*'
        'arm64_microsoft-windows-servicingstack_31bf3856ad364e35_*'
        'arm64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*'
        'arm64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*'
    )
}
Write-Host "Copying the essential WinSxS content..."
New-Item -Path $winSxSEdit -ItemType Directory -Force | Out-Null
foreach ($pattern in $keepPatterns) {
    foreach ($dir in @(Get-ChildItem -Path $winSxS -Filter $pattern -Directory -ErrorAction SilentlyContinue)) {
        Copy-Item -Path $dir.FullName -Destination (Join-Path $winSxSEdit $dir.Name) -Recurse -Force
    }
}
Assert-WinSxSRebuild -Path $winSxSEdit
Write-Host "Replacing WinSxS (this takes a while)..."
Remove-Item -Path $winSxS -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $winSxS) {
    $null = Invoke-Native -FilePath 'cmd.exe' -ArgumentList @('/c', 'rmdir', '/s', '/q', "\\?\$winSxS")
}
if (Test-Path -LiteralPath $winSxS) {
    # Renaming now would leave the full WinSxS in place next to the trimmed copy.
    throw "The original WinSxS could not be deleted completely; aborting instead of shipping a broken image."
}
Rename-Item -LiteralPath $winSxSEdit -NewName 'WinSxS' -ErrorAction Stop

#---------[ Registry ]---------#
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

#---------[ Cleanup, commit, export ]---------#
if (-not $buildProfile.SkipCleanup) {
    if (-not (Invoke-ComponentCleanup -MountPath $mountDir)) { $Script:buildWarnings++ }
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
    -Label "TINY11CORE_$($info.DisplayVersion)_$($architecture.ToUpperInvariant())" -NoPrompt:$NoPrompt

$sha256 = Write-BuildManifest -IsoPath $OutputIso -Data @{
    builder     = "tiny11Coremaker.ps1 $Script:Version"
    source      = @{ image = $sourceImage; index = $imageIndex; name = $info.Name; edition = $info.Edition; version = $info.Version; displayVersion = $info.DisplayVersion; architecture = $architecture; language = $languageCode }
    options     = @{ preset = $Preset; compress = $buildProfile.Compress; keep = $Keep; remove = $Remove; netFx3 = [bool]$EnableNetFx3; drivers = [bool]$DriverPath; zeroTouch = [bool]$ZeroTouch; interactiveOobe = [bool]$InteractiveOobe; browser = $Browser; skipTweak = $SkipTweak }
    flags       = $flags
    removedApps = $apps.Removed
    tweakGroups = $tweaks.Applied
    warnings    = $Script:buildWarnings
}

#---------[ Cleanup & summary ]---------#
Remove-Item -Path $workRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue
if ($Script:defenderExclusions) { Remove-BuildDefenderExclusion -Path $Script:defenderExclusions }

Format-BuildSummary -Elapsed ((Get-Date) - $buildStart) -IsoBytes $isoBytes -IsoPath $OutputIso `
    -AppsRemoved $apps.Removed.Count -AppsTotal $apps.Total -Warnings $Script:buildWarnings `
    -Image "$($info.Name) $($info.DisplayVersion) Core ($architecture)" -Sha256 $sha256 | ForEach-Object { Write-Host $_ -ForegroundColor Green }

Stop-Transcript | Out-Null
if (-not $Yes) { Read-Host "Done. Press Enter to close" | Out-Null }
exit 0
