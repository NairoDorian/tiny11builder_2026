<#
.SYNOPSIS
    GUI launcher for the Tiny11 Builder - Ultimate Edition.

.DESCRIPTION
    Provides an interactive Windows Forms wizard that lets you:
      1. Mount a Windows 11 ISO file OR select an already-mounted drive
      2. Select the image edition (Home, Pro, etc.)
      3. Launch the builder with your chosen options

    After the wizard completes, it invokes tiny11maker.ps1 (or
    tiny11Coremaker.ps1 for Core mode) with the appropriate parameters.

    This is the GUI equivalent of the reforged fork's approach, enhanced
    with real-time log monitoring and app customization options.

.PARAMETER BuildCore
    Launch the Core (ultra-trimmed) builder instead of the regular maker.

.PARAMETER Scratch
    Override the scratch disk drive letter.

.EXAMPLE
    .\tiny11gui.ps1
    .\tiny11gui.ps1 -BuildCore -Scratch D
#>

param (
    [switch]$BuildCore,
    [string]$Scratch
)

$ErrorActionPreference = 'Stop'

# Requires Windows Forms + Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#---------[ Load Resources ]---------#
$icoPath  = Join-Path $PSScriptRoot 'resources', 'T11M_icon.ico'
$splashPath = Join-Path $PSScriptRoot 'resources', 'T11M_splash.png'

#---------[ Import Modules ]---------#
Import-Module -Name (Join-Path $PSScriptRoot 'lib\tiny11utils.psm1') -Force
Import-Module -Name (Join-Path $PSScriptRoot 'lib\tiny11gui.psm1') -Force

#---------[ Execution Policy & Admin Check ]---------#
if ((Get-ExecutionPolicy) -ne 'Bypass') {
    $msg = "Your current PowerShell Execution Policy is set to $(Get-ExecutionPolicy), which prevents scripts from running.`nDo you want to change it to Bypass?"
    $agree = Invoke-PopupYesOrNo -title "Change execution policy?" -message $msg
    if ($agree) {
        Set-ExecutionPolicy Bypass -Scope Process -Confirm:$false
    } else {
        Write-Host "Cannot run without changing the execution policy. Exiting..."
        $null = Read-Host "Press Enter to exit..."
        exit 1
    }
}

$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
if (-not $myWindowsPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting Tiny11 GUI as admin in a new window, you can close this one."
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $newProcess.Arguments = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$($MyInvocation.MyCommand.Definition)`""
    if ($BuildCore) { $newProcess.Arguments += " -BuildCore" }
    if ($Scratch)   { $newProcess.Arguments += " -Scratch `"$Scratch`"" }
    $newProcess.Verb = "runas"
    [System.Diagnostics.Process]::Start($newProcess) | Out-Null
    exit
}

#---------[ Gather System Drives ]---------#
$driveLetters = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'CD-ROM' } |
    ForEach-Object { "$($_.DriveLetter):" }
$allDrives = Get-Volume | Where-Object { $_.DriveLetter } |
    ForEach-Object { "$($_.DriveLetter):" }
Set-DrivesList -list $allDrives

#---------[ Show Splash + Wizard ]---------#
$FormWindow = Invoke-MainForm -title "Tiny11 Builder" -version $AppVersion -icoPath $icoPath -splashPath $splashPath

# Stage 0: Mount mode
$SCREEN_STAGE = 0
$MountPanel = Invoke-MountMode
$FormWindow.Controls.Add($MountPanel)
$FormWindow.Show() | Out-Null

Write-Output "Waiting for source selection..."
Update-EventLoop -stage 0

if ($WINDOW_CLOSED) {
    Write-Output "GUI cancelled by user."
    $FormWindow.Close() | Out-Null
    exit 0
}

#---------[ Resolve Source Drive ]---------#
$sourceDrive = $null
if ($MODE_SELECT -eq 1) {
    $isoPath = Get-IsoPath
    Write-Output "Mounting ISO: $isoPath"
    $diskImage = Mount-DiskImage -ImagePath $isoPath -StorageType Raw -ReadOnly
    Start-Sleep -Seconds 2
    $vol = Get-DiskImage -ImagePath $isoPath | Get-Volume
    $sourceDrive = "$($vol.DriveLetter):"
} else {
    $sourceDrive = Get-SelectedDrive
}

Write-Output "Source drive: $sourceDrive"

#---------[ Query Image Indexes ]---------#
$wimPath = "$sourceDrive\sources\install.wim"
$esdPath = "$sourceDrive\sources\install.esd"
if (-not (Test-Path $wimPath)) {
    if (Test-Path $esdPath) {
        $wimInfoText = & 'dism' '/English' '/Get-WimInfo' "/wimfile:$esdPath" 2>&1
    } else {
        Invoke-PopupError -title "Image not found" -message "Neither install.wim nor install.esd found at $sourceDrive\sources."
        $FormWindow.Close() | Out-Null
        exit 1
    }
} else {
    $wimInfoText = & 'dism' '/English' '/Get-WimInfo' "/wimfile:$wimPath" 2>&1
}

$indexes = Get-AvailableImageIndex $wimInfoText
$editionNames = $indexes | ForEach-Object { "$($_.Index): $($_.Name)" }
if (-not $editionNames -or $editionNames.Count -eq 0) {
    $editionNames = @("No image index found")
}
Set-EditionsList -list $editionNames

#---------[ Stage 1: Image Index Selection ]---------#
# Clear previous panel and show index mode
$FormWindow.Controls.Clear()
$FormWindow.Controls.Add($SplashPictureBox)
$IndexPanel = Invoke-ImageIndexMode
$FormWindow.Controls.Add($IndexPanel)

Write-Output "Waiting for edition selection..."
Update-EventLoop -stage 1

if ($WINDOW_CLOSED) {
    Write-Output "GUI cancelled by user."
    if ($diskImage) { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null }
    $FormWindow.Close() | Out-Null
    exit 0
}

$selectedIndex = Get-SelectedImageIndex
Write-Output "Selected image index: $selectedIndex"

#---------[ Launch Builder ]---------#
$builderScript = if ($BuildCore) { 'tiny11Coremaker.ps1' } else { 'tiny11maker.ps1' }
$scriptArgs = @("-ISO", $sourceDrive, "-Index", $selectedIndex, "-Yes")
if ($Scratch) { $scriptArgs += @("-SCRATCH", $Scratch) }

Write-Output "Launching $builderScript with args: $($scriptArgs -join ' ')"
$FormWindow.Close() | Out-Null

# Run the builder in the foreground
& "$PSScriptRoot\$builderScript" @scriptArgs

#---------[ Eject ISO if mounted ]---------#
if ($diskImage) {
    Start-Sleep -Seconds 2
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
    Write-Output "ISO unmounted."
}

#---------[ Open Explorer to the ISO ]---------#
$isoOutput = "$PSScriptRoot\tiny11.iso"
if (Test-Path $isoOutput) {
    $result = Invoke-PopupYesOrNo -title "Success" -message "Tiny11 ISO created successfully!`nOpen the output folder?"
    if ($result) {
        Start-Process -FilePath "explorer.exe" -ArgumentList "/select,`"$isoOutput`""
    }
} else {
    Invoke-PopupError -title "Build failed" -message "Build completed but tiny11.iso was not found."
}
