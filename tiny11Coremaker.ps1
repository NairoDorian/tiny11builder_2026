<#
.SYNOPSIS
    Builds tiny11 Core: the smallest possible Windows 11 image, for VMs and testing.

.DESCRIPTION
    Everything tiny11maker.ps1 does, plus:
      - removes component packages (IE, Media Player, handwriting/OCR/speech/TTS,
        Defender, WordPad, Steps Recorder, Math Input, extended wallpapers)
      - removes WinRE (no recovery environment / Reset this PC)
      - trims WinSxS in place, keeping only the servicing stack, common controls,
        GDI+, VC runtimes and the store metadata (native ACL-preserving deletion;
        refused while servicing is pending)
      - disables Windows Update and Microsoft Defender
      - removes Edge including WebView2, plus the capability set

    Edge/WebView2/OneDrive/capability removal is unconditional: -Preset selects
    only the remaining optional tweaks.

    The result is NOT serviceable: no cumulative updates, language packs or
    optional features can be added afterwards. Use it for disposable VMs,
    CI runners and quick tests - never as a daily-driver OS.

.PARAMETER ISO
    Path to a Windows 11 .iso, or the drive letter of a mounted ISO.

.PARAMETER SCRATCH
    Drive letter for the work folders (default: the drive this script is on). NTFS only.

.PARAMETER WorkDirectory
    Optional absolute NTFS folder for an isolated build. Must be new or empty.
    Work files and image mounts stay below this folder; other builds are preserved.

.PARAMETER Index
    Image index to build.

.PARAMETER Edition
    Edition name instead of -Index, e.g. "Pro".

.PARAMETER Preset
    Preset for the optional tweaks (default: Minimal-VM). Core always removes
    Edge, WebView2, OneDrive, capabilities and Defender and disables Windows
    Update regardless of the preset. -KeepApps is still honored.

.PARAMETER EnableNetFx3
    Enable .NET Framework 3.5 (must happen at build time: the image cannot be
    serviced later). Interactive runs ask; -Yes runs default to no.

.PARAMETER OutputIso
    Output ISO path (default: tiny11core.iso next to this script).

.PARAMETER KeepApps
    Skip provisioned-app removal (Edge/OneDrive/capabilities are still removed in Core).

.PARAMETER Keep
    Optional utilities to keep (Terminal, Calculator, Notepad, Photos, Paint, Camera,
    SoundRecorder, StickyNotes, Clock, MediaPlayer, MoviesTV, SnippingTool).

.PARAMETER Remove
    Optional utilities to remove (same names as -Keep).

.PARAMETER PackageList
    Use this file of app-name prefixes instead of removePackage.txt.

.PARAMETER SkipTweak
    Tweak group ids from data\tweaks.psd1 to leave out (see docs/TWEAKS.md).

.PARAMETER DriverPath
    Folder of .inf drivers injected into the install and Setup images.

.PARAMETER Compress
    maximum (install.esd, smallest, default) | balanced | fast | none.
    Legacy aliases: recovery means maximum, max means balanced LZX.

.PARAMETER CompressionEngine
    Auto (pinned wimlib, DISM fallback) | Wimlib | Dism.

.PARAMETER CompressionLevel
    wimlib compression effort, 1-200 (default 100).

.PARAMETER CompressionThreads
    wimlib threads; 0 chooses automatically within memory limits.

.PARAMETER Fast
    Fast compression and no component-store cleanup (quick test builds).

.PARAMETER NoPrompt
    The ISO boots straight into Setup without "Press any key".

.PARAMETER ZeroTouch
    Fully unattended install that WIPES DISK 0 (UEFI/GPT). VMs / test machines only.

.PARAMETER InteractiveOobe
    Do not create an account; OOBE asks for a local user name.

.PARAMETER User
    Local administrator created by the answer file (default: User).

.PARAMETER Password
    Password for -User. Stored Base64-obfuscated, deleted after the first sign-in.

.PARAMETER TimeZone
    Windows time zone id (default: UTC).

.PARAMETER Locale
    Language/region/keyboard such as fr-FR (default: asked in OOBE).

.PARAMETER ComputerName
    Computer name (default: Windows picks one).

.PARAMETER UnattendFile
    Use your own answer file instead of the generated one.

.PARAMETER Browser
    None (default), Firefox or Chrome, installed at the first sign-in.

.PARAMETER Payload
    Stage payload\packages\*.cmd / *.ps1 to run once at the end of Setup.

.PARAMETER DefenderExclusion
    Temporarily exclude the work folders from this PC's Defender scanning.

.PARAMETER DryRun
    Validate and print the plan without modifying anything.

.PARAMETER Yes
    Non-interactive: never prompt.

.PARAMETER Help
    Show the full help.

.NOTES
    Shared parameters behave as in tiny11maker.ps1, except where noted above.
    -LowRam, -DisableDriverUpdates and -KeepUpdateUninstall do not exist for Core.

.PARAMETER UpdatePackage
    Local .msu / .cab packages integrated offline in the given order, before any
    removal. Core still refuses to trim WinSxS if they leave work pending.

.PARAMETER OmitNetFx3Payload
    Leave sources\sxs (~70 MB) out of the ISO (Core cannot add .NET 3.5 later anyway).

.PARAMETER ShrinkBootImage
    Rebuild boot.wim with only its Windows Setup image (bootable, maximum LZX).

.PARAMETER RemoveRedundantData
    Delete offline update downloads, temp files, archived logs and crash dumps.

.EXAMPLE
    .\tiny11Coremaker.ps1 -ISO C:\iso\Win11.iso -Edition Pro -Yes

.EXAMPLE
    .\tiny11Coremaker.ps1 -ISO E -Index 1 -ZeroTouch -EnableNetFx3 -Yes
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)][string]$ISO,
    [Parameter(Position = 1)][ValidatePattern('^[c-zC-Z]:?$')][string]$SCRATCH,
    [string]$WorkDirectory,
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
    [ValidateSet('maximum', 'balanced', 'fast', 'none', 'recovery', 'max')][string]$Compress,
    [ValidateSet('Auto', 'Dism', 'Wimlib')][string]$CompressionEngine = 'Auto',
    [ValidateRange(1, 200)][int]$CompressionLevel = 100,
    [ValidateRange(0, 1024)][int]$CompressionThreads = 0,
    [switch]$Fast,
    [string[]]$UpdatePackage = @(),
    [switch]$OmitNetFx3Payload,
    [switch]$ShrinkBootImage,
    [switch]$RemoveRedundantData,
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
$ScratchRoot = "$ScratchDisk\"
if ($WorkDirectory) {
    if (-not [IO.Path]::IsPathRooted($WorkDirectory) -or $WorkDirectory -notmatch '^[a-zA-Z]:\\') {
        throw '-WorkDirectory must be an absolute folder path on a local NTFS drive.'
    }
    $ScratchRoot = [IO.Path]::GetFullPath($WorkDirectory).TrimEnd('\')
    Assert-WorkDirectoryLocation -Path $ScratchRoot
    if ($ScratchRoot -eq [IO.Path]::GetPathRoot($ScratchRoot).TrimEnd('\')) {
        throw '-WorkDirectory must be a folder, not a drive root.'
    }
    if ((Test-Path -LiteralPath $ScratchRoot) -and @(Get-ChildItem -LiteralPath $ScratchRoot -Force -ErrorAction Stop).Count) {
        throw '-WorkDirectory must be new or empty. Stop any earlier writer before choosing another folder.'
    }
    $ScratchDisk = Split-Path -Qualifier $ScratchRoot
}
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
    $psi = New-Object System.Diagnostics.ProcessStartInfo (Get-PowerShellExecutable)
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
# Defender is removed in Core, so its CPU-limit tuning is meaningless and would
# only write policy for a component that is gone.
$flags['TuneDefenderCpuLimit'] = $false
# Driver updates are pointless on an image that is never serviced.
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
Assert-OutputIsoLocation -OutputIso $OutputIso
$updatePackages = Resolve-UpdatePackageList -Path $UpdatePackage
$updateBytes = [long](@($updatePackages | ForEach-Object { (Get-Item -LiteralPath $_).Length }) | Measure-Object -Sum).Sum
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
$workRoot = Join-Path $ScratchRoot 'tiny11'
$mountDir = Join-Path $ScratchRoot 'scratchdir'

trap {
    Write-Host ""
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray }
    Write-Warning "Cleaning up (unloading hives, discarding the mounted image)..."
    $isoToEject = if ($Script:source -and $Script:source.MountedByScript) { $Script:source.IsoPath } else { $null }
    Invoke-EmergencyCleanup -ScratchDisk $ScratchRoot -IsoImagePath $isoToEject -DefenderExclusions $Script:defenderExclusions
    if ($Script:transcriptStarted) { try { Stop-Transcript | Out-Null } catch { Write-Verbose 'Transcript already stopped.' } }
    exit 1
}

$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { Write-Verbose 'No transcript was running.' }
Start-Transcript -Path (Join-Path $logDir "tiny11core_$(Get-Date -f yyyyMMdd_HHmmss).log") | Out-Null
$Script:transcriptStarted = $true
$buildStart = Get-Date
# Inherit process priority; the user controls host CPU scheduling.
$Host.UI.RawUI.WindowTitle = "Tiny11 Core image creator - Ultimate Edition $Script:Version"

#---------[ Pre-flight, source & edition ]---------#
Test-Prerequisites
# Prepare the ISO writer before attaching/copying/servicing media (PR #604).
if (-not $DryRun) { $Script:oscdimgPath = Initialize-Oscdimg }
if (-not $WorkDirectory) { Clear-StaleBuildState }
$null = Test-ScratchDiskNtfs -ScratchPath $ScratchDisk   # default work drive included

$Script:source = Resolve-WindowsSource -IsoParameter $ISO
$DriveLetter = $Script:source.DriveLetter
Assert-SourceWorkspaceSeparation -SourceRoot "$DriveLetter\" -WorkRoot $workRoot
$sourceImage = if (Test-Path "$DriveLetter\sources\install.wim") { "$DriveLetter\sources\install.wim" } else { "$DriveLetter\sources\install.esd" }
$imageIndex = Select-ImageIndex -Images @(Get-WindowsImage -ImagePath $sourceImage) -Index $Index -Edition $Edition -NonInteractive:$Yes
$info = Get-ImageInfo -ImagePath $sourceImage -Index $imageIndex
Assert-ServicingToolsSupportImage -ImageBuild ([int]$info.Build)
$sourceMetadata = Get-InstallImageMetadata -ImagePath $sourceImage -Index $imageIndex
$architecture = $info.Architecture
$languageCode = $info.Language
Write-Host "Selected: [$imageIndex] $($info.Name) | $($info.DisplayVersion) build $($info.Version) | $architecture | $languageCode"
if ($architecture -notin 'amd64', 'arm64') { throw "Unsupported image architecture '$architecture'." }

$space = Test-SufficientScratch ((Get-RequiredScratchBytes $info.SizeBytes) + 3 * $updateBytes) ([long](Get-PSDrive -Name $ScratchDisk.TrimEnd(':')).Free)
if ($DryRun) {
    Write-Host ""
    Write-Host "===== DRY RUN (Core) - nothing will be modified =====" -ForegroundColor Yellow
    Write-Host "  Edition      : [$imageIndex] $($info.Name), $($info.DisplayVersion) build $($info.Version), $architecture, $languageCode"
    Write-Host "  Preset       : $Preset (+ Core invariants: no Edge/WebView2/OneDrive/Defender/Windows Update/WinRE)"
    Write-Host "  Tweak groups : $((Get-TweakPlan -Flags $flags -Skip $SkipTweak | ForEach-Object { $_.Id }) -join ', ')"
    Write-Host "  .NET 3.5     : $([bool]$EnableNetFx3)"
    Write-Host "  Updates      : $(if ($updatePackages.Count) { "$($updatePackages.Count) package(s), in order" } else { 'none' })"
    Write-Host "  Media options: omit .NET 3.5 payload=$([bool]$OmitNetFx3Payload), smaller boot.wim=$([bool]$ShrinkBootImage), remove redundant data=$([bool]$RemoveRedundantData)"
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

Set-DismSessionOptions -LogPath (Join-Path $logDir "dism_$(Get-Date -f yyyyMMdd_HHmmss).log") -ScratchDirectory (Join-Path $ScratchRoot 'scratchdir_dism')
Test-OfflineHiveLoading -ScratchRoot $ScratchRoot

#---------[ Copy media & export the chosen edition ]---------#
Write-Host "Copying installation media (without the install image)..."
if (Test-Path $workRoot) { Remove-Item -Path $workRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$workRoot\sources" | Out-Null
Assert-BuildNotCancelled
Invoke-Robocopy -Source "$DriveLetter\" -Destination $workRoot -ExcludeFile @('install.wim', 'install.esd')
$wimFilePath = "$workRoot\sources\install.wim"
Write-Host "Exporting edition $imageIndex from $(Split-Path $sourceImage -Leaf)..."
Export-SelectedInstallImage -Source $sourceImage -Index $imageIndex -Destination $wimFilePath -CompressionEngine $CompressionEngine
# Export-SelectedInstallImage throws when it produces no image, but Core does not
# add Standard's extra Test-Path check. Verified by the throw rather than a probe.
Dismount-WindowsSource -Source $Script:source

#---------[ Mount ]---------#
Write-Host "Mounting the Windows image..."
$null = Initialize-ScratchWorkspace -ScratchRoot $ScratchRoot
Invoke-DismChecked -Label 'Image mount' '/Mount-Image' "/ImageFile:$wimFilePath" '/Index:1' "/MountDir:$mountDir"
Assert-MountedImage -MountPath $mountDir

#---------[ Windows updates (before any removal) ]---------#
$updateResults = @()
if ($updatePackages.Count) {
    Assert-BuildNotCancelled
    $updateResults = Install-OfflineUpdatePackages -MountPath $mountDir -Packages $updatePackages -StagingRoot (Join-Path $ScratchRoot 'scratchdir_updates')
}

#---------[ Apps & capabilities ]---------#
$apps = Invoke-AppRemovalStage -MountPath $mountDir -Flags $flags -Utilities $utilities -PackageListPath $packageListPath -ImageBuild $info.Build -KeepApps:$KeepApps
$Script:buildWarnings += $apps.Failures
$Script:buildWarnings += Invoke-CapabilityRemovalStage -MountPath $mountDir -LanguageCode $languageCode -Core
$Script:buildWarnings += Invoke-OptionalFeatureRemovalStage -MountPath $mountDir -Architecture $architecture

#---------[ Component packages ]---------#
Write-Host "Removing component packages..."
$installedPackages = @(Get-WindowsPackage -Path $mountDir | ForEach-Object { $_.PackageName })
foreach ($packageName in (Get-CoreWindowsPackagesToRemove -Installed $installedPackages -LanguageCode $languageCode)) {
    Write-Host "  - $packageName"
    $rc = Invoke-Native -FilePath 'dism.exe' -ArgumentList (Add-DismSessionArguments -Arguments @("/Image:$mountDir", '/Remove-Package', "/PackageName:$packageName", '/NoRestart'))
    if ($rc -ne 0) {
        Write-Warning "Could not remove $packageName (dism exit $rc)."
        $Script:buildWarnings++
    }
}

#---------[ Edge + WebView2 program files, OneDrive, WinRE ]---------#
Write-Host "Removing Microsoft Edge and WebView2..."
# WebView2's WinSxS payload is NOT removed here (no -IncludeWinSxS). It is
# removed indirectly: the WinSxS trim below keeps only matching packages, so it
# disappears because no keep pattern matches it. Adding a WebView pattern to
# Get-CoreWinSxSKeepPatterns would silently leave Edge's store payload behind.
$edgeFiles = Remove-EdgeFiles -MountPath $mountDir -Architecture $architecture -IncludeWebView
Write-Host "Removing OneDrive..."
Remove-OneDriveFiles -MountPath $mountDir
Write-Host "Removing WinRE..."
$winre = "$mountDir\Windows\System32\Recovery\winre.wim"
if (Test-Path -LiteralPath $winre) {
    if (Remove-ImagePath -Path $winre -MountPath $mountDir) {
        # Zero-byte placeholder: Setup validates that the recovery file exists, so
        # deleting it outright produces a media Setup may reject. Core is already
        # non-serviceable, so the empty file costs nothing real.
        New-Item -Path $winre -ItemType File -Force | Out-Null
    } else {
        Write-Warning "Could not remove winre.wim."
        $Script:buildWarnings++
    }
}

#---------[ Component cleanup, then .NET 3.5 (both before the WinSxS trim) ]---------#
# Upstream WinUI order: reset the component base FIRST, then enable .NET 3.5, so
# /ResetBase can never drop the NetFx3 payload (closes the earlier Core/Standard
# ResetBase divergence), and the cleanup runs on a complete store.
if (-not $buildProfile.SkipCleanup) {
    if (-not (Invoke-ComponentCleanup -MountPath $mountDir)) { $Script:buildWarnings++ }
}
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

#---------[ WinSxS trim ]---------#
# Core deletes component files, so any servicing still waiting for first boot
# would be broken. Refuse instead of shipping it; nothing pending is reverted.
$pending = Get-OfflinePendingOperations -MountPath $mountDir -IncludePackages
if ($pending.Count) {
    $pending | ForEach-Object { Write-Host "  pending: $_" }
    throw "Core stopped before trimming WinSxS: the image has $($pending.Count) pending servicing operation(s) that need component files at first boot. Build without -EnableNetFx3 / updates, or build a serviceable Standard image."
}
Write-Host "Trimming WinSxS in place (native, ACL-preserving)..."
$null = Invoke-CoreWinSxSTrim -MountPath $mountDir -Architecture $architecture

#---------[ Registry ]---------#
Assert-BuildNotCancelled
$tweaks = Invoke-RegistryStage -MountPath $mountDir -Flags $flags -Skip $SkipTweak -RemovedPackages $apps.Removed -EdgeFiles $edgeFiles
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

$redundant = $null
if ($RemoveRedundantData) { $redundant = Remove-OfflineRedundantData -MountPath $mountDir }

#---------[ Commit, export ]---------#
# Component cleanup already ran before .NET 3.5 and the WinSxS trim (see above).
Assert-BuildNotCancelled
Write-Host "Committing and unmounting the Windows image..."
if (-not (Invoke-SafeDismountImage -Path $mountDir -Save)) {
    throw "Failed to commit/unmount the install image."
}
if ($updateResults.Count) {
    $sourceMetadata = Resolve-ServicedImageExpectation -Expected $sourceMetadata -Committed (Get-InstallImageMetadata -ImagePath $wimFilePath -Index 1)
}
Assert-BuildNotCancelled
$null = Export-FinalInstallImage -WorkRoot $workRoot -BuildProfile $buildProfile -CompressionEngine $CompressionEngine -CompressionLevel $CompressionLevel -CompressionThreads $CompressionThreads
Assert-InstallImageMetadata -ImagePath (Join-Path $workRoot ('sources\' + $buildProfile.ImageFileName)) -Expected $sourceMetadata -RepairMissing

#---------[ boot.wim, answer file, ISO ]---------#
Assert-BuildNotCancelled
$Script:buildWarnings += Invoke-BootImageStage -WorkRoot $workRoot -ScratchRoot $ScratchRoot -DriverPath $DriverPath
$bootShrink = if ($ShrinkBootImage) { Invoke-BootImageShrink -WorkRoot $workRoot } else { $null }
$omittedNetFx3Bytes = if ($OmitNetFx3Payload) { Remove-SetupNetFx3Payload -WorkRoot $workRoot } else { [long]0 }
Write-UnattendFile -Xml $unattendXml -Path "$workRoot\autounattend.xml"
Assert-BuildNotCancelled
$isoBytes = New-Tiny11Iso -WorkRoot $workRoot -OutputIso $OutputIso -Architecture $architecture -OscdimgPath $Script:oscdimgPath -PublishedPath ([ref]$OutputIso) `
    -Label "TINY11CORE_$($info.DisplayVersion)_$($architecture.ToUpperInvariant())" -NoPrompt:$NoPrompt

$sha256 = Write-BuildManifest -IsoPath $OutputIso -Data @{
    builder     = "tiny11Coremaker.ps1 $Script:Version"
    source      = @{ image = $sourceImage; index = $imageIndex; name = $info.Name; edition = $info.Edition; version = $info.Version; displayVersion = $info.DisplayVersion; architecture = $architecture; language = $languageCode }
    options     = @{ preset = $Preset; compress = $buildProfile.Compress; compressionEngine = $CompressionEngine; compressionLevel = $CompressionLevel; compressionThreads = $CompressionThreads; keep = $Keep; remove = $Remove; netFx3 = [bool]$EnableNetFx3; drivers = [bool]$DriverPath; zeroTouch = [bool]$ZeroTouch; interactiveOobe = [bool]$InteractiveOobe; browser = $Browser; skipTweak = $SkipTweak }
    flags       = $flags
    removedApps = $apps.Removed
    tweakGroups = $tweaks.Applied
    warnings    = $Script:buildWarnings
    servicing   = @{ updates = $updateResults; omittedNetFx3Bytes = $omittedNetFx3Bytes; bootImage = $bootShrink
                     redundantData = $redundant; edgeFiles = $edgeFiles; finalVersion = $sourceMetadata.Version }
}

#---------[ Cleanup & summary ]---------#
foreach ($mountName in 'scratchdir', 'scratchdir_boot', 'scratchdir_dism') {
    Remove-ScratchMountDirectory -ScratchRoot $ScratchRoot -MountName $mountName
}
Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
if ($Script:defenderExclusions) { Remove-BuildDefenderExclusion -Path $Script:defenderExclusions }

Format-BuildSummary -Elapsed ((Get-Date) - $buildStart) -IsoBytes $isoBytes -IsoPath $OutputIso `
    -AppsRemoved $apps.Removed.Count -AppsTotal $apps.Total -Warnings $Script:buildWarnings `
    -Image "$($info.Name) $($info.DisplayVersion) Core ($architecture)" -Sha256 $sha256 | ForEach-Object { Write-Host $_ -ForegroundColor Green }

Stop-Transcript | Out-Null
if (-not $Yes) { Read-Host "Done. Press Enter to close" | Out-Null }
exit 0
