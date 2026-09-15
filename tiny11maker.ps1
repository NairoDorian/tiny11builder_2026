<#
.SYNOPSIS
    Scripts to build a trimmed-down Windows 11 image.

.DESCRIPTION
    Ultimate Edition: builds a streamlined, still-serviceable Windows 11 image.
    Incorporates the best improvements from 14+ forks:
      - Reforged: auto-ISO-mount, auto-download oscdimg.exe, version tracking
      - Revamped: TaskCache ACL takeover, version-gated GUIDs, emergency trap, safe unload
      - zPoche v2: pre-flight validation, -Custom selector, -DryRun, -Fast, arch-aware autounattend
      - YmlyZA: build summary, robocopy, low-RAM profile
      - DFwindows11: browser management, comprehensive package list
      - MOPELotus: Lotus profile, payload system
      - prismatecas-ui: WPF GUI launcher

.PARAMETER ISO
    Drive letter of the mounted Windows 11 ISO (e.g. E), or a path to a .iso file.

.PARAMETER SCRATCH
    Drive letter of the desired scratch disk (e.g. D). Must be NTFS.

.PARAMETER Index
    Image index to build (an ISO can hold several editions).

.PARAMETER Custom
    Enable interactive selection of which app packages to remove.

.PARAMETER Yes
    Non-interactive: skip prompts; requires -ISO and -Index.

.PARAMETER DryRun
    Print the build plan and exit without copying or mounting.

.PARAMETER Compress
    Image compression: recovery (default), fast, or none.

.PARAMETER Fast
    Preset: fast compression + skip component cleanup.

.PARAMETER ZeroTouch
    Also wipe disk 0 and auto-install (DESTRUCTIVE; VMs/test machines only).

.PARAMETER LowRam
    Apply the 1 GB-class low-RAM profile (conservative, keeps WU/Defender/serviceable).

.PARAMETER Preset
    Build preset controlling which optional tweaks are applied. Options:
    Default, Gaming, Minimal-VM, PrivacyPlus. (Default: Default)

.PARAMETER KeepApps
    Comma-separated list of package prefixes to ADD BACK into removal (overrides defaults).

.PARAMETER Keep
    Comma-separated names of optional utilities to FORCE KEEP (overrides preset defaults).
    Valid names: Terminal, Calculator, Notepad, Photos, Paint, Camera, SoundRecorder,
    StickyNotes, Clock, MediaPlayer, MoviesTV, SnippingTool.

.PARAMETER Remove
    Comma-separated names of optional utilities to FORCE REMOVE (overrides preset defaults).
    Valid names: same as -Keep. Cannot specify the same name in both -Keep and -Remove.

.PARAMETER User
    Local administrator account created by the unattended answer file (default: User).

.PARAMETER Password
    Password for that account (default: blank; AutoLogon is always on).

.PARAMETER TimeZone
    Windows time-zone id (default: UTC).

.PARAMETER Help
    Show usage and exit.

.EXAMPLE
    .\tiny11maker.ps1 -ISO D -Index 1 -Yes
    .\tiny11maker.ps1 -ISO E -SCRATCH D -Custom
    .\tiny11maker.ps1 -ISO D -Index 1 -Yes -ZeroTouch -User Bob -Password "P@ssw0rd" -TimeZone "China Standard Time"
    .\tiny11maker.ps1 -ISO E -SCRATCH D -LowRam
    .\tiny11maker.ps1 -ISO E -SCRATCH D -Preset Gaming
    .\tiny11maker.ps1 -ISO E -SCRATCH D -Keep Terminal -Remove Paint,Camera
    .\tiny11maker.ps1 -ISO E -DryRun

.NOTES
    Ultimate Edition build from NairoDorian/tiny11builder_2026.
    Requires: Windows PowerShell 5.1, Administrator, Windows ADK (optional).
#>

#---------[ Parameters ]---------#
param (
    [Parameter(Position = 0)]
    [string]$ISO,
    [Parameter(Position = 1)]
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH,
    [int]$Index,
    [switch]$Custom,
    [switch]$Yes,
    [switch]$DryRun,
    [ValidateSet('recovery', 'fast', 'none')][string]$Compress,
    [switch]$Fast,
    [switch]$ZeroTouch,
    [switch]$LowRam,
    [string]$Preset,
    [string[]]$KeepApps,
    [string[]]$Keep = @(),
    [string[]]$Remove = @(),
    [string]$User = 'User',
    [string]$Password = '',
    [string]$TimeZone = 'UTC',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

if ($ISO) { $ISO = $ISO.Trim().Trim('"').TrimEnd(':') }
if ($SCRATCH) { $SCRATCH = $SCRATCH.Trim().TrimEnd(':') }

if (-not $SCRATCH) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $SCRATCH + ":"
}

if ($ISO -and $SCRATCH -and ($ISO -match '^[c-zC-Z]$') -and ($ISO.ToUpperInvariant() -eq $SCRATCH.ToUpperInvariant())) {
    throw "ISO source drive and SCRATCH drive must be different."
}

#---------[ Import Utility Module ]---------#
$utilsModulePath = Join-Path $PSScriptRoot 'lib\tiny11utils.psm1'
if (-not (Test-Path -Path $utilsModulePath -PathType Leaf)) {
    Write-Error "Required module not found: $utilsModulePath"
    exit 1
}
Import-Module -Name $utilsModulePath -Force

#---------[ Host Performance Optimisation ]---------#
# Boost build throughput: set High priority, cap DISM threads, and silence AV.
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
$env:DISM_MAX_THREADS = Get-MaxParallelJobs
$env:NUMBER_OF_PROCESSORS = [Environment]::ProcessorCount
Write-Output "[*] Host performance: PriorityClass=High, DISM threads=$($env:DISM_MAX_THREADS), cores=$($env:NUMBER_OF_PROCESSORS)"

#---------[ Build Preset Resolution ]---------#
$preset = if ($Preset) {
    Write-Output "Using preset: $Preset"
    Resolve-BuildPreset -PresetName $Preset
} else {
    Resolve-BuildPreset -PresetName 'Default'
}

#---------[ Show Usage ]---------#
function Show-Usage {
    Write-Output @'
tiny11 builder - Ultimate Edition

USAGE:
  .\tiny11maker.ps1 -ISO <drive> -Index <n> [options]

REQUIRED (or you will be prompted):
  -ISO <letter|path>  Drive letter of mounted Windows 11 ISO, or a .iso file path
  -Index <n>          Image index to build (e.g. 1=Home, 2=Pro)

COMMON:
  -Yes                Non-interactive; requires -ISO and -Index
  -DryRun             Print the build plan and exit (no copy/mount)
  -Custom             Interactive app package selector before building
  -Fast               fast compression + skip component cleanup
  -Compress <recovery|fast|none>  Image compression (default: recovery)

ADVANCED:
  -SCRATCH <letter>   Scratch/work drive (default: script folder drive)
  -ZeroTouch        Also WIPE DISK 0 and auto-install (DESTRUCTIVE; VMs/test only)
  -LowRam           Apply conservative 1 GB-class profile (keeps WU/Defender/serviceable)
  -KeepApps <list>    Comma-separated prefixes to always remove (overrides removePackage.txt)
  -Keep <list>        Optional utility names to keep (Terminal, Calculator, Notepad, etc.)
  -Remove <list>      Optional utility names to remove (overrides defaults)
  -Preset <name>      Load a build preset: Default, Gaming, Minimal-VM, PrivacyPlus
  -Language <code>    Language code (e.g. en-US, zh-CN, ja-JP) for language-aware package removal

UNATTENDED INSTALL (baked into the image):
  -User <name>        Local admin account (default: User)
  -Password <pwd>     Account password (default: blank; AutoLogon always on)
  -TimeZone <id>      Windows time-zone id (default: UTC; e.g. "China Standard Time")

  -Help               Show this help and exit

EXAMPLES:
  .\tiny11maker.ps1 -ISO D -Index 1 -Yes -DryRun
  .\tiny11maker.ps1 -ISO D -Index 1 -Yes
  .\tiny11maker.ps1 -ISO E -SCRATCH D -Custom
  .\tiny11maker.ps1 -ISO D -Index 1 -Yes -ZeroTouch -User Bob -Password "P@ssw0rd" -TimeZone "China Standard Time"
'@
}
if ($Help) { Show-Usage; exit 0 }

#---------[ State Tracking for Emergency Cleanup ]---------#
$Script:installImageMounted = $false
$Script:bootImageMounted = $false
$Script:offlineRegistryLoaded = $false
$Script:transcriptStarted = $false
$Script:buildWarnings = 0
$Script:buildVersion = $null

$buildProfile = Resolve-BuildProfile -Compress $Compress -Fast:$Fast
if ($ZeroTouch) { Write-Warning "-ZeroTouch: the produced image will ERASE DISK 0 automatically during Windows Setup. Use only on VMs / dedicated test machines." }
Write-Verbose "Build profile: Compress=$($buildProfile.Compress) SkipCleanup=$($buildProfile.SkipCleanup) UseEsd=$($buildProfile.UseEsd)"

if ($Yes) {
    if (-not $ISO)   { throw "-Yes requires -ISO (no interactive prompt available)." }
    if (-not $Index) { throw "-Yes requires -Index (no interactive prompt available)." }
}

#---------[ Emergency Cleanup Trap ]---------#
trap {
    Write-Error "A fatal error interrupted execution: $($_.Exception.Message)"

    if ($Script:offlineRegistryLoaded) {
        Write-Warning "Attempting emergency registry unload..."
        Invoke-SafeOfflineRegistryUnload | Out-Null
        $Script:offlineRegistryLoaded = $false
    }

    if ($Script:bootImageMounted -or $Script:installImageMounted) {
        Write-Warning "Attempting emergency image dismount..."
        Invoke-SafeDismountImage -Path "$ScratchDisk\scratchdir" | Out-Null
        $Script:bootImageMounted = $false
        $Script:installImageMounted = $false
    }

    Dismount-DiskImage -ImagePath $Script:ImagePath -ErrorAction SilentlyContinue | Out-Null
    $Script:MountedByScript = $false
    $Script:ImagePath = $null

    if (Test-Path "$ScratchDisk\scratchdir") {
        Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path "$ScratchDisk\tiny11") {
        Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($Script:transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
        $Script:transcriptStarted = $false
    }

    exit 1
}

#---------[ Execution Policy & Admin Check ]---------#
$needchange = @('AllSigned', 'Restricted', 'Undefined')
$curpolicy = Get-ExecutionPolicy
if ($curpolicy -in $needchange) {
    Write-Output "Your current PowerShell Execution Policy is set to $curpolicy, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope Process -Confirm:$false
    } else {
        Write-Output "The script cannot be run without changing the execution policy. Exiting..."
        exit 1
    }
}

$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Output "Restarting Tiny11 image creator as admin in a new window, you can close this one."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath)
    if ($ISO)       { $argList += @('-ISO', $ISO) }
    if ($SCRATCH)   { $argList += @('-SCRATCH', $SCRATCH) }
    if ($Index)     { $argList += @('-Index', $Index) }
    if ($Custom)    { $argList += '-Custom' }
    if ($Yes)       { $argList += '-Yes' }
    if ($DryRun)    { $argList += '-DryRun' }
    if ($Compress)  { $argList += @('-Compress', $Compress) }
    if ($Fast)      { $argList += '-Fast' }
    if ($ZeroTouch) { $argList += '-ZeroTouch' }
    if ($LowRam)    { $argList += '-LowRam' }
    if ($KeepApps)  { $argList += @('-KeepApps', ($KeepApps -join ',')) }
    $argList += @('-User', $User)
    if ($Password) { $argList += @('-Password', $Password) }
    $argList += @('-TimeZone', $TimeZone)
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = Build-ProcessArgumentString -Arguments $argList
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess) | Out-Null
    exit
}

#---------[ Auto-fetch autounattend.xml if missing (from reforged) ]---------#
if (-not (Test-Path -Path "$PSScriptRoot\autounattend.xml")) {
    Write-Output "autounattend.xml not found. Downloading from upstream..."
    Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile "$PSScriptRoot\autounattend.xml"
}

#---------[ Start Transcript ]---------#
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -Path "$PSScriptRoot\tiny11_$(Get-Date -f yyyyMMdd_HHmmss).log"
$Script:transcriptStarted = $true
$buildStart = Get-Date

$Host.UI.RawUI.WindowTitle = "Tiny11 image creator - Ultimate Edition"
Clear-Host
Write-Output "=== Welcome to the Tiny11 image creator! Ultimate Edition"
Write-Output "    Release: 26-09-2026  |  Based on NairoDorian/tiny11builder_2026"
Write-Output ""

#---------[ Pre-flight Validation ]---------#
Test-Prerequisites
if ($SCRATCH) {
    Test-ScratchDiskNtfs -ScratchPath $ScratchDisk
}
Test-ScratchDiskSpace -ScratchPath $ScratchDisk

#---------[ Dry Run ]---------#
function Get-DryRunSourceImage {
    if ($ISO -match '^[c-zC-Z]$') {
        $base = "$($ISO):"
        $wim = "$base\sources\install.wim"
        if (Test-Path $wim) { return $wim }
        $esd = "$base\sources\install.esd"
        if (Test-Path $esd) { return $esd }
    } elseif ($ISO -and (Test-Path -LiteralPath $ISO -PathType Leaf) -and $ISO -match '\.iso$') {
        try {
            $mountInfo = Mount-IsoAndGetDriveLetter -ImagePath $ISO
            $wim = "$($mountInfo.DriveRoot)sources\install.wim"
            $esd = "$($mountInfo.DriveRoot)sources\install.esd"
            Dismount-DiskImage -ImagePath $mountInfo.ImagePath -ErrorAction SilentlyContinue | Out-Null
            if (Test-Path $wim) { return $wim }
            if (Test-Path $esd) { return $esd }
        } catch {
            Write-Warning "Could not mount ISO for dry-run check: $_"
        }
    }
    $wim = "$ScratchDisk\sources\install.wim"
    if (Test-Path $wim) { return $wim }
    $esd = "$ScratchDisk\sources\install.esd"
    if (Test-Path $esd) { return $esd }
    return $null
}

$preflightImage = Get-DryRunSourceImage
$availableIndexes = @()
if ($preflightImage -and (Test-Path $preflightImage)) {
    $wimInfoText = & 'dism' '/English' '/Get-WimInfo' "/wimfile:$preflightImage" 2>&1
    $availableIndexes = Get-AvailableImageIndex $wimInfoText
}
$availableIndexList = @($availableIndexes.Index)

$indexOk = (-not $Index) -or (Test-ImageIndexAvailable $Index $availableIndexes)
$indexMsg = if ($availableIndexes.Count) {
    "Available indexes: " + (($availableIndexes | ForEach-Object { "$($_.Index) = $($_.Name)" }) -join '; ')
} else { "Could not read any image indexes from '$preflightImage'." }

$chosenSizeBytes = if ($Index) {
    [long](($availableIndexes | Where-Object Index -eq $Index | Select-Object -First 1).SizeBytes)
} elseif ($availableIndexes.Count) {
    [long](($availableIndexes.SizeBytes | Measure-Object -Maximum).Maximum)
} else { [long]0 }
$requiredBytes = Get-RequiredScratchBytes $chosenSizeBytes
$scratchQualifier = if ($ScratchDisk) { Split-Path -Qualifier $ScratchDisk } else { $PSScriptRoot }
$freeBytes = [long]((Get-PSDrive -Name ($scratchQualifier.TrimEnd(':')) -ErrorAction SilentlyContinue).Free)
$space = Test-SufficientScratch $requiredBytes $freeBytes

$hostArch = $Env:PROCESSOR_ARCHITECTURE
$archForOscdimg = Resolve-Architecture -HostArchitecture $hostArch
$adkOscdimg = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$archForOscdimg\Oscdimg\oscdimg.exe"
$WinSDKPath = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots", "KitsRoot10", $null)
if (-not $WinSDKPath) {
    $WinSDKPath = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Kits\Installed Roots", "KitsRoot10", $null)
}
if ($WinSDKPath) {
    $WinSDKPath = $WinSDKPath.TrimEnd('\')
    $adkOscdimg = "$WinSDKPath\Assessment and Deployment Kit\Deployment Tools\$archForOscdimg\Oscdimg\oscdimg.exe"
}
$bundledOscdimg = "$PSScriptRoot\oscdimg.exe"
$oscdimgSource = Resolve-OscdimgSource (Test-Path $adkOscdimg) (Test-Path $bundledOscdimg)
$oscdimgOk = ($oscdimgSource -ne 'download')

if ($DryRun) {
    Write-Output ""
    Write-Output "===== DRY RUN (no copy / no mount performed) ====="
    Write-Output "  Image drive (-ISO)    : $(if ($ISO) { $ISO } else { '(prompt at build time)' })"
    Write-Output "  Scratch (-SCRATCH)    : $ScratchDisk"
    Write-Output "  Image index (-Index)  : $(if ($Index) { $Index } else { '(prompt at build time)' })"
    Write-Output "  Build mode            : $(if ($ZeroTouch) { 'ZeroTouch (ERASES disk 0)' } else { 'OOBE-skip (keeps disk selection)' })"
    Write-Output "  Custom app selection  : $(if ($Custom) { 'YES' } else { 'NO (all packages in removePackage.txt)' })"
    Write-Output "  Low-RAM profile       : $(if ($LowRam) { 'YES' } else { 'NO' })"
    if ($Index -and -not $indexOk) {
        Write-Output "     ERROR: index $Index not found. $indexMsg"
    } elseif ($availableIndexes.Count) {
        Write-Output "     [OK] image has indexes: $($availableIndexList -join ', ')"
    }
    Write-Output ("  Scratch free space    : {0} GB free, ~{1} GB required  [{2}]" -f $space.FreeGB, $space.RequiredGB, $(if ($space.Ok) { 'OK' } else { 'INSUFFICIENT' }))
    Write-Output ("  ISO builder (oscdimg)  : {0}  [{1}]" -f $oscdimgSource, $(if ($oscdimgOk) { 'OK' } else { 'will download at build time' }))
    Write-Output "  Compression           : $($buildProfile.Compress)"
    Write-Output "  Skip component cleanup: $($buildProfile.SkipCleanup)"
    if (-not $preflightImage -or -not (Test-Path $preflightImage)) {
        Write-Output "     ERROR: no install.wim or install.esd found under the source."
    }
    Write-Output "  Planned steps: copy image -> mount install.wim -> remove provisioned Appx -> remove Edge/OneDrive -> registry tweaks -> TaskCache ACL takeover -> $(if ($buildProfile.SkipCleanup) { 'skip' } else { 'component cleanup' }) -> unmount/commit -> export ($($buildProfile.Compress)) -> bypass boot.wim -> create ISO"
    Write-Output "===== END DRY RUN ====="
    $dryRunFailed = ((-not $preflightImage) -or ($preflightImage -and (Test-Path $preflightImage) -eq $false)) -or ($Index -and -not $indexOk) -or (-not $space.Ok)
    Stop-Transcript -ErrorAction SilentlyContinue
    if ($dryRunFailed) { exit 1 } else { exit 0 }
}

#---------[ Resolve Source ISO / Drive ]---------#
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
$script:MountedByScript = $false
$script:ImagePath = $null
$DriveLetter = Resolve-WindowsSource -IsoParameter $ISO

#---------[ Copy Windows Image ]---------#
Write-Output "Copying Windows image..."
if (Get-Command 'robocopy.exe' -ErrorAction SilentlyContinue) {
    Invoke-Robocopy -Source "$DriveLetter\" -Destination "$ScratchDisk\tiny11"
} else {
    Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
}

if ($Script:MountedByScript -and $Script:ImagePath) {
    Dismount-DiskImage -ImagePath $Script:ImagePath -ErrorAction SilentlyContinue | Out-Null
    $Script:MountedByScript = $false
    Write-Output "Source ISO unmounted after copy."
}

if (Test-Path "$ScratchDisk\tiny11\sources\install.esd") {
    Clear-FileReadOnly -FilePath "$ScratchDisk\tiny11\sources\install.esd"
    Remove-Item "$ScratchDisk\tiny11\sources\install.esd" -Force -ErrorAction SilentlyContinue | Out-Null
}
Write-Output "Copy complete!"
Start-Sleep -Seconds 2

#---------[ ESD to WIM Conversion & Index Resolution ]---------#
Write-Output "Getting image information:"
$imageIndex = $null
if ($Index) { $imageIndex = $Index }

if (-not (Test-Path "$ScratchDisk\tiny11\sources\install.wim")) {
    if (Test-Path "$ScratchDisk\tiny11\sources\install.esd") {
        Write-Output "Found install.esd, converting to install.wim..."
        $esdIndex = Resolve-InstallImageIndex -ImagePath "$ScratchDisk\tiny11\sources\install.esd" -PreferredIndex $null
        Write-Output 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath "$ScratchDisk\tiny11\sources\install.esd" -SourceIndex $esdIndex -DestinationImagePath "$ScratchDisk\tiny11\sources\install.wim" -CompressionType Maximum -CheckIntegrity
        $imageIndex = 1
    } else {
        throw "Can't find install.wim or install.esd after copy. Provide a valid Windows 11 ISO."
    }
}

# Validate the chosen index against available indexes in the copied install.wim
$srcWimInfo = & 'dism' '/English' '/Get-WimInfo' "/wimfile:$ScratchDisk\tiny11\sources\install.wim" 2>&1
$availableIndexes = Get-AvailableImageIndex $srcWimInfo
$availableIndexList = @($availableIndexes.Index)

while ($availableIndexList -notcontains $imageIndex) {
    if ($Yes) { throw "Image index '$imageIndex' not found in install.wim. $indexMsg" }
    & 'dism' '/English' '/Get-WimInfo' "/wimfile:$ScratchDisk\tiny11\sources\install.wim"
    $inputIndex = Read-Host 'Please enter the image index number from the list above'
    $imageIndex = [int]$inputIndex
}

#---------[ Mount install.wim ]---------#
Clear-Host
Write-Output "=== Mounting Windows image. This may take a while."
$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)" | Out-Null
Clear-FileReadOnly -FilePath $wimFilePath
Initialize-ScratchWorkspace -ScratchRoot $ScratchDisk
Mount-WindowsImage -ImagePath $wimFilePath -Index $imageIndex -Path "$ScratchDisk\scratchdir"
$Script:installImageMounted = $true

#---------[ Detect Architecture, Language, Build Version ]---------#
$imageIntl = & dism /English /Get-Intl "/Image:$($ScratchDisk)\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
if ($languageLine) {
    $languageCode = $Matches[1]
    Write-Output "Default system UI language code: $languageCode"
} else {
    $languageCode = 'en-US'
    Write-Output "Default system UI language code not found. Defaulting to en-US."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($ScratchDisk)\tiny11\sources\install.wim" "/index:$imageIndex"
$lines = $imageInfo -split "`r`n"
$architecture = $null
foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        if ($architecture -eq 'x64') { $architecture = 'amd64' }
        Write-Output "Architecture: $architecture"
        break
    }
}
if (-not $architecture) {
    throw "Could not detect image architecture. Cannot apply arch-specific changes or select autoundate."
}

# Detect Windows version (for version-gated TaskCache GUIDs)
$windowsIs24H2 = $false
$buildVersionLine = & reg query "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2>$null | Select-String -Pattern '(\d+H\d+)'
if ($buildVersionLine) {
    $Script:buildVersion = $buildVersionLine.Matches.Groups[1].Value
    $windowsIs24H2 = ($Script:buildVersion -eq '24H2' -or $Script:buildVersion -eq '25H2')
    Write-Output "Detected Windows version: $Script:buildVersion (24H2+ mode: $windowsIs24H2)"
} else {
    $versionLine = & reg query "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2>$null
    if ($versionLine -match '(\d+H\d+)') {
        $Script:buildVersion = $Matches[1]
        $windowsIs24H2 = ($Script:buildVersion -eq '24H2' -or $Script:buildVersion -eq '25H2')
        Write-Output "Detected Windows version: $Script:buildVersion (24H2+ mode: $windowsIs24H2)"
    } else {
        Write-Output "Could not detect Windows version. Using legacy TaskCache GUIDs."
    }
}

Write-Output "Mounting complete! Performing removal of applications..."

#---------[ Load Package Removal List ]---------#
$packagePrefixes = Get-Content -Path "$PSScriptRoot\removePackage.txt" |
    Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { $_.Trim() } |
    Select-Object -Unique

if ($KeepApps) {
    $packagePrefixes = $packagePrefixes + $KeepApps | Select-Object -Unique
    Write-Output "Additional packages added to removal list via -KeepApps."
}

if ($Custom) {
    try {
        $selectedPrefixes = @(Show-PackageSelector -Items $packagePrefixes -DefaultAll)
    } catch {
        Write-Warning "Interactive selector failed or was interrupted. Defaulting to all configured prefixes."
        $selectedPrefixes = @($packagePrefixes)
    }
    if (-not $selectedPrefixes -or $selectedPrefixes.Count -eq 0) {
        Write-Output "No package prefixes selected for removal. Skipping Appx package removal step."
        $packagesToRemove = @()
    } else {
        Write-Output "Selected package prefixes to remove:"
        $selectedPrefixes | ForEach-Object { Write-Output " - $_" }
        $packagesToRemove = Get-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" |
            ForEach-Object { $_.PackageName } |
            Where-Object {
                $pkg = $_
                $selectedPrefixes | Where-Object { $pkg -like "*$_*" }
            }
    }
} else {
    $packagesToRemove = Get-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" |
        ForEach-Object { $_.PackageName } |
        Where-Object {
            $pkg = $_
            $packagePrefixes | Where-Object { $pkg -like "*$_*" }
        }
}

$appsTotal = @($packagesToRemove).Count
$appsRemoved = 0
foreach ($package in $packagesToRemove) {
    Write-Output "Removing provisioned package: $package"
    try {
        Remove-AppxProvisionedPackage -Path "$ScratchDisk\scratchdir" -PackageName $package | Out-Null
        $appsRemoved++
    } catch {
        Write-Warning "Failed to remove package $package. Continuing."
        $Script:buildWarnings++
    }
}

#---------[ Remove Edge ]---------#
$removeEdge = ($preset.RemoveEdge) -and ((-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.MicrosoftEdge.Stable') -or (Test-PrefixSelected $selectedPrefixes 'Edge'))
if ($removeEdge) {
    Write-Output "Removing Edge:"
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

    $edgeWinSxSPattern = if ($architecture -eq 'arm64') { "arm64_microsoft-edge-webview_31bf3856ad364e35*" } else { "amd64_microsoft-edge-webview_31bf3856ad364e35*" }
    $edgeWinSxS = Get-ChildItem -Path "$ScratchDisk\scratchdir\Windows\WinSxS" -Filter $edgeWinSxSPattern -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    if ($edgeWinSxS) {
        & 'takeown' '/f' $edgeWinSxS '/r' | Out-Null
        & 'icacls' $edgeWinSxS '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
        Remove-Item -Path $edgeWinSxS -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }

    & 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' 2>$null | Out-Null
    & 'icacls' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>$null | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
}

#---------[ Remove OneDrive ]---------#
$removeOneDrive = ($preset.RemoveOneDrive) -and ((-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'OneDrive'))
if ($removeOneDrive) {
    Write-Output "Removing OneDrive:"
    if (Test-Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe") {
        & 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" | Out-Null
        & 'icacls' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
        Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue | Out-Null
    } else {
        Write-Output "OneDriveSetup.exe not present, skipping."
    }
}

#---------[ Optional Utilities (granular control via -Keep/-Remove) ]---------#
Write-Output "Resolving optional utilities..."
$resolvedUtils = Resolve-OptionalUtilities -Keep $Keep -Remove $Remove
if ($resolvedUtils.RemovePrefixes) {
    $selectedPrefixes = $selectedPrefixes + $resolvedUtils.RemovePrefixes
    Write-Output "Optional utilities to remove: $($resolvedUtils.RemovePrefixes -join ', ')"
    Write-Output "Optional utilities kept: $($resolvedUtils.KeptNames -join ', ')"
} else {
    Write-Output "No optional utilities to remove."
}

#---------[ Optional Windows Capabilities ]---------#
Write-Output "Removing optional Windows capabilities (capabilities)..."
$capsToRemove = Get-OptionalCapabilitiesToRemove -LanguageCode $LanguageCode -Preset $preset
foreach ($cap in $capsToRemove) {
    try {
        Remove-WindowsCapability -Path "$ScratchDisk\scratchdir" -Name $cap -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed to remove capability: $cap"
    }
}
Write-Output "Capability removal complete."

#---------[ Additional Windows Packages (language-aware) ]---------#
if ($preset.RemoveWindowsPackages) {
    Write-Output "Removing additional language-specific Windows packages..."
    $packagesToRemove = Get-AdditionalWindowsPackagesToRemove -LanguageCode $LanguageCode -Preset $preset
    foreach ($pkg in $packagesToRemove) {
        try {
            Dism.exe /Image:"$ScratchDisk\scratchdir" /Remove-Package /PackageName:$pkg /NoRestart /quiet | Out-Null
            Assert-CommandExitCode -Label "Remove-Package: $pkg"
        } catch {
            Write-Warning "Failed to remove package: $pkg"
        }
    }
    Write-Output "Additional package removal complete."
}

#---------[ Remove residual bloatware files (Edge/WebView/OneDrive) ]---------#
Write-Output "Removing residual bloatware files..."
Remove-BloatwareFiles -MountPath "$ScratchDisk\scratchdir" -Architecture $architecture -RemoveEdge:$removeEdge -RemoveOneDrive:$removeOneDrive
Write-Output "Residual file removal complete."

Write-Output "Removal complete!"
Start-Sleep -Seconds 2
Clear-Host

#---------[ Load Registry Hives ]---------#
Write-Output "Loading registry..."
Invoke-RegLoad -HiveName 'zCOMPONENTS' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS"
Invoke-RegLoad -HiveName 'zDEFAULT' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\default"
Invoke-RegLoad -HiveName 'zNTUSER' -FilePath "$ScratchDisk\scratchdir\Users\Default\ntuser.dat"
Invoke-RegLoad -HiveName 'zSOFTWARE' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE"
Invoke-RegLoad -HiveName 'zSYSTEM' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM"
$Script:offlineRegistryLoaded = $true

#---------[ System Requirements Bypass ]---------#
Write-Output "Bypassing system requirements (on the system image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'

#---------[ Disable Sponsored Apps ]---------#
Write-Output "Disabling Sponsored Apps:"
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
# Version-gated: SuggestedApps key does not exist on 24H2+ builds
if (-not $windowsIs24H2) {
    Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
}
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'

#---------[ OOBE / Local Account Bypass ]---------#
Write-Output "Enabling Local Accounts on OOBE:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
$autoundatePath = Resolve-AutounattendFile -Architecture $architecture
if ($autoundatePath -and (Test-Path $autoundatePath)) {
    Copy-AutounattendWithIndex -SourcePath $autoundatePath -DestinationPath "$ScratchDisk\scratchdir\Windows\System32\Sysprep\autounattend.xml" -ImageIndex 1
}

#---------[ Reserved Storage ]---------#
Write-Output "Disabling Reserved Storage:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'

#---------[ BitLocker ]---------#
Write-Output "Disabling BitLocker Device Encryption"
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'

#---------[ Chat Icon ]---------#
Write-Output "Disabling Chat icon:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'

#---------[ Edge Registry Removal ]---------#
if ($removeEdge) {
    Write-Output "Removing Edge related registries"
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
}

#---------[ OneDrive Registry ]---------#
if ($removeOneDrive) {
    Write-Output "Disabling OneDrive folder backup"
    Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
}

#---------[ Search Highlights ]---------#
Write-Output "Disabling Search Highlights:"
Set-RegistryValue 'HKLM\zSoftware\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 'REG_DWORD' '0'

#---------[ Telemetry & Privacy ]---------#
Write-Output "Disabling Telemetry:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 'REG_DWORD' '0'

#---------[ Driver Auto-Install Prompt ]---------#
if (-not $Yes) {
    $response = Read-Host "Prevent Windows from automatically installing device drivers? (y/N)"
    if ($response -match '^(?i:y|yes)$') {
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 'REG_DWORD' '0'
        Write-Output "Automatic device driver installation was disabled for the offline image."
    } else {
        Write-Output "Keeping default driver installation behavior."
    }
}

#---------[ Prevent Outlook / DevHome / Copilot / Teams Re-installation ]---------#
$removeDevHome = ($preset.RemoveAI) -and ((-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.Windows.DevHome'))
$removeOutlook = (-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.OutlookForWindows')
$removeCopilot = ($preset.RemoveAI) -and ((-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.Windows.Copilot') -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.Copilot'))
$removeTeams = (-not $Custom) -or (Test-PrefixSelected $selectedPrefixes 'Microsoft.Windows.Teams') -or (Test-PrefixSelected $selectedPrefixes 'MicrosoftTeams') -or (Test-PrefixSelected $selectedPrefixes 'MSTeams')

if ($removeOutlook) {
    Write-Output "Prevent installation of Outlook:"
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
    Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'
}

if ($removeDevHome) {
    Write-Output "Prevents installation of DevHome:"
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
    Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
}

if ($removeCopilot) {
    Write-Output "Disabling Copilot"
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsNotepad' 'DisableAIFeatures' 'REG_DWORD' '1'
    Write-Output "Preventing Recall data analysis:"
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'REG_DWORD' '1'
}

if ($removeTeams) {
    Write-Output "Prevents installation of Teams:"
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
}

#---------[ Scheduled Task File Deletion ]---------#
Write-Host "Deleting scheduled task definition files..."
$tasksPath = "$ScratchDisk\scratchdir\Windows\System32\Tasks"
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
Write-Host "Task files have been deleted."

#---------[ Extended Telemetry & Performance Tweaks (from preset) ]---------#
Write-Output "Applying extended telemetry and performance tweaks..."
Apply-ExtendedTweaks -Preset $preset

#---------[ TaskCache Registry ACL Takeover + GUID Deletion ]---------#
Write-Host "Deleting scheduled task cache entries..."
$taskCacheGuids = Get-TaskCacheGuidsForBuild -BuildVersion $Script:buildVersion
Write-Host "Preparing ACL permissions for TaskCache entries..."
$taskCacheAclReady = Enable-TaskCacheWriteAccess -AdminGroup $adminGroup
if (-not $taskCacheAclReady) {
    Write-Warning "TaskCache ACL hardening did not complete. Continuing with best-effort deletion."
}
Remove-TaskCacheEntries -TaskGuids $taskCacheGuids

#---------[ Low-RAM Profile (optional) ]---------#
if ($LowRam) {
    $lowRamProfile = Join-Path $PSScriptRoot 'tiny11LegacyProfile.ps1'
    if (Test-Path $lowRamProfile) {
        Write-Output "Applying 1 GB-class low-RAM profile..."
        . $lowRamProfile
        Invoke-Tiny11LowRamProfile
    } else {
        Write-Warning "Low-RAM profile script not found. Skipping."
    }
}

#---------[ Unmount Registry ]---------#
Write-Output "Unmounting Registry..."
foreach ($hive in @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')) {
    Invoke-RegUnload -HiveName $hive
}
$Script:offlineRegistryLoaded = $false

#---------[ Component Cleanup ]---------#
Write-Output "Cleaning up image..."
if ($buildProfile.SkipCleanup) {
    Write-Output "Skipping component cleanup (-Fast)."
} else {
    Invoke-DismChecked -Label 'DISM cleanup' /Image:$ScratchDisk\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase
    Write-Output "Cleanup complete."
}

#---------[ Dismount install.wim ]---------#
Write-Output "Unmounting image..."
if (-not (Invoke-SafeDismountImage -Path "$ScratchDisk\scratchdir" -Save)) {
    throw "Failed to dismount the install image safely."
}
$Script:installImageMounted = $false

#---------[ Export Image ]---------#
Write-Host "Exporting image (compress: $($buildProfile.Compress))..."
Invoke-DismChecked -Label 'DISM export install.wim' /Export-Image /SourceImageFile:"$ScratchDisk\tiny11\sources\install.wim" /SourceIndex:$imageIndex /DestinationImageFile:"$ScratchDisk\tiny11\sources\install2.wim" /Compress:$($buildProfile.WimExportCompress)
if (-not (Test-Path "$ScratchDisk\tiny11\sources\install2.wim")) {
    throw "DISM export failed: install2.wim was not created."
}
Remove-Item -Path "$ScratchDisk\tiny11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny11\sources\install2.wim" -NewName "install.wim" | Out-Null
if (-not (Test-Path "$ScratchDisk\tiny11\sources\install.wim")) {
    throw "Failed to replace install.wim after export."
}
$imageIndex = 1
Write-Output "Windows image completed. Continuing with boot.wim."
Start-Sleep -Seconds 2
Clear-Host

#---------[ Mount boot.wim and Apply Bypass ]---------#
Write-Output "Mounting boot image:"
$wimFilePath = "$ScratchDisk\tiny11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)" | Out-Null
Clear-FileReadOnly -FilePath $wimFilePath
$bootWimIndex = Get-BootWimIndex -BootWimPath "$ScratchDisk\tiny11\sources\boot.wim"
Write-Output "Using boot.wim index $bootWimIndex"
Initialize-ScratchWorkspace -ScratchRoot $ScratchDisk
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny11\sources\boot.wim" -Index $bootWimIndex -Path "$ScratchDisk\scratchdir"
$Script:bootImageMounted = $true

Write-Output "Loading registry..."
Invoke-RegLoad -HiveName 'zCOMPONENTS' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS"
Invoke-RegLoad -HiveName 'zDEFAULT' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\default"
Invoke-RegLoad -HiveName 'zNTUSER' -FilePath "$ScratchDisk\scratchdir\Users\Default\ntuser.dat"
Invoke-RegLoad -HiveName 'zSOFTWARE' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE"
Invoke-RegLoad -HiveName 'zSYSTEM' -FilePath "$ScratchDisk\scratchdir\Windows\System32\config\SYSTEM"

Write-Output "Bypassing system requirements (on the setup image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'

Write-Output "Tweaking complete!"
Write-Output "Unmounting Registry..."
foreach ($hive in @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')) {
    Invoke-RegUnload -HiveName $hive
}
Write-Output "Unmounting image..."
if (-not (Invoke-SafeDismountImage -Path "$ScratchDisk\scratchdir" -Save)) {
    throw "Failed to dismount the boot image safely."
}
$Script:bootImageMounted = $false

#---------[ Create ISO ]---------#
Clear-Host
Write-Output "========================================"
Write-Output "The tiny11 image is now completed. Proceeding with the making of the ISO..."
Write-Output "Copying unattended file for bypassing MS account on OOBE..."

$finalUnattendSource = Resolve-AutounattendFile -Architecture $architecture
Copy-AutounattendWithIndex -SourcePath $finalUnattendSource -DestinationPath "$ScratchDisk\tiny11\autounattend.xml" -ImageIndex 1

Assert-IsoBootFiles -ImageRoot "$ScratchDisk\tiny11"
Write-Output "Creating ISO image..."

$OSCDIMG = Initialize-Oscdimg -HostArchitecture $hostArch
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny11\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" "$PSScriptRoot\tiny11.iso"

$isoExit = $LASTEXITCODE
$isoResult = "$PSScriptRoot\tiny11.iso"
$isoOk = Test-Path $isoResult
$isoLen = if ($isoOk) { (Get-Item $isoResult).Length } else { [long]0 }
if (-not (Test-IsoResult -ExitCode $isoExit -IsoExists $isoOk -IsoBytes $isoLen)) {
    throw "ISO creation failed (oscdimg exit $isoExit); no valid tiny11.iso was produced at $isoResult."
}

#---------[ Build Summary ]---------#
$elapsed = (Get-Date) - $buildStart
$isoPath = "$PSScriptRoot\tiny11.iso"
$isoBytes = if (Test-Path $isoPath) { (Get-Item $isoPath).Length } else { 0 }
Format-BuildSummary -Elapsed $elapsed -IsoBytes $isoBytes -IsoPath $isoPath -AppsRemoved $appsRemoved -AppsTotal $appsTotal -Warnings $Script:buildWarnings |
    ForEach-Object { Write-Output $_ }

#---------[ Cleanup ]---------#
Write-Output "Creation completed!"
if (-not $Yes) { Read-Host "Press Enter to continue" }
Write-Output "Performing Cleanup..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "Ejecting ISO drive..."
if ($DriveLetter) {
    Get-Volume -DriveLetter $DriveLetter[0] -ErrorAction SilentlyContinue | Get-DiskImage -ErrorAction SilentlyContinue | Dismount-DiskImage -ErrorAction SilentlyContinue
}
Write-Output "Iso drive ejected"

Write-Output "Removing oscdimg.exe..."
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Write-Output "Removing autounattend.xml..."
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

# Verify cleanup
foreach ($checkPath in @("$ScratchDisk\tiny11", "$ScratchDisk\scratchdir")) {
    if (Test-Path $checkPath) {
        Write-Output "$checkPath still exists. Attempting to remove it again..."
        Remove-Item -Path $checkPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path "$PSScriptRoot\oscdimg.exe") {
    Write-Output "oscdimg.exe still exists. Attempting to remove it again..."
    Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
}

Stop-Transcript -ErrorAction SilentlyContinue
exit 0
