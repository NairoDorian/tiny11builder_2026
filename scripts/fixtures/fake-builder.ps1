# Test fixture: stands in for tiny11maker.ps1 in the GUI tests (and for the
# documentation screenshot of a finished build). It only prints the lines the
# real builder prints and writes a small file to $env:T11_FAKE_OUT - it never
# mounts, loads or changes anything. Exit code: $env:T11_FAKE_EXIT (default 0).
# $env:T11_FAKE_DOCS=1 prints a longer, realistic excerpt instead of the args.
if (-not $env:T11_FAKE_DOCS) { Write-Host "FAKE args: $($args -join ' ')" }
$lines = if ($env:T11_FAKE_DOCS) {
    @(
        '=== Tiny11 image creator - Ultimate Edition 2026.09 ==='
        '    Preset: Gaming | Compression: recovery | Output: C:\tiny11\tiny11.iso'
        'Checking prerequisites...'
        'Prerequisites OK.'
        'Selected: [6] Windows 11 Pro | 25H2 build 10.0.26200.6584 | amd64 | en-GB'
        'Copying installation media (without the install image)...'
        'Exporting edition 6 from install.esd (this also handles ESD media)...'
        'Mounting the Windows image...'
        'Provisioned apps in the image (41):'
        'Removing app: Clipchamp.Clipchamp_3.1.12240.0_neutral_~_yxz26nhyzhsrt'
        'Removing app: Microsoft.BingNews_4.55.62231.0_neutral_~_8wekyb3d8bbwe'
        'Removing app: Microsoft.Copilot_1.25071.125.0_neutral_~_8wekyb3d8bbwe'
        'Removing Microsoft Edge...'
        'Removing OneDrive...'
        'Removing optional capabilities...'
        'Loading the image registry...'
        '--- [HardwareBypass] Skip TPM / Secure Boot / CPU / RAM / storage checks'
        '--- [Telemetry] Diagnostic data at the minimum, telemetry services off'
        '--- [AI] Copilot, Recall, Click to Do, Settings agent and in-app AI off'
        'Removing telemetry scheduled tasks...'
        'Cleaning up the component store (this takes a while)...'
        'Committing and unmounting the Windows image...'
        'Exporting the final image (recovery -> install.esd)...'
        'Patching boot.wim (Windows Setup hardware checks)...'
        'Creating ISO C:\tiny11\tiny11.iso ...'
    )
} else {
    @('Checking prerequisites...', 'Selected: [6] Windows 11 Pro', 'Copying installation media (without the install image)...',
      'Mounting the Windows image...', 'Loading the image registry...', 'Exporting the final image (recovery -> install.esd)...', 'Creating ISO X ...')
}
foreach ($line in $lines) {
    Write-Host $line
    Start-Sleep -Milliseconds 60
}
if (-not $env:T11_FAKE_DOCS) { Write-Warning 'a fake warning' }
if ($env:T11_FAKE_OUT) { Set-Content -Path $env:T11_FAKE_OUT -Value 'fake iso' }
Write-Host '===== BUILD SUMMARY ====='
if ($env:T11_FAKE_DOCS) {
    Write-Host '  Result        : SUCCESS'
    Write-Host '  Elapsed       : 31m 12s'
    Write-Host '  Image         : Windows 11 Pro 25H2 (amd64)'
    Write-Host '  Output ISO    : C:\tiny11\tiny11.iso  (3.41 GB)'
    Write-Host '  Apps removed  : 29 of 29 provisioned Appx'
    Write-Host '  Warnings      : none'
    Write-Host '========================='
}
exit ([int]("0$env:T11_FAKE_EXIT"))
