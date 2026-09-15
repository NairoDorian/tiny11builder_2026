@{
    # Module manifest for Tiny11 Builder Ultimate Edition - GUI module
    RootModule        = 'tiny11gui.psm1'
    ModuleVersion     = '26.09.2026'
    GUID              = 'b8a12345-1234-5678-9abc-def012345678'
    Author            = 'Ultimate Fork'
    CompanyName       = 'Tiny11 Builder'
    Description       = 'GUI wizard for the Tiny11 Builder Ultimate Edition.'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @(
        'Invoke-PopupInfo',
        'Invoke-PopupError',
        'Invoke-PopupYesOrNo',
        'Open-IsoFile',
        'Set-DrivesList',
        'Set-EditionsList',
        'Invoke-AutoDetect',
        'Update-EventLoop',
        'Get-ScreenStage',
        'Get-ModeSelect',
        'Get-IsoPath',
        'Get-SelectedDrive',
        'Get-SelectedImageIndex',
        'Invoke-MainForm',
        'Invoke-MountMode',
        'Invoke-ImageIndexMode'
    )
    PrivateData       = @{
        PSData = @{
            Tags         = @('tiny11', 'windows11', 'debloat', 'gui')
            LicenseUri   = 'https://github.com/NairoDorian/tiny11builder_2026'
            ProjectUri   = 'https://github.com/NairoDorian/tiny11builder_2026'
        }
    }
}
