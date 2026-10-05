#requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for lib\tiny11utils.psm1, the tweak catalog, the presets, the
    package list and the answer-file generator. No admin rights, no Windows
    image and no Pester needed - runs in a few seconds, locally and in CI.

.DESCRIPTION
    Sections:
      * pure helpers (profiles, presets, formatting, argument quoting)
      * data files (data\tweaks.psd1, presets\*.json, removePackage.txt)
      * answer files (generated + the static reference files), checked
        against an allow-list of real Microsoft-Windows-* unattend settings
      * removal planning (apps, capabilities, packages, editions)
      * static lint of the builder scripts

    Exit code 1 when any check fails.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Mocks injected into the module scope share recorded calls through one global.')]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond) {
    if ($cond) { $script:pass++ }
    else { Write-Host "  FAIL: $name" -ForegroundColor Red; $script:fail++ }
}
function CheckThrows([string]$name, [scriptblock]$sb) {
    $threw = $false
    try { & $sb | Out-Null } catch { $threw = $true }
    Check $name $threw
}
function Section([string]$name) { Write-Host "== $name ==" }

#======================================================================
Section 'Resolve-BuildProfile'
$p = Resolve-BuildProfile
Check 'default maximum'            ($p.Compress -eq 'maximum')
Check 'default esd'                ($p.UseEsd -and $p.ImageFileName -eq 'install.esd')
Check 'default export recovery'    ($p.ExportCompress -eq 'recovery')
Check 'default cleanup'            (-not $p.SkipCleanup)
$p = Resolve-BuildProfile -Fast
Check '-Fast fast + wim'           ($p.Compress -eq 'fast' -and $p.ImageFileName -eq 'install.wim' -and $p.SkipCleanup)
$p = Resolve-BuildProfile -Compress max
Check 'max -> wim max'             ($p.ExportCompress -eq 'max' -and -not $p.UseEsd)
$p = Resolve-BuildProfile -Compress none -Fast
Check 'explicit wins over -Fast'   ($p.Compress -eq 'none' -and $p.SkipCleanup)
Check 'legacy recovery remains maximum' ((Resolve-BuildProfile -Compress recovery).Compress -eq 'maximum')
CheckThrows 'invalid compress'     { Resolve-BuildProfile -Compress zip }

#======================================================================
Section 'Presets'
$flagNames = Get-PresetFlagNames
foreach ($name in 'Default', 'Gaming', 'Minimal-VM', 'PrivacyPlus') {
    $preset = Resolve-BuildPreset -PresetName $name
    $missing = @($flagNames | Where-Object { -not $preset.ContainsKey($_) })
    Check "$name defines every flag ($($missing -join ','))" ($missing.Count -eq 0)
    $unknown = @($preset.Keys | Where-Object { $flagNames -notcontains $_ })
    Check "$name has no unknown flag ($($unknown -join ','))" ($unknown.Count -eq 0)
    Check "$name values are bool" (@($preset.Values | Where-Object { $_ -isnot [bool] }).Count -eq 0)
    Check "$name keeps UTC clock off" (-not $preset.EnableUtcClock)
}
$d = Resolve-BuildPreset
Check 'no preset = Default'                ($d.RemoveEdge -and -not $d.RemoveStore -and -not $d.RemoveDefender)
Check 'Default keeps WebView2'             (-not $d.RemoveWebView)
Check 'Default keeps Mark-of-the-Web'      (-not $d.DisableZoneInformation)
Check 'Gaming keeps Xbox'                  ((Resolve-BuildPreset Gaming).KeepXbox)
Check 'Gaming ultimate performance'        ((Resolve-BuildPreset Gaming).EnableUltimatePerformance)
Check 'Minimal-VM removes Defender/Store'  ((Resolve-BuildPreset Minimal-VM).RemoveDefender -and (Resolve-BuildPreset Minimal-VM).RemoveStore)
Check 'PrivacyPlus keeps Defender on'      (-not (Resolve-BuildPreset PrivacyPlus).RemoveDefender)
Check 'PrivacyPlus no Defender cloud'      ((Resolve-BuildPreset PrivacyPlus).DisableDefenderCloud)
Check 'alias minimalvm'                    ((Resolve-BuildPreset minimalvm).RemoveDefender)
Check 'alias privacy+'                     ((Resolve-BuildPreset 'Privacy+').DisableDefenderCloud)
CheckThrows 'unknown preset throws'        { Resolve-BuildPreset -PresetName Nope }
CheckThrows 'missing json preset throws'   { Resolve-BuildPreset -PresetName 'C:\nope\none.json' }
$tmpPreset = Join-Path ([IO.Path]::GetTempPath()) "tiny11-test-$PID.json"
'{ "debloat": { "removeEdge": false }, "performance": { "enableUtcClock": true } }' | Set-Content -Path $tmpPreset -Encoding UTF8
$c = Resolve-BuildPreset -PresetName $tmpPreset
Check 'custom json overrides'              ((-not $c.RemoveEdge) -and $c.EnableUtcClock)
Check 'custom json inherits Default'       ($c.RemoveOneDrive -and $c.DisableTelemetry)
Remove-Item $tmpPreset -Force

# presets\*.json must spell every flag and match the built-in fallback table.
foreach ($file in Get-ChildItem (Join-Path $repo 'presets') -Filter *.json) {
    $json = Get-Content -Raw $file.FullName | ConvertFrom-Json
    $keys = @()
    foreach ($section in 'debloat', 'privacy', 'performance') {
        $keys += @($json.$section.PSObject.Properties.Name | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })
    }
    $missing = @($flagNames | Where-Object { $keys -notcontains $_ })
    $unknown = @($keys | Where-Object { $flagNames -notcontains $_ })
    Check "$($file.Name): all flags present ($($missing -join ','))" ($missing.Count -eq 0)
    Check "$($file.Name): no unknown keys ($($unknown -join ','))"   ($unknown.Count -eq 0)
}

#======================================================================
Section 'Optional utilities'
$opt = Get-OptionalUtilities
Check 'table not empty'                    ($opt.Count -ge 10)
Check 'names unique'                       (@($opt.Name | Select-Object -Unique).Count -eq $opt.Count)
$def = Resolve-OptionalUtilities
Check 'default removes Paint'              ($def.RemovePrefixes -contains 'Microsoft.Paint')
Check 'default keeps Terminal+Notepad'     ($def.KeptNames -contains 'Terminal' -and $def.KeptNames -contains 'Notepad')
Check '-Keep Paint'                        ((Resolve-OptionalUtilities -Keep Paint).KeptNames -contains 'Paint')
Check '-Remove Calculator'                 ((Resolve-OptionalUtilities -Remove Calculator).RemovePrefixes -contains 'Microsoft.WindowsCalculator')
CheckThrows 'unknown utility throws'       { Resolve-OptionalUtilities -Keep FakeApp }
CheckThrows 'keep+remove conflict throws'  { Resolve-OptionalUtilities -Keep Paint -Remove Paint }

#======================================================================
Section 'removePackage.txt'
$listPath = Join-Path $repo 'removePackage.txt'
$list = Read-PackageListFile $listPath
Check 'list not empty'                     ($list.Count -ge 30)
Check 'no duplicates'                      (@($list | Select-Object -Unique).Count -eq $list.Count)
$utilPrefixes = @($opt | ForEach-Object { $_.Prefixes })
$clash = @($list | Where-Object { $utilPrefixes -contains $_ })
Check "no optional utility in list ($($clash -join ','))" ($clash.Count -eq 0)
$protectedHits = @($list | Where-Object { Test-AppxPrefixMatch -PackageName $_ -Prefixes (Get-ProtectedAppxPrefixes) })
Check "no protected package in list ($($protectedHits -join ','))" ($protectedHits.Count -eq 0)
Check 'CrossDevice spelled correctly'      ($list -contains 'MicrosoftWindows.CrossDevice' -and $list -notcontains 'Microsoft.Windows.CrossDevice')
Check 'Widgets listed'                     ($list -contains 'MicrosoftWindows.Client.WebExperience')
$tmpList = Join-Path ([IO.Path]::GetTempPath()) "tiny11-list-$PID.txt"
"# c`r`nA.B  # trailing`r`n`r`nA.B`r`n  C.D  " | Set-Content -Path $tmpList
$parsed = Read-PackageListFile $tmpList
Check 'list parser: comments/dupes/trim'   (($parsed -join '|') -eq 'A.B|C.D')
Remove-Item $tmpList -Force

#======================================================================
Section 'Appx removal planning'
$installed = @(
    'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
    'Microsoft.BingNewsExtra_1.0.0.0_neutral_~_8wekyb3d8bbwe'
    'Microsoft.Paint_11.2409.0.0_x64__8wekyb3d8bbwe'
    'Microsoft.WindowsStore_22409.1401.5.0_x64__8wekyb3d8bbwe'
    'Microsoft.DesktopAppInstaller_1.24.0.0_x64__8wekyb3d8bbwe'
    'king.com.CandyCrushSaga_1.0.0.0_x86__kgqvnymyfvs32'
    'Microsoft.WindowsTerminal_1.21.0.0_x64__8wekyb3d8bbwe'
    'SomeVendor.Microsoft.BingNews_1.0.0.0_x64__abc'
)
$r = Resolve-AppxRemovalList -Installed $installed -RemovePrefixes @('Microsoft.BingNews', 'Microsoft.Paint', 'king.com.*', 'Microsoft.WindowsStore', 'Microsoft.DesktopAppInstaller') -KeepPrefixes @('Microsoft.Paint')
Check 'prefix match removes BingNews'      ($r -contains $installed[0])
Check 'prefix also matches BingNewsExtra'  ($r -contains $installed[1])
Check 'no substring match mid-name'        ($r -notcontains $installed[7])
Check 'keep wins'                          ($r -notcontains $installed[2])
Check 'wildcard king.com.*'                ($r -contains $installed[5])
Check 'Store protected by default'         ($r -notcontains $installed[3])
Check 'winget always protected'            ($r -notcontains $installed[4])
Check 'unlisted app untouched'             ($r -notcontains $installed[6])
$r2 = Resolve-AppxRemovalList -Installed $installed -RemovePrefixes @('Microsoft.WindowsStore') -ProtectedPrefixes (Get-ProtectedAppxPrefixes -AllowStoreRemoval)
Check 'Store removable with RemoveStore'   ($r2 -contains $installed[3])
Check 'family name'                        ((Get-PackageFamilyName $installed[0]) -eq 'Microsoft.BingNews_8wekyb3d8bbwe')
Check 'family name (x64 package)'          ((Get-PackageFamilyName $installed[2]) -eq 'Microsoft.Paint_8wekyb3d8bbwe')

#======================================================================
Section 'Capabilities & packages'
$caps = @(
    'Browser.InternetExplorer~~~~0.0.11.0', 'MathRecognizer~~~~0.0.1.0', 'Microsoft.Windows.WordPad~~~~0.0.1.0',
    'Language.Basic~~~en-US~0.0.1.0', 'Language.Handwriting~~~en-US~0.0.1.0', 'Language.OCR~~~en-US~0.0.1.0',
    'Language.Speech~~~en-US~0.0.1.0', 'Language.TextToSpeech~~~en-US~0.0.1.0', 'Language.Handwriting~~~fr-FR~0.0.1.0',
    'Media.WindowsMediaPlayer~~~~0.0.12.0', 'Microsoft.Windows.Notepad.System~~~~0.0.1.0', 'Hello.Face.20134~~~~0.0.1.0'
)
$std = Get-CapabilitiesToRemove -Installed $caps -LanguageCode 'en-US'
$core = Get-CapabilitiesToRemove -Installed $caps -LanguageCode 'en-US' -Core
Check 'std removes IE/WordPad/Math'        (($std -contains $caps[0]) -and ($std -contains $caps[1]) -and ($std -contains $caps[2]))
Check 'never removes Language.Basic'       (($std -notcontains $caps[3]) -and ($core -notcontains $caps[3]))
Check 'std removes handwriting/speech'     (($std -contains $caps[4]) -and ($std -contains $caps[6]))
Check 'std keeps OCR + TTS (Narrator)'     (($std -notcontains $caps[5]) -and ($std -notcontains $caps[7]))
Check 'core removes OCR + TTS'             (($core -contains $caps[5]) -and ($core -contains $caps[7]))
Check 'other languages untouched'          ($core -notcontains $caps[8])
Check 'std keeps WMP legacy, core drops'   (($std -notcontains $caps[9]) -and ($core -contains $caps[9]))
Check 'Notepad / Hello Face kept'          (($core -notcontains $caps[10]) -and ($core -notcontains $caps[11]))
$pkgs = @(
    'Microsoft-Windows-LanguageFeatures-OCR-en-us-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
    'Microsoft-Windows-LanguageFeatures-Basic-en-us-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
    'Windows-Defender-Client-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
    'Microsoft-Windows-Foundation-Package~31bf3856ad364e35~amd64~~10.0.26100.1'
)
$corePkgs = Get-CoreWindowsPackagesToRemove -Installed $pkgs -LanguageCode 'en-US'
Check 'core pkg: OCR (case-insensitive)'   ($corePkgs -contains $pkgs[0])
Check 'core pkg: never Basic/Foundation'   (($corePkgs -notcontains $pkgs[1]) -and ($corePkgs -notcontains $pkgs[3]))
Check 'core pkg: Defender'                 ($corePkgs -contains $pkgs[2])

#======================================================================
Section 'Image selection & info'
$imgs = @(
    [pscustomobject]@{ ImageIndex = 1; ImageName = 'Windows 11 Home' }
    [pscustomobject]@{ ImageIndex = 5; ImageName = 'Windows 11 Pro' }
    [pscustomobject]@{ ImageIndex = 6; ImageName = 'Windows 11 Pro N' }
    [pscustomobject]@{ ImageIndex = 9; ImageName = 'Windows 11 Pro for Workstations' }
)
Check '-Index kept'                        ((Select-ImageIndex -Images $imgs -Index 6) -eq 6)
CheckThrows '-Index missing throws'        { Select-ImageIndex -Images $imgs -Index 2 }
Check '-Edition Pro -> 5 (not Pro N)'      ((Select-ImageIndex -Images $imgs -Edition 'Pro') -eq 5)
Check '-Edition full name'                 ((Select-ImageIndex -Images $imgs -Edition 'Windows 11 Pro N') -eq 6)
Check '-Edition case-insensitive'          ((Select-ImageIndex -Images $imgs -Edition 'home') -eq 1)
CheckThrows '-Edition unknown throws'      { Select-ImageIndex -Images $imgs -Edition 'Enterprise' }
CheckThrows 'multi + non-interactive'      { Select-ImageIndex -Images $imgs -NonInteractive }
Check 'single image auto'                  ((Select-ImageIndex -Images @($imgs[1]) -NonInteractive) -eq 5)
Check 'display 25H2'                       ((Get-WindowsDisplayVersion 26200) -eq '25H2')
Check 'display 26H2 build from reported ISO' ((Get-WindowsDisplayVersion 26300) -eq '26H2')
Check 'display 26H1'                       ((Get-WindowsDisplayVersion 28000) -eq '26H1')
Check 'unknown newer build is explicit'   ((Get-WindowsDisplayVersion 29000) -eq 'Preview (build 29000)')
Check 'display 24H2'                       ((Get-WindowsDisplayVersion 26100) -eq '24H2')
Check 'display 23H2'                       ((Get-WindowsDisplayVersion 22631) -eq '23H2')
Check 'arch enum 9 -> amd64'               ((ConvertTo-ArchitectureName 9) -eq 'amd64')
Check 'arch enum 12 -> arm64'              ((ConvertTo-ArchitectureName 12) -eq 'arm64')
Check 'arch text x64 -> amd64'             ((ConvertTo-ArchitectureName 'x64') -eq 'amd64')
Check 'arch text ARM64 -> arm64'           ((ConvertTo-ArchitectureName 'ARM64') -eq 'arm64')
$m = Get-AvailableImageIndex @('Index : 1', 'Name : Windows 11 Home', 'Size : 15,000,000,000 bytes', 'Index : 3', 'Name : Windows 11 Pro', 'Size : 16,500,000,000 bytes')
Check 'dism text parser'                   ((($m.Index) -join ',') -eq '1,3' -and ($m | Where-Object Index -eq 3).SizeBytes -eq 16500000000)

#======================================================================
Section 'Tweak catalog'
$catalog = Get-TweakCatalog
$ids = @($catalog | ForEach-Object { $_.Id })
Check 'catalog has groups'                 ($catalog.Count -ge 20)
Check 'group ids unique'                   (@($ids | Select-Object -Unique).Count -eq $ids.Count)
$knownFlags = @($flagNames) + @('LowRam', 'DisableDriverUpdates', 'DisableWindowsUpdate')
$seen = @{}
foreach ($g in $catalog) {
    Check "[$($g.Id)] has title"           ([bool]$g.Title)
    $flag = ([string]$g.When).TrimStart('!')
    Check "[$($g.Id)] When '$($g.When)' is a known flag" ($g.When -eq 'Always' -or $knownFlags -contains $flag)
    $hasWork = @($g.Set).Count + @($g.Delete).Count + @($g.Services).Count + @($g.FirstBoot).Count
    Check "[$($g.Id)] does something"      ($hasWork -gt 0)
    foreach ($e in @($g.Set | Where-Object { $_ })) {
        $t = ConvertFrom-TweakEntry $e
        Check "[$($g.Id)] offline path: $($t.Path)"        (Test-OfflineRegistryPath $t.Path)
        Check "[$($g.Id)] no CurrentControlSet: $($t.Path)" ($t.Path -notmatch 'CurrentControlSet')
        Check "[$($g.Id)] no HKLM\z\ root: $($t.Path)"      ($t.Path -notmatch '^HKLM\\z\\')
        Check "[$($g.Id)] type $($t.Type)"                  (@('REG_SZ', 'REG_EXPAND_SZ', 'REG_DWORD', 'REG_QWORD', 'REG_MULTI_SZ', 'REG_BINARY') -contains $t.Type)
        if ($t.Type -eq 'REG_DWORD') { Check "[$($g.Id)] numeric DWORD $($t.Name)" ($t.Value -match '^\d+$') }
        $key = "$($t.Path)|$($t.Name)".ToLowerInvariant()
        if ($seen.ContainsKey($key) -and $seen[$key].Value -ne $t.Value) {
            # The same value set differently by two groups is only acceptable
            # when those groups can never apply together, or the later one is
            # a deliberate superset (listed here).
            $allowed = @('hklm\zsoftware\microsoft\windows\currentversion\policies\explorer|settingspagevisibility')
            Check "[$($g.Id)] conflicting value for $key (also in $($seen[$key].Group))" ($allowed -contains $key)
        }
        $seen[$key] = @{ Value = $t.Value; Group = $g.Id }
    }
    foreach ($e in @($g.Delete | Where-Object { $_ })) {
        Check "[$($g.Id)] delete offline path: $e" (Test-OfflineRegistryPath (($e -split '\|', 2)[0]))
    }
    foreach ($e in @($g.Services | Where-Object { $_ })) {
        Check "[$($g.Id)] service entry '$e'" ($e -match '^[A-Za-z0-9_.-]+=[0-4]$')
    }
}
Check 'Notepad AI policy uses the real key'  ([bool]$seen['hklm\zsoftware\policies\windowsnotepad|disableaifeatures'])
Check 'TIPC uses the real key'               ([bool]$seen['hklm\zntuser\software\microsoft\input\tipc|enabled'])
Check 'search highlights per-user key'       ([bool]$seen['hklm\zntuser\software\microsoft\windows\currentversion\searchsettings|isdynamicsearchboxenabled'])

$plan = @(Get-TweakPlan -Flags (Resolve-BuildPreset Default) | ForEach-Object { $_.Id })
Check 'Default plan: bypass/telemetry/AI'  (($plan -contains 'HardwareBypass') -and ($plan -contains 'Telemetry') -and ($plan -contains 'AI'))
Check 'Default plan: no Defender-off/WU'   (($plan -notcontains 'DefenderOff') -and ($plan -notcontains 'WindowsUpdateOff'))
Check 'Default plan: no UTC/MOTW changes'  (($plan -notcontains 'UtcClock') -and ($plan -notcontains 'ZoneInformation'))
Check 'Default plan: GameDvr off'          ($plan -contains 'GameDvr')
$gplan = @(Get-TweakPlan -Flags (Resolve-BuildPreset Gaming) | ForEach-Object { $_.Id })
Check 'Gaming plan keeps GameDvr (Xbox)'   ($gplan -notcontains 'GameDvr')
$skipPlan = @(Get-TweakPlan -Flags (Resolve-BuildPreset Default) -Skip 'AI' | ForEach-Object { $_.Id })
Check '-Skip removes group'                ($skipPlan -notcontains 'AI')
$onlyPlan = @(Get-TweakPlan -Flags @{} -Only 'HardwareBypass' | ForEach-Object { $_.Id })
Check '-Only'                              (($onlyPlan -join ',') -eq 'HardwareBypass')
CheckThrows 'unknown -Skip id throws'      { Get-TweakPlan -Flags @{} -Skip 'NoSuchGroup' }
Check 'condition Always'                   (Test-TweakCondition -When 'Always' -Flags @{})
Check 'condition flag'                     ((Test-TweakCondition -When 'X' -Flags @{ X = $true }) -and -not (Test-TweakCondition -When 'X' -Flags @{}))
Check 'condition negated'                  ((Test-TweakCondition -When '!X' -Flags @{}) -and -not (Test-TweakCondition -When '!X' -Flags @{ X = $true }))
$fw = ConvertFrom-TweakEntry 'HKLM\zSYSTEM\A|Rule|REG_SZ|v2.10|Action=Block|'
Check 'entry data may contain |'           ($fw.Value -eq 'v2.10|Action=Block|')

#======================================================================
Section 'Bounded native commands'
$nativeHost = (Get-Process -Id $PID).Path # powershell.exe or pwsh.exe
$nativeResult = Invoke-Native -FilePath $nativeHost -ArgumentList @('-NoProfile', '-Command', '[Console]::Out.WriteLine("stdout"); [Console]::Error.WriteLine("stderr"); exit 7') -TimeoutSeconds 10 -PassThru
Check 'native runner preserves exit code' ($nativeResult.ExitCode -eq 7)
Check 'native runner drains stdout' ($nativeResult.Output -contains 'stdout')
Check 'native runner drains stderr' ($nativeResult.Output -contains 'stderr')
$nativeErrors = @()
$nativeResult = Invoke-Native -FilePath $nativeHost -ArgumentList @('-NoProfile', '-Command', '[Console]::Out.WriteLine("stdout"); [Console]::Error.WriteLine("100% complete"); exit 7') -StreamOutput -PassThru -ErrorVariable nativeErrors 6>$null
Check 'streaming stderr is text, not an error' ($nativeErrors.Count -eq 0 -and $nativeResult.Output -contains '100% complete')
Check 'streaming preserves stdout and failure exit' ($nativeResult.Output -contains 'stdout' -and $nativeResult.ExitCode -eq 7)
CheckThrows 'streaming nonexistent executable fails' { Invoke-Native -FilePath 'C:\nonexistent-t11-command.exe' -StreamOutput }
CheckThrows 'streaming timeout terminates child' { Invoke-Native -FilePath $nativeHost -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -StreamOutput -TimeoutSeconds 1 }
$nativeClock = [Diagnostics.Stopwatch]::StartNew()
CheckThrows 'native runner terminates stalled command' { Invoke-Native -FilePath $nativeHost -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 60') -TimeoutSeconds 1 }
Check 'native timeout returns promptly' ($nativeClock.Elapsed.TotalSeconds -lt 10)
# .NET Framework writes a UTF-8 BOM to redirected stdin before closing it, so
# the child may read one BOM line (in its OEM code page) before EOF.
$nativeResult = Invoke-Native -FilePath $nativeHost -ArgumentList @('-NoProfile', '-Command', '$first = [Console]::ReadLine(); if ($null -eq $first -or $null -eq [Console]::ReadLine()) { exit 0 }; exit 1') -TimeoutSeconds 10 -PassThru
Check 'native stdin is closed rather than waiting for input' ($nativeResult.ExitCode -eq 0)
Section 'PowerShell edition support'
$expectedHost = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
Check 'child processes use the current edition' ((Get-PowerShellExecutable) -eq $expectedHost)
if ($PSVersionTable.PSEdition -eq 'Core') {
    # Natively loaded DISM fails on mounted images under PowerShell 7: an
    # already auto-loaded native module must be swapped for the proxy.
    Import-Module Dism -WarningAction SilentlyContinue
    Check 'pwsh: native DISM is not mistaken for the proxy' (-not (Test-DismCompatibilityProxy (Get-Module Dism)))
    Initialize-DismModule
    Check 'pwsh: DISM loaded via compatibility session' (Test-DismCompatibilityProxy (Get-Module Dism))
    Initialize-DismModule
    Check 'pwsh: DISM init is idempotent'   (@(Get-Module Dism).Count -eq 1)
} else {
    Initialize-DismModule
    Check '5.1: DISM stays native'          (-not (Test-DismCompatibilityProxy (Get-Module Dism)))
}
Check 'DISM cmdlets available after init'   ([bool](Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue))

Check 'quoted argument keeps braces'       ((Format-ProcessArgument 'HKLM\z A\{B50E}') -eq '"HKLM\z A\{B50E}"')
CheckThrows 'NUL in argument is refused (would truncate the command line)' { Format-ProcessArgument "HKLM\z A\{B50E}$([char]0)" }

Section 'Registry guard'
Check 'offline path ok'                    (Test-OfflineRegistryPath 'HKLM\zSOFTWARE\Policies\X')
Check 'long form ok'                       (Test-OfflineRegistryPath 'HKEY_LOCAL_MACHINE\zSYSTEM\ControlSet001')
Check 'host path rejected'                 (-not (Test-OfflineRegistryPath 'HKLM\SOFTWARE\Policies\X'))
Check 'lookalike rejected'                 (-not (Test-OfflineRegistryPath 'HKLM\zSOFTWAREX\Y'))
Check 'HKCU rejected'                      (-not (Test-OfflineRegistryPath 'HKCU\Software\X'))
CheckThrows 'Set-RegistryValue refuses host hive' { Set-RegistryValue 'HKLM\SOFTWARE\Tiny11Test' 'x' 'REG_DWORD' '1' }
CheckThrows 'Set-RegistryValue refuses bad type'  { Set-RegistryValue 'HKLM\zSOFTWARE\X' 'x' 'REG_WHATEVER' '1' }
CheckThrows 'Remove-RegistryValue refuses host'   { Remove-RegistryValue 'HKLM\SOFTWARE\Tiny11Test' }
CheckThrows 'Set refuses unloaded offline hive'    { Set-RegistryValue 'HKLM\zSOFTWARE\Tiny11Test' 'x' 'REG_DWORD' '1' }
CheckThrows 'Remove refuses unloaded offline hive' { Remove-RegistryValue 'HKLM\zSOFTWARE\Tiny11Test' }

#======================================================================
#======================================================================
Section 'Source/workspace separation'
Assert-SourceWorkspaceSeparation -SourceRoot 'E:\' -WorkRoot 'C:\.temp\build\tiny11'
Assert-SourceWorkspaceSeparation -SourceRoot 'C:\source' -WorkRoot 'C:\source2'
Check 'separate drives and sibling name prefixes are allowed' $true
CheckThrows 'work inside source is refused before copying' { Assert-SourceWorkspaceSeparation -SourceRoot 'C:\' -WorkRoot 'C:\.temp\tiny11' }
CheckThrows 'source inside work is refused' { Assert-SourceWorkspaceSeparation -SourceRoot 'C:\work\source' -WorkRoot 'C:\work' }
CheckThrows 'equal paths ignore case and trailing separators' { Assert-SourceWorkspaceSeparation -SourceRoot 'C:\Source\' -WorkRoot 'c:\source' }
CheckThrows 'normalized parent segments cannot bypass separation' { Assert-SourceWorkspaceSeparation -SourceRoot 'C:\source' -WorkRoot 'C:\source\other\..' }

Section 'Offline default control set selection'
$module=Get-Module tiny11utils
$global:T11Test=@{ Default=2; Missing=$false; MissingSelect=$false; Denied=$false; ProtectedPath=$null; Paths=@(); Native=@() }
& $module {
    function script:Get-ItemProperty {
        param($LiteralPath,$Name)
        if ($global:T11Test.MissingSelect) { throw 'missing Select key' }
        if ($LiteralPath -ne 'Registry::HKEY_LOCAL_MACHINE\zSYSTEM\Select' -or $Name -ne 'Default') { throw 'Unexpected live registry read' }
        [pscustomobject]@{ Default=$global:T11Test.Default }
    }
    function script:Test-Path {
        param($LiteralPath)
        $global:T11Test.Paths+= $LiteralPath
        return (-not $global:T11Test.Missing)
    }
    function script:Assert-OfflineHiveLoaded { param($Path) }
    function script:Invoke-Native {
        param($FilePath,$ArgumentList,[switch]$PassThru,$TimeoutSeconds)
        $global:T11Test.Native+= ,@($ArgumentList)
        if ($PassThru) {
            if ($global:T11Test.Denied) { [pscustomobject]@{ ExitCode=1; Output=@('Access is denied') } }
            else { [pscustomobject]@{ ExitCode=0; Output=@() } }
        } else { 0 }
    }
}
try {
    Check 'Default=2 selects next-boot ControlSet002' ((Get-OfflineDefaultControlSetName) -eq 'ControlSet002')
    Invoke-RegLoad -HiveName zSYSTEM -FilePath (Join-Path $repo 'logs\mock-system.hiv')
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Test' 'Value' REG_DWORD '1' | Out-Null
    Check 'catalog registry writes use selected control set' ($global:T11Test.Native[-1][1] -eq 'HKLM\zSYSTEM\ControlSet002\Control\Test')
    Remove-RegistryValue 'HKEY_LOCAL_MACHINE\zSYSTEM\ControlSet001\Control\Test' | Out-Null
    Check 'deletes use selected control set and normalize long hive spelling' ($global:T11Test.Native[-1][1] -eq 'HKLM\zSYSTEM\ControlSet002\Control\Test')
    Check 'service start changes succeed in selected set' (Set-OfflineServiceStart -Name DiagTrack -Start 4)
    Check 'service presence query uses selected set' ($global:T11Test.Paths[-1] -eq 'Registry::HKEY_LOCAL_MACHINE\zSYSTEM\ControlSet002\Services\DiagTrack')
    Check 'service write uses selected set' ($global:T11Test.Native[-1][1] -eq 'HKLM\zSYSTEM\ControlSet002\Services\DiagTrack')
    & $module {
        function script:Set-ProtectedOfflineRegistryValue {
            param($Path,$ArgumentList)
            $global:T11Test.ProtectedPath=$Path
        }
    } | Out-Null
    $global:T11Test.Denied=$true
    Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\Test' 'Protected' REG_DWORD '0' | Out-Null
    Check 'denied DWORD fallback receives the selected offline subkey' ($global:T11Test.ProtectedPath -eq 'HKLM\zSYSTEM\ControlSet002\Control\Test')
    $global:T11Test.Denied=$false; $global:T11Test.Missing=$true
    $before=$global:T11Test.Native.Count
    Check 'missing selected-set service is skipped' (-not (Set-OfflineServiceStart -Name AbsentService -Start 4))
    Check 'missing selected-set service never invokes a registry write' ($global:T11Test.Native.Count -eq $before)
    $global:T11Test.Missing=$false
    Check 'non-SYSTEM path unchanged' ((Resolve-OfflineControlSetPath 'HKLM\zSOFTWARE\Policies\Test') -eq 'HKLM\zSOFTWARE\Policies\Test')
    Check 'explicit other set unchanged' ((Resolve-OfflineControlSetPath 'HKLM\zSYSTEM\ControlSet003\Test') -eq 'HKLM\zSYSTEM\ControlSet003\Test')
    Check 'lookalike set unchanged' ((Resolve-OfflineControlSetPath 'HKLM\zSYSTEM\ControlSet0010\Test') -eq 'HKLM\zSYSTEM\ControlSet0010\Test')
    Check 'non-controlset SYSTEM key unchanged' ((Resolve-OfflineControlSetPath 'HKLM\zSYSTEM\Setup\LabConfig') -eq 'HKLM\zSYSTEM\Setup\LabConfig')
    Invoke-RegUnload -HiveName zSYSTEM | Out-Null
    Check 'unload resets selection between images' ((Resolve-OfflineControlSetPath 'HKLM\zSYSTEM\ControlSet001\Test') -eq 'HKLM\zSYSTEM\ControlSet001\Test')
    $global:T11Test.Default=1
    Check 'normal Default=1 keeps original behavior' ((Get-OfflineDefaultControlSetName) -eq 'ControlSet001')
    foreach($invalid in 0,1000,'bad',$null) {
        $global:T11Test.Default=$invalid
        CheckThrows "invalid default '$invalid' refuses guessing" { Get-OfflineDefaultControlSetName }
    }
    $global:T11Test.Default=2; $global:T11Test.Missing=$true
    CheckThrows 'nonexistent selected set is refused' { Get-OfflineDefaultControlSetName }
    $global:T11Test.Missing=$false; $global:T11Test.MissingSelect=$true
    CheckThrows 'missing Select key is refused' { Invoke-RegLoad -HiveName zSYSTEM -FilePath (Join-Path $repo 'logs\mock-system.hiv') }
    Check 'failed selection still tracks attached hive for cleanup' (& $module { $Script:LoadedRegHives.Contains('zSYSTEM') })
    Invoke-RegUnload -HiveName zSYSTEM | Out-Null
} finally {
    Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
    Remove-Variable -Name T11Test -Scope Global
}
$catalog=Get-TweakCatalog
Check 'cloud search disabled only in opt-out-able Search group' ((@($catalog | Where-Object Id -eq Search)[0].Set -contains 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search|AllowCloudSearch|REG_DWORD|0') -and (@(Get-TweakPlan -Flags (Resolve-BuildPreset) -Skip Search | Where-Object Id -eq Search).Count -eq 0))

Section 'Scheduled tasks'
$tasks = Get-TelemetryScheduledTasks
Check 'task list not empty'                ($tasks.Count -ge 10)
Check 'task paths rooted'                  (@($tasks | Where-Object { $_ -notmatch '^\\Microsoft\\Windows\\' }).Count -eq 0)
Check 'unloaded hive -> no ids'            (@(Get-OfflineTaskIds -TaskPath '\Microsoft\Windows\Nope\Nope' -TreeRoot 'Registry::HKEY_LOCAL_MACHINE\zNOTLOADED').Count -eq 0)

#======================================================================
Section 'Answer files'
# Allow-list of settings per component/pass. Anything else (e.g. <Power>,
# <ComputerName> in oobeSystem) makes Windows Setup stop with
# "could not parse or process the unattend answer file".
$allowed = @{
    'windowsPE|Microsoft-Windows-International-Core-WinPE' = 'SetupUILanguage', 'InputLocale', 'SystemLocale', 'UILanguage', 'UILanguageFallback', 'UserLocale'
    'windowsPE|Microsoft-Windows-Setup'                    = 'DiskConfiguration', 'DynamicUpdate', 'ImageInstall', 'RunSynchronous', 'UserData', 'ComplianceCheck', 'Diagnostics', 'EnableFirewall', 'EnableNetwork', 'Restart', 'UseConfigurationSet'
    'specialize|Microsoft-Windows-Shell-Setup'             = 'ComputerName', 'RegisteredOrganization', 'RegisteredOwner', 'TimeZone', 'ProductKey', 'CopyProfile', 'ConfigureChatAutoInstall'
    'specialize|Microsoft-Windows-Deployment'              = 'RunSynchronous', 'RunAsynchronous', 'ExtendOSPartition'
    'oobeSystem|Microsoft-Windows-International-Core'      = 'InputLocale', 'SystemLocale', 'UILanguage', 'UILanguageFallback', 'UserLocale'
    'oobeSystem|Microsoft-Windows-Shell-Setup'             = 'AutoLogon', 'FirstLogonCommands', 'LogonCommands', 'OOBE', 'TimeZone', 'UserAccounts', 'RegisteredOrganization', 'RegisteredOwner', 'DisableAutoDaylightTimeSet', 'ShowWindowsLive', 'VisualEffects', 'Themes'
}
$oobeAllowed = 'HideEULAPage', 'HideLocalAccountScreen', 'HideOEMRegistrationScreen', 'HideOnlineAccountScreens', 'HideWirelessSetupInOOBE', 'ProtectYourPC', 'NetworkLocation', 'UnattendEnableRetailDemo', 'SkipMachineOOBE', 'SkipUserOOBE'
$wcmNs = 'http://schemas.microsoft.com/WMIConfig/2002/State'

function Test-AnswerFile([string]$label, [string]$text) {
    $doc = $null
    try { $doc = [xml]$text } catch { Check "$label well-formed" $false; return }
    Check "$label root <unattend>" ($doc.DocumentElement.LocalName -eq 'unattend' -and $doc.DocumentElement.NamespaceURI -eq 'urn:schemas-microsoft-com:unattend')
    foreach ($child in @($doc.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
        Check "$label only <settings> under root (found <$($child.LocalName)>)" ($child.LocalName -eq 'settings')
    }
    foreach ($settings in @($doc.DocumentElement.ChildNodes | Where-Object { $_.LocalName -eq 'settings' })) {
        $pass = $settings.GetAttribute('pass')
        foreach ($comp in @($settings.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
            $key = "$pass|$($comp.GetAttribute('name'))"
            Check "$label known component $key" ($allowed.ContainsKey($key))
            Check "$label $key has architecture" ($comp.GetAttribute('processorArchitecture') -in 'amd64', 'arm64', 'x86')
            if (-not $allowed.ContainsKey($key)) { continue }
            foreach ($setting in @($comp.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
                Check "$label $key allows <$($setting.LocalName)>" ($allowed[$key] -contains $setting.LocalName)
                if ($setting.LocalName -eq 'OOBE') {
                    foreach ($o in @($setting.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
                        Check "$label OOBE allows <$($o.LocalName)>" ($oobeAllowed -contains $o.LocalName)
                    }
                }
            }
        }
    }
    $actions = $doc.SelectNodes('//@*[local-name()="action"]')
    foreach ($a in $actions) { Check "$label wcm namespace on action" ($a.NamespaceURI -eq $wcmNs) }
}

foreach ($arch in 'amd64', 'arm64') {
    foreach ($zt in $false, $true) {
        foreach ($io in $false, $true) {
            $label = "gen[$arch zt=$zt oobe=$io]"
            $x = New-UnattendXml -Architecture $arch -UserName 'Bob' -Password 'S3cr&t<' -TimeZone 'UTC' -ZeroTouch:$zt -InteractiveOobe:$io -ComputerName 'TINY11-VM' -Locale 'fr-FR'
            Test-AnswerFile $label $x
            Check "$label no plaintext password"        ($x -notmatch 'S3cr')
            Check "$label arch attribute"               ($x -match "processorArchitecture=`"$arch`"")
            Check "$label disk wipe only when ZT"       ([bool]($x -match 'WillWipeDisk') -eq $zt)
            Check "$label account only without OOBE"    ([bool]($x -match '<LocalAccounts>') -eq (-not $io))
            Check "$label first-logon hook"             ($x -match 'FirstLogon\.cmd')
        }
    }
}
$plain = New-UnattendXml -UserName 'User'
Check 'no locale -> OOBE asks region'      ($plain -notmatch 'International-Core')
Check 'no computer name by default'        ($plain -notmatch '<ComputerName>')
Check 'password never expires'             ($plain -match 'maxpwage:UNLIMITED')
Check 'zero-touch implies a locale'        ((New-UnattendXml -ZeroTouch) -match 'Microsoft-Windows-International-Core-WinPE')
$enc = ConvertTo-UnattendPassword -Password 'pw'
Check 'password encoding round-trips'      ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($enc)) -eq 'pwPassword')
Check 'user name escaped'                  ((New-UnattendXml -UserName 'a&b') -match '<Name>a&amp;b</Name>')
CheckThrows 'bad user name throws'         { New-UnattendXml -UserName 'bad/name' }
CheckThrows 'long user name throws'        { New-UnattendXml -UserName ('x' * 21) }
CheckThrows 'bad computer name throws'     { New-UnattendXml -ComputerName 'has space' }
CheckThrows 'numeric computer name throws' { New-UnattendXml -ComputerName '12345' }
CheckThrows 'bad locale throws'            { New-UnattendXml -Locale 'english' }
Check 'interactive OOBE needs no user'     ((New-UnattendXml -InteractiveOobe -UserName '') -match 'HideOnlineAccountScreens')
foreach ($static in 'autounattend.xml', 'autounattend-arm64.xml') {
    $path = Join-Path $repo $static
    if (Test-Path $path) { Test-AnswerFile $static (Get-Content -Raw $path) }
}

#======================================================================
Section 'First-boot scripts'
$sc = New-SetupCompleteScript -Commands @('powercfg.exe -setactive X')
Check 'SetupComplete runs commands'        ($sc -match 'powercfg\.exe -setactive X')
Check 'SetupComplete runs packages'        ($sc -match 'packages\\\*\.cmd')
Check 'SetupComplete CRLF'                 ($sc -match "`r`n")
$fl = New-FirstLogonScript
Check 'FirstLogon deletes answer files'    ($fl -match 'Panther\\unattend\.xml' -and $fl -match 'Sysprep\\unattend\.xml')
Check 'FirstLogon waits for network'       ($fl -match 'ping')

#======================================================================
Section 'ISO helpers'
Check 'bootdata BIOS+UEFI'                 ((Get-OscdimgBootArgument -ImageRoot 'X:\t' -SkipFileCheck) -eq '-bootdata:2#p0,e,bX:\t\boot\etfsboot.com#pEF,e,bX:\t\efi\microsoft\boot\efisys.bin')
Check 'bootdata ARM64 UEFI-only'           ((Get-OscdimgBootArgument -ImageRoot 'X:\t' -Architecture arm64 -SkipFileCheck) -eq '-bootdata:1#pEF,e,bX:\t\efi\microsoft\boot\efisys.bin')
Check 'bootdata no-prompt'                 ((Get-OscdimgBootArgument -ImageRoot 'X:\t' -NoPrompt -SkipFileCheck) -match 'efisys_noprompt\.bin$')
CheckThrows 'missing boot files throw'     { Get-OscdimgBootArgument -ImageRoot 'X:\definitely\missing' }
Check 'oscdimg lookup returns a source'    ((Find-Oscdimg).Source -in 'adk', 'bundled', 'path', 'cached', 'download')
Check 'iso ok'                             (Test-IsoResult -ExitCode 0 -IsoExists $true -IsoBytes 500MB -MinBytes 300MB)
Check 'iso too small'                      (-not (Test-IsoResult -ExitCode 0 -IsoExists $true -IsoBytes 1MB -MinBytes 300MB))
Check 'iso bad exit'                       (-not (Test-IsoResult -ExitCode 1 -IsoExists $true -IsoBytes 500MB))
Check 'robocopy 7 ok / 8 fail'             ((Test-RobocopySucceeded 7) -and -not (Test-RobocopySucceeded 8))
Check 'scratch floor 20 GB'                ((Get-RequiredScratchBytes 1GB) -eq 20GB)
Check 'scratch factor 1.5x'                ((Get-RequiredScratchBytes 20GB) -eq [long](20GB * 1.5))
Check 'scratch sufficiency'                ((Test-SufficientScratch 20GB 30GB).Ok -and -not (Test-SufficientScratch 30GB 20GB).Ok)
Check 'parallel jobs sane'                 ((Get-MaxParallelJobs) -ge 2 -and (Get-MaxParallelJobs) -le 32)

#======================================================================
Section 'Formatting'
$bs = Format-BuildSummary -Elapsed (New-TimeSpan -Minutes 27 -Seconds 41) -IsoBytes 4070127616 -IsoPath 'C:\x\tiny11.iso' -AppsRemoved 31 -AppsTotal 33 -Warnings 2 -Sha256 'abc'
Check 'summary elapsed'                    ($bs -contains '  Elapsed       : 27m 41s')
Check 'summary iso + size'                 ($bs -contains '  Output ISO    : C:\x\tiny11.iso  (3.79 GB)')
Check 'summary apps'                       ($bs -contains '  Apps removed  : 31 of 33 provisioned Appx')
Check 'summary warnings'                   ($bs -contains '  Warnings      : 2 non-fatal (see log)')
Check 'summary sha'                        ($bs -contains '  SHA-256       : abc')
Check 'elapsed over an hour'               ((Format-Elapsed (New-TimeSpan -Hours 1 -Minutes 5 -Seconds 3)) -eq '1h 05m 03s')
Check 'arg: plain'                         ((Format-ProcessArgument 'abc') -eq 'abc')
Check 'arg: empty quoted'                  ((Format-ProcessArgument '') -eq '""')
Check 'arg: spaces quoted'                 ((Format-ProcessArgument 'a b') -eq '"a b"')
Check 'arg: embedded quote'                ((Format-ProcessArgument 'a"b') -eq '"a\"b"')
Check 'arg: trailing backslash'            ((Format-ProcessArgument 'C:\x y\') -eq '"C:\x y\\"')
Check 'arg list'                           ((Build-ProcessArgumentString @('-File', 'C:\a b\c.ps1', '-Password', '')) -eq '-File "C:\a b\c.ps1" -Password ""')

#======================================================================
Section 'Assertions'
CheckThrows 'exit code assert'             { Assert-CommandExitCode -Label 'x' -ExitCode 1 }
Check 'exit code ok'                       ($null -eq (Assert-CommandExitCode -Label 'x' -ExitCode 0))
$fake = Join-Path ([IO.Path]::GetTempPath()) "tiny11-sxs-$PID"
New-Item -ItemType Directory -Force -Path "$fake\amd64_microsoft-windows-servicingstack_1", "$fake\Catalogs", "$fake\Manifests", "$fake\Fusion", "$fake\FileMaps" | Out-Null
$ok = $true; try { Assert-WinSxSRebuild -Path $fake } catch { $ok = $false }
Check 'WinSxS rebuild accepted'            $ok
Remove-Item "$fake\Manifests" -Force
CheckThrows 'WinSxS missing Manifests'     { Assert-WinSxSRebuild -Path $fake }
Remove-Item $fake -Recurse -Force
CheckThrows 'WinSxS missing path'          { Assert-WinSxSRebuild -Path 'C:\nonexistent-path-12345' }

#======================================================================
Section 'Mounted image registry prerequisites'
$module = Get-Module tiny11utils
$global:T11Test = @{ Files = $true; Conflict = $false; Denied = $false; Loads = 0; Unloads = 0 }
& $module {
    function script:Test-Path {
        param($Path, $LiteralPath)
        if ($LiteralPath -like 'Registry::*') { return $global:T11Test.Conflict }
        return $global:T11Test.Files
    }
    function script:Invoke-RegLoad {
        param($HiveName, $FilePath)
        $global:T11Test.Loads++
        if ($global:T11Test.Denied) { throw 'ERROR: The filename or extension is too long.' }
    }
    function script:Invoke-RegUnload { param($HiveName) $global:T11Test.Unloads++ }
} | Out-Null
Assert-MountedImage -MountPath 'X:\mnt'
Check 'mounted image probes and unloads SOFTWARE' ($global:T11Test.Loads -eq 1 -and $global:T11Test.Unloads -eq 1)
$global:T11Test.Conflict = $true
CheckThrows 'mounted image refuses conflicting hive' { Assert-MountedImage -MountPath 'X:\mnt' }
Check 'conflicting hive is never unloaded' ($global:T11Test.Unloads -eq 1)
$global:T11Test.Conflict = $false; $global:T11Test.Denied = $true
$diagnosticError = ''
try { Assert-MountedImage -MountPath 'X:\mnt' } catch { $diagnosticError = $_.Exception.Message }
Check 'mounted image preserves underlying registry failure' ($diagnosticError -like '*DISM cannot service*this image*filename or extension is too long*')
Check 'failed load is not unloaded' ($global:T11Test.Unloads -eq 1)
$global:T11Test.Files = $false
CheckThrows 'missing image SOFTWARE is still rejected' { Assert-MountedImage -MountPath 'X:\mnt' }
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Remove-Variable -Name T11Test -Scope Global

Section 'Isolated mount folders and bounded cleanup'
$mountWork = Join-Path $repo ('logs\mount-test-' + [guid]::NewGuid().ToString('N'))
$global:T11Test = @{ Mounted=@(); QueryFails=$false; DiscardFails=$false; Busy=0; Removes=0; Redirect=$false; Dismounts=@(); BootPath='' }
$module = Get-Module tiny11utils
& $module {
    function script:Get-WindowsImage {
        param([switch]$Mounted, $ErrorAction)
        if ($global:T11Test.QueryFails) { throw 'Mount state unavailable.' }
        $global:T11Test.Mounted
    }
    function script:Invoke-SafeDismountImage {
        param($Path, [switch]$Save)
        $global:T11Test.Dismounts += $Path
        if ($global:T11Test.DiscardFails) { return $false }
        $global:T11Test.Mounted = @(); return $true
    }
    function script:Remove-Item {
        param($LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction)
        $global:T11Test.Removes++
        if ($global:T11Test.Busy -gt 0) { $global:T11Test.Busy--; throw 'Directory briefly busy.' }
        Microsoft.PowerShell.Management\Remove-Item @PSBoundParameters
    }
    function script:Start-Sleep { param($Milliseconds) }
    function script:Get-Item {
        param($LiteralPath, [switch]$Force)
        if ($global:T11Test.Redirect) { return [pscustomobject]@{ Attributes=[IO.FileAttributes]::ReparsePoint } }
        Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
    }
    function script:Invoke-SafeOfflineRegistryUnload { }
    function script:Clear-FileReadOnly { param($FilePath) }
    function script:Get-BootWimIndex { param($BootWimPath) return 2 }
    function script:Mount-WindowsImage { param($ImagePath, $Index, $Path) $global:T11Test.BootPath=$Path }
    function script:Assert-MountedImage { param($MountPath) }
    function script:Mount-OfflineHives { param($MountPath) }
    function script:Invoke-TweakCatalog { param($Only) [pscustomobject]@{ Failures=0 } }
    function script:Dismount-OfflineHives { }
    function script:Add-ImageDrivers { param($MountPath, $DriverPath) return 1 }
} | Out-Null
try {
    $installMount = Initialize-ScratchWorkspace -ScratchRoot $mountWork
    $installMarker = Join-Path $installMount 'install-marker.txt'
    [IO.File]::WriteAllText($installMarker, 'Retain install folder during Setup servicing.')
    $bootMount = Initialize-ScratchWorkspace -ScratchRoot $mountWork -MountName scratchdir_boot
    Check 'Setup mount has its own directory' ($bootMount -ne $installMount -and (Test-Path -LiteralPath $installMarker))
    $null = Invoke-BootImageStage -WorkRoot (Join-Path $mountWork 'tiny11') -ScratchRoot $mountWork -DriverPath 'fixture-drivers'
    Check 'driver-enabled Setup stage uses isolated boot mount' ($global:T11Test.BootPath -eq $bootMount -and (Test-Path -LiteralPath $installMarker))
    $global:T11Test.Busy=1; $beforeRemoves=$global:T11Test.Removes
    Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName scratchdir_boot
    Check 'briefly busy cleanup succeeds on bounded retry' ($global:T11Test.Removes -eq ($beforeRemoves+2) -and -not (Test-Path -LiteralPath $bootMount))
    $null=Initialize-ScratchWorkspace -ScratchRoot $mountWork -MountName scratchdir_boot
    $global:T11Test.Busy=3; $beforeRemoves=$global:T11Test.Removes
    CheckThrows 'persistent busy cleanup reports failure' { Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName scratchdir_boot }
    Check 'persistent busy cleanup stops after three attempts' ($global:T11Test.Removes -eq ($beforeRemoves+3) -and (Test-Path -LiteralPath $bootMount))
    $global:T11Test.Mounted=@([pscustomobject]@{ Path=$bootMount }); $beforeRemoves=$global:T11Test.Removes
    CheckThrows 'mounted directory is never recursively deleted' { Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName scratchdir_boot }
    Check 'mounted-directory refusal happens before deletion' ($global:T11Test.Removes -eq $beforeRemoves)
    $global:T11Test.DiscardFails=$true
    CheckThrows 'failed leftover dismount refuses a new mount' { Initialize-ScratchWorkspace -ScratchRoot $mountWork -MountName scratchdir_boot }
    $workFiles=Join-Path $mountWork 'tiny11'; New-Item -ItemType Directory -Path $workFiles | Out-Null
    [IO.File]::WriteAllText((Join-Path $workFiles 'retained.wim'), 'Do not delete a mounted source.')
    $global:T11Test.Dismounts=@()
    Invoke-EmergencyCleanup -ScratchDisk $mountWork
    Check 'emergency cleanup attempts both mount folders' ($global:T11Test.Dismounts -contains $installMount -and $global:T11Test.Dismounts -contains $bootMount)
    Check 'emergency cleanup retains image files after dismount failure' (Test-Path -LiteralPath (Join-Path $workFiles 'retained.wim'))
    $global:T11Test.DiscardFails=$false
    $null=Initialize-ScratchWorkspace -ScratchRoot $mountWork -MountName scratchdir_boot
    Check 'successful leftover dismount permits a fresh empty boot folder' (@(Get-ChildItem -LiteralPath $bootMount -Force).Count -eq 0)
    $global:T11Test.QueryFails=$true; $beforeRemoves=$global:T11Test.Removes
    CheckThrows 'unknown mount state blocks cleanup' { Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName scratchdir_boot }
    Check 'unknown mount state never deletes files' ($global:T11Test.Removes -eq $beforeRemoves)
    $global:T11Test.QueryFails=$false; $global:T11Test.Redirect=$true
    CheckThrows 'redirected mount directory is refused' { Initialize-ScratchWorkspace -ScratchRoot $mountWork -MountName scratchdir_boot }
    CheckThrows 'redirected mount cleanup is refused' { Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName scratchdir_boot }
    $global:T11Test.Redirect=$false
    CheckThrows 'unexpected mount-folder names are refused' { Remove-ScratchMountDirectory -ScratchRoot $mountWork -MountName '..' }
} finally {
    Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
    Remove-Variable -Name T11Test -Scope Global
    $resolved=[IO.Path]::GetFullPath($mountWork)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'logs'))+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe mount-fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

Section 'AI policy scope and retained app choices'
$aiGroup = @(Get-TweakCatalog | Where-Object Id -eq 'AI')[0]
Check 'AI policies remain controlled by RemoveAI' ($aiGroup.When -eq 'RemoveAI')
foreach ($name in 'EdgeHistoryAISearchEnabled','BuiltInAIAPIsEnabled','AIGenThemesEnabled') {
    Check "$name uses the documented policy path" ($aiGroup.Set -contains "HKLM\zSOFTWARE\Policies\Microsoft\Edge|$name|REG_DWORD|0")
}
Check 'Paint retains its documented policy path' ($aiGroup.Set -contains 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint|DisableCocreator|REG_DWORD|1')
Check 'PR review does not force removal of Photos' ((Resolve-OptionalUtilities -Keep Photos).KeptNames -contains 'Photos')
$withoutAI=(Resolve-BuildPreset Default).Clone(); $withoutAI.RemoveAI=$false
Check 'AI policies are excluded when opted out' (@(Get-TweakPlan -Flags $withoutAI | Where-Object Id -eq 'AI').Count -eq 0)

Section 'Final installation metadata guard'
$expectedMetadata = [pscustomobject]@{ Edition='Professional'; Flags='Professional'; Architecture='amd64'; InstallationType='Client'; ProductType='WinNT'; ProductSuite='Terminal Server'; Language='en-US'; DefaultLanguage='en-US'; Languages=@('en-US'); Version='10.0.26300.9457' }
$global:T11Test = @{ Images = @($expectedMetadata.PSObject.Copy()) }
$module = Get-Module tiny11utils
& $module {
    function script:Get-InstallImageMetadata { param($ImagePath, $Index) $global:T11Test.Images }
    function script:Initialize-Wimlib { 'fixture-wimlib.exe' }
    function script:Invoke-Native { param($FilePath, $ArgumentList) $global:T11Test.Writes++; $global:T11Test.ExitCode }
} | Out-Null
$global:T11Test.Writes=0; $global:T11Test.ExitCode=0
try {
    $accepted = $true
    try { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata } catch { $accepted = $false }
    Check 'matching edition metadata accepted' $accepted
    foreach ($field in 'Edition','Flags','Architecture','InstallationType','ProductType','ProductSuite','Language','DefaultLanguage','Version') {
        $altered = $expectedMetadata.PSObject.Copy(); $altered.$field = ''
        $global:T11Test.Images = @($altered)
        CheckThrows "lost $field refuses ISO creation" { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata }
    }
    $altered = $expectedMetadata.PSObject.Copy(); $altered.Languages = @('fr-FR'); $global:T11Test.Images = @($altered)
    CheckThrows 'changed language set refuses ISO creation' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata }
    $global:T11Test.Images = @($expectedMetadata, $expectedMetadata)
    CheckThrows 'multiple final editions refuse ISO creation' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata }
    $altered=$expectedMetadata.PSObject.Copy(); $altered.Edition=''; $global:T11Test.Images=@($altered)
    $global:T11Test.ExitCode=1
    CheckThrows 'native metadata repair failure refuses ISO creation' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata -RepairMissing }
    $global:T11Test.ExitCode=0
    CheckThrows 'incomplete repair readback refuses ISO creation' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata -RepairMissing }
    $beforeWrites=$global:T11Test.Writes
    $altered.ProductType='Unexpected'; $global:T11Test.Images=@($altered)
    CheckThrows 'conflicting product type blocks missing-edition repair' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $expectedMetadata -RepairMissing }
    Check 'conflicts fail before a native metadata write' ($global:T11Test.Writes -eq $beforeWrites)
    $altered=$expectedMetadata.PSObject.Copy(); $altered.Edition=''; $altered.DefaultLanguage='fr-FR'; $altered.Language='fr-FR'; $global:T11Test.Images=@($altered)
    $sourceWithoutDefault=$expectedMetadata.PSObject.Copy(); $sourceWithoutDefault.DefaultLanguage=''
    CheckThrows 'unknown source default cannot hide a language conflict' { Assert-InstallImageMetadata -ImagePath 'X:\fixture.wim' -Expected $sourceWithoutDefault -RepairMissing }
    Check 'language conflict fails before a native metadata write' ($global:T11Test.Writes -eq $beforeWrites)
} finally {
    Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
    Remove-Variable -Name T11Test -Scope Global
}
Section 'Early offline hive-loading preflight'
if (Test-Path -LiteralPath (Join-Path ([Environment]::SystemDirectory) 'offreg.dll')) {
    $probeWork = Join-Path $repo ('logs\preflight-test-' + [guid]::NewGuid().ToString('N'))
    $global:T11Test = @{ Loads = 0; Unloads = 0; FailLoad = $false; FailUnload = $false; Alias = '' }
    $module = Get-Module tiny11utils
    & $module {
        function script:Invoke-RegLoad {
            param($HiveName, $FilePath)
            $global:T11Test.Loads++; $global:T11Test.Alias = $HiveName
            if ($global:T11Test.FailLoad) { throw 'ERROR: The filename or extension is too long.' }
        }
        function script:Invoke-RegUnload {
            param($HiveName)
            $global:T11Test.Unloads++
            if ($global:T11Test.FailUnload) { throw 'Probe remains attached.' }
        }
    } | Out-Null
    try {
        Test-OfflineHiveLoading -ScratchRoot $probeWork | Out-Null
        Check 'early probe loads/unloads one disposable hive' ($global:T11Test.Loads -eq 1 -and $global:T11Test.Unloads -eq 1)
        Check 'early probe uses a distinct offline alias' ($global:T11Test.Alias -eq ('zT11Preflight' + $PID))
        Check 'successful early probe cleans its files' (@(Get-ChildItem -LiteralPath $probeWork -Force).Count -eq 0)
        $global:T11Test.FailLoad = $true; $diagnosticError = ''
        try { Test-OfflineHiveLoading -ScratchRoot $probeWork } catch { $diagnosticError = $_.Exception.Message }
        Check 'early failure preserves cause and launch guidance' ($diagnosticError -like '*before image servicing*launch context*filename or extension is too long*')
        Check 'failed early load is not unloaded' ($global:T11Test.Unloads -eq 1)
        Check 'failed early load cleans its disposable files' (@(Get-ChildItem -LiteralPath $probeWork -Force).Count -eq 0)
        $global:T11Test.FailLoad = $false; $global:T11Test.FailUnload = $true
        CheckThrows 'early probe reports unload failure' { Test-OfflineHiveLoading -ScratchRoot $probeWork }
        Check 'failed early unload preserves diagnostic file' (@(Get-ChildItem -LiteralPath $probeWork -Recurse -Filter probe.hiv).Count -eq 1)
    } finally {
        Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
        Remove-Variable -Name T11Test -Scope Global
        if (Test-Path -LiteralPath $probeWork) { Remove-Item -LiteralPath $probeWork -Recurse -Force }
    }
}
Section 'Protected registry retry guards'
CheckThrows 'ACL retry refuses host registry' { Set-ProtectedOfflineRegistryValue -Path 'HKLM\SOFTWARE\Tiny11Test' -ArgumentList @('add') }
CheckThrows 'ACL retry refuses an unloaded hive' { Set-ProtectedOfflineRegistryValue -Path 'HKLM\zSOFTWARE\Tiny11Test' -ArgumentList @('add', 'HKLM\zSOFTWARE\Tiny11Test') }
CheckThrows 'ACL retry refuses a different command target' { Set-ProtectedOfflineRegistryValue -Path 'HKLM\zSOFTWARE\Tiny11Test' -ArgumentList @('add', 'HKLM\SOFTWARE\Tiny11Test') }
$module = Get-Module tiny11utils
$global:T11Test = @{ Retry = 0; Message = 'ERROR: Access is denied.'; Arguments = @() }
& $module {
    function script:Assert-OfflineHiveLoaded { param($Path) }
    function script:Invoke-Native { [pscustomobject]@{ ExitCode = 1; Output = @($global:T11Test.Message) } }
    function script:Set-ProtectedOfflineRegistryValue { param($Path, $ArgumentList) $global:T11Test.Retry++; $global:T11Test.Arguments = $ArgumentList }
} | Out-Null
Set-RegistryValue -path 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh' -name 'AllowNewsAndInterests' -type REG_DWORD -value '0' | Out-Null
Check 'access denied triggers targeted retry' ($global:T11Test.Retry -eq 1 -and $global:T11Test.Arguments[1] -eq 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh')
$global:T11Test.Message = 'ERROR: Invalid parameter.'
CheckThrows 'other registry failures still throw' { Set-RegistryValue -path 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh' -name 'x' -type REG_DWORD -value '0' }
Check 'other failures do not trigger file retry' ($global:T11Test.Retry -eq 1)
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Remove-Variable -Name T11Test -Scope Global

Section 'File-only offline registry writes'
if (Test-Path -LiteralPath (Join-Path ([Environment]::SystemDirectory) 'offreg.dll')) {
    Add-Type -Path (Join-Path $repo 'lib\OfflineRegistry.cs')
    $hiveFile = Join-Path $repo "logs\test-offreg-$([guid]::NewGuid().ToString('N')).hive"
    $hiveHandle = [IntPtr]::Zero
    try {
        New-Item -ItemType Directory -Path (Split-Path $hiveFile) -Force | Out-Null
        [Tiny11OfflineRegistry]::Check([Tiny11OfflineRegistry]::ORCreateHive([ref]$hiveHandle), 'Create test hive')
        [Tiny11OfflineRegistry]::Check([Tiny11OfflineRegistry]::ORSaveHive($hiveHandle, $hiveFile, 6, 1), 'Save test hive')
        [void][Tiny11OfflineRegistry]::ORCloseHive($hiveHandle); $hiveHandle = [IntPtr]::Zero
        Set-OfflineHiveDwordValues -HiveFile $hiveFile -Entries @(
            @{ SubKey = 'Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Value = 0 },
            @{ SubKey = 'Explorer\Advanced'; Name = 'TaskbarDa'; Value = 4294967295 }
        )
        [Tiny11OfflineRegistry]::Check([Tiny11OfflineRegistry]::OROpenHive($hiveFile, [ref]$hiveHandle), 'Reopen test hive')
        foreach ($expected in @(@('Policies\Microsoft\Dsh', 'AllowNewsAndInterests', [uint32]0), @('Explorer\Advanced', 'TaskbarDa', [uint32]::MaxValue))) {
            $data = [byte[]]::new(4); $size = [uint32]4; $kind = [uint32]0
            $result = [Tiny11OfflineRegistry]::ORGetValue($hiveHandle, $expected[0], $expected[1], [ref]$kind, $data, [ref]$size)
            Check "saved DWORD $($expected[1])" ($result -eq 0 -and $kind -eq 4 -and $size -eq 4 -and [BitConverter]::ToUInt32($data, 0) -eq $expected[2])
        }
        [void][Tiny11OfflineRegistry]::ORCloseHive($hiveHandle); $hiveHandle = [IntPtr]::Zero
        $before = (Get-FileHash -LiteralPath $hiveFile).Hash
        CheckThrows 'file writer rejects absolute registry paths' { Set-OfflineHiveDwordValues -HiveFile $hiveFile -Entries @(@{ SubKey = 'HKLM\SOFTWARE\Host'; Name = 'x'; Value = 0 }) }
        Check 'rejected edit leaves original file intact' ((Get-FileHash -LiteralPath $hiveFile).Hash -eq $before)
        CheckThrows 'file writer refuses active host SOFTWARE' { Set-OfflineHiveDwordValues -HiveFile (Join-Path $env:SystemRoot 'System32\config\SOFTWARE') -Entries @(@{ SubKey = 'Test'; Name = 'x'; Value = 0 }) }
    } finally {
        if ($hiveHandle -ne [IntPtr]::Zero) { [void][Tiny11OfflineRegistry]::ORCloseHive($hiveHandle) }
        Remove-Item -LiteralPath $hiveFile -Force -ErrorAction SilentlyContinue
    }
}

Section 'Stages with mocked DISM / registry'
# Replace the DISM cmdlets and registry writers *inside the module scope*
# with recorders, then drive the real stage functions.
$module = Get-Module tiny11utils
$global:T11Test = @{
    Image    = [pscustomobject]@{ ImageName = 'Windows 11 Pro'; EditionId = 'Professional'; Architecture = [uint32]12; MajorVersion = [uint32]10; MinorVersion = [uint32]0; Build = [uint32]26100; SPBuild = [uint32]4351; Languages = [System.Collections.Generic.List[string]]@('de-DE'); DefaultLanguageIndex = [uint32]0; ImageSize = [uint64]18GB }
    Appx     = @(
        [pscustomobject]@{ DisplayName = 'Microsoft.BingNews'; PackageName = 'Microsoft.BingNews_4.1.0.0_neutral_~_8wekyb3d8bbwe' }
        [pscustomobject]@{ DisplayName = 'Microsoft.WindowsTerminal'; PackageName = 'Microsoft.WindowsTerminal_1.21.0.0_x64__8wekyb3d8bbwe' }
        [pscustomobject]@{ DisplayName = 'Microsoft.Paint'; PackageName = 'Microsoft.Paint_11.0.0.0_x64__8wekyb3d8bbwe' }
        [pscustomobject]@{ DisplayName = 'Microsoft.WindowsStore'; PackageName = 'Microsoft.WindowsStore_22409.0.0.0_x64__8wekyb3d8bbwe' }
        [pscustomobject]@{ DisplayName = 'Microsoft.XboxIdentityProvider'; PackageName = 'Microsoft.XboxIdentityProvider_12.0.0.0_x64__8wekyb3d8bbwe' }
    )
    Removed  = New-Object System.Collections.Generic.List[string]
    RegSet   = New-Object System.Collections.Generic.List[string]
    RegDel   = New-Object System.Collections.Generic.List[string]
}
& $module {
    function script:Get-WindowsImage { $global:T11Test.Image }
    function script:Get-AppxProvisionedPackage { $global:T11Test.Appx }
    function script:Remove-AppxProvisionedPackage { param($Path, $PackageName) $global:T11Test.Removed.Add($PackageName) }
    function script:Set-RegistryValue { param($path, $name, $type, $value) $global:T11Test.RegSet.Add("$path|$name|$type|$value") }
    function script:Remove-RegistryValue { param($path, $Name) $global:T11Test.RegDel.Add("$path|$Name") }
    function script:Test-Path {
        # Offline services "not present"; everything else goes to the real cmdlet.
        param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, $PathType)
        if ("$Path$LiteralPath" -like 'Registry::*') { return $false }
        $real = @{}; foreach ($k in $PSBoundParameters.Keys) { $real[$k] = $PSBoundParameters[$k] }
        Microsoft.PowerShell.Management\Test-Path @real
    }
} | Out-Null

$info = Get-ImageInfo -ImagePath 'x' -Index 1
Check 'image info: arm64 from enum 12'     ($info.Architecture -eq 'arm64')
Check 'image info: version composed'       ($info.Version -eq '10.0.26100.4351')
Check 'image info: 24H2'                   ($info.DisplayVersion -eq '24H2' -and $info.Is24H2OrLater)
Check 'image info: language'               ($info.Language -eq 'de-DE')

$flags = Resolve-BuildPreset Default
$util = Resolve-OptionalUtilities -Remove Terminal
$res = Invoke-AppRemovalStage -MountPath 'X:\mnt' -Flags $flags -Utilities $util -PackageListPath $listPath 6>$null
Check 'stage: BingNews removed'            ($global:T11Test.Removed -contains $global:T11Test.Appx[0].PackageName)
Check 'stage: -Remove Terminal honoured'   ($global:T11Test.Removed -contains $global:T11Test.Appx[1].PackageName)
Check 'stage: Paint removed (default)'     ($global:T11Test.Removed -contains $global:T11Test.Appx[2].PackageName)
Check 'stage: Store kept'                  ($global:T11Test.Removed -notcontains $global:T11Test.Appx[3].PackageName)
Check 'stage: result counts'               ($res.Total -eq 4 -and $res.Removed.Count -eq 4 -and $res.Failures -eq 0)
$global:T11Test.Removed.Clear()
$res = Invoke-AppRemovalStage -MountPath 'X:\mnt' -Flags (Resolve-BuildPreset Gaming) -Utilities (Resolve-OptionalUtilities) -PackageListPath $listPath 6>$null
Check 'stage: Gaming keeps Xbox sign-in'   ($global:T11Test.Removed -notcontains $global:T11Test.Appx[4].PackageName)
Check 'stage: default keeps Terminal'      ($global:T11Test.Removed -notcontains $global:T11Test.Appx[1].PackageName)
$global:T11Test.Removed.Clear()
$res = Invoke-AppRemovalStage -MountPath 'X:\mnt' -Flags $flags -Utilities $util -PackageListPath $listPath -KeepApps 6>$null
Check 'stage: -KeepApps removes nothing'   ($global:T11Test.Removed.Count -eq 0 -and $res.Total -eq 0)
$global:T11Test.Appx += [pscustomobject]@{ DisplayName = 'Microsoft.SecHealthUI'; PackageName = 'Microsoft.SecHealthUI_1000.26100.9457.0_x64__8wekyb3d8bbwe' }
$securityFlags = Resolve-BuildPreset Default
$securityFlags.RemoveDefender = $true
$global:T11Test.Removed.Clear()
$res = Invoke-AppRemovalStage -MountPath 'X:\mnt' -Flags $securityFlags -Utilities $util -PackageListPath $listPath -ImageBuild 26300 6>$null
Check '26H2: protected Security UI kept' ($global:T11Test.Removed -notcontains $global:T11Test.Appx[-1].PackageName -and $res.Failures -eq 0 -and $res.Total -eq 4)
$global:T11Test.Removed.Clear()
$res = Invoke-AppRemovalStage -MountPath 'X:\mnt' -Flags $securityFlags -Utilities $util -PackageListPath $listPath -ImageBuild 22631 6>$null
Check 'older media: explicit Security UI removal retained' ($global:T11Test.Removed -contains $global:T11Test.Appx[-1].PackageName)

$cat = Invoke-TweakCatalog -Flags $flags 6>$null
$expectedSets = @(Get-TweakPlan -Flags $flags | ForEach-Object { @($_.Set | Where-Object { $_ }) }).Count
Check 'catalog: every planned value written' ($global:T11Test.RegSet.Count -eq $expectedSets)
Check 'catalog: no failures'               ($cat.Failures -eq 0)
Check 'catalog: applied ids reported'      ($cat.Applied -contains 'Telemetry' -and $cat.Applied -notcontains 'DefenderOff')
Check 'catalog: deletes issued'            ($global:T11Test.RegDel -contains 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate|')
$global:T11Test.RegSet.Clear()
$cat = Invoke-TweakCatalog -Flags (Resolve-BuildPreset Gaming) 6>$null
Check 'catalog: Gaming first-boot powercfg' (@($cat.FirstBoot | Where-Object { $_ -match 'powercfg' }).Count -eq 2)
Add-DeprovisionedPackage -PackageName $global:T11Test.Appx[0].PackageName
Check 'deprovision key written'            ($global:T11Test.RegSet -contains 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.BingNews_8wekyb3d8bbwe||REG_SZ|')

# Restore the real functions for the remaining sections.
Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
Remove-Variable -Name T11Test -Scope Global

#======================================================================
Section 'Early Oscdimg readiness and atomic portable cache'
$toolWork = Join-Path $repo ('logs\oscdimg-test-' + [guid]::NewGuid().ToString('N'))
$toolPath = Join-Path $toolWork 'tools\oscdimg\2.56\oscdimg.exe'
$global:T11Test = @{ ToolPath=$toolPath; Mode='success'; Downloads=0; Partial=''; BadCache=$false; Source='download'; HostArchitecture='' }
$module = Get-Module tiny11utils
& $module {
    function script:Find-Oscdimg {
        param($HostArchitecture)
        $global:T11Test.HostArchitecture=$HostArchitecture
        $source=$global:T11Test.Source
        if ($source -eq 'download' -and (Test-Path -LiteralPath $global:T11Test.ToolPath)) { $source='cached' }
        [pscustomobject]@{ Source=$source; Path=$global:T11Test.ToolPath }
    }
    function script:Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing, $ErrorAction)
        $global:T11Test.Downloads++; $global:T11Test.Partial=$OutFile
        [IO.File]::WriteAllText($OutFile,'download fixture')
        if ($global:T11Test.Mode -eq 'offline') { throw 'Network unavailable.' }
    }
    function script:Get-Sha256 {
        param($Path)
        if ($global:T11Test.Mode -eq 'bad-hash' -or ($global:T11Test.BadCache -and $Path -eq $global:T11Test.ToolPath)) { return 'INVALID' }
        'F5129F313ED7EB46F2677CF522E64264A225F226307ED0DDB52BB14C46E7CFDD'
    }
} | Out-Null
try {
    $ready = Initialize-Oscdimg -HostArchitecture ARM64 6>$null
    Check 'download is verified and published to the portable cache' ($ready -eq $toolPath -and (Test-Path -LiteralPath $toolPath))
    Check 'download uses a separate partial file and removes it' ($global:T11Test.Partial -ne $toolPath -and -not (Test-Path -LiteralPath $global:T11Test.Partial))
    Check 'tool lookup receives host architecture before downloading' ($global:T11Test.HostArchitecture -eq 'ARM64')
    $global:T11Test.Mode='offline'
    $ready = Initialize-Oscdimg 6>$null
    Check 'verified cache works without internet' ($ready -eq $toolPath -and $global:T11Test.Downloads -eq 1)
    Remove-Item -LiteralPath $toolPath -Force
    CheckThrows 'network outage fails readiness before image work' { Initialize-Oscdimg 6>$null }
    Check 'network failure publishes no tool and cleans partial data' (-not (Test-Path -LiteralPath $toolPath) -and -not (Test-Path -LiteralPath $global:T11Test.Partial))
    $global:T11Test.Mode='bad-hash'
    CheckThrows 'unexpected download checksum is rejected' { Initialize-Oscdimg 6>$null }
    Check 'bad checksum leaves no executable or partial download' (-not (Test-Path -LiteralPath $toolPath) -and -not (Test-Path -LiteralPath $global:T11Test.Partial))
    $global:T11Test.Mode='success'; $ready=Initialize-Oscdimg 6>$null
    $beforeDownloads=$global:T11Test.Downloads; $global:T11Test.BadCache=$true; $global:T11Test.Mode='offline'
    CheckThrows 'corrupt cache cannot be used offline' { Initialize-Oscdimg 6>$null }
    Check 'corrupt cache is removed and never executed' (-not (Test-Path -LiteralPath $toolPath) -and $global:T11Test.Downloads -eq ($beforeDownloads+1))
    $global:T11Test.BadCache=$false; $global:T11Test.Mode='success'; $ready=Initialize-Oscdimg 6>$null
    $global:T11Test.BadCache=$true; $beforeDownloads=$global:T11Test.Downloads
    $ready=Initialize-Oscdimg 6>$null
    Check 'corrupt cache can be replaced by a verified fresh download' ($ready -eq $toolPath -and (Test-Path -LiteralPath $toolPath) -and $global:T11Test.Downloads -eq ($beforeDownloads+1))
    $global:T11Test.BadCache=$false; $global:T11Test.Mode='offline'; $global:T11Test.Source='adk'; $beforeDownloads=$global:T11Test.Downloads
    $ready=Initialize-Oscdimg 6>$null
    Check 'installed ADK path needs no network or portable-cache download' ($ready -eq $toolPath -and $global:T11Test.Downloads -eq $beforeDownloads)
} finally {
    Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
    Remove-Variable -Name T11Test -Scope Global
    $resolved=[IO.Path]::GetFullPath($toolWork)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'logs'))+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe tool-fixture cleanup.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

Section 'ISO creation failure handling'
$isoTestRoot = Join-Path ([IO.Path]::GetTempPath()) "tiny11-iso-stage-$PID"
New-Item -ItemType Directory -Path $isoTestRoot -Force | Out-Null
$module = Get-Module tiny11utils
New-Item -ItemType Directory -Path (Join-Path $isoTestRoot 'sources') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $isoTestRoot 'sources\install.esd'),'fixture')
$global:T11Test = @{ ExitCode = 0; Create = $true; Stream = $false; BootArg = ''; Initializations=0; NativeCalls=0; Tool='' }
& $module {
    function script:Find-Oscdimg { [pscustomobject]@{ Source = 'bundled' } }
    function script:Initialize-Oscdimg { $global:T11Test.Initializations++; 'fake-oscdimg.exe' }
    function script:Get-OscdimgBootArgument { '-bootdata:2#p0,e,bBIOS#pEF,e,bUEFI' }
    function script:Get-Item { [pscustomobject]@{ Length = [long]301MB } }
    function script:Invoke-Native {
        param($FilePath, $ArgumentList, [switch]$StreamOutput)
        $global:T11Test.NativeCalls++; $global:T11Test.Tool=$FilePath
        $global:T11Test.Stream = [bool]$StreamOutput
        $global:T11Test.BootArg = $ArgumentList[5]
        if ($global:T11Test.Create) { [IO.File]::WriteAllText($ArgumentList[-1], 'fake') }
        Write-Host '100% complete'
        return $global:T11Test.ExitCode
    }
} | Out-Null
try {
    $isoPath = Join-Path $isoTestRoot 'test.iso'
    $size = New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath 6>$null
    Check 'ISO stage returns scalar size, streams and preserves boot argument' ($size -eq 301MB -and $size -is [long] -and $global:T11Test.Stream -and $global:T11Test.BootArg -eq '-bootdata:2#p0,e,bBIOS#pEF,e,bUEFI')
    [IO.File]::WriteAllText((Join-Path $isoTestRoot 'sources\install2.wim'),'leftover')
    CheckThrows 'ISO stage rejects leftover original/intermediate install images' { New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath 6>$null }
    Remove-Item -LiteralPath (Join-Path $isoTestRoot 'sources\install2.wim') -Force
    $preparedTool=Join-Path $isoTestRoot 'prepared-oscdimg.exe'; [IO.File]::WriteAllText($preparedTool,'fake executable')
    $beforeInitializations=$global:T11Test.Initializations
    $size=New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath -OscdimgPath $preparedTool 6>$null
    Check 'ISO stage uses prepared tool without another lookup/download' ($size -eq 301MB -and $global:T11Test.Tool -eq $preparedTool -and $global:T11Test.Initializations -eq $beforeInitializations)
    Check 'prepared portable tool survives successful mastering' (Test-Path -LiteralPath $preparedTool)
    $beforeNativeCalls=$global:T11Test.NativeCalls
    CheckThrows 'missing prepared tool does not trigger a late download' { New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath -OscdimgPath (Join-Path $isoTestRoot 'missing.exe') 6>$null }
    Check 'missing prepared tool preserves output and skips tool initialization/execution' ((Test-Path -LiteralPath $isoPath) -and $global:T11Test.Initializations -eq $beforeInitializations -and $global:T11Test.NativeCalls -eq $beforeNativeCalls)
    $global:T11Test.ExitCode = 7
    CheckThrows 'ISO stage rejects failed tool even with output file' { New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath 6>$null }
    $global:T11Test.ExitCode = 0; $global:T11Test.Create = $false
    CheckThrows 'ISO stage rejects missing output even with exit zero' { New-Tiny11Iso -WorkRoot $isoTestRoot -OutputIso $isoPath 6>$null }
} finally {
    Import-Module -Name (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
    Remove-Variable -Name T11Test -Scope Global
    Remove-Item -LiteralPath $isoTestRoot -Recurse -Force
}

#======================================================================
Section 'GUI logic'
Import-Module -Name (Join-Path $repo 'lib\tiny11gui.psm1') -Force -DisableNameChecking
$tmpGui = Join-Path ([IO.Path]::GetTempPath()) "tiny11-gui-$PID"
New-Item -ItemType Directory -Force -Path $tmpGui | Out-Null
$fakeIso = Join-Path $tmpGui 'fake.iso'
Set-Content -Path $fakeIso -Value 'not an iso'

$flagInfo = Get-GuiFlagInfo
Check 'GUI shows every preset flag'        ((@($flagInfo.Name | Sort-Object) -join ',') -eq (@(Get-PresetFlagNames | Sort-Object) -join ','))
Check 'GUI flag hints present'             (@($flagInfo | Where-Object { -not $_.Hint -or -not $_.Label }).Count -eq 0)
$rt = ConvertFrom-PresetJson -Path (& { $p = Join-Path $tmpGui 'rt.json'; [IO.File]::WriteAllText($p, (ConvertTo-PresetJson -Flags (Resolve-BuildPreset Gaming))); $p })
Check 'preset JSON round-trip'             (@(Get-PresetFlagNames | Where-Object { [bool]$rt[$_] -ne [bool](Resolve-BuildPreset Gaming)[$_] }).Count -eq 0)

$st = Get-GuiDefaultState
Check 'default state: Default preset'      ($st.Preset -eq 'Default' -and -not (Test-GuiFlagsModified -Flags $st.Flags -Preset 'Default'))
Check 'default state: list not modified'   (-not (Test-GuiRemoveListModified -RemoveList $st.RemoveList))
$st.Source = $fakeIso; $st.Index = 6; $st.OutputIso = Join-Path $tmpGui 'out.iso'
$req = ConvertTo-GuiBuildRequest -State $st -WorkDir $tmpGui
Check 'request: maker script'              ($req.Script -eq 'tiny11maker.ps1')
Check 'request: named preset, no files'    ($req.Arguments.Preset -eq 'Default' -and $req.Files.Count -eq 0)
Check 'request: always -Yes'               ($req.Arguments.Yes -eq $true)
Check 'request: never -Custom'             (-not $req.Arguments.Contains('Custom'))
Check 'request: keep/remove utilities'     (@($req.Arguments.Keep) -contains 'Terminal' -and @($req.Arguments.Remove) -contains 'Paint')
Check 'request: no package list'           (-not $req.Arguments.Contains('PackageList'))
$st.Password = 'secret pw'; $st.PasswordConfirm = 'secret pw'
$req = ConvertTo-GuiBuildRequest -State $st -WorkDir $tmpGui
Check 'command line masks password'        ($req.CommandLine -notmatch 'secret' -and $req.CommandLine -match "-Password '\*+'")
Check 'argument keeps password'            ($req.Arguments.Password -eq 'secret pw')
Check 'command line quotes spaces'         ((Format-GuiCommandLine -Script 'x.ps1' -Arguments ([ordered]@{ TimeZone = 'W. Europe Standard Time' })) -eq ".\x.ps1 -TimeZone 'W. Europe Standard Time'")
$st.Flags.EnableUtcClock = $true
$st.RemoveList = @($st.RemoveList | Where-Object { $_ -ne 'Microsoft.BingNews' }) + 'Vendor.Extra'
$req = ConvertTo-GuiBuildRequest -State $st -WorkDir $tmpGui
Check 'modified flags -> custom preset'    ($req.Arguments.Preset -like '*gui-preset.json' -and $req.Files.ContainsKey($req.Arguments.Preset))
$presetFile = Join-Path $tmpGui 'p.json'; [IO.File]::WriteAllText($presetFile, $req.Files[$req.Arguments.Preset])
Check 'custom preset carries the change'   ((Resolve-BuildPreset -PresetName $presetFile).EnableUtcClock)
Check 'modified list -> package list'      ($req.Arguments.PackageList -and $req.Files[$req.Arguments.PackageList] -match 'Vendor\.Extra' -and $req.Files[$req.Arguments.PackageList] -notmatch 'BingNews')
$st.Builder = 'Core'; $st.Flags.LowRam = $true; $st.InteractiveOobe = $true
$req = ConvertTo-GuiBuildRequest -State $st -WorkDir $tmpGui
Check 'Core -> Coremaker, no -LowRam'      ($req.Script -eq 'tiny11Coremaker.ps1' -and -not $req.Arguments.Contains('LowRam'))
Check 'OOBE account -> no -User'           ($req.Arguments.InteractiveOobe -and -not $req.Arguments.Contains('User'))
$st.KeepApps = $true
Check 'KeepApps -> no lists'               (-not (ConvertTo-GuiBuildRequest -State $st -WorkDir $tmpGui).Arguments.Contains('Keep'))
$dl = Get-GuiDefaultState; $dl.Source = 'e:\'
Check 'drive letter source normalised'     ((ConvertTo-GuiBuildRequest -State $dl -WorkDir $tmpGui).Arguments.ISO -eq 'E')

$v = Get-GuiDefaultState
$levels = @(Test-GuiBuildRequest -State $v)
Check 'validation: empty -> errors'        (@($levels | Where-Object Level -eq 'Error').Count -ge 2)
$v.Source = $fakeIso; $v.Index = 6; $v.OutputIso = Join-Path $tmpGui 'out.iso'
Check 'validation: valid -> no errors'     (@(Test-GuiBuildRequest -State $v | Where-Object Level -eq 'Error').Count -eq 0)
$v.Password = 'a'; $v.PasswordConfirm = 'b'
Check 'validation: password mismatch'      (@(Test-GuiBuildRequest -State $v | Where-Object { $_.Message -match 'passwords' }).Count -eq 1)
$v.PasswordConfirm = 'a'; $v.ComputerName = 'bad name!'
Check 'validation: bad computer name'      (@(Test-GuiBuildRequest -State $v | Where-Object Level -eq 'Error').Count -eq 1)
$v.ComputerName = ''; $v.EditionSizeBytes = 20GB; $v['ScratchFreeBytes'] = 5GB
Check 'validation: not enough space'       (@(Test-GuiBuildRequest -State $v | Where-Object { $_.Message -match 'GB free' }).Count -eq 1)
$v['ScratchFreeBytes'] = 0; $v.ZeroTouch = $true
Check 'validation: zero-touch warning'     (@(Test-GuiBuildRequest -State $v | Where-Object { $_.Level -eq 'Warning' -and $_.Message -match 'ZERO' }).Count -eq 1)
$v.Source = 'C:\definitely\missing.iso'
Check 'validation: missing ISO'            (@(Test-GuiBuildRequest -State $v | Where-Object { $_.Message -match 'not found' }).Count -eq 1)

$catalogAll = Get-TweakCatalog
$f0 = Resolve-BuildPreset Default
$rows = @(Get-GuiTweakRows -Flags $f0 -Catalog $catalogAll)
Check 'tweak rows = catalog groups'        ($rows.Count -eq $catalogAll.Count)
$ai = $catalogAll | Where-Object Id -eq 'AI'
$r1 = Set-GuiTweakChoice -Flags $f0 -Skip @() -Group $ai -Checked $false
Check 'uncheck applicable -> skipped'      ($r1.Skip -contains 'AI' -and $r1.Flags.RemoveAI)
$r2 = Set-GuiTweakChoice -Flags $r1.Flags -Skip $r1.Skip -Group $ai -Checked $true
Check 're-check -> unskipped'              ($r2.Skip -notcontains 'AI')
$utc = $catalogAll | Where-Object Id -eq 'UtcClock'
$r3 = Set-GuiTweakChoice -Flags $f0 -Group $utc -Checked $true
Check 'check off-group -> flag on'         ($r3.Flags.EnableUtcClock -and $r3.ChangedFlag -eq 'EnableUtcClock' -and -not $f0.EnableUtcClock)
$dvr = $catalogAll | Where-Object Id -eq 'GameDvr'
$r4 = Set-GuiTweakChoice -Flags (Resolve-BuildPreset Gaming) -Group $dvr -Checked $true
Check 'check !KeepXbox group -> flag off'  (-not $r4.Flags.KeepXbox)

$stage = Get-GuiBuildStage 'Mounting the Windows image...'
Check 'stage: mounting'                    ($stage.Percent -eq 22 -and $stage.Label -like 'Mounting*')
Check 'stage: percent is a number'         ($stage.Percent -is [int])
Check 'stage: summary = 100'               ((Get-GuiBuildStage '===== BUILD SUMMARY =====').Percent -eq 100)
Check 'stage: unknown line'                ($null -eq (Get-GuiBuildStage 'Set registry value: x'))
Check 'line kinds'                         ((Get-GuiLineKind 'WARNING: x') -eq 'warning' -and (Get-GuiLineKind 'FATAL: x') -eq 'error' -and (Get-GuiLineKind '--- [AI] x') -eq 'section' -and (Get-GuiLineKind 'hello') -eq 'text')

$set = Get-GuiDefaultState; $set.Password = 'topsecret'; $set.PasswordConfirm = 'topsecret'; $set.Locale = 'fr-FR'; $set.Flags.EnableUtcClock = $true; $set.SkipTweak = @('AI')
$settingsFile = Join-Path $tmpGui 'settings.json'
Export-GuiSettings -State $set -Path $settingsFile
Check 'settings never store the password'  ((Get-Content -Raw $settingsFile) -notmatch 'topsecret')
$back = Import-GuiSettings -Path $settingsFile
Check 'settings round-trip'                ($back.Locale -eq 'fr-FR' -and $back.Flags.EnableUtcClock -and @($back.SkipTweak) -contains 'AI' -and -not $back.Password)

$tailFile = Join-Path $tmpGui 'tail.log'
[IO.File]::WriteAllText($tailFile, "one`r`ntw")
$reader = @{ Path = $tailFile; Position = 0; Partial = '' }
$l1 = @(Read-GuiLogTail -Reader $reader)
[IO.File]::AppendAllText($tailFile, "o`r`nthree`r`n")
$l2 = @(Read-GuiLogTail -Reader $reader)
Check 'log tail: complete lines only'      (($l1 -join '|') -eq 'one' -and ($l2 -join '|') -eq 'two|three')

# Launcher: run the fake builder exactly the way the window does.
$fake = Join-Path $repo 'scripts\fixtures\fake-builder.ps1'
$env:T11_FAKE_OUT = Join-Path $tmpGui 'fake-out.iso'
$env:T11_FAKE_EXIT = '3'
$runLog = Join-Path $tmpGui 'run.log'
$proc = Start-GuiBuild -ScriptPath $fake -Arguments ([ordered]@{ ISO = 'E'; Password = 'pw'; Yes = $true; Keep = @('Paint') }) -LogPath $runLog -WorkDir $tmpGui
$proc.WaitForExit(60000) | Out-Null
$runText = Get-Content -Raw $runLog
Check 'launcher: builder output captured'  ($runText -match 'Mounting the Windows image' -and $runText -match 'WARNING: a fake warning')
Check 'launcher: native progress is not labelled ERROR' ($runText -match '100% complete' -and $runText -notmatch 'ERROR:.*100% complete|RemoteException')
Check 'launcher: exit code propagated'     ($runText -match '__TINY11_EXIT__ 3' -and $proc.ExitCode -eq 3)
Check 'launcher: args file deleted'        (@(Get-ChildItem $tmpGui -Filter 'gui-args-*.xml').Count -eq 0)
Check 'launcher: arguments passed'         ($runText -match '-ISO: E' -and $runText -match '-Yes: True')

# The whole window, driven automatically (-AutoRun) with the fake builder.
$env:T11_FAKE_EXIT = '0'
Remove-Item -LiteralPath $env:T11_FAKE_OUT -ErrorAction SilentlyContinue
$gs = Get-GuiDefaultState; $gs.Source = $fakeIso; $gs.Index = 6; $gs.EditionName = 'Windows 11 Pro'; $gs.OutputIso = $env:T11_FAKE_OUT
$guiExit = Show-Tiny11BuilderForm -SettingsPath '' -InitialState $gs -AutoRun Build -BuilderOverride $fake -Quiet
Check 'window: build ran to completion'    ($guiExit -eq 0 -and (Test-Path -LiteralPath $env:T11_FAKE_OUT))
$gs2 = Get-GuiDefaultState
$guiExit2 = Show-Tiny11BuilderForm -SettingsPath '' -InitialState $gs2 -AutoRun Build -BuilderOverride $fake -Quiet
Check 'window: invalid state never starts'  ($guiExit2 -eq -1)
$png = Join-Path $tmpGui 'tab.png'
foreach ($tabIndex in 0..6) {
    Show-Tiny11BuilderForm -SettingsPath '' -PreviewPath $png -PreviewTab $tabIndex | Out-Null
    Check "window: tab $tabIndex renders"   ((Test-Path $png) -and (Get-Item $png).Length -gt 10KB)
    Remove-Item $png -Force
}
Remove-Item Env:\T11_FAKE_OUT, Env:\T11_FAKE_EXIT -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tmpGui -Recurse -Force -ErrorAction SilentlyContinue

#======================================================================
Section 'Static lint of the scripts'
$scripts = @('tiny11maker.ps1', 'tiny11Coremaker.ps1', 'tiny11gui.ps1', 'tiny11LegacyProfile.ps1', 'lib\tiny11utils.psm1', 'lib\tiny11gui.psm1', 'scripts\update-generated.ps1')
foreach ($s in $scripts) {
    $path = Join-Path $repo $s
    if (-not (Test-Path $path)) { continue }
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
    Check "$s : UTF-8 BOM when non-ASCII (PS 5.1 reads BOM-less files as ANSI)" ((-not $nonAscii) -or $hasBom)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Check "$s : parses" ($errors.Count -eq 0)
    # Every literal registry path handed to the registry helpers must be offline.
    $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Set-RegistryValue', 'Remove-RegistryValue' }, $true)
    foreach ($call in $calls) {
        $first = $call.CommandElements | Select-Object -Skip 1 -First 1
        if ($first -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            Check "$s : offline path '$($first.Value)'" (Test-OfflineRegistryPath $first.Value)
        }
    }
}
foreach ($s in 'tiny11maker.ps1', 'tiny11Coremaker.ps1') {
    $text = Get-Content -Raw (Join-Path $repo $s)
    # 2>$null / 2>&1 on a native tool throws under EAP=Stop in PS 5.1: use Invoke-Native.
    Check "$s : no native stderr redirection" ($text -notmatch '(?m)^\s*&\s+\S+.*\s2>(\$null|&1)')
    Check "$s : no reg query before hives load" ($text -notmatch 'reg query')
    $earlyToolCheck=$text.IndexOf('if (-not $DryRun) { $Script:oscdimgPath = Initialize-Oscdimg }')
    Check "$s : real builds prepare Oscdimg before source mounting; dry run skips preparation" ($earlyToolCheck -ge 0 -and $earlyToolCheck -lt $text.IndexOf('Resolve-WindowsSource -IsoParameter'))
    Check "$s : final ISO uses the prepared Oscdimg path" ($text -match 'New-Tiny11Iso[^\r\n]*-OscdimgPath \$Script:oscdimgPath')
    Check "$s : source/workspace overlap is checked before work deletion and copying" ($text.IndexOf('Assert-SourceWorkspaceSeparation -SourceRoot') -ge 0 -and $text.IndexOf('Assert-SourceWorkspaceSeparation -SourceRoot') -lt $text.IndexOf('Remove-Item -Path $workRoot') -and $text.IndexOf('Assert-SourceWorkspaceSeparation -SourceRoot') -lt $text.IndexOf('Invoke-Robocopy -Source'))
    Check "$s : verify mount folders before deleting source files" ($text.IndexOf('Remove-ScratchMountDirectory -ScratchRoot') -lt $text.IndexOf('Remove-Item -LiteralPath $workRoot'))
}
$manifest = Read-PowerShellDataFile (Join-Path $repo 'lib\tiny11utils.psd1')
$defined = @((Get-Command -Module tiny11utils).Name)
$notExported = @($defined | Where-Object { $manifest.FunctionsToExport -notcontains $_ })
$stale = @($manifest.FunctionsToExport | Where-Object { $defined -notcontains $_ })
Check "utils manifest lists every function ($($notExported -join ','))" ($notExported.Count -eq 0)
Check "utils manifest has no stale names ($($stale -join ','))"         ($stale.Count -eq 0)

#======================================================================
Write-Host ''
$color = if ($script:fail) { 'Red' } else { 'Green' }
Write-Host "RESULT: $script:pass passed, $script:fail failed" -ForegroundColor $color
if ($script:fail) { exit 1 }
exit 0
