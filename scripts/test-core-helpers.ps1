#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the pure helper functions in lib/tiny11utils.psm1.
    Loads function definitions via AST (no Windows image needed).

    Adapted from the YmlyZA/tiny11builder test-core-helpers.ps1.
#>

$repo = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repo 'lib\tiny11utils.psm1'

# Load function definitions from the utils module.
Import-Module -Name $modulePath -Force -Scope Global -ErrorAction SilentlyContinue

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond) {
    if ($cond) { Write-Host "  PASS: $name"; $script:pass++ }
    else       { Write-Host "  FAIL: $name"; $script:fail++ }
}
function CheckThrows([string]$name, [scriptblock]$sb) {
    $threw = $false
    try { & $sb } catch { $threw = $true }
    Check $name $threw
}

Write-Host '== Resolve-BuildProfile =='
$p = Resolve-BuildProfile
Check 'default compress recovery'      ($p.Compress -eq 'recovery')
Check 'default does not skip cleanup'  ($p.SkipCleanup -eq $false)
Check 'default uses esd'               ($p.UseEsd -eq $true)
Check 'default wim export max'         ($p.WimExportCompress -eq 'max')
$p = Resolve-BuildProfile -Fast
Check '-Fast compress fast'            ($p.Compress -eq 'fast')
Check '-Fast skips cleanup'            ($p.SkipCleanup -eq $true)
Check '-Fast no esd'                   ($p.UseEsd -eq $false)
Check '-Fast wim export fast'          ($p.WimExportCompress -eq 'fast')
$p = Resolve-BuildProfile -Compress 'none'
Check '-Compress none'                 ($p.Compress -eq 'none')
Check '-Compress none no esd'          ($p.UseEsd -eq $false)
Check '-Compress none not skipclean'   ($p.SkipCleanup -eq $false)
Check '-Compress none wim export none' ($p.WimExportCompress -eq 'none')
$p = Resolve-BuildProfile -Compress 'none' -Fast
Check 'explicit compress overrides Fast' ($p.Compress -eq 'none')
Check 'Fast still skips cleanup w/ explicit compress' ($p.SkipCleanup -eq $true)
CheckThrows 'invalid compress throws'  { Resolve-BuildProfile -Compress 'zip' }

Write-Host '== Resolve-BuildPreset =='
$p = Resolve-BuildPreset -PresetName 'Default'
Check 'Default removeEdge true'    ($p.RemoveEdge -eq $true)
Check 'Default removeDefender false' ($p.RemoveDefender -eq $false)
Check 'Default removeStore false'  ($p.RemoveStore -eq $false)
$p = Resolve-BuildPreset -PresetName 'Minimal-VM'
Check 'MinimalVM removeDefender true'  ($p.RemoveDefender -eq $true)
Check 'MinimalVM removeStore true'     ($p.RemoveStore -eq $true)
Check 'Gaming enableUltimatePerf true' ((Resolve-BuildPreset -PresetName 'Gaming').EnableUltimatePerf -eq $true)
Check 'Gaming disableMouseAccel true'  ((Resolve-BuildPreset -PresetName 'Gaming').DisableMouseAcceleration -eq $true)
Check 'Gaming enableUtcClock true'     ((Resolve-BuildPreset -PresetName 'Gaming').EnableUtcClock -eq $true)
Check 'PrivacyPlus blockFirewall true' ((Resolve-BuildPreset -PresetName 'PrivacyPlus').BlockFirewallTelemetry -eq $true)
Check 'PrivacyPlus disableZoneInfo true' ((Resolve-BuildPreset -PresetName 'PrivacyPlus').DisableZoneInformation -eq $true)
Check 'PrivacyPlus enableFastShutdown true' ((Resolve-BuildPreset -PresetName 'PrivacyPlus').EnableFastShutdown -eq $true)
Check 'No preset returns Standard'     ((Resolve-BuildPreset).RemoveEdge -eq $true)
CheckThrows 'unknown preset throws'    { Resolve-BuildPreset -PresetName 'Nope' }

Write-Host '== Test-RobocopySucceeded =='
Check 'rc 0 success'  (Test-RobocopySucceeded 0)
Check 'rc 1 success'  (Test-RobocopySucceeded 1)
Check 'rc 7 success'  (Test-RobocopySucceeded 7)
Check 'rc 8 failure'  (-not (Test-RobocopySucceeded 8))
Check 'rc 16 failure' (-not (Test-RobocopySucceeded 16))

Write-Host '== Get-AvailableImageIndex =='
$single = @(
    'Details for image : X', '',
    'Index : 1',
    'Name : Windows 11 IoT Enterprise LTSC Evaluation',
    'Description : Windows 11 IoT Enterprise LTSC Evaluation',
    'Size : 19,529,686,632 bytes'
)
$a = Get-AvailableImageIndex $single
Check 'single: one image'   ($a.Count -eq 1)
Check 'single: index 1'     ($a[0].Index -eq 1)
Check 'single: name parsed' ($a[0].Name -eq 'Windows 11 IoT Enterprise LTSC Evaluation')
Check 'single: size parsed' ($a[0].SizeBytes -eq 19529686632)
$multi = @(
    'Index : 1', 'Name : Windows 11 Home', 'Size : 15,000,000,000 bytes',
    'Index : 3', 'Name : Windows 11 Pro',  'Size : 16,500,000,000 bytes'
)
$m = Get-AvailableImageIndex $multi
Check 'multi: two images'  ($m.Count -eq 2)
Check 'multi: indices 1,3' (($m.Index -join ',') -eq '1,3')
Check 'multi: pro size'    ((($m | Where-Object Index -eq 3).SizeBytes) -eq 16500000000)
Check 'empty input empty'  (@(Get-AvailableImageIndex @()).Count -eq 0)

Write-Host '== Test-ImageIndexAvailable =='
Check 'index present' (Test-ImageIndexAvailable 3 $m)
Check 'index absent'  (-not (Test-ImageIndexAvailable 2 $m))

Write-Host '== Get-RequiredScratchBytes =='
Check 'floor applies (small image)'  ((Get-RequiredScratchBytes 1GB) -eq 20GB)
Check 'factor applies (large image)' ((Get-RequiredScratchBytes 19529686632) -eq [long](19529686632 * 1.5))

Write-Host '== Test-SufficientScratch =='
Check 'enough space ok'   ((Test-SufficientScratch 20GB 30GB).Ok)
Check 'short space not ok' (-not (Test-SufficientScratch 30GB 20GB).Ok)

Write-Host '== Resolve-OscdimgSource =='
Check 'adk preferred'  ((Resolve-OscdimgSource $true  $true)  -eq 'adk')
Check 'bundled second' ((Resolve-OscdimgSource $false $true)  -eq 'bundled')
Check 'download last'  ((Resolve-OscdimgSource $false $false) -eq 'download')

Write-Host '== Format-BuildSummary =='
$bs = Format-BuildSummary -Elapsed (New-TimeSpan -Minutes 27 -Seconds 41) -IsoBytes 4070127616 -IsoPath 'C:\x\tiny11.iso' -AppsRemoved 31 -AppsTotal 33 -Warnings 2
Check 'summary result line'   ($bs -contains '  Result        : SUCCESS')
Check 'summary elapsed line'  ($bs -contains '  Elapsed       : 27m 41s')
Check 'summary iso/size line' ($bs -contains '  Output ISO    : C:\x\tiny11.iso  (3.79 GB)')
Check 'summary apps line'     ($bs -contains '  Apps removed  : 31 of 33 provisioned Appx')
Check 'summary warn line'     ($bs -contains '  Warnings      : 2 non-fatal (see log)')
Check 'summary header'        ($bs -contains '===== BUILD SUMMARY =====')
$bs0 = Format-BuildSummary -Elapsed (New-TimeSpan -Minutes 5 -Seconds 3) -IsoBytes 2147483648 -IsoPath 'C:\a.iso' -AppsRemoved 0 -AppsTotal 0 -Warnings 0
Check 'summary warn none'     ($bs0 -contains '  Warnings      : none')
Check 'summary size 2.00 GB'  ($bs0 -contains '  Output ISO    : C:\a.iso  (2.00 GB)')
Check 'summary elapsed 5m 3s' ($bs0 -contains '  Elapsed       : 5m 3s')

Write-Host '== Test-IsoResult =='
Check 'iso ok'           (Test-IsoResult -ExitCode 0 -IsoExists $true  -IsoBytes 100)
Check 'iso bad exit'     (-not (Test-IsoResult -ExitCode 1 -IsoExists $true  -IsoBytes 100))
Check 'iso missing file' (-not (Test-IsoResult -ExitCode 0 -IsoExists $false -IsoBytes 0))
Check 'iso empty file'   (-not (Test-IsoResult -ExitCode 0 -IsoExists $true  -IsoBytes 0))

Write-Host '== New-UnattendXml =='
$uaA = New-UnattendXml -Architecture 'arm64' -UserName 'User' -Password '' -TimeZone 'UTC' -Language 'en-US'
$okA = $true; try { $null = [xml]$uaA } catch { $okA = $false }
Check 'arm64 well-formed xml' $okA
Check 'arm64 arch arm64'      ($uaA -match 'processorArchitecture="arm64"')
Check 'arm64 index 1'         ($uaA -match '<Value>1</Value>')
Check 'arm64 autologon'       ($uaA -match '<AutoLogon>')
Check 'arm64 user name'       ($uaA -match '<Name>User</Name>')
Check 'arm64 timezone'        ($uaA -match '<TimeZone>UTC</TimeZone>')
Check 'arm64 no disk wipe'    (-not ($uaA -match 'WillWipeDisk'))
Check 'no product key element' (-not ($uaA -match '<ProductKey>'))
Check 'accepts eula'           ($uaA -match '<AcceptEula>true</AcceptEula>')
$uaB = New-UnattendXml -Architecture 'amd64' -UserName 'Tester' -Password 'p@ss' -TimeZone 'UTC' -Language 'en-US' -ZeroTouch
$okB = $true; try { $null = [xml]$uaB } catch { $okB = $false }
Check 'amd64-ZT well-formed xml' $okB
Check 'amd64-ZT arch amd64'      ($uaB -match 'processorArchitecture="amd64"')
Check 'amd64-ZT disk wipe'       ($uaB -match '<WillWipeDisk>true</WillWipeDisk>')
Check 'amd64-ZT installto part3' ($uaB -match '<PartitionID>3</PartitionID>')
Check 'amd64-ZT user name'       ($uaB -match '<Name>Tester</Name>')
$uaE = New-UnattendXml -Architecture 'amd64' -UserName 'a&b' -Password '' -TimeZone 'UTC' -Language 'en-US'
$okE = $true; try { $null = [xml]$uaE } catch { $okE = $false }
Check 'escaped user parses'   $okE
Check 'escaped user amp'      ($uaE -match '<Name>a&amp;b</Name>')
$uaCase = New-UnattendXml -Architecture 'ARM64' -UserName 'User' -Password '' -TimeZone 'UTC' -Language 'en-US'
Check 'arch normalized lowercase' ($uaCase -match 'processorArchitecture="arm64"')
Check 'arch not uppercase'        (-not ($uaCase -cmatch 'processorArchitecture="ARM64"'))

Write-Host '== Test-PrefixSelected =='
Check 'prefix in list' (Test-PrefixSelected @('Edge', 'OneDrive') 'Edge')
Check 'prefix not in list' (-not (Test-PrefixSelected @('Edge') 'OneDrive'))
Check 'empty list' (-not (Test-PrefixSelected @() 'Edge'))

Write-Host '== Get-OptionalUtilities =='
$opt = Get-OptionalUtilities
Check 'returns non-empty table' ($opt.Count -gt 0)
Check 'Terminal default Keep'   (($opt | Where-Object Name -eq 'Terminal'    | Select-Object -ExpandProperty Default) -eq 'Keep')
Check 'Calculator default Keep' (($opt | Where-Object Name -eq 'Calculator'  | Select-Object -ExpandProperty Default) -eq 'Keep')
Check 'Paint default Remove'    (($opt | Where-Object Name -eq 'Paint' | Select-Object -ExpandProperty Default) -eq 'Remove')
Check 'MediaPlayer default Remove' (($opt | Where-Object Name -eq 'MediaPlayer' | Select-Object -ExpandProperty Default) -eq 'Remove')
Check 'valid utility names'     ($opt.Name -contains 'Terminal' -and $opt.Name -contains 'Camera' -and $opt.Name -contains 'Calculator')

Write-Host '== Resolve-OptionalUtilities =='
$def = Resolve-OptionalUtilities
Check 'default removes Paint'    ($def.RemovePrefixes -contains 'Microsoft.Paint')
Check 'default keeps Terminal'   ($def.KeptNames -contains 'Terminal')
$keep = Resolve-OptionalUtilities -Keep 'Paint'
Check 'keep Paint -> kept'        ($keep.KeptNames -contains 'Paint')
Check 'keep Paint -> not removed' (-not ($keep.RemovePrefixes -contains 'Microsoft.Paint'))
$rem = Resolve-OptionalUtilities -Remove 'Calculator'
Check 'remove Calculator -> removed' ($rem.RemovePrefixes -contains 'Microsoft.WindowsCalculator')
CheckThrows 'unknown name throws'  { Resolve-OptionalUtilities -Keep 'FakeApp' }
CheckThrows 'conflict throws'      { Resolve-OptionalUtilities -Keep 'Paint' -Remove 'Paint' }

Write-Host '== Get-AlwaysRemovePackages =='
$arb = Get-AlwaysRemovePackages
Check 'returns non-empty list' ($arb.Count -gt 0)
Check 'contains Clipchamp'     ($arb -contains 'Clipchamp.Clipchamp_')
Check 'contains XboxGamingOverlay' ($arb -contains 'Microsoft.XboxGamingOverlay_')
Check 'contains BingNews'      ($arb -contains 'Microsoft.BingNews_')

Write-Host '== Assert-WinSxSRebuild =='
CheckThrows 'missing path throws'      { Assert-WinSxSRebuild -Path 'C:\nonexistent-path-12345' }

Write-Host '== Assert-CommandExitCode =='
CheckThrows 'nonzero throws' { Assert-CommandExitCode -Label 'Test operation' -ExitCode 1 }
Check 'zero ok' ((Assert-CommandExitCode -Label 'OK' -ExitCode 0) -eq $null)

Write-Host '== Test-ScratchDiskSpace =='
$r = Test-ScratchDiskSpace -ScratchPath 'C:\' 1MB
Check 'C: has space' ($r.Ok)
Check 'C: reports GB free' ($r.FreeGB -gt 0)

Write-Host '== Test-ScratchDiskNtfs =='
Check 'C: is NTFS' (Test-ScratchDiskNtfs -ScratchPath 'C:\')

Write-Host '== Get-MaxParallelJobs =='
$mpj = Get-MaxParallelJobs
Check 'returns int' ($mpj -is [int])
Check 'at least 1' ($mpj -ge 1)

Write-Host '== Get-OptionalCapabilitiesToRemove =='
$caps = Get-OptionalCapabilitiesToRemove -LanguageCode 'en-US' -Preset (Resolve-BuildPreset -PresetName 'Default')
Check 'returns array' ($caps -is [array])
Check 'contains IE' ($caps -contains 'Browser.InternetExplorer~~~~0.0.0.0')

Write-Host '== Get-AdditionalWindowsPackagesToRemove =='
$pkgs = Get-AdditionalWindowsPackagesToRemove -LanguageCode 'en-US' -Preset (Resolve-BuildPreset -PresetName 'Default')
Check 'returns array' ($pkgs -is [array])

Write-Host '== Remove-BloatwareFiles =='
Check 'function exists' ($null -ne (Get-Command Remove-BloatwareFiles -ErrorAction SilentlyContinue))

Write-Host '== Apply-ExtendedTweaks =='
Check 'function exists' ($null -ne (Get-Command Apply-ExtendedTweaks -ErrorAction SilentlyContinue))

Write-Host ''
Write-Host "RESULT: $script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
exit 0
