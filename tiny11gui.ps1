<#
.SYNOPSIS
    Graphical front-end for Tiny11 Builder - Ultimate Edition.

.DESCRIPTION
    Opens the builder window: every option of tiny11maker.ps1 and
    tiny11Coremaker.ps1 in seven tabs (Source, Preset & features, Apps,
    Tweaks, Setup & account, Extras, Build). The build runs from the Build tab
    with a live log, stage progress and a Cancel button that cleans up.

    Your last settings are remembered in gui-settings.json next to this script
    (never the password). Profiles can be saved and loaded from the window.

.EXAMPLE
    .\tiny11gui.ps1
    (or double-click LAUNCH_TINY11.bat and choose [1])
#>

$ErrorActionPreference = 'Stop'

#---------[ Elevation ]---------#
$principal = New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting the Tiny11 GUI as administrator..."
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    exit 0
}

#---------[ Modules ]---------#
Import-Module -Name (Join-Path $PSScriptRoot 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'lib\tiny11gui.psm1') -Force -DisableNameChecking

#---------[ Window ]---------#
Write-Host "Tiny11 Builder GUI is open. This console shows nothing more; the build log is in the window."
$exitCode = Show-Tiny11BuilderForm -IconPath (Join-Path $PSScriptRoot 'resources\T11M_icon.ico') -DefaultOutputFolder $PSScriptRoot
if ($null -eq $exitCode) { $exitCode = 0 }
exit $exitCode
