<#
.SYNOPSIS
    Builds a significantly reduced (Core) Windows 11 image — ultra-small for VMs.

.DESCRIPTION
    Tiny11 Core aggressively strips WinSxS, removes system packages, WinRE, and
    disables Windows Update / Defender. NOT serviceable after creation (no
    language packs, updates, or features can be added). Perfect for rapid
    testing / development VMs.

    Ultimate Edition: modular functions from lib/tiny11utils.psm1, emergency
    cleanup trap, proper registry hive tracking, architecture-aware WinSxS
    preservation, retry logic, and ESD export.

.PARAMETER ISO
    Drive letter of the mounted Windows 11 ISO (e.g. E), or a path to a .iso file.

.PARAMETER SCRATCH
    Drive letter of the desired scratch disk (e.g. D). Defaults to script folder.

.PARAMETER Index
    Image index to build (an ISO can hold several editions).

.PARAMETER Yes
    Non-interactive; requires -ISO and -Index.

.PARAMETER KeepApps
    Comma-separated list of package prefixes to ADD to removal (overrides removePackage.txt).

.PARAMETER Help
    Show usage and exit.

.NOTES
    Ultimate Edition build from NairoDorian/tiny11builder_2026.
#>

param (
    [Parameter(Position = 0)]
    [string]$ISO,
    [Parameter(Position = 1)]
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH,
    [int]$Index,
    [switch]$Yes,
    [string[]]$KeepApps,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'
$InformationPreference = 'Continue'

$utilsModulePath = Join-Path $PSScriptRoot 'lib\tiny11utils.psm1'
if (-not (Test-Path -Path $utilsModulePath -PathType Leaf)) {
    Write-Error "Required module not found: $utilsModulePath"
    exit 1
}
Import-Module -Name $utilsModulePath -Force

if ($Help) {
    Write-Output @'
tiny11 Core builder - Ultimate Edition

USAGE:
  .\tiny11Coremaker.ps1 -ISO <drive> -Index <n> [options]

  -ISO <letter|path>  Drive letter of mounted Windows 11 ISO, or a .iso file path
  -Index <n>          Image index to build
  -Yes                Non-interactive; requires -ISO and -Index
  -SCRATCH <letter>   Scratch/work drive (default: script folder drive)
  -KeepApps <list>    Comma-separated prefixes to always remove
  -Help               Show this help and exit
'@
    exit 0
}

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

#---------[ State Tracking for Emergency Cleanup ]---------#
$Script:installImageMounted = $false
$Script:bootImageMounted = $false
$Script:offlineRegistryLoaded = $false
$Script:transcriptStarted = $false
$Script:buildWarnings = 0
$Script:buildVersion = $null

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
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Output "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
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
    Write-Output "Restarting Tiny11 Core builder as admin in a new window, you can close this one."
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath)
    if ($ISO)       { $argList += @('-ISO', $ISO) }
    if ($SCRATCH)   { $argList += @('-SCRATCH', $SCRATCH) }
    if ($Index)     { $argList += @('-Index', $Index) }
    if ($Yes)       { $argList += '-Yes' }
    if ($KeepApps)  { $argList += @('-KeepApps', ($KeepApps -join ',')) }
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = Build-ProcessArgumentString -Arguments $argList
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess) | Out-Null
    exit
}

#---------[ Start Transcript ]---------#
Start-Transcript -Path "$PSScriptRoot\tiny11core_$(Get-Date -f yyyyMMdd_HHmmss).log"
$Script:transcriptStarted = $true
$buildStart = Get-Date

$Host.UI.RawUI.WindowTitle = "Tiny11 Core image creator - Ultimate Edition"
Clear-Host
Write-Output "=== Welcome to the Tiny11 Core image creator! Ultimate Edition"
Write-Output "    Release: 26-09-2026  |  Based on NairoDorian/tiny11builder_2026"
Write-Output "    WARNING: This produces a NON-SERVICEABLE image. No language packs, updates,"
Write-Output "    or features can be added after creation. For VMs and testing only."
Write-Output ""

if (-not $Yes) {
    Write-Output "Do you want to continue? (y/n)"
    $input = Read-Host
    if ($input -ne 'y') {
        Write-Output "Aborting."
        Stop-Transcript -ErrorAction SilentlyContinue
        exit 0
    }
}

New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
$scratchDir = "$ScratchDisk\scratchdir"

#---------[ Resolve Source ISO / Drive ]---------#
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

$srcWimInfo = & 'dism' '/English' '/Get-WimInfo' "/wimfile:$ScratchDisk\tiny11\sources\install.wim" 2>&1
$availableIndexes = Get-AvailableImageIndex $srcWimInfo
$availableIndexList = @($availableIndexes.Index)

while ($availableIndexList -notcontains $imageIndex) {
    if ($Yes) { throw "Image index '$imageIndex' not found." }
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
Mount-WindowsImage -ImagePath $wimFilePath -Index $imageIndex -Path $scratchDir
$Script:installImageMounted = $true

#---------[ Detect Architecture & Language ]---------#
$imageIntl = & dism /English /Get-Intl "/Image:$scratchDir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-z]{2})' }
if ($languageLine) {
    $languageCode = $Matches[1]
    Write-Output "Default system UI language code: $languageCode"
} else {
    $languageCode = 'en-US'
    Write-Output "Default system UI language code not found. Defaulting to en-US."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$ScratchDisk\tiny11\sources\install.wim" "/index:$imageIndex"
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

# Detect Windows version
$versionLine = & reg query "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion 2>$null | Select-String -Pattern '(\d+H\d+)'
if ($versionLine) {
    $Script:buildVersion = $versionLine.Matches.Groups[1].Value
    Write-Output "Detected Windows version: $Script:buildVersion"
}

Write-Output "Mounting complete! Performing removal of applications..."

#---------[ Load Package Removal List ]---------#
$packagePrefixes = Get-Content -Path "$PSScriptRoot\removePackage.txt" |
    Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') } |
    ForEach-Object { $_.Trim() } |
    Select-Object -Unique

if ($KeepApps) {
    $packagePrefixes = $packagePrefixes + $KeepApps | Select-Object -Unique
}

#---------[ Remove Provisioned Appx Packages ]---------#
$dismAppx = & 'dism' '/English' "/image:$scratchDir" '/Get-ProvisionedAppxPackages'
$packages = $dismAppx | ForEach-Object {
    if ($_ -match 'PackageName : (.*)') { $Matches[1] }
}

$packagesToRemove = $packages | Where-Object {
    $packageName = $_
    $packagePrefixes | Where-Object { $packageName -like "*$_*" }
}
foreach ($package in $packagesToRemove) {
    Write-Output "Removing $package :"
    & 'dism' '/English' "/image:$scratchDir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}

#---------[ Remove System Packages ]---------#
Write-Output "Removing system packages (services/features not needed in Core)..."
$systemPackagePatterns = @(
    "Microsoft-Windows-InternetExplorer-Optional-Package~31bf3856ad364e35",
    "Microsoft-Windows-Kernel-LA57-FoD-Package~31bf3856ad364e35~",
    "Microsoft-Windows-LanguageFeatures-Handwriting-$languageCode-Package~31bf3856ad364e35",
    "Microsoft-Windows-LanguageFeatures-OCR-$languageCode-Package~31bf3856ad364e35",
    "Microsoft-Windows-LanguageFeatures-Speech-$languageCode-Package~31bf3856ad364e35",
    "Microsoft-Windows-LanguageFeatures-TextToSpeech-$languageCode-Package~31bf3856ad364e35",
    "Microsoft-Windows-MediaPlayer-Package~31bf3856ad364e35",
    "Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~31bf3856ad364e35",
    "Windows-Defender-Client-Package~31bf3856ad364e35~",
    "Microsoft-Windows-WordPad-FoD-Package~",
    "Microsoft-Windows-TabletPCMath-Package~",
    "Microsoft-Windows-StepsRecorder-Package~"
)

$allPackageIds = @(& dism /image:$scratchDir /Get-Packages /Format:Table |
    Where-Object { $_ -match '^\S+\.mum' } |
    ForEach-Object { ($_ -split '\s+')[0] })

foreach ($packagePattern in $systemPackagePatterns) {
    $pkgs = $allPackageIds | Where-Object { $_ -like "$packagePattern*" }
    foreach ($packageIdentity in $pkgs) {
        Write-Output "Removing $packageIdentity..."
        Invoke-DismChecked -Label 'DISM Remove-Package' /Image:$scratchDir /Remove-Package /PackageName:$packageIdentity
    }
}

#---------[ .NET 3.5 Prompt ]---------#
if (-not $Yes) {
    Write-Output "Do you want to enable .NET 3.5? This cannot be done after the image has been created! (y/n)"
    $netInput = Read-Host
    if ($netInput -eq 'y') {
        Write-Output "Enabling .NET 3.5..."
        Invoke-DismChecked -Label 'DISM Enable NetFX3' /Image:$scratchDir /Enable-Feature /FeatureName:NetFX3 /All /Source:"$ScratchDisk\tiny11\sources\sxs"
        Write-Output ".NET 3.5 has been enabled."
    } else {
        Write-Output "Skipping .NET 3.5..."
    }
}

#---------[ Remove Edge ]---------#
Write-Output "Removing Edge:"
Remove-Item -Path "$scratchDir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$scratchDir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Remove-Item -Path "$scratchDir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

$edgeWinSxSPattern = if ($architecture -eq 'arm64') { "arm64_microsoft-edge-webview_31bf3856ad364e35*" } else { "amd64_microsoft-edge-webview_31bf3856ad364e35*" }
$edgeWinSxS = Get-ChildItem -Path "$scratchDir\Windows\WinSxS" -Filter $edgeWinSxSPattern -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
if ($edgeWinSxS) {
    & 'takeown' '/f' $edgeWinSxS '/r' 2>$null | Out-Null
    & 'icacls' $edgeWinSxS '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>$null | Out-Null
    Remove-Item -Path $edgeWinSxS -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
}

& 'takeown' '/f' "$scratchDir\Windows\System32\Microsoft-Edge-Webview" '/r' 2>$null | Out-Null
& 'icacls' "$scratchDir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>$null | Out-Null
Remove-Item -Path "$scratchDir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

#---------[ Remove WinRE ]---------#
Write-Output "Removing WinRE"
& 'takeown' '/f' "$scratchDir\Windows\System32\Recovery" '/r' 2>$null | Out-Null
& 'icacls' "$scratchDir\Windows\System32\Recovery" '/grant' 'Administrators:F' '/T' '/C' 2>$null | Out-Null
Remove-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -Recurse -Force -ErrorAction SilentlyContinue
try {
    New-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -ItemType File -Force | Out-Null
} catch {
    Write-Warning "Could not create placeholder winre.wim."
    $Script:buildWarnings++
}

#---------[ Remove OneDrive ]---------#
Write-Output "Removing OneDrive:"
if (Test-Path "$scratchDir\Windows\System32\OneDriveSetup.exe") {
    & 'takeown' '/f' "$scratchDir\Windows\System32\OneDriveSetup.exe" 2>$null | Out-Null
    & 'icacls' "$scratchDir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>$null | Out-Null
    Remove-Item -Path "$scratchDir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue | Out-Null
} else {
    Write-Output "OneDriveSetup.exe not present, skipping."
}

Write-Output "Removal complete!"
Start-Sleep -Seconds 2
Clear-Host

#---------[ WinSxS Trimming (Core-specific) ]---------#
Write-Output "Taking ownership of the WinSxS folder. This might take a while..."
& 'takeown' '/f' "$scratchDir\Windows\WinSxS" '/r' 2>$null | Out-Null
& 'icacls' "$scratchDir\Windows\WinSxS" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>$null | Out-Null
Write-Output "Complete!"
Start-Sleep -Seconds 2
Clear-Host

Write-Output "Preparing trimmed WinSxS..."
$winSxSEditPath = "$scratchDir\Windows\WinSxS_edit"
$sourceDirectory = "$scratchDir\Windows\WinSxS"

$dirsToCopy = if ($architecture -eq "amd64") {
    @(
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "x86_microsoft-windows-s..ngstack-onecorebase_31bf3856ad364e35_*",
        "x86_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack-inetsrv_*",
        "x86_microsoft-windows-servicingstack-onecore_*",
        "amd64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "amd64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "amd64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "amd64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "amd64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "amd64_microsoft-windows-s..stack-inetsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-msg.resources_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs", "FileMaps", "Fusion", "InstallTemp", "Manifests",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*"
    )
} elseif ($architecture -eq "arm64") {
    @(
        "arm64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs", "FileMaps", "Fusion", "InstallTemp", "Manifests",
        "SettingsManifests", "Temp",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft-windows-servicing-adm_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingcommon_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicing-onecore-uapi_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*"
    )
} else {
    Write-Warning "Unknown architecture: $architecture. Cannot trim WinSxS safely."
    $dirsToCopy = @()
}

if ($dirsToCopy.Count -gt 0) {
    New-Item -Path $winSxSEditPath -ItemType Directory -Force | Out-Null
    foreach ($dir in $dirsToCopy) {
        $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory -ErrorAction SilentlyContinue
        foreach ($sourceDir in $sourceDirs) {
            $destDir = Join-Path -Path $winSxSEditPath -ChildPath $sourceDir.Name
            Write-Output "Preserving: $($sourceDir.Name)"
            Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force
        }
    }
}

Write-Output "Deleting WinSxS. This may take a while..."
Remove-Item -Path "$scratchDir\Windows\WinSxS" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Rename-Item -Path $winSxSEditPath -NewName "WinSxS" -ErrorAction SilentlyContinue

#---------[ Load Registry Hives ]---------#
Write-Output "Loading registry..."
Invoke-RegLoad -HiveName 'zCOMPONENTS' -FilePath "$scratchDir\Windows\System32\config\COMPONENTS"
Invoke-RegLoad -HiveName 'zDEFAULT' -FilePath "$scratchDir\Windows\System32\config\default"
Invoke-RegLoad -HiveName 'zNTUSER' -FilePath "$scratchDir\Users\Default\ntuser.dat"
Invoke-RegLoad -HiveName 'zSOFTWARE' -FilePath "$scratchDir\Windows\System32\config\SOFTWARE"
Invoke-RegLoad -HiveName 'zSYSTEM' -FilePath "$scratchDir\Windows\System32\config\SYSTEM"
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

#---------[ Sponsored Apps ]---------#
Write-Output "Disabling Sponsored Apps:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'

#---------[ OOBE ]---------#
Write-Output "Enabling Local Accounts on OOBE:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
$autoundatePath = Resolve-AutounattendFile -Architecture $architecture
Copy-AutounattendWithIndex -SourcePath $autoundatePath -DestinationPath "$scratchDir\Windows\System32\Sysprep\autounattend.xml" -ImageIndex 1

#---------[ Reserved Storage & BitLocker ]---------#
Write-Output "Disabling Reserved Storage:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
Write-Output "Disabling BitLocker Device Encryption"
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'

#---------[ Chat Icon & Telemetry ]---------#
Write-Output "Disabling Chat icon:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
Write-Output "Disabling Telemetry:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'

#---------[ Copilot, DevHome, Outlook, Teams Prevention ]---------#
Write-Output "Prevents installation of DevHome and Outlook:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'
Write-Output "Disabling Copilot"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsNotepad' 'DisableAIFeatures' 'REG_DWORD' '1'
Write-Output "Preventing Recall data analysis:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'REG_DWORD' '1'
Write-Output "Prevents installation of Teams:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'

#---------[ Scheduled Task Deletion ]---------#
Write-Output "Deleting scheduled task definition files..."
$tasksPath = "$scratchDir\Windows\System32\Tasks"
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
Write-Output "Task files have been deleted."

#---------[ TaskCache ACL Takeover + GUID Deletion ]---------#
Write-Host "Deleting scheduled task cache entries..."
$taskCacheGuids = Get-TaskCacheGuidsForBuild -BuildVersion $Script:buildVersion
$taskCacheAclReady = Enable-TaskCacheWriteAccess -AdminGroup $adminGroup
if (-not $taskCacheAclReady) {
    Write-Warning "TaskCache ACL hardening did not complete. Continuing with best-effort deletion."
}
Remove-TaskCacheEntries -TaskGuids $taskCacheGuids

#---------[ Disable Windows Update (Post-OOBE via RunOnce) ]---------#
Write-Output "Disabling Windows Update..."
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE1' 'REG_SZ' 'net stop wuauserv'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE2' 'REG_SZ' 'sc stop wuauserv'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'StopWUPostOOBE3' 'REG_SZ' 'sc config wuauserv start= disabled'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'DisableWUPostOOBE1' 'REG_SZ' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\wuauserv /v Start /t REG_DWORD /d 4 /f'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'DisableWUPostOOBE2' 'REG_SZ' 'reg add HKLM\SYSTEM\ControlSet001\Services\wuauserv /v Start /t REG_DWORD /d 4 /f'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DoNotConnectToWindowsUpdateInternetLocations' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableWindowsUpdateAccess' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUServer' 'REG_SZ' 'localhost'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUStatusServer' 'REG_SZ' 'localhost'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'UpdateServiceUrlAlternate' 'REG_SZ' 'localhost'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'DisableOnline' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv' 'Start' 'REG_DWORD' '4'
Remove-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSVC'
Remove-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc'

#---------[ Disable Windows Defender ]---------#
Write-Output "Disabling Windows Defender"
foreach ($svc in @('WinDefend', 'WdNisSvc', 'WdNisDrv', 'WdFilter', 'Sense')) {
    try {
        Set-ItemProperty -Path "HKLM:\zSYSTEM\ControlSet001\Services\$svc" -Name "Start" -Value 4 -ErrorAction Stop
    } catch {
        Write-Warning "Could not set service $svc start=4"
        $Script:buildWarnings++
    }
}
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'REG_SZ' 'hide:virus;windowsupdate'

#---------[ Unmount Registry ]---------#
Write-Output "Unmounting Registry..."
foreach ($hive in @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')) {
    Invoke-RegUnload -HiveName $hive
}
$Script:offlineRegistryLoaded = $false

#---------[ Component Cleanup ]---------#
Write-Output "Cleaning up image..."
Invoke-DismChecked -Label 'DISM cleanup' /Image:$scratchDir /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Output "Cleanup complete."

#---------[ Dismount install.wim ]---------#
Write-Output "Unmounting image..."
if (-not (Invoke-SafeDismountImage -Path $scratchDir -Save)) {
    throw "Failed to dismount the install image safely."
}
$Script:installImageMounted = $false

#---------[ Export Image as ESD ]---------#
Write-Output "Exporting ESD. This may take a while..."
Invoke-DismChecked -Label 'DISM export install.wim (Core)' /Export-Image /SourceImageFile:"$ScratchDisk\tiny11\sources\install.wim" /SourceIndex:1 /DestinationImageFile:"$ScratchDisk\tiny11\sources\install.esd" /Compress:recovery
if (-not (Test-Path "$ScratchDisk\tiny11\sources\install.esd")) {
    throw "DISM ESD export failed: install.esd was not created."
}
Remove-Item "$ScratchDisk\tiny11\sources\install.wim" -Force -ErrorAction SilentlyContinue | Out-Null

$imageIndex = 1
Write-Output "Windows Core image completed. Continuing with boot.wim."
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
Mount-WindowsImage -ImagePath "$ScratchDisk\tiny11\sources\boot.wim" -Index $bootWimIndex -Path $scratchDir
$Script:bootImageMounted = $true

Write-Output "Loading registry..."
Invoke-RegLoad -HiveName 'zCOMPONENTS' -FilePath "$scratchDir\Windows\System32\config\COMPONENTS"
Invoke-RegLoad -HiveName 'zDEFAULT' -FilePath "$scratchDir\Windows\System32\config\default"
Invoke-RegLoad -HiveName 'zNTUSER' -FilePath "$scratchDir\Users\Default\ntuser.dat"
Invoke-RegLoad -HiveName 'zSOFTWARE' -FilePath "$scratchDir\Windows\System32\config\SOFTWARE"
Invoke-RegLoad -HiveName 'zSYSTEM' -FilePath "$scratchDir\Windows\System32\config\SYSTEM"

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
if (-not (Invoke-SafeDismountImage -Path $scratchDir -Save)) {
    throw "Failed to dismount the boot image safely."
}
$Script:bootImageMounted = $false

#---------[ Create ISO ]---------#
Clear-Host
Write-Output "========================================"
Write-Output "The tiny11 Core image is now completed. Proceeding with the making of the ISO..."
Write-Output "Copying unattended file for bypassing MS account on OOBE..."

$finalUnattendSource = Resolve-AutounattendFile -Architecture $architecture
Copy-AutounattendWithIndex -SourcePath $finalUnattendSource -DestinationPath "$ScratchDisk\tiny11\autounattend.xml" -ImageIndex 1

Assert-IsoBootFiles -ImageRoot "$ScratchDisk\tiny11"
Write-Output "Creating ISO image..."

$hostArch = $Env:PROCESSOR_ARCHITECTURE
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
Format-BuildSummary -Elapsed $elapsed -IsoBytes $isoBytes -IsoPath $isoPath -AppsRemoved 0 -AppsTotal 0 -Warnings $Script:buildWarnings |
    ForEach-Object { Write-Output $_ }

#---------[ Cleanup ]---------#
Write-Output "Creation completed!"
if (-not $Yes) { Read-Host "Press Enter to continue" }
Write-Output "Performing Cleanup..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "Removing oscdimg.exe..."
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Write-Output "Removing autounattend.xml..."
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

foreach ($checkPath in @("$ScratchDisk\tiny11", "$ScratchDisk\scratchdir")) {
    if (Test-Path $checkPath) {
        Remove-Item -Path $checkPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if (Test-Path "$PSScriptRoot\oscdimg.exe") {
    Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
}

Stop-Transcript -ErrorAction SilentlyContinue
exit 0
