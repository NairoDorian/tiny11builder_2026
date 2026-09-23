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
Check 'default recovery'           ($p.Compress -eq 'recovery')
Check 'default esd'                ($p.UseEsd -and $p.ImageFileName -eq 'install.esd')
Check 'default export recovery'    ($p.ExportCompress -eq 'recovery')
Check 'default cleanup'            (-not $p.SkipCleanup)
$p = Resolve-BuildProfile -Fast
Check '-Fast fast + wim'           ($p.Compress -eq 'fast' -and $p.ImageFileName -eq 'install.wim' -and $p.SkipCleanup)
$p = Resolve-BuildProfile -Compress max
Check 'max -> wim max'             ($p.ExportCompress -eq 'max' -and -not $p.UseEsd)
$p = Resolve-BuildProfile -Compress none -Fast
Check 'explicit wins over -Fast'   ($p.Compress -eq 'none' -and $p.SkipCleanup)
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
Check 'oscdimg lookup returns a source'    ((Find-Oscdimg).Source -in 'adk', 'bundled', 'path', 'download')
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
