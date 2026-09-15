@{
    # Module manifest for Tiny11 Builder Ultimate Edition - utility module
    RootModule        = 'tiny11utils.psm1'
    ModuleVersion     = '26.09.2026'
    GUID              = 'a1b2c3d4-1234-5678-9abc-def012345678'
    Author            = 'Ultimate Fork'
    CompanyName       = 'Tiny11 Builder'
    Description       = 'Shared utility functions for DISM, registry, privileges, ISO handling, and build orchestration.'
    CompatiblePSEditions = @('Desktop')
    FunctionsToExport = @(
        'Format-ProcessArgument',
        'Build-ProcessArgumentString',
        'Assert-CommandExitCode',
        'Invoke-DismChecked',
        'Invoke-RegLoad',
        'Invoke-RegUnload',
        'Unload-LoadedRegistries',
        'Set-RegistryValue',
        'Remove-RegistryValue',
        'Enable-Privilege',
        'Enable-TaskCacheWriteAccess',
        'Remove-TaskCacheEntries',
        'Get-TaskCacheGuidsForBuild',
        'Invoke-SafeOfflineRegistryUnload',
        'Invoke-SafeDismountImage',
        'Resolve-BuildProfile',
        'Resolve-BuildPreset',
        'Get-AvailableImageIndex',
        'Test-ImageIndexAvailable',
        'Get-RequiredScratchBytes',
        'Test-SufficientScratch',
        'Resolve-Architecture',
        'Resolve-OscdimgSource',
        'Show-WindowsImageMenu',
        'Resolve-InstallImageIndex',
        'Show-PackageSelector',
        'Mount-IsoAndGetDriveLetter',
        'Resolve-WindowsSource',
        'Assert-WindowsSourceDrive',
        'Clear-FileReadOnly',
        'Initialize-ScratchWorkspace',
        'Assert-IsoBootFiles',
        'Resolve-AutounattendFile',
        'Copy-AutounattendWithIndex',
        'Get-BootWimIndex',
        'Invoke-ScriptCleanupOnFailure',
        'Test-Prerequisites',
        'Test-ScratchDiskNtfs',
        'Test-ScratchDiskSpace',
        'Initialize-Oscdimg',
        'New-UnattendXml',
        'Format-BuildSummary',
        'Test-IsoResult',
        'Test-RobocopySucceeded',
        'Invoke-Robocopy',
        'Test-PrefixSelected',
        'Get-OptionalUtilities',
        'Resolve-OptionalUtilities',
        'Assert-WinSxSRebuild',
        'Get-AlwaysRemovePackages'
    )
    PrivateData       = @{
        PSData = @{
            Tags       = @('tiny11', 'windows11', 'debloat', 'dism', 'utilities')
            ProjectUri = 'https://github.com/NairoDorian/tiny11builder_2026'
        }
    }
}
