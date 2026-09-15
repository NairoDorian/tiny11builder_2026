<#
.SYNOPSIS
    Applies conservative settings for Windows images intended for 1 GB-class PCs.

.DESCRIPTION
    This profile intentionally leaves Windows Update, Microsoft Defender, and the
    component store available in the regular tiny11 image. It only disables
    services and visual/background features that are disproportionately expensive
    on a very low-memory machine.

    Ported from bluecloud122/tiny11builder — uses the shared Set-RegistryValue
    function from lib/tiny11utils.psm1 (already imported by the calling script).

    Apply with: .\tiny11maker.ps1 -ISO E -Index 1 -Yes -LowRam
#>

function Invoke-Tiny11LowRamProfile {
    param (
        [string]$SystemHive = 'HKLM\zSYSTEM',
        [string]$SoftwareHive = 'HKLM\zSOFTWARE',
        [string]$DefaultHive = 'HKLM\zDEFAULT',
        [string]$UserHive = 'HKLM\zNTUSER'
    )

    Write-Output "Applying the 1 GB-class low-RAM profile..."

    # Keep services in shared host processes on systems below the normal split
    # threshold. This reduces process overhead on machines with 1-2 GB of RAM.
    Set-RegistryValue "$SystemHive\ControlSet001\Control" 'SvcHostSplitThresholdInKB' 'REG_DWORD' '3670016'

    # SysMain and Windows Search create sustained paging/indexing activity on
    # HDDs commonly found in this class of older laptop.
    foreach ($serviceName in @('SysMain', 'WSearch', 'DiagTrack')) {
        Set-RegistryValue "$SystemHive\ControlSet001\Services\$serviceName" 'Start' 'REG_DWORD' '4'
    }

    # Do not let web search, location-aware search, or consumer suggestions
    # start background work on the target device.
    Set-RegistryValue "$SoftwareHive\Policies\Microsoft\Windows\Windows Search" 'AllowCortana' 'REG_DWORD' '0'
    Set-RegistryValue "$SoftwareHive\Policies\Microsoft\Windows\Windows Search" 'DisableWebSearch' 'REG_DWORD' '1'
    Set-RegistryValue "$SoftwareHive\Policies\Microsoft\Windows\Windows Search" 'ConnectedSearchUseWeb' 'REG_DWORD' '0'
    Set-RegistryValue "$SoftwareHive\Policies\Microsoft\Windows\Windows Search" 'AllowSearchToUseLocation' 'REG_DWORD' '0'

    foreach ($hive in @($DefaultHive, $UserHive)) {
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'EnableTransparency' 'REG_DWORD' '0'
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 'REG_DWORD' '3'
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarAnimations' 'REG_DWORD' '0'
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarDa' 'REG_DWORD' '0'
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'SearchboxTaskbarMode' 'REG_DWORD' '0'
        Set-RegistryValue "$hive\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" 'GlobalUserDisabled' 'REG_DWORD' '1'
    }

    Set-RegistryValue "$DefaultHive\Control Panel\Desktop\WindowMetrics" 'MinAnimate' 'REG_SZ' '0'
    Set-RegistryValue "$UserHive\Control Panel\Desktop\WindowMetrics" 'MinAnimate' 'REG_SZ' '0'

    Write-Output "Low-RAM profile applied; this profile does not change Windows Update or Defender state."
}
