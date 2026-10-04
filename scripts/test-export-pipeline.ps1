#requires -Version 5.1
# Small, real file-only WIM/ESD exports. No DISM, mounts, registry or elevation.
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'lib\tiny11utils.psm1') -Force -DisableNameChecking
$wimlib=Initialize-Wimlib
$work=Join-Path $repo ('logs\export-test-'+[guid]::NewGuid().ToString('N'))
$script:passed=0
function Assert([bool]$Condition,[string]$Message) { if(-not $Condition) { throw $Message }; $script:passed++ }
function Run-Wim([string[]]$Arguments) {
    $rc=Invoke-Native -FilePath $wimlib -ArgumentList $Arguments
    Assert ($rc -eq 0) ('wimlib '+$Arguments[0]+' failed')
}
function Get-LogicalWimRecords([string]$Path) {
    $result=Invoke-Native -FilePath $wimlib -ArgumentList @('dir',$Path,'1','--detailed') -PassThru
    Assert ($result.ExitCode -eq 0) 'Detailed metadata read succeeds.'
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $groups=@{}; $currentPath=$null; $group=$null
    foreach($line in $result.Output) {
        if($line -match '^Full Path\s*=\s*"(.+)"$') { $currentPath=$Matches[1]; $group=$null }
        if($line -match '^Link Group ID\s*=\s*(.+)$') { $group=$Matches[1]; continue }
        if($line -match '^Link Count\s*=\s*(\d+)$' -and [int]$Matches[1] -gt 1) {
            if(-not $groups.ContainsKey($group)) { $groups[$group]=New-Object 'System.Collections.Generic.List[string]' }
            $groups[$group].Add($currentPath)
        }
        # These fields describe physical container placement, not Windows data.
        if($line -match '^\s*(?:Compressed size|Offset in WIM|Solid resource|Solid offset|Part Number|Reference Count|Flags)\s*=') {continue}
        $lines.Add($line)
    }
    $topology=New-Object 'System.Collections.Generic.List[string]'
    foreach($paths in $groups.Values) { $paths.Sort([StringComparer]::Ordinal); $topology.Add('HARDLINK|'+($paths -join '|')) }
    $topology.Sort([StringComparer]::Ordinal)
    return ($lines -join "`n")+"`n"+($topology -join "`n")
}
New-Item -ItemType Directory $work | Out-Null
try {
    $first=Join-Path $work 'first'; $second=Join-Path $work 'second'
    New-Item -ItemType Directory $first,$second | Out-Null
    [IO.File]::WriteAllText((Join-Path $first 'edition.txt'),'First edition')
    [IO.File]::WriteAllText((Join-Path $second 'edition.txt'),'Second edition')
    [void](New-Item -ItemType HardLink -Path (Join-Path $second 'linked.txt') -Target (Join-Path $second 'edition.txt'))
    Set-Content -LiteralPath (Join-Path $second 'edition.txt') -Stream 'extra' -Value 'Alternate stream preserved'
    # Multi-language metadata with a non-first default catches hardcoding.
    $metadataOptions = @(
        '--image-property=FLAGS=Professional'
        '--image-property=WINDOWS/ARCH=9'
        '--image-property=WINDOWS/EDITIONID=Professional'
        '--image-property=WINDOWS/INSTALLATIONTYPE=Client'
        '--image-property=WINDOWS/PRODUCTTYPE=WinNT'
        '--image-property=WINDOWS/PRODUCTSUITE=Terminal Server'
        '--image-property=WINDOWS/LANGUAGES/LANGUAGE[1]=en-US'
        '--image-property=WINDOWS/LANGUAGES/LANGUAGE[2]=fr-FR'
        '--image-property=WINDOWS/LANGUAGES/DEFAULT=fr-FR'
        '--image-property=WINDOWS/VERSION/MAJOR=10'
        '--image-property=WINDOWS/VERSION/MINOR=0'
        '--image-property=WINDOWS/VERSION/BUILD=26300'
        '--image-property=WINDOWS/VERSION/SPBUILD=9457'
    )
    foreach($compression in 'LZX','XPRESS','LZMS') {
        $source=Join-Path $work "source-$compression.wim"
        $options=if($compression -eq 'LZMS') {@('--solid','--solid-compress=LZMS:100')} else {@("--compress=$compression")}
        Run-Wim (@('capture',$first,$source,'First','--check')+$options+$metadataOptions)
        Run-Wim (@('append',$second,$source,'Second','--check')+$metadataOptions)
        $sourceHash=Get-Sha256 $source
        $destination=Join-Path $work "selected-$compression.wim"
        Export-SelectedInstallImage -Source $source -Index 2 -Destination $destination -CompressionEngine Wimlib 6>$null
        $stream=[IO.File]::OpenRead($destination)
        try {
            $reader=New-Object IO.BinaryReader($stream)
            $header=$reader.ReadBytes(208)
            Assert ([BitConverter]::ToUInt32($header,12) -eq 0x10d00) "$compression exports a standard mountable WIM."
            Assert ([BitConverter]::ToUInt32($header,44) -eq 1) 'Only the selected edition is exported.'
            $flags=[BitConverter]::ToUInt32($header,16)
            Assert (($flags -band 0x80000) -eq 0) 'Working WIM must not use LZMS.'
            if($compression -eq 'LZX') { Assert (($flags -band 0x40000) -ne 0) 'LZX is reused without recompression.' }
        } finally { $stream.Dispose() }
        $extract=Join-Path $work "extract-$compression"
        Run-Wim @('extract',$destination,'1','/edition.txt','--no-acls',"--dest-dir=$extract")
        Assert ([IO.File]::ReadAllText((Join-Path $extract 'edition.txt')) -eq 'Second edition') 'Correct edition contents.'
        Assert ((Get-Sha256 $source) -eq $sourceHash) 'Source remains untouched.'
        Run-Wim @('verify',$destination)
        $logicalBefore=Get-LogicalWimRecords $destination
        $finalRoot=Join-Path $work "final-$compression"
        New-Item -ItemType Directory -Path (Join-Path $finalRoot 'sources') -Force | Out-Null
        Copy-Item -LiteralPath $destination -Destination (Join-Path $finalRoot 'sources\install.wim')
        $final=Export-FinalInstallImage -WorkRoot $finalRoot -BuildProfile (Resolve-BuildProfile -Compress maximum) -CompressionEngine Wimlib 6>$null
        $logicalAfter=Get-LogicalWimRecords $final
        Assert ($logicalBefore -eq $logicalAfter) 'Final maximum compression preserves data, ADS, permissions, timestamps, attributes and hard-link membership.'
        Run-Wim @('verify',$final)
        $expectedMetadata = Get-InstallImageMetadata -ImagePath $source -Index 2
        foreach ($imagePath in $destination, $final) {
            $beforeHash = Get-Sha256 $imagePath
            Assert-InstallImageMetadata -ImagePath $imagePath -Expected $expectedMetadata -RepairMissing
            Assert ((Get-Sha256 $imagePath) -eq $beforeHash) 'Matching metadata is a read-only no-op.'
            $beforeRecords = Get-LogicalWimRecords $imagePath
            Run-Wim @('info', $imagePath, '1', '--check',
                '--image-property=WINDOWS/EDITIONID=', '--image-property=WINDOWS/INSTALLATIONTYPE=',
                '--image-property=WINDOWS/PRODUCTTYPE=', '--image-property=WINDOWS/PRODUCTSUITE=',
                '--image-property=WINDOWS/LANGUAGES=')
            $lost = Get-InstallImageMetadata -ImagePath $imagePath -Index 1
            Assert (-not $lost.Edition -and -not $lost.Languages.Count -and $lost.Flags -eq 'Professional') 'Fixture reproduces #583: FLAGS survives but Setup fields disappear.'
            $threw = $false
            try { Assert-InstallImageMetadata -ImagePath $imagePath -Expected $expectedMetadata } catch { $threw = $true }
            Assert $threw 'Strict guard rejects lost metadata before repair.'
            Assert-InstallImageMetadata -ImagePath $imagePath -Expected $expectedMetadata -RepairMissing
            $restored = Get-InstallImageMetadata -ImagePath $imagePath -Index 1
            Assert ($restored.DefaultLanguage -eq 'fr-FR' -and ($restored.Languages -join ',') -eq 'en-US,fr-FR') 'Repair preserves multilingual order and non-first default language.'
            Assert ((Get-LogicalWimRecords $imagePath) -eq $beforeRecords) 'Repair preserves payloads, ADS, ACLs, timestamps and hard-link membership.'
            $stream=[IO.File]::OpenRead($imagePath)
            try {
                $reader=New-Object IO.BinaryReader($stream); $header=$reader.ReadBytes(208)
                Assert (([BitConverter]::ToUInt64($header,124) -band 0x00ffffffffffffffL) -gt 0) 'Repair retains an integrity table.'
            } finally { $stream.Dispose() }
            Run-Wim @('info', $imagePath, '1', '--check', '--image-property=WINDOWS/LANGUAGES/DEFAULT=')
            Assert-InstallImageMetadata -ImagePath $imagePath -Expected $expectedMetadata -RepairMissing
            Assert ((Get-InstallImageMetadata -ImagePath $imagePath -Index 1).DefaultLanguage -eq 'fr-FR') 'Missing default is restored without replacing it with the first language.'
            Run-Wim @('verify', $imagePath)
            Run-Wim @('info', $imagePath, '1', '--check', '--image-property=WINDOWS/EDITIONID=Core')
            $badHash = Get-Sha256 $imagePath; $threw = $false
            try { Assert-InstallImageMetadata -ImagePath $imagePath -Expected $expectedMetadata -RepairMissing } catch { $threw = $true }
            Assert ($threw -and (Get-Sha256 $imagePath) -eq $badHash) 'Conflicting edition fails without modifying the image.'
        }
        $threw=$false
        try { Export-SelectedInstallImage -Source $source -Index 2 -Destination $destination -CompressionEngine Wimlib } catch { $threw=$true }
        Assert $threw 'Never append to or overwrite an earlier export.'
    }
    $invalid=Join-Path $work 'invalid.wim'
    $threw=$false
    try { Export-SelectedInstallImage -Source $source -Index 999 -Destination $invalid -CompressionEngine Wimlib 6>$null } catch { $threw=$true }
    Assert $threw 'Native invalid-index error fails the stage.'
    Assert (-not (Test-Path -LiteralPath $invalid)) 'Failed export is never published as the working image.'
} finally {
    $resolved=[IO.Path]::GetFullPath($work)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'logs'))+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host "RESULT: $script:passed real export checks passed."
