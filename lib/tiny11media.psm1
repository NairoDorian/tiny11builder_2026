# Read only optical filesystem metadata; never attach an ISO or service an image.
$Script:MediaRoot = $PSScriptRoot

function Get-WindowsReleaseHint {
    param([string]$Source)
    $name = [IO.Path]::GetFileName($Source)
    if ($name -match '(?i)(21H2|22H2|23H2|24H2|25H2|26H1|26H2)') {
        return "Windows 11 $($Matches[1].ToUpperInvariant()) (filename hint; awaiting image metadata)"
    }
    if ($name -match '(?<!\d)(22000|22621|22631|26100|26200|26300|28000)(?!\d)') {
        $release = Get-WindowsDisplayVersion -Build ([int]$Matches[1])
        return "Windows 11 $release (filename hint; awaiting image metadata)"
    }
    return 'Reading the image metadata directly; no ISO mount needed.'
}

function Read-WimMetadata {
    param([Parameter(Mandatory=$true)][IO.Stream]$Stream)
    $reader = New-Object IO.BinaryReader($Stream, [Text.Encoding]::Unicode, $true)
    try {
        $Stream.Position = 0
        $header = $reader.ReadBytes(208)
        if ($header.Length -ne 208 -or [Text.Encoding]::ASCII.GetString($header,0,8) -ne "MSWIM`0`0`0") { throw 'Invalid WIM/ESD header.' }
        $sizeFlags = [BitConverter]::ToUInt64($header,72)
        $length = $sizeFlags -band 0x00ffffffffffffffL
        $offset = [BitConverter]::ToUInt64($header,80)
        if (($sizeFlags -shr 56) -band 4) { throw 'Compressed WIM XML metadata is not supported.' }
        if ($length -lt 2 -or $length -gt 16MB -or $offset -gt [uint64]$Stream.Length -or $length -gt ([uint64]$Stream.Length - $offset)) { throw 'WIM XML metadata is outside the image or exceeds the size limit.' }
        $Stream.Position = [long]$offset
        $bytes = $reader.ReadBytes([int]$length)
        if ($bytes.Length -ne $length) { throw 'Truncated WIM XML metadata.' }
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $memory = New-Object IO.MemoryStream(,$bytes)
        $xmlReader = [Xml.XmlReader]::Create($memory,$settings)
        try {
            $document = New-Object Xml.XmlDocument
            $document.XmlResolver = $null
            $document.Load($xmlReader)
        } finally { $xmlReader.Dispose(); $memory.Dispose() }
        $images = @($document.SelectNodes('/WIM/IMAGE'))
        if (-not $images.Count) { throw 'No images found in WIM metadata.' }
        foreach ($image in $images) {
            $windows = $image.SelectSingleNode('WINDOWS')
            if (-not $windows) { throw 'This is not Windows installation image metadata.' }
            $version = $windows.SelectSingleNode('VERSION')
            $build = [int]$version.BUILD
            $languages = @($windows.SelectNodes('LANGUAGES/LANGUAGE') | ForEach-Object { $_.InnerText })
            $language = [string]$windows.LANGUAGES.DEFAULT
            if (-not $language -and $languages.Count) { $language = $languages[0] }
            [pscustomobject]@{
                Index = [int]$image.GetAttribute('INDEX'); Name = [string]$image.NAME
                Edition = [string]$windows.EDITIONID; Flags = [string]$image.FLAGS
                InstallationType = [string]$windows.INSTALLATIONTYPE
                ProductType = [string]$windows.PRODUCTTYPE; ProductSuite = [string]$windows.PRODUCTSUITE
                Architecture = ConvertTo-ArchitectureName ([string]$windows.ARCH)
                Build = $build; Version = '{0}.{1}.{2}.{3}' -f $version.MAJOR,$version.MINOR,$version.BUILD,$version.SPBUILD
                DisplayVersion = Get-WindowsDisplayVersion $build; Is24H2OrLater = ($build -ge 26100)
                Languages = $languages; Language = $language; DefaultLanguage = [string]$windows.LANGUAGES.DEFAULT; SizeBytes = [long]$image.TOTALBYTES
            }
        }
    } finally { $reader.Dispose() }
}

function Get-IsoImageEditions {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Bundled MIT libraries: no first-use download, installation, elevation or cache.
    foreach ($component in 'Streams','Core','Iso9660','Udf') {
        [void][Reflection.Assembly]::LoadFrom((Join-Path $Script:MediaRoot "vendor\DiscUtils\DiscUtils.$component.dll"))
    }
    $iso = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $filesystem = $null; $image = $null
    try {
        if ([DiscUtils.Udf.UdfReader]::Detect($iso)) { $filesystem = [DiscUtils.Udf.UdfReader]::new($iso) }
        else { $iso.Position=0; $filesystem = [DiscUtils.Iso9660.CDReader]::new($iso,$true) }
        $entry = @('sources\install.wim','sources\install.esd' | Where-Object { $filesystem.FileExists($_) } | Select-Object -First 1)
        if (-not $entry.Count) { throw 'The ISO does not contain sources\install.wim or install.esd. Split SWM media needs an explicit image index.' }
        $image = $filesystem.OpenFile($entry[0],[IO.FileMode]::Open,[IO.FileAccess]::Read)
        Read-WimMetadata -Stream $image
    } finally {
        if ($image) { $image.Dispose() }
        if ($filesystem) { $filesystem.Dispose() }
        $iso.Dispose()
    }
}

Export-ModuleMember -Function Get-WindowsReleaseHint, Read-WimMetadata, Get-IsoImageEditions
