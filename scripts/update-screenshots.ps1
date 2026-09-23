#requires -Version 5.1
<#
.SYNOPSIS
    Regenerates the GUI screenshots in docs\ (gui-*.png).

.DESCRIPTION
    Every image is rendered from the window itself with DrawToBitmap - never a
    screen grab - so nothing else on the desktop can appear in them. The
    sample settings below are fictional (user "Alice", edition 6).
    gui-build-done.png shows a finished build: it is produced by running the
    window with scripts\fixtures\fake-builder.ps1, which only prints a
    realistic log and never touches the system.

    Run it in Windows PowerShell 5.1 (STA, the default for powershell.exe).
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $repo 'lib\tiny11gui.psm1') -Force -DisableNameChecking
$docs = Join-Path $repo 'docs'
$icon = Join-Path $repo 'resources\T11M_icon.ico'

function New-DocState {
    param([string]$Source, [string]$OutputIso)
    $s = Get-GuiDefaultState
    $s.Source = $Source; $s.Index = 6; $s.EditionName = 'Windows 11 Pro'; $s.EditionSizeBytes = 19GB
    $s.OutputIso = $OutputIso
    $s.Preset = 'Gaming'
    $gaming = Resolve-BuildPreset Gaming
    foreach ($k in $gaming.Keys) { $s.Flags[$k] = $gaming[$k] }
    $s.Browser = 'Firefox'; $s.User = 'Alice'; $s.Locale = 'en-GB'; $s.TimeZone = 'GMT Standard Time'; $s.ComputerName = 'GAMING-PC'
    $s.Keep = @('Terminal', 'Calculator', 'Notepad', 'Photos', 'Paint', 'SnippingTool')
    $s.Remove = @('Camera', 'SoundRecorder', 'StickyNotes', 'Clock', 'MediaPlayer', 'MoviesTV')
    return $s
}

$tabs = 'source', 'preset', 'apps', 'tweaks', 'setup', 'extras', 'build'
for ($i = 0; $i -lt $tabs.Count; $i++) {
    $path = Join-Path $docs "gui-$($tabs[$i]).png"
    Show-Tiny11BuilderForm -IconPath $icon -SettingsPath '' -PreviewTab $i -PreviewPath $path `
        -InitialState (New-DocState -Source 'D:\ISO\Win11_25H2_English_x64.iso' -OutputIso 'C:\tiny11\tiny11.iso') | Out-Null
    Write-Host "rendered $path"
}

# Finished build: the output must be in an existing folder for validation,
# so the fake ISO goes to the git-ignored logs\gui folder and is deleted after.
$work = Join-Path $repo 'logs\gui'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$fakeIso = Join-Path $work 'tiny11-screenshot.iso'
$env:T11_FAKE_DOCS = '1'; $env:T11_FAKE_OUT = $fakeIso; $env:T11_FAKE_EXIT = '0'
try {
    $code = Show-Tiny11BuilderForm -IconPath $icon -SettingsPath '' -InitialState (New-DocState -Source 'E' -OutputIso $fakeIso) `
        -AutoRun Build -BuilderOverride (Join-Path $repo 'scripts\fixtures\fake-builder.ps1') -Quiet `
        -PreviewPath (Join-Path $docs 'gui-build-done.png')
    if ($code -ne 0) { throw "The fake build did not finish (exit $code)." }
    Write-Host "rendered $(Join-Path $docs 'gui-build-done.png')"
} finally {
    foreach ($n in 'T11_FAKE_DOCS', 'T11_FAKE_OUT', 'T11_FAKE_EXIT') { [Environment]::SetEnvironmentVariable($n, $null) }
    if (Test-Path -LiteralPath $fakeIso) { Remove-Item -LiteralPath $fakeIso -Force }
}
