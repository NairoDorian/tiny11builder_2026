#requires -Version 5.1
# File-only metadata and timing regression tests. No servicing or host mounts.
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $repo 'lib\tiny11gui.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $repo 'lib\tiny11media.psm1') -Force -DisableNameChecking
$script:passed=0
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
function AssertThrows([scriptblock]$Action,[string]$Message) { $threw=$false; try { & $Action | Out-Null } catch { $threw=$true }; Assert $threw $Message }
function New-TestWim([string]$Xml) {
    $xmlBytes=[Text.Encoding]::Unicode.GetBytes($Xml)
    $buffer=New-Object byte[] (208+$xmlBytes.Length)
    [Text.Encoding]::ASCII.GetBytes("MSWIM`0`0`0").CopyTo($buffer,0)
    [BitConverter]::GetBytes([uint64]$xmlBytes.Length).CopyTo($buffer,72)
    [BitConverter]::GetBytes([uint64]208).CopyTo($buffer,80)
    $xmlBytes.CopyTo($buffer,208)
    return ,$buffer
}
$xml='<WIM><IMAGE INDEX="3"><NAME>Windows 11 Pro</NAME><TOTALBYTES>123456789</TOTALBYTES><WINDOWS><ARCH>12</ARCH><EDITIONID>Professional</EDITIONID><LANGUAGES><LANGUAGE>fr-FR</LANGUAGE><DEFAULT>fr-FR</DEFAULT></LANGUAGES><VERSION><MAJOR>10</MAJOR><MINOR>0</MINOR><BUILD>26300</BUILD><SPBUILD>9457</SPBUILD></VERSION></WINDOWS></IMAGE></WIM>'
$bytes=New-TestWim $xml
$stream=New-Object IO.MemoryStream(,$bytes)
try {
    $images=@(Read-WimMetadata $stream)
    Assert ($images.Count -eq 1 -and $images[0].Index -eq 3) 'Actual indexes must come from XML.'
    Assert ($images[0].Architecture -eq 'arm64' -and $images[0].Language -eq 'fr-FR') 'Read arch/language.'
    Assert ($images[0].Version -eq '10.0.26300.9457' -and $images[0].SizeBytes -eq 123456789) 'Read build and size.'
    Assert $stream.CanRead 'Reader must leave the caller stream open.'
} finally { $stream.Dispose() }
foreach ($badXml in '<WIM/>', ('<!DOCTYPE WIM [<!ENTITY x SYSTEM "file:///C:/Windows/win.ini">]><WIM>&x;</WIM>')) {
    $badStream=New-Object IO.MemoryStream(,(New-TestWim $badXml))
    try { AssertThrows { Read-WimMetadata $badStream } 'Reject missing image/external XML entities.' } finally { $badStream.Dispose() }
}
foreach ($kind in 'signature','offset','length','compressed','truncated') {
    $bad=$bytes.Clone()
    switch($kind) {
        'signature' { $bad[0]=0 }
        'offset' { [BitConverter]::GetBytes([uint64]::MaxValue).CopyTo($bad,80) }
        'length' { [BitConverter]::GetBytes([uint64]17MB).CopyTo($bad,72) }
        'compressed' { $bad[79]=4 }
        'truncated' { $bad=New-Object byte[] 10 }
    }
    $badStream=New-Object IO.MemoryStream(,$bad)
    try { AssertThrows { Read-WimMetadata $badStream } "Reject $kind metadata." } finally { $badStream.Dispose() }
}
Assert ((Get-WindowsReleaseHint 'Windows11_24H2_x64.iso') -match '24H2.*hint') 'Release filename hint.'
Assert ((Get-WindowsReleaseHint 'Windows11_Client_x64_26300_9457.iso') -match '26H2.*hint') 'Built-in build list.'
Assert ((Get-WindowsReleaseHint 'custom.iso') -notmatch 'Windows 11') 'Unknown filename must not guess a release.'

# Real ISO9660 fixture: misleading filename, exact metadata, no cache or mounting.
$work=Join-Path $repo ('logs\media-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
    foreach($component in 'Streams','Core','Iso9660','Udf') { [void][Reflection.Assembly]::LoadFrom((Join-Path $repo "lib\vendor\DiscUtils\DiscUtils.$component.dll")) }
    $isoPath=Join-Path $work 'Windows11_24H2.iso'
    $builder=[DiscUtils.Iso9660.CDBuilder]::new()
    $builder.UseJoliet=$true
    [void]$builder.AddFile('sources\install.wim',$bytes)
    $builder.Build($isoPath)
    $actual=@(Get-SourceEditions $isoPath)
    Assert ($actual.Count -eq 1 -and $actual[0].Build -eq 26300 -and $actual[0].Index -eq 3) 'Read ISO9660 directly; do not trust name or standard index.'
    $exclusive=[IO.File]::Open($isoPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $exclusive.Dispose()
    Assert $true 'ISO handles released after reading.'
    # The GUI worker follows this same independent runspace path.
    $ps=[PowerShell]::Create()
    try {
        [void]$ps.AddScript({param($root,$path) Import-Module (Join-Path $root 'lib\tiny11utils.psm1') -DisableNameChecking; Import-Module (Join-Path $root 'lib\tiny11gui.psm1') -DisableNameChecking; Get-SourceEditions $path }).AddArgument($repo).AddArgument($isoPath)
        $handle=$ps.BeginInvoke()
        $result=@($ps.EndInvoke($handle))
        Assert (-not $ps.HadErrors -and $result.Count -eq 1 -and $result[0].Index -eq 3) 'Independent GUI metadata runspace works.'
    } finally { $ps.Dispose() }
} finally { Get-ChildItem -LiteralPath $work -File | Remove-Item -Force; Remove-Item -LiteralPath $work }

$now=[datetime]'2026-10-04T12:00:00'
$timing=Get-GuiTiming -BuildStart $now.AddSeconds(-2) -OverallPercent 20 -Now $now
Assert ($null -eq $timing.TotalEtaSeconds -and $timing.Text -match 'estimating') 'Warm-up must not invent ETA.'
$step=@{ Start=$now.AddSeconds(-10); StartPercent=25; Percent=50; Advanced=$now; Id='compress' }
$timing=Get-GuiTiming -BuildStart $now.AddSeconds(-120) -OverallPercent 50 -StageTiming $step -Now $now
Assert ($timing.StepEtaSeconds -eq 20 -and $timing.TotalEtaSeconds -eq 120) 'ETA uses observed progress delta.'
$step.Advanced=$now.AddSeconds(-100)
$timing=Get-GuiTiming -BuildStart $now.AddSeconds(-120) -OverallPercent 50 -StageTiming $step -Now $now
Assert ($null -eq $timing.StepEtaSeconds) 'Stop displaying stale step ETA.'
$timing=Get-GuiTiming -BuildStart $now.AddSeconds(-120) -OverallPercent 100 -Now $now
Assert ($timing.TotalEtaSeconds -eq 0) 'Completion ETA is zero.'
$stage=Get-GuiStepProgress -Line '__TINY11_PROGRESS__ {"Stage":"apps","Percent":50,"Label":"Removing apps"}'
Assert ($stage.StepPercent -eq 50 -and $stage.OverallPercent -lt 100) 'Structured step percentages.'
Assert ($null -eq (Get-GuiStepProgress 'CPU limit 25%' $stage)) 'Incidental numbers are not native progress.'
Write-Host "RESULT: $script:passed media/progress checks passed."
