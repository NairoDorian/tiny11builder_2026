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

#---------[ Process / Argument Helpers ]---------#

function Format-ProcessArgument {
    param([string]$Argument)
    if ($Argument -match '\s') {
        return '"' + $Argument.Replace('"', '""') + '"'
    }
    return $Argument
}

function Build-ProcessArgumentString {
    param([string[]]$Arguments)
    return ($Arguments | ForEach-Object { Format-ProcessArgument $_ }) -join ' '
}

#---------[ DISM / Command Exit-Code Checking ]---------#

function Assert-CommandExitCode {
    param(
        [string]$Label,
        [int[]]$AllowedExitCodes = @(0)
    )
    if ($AllowedExitCodes -notcontains $LASTEXITCODE) {
        throw "$Label failed with exit code $LASTEXITCODE"
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
    reg load "HKLM\$HiveName" $FilePath
    Assert-CommandExitCode -Label "reg load HKLM\$HiveName"
    if (-not $Script:LoadedRegHives.Contains($HiveName)) {
        $Script:LoadedRegHives.Add($HiveName)
    }
}

function Invoke-RegUnload {
    param([string]$HiveName)
    reg unload "HKLM\$HiveName"
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
        throw "reg unload HKLM\$HiveName failed with exit code $LASTEXITCODE"
    }
    if ($Script:LoadedRegHives.Contains($HiveName)) {
        $Script:LoadedRegHives.Remove($HiveName)
    } elseif ($LASTEXITCODE -eq 0) {
        Write-Output "Unloaded registry hive: HKLM\$HiveName"
    }
}

function Unload-LoadedRegistries {
    for ($i = $Script:LoadedRegHives.Count - 1; $i -ge 0; $i--) {
        $hive = $Script:LoadedRegHives[$i]
        reg unload "HKLM\$hive" 2>&1 | Out-Null
        $Script:LoadedRegHives.RemoveAt($i)
        Write-Output "Unloaded registry hive: HKLM\$hive"
    }
}

function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
    Assert-CommandExitCode -Label "reg add $path\$name"
    Write-Output "Set registry value: $path\$name"
}

function Remove-RegistryValue {
    param (
        [string]$path
    )
    & 'reg' 'delete' $path '/f' | Out-Null
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1) {
        throw "reg delete $path failed with exit code $LASTEXITCODE"
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Removed registry value: $path"
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

#---------[ TaskCache GUID Definitions (version-gated) ]---------#
# These GUIDs represent scheduled tasks safe to remove from the TaskCache
# registry key. Version-branch-aware: Windows 11 24H2+ (build 26xxx) uses a
# different task set than older builds (per PR #289 from vinisebold/revamped).

$Script:TaskCacheGuids_24H2 = @(
    '3047C197-66F1-4523-BA92-6C955FEF9E4E'  # Application Compatibility Appraiser
    'A0C71CB8-E8F0-498A-901D-4EDA09E07FF4'
    '780E487D-C62F-4B55-AF84-0E38116AFE07'
    'FD607F42-4541-418A-B812-05C32EBA8626'
    'E4FED5BC-D567-4044-9642-2EDADF7DE108'
    'E292525C-72F1-482C-8F35-C513FAA98DAE'
    '30E6DB3D-C3AA-44DA-8E88-9DB52D84975E'
    '7235AFD9-C139-458E-AA61-F6FD579A198F'
    '6FD85B93-7A13-4DCA-B793-1D7D18FEAC39'
)

$Script:TaskCacheGuids_Legacy = @(
    '0600DD45-FAF2-4131-A006-0B17509B9F78'
    '4738DE7A-BCC1-4E2D-B1B0-CADB044BFA81'
    '6FAC31FA-4A85-4E64-BFD5-2154FF4594B3'
    'FC931F16-B50A-472E-B061-B6F79A71EF59'
    '0671EB05-7D95-4153-A32B-1426B9FE61DB'
    '87BF85F4-2CE1-4160-96EA-52F554AA28A2'
    '8A9C643C-3D74-4099-B6BD-9C6D170898B1'
    'E3176A65-4E44-4ED3-AA73-3283660ACB9C'
)

function Remove-TaskCacheEntries {
    param(
        [string[]]$TaskGuids,
        [string]$TaskCacheRoot = 'HKEY_LOCAL_MACHINE\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks'
    )

    foreach ($taskGuid in $TaskGuids) {
        if ([string]::IsNullOrWhiteSpace($taskGuid)) {
            continue
        }

        $taskPath = "$TaskCacheRoot\{$taskGuid}"
        & 'reg' 'delete' $taskPath '/f' | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-Output "Removed TaskCache entry: $taskGuid"
        } else {
            Write-Warning "Could not remove TaskCache entry (may not exist): $taskGuid"
        }
    }
}

function Get-TaskCacheGuidsForBuild {
    param(
        [string]$BuildVersion
    )

    # Windows 11 24H2 (build 26100+) and 25H2 use the updated GUID set.
    if ($BuildVersion -and $BuildVersion -match '^26[0-9]{3}') {
        return $Script:TaskCacheGuids_24H2
    }
    return $Script:TaskCacheGuids_Legacy
}

#---------[ Safe Dismount / Unload ]---------#

function Invoke-SafeOfflineRegistryUnload {
    param(
        [string[]]$Hives = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')
    )

    foreach ($hive in $Hives) {
        & 'reg' 'unload' "HKLM\$hive" | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Output "Unloaded registry hive: HKLM\$hive"
        } else {
            Write-Warning "Could not unload HKLM\$hive (it may already be unloaded)."
        }
    }
}

function Invoke-SafeDismountImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Save
    )

    if (-not (Test-Path -Path $Path)) {
        return $false
    }

    try {
        if ($Save) {
            Dismount-WindowsImage -Path $Path -Save -ErrorAction Stop
        } else {
            Dismount-WindowsImage -Path $Path -Discard -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Warning "Failed to dismount image at $($Path): $_"
        return $false
    }
}

#---------[ Build Profile Resolution ]---------#

function Resolve-BuildProfile {
    param([string]$Compress, [switch]$Fast)

    $valid = 'recovery', 'fast', 'none'
    if ($Compress -and ($valid -notcontains $Compress)) {
        throw "Invalid -Compress '$Compress'. Valid values: $($valid -join ', ')"
    }
    $effective = if ($Compress) { $Compress } elseif ($Fast) { 'fast' } else { 'recovery' }
    return [pscustomobject]@{
        Compress          = $effective
        SkipCleanup       = [bool]$Fast
        UseEsd            = ($effective -eq 'recovery')
        WimExportCompress = if ($effective -eq 'recovery') { 'max' } else { $effective }
    }
}

#---------[ Build Preset Resolution ]---------#

## Preset definitions matching the namnguyen97x preset schema.
## Each preset controls which optional debloat/privacy/performance tweaks are applied.
$PresetDefaults = @{
    Standard = @{
        RemoveAppx              = $true
        RemoveCapabilities      = $true
        RemoveWindowsPackages   = $true
        RemoveOneDrive          = $true
        RemoveAI                = $true
        RemoveEdge              = $true
        RemoveStore             = $false
        RemoveDefender          = $false
        DisableTelemetry        = $true
        DisableAds              = $true
        DisableSponsoredApps    = $true
        DisableThirdParty       = $true
        BlockFirewallTelemetry  = $false
        DisableZoneInformation  = $false
        EnableUltimatePerf      = $false
        EnableFastShutdown      = $false
        DisableMouseAcceleration = $false
        EnableUtcClock          = $false
        TuneMouseLatency        = $true
        TuneDefenderCpuLimit    = $true
    }
    Default = @{
        RemoveAppx              = $true
        RemoveCapabilities      = $true
        RemoveWindowsPackages   = $true
        RemoveOneDrive          = $true
        RemoveAI                = $true
        RemoveEdge              = $true
        RemoveStore             = $false
        RemoveDefender          = $false
        DisableTelemetry        = $true
        DisableAds              = $true
        DisableSponsoredApps    = $true
        DisableThirdParty       = $true
        BlockFirewallTelemetry  = $false
        DisableZoneInformation  = $false
        EnableUltimatePerf      = $false
        EnableFastShutdown      = $false
        DisableMouseAcceleration = $false
        EnableUtcClock          = $false
        TuneMouseLatency        = $true
        TuneDefenderCpuLimit    = $true
    }
    Gaming = @{
        RemoveAppx              = $true
        RemoveCapabilities      = $true
        RemoveWindowsPackages   = $true
        RemoveOneDrive          = $true
        RemoveAI                = $true
        RemoveEdge              = $true
        RemoveStore             = $false
        RemoveDefender          = $false
        DisableTelemetry        = $true
        DisableAds              = $true
        DisableSponsoredApps    = $true
        DisableThirdParty       = $true
        BlockFirewallTelemetry  = $false
        DisableZoneInformation  = $false
        EnableUltimatePerf      = $true
        EnableFastShutdown      = $false
        DisableMouseAcceleration = $true
        EnableUtcClock          = $true
        TuneMouseLatency        = $true
        TuneDefenderCpuLimit    = $true
    }
    MinimalVM = @{
        RemoveAppx              = $true
        RemoveCapabilities      = $true
        RemoveWindowsPackages   = $true
        RemoveOneDrive          = $true
        RemoveAI                = $true
        RemoveEdge              = $true
        RemoveStore             = $true
        RemoveDefender          = $true
        DisableTelemetry        = $true
        DisableAds              = $true
        DisableSponsoredApps    = $true
        DisableThirdParty       = $true
        BlockFirewallTelemetry  = $false
        DisableZoneInformation  = $false
        EnableUltimatePerf      = $true
        EnableFastShutdown      = $false
        DisableMouseAcceleration = $false
        EnableUtcClock          = $false
        TuneMouseLatency        = $true
        TuneDefenderCpuLimit    = $true
    }
    PrivacyPlus = @{
        RemoveAppx              = $true
        RemoveCapabilities      = $true
        RemoveWindowsPackages   = $true
        RemoveOneDrive          = $true
        RemoveAI                = $true
        RemoveEdge              = $true
        RemoveStore             = $false
        RemoveDefender          = $true
        DisableTelemetry        = $true
        DisableAds              = $true
        DisableSponsoredApps    = $true
        DisableThirdParty       = $true
        BlockFirewallTelemetry  = $true
        DisableZoneInformation  = $true
        EnableUltimatePerf      = $false
        EnableFastShutdown      = $true
        DisableMouseAcceleration = $false
        EnableUtcClock          = $false
        TuneMouseLatency        = $true
        TuneDefenderCpuLimit    = $true
    }
}

function Resolve-BuildPreset {
    param([string]$PresetName)
    if (-not $PresetName) { return $PresetDefaults.Standard }
    $preset = $PresetDefaults[$PresetName]
    if (-not $preset) { throw "Unknown preset '$PresetName'. Available: $($PresetDefaults.Keys -join ', ')" }
    return $preset
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

function Test-ImageIndexAvailable {
    param([int]$Index, $Available)
    return ([int[]]@($Available.Index)) -contains $Index
}

#---------[ Scratch Disk Validation ]---------#

function Get-RequiredScratchBytes {
    param([long]$ImageApparentBytes)
    $factor = 1.5
    $floor  = 20GB
    return [long]([math].Max([double]$floor, [double]$ImageApparentBytes * $factor))
}

function Test-SufficientScratch {
    param([long]$RequiredBytes, [long]$FreeBytes)
    return [pscustomobject]@{
        Ok            = ($FreeBytes -ge $RequiredBytes)
        RequiredBytes = $RequiredBytes
        FreeBytes     = $FreeBytes
        RequiredGB    = [math].Round($RequiredBytes / 1GB, 1)
        FreeGB        = [math].Round($FreeBytes / 1GB, 1)
    }
}

function Resolve-OscdimgSource {
    param([bool]$AdkExists, [bool]$BundledExists)
    if ($AdkExists)     { return 'adk' }
    if ($BundledExists) { return 'bundled' }
    return 'download'
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

function Resolve-InstallImageIndex {
    param(
        [string]$ImagePath,
        [Nullable[int]]$PreferredIndex
    )

    $images = @(Get-WindowsImage -ImagePath $ImagePath)
    if ($images.Count -eq 0) {
        throw "No images found in $ImagePath"
    }
    $indexes = @($images | ForEach-Object { $_.ImageIndex })

    if ($null -ne $PreferredIndex -and ($indexes -contains $PreferredIndex)) {
        $selected = $images | Where-Object { $_.ImageIndex -eq $PreferredIndex } | Select-Object -First 1
        Write-Host "Using image index $PreferredIndex from earlier selection: $($selected.ImageName)"
        return $PreferredIndex
    }

    if ($images.Count -eq 1) {
        Show-WindowsImageMenu -Images $images
        Write-Host "Only one image found; using index $($images[0].ImageIndex): $($images[0].ImageName)"
        return $images[0].ImageIndex
    }

    $index = $null
    while ($indexes -notcontains $index) {
        Show-WindowsImageMenu -Images $images
        $rawIndex = Read-Host 'Enter the image index number from the list above'
        $parsedIndex = 0
        if (-not [int]::TryParse($rawIndex, [ref]$parsedIndex)) {
            Write-Host "Invalid input. Enter a number from the list, e.g. $($indexes -join ', ')"
            continue
        }
        if ($indexes -notcontains $parsedIndex) {
            Write-Host "Index $parsedIndex is not available. Choose one of: $($indexes -join ', ')"
            continue
        }
        $index = $parsedIndex
    }

    $chosen = $images | Where-Object { $_.ImageIndex -eq $index } | Select-Object -First 1
    Write-Host "Selected index $index`: $($chosen.ImageName)"
    return $index
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
    param([string]$IsoParameter)

    $Script:ImagePath = $null
    $Script:MountedByScript = $false
    $driveLetter = $null

    if ($IsoParameter) {
        if ($IsoParameter -match '^[c-zC-Z]$') {
            $driveLetter = $IsoParameter + ":"
            Assert-WindowsSourceDrive -DriveRoot $driveLetter
            Write-Host "Using mounted drive $driveLetter"
            return $driveLetter
        }
        if ((Test-Path -LiteralPath $IsoParameter -PathType Leaf) -and ($IsoParameter -match '\.iso$')) {
            try {
                $mount = Mount-IsoAndGetDriveLetter -ImagePath $IsoParameter
                $Script:ImagePath = $mount.ImagePath
                $driveLetter = $mount.DriveRoot
                Assert-WindowsSourceDrive -DriveRoot $driveLetter
            } catch {
                if ($Script:ImagePath) {
                    Dismount-DiskImage -ImagePath $Script:ImagePath -ErrorAction SilentlyContinue | Out-Null
                }
                $Script:ImagePath = $null
                throw
            }
            $Script:MountedByScript = $true
            Write-Host "Mounted $($Script:ImagePath) at $driveLetter"
            return $driveLetter
        }
        throw "Invalid -ISO value. Provide a drive letter (e.g. E) or a path to a .iso file."
    }

    do {
        $userInput = Read-Host "Enter Windows 11 ISO path or mounted drive letter"
        $userInput = $userInput.Trim().Trim('"').TrimEnd(':')
        if ($userInput -match '^[c-zC-Z]$') {
            $driveLetter = $userInput + ":"
            try {
                Assert-WindowsSourceDrive -DriveRoot $driveLetter
            } catch {
                Write-Host $_.Exception.Message
                $driveLetter = $null
                continue
            }
            Write-Host "Using mounted drive $driveLetter"
        } elseif ((Test-Path -LiteralPath $userInput -PathType Leaf) -and ($userInput -match '\.iso$')) {
            try {
                $mount = Mount-IsoAndGetDriveLetter -ImagePath $userInput
                $Script:ImagePath = $mount.ImagePath
                $driveLetter = $mount.DriveRoot
                Assert-WindowsSourceDrive -DriveRoot $driveLetter
            } catch {
                Write-Host $_.Exception.Message
                if ($Script:ImagePath) {
                    Dismount-DiskImage -ImagePath $Script:ImagePath -ErrorAction SilentlyContinue | Out-Null
                }
                $Script:ImagePath = $null
                $Script:MountedByScript = $false
                $driveLetter = $null
                continue
            }
            $Script:MountedByScript = $true
            Write-Host "Mounted $($Script:ImagePath) at $driveLetter"
        } else {
            Write-Host "Invalid input. Provide a drive letter (e.g. E) or a path to a .iso file."
            $driveLetter = $null
        }
    } while (-not $driveLetter)

    return $driveLetter
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

function Initialize-ScratchWorkspace {
    param([string]$ScratchRoot)

    $scratchDir = Join-Path $ScratchRoot 'scratchdir'
    if (-not (Test-Path $scratchDir)) {
        return
    }

    $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $scratchDir })
    if ($mounted.Count -gt 0) {
        Write-Host "Dismounting leftover scratch image from a previous run..."
        Dismount-WindowsImage -Path $scratchDir -Discard -ErrorAction Stop
    }

    Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $scratchDir | Out-Null
}

function Assert-IsoBootFiles {
    param([string]$ImageRoot)
    $requiredFiles = @(
        "$ImageRoot\boot\etfsboot.com",
        "$ImageRoot\efi\microsoft\boot\efisys.bin"
    )
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            throw "Missing boot file required for ISO creation: $file"
        }
    }
}

function Resolve-AutounattendFile {
    param([string]$Architecture)
    if ($Architecture -eq 'arm64') {
        $arm64Path = "$PSScriptRoot\autounattend-arm64.xml"
        if (Test-Path $arm64Path) { return $arm64Path }
        Write-Warning "autounattend-arm64.xml not found; falling back to autounattend.xml (amd64)."
    }
    $defaultPath = "$PSScriptRoot\autounattend.xml"
    if (-not (Test-Path $defaultPath)) {
        throw "autounattend.xml not found in $PSScriptRoot"
    }
    return $defaultPath
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

function Copy-AutounattendWithIndex {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [int]$ImageIndex = 1
    )
    $xml = Get-Content -Path $SourcePath -Raw
    $xml = $xml -replace '(<Key>/IMAGE/INDEX</Key>\s*<Value>)\d+(</Value>)', "`${1}${ImageIndex}`${2}"
    if ($xml -notmatch "<Key>/IMAGE/INDEX</Key>`s*<Value>$ImageIndex</Value>") {
        throw "Failed to patch /IMAGE/INDEX to $ImageIndex in autoundate source."
    }
    $destDir = Split-Path -Path $DestinationPath -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($DestinationPath, $xml, $utf8NoBom)
    if (-not (Test-Path $DestinationPath)) {
        throw "Failed to write autoundate to $DestinationPath"
    }
}

function Invoke-ScriptCleanupOnFailure {
    param(
        [string]$ScratchDisk
    )

    Unload-LoadedRegistries

    Dismount-DiskImage -ImagePath $Script:ImagePath -ErrorAction SilentlyContinue | Out-Null
    $Script:MountedByScript = $false
    $Script:ImagePath = $null

    if ($ScratchDisk -and (Test-Path "$ScratchDisk\scratchdir")) {
        try {
            Dismount-WindowsImage -Path "$ScratchDisk\scratchdir" -Discard -ErrorAction Stop
        } catch {
            Write-Warning "Could not dismount scratch image during cleanup."
        }
    }
    if ($ScratchDisk -and (Test-Path "$ScratchDisk\tiny11")) {
        try {
            Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not remove partial tiny11 work folder during cleanup."
        }
    }

    # Clean up downloaded oscdimg if present
    $localOscdimg = "$PSScriptRoot\oscdimg.exe"
    if (Test-Path $localOscdimg) {
        Remove-Item -Path $localOscdimg -Force -ErrorAction SilentlyContinue
    }
}

#---------[ Prerequisites & Disk Validation ]---------#

function Test-Prerequisites {
    Write-Output "Checking prerequisites..."

    if (-not (Get-Command 'dism.exe' -ErrorAction SilentlyContinue)) {
        throw "DISM was not found. Install the Windows Assessment and Deployment Kit (ADK) or run on a Windows edition that includes deployment tools."
    }

    foreach ($cmd in @('Mount-WindowsImage', 'Dismount-WindowsImage', 'Get-WindowsImage', 'Export-WindowsImage')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "Required cmdlet '$cmd' was not found. Install the DISM PowerShell module (usually included with ADK)."
        }
    }

    if (-not (Test-Path "$PSScriptRoot\removePackage.txt")) {
        throw "removePackage.txt was not found in $PSScriptRoot"
    }

    if (-not (Test-Path "$PSScriptRoot\autounattend.xml")) {
        throw "autounattend.xml was not found in $PSScriptRoot"
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
}

function Test-ScratchDiskSpace {
    param(
        [string]$ScratchPath,
        [uint64]$RequiredBytes = 20GB
    )

    $itemPath = $ScratchPath
    if (-not (Test-Path $itemPath)) {
        $itemPath = Split-Path $ScratchPath -Parent
    }
    if (-not (Test-Path $itemPath)) {
        Write-Warning "Could not verify free disk space for $ScratchPath"
        return
    }

    $driveName = (Get-Item $itemPath).PSDrive.Name
    $freeBytes = (Get-PSDrive -Name $driveName).Free
    $requiredGb = [math].Round($RequiredBytes / 1GB)
    $freeGb = [math].Round($freeBytes / 1GB, 1)

    Write-Output "Scratch disk ${driveName}: free space ${freeGb} GB (required: ${requiredGb} GB)"
    if ($freeBytes -lt $RequiredBytes) {
        throw "Insufficient free space on ${driveName}:. Need at least ${requiredGb} GB, but only ${freeGb} GB is available."
    }
}

function Initialize-Oscdimg {
    param([string]$HostArchitecture)

    Write-Host "Checking for prerequisite oscdimg.exe..."
    $adkArch = Resolve-Architecture -HostArchitecture $HostArchitecture
    $ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$adkArch\Oscdimg"
    $localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

    $oscdimgPath = $null
    if ([System.IO.Directory]::Exists($ADKDepTools)) {
        Write-Host "Will be using oscdimg.exe from system ADK."
        $oscdimgPath = "$ADKDepTools\oscdimg.exe"
    } else {
        Write-Host "ADK folder not found. Creating/using local copy of oscdimg.exe."
        $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

        if (-not (Test-Path -Path $localOSCDIMGPath)) {
            Write-Host "Downloading oscdimg.exe..."
            Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

            if (-not (Test-Path $localOSCDIMGPath)) {
                throw "Failed to download oscdimg.exe."
            }
            Write-Host "oscdimg.exe downloaded successfully."
        } else {
            Write-Host "oscdimg.exe already exists locally."
        }

        $oscdimgPath = $localOSCDIMGPath
    }

    if (-not (Test-Path $oscdimgPath)) {
        throw "oscdimg.exe not found at $oscdimgPath"
    }

    return $oscdimgPath
}

#---------[ Unattended XML Generation ]---------#

function New-UnattendXml {
    param(
        [ValidateSet('amd64', 'arm64')][string]$Architecture,
        [string]$UserName,
        [string]$Password,
        [string]$TimeZone,
        [string]$Language = 'en-US',
        [switch]$ZeroTouch
    )

    $Architecture = $Architecture.ToLower()
    $escUser = [System.Security.SecurityElement]::Escape($UserName)
    $escPass = [System.Security.SecurityElement]::Escape($Password)
    $escTz   = [System.Security.SecurityElement]::Escape($TimeZone)
    $ns      = 'xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"'
    $common  = "publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`" $ns"

    if ($ZeroTouch) {
        $diskConfig = @"
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>260</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Label>System</Label><Format>FAT32</Format></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Label>Windows</Label><Format>NTFS</Format><Letter>C</Letter></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
                <WillShowUI>OnError</WillShowUI>
            </DiskConfiguration>
"@
        $installTo = '<InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>'
    } else {
        $diskConfig = ''
        $installTo  = ''
    }

    return @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="$Architecture" $common>
            <SetupUILanguage><UILanguage>$Language</UILanguage></SetupUILanguage>
            <InputLocale>$Language</InputLocale>
            <SystemLocale>$Language</SystemLocale>
            <UILanguage>$Language</UILanguage>
            <UserLocale>$Language</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="$Architecture" $common>
            <UserData>
                <AcceptEula>true</AcceptEula>
            </UserData>
            <ImageInstall>
                <OSImage>
                    <InstallFrom><MetaData wcm:action="add"><Key>/IMAGE/INDEX</Key><Value>1</Value></MetaData></InstallFrom>
                    $installTo
                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="$Architecture" $common>
            <InputLocale>$Language</InputLocale>
            <SystemLocale>$Language</SystemLocale>
            <UILanguage>$Language</UILanguage>
            <UserLocale>$Language</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$Architecture" $common>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Home</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>$escUser</Name>
                        <Group>Administrators</Group>
                        <Password><Value>$escPass</Value><PlainText>true</PlainText></Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Username>$escUser</Username>
                <Enabled>true</Enabled>
                <LogonCount>999999999</LogonCount>
                <Password><Value>$escPass</Value><PlainText>true</PlainText></Password>
            </AutoLogon>
            <TimeZone>$escTz</TimeZone>
        </component>
    </settings>
</unattend>
"@
}

#---------[ Build Summary ]---------#

function Format-BuildSummary {
    param(
        [timespan]$Elapsed,
        [long]$IsoBytes,
        [string]$IsoPath,
        [int]$AppsRemoved,
        [int]$AppsTotal,
        [int]$Warnings
    )
    $elapsedText = "{0}m {1}s" -f [int][math].Floor($Elapsed.TotalMinutes), $Elapsed.Seconds
    $sizeText    = "{0} GB" -f (($IsoBytes / 1GB).ToString('N2', [System.Globalization.CultureInfo]::InvariantCulture))
    $warnText    = if ($Warnings -eq 0) { 'none' } else { "$Warnings non-fatal (see log)" }
    return @(
        "===== BUILD SUMMARY =====",
        "  Result        : SUCCESS",
        "  Elapsed       : $elapsedText",
        "  Output ISO    : $IsoPath  ($sizeText)",
        "  Apps removed  : $AppsRemoved of $AppsTotal provisioned Appx",
        "  Warnings      : $warnText",
        "========================="
    )
}

function Test-IsoResult {
    param([int]$ExitCode, [bool]$IsoExists, [long]$IsoBytes)
    return ($ExitCode -eq 0 -and $IsoExists -and $IsoBytes -gt 0)
}

#---------[ Robocopy Wrapper ]---------#

function Test-RobocopySucceeded {
    param([int]$ExitCode)
    return ($ExitCode -lt 8)
}

function Invoke-Robocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    & robocopy.exe $Source $Destination '/E' '/MT' '/R:3' '/W:3' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' | Out-Null
    if (-not (Test-RobocopySucceeded $LASTEXITCODE)) {
        throw "robocopy failed (exit code $LASTEXITCODE) copying '$Source' -> '$Destination'."
    }
}

#---------[ Package Selection ]---------#

function Test-PrefixSelected {
    param(
        [string[]]$SelectedPrefixes,
        [string]$Prefix
    )
    return $SelectedPrefixes -contains $Prefix
}

Export-ModuleMember -Function Format-ProcessArgument
Export-ModuleMember -Function Build-ProcessArgumentString
Export-ModuleMember -Function Assert-CommandExitCode
Export-ModuleMember -Function Invoke-DismChecked
Export-ModuleMember -Function Invoke-RegLoad
Export-ModuleMember -Function Invoke-RegUnload
Export-ModuleMember -Function Unload-LoadedRegistries
Export-ModuleMember -Function Set-RegistryValue
Export-ModuleMember -Function Remove-RegistryValue
Export-ModuleMember -Function Enable-Privilege
Export-ModuleMember -Function Enable-TaskCacheWriteAccess
Export-ModuleMember -Function Remove-TaskCacheEntries
Export-ModuleMember -Function Get-TaskCacheGuidsForBuild
Export-ModuleMember -Function Invoke-SafeOfflineRegistryUnload
Export-ModuleMember -Function Invoke-SafeDismountImage
Export-ModuleMember -Function Resolve-BuildProfile
Export-ModuleMember -Function Resolve-BuildPreset
Export-ModuleMember -Function Get-AvailableImageIndex
Export-ModuleMember -Function Test-ImageIndexAvailable
Export-ModuleMember -Function Get-RequiredScratchBytes
Export-ModuleMember -Function Test-SufficientScratch
Export-ModuleMember -Function Resolve-OscdimgSource
Export-ModuleMember -Function Show-WindowsImageMenu
Export-ModuleMember -Function Resolve-InstallImageIndex
Export-ModuleMember -Function Resolve-Architecture
Export-ModuleMember -Function Show-PackageSelector
Export-ModuleMember -Function Mount-IsoAndGetDriveLetter
Export-ModuleMember -Function Resolve-WindowsSource
Export-ModuleMember -Function Assert-WindowsSourceDrive
Export-ModuleMember -Function Clear-FileReadOnly
Export-ModuleMember -Function Initialize-ScratchWorkspace
Export-ModuleMember -Function Assert-IsoBootFiles
Export-ModuleMember -Function Resolve-AutounattendFile
Export-ModuleMember -Function Get-BootWimIndex
Export-ModuleMember -Function Copy-AutounattendWithIndex
Export-ModuleMember -Function Invoke-ScriptCleanupOnFailure
Export-ModuleMember -Function Test-Prerequisites
Export-ModuleMember -Function Test-ScratchDiskNtfs
Export-ModuleMember -Function Test-ScratchDiskSpace
Export-ModuleMember -Function Initialize-Oscdimg
Export-ModuleMember -Function New-UnattendXml
Export-ModuleMember -Function Format-BuildSummary
Export-ModuleMember -Function Test-IsoResult
Export-ModuleMember -Function Test-RobocopySucceeded
Export-ModuleMember -Function Invoke-Robocopy
Export-ModuleMember -Function Test-PrefixSelected
