# Test fixture: stands in for tiny11maker.ps1 in the GUI tests.
# It only prints the stage lines the real builder prints and writes a small
# file to $env:T11_FAKE_OUT - it never mounts, loads or changes anything.
# Exit code comes from $env:T11_FAKE_EXIT (default 0).
Write-Host "FAKE args: $($args -join ' ')"
foreach ($line in 'Checking prerequisites...', 'Selected: [6] Windows 11 Pro', 'Copying installation media (without the install image)...',
    'Mounting the Windows image...', 'Loading the image registry...', 'Exporting the final image (recovery -> install.esd)...', 'Creating ISO X ...') {
    Write-Host $line
    Start-Sleep -Milliseconds 100
}
Write-Warning 'a fake warning'
if ($env:T11_FAKE_OUT) { Set-Content -Path $env:T11_FAKE_OUT -Value 'fake iso' }
Write-Host '===== BUILD SUMMARY ====='
exit ([int]("0$env:T11_FAKE_EXIT"))
