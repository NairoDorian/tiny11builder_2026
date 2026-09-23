<#
.SYNOPSIS
    Windows Forms front-end for Tiny11 Builder - Ultimate Edition.

.DESCRIPTION
    Show-Tiny11BuilderForm opens one tabbed window that exposes every option
    of tiny11maker.ps1 / tiny11Coremaker.ps1:

      Source           ISO or drive, edition (with build/arch/language/size),
                       Standard or Core builder, output ISO, work drive,
                       compression, quick build, no-"press any key"
      Preset/features  preset + every preset flag as a checkbox; save/load presets
      Apps             the removal list (checked = removed), optional utilities,
                       keep everything, add prefixes, import/export lists
      Tweaks           every registry tweak group, what enables it, its values;
                       uncheck to skip, check to switch its flag on
      Setup & account  local admin / OOBE account, password, computer name,
                       locale, time zone, zero-touch, custom answer file,
                       answer-file preview
      Extras           .NET 3.5, drivers, browser, payload, low-RAM, driver
                       updates, Defender exclusion on the build machine
      Build            summary, validation, equivalent command line, and the
                       build itself: live log, stage progress, cancel + cleanup

    The build runs as a separate, hidden, non-interactive powershell.exe
    (builder + -Yes); its output is streamed into the window. The window never
    touches the host except "Load editions", which mounts the chosen ISO
    read-only for a few seconds to list its editions.

    The pure parts (flag metadata, state -> builder arguments, validation,
    tweak toggling, progress parsing) are separate functions covered by
    scripts\test-core-helpers.ps1.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Script:AppTitle = 'Tiny11 Builder - Ultimate Edition'
$Script:GuiRepoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }

# Flags the Core builder forces on regardless of the preset (mirrors tiny11Coremaker.ps1).
$Script:CoreForcedFlags = @('RemoveEdge', 'RemoveWebView', 'RemoveOneDrive', 'RemoveDefender', 'RemoveCapabilities')

#======================================================================
#region Pure helpers (unit-tested)
#======================================================================

function Get-GuiFlagInfo {
    # Label, section and help text for every preset flag, in display order.
    @(
        [pscustomobject]@{ Name = 'RemoveAppx';                Section = 'Debloat';     Label = 'Remove provisioned apps';                   Hint = 'Removes the apps in the Apps tab (Bing, Xbox, Teams, Clipchamp, ...).' }
        [pscustomobject]@{ Name = 'RemoveEdge';                Section = 'Debloat';     Label = 'Remove Microsoft Edge';                     Hint = 'Deletes the Edge browser and its updater and blocks reinstallation. Pick a browser in Extras or use winget later.' }
        [pscustomobject]@{ Name = 'RemoveWebView';             Section = 'Debloat';     Label = 'Also remove Edge WebView2';                 Hint = 'WebView2 is needed by Widgets, Teams, the new Outlook and many third-party apps. Only for minimal VMs.' }
        [pscustomobject]@{ Name = 'RemoveOneDrive';            Section = 'Debloat';     Label = 'Remove OneDrive';                           Hint = 'No OneDrive setup at first sign-in, no folder backup nags.' }
        [pscustomobject]@{ Name = 'RemoveAI';                  Section = 'Debloat';     Label = 'Remove Copilot, Recall and AI features';    Hint = 'Copilot, Recall, Click to Do, Settings agent, AI in Paint/Notepad/Edge (24H2/25H2 policies).' }
        [pscustomobject]@{ Name = 'RemoveCapabilities';        Section = 'Debloat';     Label = 'Remove legacy capabilities';                Hint = 'IE mode, WordPad, Steps Recorder, Math Input, PowerShell ISE, Quick Assist, handwriting and speech packs.' }
        [pscustomobject]@{ Name = 'RemoveStore';               Section = 'Debloat';     Label = 'Remove Microsoft Store';                    Hint = 'winget keeps working, but Store apps cannot be installed or updated.' }
        [pscustomobject]@{ Name = 'RemoveDefender';            Section = 'Debloat';     Label = 'Disable Microsoft Defender (no antivirus!)'; Hint = 'Leaves the machine without real-time protection. Isolated VMs only.' }
        [pscustomobject]@{ Name = 'KeepXbox';                  Section = 'Debloat';     Label = 'Keep Xbox app, Game Bar and Xbox sign-in';  Hint = 'Needed for Game Pass and games that use Xbox Live sign-in.' }
        [pscustomobject]@{ Name = 'DisableTelemetry';          Section = 'Privacy';     Label = 'Minimal diagnostic data, telemetry off';     Hint = 'Telemetry policies, DiagTrack service off, telemetry scheduled tasks removed.' }
        [pscustomobject]@{ Name = 'DisableAds';                Section = 'Privacy';     Label = 'No ads, suggestions or Bing in search';     Hint = 'Advertising ID, Start/Settings/lock-screen suggestions, web search in Start.' }
        [pscustomobject]@{ Name = 'DisableSponsoredApps';      Section = 'Privacy';     Label = 'No sponsored / silently installed apps';    Hint = 'Stops Windows from installing promoted apps and clears the Start pins.' }
        [pscustomobject]@{ Name = 'DisableThirdPartyTelemetry'; Section = 'Privacy';    Label = '.NET / PowerShell telemetry opt-out';        Hint = 'Sets DOTNET_CLI_TELEMETRY_OPTOUT and POWERSHELL_TELEMETRY_OPTOUT system-wide.' }
        [pscustomobject]@{ Name = 'BlockFirewallTelemetry';    Section = 'Privacy';     Label = 'Firewall-block compatibility telemetry';    Hint = 'Outbound block rules for CompatTelRunner.exe and DeviceCensus.exe.' }
        [pscustomobject]@{ Name = 'DisableDefenderCloud';      Section = 'Privacy';     Label = 'Defender: no cloud reports or samples';      Hint = 'Keeps Defender on but disables MAPS reporting and automatic sample submission.' }
        [pscustomobject]@{ Name = 'DisableZoneInformation';    Section = 'Privacy';     Label = 'Do not tag downloads (Mark-of-the-Web)';    Hint = 'Less secure: SmartScreen and Office Protected View rely on it.' }
        [pscustomobject]@{ Name = 'EnableUltimatePerformance'; Section = 'Performance'; Label = 'Ultimate Performance power plan';           Hint = 'Activated at first boot. Higher idle power draw; not for laptops on battery.' }
        [pscustomobject]@{ Name = 'EnableFastShutdown';        Section = 'Performance'; Label = 'Fast shutdown (2 s timeouts)';               Hint = 'Hung apps and services are closed after 2 seconds; unsaved work is not waited for.' }
        [pscustomobject]@{ Name = 'DisableMouseAcceleration';  Section = 'Performance'; Label = 'Raw mouse input (no acceleration)';         Hint = 'Turns off "Enhance pointer precision" for every new user.' }
        [pscustomobject]@{ Name = 'TuneDefenderCpuLimit';      Section = 'Performance'; Label = 'Cap Defender scans at 25 % CPU';            Hint = 'Scheduled scans use at most a quarter of the CPU.' }
        [pscustomobject]@{ Name = 'EnableDriverBlocklist';     Section = 'Performance'; Label = 'Vulnerable-driver blocklist';               Hint = 'Enforces Microsoft''s blocklist of known-exploitable drivers (security).' }
        [pscustomobject]@{ Name = 'EnableUtcClock';            Section = 'Performance'; Label = 'Hardware clock in UTC (Linux dual-boot)';   Hint = 'Only useful when another OS shares the clock.' }
    )
}

function Get-GuiPresetDescription {
    param([string]$Preset)
    switch ($Preset) {
        'Default'     { 'Balanced: removes bloat, Edge, OneDrive and AI; keeps Store, Defender and WebView2.' }
        'Gaming'      { 'Default + keeps Xbox/Game Bar, Ultimate Performance, raw mouse, fast shutdown, telemetry firewall rules.' }
        'PrivacyPlus' { 'Default + telemetry firewall rules, no Defender cloud reporting, fast shutdown. Defender stays on.' }
        'Minimal-VM'  { 'Smallest footprint for lab VMs: also removes Store, WebView2 and Defender (no antivirus).' }
        default       { 'Custom flags.' }
    }
}

function Get-GuiCompressionDescription {
    param([string]$Compress)
    switch ($Compress) {
        'recovery' { 'install.esd (LZMS): smallest ISO, slowest export (10-20 min).' }
        'max'      { 'install.wim, maximum LZX compression.' }
        'fast'     { 'install.wim, XPRESS: quick export, larger ISO.' }
        'none'     { 'install.wim, uncompressed: fastest, largest ISO.' }
        default    { '' }
    }
}

function Get-GuiDefaultState {
    # Every field the window edits, with defaults matching the builders.
    $flags = Resolve-BuildPreset -PresetName 'Default'
    $flags['LowRam'] = $false
    $flags['DisableDriverUpdates'] = $false
    $flags['DisableWindowsUpdate'] = $false
    $utilities = Get-OptionalUtilities
    [ordered]@{
        Source             = ''
        Index              = 0
        EditionName        = ''
        EditionSizeBytes   = [long]0
        Builder            = 'Standard'
        Preset             = 'Default'
        PresetFile         = ''
        Flags              = $flags
        Compress           = 'recovery'
        Fast               = $false
        NoPrompt           = $false
        DryRun             = $false
        Scratch            = ''
        OutputIso          = (Join-Path $Script:GuiRepoRoot 'tiny11.iso')
        InteractiveOobe    = $false
        User               = 'User'
        Password           = ''
        PasswordConfirm    = ''
        ComputerName       = ''
        TimeZone           = 'UTC'
        Locale             = ''
        ZeroTouch          = $false
        UnattendFile       = ''
        KeepApps           = $false
        RemoveList         = @(Read-PackageListFile (Join-Path $Script:GuiRepoRoot 'removePackage.txt'))
        Keep               = @($utilities | Where-Object Default -eq 'Keep' | ForEach-Object { $_.Name })
        Remove             = @($utilities | Where-Object Default -eq 'Remove' | ForEach-Object { $_.Name })
        SkipTweak          = @()
        EnableNetFx3       = $false
        DriverPath         = ''
        Browser            = 'None'
        Payload            = $false
        DefenderExclusion  = $false
    }
}

function Test-GuiFlagsModified {
    # $true when the preset flags differ from the named preset.
    param([hashtable]$Flags, [string]$Preset)
    if (-not $Preset -or $Preset -eq 'Custom file') { return $true }
    $reference = Resolve-BuildPreset -PresetName $Preset
    foreach ($name in Get-PresetFlagNames) {
        if ([bool]$Flags[$name] -ne [bool]$reference[$name]) { return $true }
    }
    return $false
}

function Test-GuiRemoveListModified {
    param([string[]]$RemoveList, [string]$DefaultListPath = (Join-Path $Script:GuiRepoRoot 'removePackage.txt'))
    $default = @(Read-PackageListFile $DefaultListPath)
    $current = @($RemoveList | Where-Object { $_ })
    if ($default.Count -ne $current.Count) { return $true }
    return @(Compare-Object -ReferenceObject $default -DifferenceObject $current).Count -gt 0
}

function Format-GuiCommandLine {
    # The builder command a user could paste into an elevated PowerShell.
    param([string]$Script, [System.Collections.IDictionary]$Arguments)
    $quote = {
        param($v)
        $s = [string]$v
        if ($s -match '^[A-Za-z0-9_.:\\,-]+$') { return $s }
        return "'" + $s.Replace("'", "''") + "'"
    }
    $parts = @(".\$Script")
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [bool]) {
            if ($value) { $parts += "-$key" }
        } elseif ($key -eq 'Password') {
            $parts += "-Password '********'"
        } elseif ($value -is [array]) {
            if ($value.Count) { $parts += "-$key " + (($value | ForEach-Object { & $quote $_ }) -join ',') }
        } elseif ("$value" -ne '') {
            $parts += "-$key " + (& $quote $value)
        }
    }
    return ($parts -join ' ')
}

function ConvertTo-GuiBuildRequest {
    # Turns the window state into builder arguments. Returns
    # @{ Script; ScriptPath; Arguments; Files = @{ path = content }; CommandLine }.
    # Files (custom preset / package list) must be written before launching.
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$State,
        [string]$RepoRoot = $Script:GuiRepoRoot,
        [string]$WorkDir = (Join-Path $Script:GuiRepoRoot 'logs\gui')
    )
    $isCore = $State.Builder -eq 'Core'
    $script = if ($isCore) { 'tiny11Coremaker.ps1' } else { 'tiny11maker.ps1' }
    $a = [ordered]@{}
    $files = @{}

    $source = ([string]$State.Source).Trim().Trim('"')
    if ($source -match '^[A-Za-z]:?\\?$') { $source = $source.Substring(0, 1).ToUpperInvariant() }
    $a.ISO = $source
    if ($State.Index) { $a.Index = [int]$State.Index }

    if (Test-GuiFlagsModified -Flags $State.Flags -Preset $State.Preset) {
        $presetPath = Join-Path $WorkDir 'gui-preset.json'
        $files[$presetPath] = ConvertTo-PresetJson -Flags $State.Flags -Name 'GUI' -Description "Flags chosen in the GUI (based on $($State.Preset))"
        $a.Preset = $presetPath
    } else {
        $a.Preset = $State.Preset
    }

    $a.Compress = $State.Compress
    if ($State.Fast) { $a.Fast = $true }
    if ($State.NoPrompt) { $a.NoPrompt = $true }
    if ($State.Scratch) { $a.SCRATCH = ([string]$State.Scratch).Substring(0, 1) }
    if ($State.OutputIso) { $a.OutputIso = $State.OutputIso }

    if ($State.InteractiveOobe) {
        $a.InteractiveOobe = $true
    } else {
        $a.User = $State.User
        if ($State.Password) { $a.Password = $State.Password }
    }
    if ($State.ComputerName) { $a.ComputerName = $State.ComputerName }
    if ($State.TimeZone) { $a.TimeZone = $State.TimeZone }
    if ($State.Locale) { $a.Locale = $State.Locale }
    if ($State.ZeroTouch) { $a.ZeroTouch = $true }
    if ($State.UnattendFile) { $a.UnattendFile = $State.UnattendFile }

    if ($State.KeepApps) {
        $a.KeepApps = $true
    } else {
        if (Test-GuiRemoveListModified -RemoveList $State.RemoveList -DefaultListPath (Join-Path $RepoRoot 'removePackage.txt')) {
            $listPath = Join-Path $WorkDir 'gui-packages.txt'
            $files[$listPath] = ("# Package list chosen in the Tiny11 GUI`r`n" + ((@($State.RemoveList) | Where-Object { $_ }) -join "`r`n") + "`r`n")
            $a.PackageList = $listPath
        }
        if (@($State.Keep).Count) { $a.Keep = @($State.Keep) }
        if (@($State.Remove).Count) { $a.Remove = @($State.Remove) }
    }
    if (@($State.SkipTweak).Count) { $a.SkipTweak = @($State.SkipTweak) }

    if ($State.EnableNetFx3) { $a.EnableNetFx3 = $true }
    if ($State.DriverPath) { $a.DriverPath = $State.DriverPath }
    if ($State.Browser -and $State.Browser -ne 'None') { $a.Browser = $State.Browser }
    if ($State.Payload) { $a.Payload = $true }
    if ($State.DefenderExclusion) { $a.DefenderExclusion = $true }
    if (-not $isCore) {
        if ($State.Flags.LowRam) { $a.LowRam = $true }
        if ($State.Flags.DisableDriverUpdates) { $a.DisableDriverUpdates = $true }
    }
    if ($State.DryRun) { $a.DryRun = $true }
    $a.Yes = $true

    return [pscustomobject]@{
        Script      = $script
        ScriptPath  = Join-Path $RepoRoot $script
        Arguments   = $a
        Files       = $files
        CommandLine = Format-GuiCommandLine -Script $script -Arguments $a
    }
}

function Test-GuiBuildRequest {
    # Validation shown in the Build tab. Returns @{ Level = 'Error'|'Warning'|'Info'; Message }.
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$State)
    $out = New-Object System.Collections.Generic.List[object]
    $add = { param($level, $msg) $out.Add([pscustomobject]@{ Level = $level; Message = $msg }) }

    $source = ([string]$State.Source).Trim().Trim('"')
    if (-not $source) {
        & $add 'Error' 'Choose a Windows 11 ISO file or drive (Source tab).'
    } elseif ($source -notmatch '^[A-Za-z]:?\\?$' -and -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        & $add 'Error' "ISO file not found: $source"
    }
    if (-not $State.Index) { & $add 'Error' 'Pick an edition (Source tab > Load editions).' }
    if (-not $State.InteractiveOobe -and $State.Password -ne $State.PasswordConfirm) {
        & $add 'Error' 'The two passwords do not match (Setup & account tab).'
    }
    if (-not $State.UnattendFile) {
        try {
            $null = New-UnattendXml -UserName $State.User -Password $State.Password -TimeZone $State.TimeZone -Locale $State.Locale `
                -ComputerName $State.ComputerName -ZeroTouch:([bool]$State.ZeroTouch) -InteractiveOobe:([bool]$State.InteractiveOobe)
        } catch {
            & $add 'Error' ($_.Exception.Message -replace '^New-UnattendXml: ', '')
        }
    } elseif (-not (Test-Path -LiteralPath $State.UnattendFile)) {
        & $add 'Error' "Answer file not found: $($State.UnattendFile)"
    }
    if ($State.OutputIso) {
        $dir = Split-Path -Parent $State.OutputIso
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { & $add 'Error' "Output folder does not exist: $dir" }
        if ($State.OutputIso -notmatch '\.iso$') { & $add 'Warning' 'The output file does not end in .iso.' }
    } else {
        & $add 'Error' 'Choose where to save the ISO (Source tab).'
    }
    if ($State.DriverPath -and -not (Test-Path -LiteralPath $State.DriverPath)) { & $add 'Error' "Driver folder not found: $($State.DriverPath)" }
    if ($State.PresetFile -and -not (Test-Path -LiteralPath $State.PresetFile)) { & $add 'Warning' "Preset file not found: $($State.PresetFile) (the flags shown are used)." }

    $f = $State.Flags
    if (-not $State.KeepApps -and $f.RemoveAppx -and -not @($State.RemoveList | Where-Object { $_ }).Count) {
        & $add 'Warning' 'The app removal list is empty: only optional utilities will be removed.'
    }
    if ($State.Builder -eq 'Core') { & $add 'Warning' 'Core image: no Windows Update, language packs, features or WinRE. For VMs and tests only.' }
    if ($State.ZeroTouch) { & $add 'Warning' 'ZERO-TOUCH: the ISO erases disk 0 as soon as it boots. VMs / test PCs only.' }
    if ($f.RemoveDefender -or $State.Builder -eq 'Core') { & $add 'Warning' 'Defender is disabled: the installed system has no antivirus.' }
    if ($f.RemoveWebView) { & $add 'Warning' 'WebView2 removed: Widgets, Teams, the new Outlook and many apps will not work.' }
    if ($f.DisableZoneInformation) { & $add 'Warning' 'Mark-of-the-Web disabled: SmartScreen cannot flag downloaded files.' }
    if ($f.RemoveEdge -and $State.Browser -eq 'None') { & $add 'Info' 'No browser will be installed (Edge is removed). Use Extras > Browser or winget later.' }
    if ($State.EditionSizeBytes -and $State.ScratchFreeBytes) {
        $need = Get-RequiredScratchBytes ([long]$State.EditionSizeBytes)
        if ([long]$State.ScratchFreeBytes -lt $need) {
            & $add 'Error' ('Work drive has {0:N1} GB free, ~{1:N1} GB needed.' -f ($State.ScratchFreeBytes / 1GB), ($need / 1GB))
        }
    }
    if ($State.DryRun) { & $add 'Info' 'Dry run: the plan is printed, nothing is built.' }
    return $out.ToArray()
}

function Get-GuiTweakRows {
    # One row per catalog group: does it apply with these flags, is it checked.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Flags,
        [string[]]$Skip = @(),
        [object[]]$Catalog = (Get-TweakCatalog)
    )
    foreach ($g in $Catalog) {
        $applies = Test-TweakCondition -When $g.When -Flags $Flags
        [pscustomobject]@{
            Id       = $g.Id
            Title    = $g.Title
            When     = $g.When
            Applies  = $applies
            Checked  = $applies -and ($Skip -notcontains $g.Id)
        }
    }
}

function Set-GuiTweakChoice {
    # The user (un)checked a tweak group. Unchecking an applicable group skips
    # it; checking a group whose flag is off switches that flag on (or off for
    # '!Flag' groups). Returns @{ Flags; Skip; ChangedFlag }.
    param(
        [Parameter(Mandatory = $true)][hashtable]$Flags,
        [string[]]$Skip = @(),
        [Parameter(Mandatory = $true)]$Group,
        [Parameter(Mandatory = $true)][bool]$Checked
    )
    $flags = $Flags.Clone()
    $skipList = New-Object System.Collections.Generic.List[string]
    foreach ($s in $Skip) { if ($s) { $skipList.Add($s) } }
    $changed = $null
    if ($Checked) {
        [void]$skipList.Remove($Group.Id)
        if (-not (Test-TweakCondition -When $Group.When -Flags $flags) -and $Group.When -ne 'Always') {
            $flag = $Group.When.TrimStart('!')
            $flags[$flag] = -not $Group.When.StartsWith('!')
            $changed = $flag
        }
    } elseif (-not $skipList.Contains($Group.Id)) {
        $skipList.Add($Group.Id)
    }
    return [pscustomobject]@{ Flags = $flags; Skip = $skipList.ToArray(); ChangedFlag = $changed }
}

function Get-GuiBuildStage {
    # Maps a builder log line to @{ Percent; Label } for the progress bar.
    param([string]$Line)
    $stages = @(
        ,@('Checking prerequisites', 2, 'Checking prerequisites')
        ,@('Selected: ', 5, 'Reading the edition')
        ,@('DRY RUN', 50, 'Dry run')
        ,@('Copying installation media', 8, 'Copying the installation media')
        ,@('Exporting edition', 12, 'Exporting the chosen edition')
        ,@('Mounting the Windows image', 22, 'Mounting the Windows image')
        ,@('Provisioned apps in the image', 26, 'Removing apps')
        ,@('Removing Microsoft Edge', 34, 'Removing Edge')
        ,@('Removing OneDrive', 36, 'Removing OneDrive')
        ,@('Removing optional capabilities', 38, 'Removing capabilities')
        ,@('Enabling .NET Framework 3.5', 42, 'Enabling .NET 3.5')
        ,@('Removing component packages', 44, 'Removing component packages')
        ,@('Removing WinRE', 46, 'Removing WinRE')
        ,@('Taking ownership of WinSxS', 48, 'Rebuilding WinSxS')
        ,@('Loading the image registry', 55, 'Applying registry tweaks')
        ,@('Removing telemetry scheduled tasks', 60, 'Removing telemetry tasks')
        ,@('Cleaning up the component store', 64, 'Cleaning the component store')
        ,@('Committing and unmounting', 74, 'Saving the image')
        ,@('Exporting the final image', 78, 'Compressing the image')
        ,@('Patching boot.wim', 90, 'Patching Windows Setup')
        ,@('Creating ISO', 95, 'Writing the ISO')
        ,@('===== BUILD SUMMARY', 100, 'Done')
        ,@('END DRY RUN', 100, 'Dry run finished')
    )
    foreach ($s in $stages) {
        if ($Line.Contains($s[0])) { return [pscustomobject]@{ Percent = $s[1]; Label = $s[2] } }
    }
    return $null
}

function Get-GuiLineKind {
    # Colour class of a log line: error, warning, section, success or text.
    param([string]$Line)
    if ($Line -match '^(FATAL|ERROR)|failed|^\s*\+ ') { return 'error' }
    if ($Line -match '^WARNING') { return 'warning' }
    if ($Line -match '^(---|===|Selected:)') { return 'section' }
    if ($Line -match 'Result\s+: SUCCESS|^  (Output ISO|SHA-256|Elapsed)') { return 'success' }
    return 'text'
}

function Export-GuiSettings {
    # Saves the window state (never the password) as JSON.
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$State, [Parameter(Mandatory = $true)][string]$Path)
    $copy = [ordered]@{}
    foreach ($k in $State.Keys) { if ($k -notin 'Password', 'PasswordConfirm', 'ScratchFreeBytes') { $copy[$k] = $State[$k] } }
    $copy['SettingsVersion'] = 1
    [IO.File]::WriteAllText($Path, ($copy | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
}

function Import-GuiSettings {
    # Loads settings saved by Export-GuiSettings on top of the defaults;
    # unknown or missing fields are ignored.
    param([Parameter(Mandatory = $true)][string]$Path)
    $state = Get-GuiDefaultState
    $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) {
        if (-not $state.Contains($p.Name)) { continue }
        if ($p.Name -eq 'Flags') {
            foreach ($f in $p.Value.PSObject.Properties) { if ($state.Flags.ContainsKey($f.Name)) { $state.Flags[$f.Name] = [bool]$f.Value } }
        } elseif ($state[$p.Name] -is [array]) {
            $state[$p.Name] = @($p.Value | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        } elseif ($state[$p.Name] -is [bool]) {
            $state[$p.Name] = [bool]$p.Value
        } elseif ($null -ne $p.Value) {
            $state[$p.Name] = $p.Value
        }
    }
    return $state
}

#endregion

#======================================================================
#region Build runner
#======================================================================

function Start-GuiBuild {
    # Starts the builder in a hidden powershell.exe. Arguments travel through
    # a CLIXML file the launcher deletes immediately (so a password never
    # appears on a command line); every output line is appended to $LogPath.
    # Returns the Process. The launcher writes "__TINY11_EXIT__ <code>" last.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [string]$WorkDir = (Split-Path -Parent $LogPath)
    )
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $argsFile = Join-Path $WorkDir "gui-args-$PID.xml"
    $launcher = Join-Path $WorkDir 'gui-launcher.ps1'
    $plain = @{}
    foreach ($k in $Arguments.Keys) { $plain[$k] = $Arguments[$k] }
    $plain | Export-Clixml -LiteralPath $argsFile
    $launcherCode = @'
param([string]$ArgsFile, [string]$LogPath, [string]$Builder)
$ErrorActionPreference = 'Continue'
$log = { param($text) [System.IO.File]::AppendAllText($LogPath, "$text`r`n") }
$code = 1
try {
    $a = Import-Clixml -LiteralPath $ArgsFile
    Remove-Item -LiteralPath $ArgsFile -Force
    & $Builder @a *>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) { & $log "WARNING: $($_.Message)" }
        elseif ($_ -is [System.Management.Automation.ErrorRecord]) { & $log "ERROR: $_" }
        else { & $log "$_" }
    }
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
} catch {
    & $log "FATAL: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $ArgsFile) { Remove-Item -LiteralPath $ArgsFile -Force }
}
& $log "__TINY11_EXIT__ $code"
exit $code
'@
    [IO.File]::WriteAllText($launcher, $launcherCode, (New-Object System.Text.UTF8Encoding $true))
    [IO.File]::WriteAllText($LogPath, '', (New-Object System.Text.UTF8Encoding $false))

    $psi = New-Object System.Diagnostics.ProcessStartInfo 'powershell.exe'
    $psi.Arguments = Build-ProcessArgumentString -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
        '-ArgsFile', $argsFile, '-LogPath', $LogPath, '-Builder', $ScriptPath)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = Split-Path -Parent $ScriptPath
    return [System.Diagnostics.Process]::Start($psi)
}

function Read-GuiLogTail {
    # Returns the lines appended to $Reader's file since the last call.
    # $Reader = @{ Path; Position; Partial } (mutated).
    param([Parameter(Mandatory = $true)][hashtable]$Reader)
    if (-not (Test-Path -LiteralPath $Reader.Path)) { return @() }
    $fs = [System.IO.File]::Open($Reader.Path, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        if ($fs.Length -le $Reader.Position) { return @() }
        [void]$fs.Seek($Reader.Position, 'Begin')
        $buffer = New-Object byte[] ($fs.Length - $Reader.Position)
        $read = $fs.Read($buffer, 0, $buffer.Length)
        $Reader.Position += $read
    } finally {
        $fs.Dispose()
    }
    $text = $Reader.Partial + [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
    $lines = $text -split "`r?`n"
    $Reader.Partial = $lines[-1]
    if ($lines.Count -le 1) { return @() }
    return @($lines[0..($lines.Count - 2)])
}

function Stop-GuiBuild {
    # Kills the builder process tree, then discards the mounted image and
    # unloads the offline hives it may have left behind.
    param($Process, [string]$ScratchDisk)
    if ($Process -and -not $Process.HasExited) {
        $null = Invoke-Native -FilePath 'taskkill.exe' -ArgumentList @('/PID', "$($Process.Id)", '/T', '/F')
        try { $Process.WaitForExit(15000) | Out-Null } catch { Write-Verbose 'Process already gone.' }
    }
    if ($ScratchDisk) {
        Invoke-EmergencyCleanup -ScratchDisk $ScratchDisk
        Clear-StaleBuildState
    }
}

#endregion

#======================================================================
#region Popups and small UI helpers
#======================================================================

function Invoke-PopupInfo {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Message)
    $null = [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Information')
}

function Invoke-PopupError {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Message)
    $null = [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error')
}

function Invoke-PopupYesOrNo {
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][string]$Message)
    return ([System.Windows.Forms.MessageBox]::Show($Message, $Title, 'YesNo', 'Question') -eq 'Yes')
}

function Get-SetupMediaDrives {
    # Drive letters (E:) whose root looks like Windows setup media.
    @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object {
            $root = "$($_.DriveLetter):"
            if ((Test-Path "$root\sources\install.wim") -or (Test-Path "$root\sources\install.esd")) { $root }
        })
}

function Get-NtfsDrives {
    # Fixed NTFS drives as objects (Letter, FreeBytes, Label).
    @(Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' -and $_.DriveType -eq 'Fixed' } |
        Sort-Object DriveLetter | ForEach-Object {
            [pscustomobject]@{ Letter = [string]$_.DriveLetter; FreeBytes = [long]$_.SizeRemaining; Label = ('{0}:  {1:N0} GB free  {2}' -f $_.DriveLetter, ($_.SizeRemaining / 1GB), $_.FileSystemLabel).TrimEnd() }
        })
}

function Get-SourceEditions {
    # Lists the editions of an ISO path or drive letter with their details
    # (Get-ImageInfo objects). Mounts an ISO read-only and dismounts it again.
    param([Parameter(Mandatory = $true)][string]$Source)
    $mountedHere = $false
    $root = $null
    try {
        if ($Source -match '^[A-Za-z]:?\\?$') {
            $root = $Source.Substring(0, 1) + ':'
        } else {
            $image = Get-DiskImage -ImagePath $Source -ErrorAction Stop
            if (-not $image.Attached) {
                $image = Mount-DiskImage -ImagePath $Source -Access ReadOnly -PassThru -ErrorAction Stop
                $mountedHere = $true
            }
            for ($i = 0; $i -lt 20 -and -not $root; $i++) {
                $letter = ($image | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
                if ($letter) { $root = "${letter}:" } else { Start-Sleep -Milliseconds 500 }
            }
            if (-not $root) { throw 'The ISO mounted but got no drive letter.' }
        }
        $wim = if (Test-Path "$root\sources\install.wim") { "$root\sources\install.wim" } else { "$root\sources\install.esd" }
        if (-not (Test-Path $wim)) { throw "$root does not contain sources\install.wim or install.esd." }
        return @(Get-WindowsImage -ImagePath $wim | Sort-Object ImageIndex | ForEach-Object { Get-ImageInfo -ImagePath $wim -Index $_.ImageIndex })
    } finally {
        if ($mountedHere) { Dismount-DiskImage -ImagePath $Source -ErrorAction SilentlyContinue | Out-Null }
    }
}

function Format-GuiEdition {
    param($Info)
    '{0}: {1}   -  {2} ({3})  {4}  {5}  {6:N1} GB' -f $Info.Index, $Info.Name, $Info.DisplayVersion, $Info.Version, $Info.Architecture, $Info.Language, ($Info.SizeBytes / 1GB)
}

function New-UiControl {
    # Creates a control, positions it and adds it to $Parent.
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)]$Parent,
        [int]$X, [int]$Y, [int]$W = 100, [int]$H = 23,
        [string]$Text,
        [hashtable]$Props = @{}
    )
    $c = New-Object "System.Windows.Forms.$Type"
    $c.SetBounds($X, $Y, $W, $H)
    if ($PSBoundParameters.ContainsKey('Text')) { $c.Text = $Text }
    foreach ($k in $Props.Keys) { $c.$k = $Props[$k] }
    $Parent.Controls.Add($c)
    return $c
}

#endregion

#======================================================================
#region Main window
#======================================================================

function Show-Tiny11BuilderForm {
    # Opens the builder window. -PreviewPath renders it (optionally on
    # -PreviewTab) to a PNG without showing it: used by CI and the docs.
    # -InitialState pre-fills the window (tests); -SettingsPath is where the
    # last session is remembered (default: gui-settings.json in the project).
    param(
        [string]$IconPath,
        [string]$BannerPath,
        [object[]]$Utilities = (Get-OptionalUtilities),
        [string]$DefaultOutputFolder,
        [string]$SettingsPath = (Join-Path $Script:GuiRepoRoot 'gui-settings.json'),
        [System.Collections.IDictionary]$InitialState,
        [string]$PreviewPath,
        [int]$PreviewTab = 0,
        # Test hooks: run a build as soon as the window opens (Build | DryRun),
        # with another script in place of the builder, and without pop-ups;
        # the window closes by itself when the build ends.
        [ValidateSet('', 'Build', 'DryRun')][string]$AutoRun = '',
        [string]$BuilderOverride,
        [switch]$Quiet
    )

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $font = New-Object System.Drawing.Font('Segoe UI', 9)
    $bold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $mono = New-Object System.Drawing.Font('Consolas', 9)
    $accent = [System.Drawing.Color]::FromArgb(0, 103, 192)
    $muted = [System.Drawing.Color]::FromArgb(96, 96, 96)
    $danger = [System.Drawing.Color]::Firebrick

    #--- State ---
    $state = if ($InitialState) { $InitialState }
             elseif ($SettingsPath -and (Test-Path -LiteralPath $SettingsPath)) { try { Import-GuiSettings -Path $SettingsPath } catch { Get-GuiDefaultState } }
             else { Get-GuiDefaultState }
    if ($DefaultOutputFolder -and -not $InitialState -and -not ($SettingsPath -and (Test-Path -LiteralPath $SettingsPath))) {
        $state.OutputIso = Join-Path $DefaultOutputFolder 'tiny11.iso'
    }
    $ui = @{
        State      = $state
        Loading    = $true      # suppresses change handlers while controls are filled
        Editions   = @()
        Drives     = @(Get-NtfsDrives)
        Catalog    = @(Get-TweakCatalog)
        FlagBoxes  = @{}
        Process    = $null
        Reader     = $null
        BuildStart = $null
        LastExit   = $null
        BuildScratch = $null
        Quiet      = [bool]$Quiet
        BuilderOverride = $BuilderOverride
        AutoRun    = $AutoRun
    }

    #--- Window ---
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Script:AppTitle
    $form.Font = $font
    $form.AutoScaleMode = 'Dpi'
    $form.ClientSize = New-Object System.Drawing.Size(920, 700)
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.Color]::White
    if ($IconPath -and (Test-Path $IconPath)) { try { $form.Icon = New-Object System.Drawing.Icon($IconPath) } catch { Write-Verbose 'Icon could not be loaded.' } }
    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.AutoPopDelay = 20000
    $ui.Form = $form

    # Header
    $header = New-UiControl -Type Panel -Parent $form -X 0 -Y 0 -W 920 -H 64 -Props @{ BackColor = $accent }
    if ($IconPath -and (Test-Path $IconPath)) {
        $logo = New-UiControl -Type PictureBox -Parent $header -X 14 -Y 10 -W 44 -H 44 -Props @{ SizeMode = 'Zoom'; BackColor = $accent }
        try { $logo.Image = (New-Object System.Drawing.Icon($IconPath, 48, 48)).ToBitmap() } catch { Write-Verbose 'Logo not loaded.' }
    }
    $null = New-UiControl -Type Label -Parent $header -X 68 -Y 9 -W 600 -H 26 -Text 'Tiny11 Builder  -  Ultimate Edition' -Props @{ ForeColor = [System.Drawing.Color]::White; BackColor = $accent; Font = (New-Object System.Drawing.Font('Segoe UI Semibold', 14)) }
    $null = New-UiControl -Type Label -Parent $header -X 70 -Y 37 -W 820 -H 18 -Text 'Build a small, clean Windows 11 ISO from the official one. Nothing on this PC is changed.' -Props @{ ForeColor = [System.Drawing.Color]::FromArgb(220, 235, 250); BackColor = $accent }

    # Tabs
    $tabs = New-UiControl -Type TabControl -Parent $form -X 8 -Y 72 -W 904 -H 568 -Props @{ Padding = (New-Object System.Drawing.Point(14, 5)) }
    $ui.Tabs = $tabs
    $newTab = { param($title) $t = New-Object System.Windows.Forms.TabPage; $t.Text = $title; $t.BackColor = [System.Drawing.Color]::White; $t.AutoScroll = $true; $tabs.TabPages.Add($t); $t }
    $tabSource = & $newTab '1  Source'
    $tabPreset = & $newTab '2  Preset && features'
    $tabApps = & $newTab '3  Apps'
    $tabTweaks = & $newTab '4  Tweaks'
    $tabSetup = & $newTab '5  Setup && account'
    $tabExtras = & $newTab '6  Extras'
    $tabBuild = & $newTab '7  Build'

    # Bottom bar
    $bottom = New-UiControl -Type Panel -Parent $form -X 0 -Y 646 -W 920 -H 54
    $btnLoadProfile = New-UiControl -Type Button -Parent $bottom -X 14 -Y 12 -W 110 -H 30 -Text 'Load profile...'
    $btnSaveProfile = New-UiControl -Type Button -Parent $bottom -X 130 -Y 12 -W 110 -H 30 -Text 'Save profile...'
    $btnReset = New-UiControl -Type Button -Parent $bottom -X 246 -Y 12 -W 110 -H 30 -Text 'Reset all'
    $btnDryRun = New-UiControl -Type Button -Parent $bottom -X 506 -Y 12 -W 110 -H 30 -Text 'Dry run'
    $btnBuild = New-UiControl -Type Button -Parent $bottom -X 622 -Y 8 -W 170 -H 38 -Text 'Build ISO' -Props @{ BackColor = $accent; ForeColor = [System.Drawing.Color]::White; FlatStyle = 'Flat'; Font = (New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)) }
    $btnClose = New-UiControl -Type Button -Parent $bottom -X 798 -Y 12 -W 108 -H 30 -Text 'Close'
    $tip.SetToolTip($btnDryRun, 'Validate everything and print the build plan without building.')
    $tip.SetToolTip($btnLoadProfile, 'Load all settings from a profile file (passwords are never saved).')

    #================ Tab 1: Source ================
    $g1 = New-UiControl -Type GroupBox -Parent $tabSource -X 12 -Y 10 -W 868 -H 150 -Text 'Windows 11 image'
    $null = New-UiControl -Type Label -Parent $g1 -X 14 -Y 30 -W 120 -Text 'ISO file or drive:'
    $cbSource = New-UiControl -Type ComboBox -Parent $g1 -X 140 -Y 27 -W 480
    foreach ($d in (Get-SetupMediaDrives)) { [void]$cbSource.Items.Add($d) }
    $tip.SetToolTip($cbSource, 'A Windows 11 .iso from microsoft.com, or the letter of a mounted ISO / USB stick (e.g. E:).')
    $btnBrowseIso = New-UiControl -Type Button -Parent $g1 -X 628 -Y 26 -W 100 -H 26 -Text 'Browse...'
    $btnLoadEditions = New-UiControl -Type Button -Parent $g1 -X 734 -Y 26 -W 118 -H 26 -Text 'Load editions' -Props @{ Font = $bold }
    $null = New-UiControl -Type Label -Parent $g1 -X 14 -Y 66 -W 120 -Text 'Edition:'
    $cbEdition = New-UiControl -Type ComboBox -Parent $g1 -X 140 -Y 63 -W 712 -Props @{ DropDownStyle = 'DropDownList' }
    $lblEditionHint = New-UiControl -Type Label -Parent $g1 -X 140 -Y 94 -W 712 -H 44 -Text 'Click "Load editions": the ISO is mounted read-only for a moment to list its editions (build, architecture, language, size).' -Props @{ ForeColor = $muted }

    $g2 = New-UiControl -Type GroupBox -Parent $tabSource -X 12 -Y 170 -W 868 -H 110 -Text 'Builder'
    $rbStandard = New-UiControl -Type RadioButton -Parent $g2 -X 16 -Y 26 -W 250 -Text 'Standard  (recommended)' -Props @{ Font = $bold }
    $null = New-UiControl -Type Label -Parent $g2 -X 34 -Y 50 -W 390 -H 50 -Text 'Serviceable: Windows Update, language packs and optional features keep working. For PCs, laptops and long-lived VMs.' -Props @{ ForeColor = $muted }
    $rbCore = New-UiControl -Type RadioButton -Parent $g2 -X 450 -Y 26 -W 250 -Text 'Core  (smallest, VM only)' -Props @{ Font = $bold }
    $null = New-UiControl -Type Label -Parent $g2 -X 468 -Y 50 -W 390 -H 50 -Text 'NOT serviceable: no updates, no WinRE, no Defender, trimmed WinSxS. For disposable VMs and tests.' -Props @{ ForeColor = $muted }

    $g3 = New-UiControl -Type GroupBox -Parent $tabSource -X 12 -Y 290 -W 868 -H 230 -Text 'Output'
    $null = New-UiControl -Type Label -Parent $g3 -X 14 -Y 30 -W 120 -Text 'Save ISO as:'
    $tbOutput = New-UiControl -Type TextBox -Parent $g3 -X 140 -Y 27 -W 588
    $btnSaveAs = New-UiControl -Type Button -Parent $g3 -X 734 -Y 26 -W 118 -H 26 -Text 'Save as...'
    $null = New-UiControl -Type Label -Parent $g3 -X 14 -Y 66 -W 120 -Text 'Work drive:'
    $cbScratch = New-UiControl -Type ComboBox -Parent $g3 -X 140 -Y 63 -W 400 -Props @{ DropDownStyle = 'DropDownList' }
    [void]$cbScratch.Items.Add('(same drive as the builder)')
    foreach ($d in $ui.Drives) { [void]$cbScratch.Items.Add($d.Label) }
    $lblScratchHint = New-UiControl -Type Label -Parent $g3 -X 548 -Y 66 -W 305 -H 36 -Text 'NTFS, ~25 GB free. An SSD makes builds much faster.' -Props @{ ForeColor = $muted }
    $null = New-UiControl -Type Label -Parent $g3 -X 14 -Y 106 -W 120 -Text 'Compression:'
    $cbCompress = New-UiControl -Type ComboBox -Parent $g3 -X 140 -Y 103 -W 160 -Props @{ DropDownStyle = 'DropDownList' }
    foreach ($c in 'recovery', 'max', 'fast', 'none') { [void]$cbCompress.Items.Add($c) }
    $lblCompress = New-UiControl -Type Label -Parent $g3 -X 310 -Y 106 -W 540 -Props @{ ForeColor = $muted }
    $chkFast = New-UiControl -Type CheckBox -Parent $g3 -X 140 -Y 140 -W 700 -Text 'Quick test build: fast compression, skip the component-store cleanup (larger ISO)'
    $chkNoPrompt = New-UiControl -Type CheckBox -Parent $g3 -X 140 -Y 166 -W 700 -Text 'Boot straight into Setup (no "Press any key to boot from CD or DVD")'
    $chkDryRunOpt = New-UiControl -Type CheckBox -Parent $g3 -X 140 -Y 192 -W 700 -Text 'Dry run only: validate and show the plan, build nothing'

    #================ Tab 2: Preset & features ================
    $null = New-UiControl -Type Label -Parent $tabPreset -X 14 -Y 16 -W 60 -Text 'Preset:' -Props @{ Font = $bold }
    $cbPreset = New-UiControl -Type ComboBox -Parent $tabPreset -X 78 -Y 13 -W 170 -Props @{ DropDownStyle = 'DropDownList' }
    foreach ($p in 'Default', 'Gaming', 'PrivacyPlus', 'Minimal-VM', 'Custom file') { [void]$cbPreset.Items.Add($p) }
    $btnPresetReset = New-UiControl -Type Button -Parent $tabPreset -X 256 -Y 12 -W 120 -H 26 -Text 'Reset to preset'
    $btnPresetLoad = New-UiControl -Type Button -Parent $tabPreset -X 382 -Y 12 -W 130 -H 26 -Text 'Load preset file...'
    $btnPresetSave = New-UiControl -Type Button -Parent $tabPreset -X 518 -Y 12 -W 130 -H 26 -Text 'Save as preset...'
    $lblPresetState = New-UiControl -Type Label -Parent $tabPreset -X 660 -Y 16 -W 220 -Props @{ ForeColor = $accent; Font = $bold }
    $lblPresetDesc = New-UiControl -Type Label -Parent $tabPreset -X 14 -Y 44 -W 866 -H 20 -Props @{ ForeColor = $muted }
    $sectionBoxes = @{
        Debloat     = (New-UiControl -Type GroupBox -Parent $tabPreset -X 12 -Y 70 -W 290 -H 330 -Text 'Remove')
        Privacy     = (New-UiControl -Type GroupBox -Parent $tabPreset -X 308 -Y 70 -W 286 -H 330 -Text 'Privacy')
        Performance = (New-UiControl -Type GroupBox -Parent $tabPreset -X 600 -Y 70 -W 280 -H 330 -Text 'Performance && security')
    }
    $rowY = @{ Debloat = 24; Privacy = 24; Performance = 24 }
    foreach ($fi in Get-GuiFlagInfo) {
        $box = $sectionBoxes[$fi.Section]
        $cb = New-UiControl -Type CheckBox -Parent $box -X 12 -Y $rowY[$fi.Section] -W ($box.Width - 20) -H 34 -Text $fi.Label -Props @{ Tag = $fi.Name }
        $tip.SetToolTip($cb, $fi.Hint)
        if ($fi.Name -in 'RemoveDefender', 'RemoveWebView', 'DisableZoneInformation') { $cb.ForeColor = $danger }
        $ui.FlagBoxes[$fi.Name] = $cb
        $rowY[$fi.Section] += 33
    }
    $null = New-UiControl -Type Label -Parent $tabPreset -X 14 -Y 410 -W 866 -H 100 -Text ("Every checkbox maps to a preset flag; hover for details. Changing any box turns the build into a custom preset (saved to logs\gui\gui-preset.json and passed with -Preset).`n" +
        "The exact registry values behind each option are listed in the Tweaks tab and in docs\TWEAKS.md. With the Core builder, Edge, WebView2, OneDrive, capabilities and Defender are always removed.") -Props @{ ForeColor = $muted }

    #================ Tab 3: Apps ================
    $chkKeepApps = New-UiControl -Type CheckBox -Parent $tabApps -X 14 -Y 10 -W 600 -Text 'Keep ALL provisioned apps (remove nothing from this tab)' -Props @{ Font = $bold }
    $null = New-UiControl -Type Label -Parent $tabApps -X 14 -Y 38 -W 520 -Text 'Removed apps (checked = removed; matched by package-name prefix):' -Props @{ ForeColor = $accent; Font = $bold }
    $lvApps = New-UiControl -Type ListView -Parent $tabApps -X 14 -Y 60 -W 520 -H 380 -Props @{ View = 'Details'; CheckBoxes = $true; FullRowSelect = $true; HeaderStyle = 'None'; ShowGroups = $true }
    [void]$lvApps.Columns.Add('Package prefix', 490)
    $tbAddApp = New-UiControl -Type TextBox -Parent $tabApps -X 14 -Y 448 -W 270
    $btnAddApp = New-UiControl -Type Button -Parent $tabApps -X 290 -Y 447 -W 90 -H 25 -Text 'Add prefix'
    $tip.SetToolTip($tbAddApp, 'e.g. Microsoft.MicrosoftJournal or SpotifyAB.* (wildcards allowed)')
    $btnAppsAll = New-UiControl -Type Button -Parent $tabApps -X 14 -Y 480 -W 60 -H 25 -Text 'All'
    $btnAppsNone = New-UiControl -Type Button -Parent $tabApps -X 78 -Y 480 -W 60 -H 25 -Text 'None'
    $btnAppsDefault = New-UiControl -Type Button -Parent $tabApps -X 142 -Y 480 -W 70 -H 25 -Text 'Default'
    $btnAppsImport = New-UiControl -Type Button -Parent $tabApps -X 334 -Y 480 -W 96 -H 25 -Text 'Import list...'
    $btnAppsExport = New-UiControl -Type Button -Parent $tabApps -X 436 -Y 480 -W 98 -H 25 -Text 'Export list...'
    $null = New-UiControl -Type Label -Parent $tabApps -X 552 -Y 38 -W 330 -Text 'Optional apps (checked = kept):' -Props @{ ForeColor = $accent; Font = $bold }
    $clbUtil = New-UiControl -Type CheckedListBox -Parent $tabApps -X 552 -Y 60 -W 328 -H 230 -Props @{ CheckOnClick = $true }
    foreach ($u in $Utilities) { [void]$clbUtil.Items.Add($u.Name) }
    $lblAppsInfo = New-UiControl -Type Label -Parent $tabApps -X 552 -Y 300 -W 328 -H 210 -Props @{ ForeColor = $muted }

    #================ Tab 4: Tweaks ================
    $null = New-UiControl -Type Label -Parent $tabTweaks -X 14 -Y 10 -W 866 -H 34 -Text 'Registry tweak groups (data\tweaks.psd1). Checked groups are applied. Uncheck to skip a group; checking a greyed group switches on the preset flag it needs. Select a group to see every value it writes.' -Props @{ ForeColor = $muted }
    $lvTweaks = New-UiControl -Type ListView -Parent $tabTweaks -X 14 -Y 48 -W 866 -H 290 -Props @{ View = 'Details'; CheckBoxes = $true; FullRowSelect = $true; MultiSelect = $false }
    [void]$lvTweaks.Columns.Add('Group', 150)
    [void]$lvTweaks.Columns.Add('Enabled by', 170)
    [void]$lvTweaks.Columns.Add('What it does', 520)
    $tbTweakDetail = New-UiControl -Type TextBox -Parent $tabTweaks -X 14 -Y 346 -W 866 -H 132 -Props @{ Multiline = $true; ReadOnly = $true; ScrollBars = 'Both'; WordWrap = $false; Font = $mono; BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248) }
    $btnTweaksAll = New-UiControl -Type Button -Parent $tabTweaks -X 14 -Y 486 -W 190 -H 26 -Text 'Apply every applicable group'
    $lblTweakCount = New-UiControl -Type Label -Parent $tabTweaks -X 214 -Y 490 -W 660 -Props @{ ForeColor = $muted }

    #================ Tab 5: Setup & account ================
    $g5a = New-UiControl -Type GroupBox -Parent $tabSetup -X 12 -Y 10 -W 430 -H 250 -Text 'Account'
    $rbLocalAdmin = New-UiControl -Type RadioButton -Parent $g5a -X 14 -Y 24 -W 400 -Text 'Create a local administrator automatically'
    $null = New-UiControl -Type Label -Parent $g5a -X 34 -Y 56 -W 110 -Text 'User name:'
    $tbUser = New-UiControl -Type TextBox -Parent $g5a -X 150 -Y 53 -W 260
    $null = New-UiControl -Type Label -Parent $g5a -X 34 -Y 88 -W 110 -Text 'Password:'
    $tbPassword = New-UiControl -Type TextBox -Parent $g5a -X 150 -Y 85 -W 260 -Props @{ UseSystemPasswordChar = $true }
    $null = New-UiControl -Type Label -Parent $g5a -X 34 -Y 120 -W 110 -Text 'Confirm:'
    $tbPassword2 = New-UiControl -Type TextBox -Parent $g5a -X 150 -Y 117 -W 260 -Props @{ UseSystemPasswordChar = $true }
    $chkShowPw = New-UiControl -Type CheckBox -Parent $g5a -X 150 -Y 144 -W 200 -Text 'Show password'
    $null = New-UiControl -Type Label -Parent $g5a -X 34 -Y 166 -W 380 -H 30 -Text 'Empty = no password. Stored Base64-obfuscated; the answer files are deleted after the first sign-in.' -Props @{ ForeColor = $muted }
    $rbOobe = New-UiControl -Type RadioButton -Parent $g5a -X 14 -Y 204 -W 410 -H 36 -Text 'Let me create my local account during setup (OOBE)'

    $g5b = New-UiControl -Type GroupBox -Parent $tabSetup -X 450 -Y 10 -W 430 -H 250 -Text 'Region && computer'
    $null = New-UiControl -Type Label -Parent $g5b -X 14 -Y 30 -W 110 -Text 'Language:'
    $cbLocale = New-UiControl -Type ComboBox -Parent $g5b -X 130 -Y 27 -W 286 -Props @{ DropDownStyle = 'DropDown'; AutoCompleteMode = 'SuggestAppend'; AutoCompleteSource = 'ListItems' }
    [void]$cbLocale.Items.Add('(ask during setup)')
    foreach ($ci in ([System.Globalization.CultureInfo]::GetCultures('SpecificCultures') | Sort-Object Name)) { [void]$cbLocale.Items.Add("$($ci.Name)  -  $($ci.EnglishName)") }
    $tip.SetToolTip($cbLocale, 'Pre-selects language, region and keyboard and skips those setup pages. Leave "(ask during setup)" to choose them in OOBE.')
    $null = New-UiControl -Type Label -Parent $g5b -X 14 -Y 66 -W 110 -Text 'Time zone:'
    $cbTimeZone = New-UiControl -Type ComboBox -Parent $g5b -X 130 -Y 63 -W 286 -Props @{ DropDownStyle = 'DropDownList'; DropDownWidth = 480 }
    $zones = @([System.TimeZoneInfo]::GetSystemTimeZones())
    foreach ($z in $zones) { [void]$cbTimeZone.Items.Add($z.DisplayName) }
    $btnTzHere = New-UiControl -Type Button -Parent $g5b -X 130 -Y 92 -W 150 -H 24 -Text 'Use this PC''s zone'
    $null = New-UiControl -Type Label -Parent $g5b -X 14 -Y 134 -W 110 -Text 'Computer name:'
    $tbComputer = New-UiControl -Type TextBox -Parent $g5b -X 130 -Y 131 -W 286
    $null = New-UiControl -Type Label -Parent $g5b -X 130 -Y 158 -W 286 -H 34 -Text 'Empty = Windows picks DESKTOP-XXXXXXX. Max 15 letters, digits or "-".' -Props @{ ForeColor = $muted }

    $g5c = New-UiControl -Type GroupBox -Parent $tabSetup -X 12 -Y 268 -W 868 -H 246 -Text 'Installation'
    $chkZeroTouch = New-UiControl -Type CheckBox -Parent $g5c -X 14 -Y 26 -W 840 -Text 'ZERO-TOUCH: erase disk 0 and install with no questions at all (UEFI/GPT)' -Props @{ ForeColor = $danger; Font = $bold }
    $null = New-UiControl -Type Label -Parent $g5c -X 32 -Y 50 -W 820 -H 34 -Text 'DESTRUCTIVE: the ISO wipes the first disk as soon as it boots. Only for virtual machines or dedicated test PCs. Implies "boot straight into Setup".' -Props @{ ForeColor = $muted }
    $null = New-UiControl -Type Label -Parent $g5c -X 14 -Y 96 -W 170 -Text 'Custom answer file (optional):'
    $tbUnattend = New-UiControl -Type TextBox -Parent $g5c -X 190 -Y 93 -W 450
    $btnUnattendBrowse = New-UiControl -Type Button -Parent $g5c -X 646 -Y 92 -W 90 -H 25 -Text 'Browse...'
    $btnUnattendClear = New-UiControl -Type Button -Parent $g5c -X 742 -Y 92 -W 60 -H 25 -Text 'Clear'
    $null = New-UiControl -Type Label -Parent $g5c -X 190 -Y 120 -W 660 -H 34 -Text 'Replaces the generated answer file (account, locale and zero-touch options above are then ignored). Its image index is pointed at the exported edition.' -Props @{ ForeColor = $muted }
    $btnPreviewXml = New-UiControl -Type Button -Parent $g5c -X 14 -Y 164 -W 220 -H 30 -Text 'Preview the answer file...'
    $btnSaveXml = New-UiControl -Type Button -Parent $g5c -X 240 -Y 164 -W 220 -H 30 -Text 'Save autounattend.xml as...'
    $tip.SetToolTip($btnSaveXml, 'Save the generated answer file, e.g. to use tiny11''s OOBE settings with Rufus or a stock ISO.')

    #================ Tab 6: Extras ================
    $g6a = New-UiControl -Type GroupBox -Parent $tabExtras -X 12 -Y 10 -W 868 -H 230 -Text 'Add to the image'
    $chkNetFx = New-UiControl -Type CheckBox -Parent $g6a -X 14 -Y 26 -W 840 -Text 'Enable .NET Framework 3.5 (old games and tools; cannot be added later to a Core image)'
    $null = New-UiControl -Type Label -Parent $g6a -X 14 -Y 62 -W 120 -Text 'Drivers folder:'
    $tbDrivers = New-UiControl -Type TextBox -Parent $g6a -X 140 -Y 59 -W 480
    $btnDrivers = New-UiControl -Type Button -Parent $g6a -X 626 -Y 58 -W 90 -H 25 -Text 'Browse...'
    $btnDriversClear = New-UiControl -Type Button -Parent $g6a -X 722 -Y 58 -W 60 -H 25 -Text 'Clear'
    $lblDrivers = New-UiControl -Type Label -Parent $g6a -X 140 -Y 86 -W 710 -H 20 -Text 'Every .inf below this folder goes into Windows and into Setup (e.g. Intel RST/VMD so Setup sees the disk).' -Props @{ ForeColor = $muted }
    $null = New-UiControl -Type Label -Parent $g6a -X 14 -Y 118 -W 120 -Text 'Browser:'
    $cbBrowser = New-UiControl -Type ComboBox -Parent $g6a -X 140 -Y 115 -W 160 -Props @{ DropDownStyle = 'DropDownList' }
    foreach ($b in 'None', 'Firefox', 'Chrome') { [void]$cbBrowser.Items.Add($b) }
    $null = New-UiControl -Type Label -Parent $g6a -X 310 -Y 118 -W 540 -Text 'Installed silently at the first sign-in (waits for the network).' -Props @{ ForeColor = $muted }
    $chkPayload = New-UiControl -Type CheckBox -Parent $g6a -X 14 -Y 152 -W 440 -Text 'Run my scripts from payload\packages at the end of Setup'
    $btnPayloadOpen = New-UiControl -Type Button -Parent $g6a -X 460 -Y 150 -W 150 -H 25 -Text 'Open payload folder'
    $lblPayload = New-UiControl -Type Label -Parent $g6a -X 32 -Y 178 -W 820 -H 40 -Props @{ ForeColor = $muted }

    $g6b = New-UiControl -Type GroupBox -Parent $tabExtras -X 12 -Y 248 -W 868 -H 100 -Text 'System profile'
    $chkLowRam = New-UiControl -Type CheckBox -Parent $g6b -X 14 -Y 26 -W 840 -Text 'Low-RAM profile for 1-2 GB PCs: fewer service hosts, no SysMain / search indexing, no animations or background apps'
    $chkDriverUpd = New-UiControl -Type CheckBox -Parent $g6b -X 14 -Y 56 -W 840 -Text 'Do not let Windows Update install or replace device drivers'

    $g6c = New-UiControl -Type GroupBox -Parent $tabExtras -X 12 -Y 356 -W 868 -H 100 -Text 'This PC (the one building the ISO)'
    $chkDefExcl = New-UiControl -Type CheckBox -Parent $g6c -X 14 -Y 26 -W 840 -Text 'Faster build: temporarily exclude the work folders from this PC''s Defender scanning'
    $null = New-UiControl -Type Label -Parent $g6c -X 32 -Y 52 -W 820 -H 40 -Text 'The only option that touches this PC: two folder exclusions are added before the build and removed again when it ends (or fails). Off by default.' -Props @{ ForeColor = $muted }

    #================ Tab 7: Build ================
    $null = New-UiControl -Type Label -Parent $tabBuild -X 14 -Y 8 -W 400 -Text 'Plan' -Props @{ Font = $bold; ForeColor = $accent }
    $tbSummary = New-UiControl -Type TextBox -Parent $tabBuild -X 14 -Y 28 -W 430 -H 150 -Props @{ Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical'; Font = $mono; BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248) }
    $null = New-UiControl -Type Label -Parent $tabBuild -X 454 -Y 8 -W 400 -Text 'Checks' -Props @{ Font = $bold; ForeColor = $accent }
    $lvChecks = New-UiControl -Type ListView -Parent $tabBuild -X 454 -Y 28 -W 426 -H 150 -Props @{ View = 'Details'; HeaderStyle = 'None'; FullRowSelect = $true }
    [void]$lvChecks.Columns.Add('Message', 760)
    $null = New-UiControl -Type Label -Parent $tabBuild -X 14 -Y 186 -W 300 -Text 'Equivalent command line:' -Props @{ ForeColor = $muted }
    $tbCommand = New-UiControl -Type TextBox -Parent $tabBuild -X 14 -Y 206 -W 776 -Props @{ ReadOnly = $true; Font = $mono }
    $btnCopyCmd = New-UiControl -Type Button -Parent $tabBuild -X 796 -Y 205 -W 84 -H 25 -Text 'Copy'
    $progress = New-UiControl -Type ProgressBar -Parent $tabBuild -X 14 -Y 240 -W 866 -H 18 -Props @{ Minimum = 0; Maximum = 100 }
    $lblStage = New-UiControl -Type Label -Parent $tabBuild -X 14 -Y 262 -W 600 -Text 'Ready.' -Props @{ Font = $bold }
    $lblElapsed = New-UiControl -Type Label -Parent $tabBuild -X 620 -Y 262 -W 260 -Props @{ TextAlign = 'TopRight'; ForeColor = $muted }
    $rtbLog = New-UiControl -Type RichTextBox -Parent $tabBuild -X 14 -Y 284 -W 866 -H 200 -Props @{ ReadOnly = $true; Font = $mono; BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28); ForeColor = [System.Drawing.Color]::Gainsboro; WordWrap = $false; DetectUrls = $false }
    $btnCancel = New-UiControl -Type Button -Parent $tabBuild -X 14 -Y 490 -W 130 -H 26 -Text 'Cancel build' -Props @{ Enabled = $false }
    $btnOpenLogs = New-UiControl -Type Button -Parent $tabBuild -X 150 -Y 490 -W 130 -H 26 -Text 'Open logs folder'
    $btnOpenOutput = New-UiControl -Type Button -Parent $tabBuild -X 286 -Y 490 -W 150 -H 26 -Text 'Show the ISO' -Props @{ Enabled = $false }
    $btnCopyLog = New-UiControl -Type Button -Parent $tabBuild -X 442 -Y 490 -W 110 -H 26 -Text 'Copy log'

    $ui.Controls = @{
        Source = $cbSource; Edition = $cbEdition; EditionHint = $lblEditionHint; Standard = $rbStandard; Core = $rbCore
        Output = $tbOutput; Scratch = $cbScratch; ScratchHint = $lblScratchHint; Compress = $cbCompress; CompressHint = $lblCompress
        Fast = $chkFast; NoPrompt = $chkNoPrompt; DryRun = $chkDryRunOpt; Preset = $cbPreset; PresetState = $lblPresetState; PresetDesc = $lblPresetDesc
        KeepApps = $chkKeepApps; Apps = $lvApps; Util = $clbUtil; AppsInfo = $lblAppsInfo; Tweaks = $lvTweaks; TweakDetail = $tbTweakDetail; TweakCount = $lblTweakCount
        LocalAdmin = $rbLocalAdmin; Oobe = $rbOobe; User = $tbUser; Password = $tbPassword; Password2 = $tbPassword2; Locale = $cbLocale; TimeZone = $cbTimeZone
        Computer = $tbComputer; ZeroTouch = $chkZeroTouch; Unattend = $tbUnattend; NetFx = $chkNetFx; Drivers = $tbDrivers; DriversHint = $lblDrivers; Browser = $cbBrowser
        Payload = $chkPayload; PayloadHint = $lblPayload; LowRam = $chkLowRam; DriverUpd = $chkDriverUpd; DefExcl = $chkDefExcl
        Summary = $tbSummary; Checks = $lvChecks; Command = $tbCommand; Progress = $progress; Stage = $lblStage; Elapsed = $lblElapsed; Log = $rtbLog
        Cancel = $btnCancel; OpenOutput = $btnOpenOutput; Build = $btnBuild; DryRunBtn = $btnDryRun; LoadProfile = $btnLoadProfile; SaveProfile = $btnSaveProfile; Reset = $btnReset
    }
    $ui.Zones = $zones

    #==================================================================
    # UI <-> state
    #==================================================================
    $syncAppsInfo = {
        $f = $ui.State.Flags
        $lines = @()
        $lines += if ($f.RemoveStore) { 'Microsoft Store: REMOVED (preset flag).' } else { 'Microsoft Store: kept.' }
        $lines += if ($f.RemoveDefender -or $ui.State.Builder -eq 'Core') { 'Windows Security app: REMOVED.' } else { 'Windows Security app: kept.' }
        $lines += if ($f.KeepXbox) { 'Xbox app, Game Bar and Xbox sign-in: KEPT (preset flag).' } else { 'Xbox apps: removed when listed on the left.' }
        $lines += ''
        $lines += 'Always kept: winget (App Installer), Visual C++ / .NET / UI frameworks, media codecs (HEVC, HEIF, AV1, VP9, WebP, RAW...).'
        $lines += ''
        $lines += 'Entries for apps an image does not contain are simply ignored. Removed apps are also deprovisioned, so feature updates do not bring them back.'
        $ui.Controls.AppsInfo.Text = $lines -join "`n"
        # Entries a preset flag overrides are greyed (they stay listed, but are kept).
        $xbox = 'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay'
        foreach ($item in $ui.Controls.Apps.Items) {
            $overridden = $f.KeepXbox -and ($xbox -contains $item.Text)
            $item.ForeColor = if ($overridden) { [System.Drawing.Color]::Gray } else { [System.Drawing.SystemColors]::WindowText }
            $item.ToolTipText = if ($overridden) { 'Kept: "Keep Xbox app, Game Bar and Xbox sign-in" is on (Preset & features tab).' } else { '' }
        }
        $ui.Controls.Apps.ShowItemToolTips = $true
        $ui.Controls.Apps.Enabled = -not $ui.State.KeepApps
        $ui.Controls.Util.Enabled = -not $ui.State.KeepApps
    }

    $syncTweaks = {
        $ui.Loading = $true
        $lv = $ui.Controls.Tweaks
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $rows = @(Get-GuiTweakRows -Flags $ui.State.Flags -Skip $ui.State.SkipTweak -Catalog $ui.Catalog)
        foreach ($r in $rows) {
            $item = New-Object System.Windows.Forms.ListViewItem($r.Id)
            [void]$item.SubItems.Add($(if ($r.When -eq 'Always') { 'always' } elseif ($r.When.StartsWith('!')) { "not $($r.When.TrimStart('!'))" } else { $r.When }))
            [void]$item.SubItems.Add($r.Title)
            $item.Checked = $r.Checked
            $item.Tag = $r.Id
            if (-not $r.Applies) { $item.ForeColor = [System.Drawing.Color]::Gray }
            elseif (-not $r.Checked) { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
            [void]$lv.Items.Add($item)
        }
        $lv.EndUpdate()
        if ($lv.Items.Count -and -not $lv.SelectedItems.Count) { $lv.Items[0].Selected = $true }
        $applied = @($rows | Where-Object Checked).Count
        $ui.Controls.TweakCount.Text = "$applied of $($rows.Count) groups applied" + $(if (@($ui.State.SkipTweak).Count) { "  |  skipped: $(@($ui.State.SkipTweak) -join ', ')" } else { '' })
        $ui.Loading = $false
    }

    $syncFlags = {
        # Flag checkboxes, preset label, Core invariants, dependent views.
        $ui.Loading = $true
        $isCore = $ui.State.Builder -eq 'Core'
        foreach ($name in $ui.FlagBoxes.Keys) {
            $cb = $ui.FlagBoxes[$name]
            $forced = $isCore -and ($Script:CoreForcedFlags -contains $name)
            $cb.Checked = [bool]$ui.State.Flags[$name] -or $forced
            $cb.Enabled = -not $forced
        }
        $ui.State.Flags['DisableWindowsUpdate'] = $isCore
        if ($isCore) { foreach ($n in $Script:CoreForcedFlags) { $ui.State.Flags[$n] = $true } }
        $modified = Test-GuiFlagsModified -Flags $ui.State.Flags -Preset $ui.State.Preset
        $ui.Controls.PresetState.Text = if ($ui.State.Preset -eq 'Custom file') { 'Custom preset file' } elseif ($modified) { "Customised ($($ui.State.Preset))" } else { '' }
        $ui.Controls.PresetDesc.Text = if ($ui.State.Preset -eq 'Custom file') { "Loaded from $($ui.State.PresetFile)" } else { Get-GuiPresetDescription $ui.State.Preset }
        $ui.Controls.LowRam.Checked = [bool]$ui.State.Flags.LowRam
        $ui.Controls.DriverUpd.Checked = [bool]$ui.State.Flags.DisableDriverUpdates
        $ui.Controls.LowRam.Enabled = -not $isCore
        $ui.Controls.DriverUpd.Enabled = -not $isCore
        $ui.Loading = $false
        & $syncTweaks
        & $syncAppsInfo
    }

    $syncApps = {
        $ui.Loading = $true
        $lv = $ui.Controls.Apps
        $lv.BeginUpdate()
        $lv.Items.Clear()
        $lv.Groups.Clear()
        $groups = [ordered]@{}
        $section = 'Other'
        $defaultList = Join-Path $Script:GuiRepoRoot 'removePackage.txt'
        $known = [ordered]@{}
        if (Test-Path -LiteralPath $defaultList) {
            foreach ($line in Get-Content -LiteralPath $defaultList) {
                if ($line -match '^# --- (.+?) -+\s*$') { $section = $Matches[1]; continue }
                $entry = ($line -replace '#.*$', '').Trim()
                if ($entry) { $known[$entry] = $section }
            }
        }
        $all = @($known.Keys) + @($ui.State.RemoveList | Where-Object { $_ -and -not $known.Contains($_) })
        foreach ($entry in $all) {
            $sec = if ($known.Contains($entry)) { $known[$entry] } else { 'Added by you' }
            if (-not $groups.Contains($sec)) { $groups[$sec] = New-Object System.Windows.Forms.ListViewGroup($sec, $sec); [void]$lv.Groups.Add($groups[$sec]) }
            $item = New-Object System.Windows.Forms.ListViewItem($entry, $groups[$sec])
            $item.Checked = @($ui.State.RemoveList) -contains $entry
            [void]$lv.Items.Add($item)
        }
        $lv.EndUpdate()
        for ($i = 0; $i -lt $ui.Controls.Util.Items.Count; $i++) {
            $ui.Controls.Util.SetItemChecked($i, (@($ui.State.Keep) -contains [string]$ui.Controls.Util.Items[$i]))
        }
        $ui.Controls.KeepApps.Checked = [bool]$ui.State.KeepApps
        $ui.Loading = $false
        & $syncAppsInfo
    }

    $syncPayload = {
        $dir = Join-Path $Script:GuiRepoRoot 'payload\packages'
        $scripts = @(Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.cmd', '.ps1' })
        $ui.Controls.PayloadHint.Text = if ($scripts.Count) { "$($scripts.Count) script(s) will run: $(($scripts.Name) -join ', ')" } else { 'payload\packages contains no .cmd / .ps1 yet. Run once as SYSTEM, logged to C:\Windows\Setup\Tiny11\setupcomplete.log.' }
    }

    $syncDrivers = {
        $path = $ui.Controls.Drivers.Text.Trim()
        if ($path -and (Test-Path -LiteralPath $path)) {
            $count = @(Get-ChildItem -LiteralPath $path -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue).Count
            $ui.Controls.DriversHint.Text = "$count driver package(s) (.inf) found."
            $ui.Controls.DriversHint.ForeColor = if ($count) { [System.Drawing.Color]::DarkGreen } else { $danger }
        } elseif ($path) {
            $ui.Controls.DriversHint.Text = 'Folder not found.'
            $ui.Controls.DriversHint.ForeColor = $danger
        } else {
            $ui.Controls.DriversHint.Text = 'Every .inf below this folder goes into Windows and into Setup (e.g. Intel RST/VMD so Setup sees the disk).'
            $ui.Controls.DriversHint.ForeColor = $muted
        }
    }

    $selectCombo = {
        param($combo, $value)
        $index = $combo.Items.IndexOf($value)
        if ($index -ge 0) { $combo.SelectedIndex = $index } elseif ($combo.Items.Count -and $combo.SelectedIndex -lt 0) { $combo.SelectedIndex = 0 }
    }

    $applyState = {
        # State -> every control.
        $ui.Loading = $true
        $s = $ui.State
        $c = $ui.Controls
        $c.Source.Text = [string]$s.Source
        $c.Edition.Items.Clear()
        if ($s.Index) { [void]$c.Edition.Items.Add("$($s.Index): $($s.EditionName)"); $c.Edition.SelectedIndex = 0 }
        $c.Standard.Checked = $s.Builder -ne 'Core'
        $c.Core.Checked = $s.Builder -eq 'Core'
        $c.Output.Text = [string]$s.OutputIso
        $c.Scratch.SelectedIndex = 0
        if ($s.Scratch) {
            for ($i = 0; $i -lt $ui.Drives.Count; $i++) { if ($ui.Drives[$i].Letter -eq ([string]$s.Scratch).Substring(0, 1)) { $c.Scratch.SelectedIndex = $i + 1 } }
        }
        & $selectCombo $c.Compress ([string]$s.Compress)
        $c.CompressHint.Text = Get-GuiCompressionDescription $s.Compress
        $c.Fast.Checked = [bool]$s.Fast
        $c.NoPrompt.Checked = [bool]$s.NoPrompt
        $c.DryRun.Checked = [bool]$s.DryRun
        & $selectCombo $c.Preset ([string]$s.Preset)
        $c.LocalAdmin.Checked = -not $s.InteractiveOobe
        $c.Oobe.Checked = [bool]$s.InteractiveOobe
        $c.User.Text = [string]$s.User
        $c.Password.Text = [string]$s.Password
        $c.Password2.Text = [string]$s.PasswordConfirm
        foreach ($ctl in $c.User, $c.Password, $c.Password2) { $ctl.Enabled = -not $s.InteractiveOobe }
        $c.Locale.SelectedIndex = 0
        if ($s.Locale) {
            $match = @($c.Locale.Items | Where-Object { $_ -like "$($s.Locale)  -*" } | Select-Object -First 1)
            if ($match) { $c.Locale.SelectedItem = $match[0] } else { $c.Locale.Text = $s.Locale }
        }
        $zoneIds = @($ui.Zones | ForEach-Object { $_.Id })
        $zoneIndex = [array]::IndexOf($zoneIds, [string]$s.TimeZone)
        $c.TimeZone.SelectedIndex = if ($zoneIndex -ge 0) { $zoneIndex } else { [Math]::Max(0, [array]::IndexOf($zoneIds, 'UTC')) }
        $c.Computer.Text = [string]$s.ComputerName
        $c.ZeroTouch.Checked = [bool]$s.ZeroTouch
        $c.Unattend.Text = [string]$s.UnattendFile
        $c.NetFx.Checked = [bool]$s.EnableNetFx3
        $c.Drivers.Text = [string]$s.DriverPath
        & $selectCombo $c.Browser ([string]$s.Browser)
        $c.Payload.Checked = [bool]$s.Payload
        $c.DefExcl.Checked = [bool]$s.DefenderExclusion
        $ui.Loading = $false
        & $syncFlags
        & $syncApps
        & $syncPayload
        & $syncDrivers
    }

    $readState = {
        # Controls that are not kept in sync by events -> state.
        $s = $ui.State
        $c = $ui.Controls
        $s.Source = $c.Source.Text.Trim().Trim('"')
        $s.OutputIso = $c.Output.Text.Trim().Trim('"')
        $s.User = $c.User.Text.Trim()
        $s.Password = $c.Password.Text
        $s.PasswordConfirm = $c.Password2.Text
        $s.ComputerName = $c.Computer.Text.Trim()
        $localeText = [string]$c.Locale.Text
        $s.Locale = if ($c.Locale.SelectedIndex -eq 0 -or $localeText -like '(ask*' -or -not $localeText.Trim()) { '' } else { ($localeText -split '\s+-\s+', 2)[0].Trim() }
        if ($c.TimeZone.SelectedIndex -ge 0) { $s.TimeZone = $ui.Zones[$c.TimeZone.SelectedIndex].Id }
        $s.UnattendFile = $c.Unattend.Text.Trim().Trim('"')
        $s.DriverPath = $c.Drivers.Text.Trim().Trim('"')
        $s.Scratch = if ($c.Scratch.SelectedIndex -gt 0) { $ui.Drives[$c.Scratch.SelectedIndex - 1].Letter } else { '' }
        $scratchLetter = if ($s.Scratch) { $s.Scratch } else { $Script:GuiRepoRoot.Substring(0, 1) }
        $drive = @($ui.Drives | Where-Object { $_.Letter -eq $scratchLetter })
        $s['ScratchFreeBytes'] = if ($drive) { $drive[0].FreeBytes } else { [long]0 }
        $s.Keep = @(); $s.Remove = @()
        for ($i = 0; $i -lt $c.Util.Items.Count; $i++) {
            if ($c.Util.GetItemChecked($i)) { $s.Keep += [string]$c.Util.Items[$i] } else { $s.Remove += [string]$c.Util.Items[$i] }
        }
        $s.RemoveList = @($c.Apps.Items | Where-Object { $_.Checked } | ForEach-Object { $_.Text })
        return $s
    }

    $refreshBuildTab = {
        $s = & $readState
        $req = ConvertTo-GuiBuildRequest -State $s
        $ui.Controls.Command.Text = "powershell -ExecutionPolicy Bypass -File $($req.CommandLine.Substring(2))"
        $checks = @(Test-GuiBuildRequest -State $s)
        $lv = $ui.Controls.Checks
        $lv.Items.Clear()
        foreach ($chk in $checks) {
            $prefix = switch ($chk.Level) { 'Error' { '[X] ' } 'Warning' { '[!] ' } default { '[i] ' } }
            $item = New-Object System.Windows.Forms.ListViewItem($prefix + $chk.Message)
            $item.ForeColor = switch ($chk.Level) { 'Error' { $danger } 'Warning' { [System.Drawing.Color]::DarkOrange } default { $muted } }
            [void]$lv.Items.Add($item)
        }
        if (-not $checks.Count) { [void]$lv.Items.Add('[OK] Everything looks good.') }
        $flagsOn = @(Get-GuiFlagInfo | Where-Object { $s.Flags[$_.Name] } | ForEach-Object { $_.Label })
        $tweaksOn = @(Get-GuiTweakRows -Flags $s.Flags -Skip $s.SkipTweak -Catalog $ui.Catalog | Where-Object Checked).Count
        $kept = if ($s.KeepApps) { 'all apps kept' } else { "$(@($s.RemoveList).Count) app prefixes removed; keeping $(@($s.Keep) -join ', ')" }
        $extras = @()
        if ($s.EnableNetFx3) { $extras += '.NET 3.5' }
        if ($s.DriverPath) { $extras += 'drivers' }
        if ($s.Browser -ne 'None') { $extras += $s.Browser }
        if ($s.Payload) { $extras += 'payload' }
        if ($s.Flags.LowRam) { $extras += 'low-RAM' }
        if ($s.Flags.DisableDriverUpdates) { $extras += 'no WU drivers' }
        $summary = @(
            "Builder : $($s.Builder)$(if ($s.DryRun) { ' (DRY RUN)' })"
            "Source  : $(if ($s.Source) { $s.Source } else { '-' })"
            "Edition : $(if ($s.Index) { "$($s.Index): $($s.EditionName)" } else { '-' })"
            "Preset  : $($s.Preset)$(if (Test-GuiFlagsModified -Flags $s.Flags -Preset $s.Preset) { ' (customised)' })"
            "Apps    : $kept"
            "Tweaks  : $tweaksOn groups"
            "Account : $(if ($s.InteractiveOobe) { 'created during OOBE' } else { "$($s.User)$(if ($s.Password) { ' (password set)' } else { ' (no password)' })" })"
            "Region  : $(if ($s.Locale) { $s.Locale } else { 'asked in OOBE' }), $($s.TimeZone)"
            "Install : $(if ($s.ZeroTouch) { 'ZERO-TOUCH (wipes disk 0)' } else { 'normal Setup' })$(if ($s.NoPrompt -or $s.ZeroTouch) { ', no key press' })"
            "Extras  : $(if ($extras.Count) { $extras -join ', ' } else { 'none' })"
            "Output  : $($s.OutputIso) [$($s.Compress)$(if ($s.Fast) { ', quick' })]"
            ''
            'Enabled features:'
        ) + @($flagsOn | ForEach-Object { "  - $_" })
        $ui.Controls.Summary.Text = $summary -join "`r`n"
        return $checks
    }

    $appendLog = {
        param([string]$line)
        $rtb = $ui.Controls.Log
        $color = switch (Get-GuiLineKind $line) {
            'error'   { [System.Drawing.Color]::FromArgb(255, 110, 110) }
            'warning' { [System.Drawing.Color]::FromArgb(255, 200, 90) }
            'section' { [System.Drawing.Color]::FromArgb(110, 190, 255) }
            'success' { [System.Drawing.Color]::FromArgb(120, 220, 130) }
            default   { [System.Drawing.Color]::Gainsboro }
        }
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $rtb.SelectionColor = $color
        $rtb.AppendText($line + "`n")
    }

    $setBusy = {
        param([bool]$busy)
        foreach ($t in $ui.Tabs.TabPages) { if ($t -ne $tabBuild) { foreach ($ctl in $t.Controls) { $ctl.Enabled = -not $busy } } }
        foreach ($ctl in $ui.Controls.Build, $ui.Controls.DryRunBtn, $ui.Controls.LoadProfile, $ui.Controls.SaveProfile, $ui.Controls.Reset) { $ctl.Enabled = -not $busy }
        $ui.Controls.Cancel.Enabled = $busy
        if (-not $busy) { & $syncFlags }
    }

    $finishBuild = {
        param([int]$code)
        $ui.Timer.Stop()
        $ui.Process = $null
        $ui.LastExit = $code
        & $setBusy $false
        $iso = $ui.State.OutputIso
        if ($code -eq 0 -and -not $ui.CurrentDryRun -and (Test-Path -LiteralPath $iso)) {
            $ui.Controls.Progress.Value = 100
            $ui.Controls.Stage.Text = 'Finished - the ISO is ready.'
            $ui.Controls.Stage.ForeColor = [System.Drawing.Color]::DarkGreen
            $ui.Controls.OpenOutput.Enabled = $true
            if (-not $ui.Quiet -and (Invoke-PopupYesOrNo -Title 'Tiny11 ISO ready' -Message "Created:`n$iso`n`nShow it in Explorer?")) {
                Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$iso`""
            }
        } elseif ($code -eq 0) {
            $ui.Controls.Progress.Value = 100
            $ui.Controls.Stage.Text = 'Dry run finished - see the plan in the log.'
            $ui.Controls.Stage.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            $ui.Controls.Stage.Text = "Build failed (exit code $code) - see the log."
            $ui.Controls.Stage.ForeColor = $danger
        }
        if ($ui.AutoRun) { $ui.Form.BeginInvoke([Action] { $ui.Form.Close() }) | Out-Null }
    }

    $startBuild = {
        param([bool]$dryRun)
        $checks = & $refreshBuildTab
        $ui.Tabs.SelectedTab = $tabBuild
        $errors = @($checks | Where-Object Level -eq 'Error')
        if ($errors.Count) {
            if (-not $ui.Quiet) { Invoke-PopupError -Title 'Cannot start yet' -Message (($errors | ForEach-Object { "- $($_.Message)" }) -join "`n") }
            if ($ui.AutoRun) { $ui.LastExit = -1; $ui.Form.BeginInvoke([Action] { $ui.Form.Close() }) | Out-Null }
            return
        }
        if ($ui.State.ZeroTouch -and -not $dryRun -and -not $ui.Quiet) {
            if (-not (Invoke-PopupYesOrNo -Title 'Zero-touch ISO' -Message "This ISO will ERASE DISK 0 without asking on whatever machine boots it.`n`nBuild it anyway?")) { return }
        }
        $state = $ui.State
        $savedDryRun = [bool]$state.DryRun
        $state.DryRun = $dryRun -or $savedDryRun
        $req = ConvertTo-GuiBuildRequest -State $state
        $state.DryRun = $savedDryRun
        foreach ($file in $req.Files.Keys) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            [IO.File]::WriteAllText($file, $req.Files[$file], (New-Object System.Text.UTF8Encoding $false))
        }
        if ($SettingsPath) { try { Export-GuiSettings -State $state -Path $SettingsPath } catch { Write-Verbose "Settings not saved: $($_.Exception.Message)" } }
        $ui.CurrentDryRun = [bool]$req.Arguments.DryRun
        $ui.BuildScratch = if ($state.Scratch) { "$($state.Scratch):" } else { $Script:GuiRepoRoot.Substring(0, 2) }
        $scriptPath = if ($ui.BuilderOverride) { $ui.BuilderOverride } else { $req.ScriptPath }
        $logPath = Join-Path $Script:GuiRepoRoot ("logs\gui\gui-build-{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
        $ui.Controls.Log.Clear()
        & $appendLog "> $($req.CommandLine)"
        $ui.Controls.Progress.Value = 0
        $ui.Controls.Stage.Text = 'Starting...'
        $ui.Controls.Stage.ForeColor = [System.Drawing.Color]::Black
        $ui.Controls.OpenOutput.Enabled = $false
        & $setBusy $true
        try {
            $ui.Process = Start-GuiBuild -ScriptPath $scriptPath -Arguments $req.Arguments -LogPath $logPath
        } catch {
            & $setBusy $false
            Invoke-PopupError -Title 'Could not start the builder' -Message $_.Exception.Message
            return
        }
        $ui.Reader = @{ Path = $logPath; Position = 0; Partial = '' }
        $ui.BuildStart = Get-Date
        $ui.Timer.Start()
    }

    #==================================================================
    # Events
    #==================================================================
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 300
    $ui.Timer = $timer
    $timer.Add_Tick({
            $lines = @(Read-GuiLogTail -Reader $ui.Reader)
            $exitCode = $null
            foreach ($line in $lines) {
                if ($line -match '^__TINY11_EXIT__ (-?\d+)') { $exitCode = [int]$Matches[1]; continue }
                & $appendLog $line
                $stage = Get-GuiBuildStage $line
                if ($stage -and $stage.Percent -ge $ui.Controls.Progress.Value) {
                    $ui.Controls.Progress.Value = [Math]::Max(0, [Math]::Min(100, [int]$stage.Percent))
                    $ui.Controls.Stage.Text = "$($stage.Label)..."
                }
            }
            if ($lines.Count) { $ui.Controls.Log.ScrollToCaret() }
            if ($ui.BuildStart) { $ui.Controls.Elapsed.Text = 'Elapsed ' + (Format-Elapsed ((Get-Date) - $ui.BuildStart)) }
            if ($null -ne $exitCode) {
                & $finishBuild $exitCode
            } elseif ($ui.Process -and $ui.Process.HasExited) {
                Start-Sleep -Milliseconds 300
                $code = $ui.Process.ExitCode
                foreach ($line in @(Read-GuiLogTail -Reader $ui.Reader)) {
                    if ($line -match '^__TINY11_EXIT__ (-?\d+)') { $code = [int]$Matches[1] } else { & $appendLog $line }
                }
                & $finishBuild $code
            }
        })

    $btnBrowseIso.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Windows ISO (*.iso)|*.iso|All files (*.*)|*.*'
            $dlg.Title = 'Select a Windows 11 ISO'
            if ($dlg.ShowDialog() -eq 'OK') { $ui.Controls.Source.Text = $dlg.FileName; $ui.State.Source = $dlg.FileName }
        })
    $btnLoadEditions.Add_Click({
            $src = $ui.Controls.Source.Text.Trim().Trim('"')
            if (-not $src) { Invoke-PopupError -Title 'No source' -Message 'Choose an ISO file or a drive first.'; return }
            $ui.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            $ui.Controls.EditionHint.Text = 'Reading editions...'
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $ui.Editions = @(Get-SourceEditions -Source $src)
                $ui.Controls.Edition.Items.Clear()
                foreach ($e in $ui.Editions) { [void]$ui.Controls.Edition.Items.Add((Format-GuiEdition $e)) }
                $pick = [array]::IndexOf(@($ui.Editions | ForEach-Object { $_.Name }), 'Windows 11 Pro')
                $ui.Controls.Edition.SelectedIndex = if ($pick -ge 0) { $pick } else { 0 }
                $ui.Controls.EditionHint.Text = "$($ui.Editions.Count) edition(s) found. The build exports only the one you pick."
            } catch {
                $ui.Controls.EditionHint.Text = "Could not read editions: $($_.Exception.Message)"
                Invoke-PopupError -Title 'Cannot read editions' -Message $_.Exception.Message
            } finally {
                $ui.Form.Cursor = [System.Windows.Forms.Cursors]::Default
            }
        })
    $cbEdition.Add_SelectedIndexChanged({
            if ($ui.Loading -or -not $ui.Editions.Count) { return }
            $e = $ui.Editions[$ui.Controls.Edition.SelectedIndex]
            $ui.State.Index = [int]$e.Index
            $ui.State.EditionName = $e.Name
            $ui.State.EditionSizeBytes = [long]$e.SizeBytes
            $need = Get-RequiredScratchBytes ([long]$e.SizeBytes)
            $ui.Controls.ScratchHint.Text = ('NTFS, ~{0:N0} GB free needed for this edition.' -f ($need / 1GB))
            if ($e.Architecture -eq 'arm64') { $ui.Controls.EditionHint.Text = 'ARM64 image: the ISO will be UEFI-only.' }
        })
    $rbStandard.Add_CheckedChanged({
            if ($ui.Loading -or -not $rbStandard.Checked) { return }
            $ui.State.Builder = 'Standard'
            $out = $ui.Controls.Output.Text
            if ($out -match 'tiny11core\.iso$') { $ui.Controls.Output.Text = $out -replace 'tiny11core\.iso$', 'tiny11.iso' }
            & $syncFlags
        })
    $rbCore.Add_CheckedChanged({
            if ($ui.Loading -or -not $rbCore.Checked) { return }
            $ui.State.Builder = 'Core'
            if ($ui.State.Preset -eq 'Default' -and -not (Test-GuiFlagsModified -Flags $ui.State.Flags -Preset 'Default')) {
                $ui.State.Preset = 'Minimal-VM'
                $keepRuntime = @{ LowRam = $ui.State.Flags.LowRam; DisableDriverUpdates = $ui.State.Flags.DisableDriverUpdates }
                $ui.State.Flags = Resolve-BuildPreset 'Minimal-VM'
                foreach ($k in $keepRuntime.Keys) { $ui.State.Flags[$k] = [bool]$keepRuntime[$k] }
                $ui.Loading = $true; & $selectCombo $ui.Controls.Preset 'Minimal-VM'; $ui.Loading = $false
            }
            $out = $ui.Controls.Output.Text
            if ($out -match 'tiny11\.iso$') { $ui.Controls.Output.Text = $out -replace 'tiny11\.iso$', 'tiny11core.iso' }
            & $syncFlags
        })
    $btnSaveAs.Add_Click({
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'ISO image (*.iso)|*.iso'
            $dlg.FileName = Split-Path $ui.Controls.Output.Text -Leaf
            if ($dlg.ShowDialog() -eq 'OK') { $ui.Controls.Output.Text = $dlg.FileName }
        })
    $cbCompress.Add_SelectedIndexChanged({
            if ($ui.Loading) { return }
            $ui.State.Compress = [string]$ui.Controls.Compress.SelectedItem
            $ui.Controls.CompressHint.Text = Get-GuiCompressionDescription $ui.State.Compress
        })
    $chkFast.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.Fast = $chkFast.Checked } })
    $chkNoPrompt.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.NoPrompt = $chkNoPrompt.Checked } })
    $chkDryRunOpt.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.DryRun = $chkDryRunOpt.Checked } })

    # Preset tab
    $cbPreset.Add_SelectedIndexChanged({
            if ($ui.Loading) { return }
            $name = [string]$ui.Controls.Preset.SelectedItem
            if ($name -eq 'Custom file') {
                if (-not $ui.State.PresetFile) { $btnPresetLoad.PerformClick() }
                return
            }
            $ui.State.Preset = $name
            $ui.State.PresetFile = ''
            $runtime = @{ LowRam = $ui.State.Flags.LowRam; DisableDriverUpdates = $ui.State.Flags.DisableDriverUpdates }
            $ui.State.Flags = Resolve-BuildPreset $name
            foreach ($k in $runtime.Keys) { $ui.State.Flags[$k] = [bool]$runtime[$k] }
            $ui.State.SkipTweak = @()
            & $syncFlags
        })
    foreach ($name in @($ui.FlagBoxes.Keys)) {
        $ui.FlagBoxes[$name].Add_CheckedChanged({
                if ($ui.Loading) { return }
                $ui.State.Flags[$this.Tag] = $this.Checked
                & $syncFlags
            })
    }
    $btnPresetReset.Add_Click({
            $name = if ($ui.State.Preset -eq 'Custom file') { 'Default' } else { $ui.State.Preset }
            $runtime = @{ LowRam = $ui.State.Flags.LowRam; DisableDriverUpdates = $ui.State.Flags.DisableDriverUpdates }
            $ui.State.Preset = $name
            $ui.State.PresetFile = ''
            $ui.State.Flags = Resolve-BuildPreset $name
            foreach ($k in $runtime.Keys) { $ui.State.Flags[$k] = [bool]$runtime[$k] }
            $ui.State.SkipTweak = @()
            $ui.Loading = $true; & $selectCombo $ui.Controls.Preset $name; $ui.Loading = $false
            & $syncFlags
        })
    $btnPresetLoad.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Preset (*.json)|*.json'
            $dlg.InitialDirectory = Join-Path $Script:GuiRepoRoot 'presets'
            if ($dlg.ShowDialog() -ne 'OK') {
                $ui.Loading = $true; & $selectCombo $ui.Controls.Preset $ui.State.Preset; $ui.Loading = $false
                return
            }
            try {
                $runtime = @{ LowRam = $ui.State.Flags.LowRam; DisableDriverUpdates = $ui.State.Flags.DisableDriverUpdates }
                $ui.State.Flags = Resolve-BuildPreset $dlg.FileName
                foreach ($k in $runtime.Keys) { $ui.State.Flags[$k] = [bool]$runtime[$k] }
                $ui.State.Preset = 'Custom file'
                $ui.State.PresetFile = $dlg.FileName
                $ui.Loading = $true; & $selectCombo $ui.Controls.Preset 'Custom file'; $ui.Loading = $false
                & $syncFlags
            } catch {
                Invoke-PopupError -Title 'Invalid preset' -Message $_.Exception.Message
            }
        })
    $btnPresetSave.Add_Click({
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Preset (*.json)|*.json'
            $dlg.InitialDirectory = Join-Path $Script:GuiRepoRoot 'presets'
            $dlg.FileName = 'my-preset.json'
            if ($dlg.ShowDialog() -eq 'OK') {
                $json = ConvertTo-PresetJson -Flags $ui.State.Flags -Name ([IO.Path]::GetFileNameWithoutExtension($dlg.FileName)) -Description 'Saved from the Tiny11 GUI'
                [IO.File]::WriteAllText($dlg.FileName, $json, (New-Object System.Text.UTF8Encoding $false))
                Invoke-PopupInfo -Title 'Preset saved' -Message "Use it with -Preset `"$($dlg.FileName)`" or load it here later."
            }
        })

    # Apps tab
    $chkKeepApps.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.KeepApps = $chkKeepApps.Checked; & $syncAppsInfo } })
    $setAllApps = { param([bool]$value) foreach ($item in $ui.Controls.Apps.Items) { $item.Checked = $value } }
    $btnAppsAll.Add_Click({ & $setAllApps $true })
    $btnAppsNone.Add_Click({ & $setAllApps $false })
    $btnAppsDefault.Add_Click({
            $ui.State.RemoveList = @(Read-PackageListFile (Join-Path $Script:GuiRepoRoot 'removePackage.txt'))
            $utils = Get-OptionalUtilities
            $ui.State.Keep = @($utils | Where-Object Default -eq 'Keep' | ForEach-Object { $_.Name })
            $ui.State.Remove = @($utils | Where-Object Default -eq 'Remove' | ForEach-Object { $_.Name })
            $ui.State.KeepApps = $false
            & $syncApps
        })
    $btnAddApp.Add_Click({
            $entry = $tbAddApp.Text.Trim()
            if (-not $entry) { return }
            if ($entry -notmatch '^[A-Za-z0-9_.*-]+$') { Invoke-PopupError -Title 'Invalid prefix' -Message 'Use a package name prefix such as Vendor.AppName (letters, digits, . _ - and *).'; return }
            $s = & $readState
            if (@($s.RemoveList) -notcontains $entry) { $s.RemoveList = @($s.RemoveList) + $entry }
            $tbAddApp.Text = ''
            & $syncApps
        })
    $btnAppsImport.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Package list (*.txt)|*.txt|All files (*.*)|*.*'
            if ($dlg.ShowDialog() -eq 'OK') {
                $ui.State.RemoveList = @(Read-PackageListFile $dlg.FileName)
                & $syncApps
            }
        })
    $btnAppsExport.Add_Click({
            $s = & $readState
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Package list (*.txt)|*.txt'
            $dlg.FileName = 'my-packages.txt'
            if ($dlg.ShowDialog() -eq 'OK') {
                [IO.File]::WriteAllText($dlg.FileName, ("# Tiny11 package list`r`n" + (@($s.RemoveList) -join "`r`n") + "`r`n"))
            }
        })

    # Tweaks tab
    $lvTweaks.Add_ItemChecked({
            param($eventSource, $e)
            if ($ui.Loading) { return }
            $group = $ui.Catalog | Where-Object { $_.Id -eq $e.Item.Tag } | Select-Object -First 1
            # WinForms raises ItemChecked for every item when the handle is created;
            # only react when the box disagrees with the computed state.
            $current = (Test-TweakCondition -When $group.When -Flags $ui.State.Flags) -and (@($ui.State.SkipTweak) -notcontains $group.Id)
            if ($current -eq $e.Item.Checked) { return }
            $result = Set-GuiTweakChoice -Flags $ui.State.Flags -Skip $ui.State.SkipTweak -Group $group -Checked $e.Item.Checked
            $ui.State.Flags = $result.Flags
            $ui.State.SkipTweak = $result.Skip
            # Rebuild after the event returns: changing items inside ItemChecked is not allowed.
            $ui.Form.BeginInvoke([Action] { & $syncFlags }) | Out-Null
        })
    $lvTweaks.Add_SelectedIndexChanged({
            if (-not $lvTweaks.SelectedItems.Count) { return }
            $g = $ui.Catalog | Where-Object { $_.Id -eq $lvTweaks.SelectedItems[0].Tag } | Select-Object -First 1
            $lines = @("[$($g.Id)] $($g.Title)", "When: $($g.When)")
            if ($g.Notes) { $lines += "Note: $($g.Notes)" }
            foreach ($entry in @($g.Set | Where-Object { $_ })) { $t = ConvertFrom-TweakEntry $entry; $lines += "  set    $($t.Path)\$($t.Name) = $($t.Value)  ($($t.Type))" }
            foreach ($entry in @($g.Delete | Where-Object { $_ })) { $lines += "  delete $entry" }
            foreach ($entry in @($g.Services | Where-Object { $_ })) { $lines += "  service $entry" }
            foreach ($entry in @($g.FirstBoot | Where-Object { $_ })) { $lines += "  first boot: $entry" }
            $tbTweakDetail.Text = $lines -join "`r`n"
        })
    $btnTweaksAll.Add_Click({ $ui.State.SkipTweak = @(); & $syncTweaks })

    # Setup tab
    $rbOobe.Add_CheckedChanged({
            if ($ui.Loading) { return }
            $ui.State.InteractiveOobe = $rbOobe.Checked
            foreach ($ctl in $tbUser, $tbPassword, $tbPassword2) { $ctl.Enabled = -not $rbOobe.Checked }
        })
    $chkShowPw.Add_CheckedChanged({ $tbPassword.UseSystemPasswordChar = -not $chkShowPw.Checked; $tbPassword2.UseSystemPasswordChar = -not $chkShowPw.Checked })
    $btnTzHere.Add_Click({ $ui.Controls.TimeZone.SelectedIndex = [array]::IndexOf(@($ui.Zones | ForEach-Object { $_.Id }), [System.TimeZoneInfo]::Local.Id) })
    $chkZeroTouch.Add_CheckedChanged({
            if ($ui.Loading) { return }
            if ($chkZeroTouch.Checked) {
                if (-not (Invoke-PopupYesOrNo -Title 'Zero-touch install' -Message "The ISO will ERASE DISK 0 without asking as soon as it boots.`n`nOnly for virtual machines or dedicated test PCs. Enable?")) {
                    $ui.Loading = $true; $chkZeroTouch.Checked = $false; $ui.Loading = $false
                    return
                }
                $chkNoPrompt.Checked = $true
            }
            $ui.State.ZeroTouch = $chkZeroTouch.Checked
        })
    $btnUnattendBrowse.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Answer file (*.xml)|*.xml'
            if ($dlg.ShowDialog() -eq 'OK') { $tbUnattend.Text = $dlg.FileName }
        })
    $btnUnattendClear.Add_Click({ $tbUnattend.Text = '' })
    $makeXml = {
        $s = & $readState
        if ($s.UnattendFile) { return Set-UnattendImageIndex -Xml (Get-Content -Raw -LiteralPath $s.UnattendFile) -ImageIndex 1 }
        $arch = if ($ui.Editions.Count -and $ui.Controls.Edition.SelectedIndex -ge 0) { $ui.Editions[$ui.Controls.Edition.SelectedIndex].Architecture } else { 'amd64' }
        return New-UnattendXml -Architecture $arch -UserName $s.User -Password $s.Password -TimeZone $s.TimeZone -Locale $s.Locale `
            -ComputerName $s.ComputerName -ZeroTouch:([bool]$s.ZeroTouch) -InteractiveOobe:([bool]$s.InteractiveOobe)
    }
    $btnPreviewXml.Add_Click({
            try { $xml = & $makeXml } catch { Invoke-PopupError -Title 'Answer file' -Message $_.Exception.Message; return }
            $dlg = New-Object System.Windows.Forms.Form
            $dlg.Text = 'autounattend.xml preview'
            $dlg.Size = New-Object System.Drawing.Size(900, 650)
            $dlg.StartPosition = 'CenterParent'
            $box = New-Object System.Windows.Forms.TextBox
            $box.Multiline = $true; $box.ReadOnly = $true; $box.ScrollBars = 'Both'; $box.WordWrap = $false; $box.Dock = 'Fill'; $box.Font = $mono
            $box.Text = $xml -replace "(?<!`r)`n", "`r`n"
            $dlg.Controls.Add($box)
            [void]$dlg.ShowDialog($ui.Form)
        })
    $btnSaveXml.Add_Click({
            try { $xml = & $makeXml } catch { Invoke-PopupError -Title 'Answer file' -Message $_.Exception.Message; return }
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Answer file (*.xml)|*.xml'
            $dlg.FileName = 'autounattend.xml'
            if ($dlg.ShowDialog() -eq 'OK') { Write-UnattendFile -Xml $xml -Path $dlg.FileName }
        })

    # Extras tab
    $chkNetFx.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.EnableNetFx3 = $chkNetFx.Checked } })
    $btnDrivers.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Folder containing .inf driver packages'
            if ($dlg.ShowDialog() -eq 'OK') { $tbDrivers.Text = $dlg.SelectedPath }
        })
    $btnDriversClear.Add_Click({ $tbDrivers.Text = '' })
    $tbDrivers.Add_TextChanged({ if (-not $ui.Loading) { & $syncDrivers } })
    $cbBrowser.Add_SelectedIndexChanged({ if (-not $ui.Loading) { $ui.State.Browser = [string]$cbBrowser.SelectedItem } })
    $chkPayload.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.Payload = $chkPayload.Checked; & $syncPayload } })
    $btnPayloadOpen.Add_Click({
            $dir = Join-Path $Script:GuiRepoRoot 'payload\packages'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$dir`""
        })
    $chkLowRam.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.Flags['LowRam'] = $chkLowRam.Checked; & $syncTweaks } })
    $chkDriverUpd.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.Flags['DisableDriverUpdates'] = $chkDriverUpd.Checked; & $syncTweaks } })
    $chkDefExcl.Add_CheckedChanged({ if (-not $ui.Loading) { $ui.State.DefenderExclusion = $chkDefExcl.Checked } })

    # Build tab & bottom bar
    $tabs.Add_SelectedIndexChanged({ if ($ui.Tabs.SelectedTab -eq $tabBuild -and -not $ui.Process) { $null = & $refreshBuildTab } elseif ($ui.Tabs.SelectedTab -eq $tabExtras) { & $syncPayload } })
    $btnCopyCmd.Add_Click({ if ($tbCommand.Text) { [System.Windows.Forms.Clipboard]::SetText($tbCommand.Text) } })
    $btnCopyLog.Add_Click({ if ($rtbLog.Text) { [System.Windows.Forms.Clipboard]::SetText($rtbLog.Text) } })
    $btnOpenLogs.Add_Click({
            $dir = Join-Path $Script:GuiRepoRoot 'logs'
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$dir`""
        })
    $btnOpenOutput.Add_Click({ if (Test-Path -LiteralPath $ui.State.OutputIso) { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$($ui.State.OutputIso)`"" } })
    $btnBuild.Add_Click({ & $startBuild $false })
    $btnDryRun.Add_Click({ & $startBuild $true })
    $btnCancel.Add_Click({
            if (-not $ui.Process) { return }
            if (-not (Invoke-PopupYesOrNo -Title 'Cancel the build?' -Message 'The builder is stopped and the mounted image is discarded. Continue?')) { return }
            $ui.Timer.Stop()
            & $appendLog 'Cancelling: stopping the builder and cleaning up the work folders...'
            [System.Windows.Forms.Application]::DoEvents()
            $proc = $ui.Process
            $ui.Process = $null
            try { Stop-GuiBuild -Process $proc -ScratchDisk $ui.BuildScratch } catch { & $appendLog "Cleanup warning: $($_.Exception.Message)" }
            foreach ($line in @(Read-GuiLogTail -Reader $ui.Reader)) { if ($line -notmatch '^__TINY11_EXIT__') { & $appendLog $line } }
            & $appendLog 'Build cancelled.'
            & $setBusy $false
            $ui.Controls.Stage.Text = 'Cancelled.'
            $ui.Controls.Stage.ForeColor = $danger
        })
    $btnSaveProfile.Add_Click({
            $s = & $readState
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = 'Tiny11 GUI profile (*.json)|*.json'
            $dlg.FileName = 'tiny11-profile.json'
            if ($dlg.ShowDialog() -eq 'OK') { Export-GuiSettings -State $s -Path $dlg.FileName }
        })
    $btnLoadProfile.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = 'Tiny11 GUI profile (*.json)|*.json'
            if ($dlg.ShowDialog() -eq 'OK') {
                try { $ui.State = Import-GuiSettings -Path $dlg.FileName; $ui.Editions = @(); & $applyState }
                catch { Invoke-PopupError -Title 'Invalid profile' -Message $_.Exception.Message }
            }
        })
    $btnReset.Add_Click({
            if (Invoke-PopupYesOrNo -Title 'Reset' -Message 'Reset every option to its default?') {
                $ui.State = Get-GuiDefaultState
                $ui.Editions = @()
                & $applyState
            }
        })
    $btnClose.Add_Click({ $ui.Form.Close() })
    $form.Add_FormClosing({
            param($eventSource, $e)
            if ($ui.Process -and -not $ui.Process.HasExited) {
                if (-not (Invoke-PopupYesOrNo -Title 'Build running' -Message 'A build is running. Stop it, clean up and close?')) { $e.Cancel = $true; return }
                $ui.Timer.Stop()
                try { Stop-GuiBuild -Process $ui.Process -ScratchDisk $ui.BuildScratch } catch { Write-Verbose $_.Exception.Message }
            }
            if (-not $PreviewPath -and $SettingsPath) {
                try { Export-GuiSettings -State (& $readState) -Path $SettingsPath } catch { Write-Verbose "Settings not saved: $($_.Exception.Message)" }
            }
        })

    & $applyState
    $ui.Loading = $false

    if ($PreviewPath) {
        $tabs.SelectedIndex = [Math]::Min([Math]::Max(0, $PreviewTab), $tabs.TabCount - 1)
        if ($tabs.SelectedTab -eq $tabBuild) { $null = & $refreshBuildTab }
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $form.Close()
        return $null
    }

    if ($AutoRun) {
        $form.Add_Shown({ & $startBuild ($ui.AutoRun -eq 'DryRun') })
    }
    [void]$form.ShowDialog()
    return $ui.LastExit
}

#endregion

Export-ModuleMember -Function Get-GuiFlagInfo, Get-GuiPresetDescription, Get-GuiCompressionDescription, Get-GuiDefaultState,
    Test-GuiFlagsModified, Test-GuiRemoveListModified, Format-GuiCommandLine, ConvertTo-GuiBuildRequest, Test-GuiBuildRequest,
    Get-GuiTweakRows, Set-GuiTweakChoice, Get-GuiBuildStage, Get-GuiLineKind, Export-GuiSettings, Import-GuiSettings,
    Start-GuiBuild, Read-GuiLogTail, Stop-GuiBuild, Invoke-PopupInfo, Invoke-PopupError, Invoke-PopupYesOrNo,
    Get-SetupMediaDrives, Get-NtfsDrives, Get-SourceEditions, Format-GuiEdition, New-UiControl, Show-Tiny11BuilderForm
