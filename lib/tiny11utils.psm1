<#
.SYNOPSIS
    Shared utility module for Tiny11 Builder - Ultimate Edition.

.DESCRIPTION
    Centralizes reusable functions for DISM operations, registry manipulation,
    privilege escalation, safe cleanup, ISO handling, unattended XML generation,
    and build orchestration. Imported by both tiny11maker.ps1 and tiny11Coremaker.ps1.

    Combines hardening from the revamped fork (ACL TaskCache takeover, emergency
    cleanup trap, safe dismount/unload), zPoche v2 (pre-flight validation,
    robocopy, arch-aware autounattend), and YmlyZA (build profiles, dry-run).
#>

#---------[ Module Paths ]---------#
# This module lives in lib/, so $PSScriptRoot points to lib/.
# $repoRoot points to the project root where data files live.
$repoRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }

#---------[ Process / Argument Helpers ]---------#

function Format-ProcessArgument {
    # Quotes one argument for a Windows command line (CommandLineToArgvW rules):
    # empty strings and values with whitespace/quotes are wrapped in quotes,
    # embedded quotes become \" and backslashes that precede a quote are doubled.
    param([AllowEmptyString()][string]$Argument)
    if ($Argument -and $Argument -notmatch '[\s"]') {
        return $Argument
    }
    $escaped = [regex]::Replace($Argument, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $escaped + '"'
}

function Build-ProcessArgumentString {
    param([string[]]$Arguments)
    return ($Arguments | ForEach-Object { Format-ProcessArgument $_ }) -join ' '
}

#---------[ Native Command Runner ]---------#

function Invoke-Native {
    # Runs a native executable, captures stdout+stderr as strings and returns
    # the exit code. Windows PowerShell 5.1 turns *any* redirected stderr line
    # into a terminating error when the caller uses $ErrorActionPreference =
    # 'Stop' (both builders do), so every "quiet" native call must go through
    # here instead of `& tool 2>$null`.
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$PassThru
    )
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    if ($PassThru) {
        return [pscustomobject]@{ ExitCode = $exitCode; Output = @($output) }
    }
    return $exitCode
}

function Grant-AdminFullControl {
    # takeown + icacls on a file or folder inside the mounted image so it can be
    # deleted. Missing paths are ignored; failures are reported, never thrown.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Recurse
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $adminGroup = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
    $takeArgs = @('/F', $Path, '/A')
    if ($Recurse) { $takeArgs += @('/R', '/D', 'Y') }
    $null = Invoke-Native -FilePath 'takeown.exe' -ArgumentList $takeArgs
    $aclArgs = @($Path, '/grant', "${adminGroup}:(F)", '/C', '/Q')
    if ($Recurse) { $aclArgs += '/T' }
    $rc = Invoke-Native -FilePath 'icacls.exe' -ArgumentList $aclArgs
    if ($rc -ne 0) { Write-Warning "icacls returned $rc for $Path" }
    return ($rc -eq 0)
}

function Remove-ImagePath {
    # Take ownership of, then delete, a file/folder in the mounted image.
    # Returns $true when the path is gone afterwards.
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $isDir = Test-Path -LiteralPath $Path -PathType Container
    $null = Grant-AdminFullControl -Path $Path -Recurse:$isDir
    Remove-Item -LiteralPath $Path -Recurse:$isDir -Force -ErrorAction SilentlyContinue
    return -not (Test-Path -LiteralPath $Path)
}

#---------[ DISM / Command Exit-Code Checking ]---------#

function Assert-CommandExitCode {
    param(
        [string]$Label = 'Command',
        [int[]]$AllowedExitCodes = @(0),
        [int]$ExitCode = $LASTEXITCODE
    )
    if ($AllowedExitCodes -notcontains $ExitCode) {
        throw "$Label failed with exit code $ExitCode"
    }
}

function Invoke-DismChecked {
    param(
        [string]$Label,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$DismArgs
    )
    & dism @DismArgs
    Assert-CommandExitCode -Label $Label
}

#---------[ Registry Management (tracked + safe unload) ]---------#

$Script:LoadedRegHives = [System.Collections.Generic.List[string]]::new()

function Invoke-RegLoad {
    param(
        [string]$HiveName,
        [string]$FilePath
    )
    $result = Invoke-Native -FilePath 'reg.exe' -ArgumentList @('load', "HKLM\$HiveName", $FilePath) -PassThru
    if ($result.ExitCode -ne 0) {
        throw "reg load HKLM\$HiveName from '$FilePath' failed (exit $($result.ExitCode)): $($result.Output -join ' ')"
    }
    if (-not $Script:LoadedRegHives.Contains($HiveName)) {
        $Script:LoadedRegHives.Add($HiveName)
    }
}

function Invoke-RegUnload {
    # Unloads an offline hive. "Access denied" on unload almost always means a
    # .NET RegistryKey handle (or AV scanner) still has the hive open, so we
    # force a GC and retry a few times before giving up. An unload failure
    # leaves the mounted image un-committable, hence the hard throw.
    param(
        [string]$HiveName,
        [int]$Retries = 5
    )
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $rc = Invoke-Native -FilePath 'reg.exe' -ArgumentList @('unload', "HKLM\$HiveName")
        if ($rc -eq 0) { break }
        if (-not (Test-Path "Registry::HKEY_LOCAL_MACHINE\$HiveName")) { $rc = 0; break }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Seconds $attempt
    }
    if ($rc -ne 0) {
        throw "reg unload HKLM\$HiveName failed after $Retries attempts (exit code $rc)."
    }
    [void]$Script:LoadedRegHives.Remove($HiveName)
    Write-Output "Unloaded registry hive: HKLM\$HiveName"
}

function Mount-OfflineHives {
    # Loads the five hives of a mounted Windows image under HKLM\z<NAME>.
    # All offline registry edits in this project go through these names, and
    # Set-RegistryValue refuses anything else so the host registry is never touched.
    param([Parameter(Mandatory = $true)][string]$MountPath)
    Invoke-RegLoad -HiveName 'zCOMPONENTS' -FilePath "$MountPath\Windows\System32\config\COMPONENTS"
    Invoke-RegLoad -HiveName 'zDEFAULT'    -FilePath "$MountPath\Windows\System32\config\default"
    Invoke-RegLoad -HiveName 'zNTUSER'     -FilePath "$MountPath\Users\Default\ntuser.dat"
    Invoke-RegLoad -HiveName 'zSOFTWARE'   -FilePath "$MountPath\Windows\System32\config\SOFTWARE"
    Invoke-RegLoad -HiveName 'zSYSTEM'     -FilePath "$MountPath\Windows\System32\config\SYSTEM"
}

function Dismount-OfflineHives {
    foreach ($hive in @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')) {
        Invoke-RegUnload -HiveName $hive
    }
}

$Script:OfflineHiveNames = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')
$Script:RegistryValueTypes = @('REG_SZ', 'REG_EXPAND_SZ', 'REG_DWORD', 'REG_QWORD', 'REG_MULTI_SZ', 'REG_BINARY')

function Test-OfflineRegistryPath {
    # True when $Path points inside one of the offline hives (HKLM\zSOFTWARE\...).
    # Everything this project writes must live there: a path such as
    # HKLM\SOFTWARE\... would silently modify the *build machine* instead.
    param([string]$Path)
    if (-not $Path) { return $false }
    $normalized = $Path -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\'
    foreach ($hive in $Script:OfflineHiveNames) {
        if ($normalized -like "HKLM\$hive" -or $normalized -like "HKLM\$hive\*") { return $true }
    }
    return $false
}

function Assert-OfflineHiveLoaded {
    # Second safety net: even a valid HKLM\z* path is refused unless that hive
    # really is a loaded offline image hive. Nothing can then be written to (or
    # deleted from) the build machine's own registry, whatever calls this.
    param([Parameter(Mandatory = $true)][string]$Path)
    $hive = (($Path -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM\') -split '\\')[1]
    if (-not (Microsoft.PowerShell.Management\Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$hive")) {
        throw "Refusing to modify '$Path': offline hive HKLM\$hive is not loaded (no image mounted)."
    }
}

function Set-RegistryValue {
    # Writes one value into an offline hive via reg.exe. Throws on failure, and
    # refuses paths outside HKLM\z* (see Test-OfflineRegistryPath) or hives
    # that are not currently loaded from a mounted image.
    param (
        [Parameter(Mandatory = $true)][string]$path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$name,
        [Parameter(Mandatory = $true)][string]$type,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$value
    )
    if (-not (Test-OfflineRegistryPath $path)) {
        throw "Refusing to write '$path': only offline hives (HKLM\zSOFTWARE, zSYSTEM, zNTUSER, zDEFAULT, zCOMPONENTS) may be modified."
    }
    if ($Script:RegistryValueTypes -notcontains $type) {
        throw "Invalid registry value type '$type' for $path\$name."
    }
    Assert-OfflineHiveLoaded -Path $path
    $regArgs = @('add', $path, '/f', '/t', $type, '/d', $value)
    if ($name) { $regArgs += @('/v', $name) } else { $regArgs += '/ve' }
    $rc = Invoke-Native -FilePath 'reg.exe' -ArgumentList $regArgs
    Assert-CommandExitCode -Label "reg add $path\$name" -ExitCode $rc
    Write-Output "Set registry value: $path\$name"
}

function Remove-RegistryValue {
    # Deletes a whole key (or a single value with -Name) from an offline hive.
    # A missing key is not an error: reg.exe returns 1 and we move on.
    param (
        [Parameter(Mandatory = $true)][string]$path,
        [string]$Name
    )
    if (-not (Test-OfflineRegistryPath $path)) {
        throw "Refusing to delete '$path': only offline hives (HKLM\z*) may be modified."
    }
    Assert-OfflineHiveLoaded -Path $path
    $regArgs = @('delete', $path, '/f')
    if ($Name) { $regArgs += @('/v', $Name) }
    $rc = Invoke-Native -FilePath 'reg.exe' -ArgumentList $regArgs
    if ($rc -ne 0 -and $rc -ne 1) {
        throw "reg delete $path failed with exit code $rc"
    }
    if ($rc -eq 0) {
        Write-Output "Removed registry entry: $path$(if ($Name) { "\$Name" })"
    }
}

#---------[ Privilege Escalation (C# P/Invoke) ]---------#

function Enable-Privilege {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Privilege
    )

    if (-not ('AdvPrivilege' -as [type])) {
        $source = @"
using System;
using System.Runtime.InteropServices;

public static class AdvPrivilege
{
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TokPriv1Luid
    {
        public int Count;
        public long Luid;
        public int Attr;
    }

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    internal static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", ExactSpelling = true)]
    internal static extern bool CloseHandle(IntPtr h);

    internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
    internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
    internal const int TOKEN_QUERY = 0x00000008;
    internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

    public static bool EnablePrivilege(string privilege)
    {
        IntPtr htok = IntPtr.Zero;
        TokPriv1Luid tp;
        long luid = 0;

        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok))
        {
            return false;
        }

        if (!LookupPrivilegeValue(null, privilege, ref luid))
        {
            CloseHandle(htok);
            return false;
        }

        tp.Count = 1;
        tp.Luid = luid;
        tp.Attr = SE_PRIVILEGE_ENABLED;

        bool retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(htok);
        return retVal;
    }
}
"@

        Add-Type -TypeDefinition $source -ErrorAction Stop | Out-Null
    }

    [AdvPrivilege]::EnablePrivilege($Privilege) | Out-Null
}

function Enable-TaskCacheWriteAccess {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Principal.NTAccount]$AdminGroup,
        [string]$OfflineTaskKey = 'zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks'
    )

    try {
        Enable-Privilege -Privilege 'SeTakeOwnershipPrivilege'
        Enable-Privilege -Privilege 'SeBackupPrivilege'
        Enable-Privilege -Privilege 'SeRestorePrivilege'
    } catch {
        Write-Warning "Could not enable all required privileges for TaskCache ACL handling: $_"
    }

    try {
        $ownershipKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $OfflineTaskKey,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership
        )

        if (-not $ownershipKey) {
            Write-Warning "TaskCache key not found for ownership update: $OfflineTaskKey"
            return $false
        }

        $ownershipAcl = $ownershipKey.GetAccessControl()
        $ownershipAcl.SetOwner($AdminGroup)
        $ownershipKey.SetAccessControl($ownershipAcl)
        $ownershipKey.Close()

        $permissionKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $OfflineTaskKey,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions
        )

        if (-not $permissionKey) {
            Write-Warning "TaskCache key not found for permission update: $OfflineTaskKey"
            return $false
        }

        $permissionAcl = $permissionKey.GetAccessControl()
        $permissionAcl.SetAccessRuleProtection($false, $false)

        $allowRule = New-Object System.Security.AccessControl.RegistryAccessRule(
            $AdminGroup,
            [System.Security.AccessControl.RegistryRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )

        $permissionAcl.SetAccessRule($allowRule)
        $permissionKey.SetAccessControl($permissionAcl)
        $permissionKey.Close()

        return $true
    } catch {
        Write-Warning "Failed to grant TaskCache write access: $_"
        return $false
    }
}

#---------[ Offline Scheduled Task Removal ]---------#
# A scheduled task lives in three places inside an image:
#   1. the XML definition   Windows\System32\Tasks\<path>
#   2. TaskCache\Tree\<path>         (value "Id" = the task GUID)
#   3. TaskCache\Tasks\{GUID} plus Boot/Logon/Plain/Maintenance\{GUID}
# Older builders deleted hard-coded GUIDs, but those GUIDs are generated when
# Microsoft builds each image and differ between releases (the old lists never
# matched a 24H2/25H2 image). We resolve the GUID from the Tree key instead,
# so the same task list works on every build.

function Get-TelemetryScheduledTasks {
    # Task paths removed from every build. A trailing '\' means "the whole folder".
    @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp'
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
        '\Microsoft\Windows\Application Experience\MareBackup'
        '\Microsoft\Windows\Application Experience\SdbinstMergeDbTask'
        '\Microsoft\Windows\Autochk\Proxy'
        '\Microsoft\Windows\Chkdsk\Proxy'
        '\Microsoft\Windows\Customer Experience Improvement Program\'
        '\Microsoft\Windows\Device Information\Device'
        '\Microsoft\Windows\Device Information\Device User'
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
        '\Microsoft\Windows\Feedback\Siuf\DmClient'
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
        '\Microsoft\Windows\Maps\MapsToastTask'
        '\Microsoft\Windows\Maps\MapsUpdateTask'
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
}

function Get-OfflineTaskIds {
    # Returns @{ TreePath = '<relative tree key>'; Id = '{GUID}' } for a task
    # path, or for every task below a folder path (trailing '\').
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [string]$TreeRoot = 'Registry::HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree'
    )
    $relative = $TaskPath.Trim('\')
    $key = Join-Path $TreeRoot $relative
    if (-not (Test-Path -LiteralPath $key)) { return @() }
    $keys = @(Get-Item -LiteralPath $key)
    if ($TaskPath.EndsWith('\')) {
        $keys += @(Get-ChildItem -LiteralPath $key -Recurse -ErrorAction SilentlyContinue)
    }
    $result = foreach ($k in $keys) {
        $id = $k.GetValue('Id')
        if ($id) {
            [pscustomobject]@{ TreePath = $k.Name; Id = [string]$id }
        }
        $k.Close()
    }
    return @($result)
}

function Remove-OfflineScheduledTask {
    # Removes each task (definition file + every TaskCache reference) from the
    # mounted image. Requires the SOFTWARE hive to be loaded as HKLM\zSOFTWARE.
    # Returns the number of TaskCache entries deleted.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [Parameter(Mandatory = $true)][string[]]$TaskPath
    )
    $cache = 'HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache'
    $removed = 0
    foreach ($task in $TaskPath) {
        $entries = @(Get-OfflineTaskIds -TaskPath $task)
        foreach ($entry in $entries) {
            foreach ($sub in 'Tasks', 'Boot', 'Logon', 'Plain', 'Maintenance') {
                Remove-RegistryValue "$cache\$sub\$($entry.Id)" | Out-Null
            }
            $removed++
        }
        # Deleting the Tree key last also removes any empty folder keys below it.
        Remove-RegistryValue "$cache\Tree\$($task.Trim('\'))" | Out-Null

        $file = Join-Path "$MountPath\Windows\System32\Tasks" $task.Trim('\')
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($entries.Count) { Write-Host "Removed scheduled task: $task" }
    }
    [GC]::Collect()
    return $removed
}

#---------[ Safe Dismount / Unload ]---------#

function Invoke-SafeOfflineRegistryUnload {
    # Best-effort unload used by the emergency trap: never throws.
    param(
        [string[]]$Hives = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')
    )
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    foreach ($hive in $Hives) {
        if (-not (Test-Path "Registry::HKEY_LOCAL_MACHINE\$hive")) { continue }
        $rc = Invoke-Native -FilePath 'reg.exe' -ArgumentList @('unload', "HKLM\$hive")
        if ($rc -eq 0) {
            Write-Output "Unloaded registry hive: HKLM\$hive"
        } else {
            Write-Warning "Could not unload HKLM\$hive (exit $rc). Run 'reg unload HKLM\$hive' manually after closing regedit."
        }
    }
}

function Invoke-SafeDismountImage {
    # Dismounts the image at $Path, retrying because a lingering handle (Explorer,
    # an AV scan of the freshly written hives, ...) commonly makes the first
    # attempt fail. Falls back to `dism /Cleanup-Mountpoints` for a discard.
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Save,
        [int]$Retries = 3
    )

    if (-not (Test-Path -Path $Path)) {
        return $false
    }
    $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Path -or $_.MountPath -eq $Path })
    if ($mounted.Count -eq 0 -and -not (Test-Path (Join-Path $Path 'Windows'))) {
        return $true
    }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            [GC]::Collect()
            if ($Save) {
                Dismount-WindowsImage -Path $Path -Save -ErrorAction Stop | Out-Null
            } else {
                Dismount-WindowsImage -Path $Path -Discard -ErrorAction Stop | Out-Null
            }
            return $true
        } catch {
            Write-Warning "Dismount attempt $attempt/$Retries at $Path failed: $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
    if (-not $Save) {
        $null = Invoke-Native -FilePath 'dism.exe' -ArgumentList @('/Cleanup-Mountpoints')
    }
    return $false
}
#---------[ Build Profile Resolution ]---------#

function Resolve-BuildProfile {
    # -Compress picks the final install image format:
    #   recovery -> install.esd (LZMS, smallest ISO, slowest export) [default]
    #   max      -> install.wim, maximum LZX compression
    #   fast     -> install.wim, XPRESS (quick builds)
    #   none     -> install.wim, uncompressed (largest)
    # -Fast = fast compression + skip DISM component cleanup; an explicit
    # -Compress still wins over -Fast.
    param([string]$Compress, [switch]$Fast)

    $valid = 'recovery', 'max', 'fast', 'none'
    if ($Compress -and ($valid -notcontains $Compress)) {
        throw "Invalid -Compress '$Compress'. Valid values: $($valid -join ', ')"
    }
    $effective = if ($Compress) { $Compress.ToLowerInvariant() } elseif ($Fast) { 'fast' } else { 'recovery' }
    return [pscustomobject]@{
        Compress       = $effective
        SkipCleanup    = [bool]$Fast
        UseEsd         = ($effective -eq 'recovery')
        ExportCompress = $effective
        ImageFileName  = if ($effective -eq 'recovery') { 'install.esd' } else { 'install.wim' }
    }
}

#---------[ Build Preset Resolution ]---------#

function Get-PresetFlagNames {
    # Every flag a preset may set. Unknown keys in a preset file are reported;
    # missing keys fall back to the Default preset.
    @(
        'RemoveAppx', 'RemoveCapabilities', 'RemoveOneDrive', 'RemoveEdge', 'RemoveWebView',
        'RemoveAI', 'RemoveStore', 'RemoveDefender', 'KeepXbox',
        'DisableTelemetry', 'DisableAds', 'DisableSponsoredApps', 'DisableThirdPartyTelemetry',
        'BlockFirewallTelemetry', 'DisableZoneInformation', 'DisableDefenderCloud',
        'EnableUltimatePerformance', 'EnableFastShutdown', 'DisableMouseAcceleration',
        'EnableUtcClock', 'TuneDefenderCpuLimit', 'EnableDriverBlocklist'
    )
}

function Get-PresetFlagSection {
    # Section of a flag in presets\*.json (debloat / privacy / performance).
    param([Parameter(Mandatory = $true)][string]$Flag)
    if ($Flag -match '^(Remove|Keep)') { return 'debloat' }
    if ($Flag -match '^(Disable(Telemetry|Ads|SponsoredApps|ThirdPartyTelemetry|ZoneInformation|DefenderCloud)|BlockFirewallTelemetry)$') { return 'privacy' }
    return 'performance'
}

function ConvertTo-PresetJson {
    # Inverse of ConvertFrom-PresetJson: writes a flag hashtable in the
    # presets\*.json schema (camelCase keys grouped by section).
    param(
        [Parameter(Mandatory = $true)][hashtable]$Flags,
        [string]$Name = 'Custom',
        [string]$Description = ''
    )
    $doc = [ordered]@{ name = $Name; description = $Description; debloat = [ordered]@{}; privacy = [ordered]@{}; performance = [ordered]@{} }
    foreach ($flag in Get-PresetFlagNames) {
        $key = $flag.Substring(0, 1).ToLowerInvariant() + $flag.Substring(1)
        $doc[(Get-PresetFlagSection $flag)][$key] = [bool]$Flags[$flag]
    }
    return ($doc | ConvertTo-Json -Depth 4)
}

function ConvertFrom-PresetJson {
    # Flattens a presets\*.json file (camelCase keys grouped in debloat /
    # privacy / performance sections, namnguyen97x schema) into a hashtable
    # with PascalCase keys. Top-level boolean keys are accepted too.
    param([Parameter(Mandatory = $true)][string]$Path)
    $json = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $result = @{}
    $add = {
        param($obj)
        foreach ($k in $obj.PSObject.Properties.Name) {
            $v = $obj.$k
            if ($v -is [bool]) {
                $result[$k.Substring(0, 1).ToUpperInvariant() + $k.Substring(1)] = $v
            }
        }
    }
    & $add $json
    foreach ($section in @('debloat', 'privacy', 'performance')) {
        if ($json.$section) { & $add $json.$section }
    }
    return $result
}

function Resolve-BuildPreset {
    # Returns the flag hashtable for a preset name (Default, Gaming,
    # Minimal-VM, PrivacyPlus - case/dash-insensitive) or a path to a custom
    # .json preset. presets\<name>.json wins over the built-in table below,
    # which is the fallback when the JSON file is missing or unreadable.
    param([string]$PresetName)

    $f = $false; $t = $true
    $base = @{
        RemoveAppx = $t; RemoveCapabilities = $t; RemoveOneDrive = $t; RemoveEdge = $t; RemoveWebView = $f
        RemoveAI = $t; RemoveStore = $f; RemoveDefender = $f; KeepXbox = $f
        DisableTelemetry = $t; DisableAds = $t; DisableSponsoredApps = $t; DisableThirdPartyTelemetry = $t
        BlockFirewallTelemetry = $f; DisableZoneInformation = $f; DisableDefenderCloud = $f
        EnableUltimatePerformance = $f; EnableFastShutdown = $f; DisableMouseAcceleration = $f
        EnableUtcClock = $f; TuneDefenderCpuLimit = $t; EnableDriverBlocklist = $t
    }
    $overrides = @{
        'Default'     = @{}
        'Gaming'      = @{ KeepXbox = $t; BlockFirewallTelemetry = $t; EnableUltimatePerformance = $t; EnableFastShutdown = $t; DisableMouseAcceleration = $t }
        'Minimal-VM'  = @{ RemoveWebView = $t; RemoveStore = $t; RemoveDefender = $t; BlockFirewallTelemetry = $t
                           DisableZoneInformation = $t; EnableUltimatePerformance = $t; EnableFastShutdown = $t
                           TuneDefenderCpuLimit = $f; EnableDriverBlocklist = $f }
        'PrivacyPlus' = @{ BlockFirewallTelemetry = $t; DisableDefenderCloud = $t; EnableFastShutdown = $t }
    }

    if (-not $PresetName) { $PresetName = 'Default' }

    # Custom preset file: anything ending in .json that exists.
    if ($PresetName -match '\.json$') {
        if (-not (Test-Path -LiteralPath $PresetName)) { throw "Preset file not found: $PresetName" }
        $custom = ConvertFrom-PresetJson -Path $PresetName
        $merged = $base.Clone()
        foreach ($k in $custom.Keys) { $merged[$k] = $custom[$k] }
        return $merged
    }

    $wanted = ($PresetName -replace '\+', 'Plus') -replace '[- ]', ''
    $key = $overrides.Keys | Where-Object { ($_ -replace '-', '') -ieq $wanted } | Select-Object -First 1
    if (-not $key) { throw "Unknown preset '$PresetName'. Available: $($overrides.Keys -join ', '), or a path to a .json preset." }

    $merged = $base.Clone()
    foreach ($k in $overrides[$key].Keys) { $merged[$k] = $overrides[$key][$k] }

    $jsonPath = Join-Path (Join-Path $repoRoot 'presets') ($key.ToLowerInvariant() + '.json')
    if (Test-Path -LiteralPath $jsonPath) {
        try {
            $fromJson = ConvertFrom-PresetJson -Path $jsonPath
            $merged = $base.Clone()
            foreach ($k in $fromJson.Keys) { $merged[$k] = $fromJson[$k] }
        } catch {
            Write-Warning "Failed to load preset JSON '$jsonPath' ($($_.Exception.Message)); using built-in defaults."
        }
    }
    return $merged
}

#---------[ Image Index Parsing ]---------#

function Get-AvailableImageIndex {
    param([string[]]$WimInfoText)

    if ($WimInfoText -is [string]) { $WimInfoText = $WimInfoText -split "`r`n" }
    $images = @()
    $cur = $null

    foreach ($line in $WimInfoText) {
        $text = [string]$line
        if ($text -match '^\s*Index\s*:\s*(\d+)') {
            if ($cur) { $images += [pscustomobject]$cur }
            $cur = [ordered]@{ Index = [int]$Matches[1]; Name = ''; SizeBytes = [long]0 }
        } elseif ($cur -and $text -match '^\s*Name\s*:\s*(.+?)\s*$') {
            $cur.Name = $Matches[1]
        } elseif ($cur -and $text -match '^\s*Size\s*:\s*([\d,]+)') {
            $cur.SizeBytes = [long]($Matches[1] -replace ',', '')
        }
    }
    if ($cur) { $images += [pscustomobject]$cur }
    if ($images.Count -eq 0) { return @() }
    return ,$images
}

#---------[ Scratch Disk Validation ]---------#

function Get-RequiredScratchBytes {
    param([long]$ImageApparentBytes)
    $factor = 1.5
    $floor  = 20GB
    $calc = [double]$ImageApparentBytes * $factor
    if ($calc -gt $floor) { $floor = $calc }
    return [long]$floor
}

function Test-SufficientScratch {
    param([long]$RequiredBytes, [long]$FreeBytes)
    return [pscustomobject]@{
        Ok            = ($FreeBytes -ge $RequiredBytes)
        RequiredBytes = $RequiredBytes
        FreeBytes     = $FreeBytes
        RequiredGB    = [int](($RequiredBytes / 1GB) * 10 + 0.5) / 10
        FreeGB        = [int](($FreeBytes / 1GB) * 10 + 0.5) / 10
    }
}

#---------[ Display Helpers ]---------#

function Show-WindowsImageMenu {
    param([array]$Images)
    Write-Host ''
    Write-Host 'Available Windows images:' -ForegroundColor Cyan
    foreach ($img in ($Images | Sort-Object ImageIndex)) {
        $label = $img.ImageName
        if ($img.ImageDescription -and $img.ImageDescription -ne $img.ImageName) {
            $label = "$label - $($img.ImageDescription)"
        }
        Write-Host ("  [{0,2}]  {1}" -f $img.ImageIndex, $label)
    }
    Write-Host ''
}

function Resolve-Architecture {
    param([string]$HostArchitecture)
    switch ($HostArchitecture) {
        'AMD64' { return 'amd64' }
        'ARM64' { return 'arm64' }
        default { return $HostArchitecture.ToLowerInvariant() }
    }
}

#---------[ Package Selector ]---------#

function Show-PackageSelector {
    param(
        [string[]]$Items
    )

    $selected = @{}
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $selected[$i] = $true
    }

    while ($true) {
        Clear-Host
        Write-Host "Select packages to REMOVE from the image:" -ForegroundColor Cyan
        Write-Host "Toggle items by entering numbers separated by commas. Commands: all, none" -ForegroundColor DarkGray
        Write-Host "Tip: use ranges like 1-5 or combinations like 1,3,7-9" -ForegroundColor DarkGray
        Write-Host "use: q / quit / exit to abort - use: 'done' if the selection is ready to proceed" -ForegroundColor DarkGreen
        Write-Host ""

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $mark = if ($selected[$i]) { '[X]' } else { '[ ]' }
            $num = ($i + 1).ToString().PadLeft(3)
            Write-Host "$num $mark  $($Items[$i])"
        }

        Write-Host ""
        $selectionInput = Read-Host "Enter selection"
        if (-not $selectionInput) { continue }

        $selectionInput = $selectionInput.Trim()
        $lower = $selectionInput.ToLowerInvariant()
        if ($lower -in @('q', 'quit', 'exit')) {
            Write-Host "Exiting selection, keeping current choices." -ForegroundColor Yellow
            break
        }
        if ($lower -eq 'done') { break }
        if ($lower -eq 'all') {
            for ($i = 0; $i -lt $Items.Count; $i++) { $selected[$i] = $true }
            continue
        }
        if ($lower -eq 'none') {
            for ($i = 0; $i -lt $Items.Count; $i++) { $selected[$i] = $false }
            continue
        }

        $tokens = $selectionInput -split '[, ]+' | Where-Object { $_ -ne '' }
        foreach ($t in $tokens) {
            if ($t -match '^\d+$') {
                $idx = [int]$t - 1
                if ($idx -ge 0 -and $idx -lt $Items.Count) {
                    $selected[$idx] = -not $selected[$idx]
                } else {
                    Write-Host "Number out of range: $t" -ForegroundColor DarkYellow
                    Start-Sleep -Seconds 1
                }
            } elseif ($t -match '^(\d+)-(\d+)$') {
                $start = [int]$Matches[1] - 1
                $end = [int]$Matches[2] - 1
                if ($start -lt 0) { $start = 0 }
                if ($end -ge $Items.Count) { $end = $Items.Count - 1 }
                if ($start -le $end) {
                    for ($j = $start; $j -le $end; $j++) {
                        $selected[$j] = -not $selected[$j]
                    }
                } else {
                    Write-Host "Invalid range: $t" -ForegroundColor DarkYellow
                    Start-Sleep -Seconds 1
                }
            } else {
                Write-Host "Ignored token: $t" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 1
            }
        }
    }

    $result = for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($selected[$i]) { $Items[$i] }
    }
    return ,$result
}

#---------[ ISO / Source Resolution ]---------#

function Mount-IsoAndGetDriveLetter {
    param([string]$ImagePath)

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "ISO file not found: $ImagePath"
    }

    $imagePath = (Resolve-Path -LiteralPath $ImagePath).Path
    $diskImage = Get-DiskImage -ImagePath $imagePath -ErrorAction SilentlyContinue
    if (-not $diskImage -or -not $diskImage.Attached) {
        Mount-DiskImage -ImagePath $imagePath -Access ReadOnly -PassThru | Out-Null
    } else {
        Write-Host "ISO is already mounted: $ImagePath"
    }

    $driveLetter = $null
    for ($i = 0; $i -lt 60; $i++) {
        $vol = Get-DiskImage -ImagePath $imagePath -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue
        if ($vol) {
            if ($vol -is [System.Array]) {
                $vol = @($vol | Where-Object { $_.DriveLetter } | Select-Object -First 1)
            }
            if ($vol -and $vol.DriveLetter) {
                $driveLetter = [string]$vol.DriveLetter
                break
            }
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $driveLetter) {
        Dismount-DiskImage -ImagePath $imagePath -ErrorAction SilentlyContinue | Out-Null
        throw "ISO mounted but no drive letter was assigned. Mount the ISO manually in Explorer and pass that drive letter with -ISO."
    }

    $driveRoot = ($driveLetter.TrimEnd(':') + ':')
    if ($driveRoot -notmatch '^[A-Za-z]:$') {
        Dismount-DiskImage -ImagePath $imagePath -ErrorAction SilentlyContinue | Out-Null
        throw "Could not resolve a valid drive letter for mounted ISO (got '$driveLetter')."
    }

    return @{
        ImagePath = $imagePath
        DriveRoot = $driveRoot
    }
}

function Resolve-WindowsSource {
    # Turns -ISO (drive letter, .iso path, or nothing = prompt) into
    # @{ DriveLetter = 'E:'; IsoPath = <path or $null>; MountedByScript = <bool> }.
    # MountedByScript tells the caller it must eject the ISO again
    # (Dismount-WindowsSource); drives the user mounted are left alone.
    param([string]$IsoParameter)

    $interactive = -not $IsoParameter
    while ($true) {
        $value = if ($interactive) {
            (Read-Host "Enter the Windows 11 ISO path or the letter of a mounted ISO").Trim().Trim('"').TrimEnd(':', '\')
        } else { $IsoParameter }
        try {
            if ($value -match '^[c-zC-Z]$') {
                $drive = "${value}:"
                Assert-WindowsSourceDrive -DriveRoot $drive
                Write-Host "Using mounted drive $drive"
                return [pscustomobject]@{ DriveLetter = $drive; IsoPath = $null; MountedByScript = $false }
            }
            if ($value -match '\.iso$' -and (Test-Path -LiteralPath $value -PathType Leaf)) {
                $alreadyMounted = [bool](Get-DiskImage -ImagePath (Resolve-Path -LiteralPath $value).Path -ErrorAction SilentlyContinue).Attached
                $mount = Mount-IsoAndGetDriveLetter -ImagePath $value
                $source = [pscustomobject]@{ DriveLetter = $mount.DriveRoot; IsoPath = $mount.ImagePath; MountedByScript = -not $alreadyMounted }
                try {
                    Assert-WindowsSourceDrive -DriveRoot $source.DriveLetter
                } catch {
                    Dismount-WindowsSource -Source $source
                    throw
                }
                Write-Host "Mounted $($source.IsoPath) at $($source.DriveLetter)"
                return $source
            }
            throw "'$value' is neither a drive letter (e.g. E) nor an existing .iso file."
        } catch {
            if (-not $interactive) { throw }
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}

function Dismount-WindowsSource {
    # Ejects the source ISO if (and only if) this run mounted it.
    param($Source)
    if ($Source -and $Source.MountedByScript -and $Source.IsoPath) {
        Dismount-DiskImage -ImagePath $Source.IsoPath -ErrorAction SilentlyContinue | Out-Null
        $Source.MountedByScript = $false
        Write-Host "Source ISO unmounted."
    }
}

function Assert-WindowsSourceDrive {
    param([string]$DriveRoot)
    if (-not (Test-Path "$DriveRoot\sources\boot.wim")) {
        throw "Drive $DriveRoot does not contain sources\boot.wim. Mount a valid Windows 11 ISO."
    }
    if (-not (Test-Path "$DriveRoot\sources\install.wim") -and -not (Test-Path "$DriveRoot\sources\install.esd")) {
        throw "Drive $DriveRoot does not contain sources\install.wim or install.esd."
    }
}

function Clear-FileReadOnly {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) {
        return
    }
    & attrib -R $FilePath
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not clear read-only attribute on $FilePath (attrib exit code $LASTEXITCODE)."
    }
}

#---------[ Scratch Workspace Management ]---------#

function Clear-StaleBuildState {
    # Recovers from a previous run that crashed or was closed mid-build:
    # unloads leftover z* hives and lets DISM forget orphaned mount points.
    # Without this the next reg load / Mount-WindowsImage fails.
    foreach ($hive in $Script:OfflineHiveNames) {
        if (Test-Path "Registry::HKEY_LOCAL_MACHINE\$hive") {
            Write-Warning "Hive HKLM\$hive is still loaded from a previous run; unloading."
            try { Invoke-RegUnload -HiveName $hive } catch { Write-Warning $_.Exception.Message }
        }
    }
    $null = Invoke-Native -FilePath 'dism.exe' -ArgumentList @('/English', '/Cleanup-Mountpoints')
}

function Initialize-ScratchWorkspace {
    # Guarantees an empty, existing mount directory (Mount-WindowsImage needs
    # it to exist - the old version returned early on a first run and the
    # mount then failed), discarding any image still mounted there.
    param([Parameter(Mandatory = $true)][string]$ScratchRoot)

    $scratchDir = Join-Path $ScratchRoot 'scratchdir'
    if (Test-Path $scratchDir) {
        $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $scratchDir -or $_.MountPath -eq $scratchDir })
        if ($mounted.Count -gt 0) {
            Write-Host "Dismounting leftover scratch image from a previous run..."
            $null = Invoke-SafeDismountImage -Path $scratchDir
        }
        Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $scratchDir) {
            # Long paths / odd ACLs left behind by a crashed run.
            $null = Invoke-Native -FilePath 'cmd.exe' -ArgumentList @('/c', 'rmdir', '/s', '/q', "\\?\$scratchDir")
        }
    }
    New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null
    return $scratchDir
}

function Assert-MountedImage {
    # Sanity check right after Mount-WindowsImage.
    param([Parameter(Mandatory = $true)][string]$MountPath)
    if (-not (Test-Path "$MountPath\Windows\System32\config\SOFTWARE")) {
        throw "Image did not mount correctly at $MountPath (no Windows\System32\config\SOFTWARE)."
    }
}

function Get-OscdimgBootArgument {
    # Builds oscdimg's -bootdata switch. x64 media boot on BIOS (etfsboot.com)
    # and UEFI (efisys.bin); ARM64 media are UEFI-only. -NoPrompt picks
    # efisys_noprompt.bin so the ISO boots without "Press any key...".
    param(
        [Parameter(Mandatory = $true)][string]$ImageRoot,
        [string]$Architecture = 'amd64',
        [switch]$NoPrompt,
        [switch]$SkipFileCheck
    )
    $efiName = if ($NoPrompt) { 'efisys_noprompt.bin' } else { 'efisys.bin' }
    $efi = "$ImageRoot\efi\microsoft\boot\$efiName"
    if ($NoPrompt -and -not $SkipFileCheck -and -not (Test-Path $efi)) {
        Write-Warning "$efiName not found; falling back to efisys.bin."
        $efi = "$ImageRoot\efi\microsoft\boot\efisys.bin"
    }
    $bios = "$ImageRoot\boot\etfsboot.com"
    if (-not $SkipFileCheck) {
        if (-not (Test-Path $efi)) { throw "Missing UEFI boot file required for ISO creation: $efi" }
        if ((Get-Item $efi).Length -lt 64KB) { throw "UEFI boot file looks truncated: $efi" }
    }
    $hasBios = ($Architecture -ne 'arm64') -and ($SkipFileCheck -or (Test-Path $bios))
    if ($hasBios) {
        return "-bootdata:2#p0,e,b$bios#pEF,e,b$efi"
    }
    return "-bootdata:1#pEF,e,b$efi"
}

function Get-BootWimIndex {
    param([string]$BootWimPath)
    $images = @(Get-WindowsImage -ImagePath $BootWimPath)
    foreach ($img in $images) {
        if ($img.ImageName -match 'Windows Setup') {
            return $img.ImageIndex
        }
    }
    if ($images.ImageIndex -contains 2) { return 2 }
    if ($images.Count -gt 0) { return $images[0].ImageIndex }
    throw "No images found in $BootWimPath"
}

function Set-UnattendImageIndex {
    # For -UnattendFile: the builders export a single edition, so any
    # /IMAGE/INDEX in a user-supplied answer file must point at image 1.
    param(
        [Parameter(Mandatory = $true)][string]$Xml,
        [int]$ImageIndex = 1
    )
    if ($Xml -notmatch '<Key>/IMAGE/INDEX</Key>') { return $Xml }
    $patched = $Xml -replace '(<Key>/IMAGE/INDEX</Key>\s*<Value>)\d+(</Value>)', "`${1}${ImageIndex}`${2}"
    if ($patched -notmatch "<Key>/IMAGE/INDEX</Key>\s*<Value>$ImageIndex</Value>") {
        throw "Failed to point /IMAGE/INDEX at image $ImageIndex in the answer file."
    }
    return $patched
}

function Invoke-EmergencyCleanup {
    # Shared body of both builders' trap: unload hives, discard the mounted
    # image, eject the ISO we mounted, drop temporary Defender exclusions.
    # Every step is best-effort; this must never throw.
    param(
        [string]$ScratchDisk,
        [string]$IsoImagePath,
        [string[]]$DefenderExclusions,
        [switch]$KeepWorkFolder
    )
    try { Invoke-SafeOfflineRegistryUnload } catch { Write-Verbose "Hive unload: $($_.Exception.Message)" }
    if ($ScratchDisk -and (Test-Path "$ScratchDisk\scratchdir")) {
        try { $null = Invoke-SafeDismountImage -Path "$ScratchDisk\scratchdir" } catch { Write-Verbose "Dismount: $($_.Exception.Message)" }
    }
    if ($IsoImagePath) {
        Dismount-DiskImage -ImagePath $IsoImagePath -ErrorAction SilentlyContinue | Out-Null
    }
    if ($DefenderExclusions) {
        try { Remove-BuildDefenderExclusion -Path $DefenderExclusions } catch { Write-Verbose "Defender exclusion: $($_.Exception.Message)" }
    }
    if (-not $KeepWorkFolder -and $ScratchDisk -and (Test-Path "$ScratchDisk\tiny11")) {
        Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

#---------[ Prerequisites & Disk Validation ]---------#

function Test-Prerequisites {
    Write-Output "Checking prerequisites..."

    if (-not (Get-Command 'dism.exe' -ErrorAction SilentlyContinue)) {
        throw "DISM was not found. It ships with every Windows 10/11 install; check that %SystemRoot%\System32 is on PATH."
    }

    foreach ($cmd in @('Mount-WindowsImage', 'Dismount-WindowsImage', 'Get-WindowsImage', 'Export-WindowsImage', 'Get-AppxProvisionedPackage')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "Required cmdlet '$cmd' was not found. Run the builder in Windows PowerShell 5.1 (powershell.exe), which includes the DISM module."
        }
    }

    foreach ($file in 'removePackage.txt', 'data\tweaks.psd1') {
        if (-not (Test-Path (Join-Path $repoRoot $file))) {
            throw "$file was not found in $repoRoot"
        }
    }

    Write-Output "Prerequisites OK."
}

function Test-ScratchDiskNtfs {
    param([string]$ScratchPath)
    if (-not (Test-Path $ScratchPath)) {
        Write-Warning "Could not verify NTFS filesystem for $ScratchPath"
        return
    }
    $driveName = (Get-Item $ScratchPath).PSDrive.Name
    $volume = Get-Volume -DriveLetter $driveName -ErrorAction SilentlyContinue
    if (-not $volume) {
        Write-Warning "Could not verify NTFS filesystem for ${driveName}:"
        return
    }
    if ($volume.FileSystem -ne 'NTFS') {
        throw "Scratch drive ${driveName}: must use NTFS (found $($volume.FileSystem)). ACL support is required for image processing."
    }
    return $true
}

#---------[ oscdimg.exe ]---------#

function Find-Oscdimg {
    # Returns @{ Path; Source } for the best available oscdimg.exe without
    # downloading anything: installed ADK (located through the KitsRoot10
    # registry value, so non-default install folders work), then a copy next
    # to the scripts, then anything on PATH. Source = 'download' if none.
    param([string]$HostArchitecture = $env:PROCESSOR_ARCHITECTURE)
    $adkArch = Resolve-Architecture -HostArchitecture $HostArchitecture
    $roots = @()
    foreach ($key in 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots',
                     'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Kits\Installed Roots') {
        $kits = [Microsoft.Win32.Registry]::GetValue($key, 'KitsRoot10', $null)
        if ($kits) { $roots += $kits.TrimEnd('\') }
    }
    $roots += "${env:ProgramFiles(x86)}\Windows Kits\10"
    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($arch in @($adkArch, 'amd64', 'x86') | Select-Object -Unique) {
            $candidate = "$root\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
            if (Test-Path -LiteralPath $candidate) {
                return [pscustomobject]@{ Path = $candidate; Source = 'adk' }
            }
        }
    }
    $local = Join-Path $repoRoot 'oscdimg.exe'
    if (Test-Path -LiteralPath $local) { return [pscustomobject]@{ Path = $local; Source = 'bundled' } }
    $onPath = Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($onPath) { return [pscustomobject]@{ Path = $onPath.Source; Source = 'path' } }
    return [pscustomobject]@{ Path = $local; Source = 'download' }
}

function Initialize-Oscdimg {
    # Finds oscdimg.exe or downloads Microsoft's copy from the public symbol
    # server. That copy carries no embedded Authenticode signature, but the URL
    # is content-addressed (timestamp + size), so the file is pinned by SHA-256
    # and rejected if it ever differs. Returns the path; sets
    # $Script:OscdimgDownloaded when fetched.
    param([string]$HostArchitecture = $env:PROCESSOR_ARCHITECTURE)
    $expectedSha256 = 'F5129F313ED7EB46F2677CF522E64264A225F226307ED0DDB52BB14C46E7CFDD'  # oscdimg 2.56, 143 360 bytes

    $found = Find-Oscdimg -HostArchitecture $HostArchitecture
    if ($found.Source -ne 'download') {
        Write-Host "Using oscdimg.exe ($($found.Source)): $($found.Path)"
        return $found.Path
    }

    $url = 'https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe'
    Write-Host "Windows ADK not found. Downloading oscdimg.exe from the Microsoft symbol server..."
    $previous = [Net.ServicePointManager]::SecurityProtocol
    $ProgressPreference = 'SilentlyContinue'   # the PS 5.1 progress bar makes downloads ~10x slower
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $found.Path -UseBasicParsing -ErrorAction Stop
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previous
    }
    $actual = Get-Sha256 -Path $found.Path
    if ($actual -ne $expectedSha256) {
        Remove-Item -LiteralPath $found.Path -Force -ErrorAction SilentlyContinue
        throw "Downloaded oscdimg.exe has an unexpected SHA-256 ($actual). Install the Windows ADK Deployment Tools instead."
    }
    $Script:OscdimgDownloaded = $true
    Write-Host "oscdimg.exe downloaded and verified (SHA-256 pinned)."
    return $found.Path
}

#---------[ Unattended XML Generation ]---------#

function ConvertTo-UnattendPassword {
    # Windows answer files accept passwords as Base64(UTF-16LE(<password><suffix>))
    # with <PlainText>false</PlainText>. The suffix is the element name
    # ("Password" for LocalAccount/AutoLogon). This is obfuscation, not
    # encryption - but it keeps the password out of casual view on the ISO.
    param(
        [AllowEmptyString()][string]$Password,
        [string]$Suffix = 'Password'
    )
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Password + $Suffix))
}

function New-UnattendXml {
    # Builds the answer file baked into the ISO root (autounattend.xml) and the
    # image (Sysprep\unattend.xml). Every option the builders expose ends up
    # here, so this is the single source of truth for OOBE behaviour.
    #
    #   Default         : local admin <UserName> is created + auto-logon once,
    #                     Microsoft-account / network pages are skipped, region
    #                     and keyboard pages are still shown (no locale forced).
    #   -InteractiveOobe: no account is created; OOBE only hides the online
    #                     account screens so you pick your own local user name.
    #   -Locale xx-YY   : pre-selects language/region/keyboard (skips those pages).
    #   -ZeroTouch      : also wipes disk 0 (UEFI/GPT layout) - fully unattended.
    param(
        [ValidateSet('amd64', 'arm64')][string]$Architecture = 'amd64',
        [string]$UserName = 'User',
        [AllowEmptyString()][string]$Password = '',
        [string]$TimeZone = 'UTC',
        [string]$Locale,
        [string]$ComputerName,
        [int]$ImageIndex = 1,
        [switch]$ZeroTouch,
        [switch]$InteractiveOobe,
        [switch]$NoCompact
    )

    $Architecture = $Architecture.ToLowerInvariant()
    if (-not $InteractiveOobe) {
        if ([string]::IsNullOrWhiteSpace($UserName)) { throw 'New-UnattendXml: -UserName is required unless -InteractiveOobe is used.' }
        if ($UserName.Length -gt 20 -or $UserName -match '["/\\\[\]:;|=,+*?<>@]') {
            throw ("New-UnattendXml: '$UserName' is not a valid local account name " + '(max 20 chars, none of "/\[]:;|=,+*?<>@).')
        }
    }
    if ($ComputerName -and ($ComputerName.Length -gt 15 -or $ComputerName -notmatch '^[A-Za-z0-9-]+$' -or $ComputerName -match '^\d+$')) {
        throw "New-UnattendXml: '$ComputerName' is not a valid NetBIOS computer name (1-15 letters, digits or '-')."
    }
    if ($Locale -and $Locale -notmatch '^[a-z]{2,3}(-[A-Za-z]{2,4}){1,2}$') {
        throw "New-UnattendXml: '$Locale' is not a valid locale name (e.g. en-US, fr-FR, zh-Hans-CN)."
    }
    # Setup needs the UI language on the windowsPE pass to run unattended.
    if ($ZeroTouch -and -not $Locale) { $Locale = 'en-US' }

    $esc = { param($v) [System.Security.SecurityElement]::Escape([string]$v) }
    $wcm = 'xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    $attrs = "processorArchitecture=`"$Architecture`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`" $wcm"
    $sb = New-Object System.Text.StringBuilder
    $w = { param($line) [void]$sb.AppendLine($line) }

    & $w '<?xml version="1.0" encoding="utf-8"?>'
    & $w '<!-- Generated by Tiny11 Builder Ultimate Edition (New-UnattendXml). -->'
    & $w '<unattend xmlns="urn:schemas-microsoft-com:unattend">'

    #--- windowsPE ---
    & $w '    <settings pass="windowsPE">'
    if ($Locale) {
        & $w "        <component name=`"Microsoft-Windows-International-Core-WinPE`" $attrs>"
        & $w "            <SetupUILanguage><UILanguage>$Locale</UILanguage></SetupUILanguage>"
        & $w "            <InputLocale>$Locale</InputLocale>"
        & $w "            <SystemLocale>$Locale</SystemLocale>"
        & $w "            <UILanguage>$Locale</UILanguage>"
        & $w "            <UserLocale>$Locale</UserLocale>"
        & $w '        </component>'
    }
    & $w "        <component name=`"Microsoft-Windows-Setup`" $attrs>"
    if ($ZeroTouch) {
        & $w '            <DiskConfiguration>'
        & $w '                <Disk wcm:action="add">'
        & $w '                    <DiskID>0</DiskID>'
        & $w '                    <WillWipeDisk>true</WillWipeDisk>'
        & $w '                    <CreatePartitions>'
        & $w '                        <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>'
        & $w '                        <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>'
        & $w '                        <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>'
        & $w '                    </CreatePartitions>'
        & $w '                    <ModifyPartitions>'
        & $w '                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>'
        & $w '                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>'
        & $w '                        <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Label>Windows</Label><Letter>C</Letter><Format>NTFS</Format></ModifyPartition>'
        & $w '                    </ModifyPartitions>'
        & $w '                </Disk>'
        & $w '                <WillShowUI>OnError</WillShowUI>'
        & $w '            </DiskConfiguration>'
    }
    & $w '            <DynamicUpdate>'
    & $w '                <Enable>false</Enable>'
    & $w '                <WillShowUI>OnError</WillShowUI>'
    & $w '            </DynamicUpdate>'
    & $w '            <ImageInstall>'
    & $w '                <OSImage>'
    if (-not $NoCompact) { & $w '                    <Compact>true</Compact>' }
    & $w '                    <InstallFrom>'
    & $w '                        <MetaData wcm:action="add">'
    & $w '                            <Key>/IMAGE/INDEX</Key>'
    & $w "                            <Value>$ImageIndex</Value>"
    & $w '                        </MetaData>'
    & $w '                    </InstallFrom>'
    if ($ZeroTouch) { & $w '                    <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>' }
    & $w '                    <WillShowUI>OnError</WillShowUI>'
    & $w '                </OSImage>'
    & $w '            </ImageInstall>'
    # Belt and braces: boot.wim already carries LabConfig, but setting it again
    # here keeps the bypass working if someone swaps in a stock boot.wim.
    & $w '            <RunSynchronous>'
    $order = 1
    foreach ($check in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck') {
        & $w '                <RunSynchronousCommand wcm:action="add">'
        & $w "                    <Order>$order</Order>"
        & $w "                    <Path>reg.exe add &quot;HKLM\SYSTEM\Setup\LabConfig&quot; /v $check /t REG_DWORD /d 1 /f</Path>"
        & $w '                </RunSynchronousCommand>'
        $order++
    }
    & $w '            </RunSynchronous>'
    & $w '            <UserData>'
    & $w '                <AcceptEula>true</AcceptEula>'
    & $w '                <ProductKey><Key/></ProductKey>'
    & $w '            </UserData>'
    & $w '        </component>'
    & $w '    </settings>'

    #--- specialize ---
    & $w '    <settings pass="specialize">'
    if ($ComputerName) {
        & $w "        <component name=`"Microsoft-Windows-Shell-Setup`" $attrs>"
        & $w "            <ComputerName>$(& $esc $ComputerName)</ComputerName>"
        & $w '        </component>'
    }
    & $w "        <component name=`"Microsoft-Windows-Deployment`" $attrs>"
    & $w '            <RunSynchronous>'
    & $w '                <RunSynchronousCommand wcm:action="add">'
    & $w '                    <Order>1</Order>'
    & $w '                    <Path>reg.exe add &quot;HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE&quot; /v BypassNRO /t REG_DWORD /d 1 /f</Path>'
    & $w '                </RunSynchronousCommand>'
    # Local accounts otherwise expire after 42 days and lock the user out of
    # an offline machine with a "password has expired" prompt.
    & $w '                <RunSynchronousCommand wcm:action="add">'
    & $w '                    <Order>2</Order>'
    & $w '                    <Path>net.exe accounts /maxpwage:UNLIMITED</Path>'
    & $w '                </RunSynchronousCommand>'
    & $w '            </RunSynchronous>'
    & $w '        </component>'
    & $w '    </settings>'

    #--- oobeSystem ---
    & $w '    <settings pass="oobeSystem">'
    if ($Locale) {
        & $w "        <component name=`"Microsoft-Windows-International-Core`" $attrs>"
        & $w "            <InputLocale>$Locale</InputLocale>"
        & $w "            <SystemLocale>$Locale</SystemLocale>"
        & $w "            <UILanguage>$Locale</UILanguage>"
        & $w "            <UserLocale>$Locale</UserLocale>"
        & $w '        </component>'
    }
    & $w "        <component name=`"Microsoft-Windows-Shell-Setup`" $attrs>"
    if (-not $InteractiveOobe) {
        $user = & $esc $UserName
        $pw = ConvertTo-UnattendPassword -Password $Password -Suffix 'Password'
        & $w '            <AutoLogon>'
        & $w '                <Enabled>true</Enabled>'
        & $w '                <LogonCount>1</LogonCount>'
        & $w "                <Password><Value>$pw</Value><PlainText>false</PlainText></Password>"
        & $w "                <Username>$user</Username>"
        & $w '            </AutoLogon>'
    }
    # Runs %WINDIR%\Setup\Tiny11\FirstLogon.cmd (staged by Install-ImagePayload):
    # browser install, user payloads, and deletion of the cached answer files.
    & $w '            <FirstLogonCommands>'
    & $w '                <SynchronousCommand wcm:action="add">'
    & $w '                    <CommandLine>cmd.exe /c if exist &quot;%WINDIR%\Setup\Tiny11\FirstLogon.cmd&quot; call &quot;%WINDIR%\Setup\Tiny11\FirstLogon.cmd&quot;</CommandLine>'
    & $w '                    <Description>Tiny11 first-logon tasks</Description>'
    & $w '                    <Order>1</Order>'
    & $w '                </SynchronousCommand>'
    & $w '            </FirstLogonCommands>'
    & $w '            <OOBE>'
    & $w '                <HideEULAPage>true</HideEULAPage>'
    if (-not $InteractiveOobe) { & $w '                <HideLocalAccountScreen>true</HideLocalAccountScreen>' }
    & $w '                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>'
    & $w '                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>'
    & $w '                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>'
    & $w '                <ProtectYourPC>3</ProtectYourPC>'
    & $w '            </OOBE>'
    & $w "            <TimeZone>$(& $esc $TimeZone)</TimeZone>"
    if (-not $InteractiveOobe) {
        & $w '            <UserAccounts>'
        & $w '                <LocalAccounts>'
        & $w '                    <LocalAccount wcm:action="add">'
        & $w "                        <DisplayName>$user</DisplayName>"
        & $w '                        <Group>Administrators</Group>'
        & $w "                        <Name>$user</Name>"
        & $w "                        <Password><Value>$pw</Value><PlainText>false</PlainText></Password>"
        & $w '                    </LocalAccount>'
        & $w '                </LocalAccounts>'
        & $w '            </UserAccounts>'
    }
    & $w '        </component>'
    & $w '    </settings>'
    & $w '</unattend>'

    return $sb.ToString()
}

function Write-UnattendFile {
    # Writes answer-file text as UTF-8 without BOM after checking it parses.
    param(
        [Parameter(Mandatory = $true)][string]$Xml,
        [Parameter(Mandatory = $true)][string]$Path
    )
    try { $null = [xml]$Xml } catch { throw "Generated answer file is not well-formed XML: $($_.Exception.Message)" }
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Xml, (New-Object System.Text.UTF8Encoding $false))
}

#---------[ Build Summary ]---------#

function Format-Elapsed {
    param([timespan]$Elapsed)
    if ($Elapsed.TotalHours -ge 1) {
        return '{0}h {1:00}m {2:00}s' -f [int][Math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds
    }
    return '{0}m {1}s' -f $Elapsed.Minutes, $Elapsed.Seconds
}

function Format-BuildSummary {
    param(
        [timespan]$Elapsed,
        [long]$IsoBytes,
        [string]$IsoPath,
        [int]$AppsRemoved,
        [int]$AppsTotal,
        [int]$Warnings,
        [string]$Image,
        [string]$Sha256
    )
    $sizeText = "{0} GB" -f (($IsoBytes / 1GB).ToString('N2', [System.Globalization.CultureInfo]::InvariantCulture))
    $warnText = if ($Warnings -eq 0) { 'none' } else { "$Warnings non-fatal (see log)" }
    $lines = @(
        "===== BUILD SUMMARY =====",
        "  Result        : SUCCESS",
        "  Elapsed       : $(Format-Elapsed $Elapsed)"
    )
    if ($Image) { $lines += "  Image         : $Image" }
    $lines += @(
        "  Output ISO    : $IsoPath  ($sizeText)",
        "  Apps removed  : $AppsRemoved of $AppsTotal provisioned Appx",
        "  Warnings      : $warnText"
    )
    if ($Sha256) { $lines += "  SHA-256       : $Sha256" }
    $lines += "========================="
    return $lines
}

function Test-IsoResult {
    # oscdimg can exit 0 and still leave a stub file behind if the disk fills
    # up; a bootable Windows ISO is never smaller than a few hundred MB.
    param([int]$ExitCode, [bool]$IsoExists, [long]$IsoBytes, [long]$MinBytes = 1)
    return ($ExitCode -eq 0 -and $IsoExists -and $IsoBytes -ge $MinBytes -and $IsoBytes -gt 0)
}

#---------[ Robocopy Wrapper ]---------#

function Test-RobocopySucceeded {
    param([int]$ExitCode)
    return ($ExitCode -lt 8)
}

function Invoke-Robocopy {
    # Mirrors the ISO tree into the work folder. /A-:R strips the read-only
    # attribute that every file copied from an ISO carries; -ExcludeFile skips
    # the multi-GB install image we export separately.
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExcludeFile = @()
    )
    $rcArgs = @($Source, $Destination, '/E', "/MT:$(Get-MaxParallelJobs)", '/R:3', '/W:3', '/A-:R', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($ExcludeFile.Count) { $rcArgs += @('/XF') + $ExcludeFile }
    $rc = Invoke-Native -FilePath 'robocopy.exe' -ArgumentList $rcArgs
    if (-not (Test-RobocopySucceeded $rc)) {
        throw "robocopy failed (exit code $rc) copying '$Source' -> '$Destination'."
    }
}

#---------[ Optional Utilities & Packages ]---------#

function Get-OptionalUtilities {
    # Single source of truth for user-selectable standalone utility apps.
    # Name = friendly token used by -Keep/-Remove and the picker.
    # Prefixes = provisioned-Appx name prefixes. Default = 'Keep' or 'Remove'.
    @(
        [pscustomobject]@{ Name = 'Terminal';      Prefixes = @('Microsoft.WindowsTerminal');             Default = 'Keep'   }
        [pscustomobject]@{ Name = 'Calculator';    Prefixes = @('Microsoft.WindowsCalculator');           Default = 'Keep'   }
        [pscustomobject]@{ Name = 'Notepad';       Prefixes = @('Microsoft.WindowsNotepad');              Default = 'Keep'   }
        [pscustomobject]@{ Name = 'Photos';        Prefixes = @('Microsoft.Windows.Photos');              Default = 'Keep'   }
        [pscustomobject]@{ Name = 'Paint';         Prefixes = @('Microsoft.Paint', 'Microsoft.MSPaint');  Default = 'Remove' }
        [pscustomobject]@{ Name = 'Camera';        Prefixes = @('Microsoft.WindowsCamera');               Default = 'Remove' }
        [pscustomobject]@{ Name = 'SoundRecorder'; Prefixes = @('Microsoft.WindowsSoundRecorder');        Default = 'Remove' }
        [pscustomobject]@{ Name = 'StickyNotes';   Prefixes = @('Microsoft.MicrosoftStickyNotes');        Default = 'Remove' }
        [pscustomobject]@{ Name = 'Clock';         Prefixes = @('Microsoft.WindowsAlarms');               Default = 'Remove' }
        [pscustomobject]@{ Name = 'MediaPlayer';   Prefixes = @('Microsoft.ZuneMusic');                   Default = 'Remove' }
        [pscustomobject]@{ Name = 'MoviesTV';      Prefixes = @('Microsoft.ZuneVideo');                   Default = 'Remove' }
        [pscustomobject]@{ Name = 'SnippingTool';  Prefixes = @('Microsoft.ScreenSketch');                Default = 'Remove' }
    )
}

function Resolve-OptionalUtilities {
    # Resolve the keep/remove state of every optional utility from its default,
    # overridden by -Keep (force keep) and -Remove (force drop). Returns the list
    # of Appx prefixes to remove and the names kept. Throws on an unknown name or
    # a name present in both lists.
    param(
        [string[]]$Keep = @(),
        [string[]]$Remove = @()
    )
    $table = Get-OptionalUtilities
    $valid = $table.Name
    foreach ($n in @($Keep + $Remove)) {
        if ($valid -notcontains $n) {
            throw "Unknown optional utility '$n'. Valid names: $($valid -join ', ')"
        }
    }
    $conflict = $Keep | Where-Object { $Remove -contains $_ }
    if ($conflict) {
        throw "Optional utility '$($conflict -join ', ')' cannot be in both -Keep and -Remove."
    }
    $removePrefixes = New-Object System.Collections.Generic.List[string]
    $keptNames      = New-Object System.Collections.Generic.List[string]
    foreach ($u in $table) {
        $state = $u.Default
        if ($Keep   -contains $u.Name) { $state = 'Keep' }
        if ($Remove -contains $u.Name) { $state = 'Remove' }
        if ($state -eq 'Remove') { $u.Prefixes | ForEach-Object { $removePrefixes.Add($_) } }
        else                     { $keptNames.Add($u.Name) }
    }
    [pscustomobject]@{
        RemovePrefixes = $removePrefixes.ToArray()
        KeptNames      = $keptNames.ToArray()
    }
}

function Assert-WinSxSRebuild {
    # Integrity gate for the rebuilt WinSxS (WinSxS_edit) BEFORE the old WinSxS is
    # deleted. The servicing stack is mandatory for boot/sysprep; the metadata
    # folders are always present in a healthy component store. If anything critical
    # is missing the allowlist did not match this build - abort rather than ship a
    # non-bootable image.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path $Path)) {
        throw "WinSxS rebuild path not found: $Path"
    }
    $hasServicingStack = @(Get-ChildItem -Path $Path -Directory -Filter '*servicingstack*' -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasServicingStack) {
        throw "WinSxS rebuild incomplete: no '*servicingstack*' directory under $Path. Aborting to avoid a non-bootable image."
    }
    $requiredMeta = 'Catalogs', 'Manifests', 'Fusion', 'FileMaps'
    $missing = $requiredMeta | Where-Object { -not (Test-Path (Join-Path $Path $_)) }
    if ($missing) {
        throw "WinSxS rebuild incomplete: missing $($missing -join ', ') under $Path. Aborting to avoid a non-bootable image."
    }
}

#---------[ Image Information ]---------#

function ConvertTo-ArchitectureName {
    # Get-WindowsImage reports the architecture as the PROCESSOR_ARCHITECTURE
    # enum; DISM text output uses x64/x86/ARM64. Normalise both to the names
    # used in unattend files and WinSxS folders.
    param($Architecture)
    switch -Regex ([string]$Architecture) {
        '^(9|x64|amd64)$' { return 'amd64' }
        '^(12|arm64)$'    { return 'arm64' }
        '^(0|x86)$'       { return 'x86' }
        '^(5|arm)$'       { return 'arm' }
        default           { return ([string]$Architecture).ToLowerInvariant() }
    }
}

function Get-WindowsDisplayVersion {
    # Maps a build number to its marketing version. Needed before the registry
    # is loaded (the old code queried HKLM\zSOFTWARE before loading it, so
    # 24H2 detection never worked).
    param([int]$Build)
    if ($Build -ge 26200) { return '25H2' }
    if ($Build -ge 26100) { return '24H2' }
    if ($Build -ge 22631) { return '23H2' }
    if ($Build -ge 22621) { return '22H2' }
    if ($Build -ge 22000) { return '21H2' }
    return 'pre-Windows 11'
}

function Get-ImageInfo {
    # Reads edition, architecture, build and languages of one image index
    # straight from the WIM/ESD metadata - no mount and no hive load needed.
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [Parameter(Mandatory = $true)][int]$Index
    )
    $img = Get-WindowsImage -ImagePath $ImagePath -Index $Index -ErrorAction Stop
    # The object exposes MajorVersion/MinorVersion/Build/SPBuild (UInt32); the
    # 'Version : 10.0.26100.1742' line Get-WindowsImage prints is composed by its format view.
    $build = [int]$img.Build
    $version = '{0}.{1}.{2}.{3}' -f $img.MajorVersion, $img.MinorVersion, $img.Build, $img.SPBuild
    # Languages may read "en-US (Default)" depending on the DISM version.
    $rawLanguages = @($img.Languages | ForEach-Object { [string]$_ })
    $languages = @($rawLanguages | ForEach-Object { ($_ -replace '\s*\(Default\)', '').Trim() })
    $marked = @($rawLanguages | Where-Object { $_ -match '\(Default\)' })
    $default = if ($marked.Count) {
        ($marked[0] -replace '\s*\(Default\)', '').Trim()
    } elseif ($null -ne $img.DefaultLanguageIndex -and $languages.Count -gt $img.DefaultLanguageIndex) {
        $languages[$img.DefaultLanguageIndex]
    } elseif ($languages.Count) { $languages[0] } else { 'en-US' }
    return [pscustomobject]@{
        Index          = $Index
        Name           = $img.ImageName
        Edition        = $img.EditionId
        Architecture   = ConvertTo-ArchitectureName $img.Architecture
        Build          = $build
        Version        = $version
        DisplayVersion = Get-WindowsDisplayVersion -Build $build
        Is24H2OrLater  = ($build -ge 26100)
        Languages      = $languages
        Language       = [string]$default
        SizeBytes      = [long]$img.ImageSize
    }
}

function Select-ImageIndex {
    # Picks the image to build from the list Get-WindowsImage -ImagePath
    # returns (objects with ImageIndex / ImageName):
    #   -Index   : must exist
    #   -Edition : exact image name, or a name ending in " <Edition>"
    #              ("Pro" -> "Windows 11 Pro", but not "Windows 11 Pro N")
    #   otherwise: the only image, or an interactive menu (unless -NonInteractive).
    param(
        [Parameter(Mandatory = $true)][object[]]$Images,
        [int]$Index,
        [string]$Edition,
        [switch]$NonInteractive
    )
    $list = ($Images | Sort-Object ImageIndex | ForEach-Object { "$($_.ImageIndex) = $($_.ImageName)" }) -join '; '
    if ($Index) {
        if (@($Images.ImageIndex) -notcontains $Index) { throw "Image index $Index not found. Available: $list" }
        return $Index
    }
    if ($Edition) {
        $hits = @($Images | Where-Object { $_.ImageName -ieq $Edition -or $_.ImageName -like "* $Edition" })
        if ($hits.Count -eq 1) { return [int]$hits[0].ImageIndex }
        if ($hits.Count -gt 1) { throw "Edition '$Edition' is ambiguous. Use -Index. Available: $list" }
        throw "Edition '$Edition' not found. Available: $list"
    }
    if (@($Images).Count -eq 1) { return [int]$Images[0].ImageIndex }
    if ($NonInteractive) { throw "This image contains several editions; pass -Index or -Edition. Available: $list" }

    $indexes = @($Images | ForEach-Object { [int]$_.ImageIndex })
    while ($true) {
        Show-WindowsImageMenu -Images $Images
        $raw = Read-Host 'Enter the image index to build'
        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed) -and $indexes -contains $parsed) { return $parsed }
        Write-Host "Choose one of: $($indexes -join ', ')" -ForegroundColor Yellow
    }
}

#---------[ Removal Planning (pure functions, unit-tested) ]---------#

function Get-ProtectedAppxPrefixes {
    # Provisioned packages that must survive any removal list: frameworks other
    # apps depend on, winget, codecs, and (unless the preset says otherwise)
    # the Store and the Windows Security UI.
    param(
        [switch]$AllowStoreRemoval,
        [switch]$AllowSecurityUiRemoval
    )
    $protected = @(
        'Microsoft.DesktopAppInstaller'
        'Microsoft.VCLibs'
        'Microsoft.UI.Xaml'
        'Microsoft.NET.Native'
        'Microsoft.WindowsAppRuntime'
        'Microsoft.ApplicationCompatibilityEnhancements'
        'Microsoft.AV1VideoExtension'
        'Microsoft.AVCEncoderVideoExtension'
        'Microsoft.HEIFImageExtension'
        'Microsoft.HEVCVideoExtension'
        'Microsoft.MPEG2VideoExtension'
        'Microsoft.RawImageExtension'
        'Microsoft.VP9VideoExtensions'
        'Microsoft.WebMediaExtensions'
        'Microsoft.WebpImageExtension'
    )
    if (-not $AllowStoreRemoval)      { $protected += @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp') }
    if (-not $AllowSecurityUiRemoval) { $protected += 'Microsoft.SecHealthUI' }
    return $protected
}

function Test-AppxPrefixMatch {
    # A package matches a list entry when its name starts with the entry
    # (wildcards such as king.com.* allowed). Prefix matching avoids the
    # accidental substring hits the old "*entry*" matching produced.
    param([string]$PackageName, [string[]]$Prefixes)
    foreach ($p in $Prefixes) {
        if (-not $p) { continue }
        if ($PackageName -like "$p*") { return $true }
    }
    return $false
}

function Resolve-AppxRemovalList {
    # Given the provisioned package names found in the image, returns the ones
    # to remove: (removePackage.txt entries + utilities marked Remove)
    # minus (utilities marked Keep + protected packages).
    param(
        [string[]]$Installed = @(),
        [string[]]$RemovePrefixes = @(),
        [string[]]$KeepPrefixes = @(),
        [string[]]$ProtectedPrefixes = (Get-ProtectedAppxPrefixes)
    )
    return @($Installed | Where-Object {
        (Test-AppxPrefixMatch -PackageName $_ -Prefixes $RemovePrefixes) -and
        -not (Test-AppxPrefixMatch -PackageName $_ -Prefixes $KeepPrefixes) -and
        -not (Test-AppxPrefixMatch -PackageName $_ -Prefixes $ProtectedPrefixes)
    })
}

function Read-PackageListFile {
    # Reads removePackage.txt-style files: one prefix per line, '#' comments
    # (whole-line or trailing) and blank lines ignored, duplicates dropped.
    param([Parameter(Mandatory = $true)][string]$Path)
    return @(Get-Content -LiteralPath $Path |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ } |
        Select-Object -Unique)
}

function Get-CapabilitiesToRemove {
    # Picks capability identities to remove from those installed in the image.
    # Standard (serviceable) images drop legacy tools plus handwriting/speech
    # packs; -Core additionally drops OCR, text-to-speech and legacy Media Player.
    # Basic language features (spell-check, typing) are always kept.
    param(
        [string[]]$Installed = @(),
        [string]$LanguageCode = 'en-US',
        [switch]$Core
    )
    $patterns = @(
        'App.StepsRecorder~'
        'App.Support.QuickAssist~'
        'Browser.InternetExplorer~'
        'MathRecognizer~'
        'Microsoft.Wallpapers.Extended~'
        'Microsoft.Windows.PowerShell.ISE~'
        'Microsoft.Windows.WordPad~'
        'XPS.Viewer~'
        "Language.Handwriting~~~$LanguageCode~"
        "Language.Speech~~~$LanguageCode~"
    )
    if ($Core) {
        $patterns += @(
            "Language.OCR~~~$LanguageCode~"
            "Language.TextToSpeech~~~$LanguageCode~"
            'Media.WindowsMediaPlayer~'
        )
    }
    return @($Installed | Where-Object {
        $name = $_
        @($patterns | Where-Object { $name -like "$_*" }).Count -gt 0
    })
}

function Get-CoreWindowsPackagesToRemove {
    # Component packages (DISM /Remove-Package) stripped from Core images only.
    # Returns full package identities picked from $Installed.
    param(
        [string[]]$Installed = @(),
        [string]$LanguageCode = 'en-US'
    )
    $patterns = @(
        'Microsoft-Windows-InternetExplorer-Optional-Package~'
        'Microsoft-Windows-Kernel-LA57-FoD-Package~'
        "Microsoft-Windows-LanguageFeatures-Handwriting-$LanguageCode-Package~"
        "Microsoft-Windows-LanguageFeatures-OCR-$LanguageCode-Package~"
        "Microsoft-Windows-LanguageFeatures-Speech-$LanguageCode-Package~"
        "Microsoft-Windows-LanguageFeatures-TextToSpeech-$LanguageCode-Package~"
        'Microsoft-Windows-MediaPlayer-Package~'
        'Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~'
        'Windows-Defender-Client-Package~'
        'Microsoft-Windows-WordPad-FoD-Package~'
        'Microsoft-Windows-TabletPCMath-Package~'
        'Microsoft-Windows-StepsRecorder-Package~'
    )
    return @($Installed | Where-Object {
        $name = $_
        @($patterns | Where-Object { $name -like "$_*" }).Count -gt 0
    })
}

#---------[ Edge / OneDrive File Removal ]---------#

function Remove-EdgeFiles {
    # Deletes the Chromium Edge install and updater from the mounted image.
    # -IncludeWebView also removes the WebView2 runtime (breaks Widgets, Teams,
    # Outlook and many third-party apps). -IncludeWinSxS deletes the WebView
    # component-store payload, which makes the image unserviceable: Core only.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [string]$Architecture = 'amd64',
        [switch]$IncludeWebView,
        [switch]$IncludeWinSxS
    )
    foreach ($dir in 'Edge', 'EdgeCore', 'EdgeUpdate') {
        $path = "$MountPath\Program Files (x86)\Microsoft\$dir"
        if (Test-Path -LiteralPath $path) {
            Write-Host "Removing $path"
            if (-not (Remove-ImagePath -Path $path)) { Write-Warning "Could not fully remove $path" }
        }
    }
    $shortcut = "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
    if (Test-Path -LiteralPath $shortcut) { Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue }

    if ($IncludeWebView) {
        $webView = "$MountPath\Windows\System32\Microsoft-Edge-Webview"
        if (Test-Path -LiteralPath $webView) {
            Write-Host "Removing $webView"
            if (-not (Remove-ImagePath -Path $webView)) { Write-Warning "Could not fully remove $webView" }
        }
    }
    if ($IncludeWinSxS) {
        $pattern = "${Architecture}_microsoft-edge-webview_31bf3856ad364e35*"
        foreach ($dir in @(Get-ChildItem -Path "$MountPath\Windows\WinSxS" -Filter $pattern -Directory -ErrorAction SilentlyContinue)) {
            Write-Host "Removing WinSxS\$($dir.Name)"
            if (-not (Remove-ImagePath -Path $dir.FullName)) { Write-Warning "Could not fully remove $($dir.FullName)" }
        }
    }
}

function Remove-OneDriveFiles {
    # OneDrive ships as OneDriveSetup.exe (installed per user at first sign-in)
    # plus Start-menu leftovers; the Run-key entry is handled by the tweak catalog.
    param([Parameter(Mandatory = $true)][string]$MountPath)
    $items = @(
        "$MountPath\Windows\System32\OneDriveSetup.exe"
        "$MountPath\Windows\SysWOW64\OneDriveSetup.exe"
        "$MountPath\Program Files\Microsoft OneDrive"
        "$MountPath\Program Files (x86)\Microsoft OneDrive"
        "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
        "$MountPath\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
    )
    foreach ($item in $items) {
        if (Test-Path -LiteralPath $item) {
            Write-Host "Removing $item"
            if (-not (Remove-ImagePath -Path $item)) { Write-Warning "Could not fully remove $item" }
        }
    }
}

#---------[ Tweak Catalog (data\tweaks.psd1) ]---------#

function Get-TweakCatalog {
    # Loads data\tweaks.psd1 and returns its groups. Import-PowerShellDataFile
    # only evaluates literals, so the catalog cannot execute code.
    param([string]$Path = (Join-Path $repoRoot 'data\tweaks.psd1'))
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Tweak catalog not found: $Path"
    }
    $data = Read-PowerShellDataFile -Path $Path
    return @($data.Groups)
}

function Read-PowerShellDataFile {
    # Same guarantee as Import-PowerShellDataFile (only literals are evaluated,
    # nothing executes) without depending on module auto-loading, which fails
    # in some hosts with an unusual PSModulePath.
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Cannot parse ${Path}: $($errors[0].Message)" }
    $hashtable = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $false)
    if (-not $hashtable) { throw "$Path does not contain a hashtable." }
    return $hashtable.SafeGetValue()
}

function ConvertFrom-TweakEntry {
    # Parses a 'Path|Name|Type|Data' Set entry (Data may itself contain '|').
    param([Parameter(Mandatory = $true)][string]$Entry)
    $parts = $Entry -split '\|', 4
    if ($parts.Count -ne 4) { throw "Malformed tweak entry (expected Path|Name|Type|Data): $Entry" }
    return [pscustomobject]@{ Path = $parts[0]; Name = $parts[1]; Type = $parts[2]; Value = $parts[3] }
}

function Test-TweakCondition {
    # 'Always' -> true; 'Flag' -> $Flags.Flag is true; '!Flag' -> $Flags.Flag is false/missing.
    param(
        [string]$When,
        [hashtable]$Flags = @{}
    )
    if (-not $When -or $When -eq 'Always') { return $true }
    $negate = $When.StartsWith('!')
    $flag = $When.TrimStart('!')
    $value = $Flags.ContainsKey($flag) -and [bool]$Flags[$flag]
    if ($negate) { return -not $value }
    return $value
}

function Get-TweakPlan {
    # Returns the catalog groups that apply for these flags, honouring
    # -Skip (group ids to leave out) and -Only (apply nothing else).
    param(
        [hashtable]$Flags = @{},
        [string[]]$Skip = @(),
        [string[]]$Only = @(),
        [object[]]$Catalog = (Get-TweakCatalog)
    )
    $known = @($Catalog | ForEach-Object { $_.Id })
    foreach ($id in @($Skip + $Only)) {
        if ($id -and $known -notcontains $id) {
            throw "Unknown tweak group '$id'. Valid ids: $($known -join ', ')"
        }
    }
    return @($Catalog | Where-Object {
        (Test-TweakCondition -When $_.When -Flags $Flags) -and
        ($Skip -notcontains $_.Id) -and
        ($Only.Count -eq 0 -or $Only -contains $_.Id)
    })
}

function Set-OfflineServiceStart {
    # Sets a service's start type in the offline SYSTEM hive; silently skips
    # services that do not exist in this image (build-to-build differences).
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateRange(0, 4)][int]$Start
    )
    if (-not (Test-Path "Registry::HKEY_LOCAL_MACHINE\zSYSTEM\ControlSet001\Services\$Name")) {
        Write-Verbose "Service $Name not present in image; skipped."
        return $false
    }
    Set-RegistryValue "HKLM\zSYSTEM\ControlSet001\Services\$Name" 'Start' 'REG_DWORD' "$Start" | Out-Null
    Write-Host "Service $Name start type -> $Start"
    return $true
}

function Invoke-TweakGroup {
    # Applies one catalog group to the loaded offline hives. Individual entry
    # failures are reported and counted, not fatal: a missing key on one build
    # must not abort a 40-minute image build. Returns the failure count.
    param([Parameter(Mandatory = $true)][hashtable]$Group)
    $failures = 0
    Write-Host "--- [$($Group.Id)] $($Group.Title)" -ForegroundColor Cyan
    foreach ($entry in @($Group.Set)) {
        if (-not $entry) { continue }
        try {
            $t = ConvertFrom-TweakEntry $entry
            $null = Set-RegistryValue $t.Path $t.Name $t.Type $t.Value
            Write-Host "    $($t.Path)\$($t.Name) = $($t.Value)" -ForegroundColor DarkGray
        } catch {
            Write-Warning "[$($Group.Id)] $($_.Exception.Message)"
            $failures++
        }
    }
    foreach ($entry in @($Group.Delete)) {
        if (-not $entry) { continue }
        try {
            $parts = $entry -split '\|', 2
            if ($parts.Count -eq 2) { $null = Remove-RegistryValue $parts[0] -Name $parts[1] }
            else { $null = Remove-RegistryValue $parts[0] }
            Write-Host "    (deleted) $entry" -ForegroundColor DarkGray
        } catch {
            Write-Warning "[$($Group.Id)] $($_.Exception.Message)"
            $failures++
        }
    }
    foreach ($entry in @($Group.Services)) {
        if (-not $entry) { continue }
        $name, $start = $entry -split '=', 2
        try { Set-OfflineServiceStart -Name $name -Start ([int]$start) | Out-Null }
        catch { Write-Warning "[$($Group.Id)] service ${name}: $($_.Exception.Message)"; $failures++ }
    }
    return $failures
}

function Invoke-TweakCatalog {
    # Applies every applicable group; returns
    # @{ Applied = <ids>; Failures = <n>; FirstBoot = <command lines> }.
    param(
        [hashtable]$Flags = @{},
        [string[]]$Skip = @(),
        [string[]]$Only = @()
    )
    $plan = Get-TweakPlan -Flags $Flags -Skip $Skip -Only $Only
    $failures = 0
    $firstBoot = New-Object System.Collections.Generic.List[string]
    foreach ($group in $plan) {
        $failures += [int](Invoke-TweakGroup -Group $group)
        foreach ($line in @($group.FirstBoot)) { if ($line) { $firstBoot.Add($line) } }
    }
    return [pscustomobject]@{
        Applied   = @($plan | ForEach-Object { $_.Id })
        Failures  = $failures
        FirstBoot = $firstBoot.ToArray()
    }
}

function Get-MaxParallelJobs {
    # Thread count for multi-threaded copies (robocopy /MT). Respects the
    # MAX_PARALLEL_JOBS override; otherwise 80% of logical CPUs, min 2, max 32.
    $envMax = $env:MAX_PARALLEL_JOBS -as [int]
    if ($envMax -and $envMax -gt 0) { return [Math]::Min($envMax, 128) }
    $proc = [Environment]::ProcessorCount
    if (-not $proc -or $proc -lt 1) { $proc = 4 }
    $calc = [int]($proc * 0.8)
    return [Math]::Max(2, [Math]::Min($calc, 32))
}

#---------[ Re-provisioning Protection ]---------#

function Get-PackageFamilyName {
    # 'Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
    #   -> 'Microsoft.BingNews_8wekyb3d8bbwe'
    param([Parameter(Mandatory = $true)][string]$PackageName)
    $parts = $PackageName -split '_'
    if ($parts.Count -lt 2) { return $PackageName }
    return "$($parts[0])_$($parts[-1])"
}

function Add-DeprovisionedPackage {
    # Marks a removed app as deprovisioned so Windows feature/cumulative
    # updates do not silently re-install it for new or existing users.
    param([Parameter(Mandatory = $true)][string[]]$PackageName)
    foreach ($pkg in $PackageName) {
        $family = Get-PackageFamilyName $pkg
        Set-RegistryValue "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$family" '' 'REG_SZ' '' | Out-Null
    }
}

#---------[ First-boot Payload (SetupComplete.cmd) ]---------#

function New-SetupCompleteScript {
    # Builds %WINDIR%\Setup\Scripts\SetupComplete.cmd. Windows runs it once as
    # SYSTEM at the end of Setup, before the first sign-in. It runs the
    # catalog's FirstBoot commands, then any payload\*.cmd / *.ps1 staged in
    # %WINDIR%\Setup\Tiny11\packages, logging to %WINDIR%\Setup\Tiny11\setupcomplete.log.
    param([string[]]$Commands = @())
    $lines = @(
        '@echo off'
        ':: Generated by Tiny11 Builder - Ultimate Edition. Runs once as SYSTEM after Windows Setup.'
        'setlocal'
        'set "T11=%WINDIR%\Setup\Tiny11"'
        'if not exist "%T11%" mkdir "%T11%"'
        'set "LOG=%T11%\setupcomplete.log"'
        'echo [%DATE% %TIME%] SetupComplete started>> "%LOG%"'
    )
    foreach ($cmd in $Commands) {
        $lines += "$cmd >> `"%LOG%`" 2>&1"
    }
    $lines += @(
        'if exist "%T11%\packages" ('
        '  for %%f in ("%T11%\packages\*.cmd") do ('
        '    echo [%DATE% %TIME%] running %%~nxf>> "%LOG%"'
        '    call "%%f" >> "%LOG%" 2>&1'
        '  )'
        '  for %%f in ("%T11%\packages\*.ps1") do ('
        '    echo [%DATE% %TIME%] running %%~nxf>> "%LOG%"'
        '    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%f" >> "%LOG%" 2>&1'
        '  )'
        ')'
        'echo [%DATE% %TIME%] SetupComplete finished>> "%LOG%"'
        'endlocal'
    )
    return ($lines -join "`r`n") + "`r`n"
}

function New-FirstLogonScript {
    # Builds %WINDIR%\Setup\Tiny11\FirstLogon.cmd, called by the answer file's
    # FirstLogonCommands in the first user's (elevated) session. It waits up
    # to ~2 minutes for a network connection (Wi-Fi may connect late), runs
    # %WINDIR%\Setup\Tiny11\firstlogon\*.cmd / *.ps1 (e.g. browser installers),
    # then deletes the cached answer files, which contain the account password.
    $lines = @(
        '@echo off'
        ':: Generated by Tiny11 Builder - Ultimate Edition. Runs once at the first sign-in.'
        'setlocal'
        'set "T11=%WINDIR%\Setup\Tiny11"'
        'set "LOG=%T11%\firstlogon.log"'
        'echo [%DATE% %TIME%] FirstLogon started>> "%LOG%"'
        'if exist "%T11%\firstlogon\*.*" ('
        '  for /l %%i in (1,1,24) do ('
        '    ping -n 1 -w 2000 1.1.1.1 >nul 2>&1 && goto :online'
        '    timeout /t 5 /nobreak >nul'
        '  )'
        '  echo [%DATE% %TIME%] no network after 2 minutes, trying anyway>> "%LOG%"'
        ')'
        ':online'
        'for %%f in ("%T11%\firstlogon\*.cmd") do ('
        '  echo [%DATE% %TIME%] running %%~nxf>> "%LOG%"'
        '  call "%%f" >> "%LOG%" 2>&1'
        ')'
        'for %%f in ("%T11%\firstlogon\*.ps1") do ('
        '  echo [%DATE% %TIME%] running %%~nxf>> "%LOG%"'
        '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%f" >> "%LOG%" 2>&1'
        ')'
        'del /f /q "%WINDIR%\Panther\unattend.xml" "%WINDIR%\Panther\unattend-original.xml" "%WINDIR%\System32\Sysprep\unattend.xml" >nul 2>&1'
        'echo [%DATE% %TIME%] FirstLogon finished>> "%LOG%"'
        'endlocal'
    )
    return ($lines -join "`r`n") + "`r`n"
}

function Install-ImagePayload {
    # Stages the first-boot/first-logon scripts and optional payload into the
    # mounted image.
    #   $PackageFiles    : .cmd/.ps1 run by SetupComplete.cmd (SYSTEM, before sign-in)
    #   $FirstLogonFiles : .cmd/.ps1 run by FirstLogon.cmd (first user, network up)
    #   $Commands        : extra command lines for SetupComplete.cmd
    # An existing OEM SetupComplete.cmd is preserved and chained.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [string[]]$Commands = @(),
        [string[]]$PackageFiles = @(),
        [string[]]$FirstLogonFiles = @()
    )
    $scripts = "$MountPath\Windows\Setup\Scripts"
    $t11 = "$MountPath\Windows\Setup\Tiny11"
    New-Item -ItemType Directory -Force -Path $scripts, "$t11\packages", "$t11\firstlogon" | Out-Null
    foreach ($file in $PackageFiles) {
        if (Test-Path -LiteralPath $file) {
            Copy-Item -LiteralPath $file -Destination "$t11\packages" -Force
            Write-Host "Staged first-boot payload: $(Split-Path $file -Leaf)"
        }
    }
    foreach ($file in $FirstLogonFiles) {
        if (Test-Path -LiteralPath $file) {
            Copy-Item -LiteralPath $file -Destination "$t11\firstlogon" -Force
            Write-Host "Staged first-logon payload: $(Split-Path $file -Leaf)"
        }
    }
    [System.IO.File]::WriteAllText("$t11\FirstLogon.cmd", (New-FirstLogonScript), [System.Text.Encoding]::ASCII)
    $target = Join-Path $scripts 'SetupComplete.cmd'
    if (Test-Path -LiteralPath $target) {
        Move-Item -LiteralPath $target -Destination "$t11\SetupComplete.oem.cmd" -Force
        $Commands = @('call "%WINDIR%\Setup\Tiny11\SetupComplete.oem.cmd"') + $Commands
    }
    $content = New-SetupCompleteScript -Commands $Commands
    [System.IO.File]::WriteAllText($target, $content, [System.Text.Encoding]::ASCII)
}

#---------[ Drivers ]---------#

function Add-ImageDrivers {
    # Injects every .inf under $DriverPath (recursively) into a mounted image.
    # Typical use: Intel RST/VMD storage drivers so Setup can see the disk.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [Parameter(Mandatory = $true)][string]$DriverPath
    )
    if (-not (Test-Path -LiteralPath $DriverPath)) { throw "Driver folder not found: $DriverPath" }
    $infs = @(Get-ChildItem -LiteralPath $DriverPath -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue)
    if ($infs.Count -eq 0) { Write-Warning "No .inf files under $DriverPath; nothing injected."; return 0 }
    Write-Host "Injecting $($infs.Count) driver package(s) from $DriverPath..."
    $added = @(Add-WindowsDriver -Path $MountPath -Driver $DriverPath -Recurse -ForceUnsigned:$false -ErrorAction Stop)
    return $added.Count
}

#---------[ Host Defender Exclusion (opt-in speed-up) ]---------#

function Add-BuildDefenderExclusion {
    # Excludes the scratch folders from the *host's* real-time scanning; DISM
    # writes ~100k files and on-access scanning can double build time.
    # Returns the paths actually added so they can be removed afterwards.
    param([Parameter(Mandatory = $true)][string[]]$Path)
    if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) { return @() }
    $existing = @((Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath)
    $added = @($Path | Where-Object { $existing -notcontains $_ })
    if ($added.Count) {
        try {
            Add-MpPreference -ExclusionPath $added -ErrorAction Stop
            Write-Host "Temporarily excluded from Defender scanning: $($added -join ', ')"
        } catch {
            Write-Warning "Could not add Defender exclusions (Tamper Protection or policy?): $($_.Exception.Message)"
            return @()
        }
    }
    return $added
}

function Remove-BuildDefenderExclusion {
    param([string[]]$Path)
    if (-not $Path -or -not (Get-Command Remove-MpPreference -ErrorAction SilentlyContinue)) { return }
    try {
        Remove-MpPreference -ExclusionPath $Path -ErrorAction Stop
        Write-Host "Removed temporary Defender exclusions."
    } catch {
        Write-Warning "Could not remove Defender exclusions ($($Path -join ', ')); remove them manually in Windows Security."
    }
}

#---------[ Build Artifacts ]---------#

function Get-Sha256 {
    # SHA-256 of a file as upper-case hex. Uses .NET directly: Get-FileHash is
    # a script cmdlet that fails to auto-load in hosts with a foreign PSModulePath.
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '')
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}
function Write-BuildManifest {
    # Writes <iso>.json next to the ISO: source, edition, build, options,
    # removed packages and applied tweak groups - so every ISO is reproducible
    # and auditable. Also writes <iso>.sha256 (sha256sum-compatible format).
    param(
        [Parameter(Mandatory = $true)][string]$IsoPath,
        [Parameter(Mandatory = $true)][hashtable]$Data
    )
    $hash = (Get-Sha256 -Path $IsoPath).ToLowerInvariant()
    $Data['iso'] = @{ file = (Split-Path $IsoPath -Leaf); sizeBytes = (Get-Item -LiteralPath $IsoPath).Length; sha256 = $hash }
    $Data['generatedAt'] = (Get-Date).ToString('o')
    $json = $Data | ConvertTo-Json -Depth 6
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$IsoPath.json", $json, $enc)
    [System.IO.File]::WriteAllText("$IsoPath.sha256", "$hash *$(Split-Path $IsoPath -Leaf)`n", $enc)
    return $hash
}


#---------[ Shared Build Stages (used by tiny11maker.ps1 and tiny11Coremaker.ps1) ]---------#

function Invoke-AppRemovalStage {
    # Removes provisioned apps from the mounted image according to the list
    # file, the optional-utility choices and the preset flags. Returns
    # @{ Removed = <package names>; Total = <n planned>; Failures = <n> }.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [Parameter(Mandatory = $true)][hashtable]$Flags,
        [Parameter(Mandatory = $true)]$Utilities,
        [Parameter(Mandatory = $true)][string]$PackageListPath,
        [switch]$Custom,
        [switch]$KeepApps
    )
    $provisioned = @(Get-AppxProvisionedPackage -Path $MountPath)
    Write-Host "Provisioned apps in the image ($($provisioned.Count)):"
    $provisioned | Sort-Object DisplayName | ForEach-Object { Write-Host "  $($_.DisplayName)  [$($_.PackageName)]" -ForegroundColor DarkGray }

    $removed = New-Object System.Collections.Generic.List[string]
    if ($KeepApps -or -not $Flags.RemoveAppx) {
        Write-Host "App removal skipped ($(if ($KeepApps) { '-KeepApps' } else { 'preset RemoveAppx=false' }))."
        return [pscustomobject]@{ Removed = @(); Total = 0; Failures = 0 }
    }

    $removePrefixes = @(Read-PackageListFile $PackageListPath) + @($Utilities.RemovePrefixes)
    $keepPrefixes = @((Get-OptionalUtilities | Where-Object { $Utilities.KeptNames -contains $_.Name }).Prefixes)
    if ($Flags.KeepXbox) {
        $keepPrefixes += @('Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameOverlay',
                           'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay')
    }
    if ($Flags.RemoveStore) { $removePrefixes += @('Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp') }
    if ($Flags.RemoveDefender) { $removePrefixes += 'Microsoft.SecHealthUI' }
    $protected = Get-ProtectedAppxPrefixes -AllowStoreRemoval:([bool]$Flags.RemoveStore) -AllowSecurityUiRemoval:([bool]$Flags.RemoveDefender)
    $plan = @(Resolve-AppxRemovalList -Installed @($provisioned.PackageName) -RemovePrefixes $removePrefixes `
            -KeepPrefixes $keepPrefixes -ProtectedPrefixes $protected)

    if ($Custom -and $plan.Count) {
        $byName = @{}
        foreach ($p in $provisioned | Where-Object { $plan -contains $_.PackageName }) { $byName[$p.DisplayName] = $p.PackageName }
        $picked = @(Show-PackageSelector -Items @($byName.Keys | Sort-Object))
        $plan = @($picked | Where-Object { $_ } | ForEach-Object { $byName[$_] })
    }

    $failures = 0
    foreach ($package in $plan) {
        Write-Host "Removing app: $package"
        try {
            Remove-AppxProvisionedPackage -Path $MountPath -PackageName $package -ErrorAction Stop | Out-Null
            $removed.Add($package)
        } catch {
            Write-Warning "Could not remove $package : $($_.Exception.Message)"
            $failures++
        }
    }
    return [pscustomobject]@{ Removed = $removed.ToArray(); Total = $plan.Count; Failures = $failures }
}

function Invoke-CapabilityRemovalStage {
    # Removes optional capabilities (see Get-CapabilitiesToRemove). Returns the failure count.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [string]$LanguageCode = 'en-US',
        [switch]$Core
    )
    Write-Host "Removing optional capabilities..."
    $installed = @(Get-WindowsCapability -Path $MountPath | Where-Object { $_.State -eq 'Installed' } | ForEach-Object { $_.Name })
    $failures = 0
    foreach ($cap in (Get-CapabilitiesToRemove -Installed $installed -LanguageCode $LanguageCode -Core:$Core)) {
        Write-Host "  - $cap"
        try { Remove-WindowsCapability -Path $MountPath -Name $cap -ErrorAction Stop | Out-Null }
        catch { Write-Warning "Could not remove capability $cap : $($_.Exception.Message)"; $failures++ }
    }
    return $failures
}

function Invoke-RegistryStage {
    # Loads the hives, applies the tweak catalog, deprovisions removed apps,
    # removes telemetry tasks and unloads. Returns the catalog result object.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [Parameter(Mandatory = $true)][hashtable]$Flags,
        [string[]]$Skip = @(),
        [string[]]$RemovedPackages = @()
    )
    Write-Host "Loading the image registry..."
    Mount-OfflineHives -MountPath $MountPath
    $result = Invoke-TweakCatalog -Flags $Flags -Skip $Skip
    if ($RemovedPackages.Count) {
        Write-Host "Marking $($RemovedPackages.Count) removed apps as deprovisioned (no reinstall on feature updates)..."
        Add-DeprovisionedPackage -PackageName $RemovedPackages
    }
    if ($Flags.DisableTelemetry) {
        Write-Host "Removing telemetry scheduled tasks..."
        $adminGroup = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount])
        foreach ($key in 'Tasks', 'Tree') {
            $null = Enable-TaskCacheWriteAccess -AdminGroup $adminGroup -OfflineTaskKey "zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\$key"
        }
        $count = Remove-OfflineScheduledTask -MountPath $MountPath -TaskPath (Get-TelemetryScheduledTasks)
        Write-Host "Removed $count scheduled task registration(s)."
    }
    Write-Host "Unloading the image registry..."
    Dismount-OfflineHives
    return $result
}

function Invoke-ComponentCleanup {
    # DISM component-store cleanup. /ResetBase makes superseded updates
    # unremovable but saves ~1 GB. Failure is not fatal. Returns $true on success.
    param(
        [Parameter(Mandatory = $true)][string]$MountPath,
        [switch]$NoResetBase
    )
    Write-Host "Cleaning up the component store (this takes a while)..."
    $cleanupArgs = @("/Image:$MountPath", '/Cleanup-Image', '/StartComponentCleanup')
    if (-not $NoResetBase) { $cleanupArgs += '/ResetBase' }
    $rc = Invoke-Native -FilePath 'dism.exe' -ArgumentList $cleanupArgs
    if ($rc -ne 0) {
        Write-Warning "Component cleanup returned $rc (the image is still valid, just larger)."
        return $false
    }
    return $true
}

function Export-FinalInstallImage {
    # Exports sources\install.wim (index 1) to the final format chosen by
    # Resolve-BuildProfile and replaces the working file, with retries for the
    # transient locks antivirus / the search indexer put on fresh files.
    param(
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)]$BuildProfile
    )
    $source = "$WorkRoot\sources\install.wim"
    $final = "$WorkRoot\sources\$($BuildProfile.ImageFileName)"
    $temp = "$WorkRoot\sources\install_export.$(if ($BuildProfile.UseEsd) { 'esd' } else { 'wim' })"
    Write-Host "Exporting the final image ($($BuildProfile.Compress) -> $($BuildProfile.ImageFileName))..."
    Invoke-DismChecked -Label 'DISM export' '/Export-Image' "/SourceImageFile:$source" '/SourceIndex:1' "/DestinationImageFile:$temp" "/Compress:$($BuildProfile.ExportCompress)" '/CheckIntegrity'
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Remove-Item -LiteralPath $source -Force -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $final -Force -ErrorAction Stop
            return $final
        } catch {
            if ($attempt -eq 5) { throw "Could not replace the install image: $($_.Exception.Message)" }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Invoke-BootImageStage {
    # Patches the Windows Setup image in boot.wim: hardware-check bypass
    # (HardwareBypass catalog group) and optional storage drivers.
    # Returns the number of failed tweak entries.
    param(
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$ScratchRoot,
        [string]$DriverPath
    )
    Write-Host "Patching boot.wim (Windows Setup hardware checks)..."
    $bootWim = "$WorkRoot\sources\boot.wim"
    Clear-FileReadOnly -FilePath $bootWim
    $bootIndex = Get-BootWimIndex -BootWimPath $bootWim
    $mountDir = Initialize-ScratchWorkspace -ScratchRoot $ScratchRoot
    Mount-WindowsImage -ImagePath $bootWim -Index $bootIndex -Path $mountDir | Out-Null
    Assert-MountedImage -MountPath $mountDir
    Mount-OfflineHives -MountPath $mountDir
    $result = Invoke-TweakCatalog -Only 'HardwareBypass'
    Dismount-OfflineHives
    if ($DriverPath) {
        $count = Add-ImageDrivers -MountPath $mountDir -DriverPath $DriverPath
        Write-Host "Injected $count driver(s) into Windows Setup."
    }
    if (-not (Invoke-SafeDismountImage -Path $mountDir -Save)) {
        throw "Failed to commit/unmount boot.wim."
    }
    return $result.Failures
}

function New-Tiny11Iso {
    # Runs oscdimg over the work folder and validates the result. Returns the
    # ISO size in bytes. Deletes oscdimg.exe again if it had to be downloaded.
    param(
        [Parameter(Mandatory = $true)][string]$WorkRoot,
        [Parameter(Mandatory = $true)][string]$OutputIso,
        [string]$Architecture = 'amd64',
        [string]$Label = 'TINY11',
        [switch]$NoPrompt
    )
    $found = Find-Oscdimg
    $oscdimg = Initialize-Oscdimg
    $bootArg = Get-OscdimgBootArgument -ImageRoot $WorkRoot -Architecture $Architecture -NoPrompt:$NoPrompt
    $Label = ($Label -replace '[^A-Za-z0-9_]', '')
    if ($Label.Length -gt 32) { $Label = $Label.Substring(0, 32) }
    if (Test-Path -LiteralPath $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }
    Write-Host "Creating ISO $OutputIso ..."
    & $oscdimg '-m' '-o' '-u2' '-udfver102' "-l$Label" $bootArg $WorkRoot $OutputIso
    $exitCode = $LASTEXITCODE
    if ($found.Source -eq 'download') { Remove-Item -LiteralPath $oscdimg -Force -ErrorAction SilentlyContinue }
    $bytes = if (Test-Path -LiteralPath $OutputIso) { (Get-Item -LiteralPath $OutputIso).Length } else { [long]0 }
    if (-not (Test-IsoResult -ExitCode $exitCode -IsoExists ($bytes -gt 0) -IsoBytes $bytes -MinBytes 300MB)) {
        throw "ISO creation failed (oscdimg exit $exitCode, $bytes bytes)."
    }
    return $bytes
}

function Get-Tiny11PayloadFiles {
    # Resolves -Payload / -Browser into the file lists Install-ImagePayload takes.
    param(
        [switch]$Payload,
        [string]$Browser = 'None'
    )
    $packages = @()
    if ($Payload) {
        # Everything except the README is staged (installers next to the scripts included);
        # SetupComplete.cmd only *executes* the top-level *.cmd / *.ps1 files.
        $packages = @(Get-ChildItem -Path (Join-Path $repoRoot 'payload\packages') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'README.md' } | ForEach-Object { $_.FullName })
    }
    $firstLogon = @()
    if ($Browser -and $Browser -ne 'None') {
        $installer = Join-Path $repoRoot "Browsers\$($Browser.ToLowerInvariant())_installer.cmd"
        if (-not (Test-Path -LiteralPath $installer)) { throw "No installer script for browser '$Browser' ($installer)." }
        $firstLogon += $installer
    }
    return [pscustomobject]@{ PackageFiles = $packages; FirstLogonFiles = $firstLogon }
}

Export-ModuleMember -Function *-*
