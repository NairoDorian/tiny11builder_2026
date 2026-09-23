<#
.SYNOPSIS
    Low-RAM (1-2 GB) profile - compatibility shim.

.DESCRIPTION
    The low-RAM settings (ported from bluecloud122/tiny11builder) now live in
    the tweak catalog as the 'LowRam' group (data\tweaks.psd1), which
    tiny11maker.ps1 applies when you pass -LowRam:

        .\tiny11maker.ps1 -ISO E -Edition Pro -LowRam

    The profile keeps Windows Update, Defender and the component store intact.
    It merges svchost processes, disables SysMain and Windows Search indexing,
    and turns off transparency, animations and background apps.

    This file remains so that older scripts which dot-source it and call
    Invoke-Tiny11LowRamProfile still work. The offline hives must already be
    loaded (Mount-OfflineHives).
#>

function Invoke-Tiny11LowRamProfile {
    $result = Invoke-TweakCatalog -Only 'LowRam'
    if ($result.Failures) {
        Write-Warning "Low-RAM profile: $($result.Failures) registry change(s) failed."
    }
}
