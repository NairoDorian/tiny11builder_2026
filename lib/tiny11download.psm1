#requires -Version 5.1
<#
.SYNOPSIS
    Official Windows 11 ISO recognition and download helpers (no admin needed).

.DESCRIPTION
    Everything here is OPTIONAL and informational. A local ISO always works
    offline; recognition only adds "this is Microsoft's published file".

      * Get-WindowsIsoHashCatalog reads the public "Verify your download" table
        (language -> SHA-256) from Microsoft's static Windows 11 download pages
        for x64 and ARM64. That table only lists the CURRENT public release, so
        an older official ISO is reported as "not in the current list", never
        as fake.
      * Test-WindowsIsoAuthenticity hashes a local ISO (streamed, with progress)
        and looks it up in that table.
      * Save-WindowsIsoDownload downloads from a direct Microsoft ISO link that
        the user obtained on Microsoft's page in a browser. Microsoft hosts only,
        every redirect checked, strong-ETag resume of .part files, free-space
        check, SHA-256 verification, no overwrite.
      * Find-OfficialIsoHandoff powers the assisted "Get Windows 11" flow: it
        notices the link the user copies, or the ISO their browser finishes,
        and takes over.
#>

$Script:IsoPages = @{
    x64   = 'https://www.microsoft.com/en-us/software-download/windows11'
    arm64 = 'https://www.microsoft.com/en-us/software-download/windows11arm64'
}
$Script:PageHosts = @('www.microsoft.com')
$Script:IsoHosts = @('software.download.prss.microsoft.com', 'software-static.download.prss.microsoft.com', 'download.microsoft.com')
$Script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Tiny11Builder/2026.11 (PowerShell)'

function Get-OfficialIsoPage {
    # Microsoft's official download page for a person to use in a browser.
    param([ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
    return $Script:IsoPages[$Architecture]
}

function New-Tiny11HttpClient {
    # Redirects are followed manually so every hop's host can be checked.
    param([int]$TimeoutSeconds = 60)
    Add-Type -AssemblyName System.Net.Http
    # Process-level only (PS 5.1 / .NET Framework defaults can lack TLS 1.2).
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd($Script:UserAgent)
    return $client
}

function Test-AllowedHttpsUri {
    param([Parameter(Mandatory = $true)][uri]$Uri, [Parameter(Mandatory = $true)][string[]]$AllowedHosts)
    return ($Uri.IsAbsoluteUri -and $Uri.Scheme -eq 'https' -and $Uri.IsDefaultPort -and -not $Uri.UserInfo -and
        $AllowedHosts -contains $Uri.IdnHost.ToLowerInvariant())
}

function Invoke-Tiny11HttpGetString {
    # Small bounded GET (pages only): HTTPS, allow-listed hosts on every hop.
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [string[]]$AllowedHosts = $Script:PageHosts,
        [int]$MaxBytes = 4MB,
        [int]$TimeoutSeconds = 30
    )
    $client = New-Tiny11HttpClient -TimeoutSeconds $TimeoutSeconds
    try {
        for ($hop = 0; $hop -lt 5; $hop++) {
            if (-not (Test-AllowedHttpsUri -Uri $Uri -AllowedHosts $AllowedHosts)) { throw "Refusing request to an unexpected host: $($Uri.Host)" }
            $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                $code = [int]$response.StatusCode
                if ($code -in 301, 302, 303, 307, 308) {
                    if (-not $response.Headers.Location) { throw 'Empty redirect.' }
                    $Uri = if ($response.Headers.Location.IsAbsoluteUri) { $response.Headers.Location } else { [uri]::new($Uri, $response.Headers.Location) }
                    continue
                }
                if ($code -lt 200 -or $code -ge 300) { throw "HTTP $code from $($Uri.Host)." }
                $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $memory = New-Object System.IO.MemoryStream
                try {
                    $buffer = [byte[]]::new(65536)
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ($memory.Length + $read -gt $MaxBytes) { throw "Response from $($Uri.Host) is larger than expected." }
                        $memory.Write($buffer, 0, $read)
                    }
                    return [Text.Encoding]::UTF8.GetString($memory.ToArray())
                } finally { $stream.Dispose(); $memory.Dispose() }
            } finally { $response.Dispose() }
        }
        throw 'Too many redirects.'
    } finally { $client.Dispose() }
}

function ConvertFrom-WindowsIsoHashPage {
    # Parses the "Hash values for the ISO files for Each Language" table and the
    # release label ("Version 26H2") of a Microsoft Windows 11 download page.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Html, [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
    $release = [regex]::Match($Html, '(?i)Version\s+(\d{2}H\d)').Groups[1].Value
    $entries = foreach ($row in [regex]::Matches($Html, '(?is)<tr>\s*<td>\s*([^<]+?)\s*</td>\s*<td>\s*([A-Fa-f0-9]{64})\s*</td>\s*</tr>')) {
        $label = [Net.WebUtility]::HtmlDecode(($row.Groups[1].Value -replace '\s+', ' ').Trim())
        [pscustomobject]@{
            Architecture = $Architecture
            Language     = ($label -replace '(?i)\s*(64|32)-bit$', '').Trim()
            Label        = $label
            Sha256       = $row.Groups[2].Value.ToUpperInvariant()
            Release      = $release
        }
    }
    return @($entries)
}

function Get-WindowsIsoHashCatalog {
    # Never throws: offline or a changed page yields Entries = @() plus Errors.
    param([ValidateSet('x64', 'arm64')][string[]]$Architecture = @('x64', 'arm64'), [int]$TimeoutSeconds = 30)
    $entries = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($arch in $Architecture) {
        try {
            $html = Invoke-Tiny11HttpGetString -Uri $Script:IsoPages[$arch] -TimeoutSeconds $TimeoutSeconds
            $found = @(ConvertFrom-WindowsIsoHashPage -Html $html -Architecture $arch)
            if (-not $found.Count) { $errors.Add("$arch : Microsoft's page no longer contains the hash table.") }
            foreach ($entry in $found) { $entries.Add($entry) }
        } catch { $errors.Add("$arch : $($_.Exception.Message)") }
    }
    return [pscustomobject]@{ Entries = $entries.ToArray(); Errors = $errors.ToArray(); Retrieved = (Get-Date).ToString('o') }
}

function Find-WindowsIsoHash {
    param([Parameter(Mandatory = $true)][string]$Sha256, $Catalog)
    $wanted = $Sha256.Trim().ToUpperInvariant()
    return (@($Catalog.Entries) | Where-Object { $_.Sha256 -eq $wanted } | Select-Object -First 1)
}

function Get-FileSha256WithProgress {
    # Streamed SHA-256; $OnProgress receives a 0..100 percent about every 2 %.
    param([Parameter(Mandatory = $true)][string]$Path, [scriptblock]$OnProgress)
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 4MB, [IO.FileOptions]::SequentialScan)
    try {
        $buffer = [byte[]]::new(8MB); $done = [long]0; $total = [Math]::Max([long]1, $stream.Length); $last = -1
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha.TransformBlock($buffer, 0, $read, $null, 0)
            $done += $read
            $percent = [int](100 * $done / $total)
            if ($OnProgress -and $percent -ge $last + 2) { $last = $percent; & $OnProgress $percent }
        }
        [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return ([BitConverter]::ToString($sha.Hash) -replace '-', '')
    } finally { $stream.Dispose(); $sha.Dispose() }
}

function Test-WindowsIsoAuthenticity {
    # Status: Verified | NotListed | Unavailable. Informational only: no caller
    # may refuse to build because of it.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Sha256,
        $Catalog,
        [scriptblock]$OnProgress
    )
    if (-not $Sha256) { $Sha256 = Get-FileSha256WithProgress -Path $Path -OnProgress $OnProgress }
    if (-not $Catalog) { $Catalog = Get-WindowsIsoHashCatalog }
    $match = if (@($Catalog.Entries).Count) { Find-WindowsIsoHash -Sha256 $Sha256 -Catalog $Catalog } else { $null }
    $status = if ($match) { 'Verified' } elseif (@($Catalog.Entries).Count) { 'NotListed' } else { 'Unavailable' }
    $message = switch ($status) {
        'Verified'    { "Official Microsoft ISO: Windows 11 $($match.Release) $($match.Label) ($($match.Architecture))." }
        'NotListed'   { "Not in Microsoft's current download list ($(@($Catalog.Entries)[0].Release)). It may be an older or Insider release, another channel, or a modified file. The build is not affected." }
        'Unavailable' { "Microsoft's hash list could not be reached (offline?). The build is not affected." }
    }
    return [pscustomobject]@{
        Status = $status; Sha256 = $Sha256.ToUpperInvariant(); Message = $message
        Language = $match.Language; Architecture = $match.Architecture; Release = $match.Release; Errors = @($Catalog.Errors)
    }
}

function Test-MicrosoftIsoUrl {
    # A direct ISO link from Microsoft's download page (valid about 24 hours).
    param([Parameter(Mandatory = $true)][string]$Url)
    $uri = $null
    if (-not [uri]::TryCreate($Url.Trim(), [UriKind]::Absolute, [ref]$uri) -or -not (Test-AllowedHttpsUri -Uri $uri -AllowedHosts $Script:IsoHosts) -or
        $uri.Fragment -or [IO.Path]::GetExtension($uri.AbsolutePath) -ne '.iso') {
        throw "Paste the direct HTTPS .iso link from Microsoft's download page (hosts: $($Script:IsoHosts -join ', ')). Other sites are not accepted."
    }
    return $uri
}

function Get-IsoFileNameFromUrl {
    param([Parameter(Mandatory = $true)][uri]$Uri)
    $name = [Uri]::UnescapeDataString([IO.Path]::GetFileName($Uri.AbsolutePath))
    if (-not $name -or $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'Microsoft returned an unusable ISO file name.' }
    return $name
}

function Test-TransientDownloadError {
    # Network hiccups worth a resume. PowerShell wraps .NET exceptions in
    # MethodInvocationException, so the whole InnerException chain is checked.
    param([Parameter(Mandatory = $true)]$ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception) {
        if ($exception -is [System.Net.Http.HttpRequestException] -or $exception -is [IO.IOException] -or
            $exception -is [Threading.Tasks.TaskCanceledException] -or $exception -is [Net.Sockets.SocketException]) { return $true }
        $exception = $exception.InnerException
    }
    return ([string]$ErrorRecord.Exception.Message -match 'ended early')
}

function Save-WindowsIsoDownload {
    # Downloads a Microsoft ISO link to $Destination (folder or .iso path).
    # Interrupted downloads keep <name>.iso.part + .part.json and resume with the
    # same (or a fresh) link to the same file, as long as Microsoft's strong
    # ETag is unchanged. $OnProgress gets @{ Bytes; Total; BytesPerSecond; Phase }.
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ExpectedSha256,
        [scriptblock]$OnProgress,
        [switch]$SkipVerification,
        [int]$Retries = 4,
        # Test seams: an injected HttpClient (not disposed here), retry delays and a hash catalog.
        $Client,
        [int[]]$RetryDelaySeconds = @(2, 5, 10, 20, 30),
        $Catalog
    )
    $uri = Test-MicrosoftIsoUrl -Url $Url
    $target = if ((Test-Path -LiteralPath $Destination -PathType Container) -or -not ([IO.Path]::GetExtension($Destination) -eq '.iso')) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Join-Path ([IO.Path]::GetFullPath($Destination)) (Get-IsoFileNameFromUrl -Uri $uri)
    } else { [IO.Path]::GetFullPath($Destination) }
    if (Test-Path -LiteralPath $target) { throw "$target already exists; existing files are never overwritten. Choose another folder or delete it first." }
    $part = "$target.part"; $meta = "$part.json"
    $resource = $uri.GetLeftPart([UriPartial]::Path)
    $saved = $null
    if ((Test-Path -LiteralPath $part) -and (Test-Path -LiteralPath $meta)) {
        try { $saved = Get-Content -Raw -LiteralPath $meta | ConvertFrom-Json } catch { $saved = $null }
    }
    if ($saved -and ($saved.Resource -ne $resource -or -not $saved.ETag -or $saved.ETag -like 'W/*')) {
        Remove-Item -LiteralPath $part, $meta -Force -ErrorAction SilentlyContinue; $saved = $null
    }
    if (-not $saved -and (Test-Path -LiteralPath $part)) { Remove-Item -LiteralPath $part -Force }
    $ownsClient = -not $Client
    $client = if ($Client) { $Client } else { New-Tiny11HttpClient -TimeoutSeconds 3600 }
    $attempt = 0
    try {
        while ($true) {
            $offset = if (Test-Path -LiteralPath $part) { (Get-Item -LiteralPath $part).Length } else { [long]0 }
            try {
                $response = $null; $current = $uri
                for ($hop = 0; $hop -lt 6; $hop++) {
                    $null = Test-MicrosoftIsoUrl -Url $current.AbsoluteUri
                    $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $current)
                    if ($offset -gt 0 -and $saved.ETag) {
                        $request.Headers.Range = New-Object System.Net.Http.Headers.RangeHeaderValue($offset, $null)
                        $request.Headers.IfRange = New-Object System.Net.Http.Headers.RangeConditionHeaderValue([System.Net.Http.Headers.EntityTagHeaderValue]::Parse($saved.ETag))
                    }
                    $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    $code = [int]$response.StatusCode
                    if ($code -notin 301, 302, 303, 307, 308) { break }
                    $next = $response.Headers.Location; $response.Dispose(); $response = $null
                    if (-not $next) { throw 'Microsoft returned an empty redirect.' }
                    $current = if ($next.IsAbsoluteUri) { $next } else { [uri]::new($current, $next) }
                }
                if (-not $response) { throw 'Too many download redirects.' }
                $code = [int]$response.StatusCode
                if ($code -eq 416 -and $offset -gt 0 -and $response.Content.Headers.ContentRange.Length -eq $offset) { $response.Dispose(); break }
                if ($code -eq 403 -or $code -eq 410) { throw "Microsoft refused the link (HTTP $code). Links expire after about 24 hours: get a fresh link from the download page; the partial file is kept and resumes." }
                if ($code -ne 200 -and $code -ne 206) { throw "Unexpected download response HTTP $code." }
                if ($code -eq 206 -and $response.Content.Headers.ContentRange.From -ne $offset) { throw 'The server resumed at an unexpected position.' }
                if ($code -eq 200) { $offset = 0 }
                $total = if ($response.Content.Headers.ContentRange -and $response.Content.Headers.ContentRange.Length) { [long]$response.Content.Headers.ContentRange.Length }
                         elseif ($response.Content.Headers.ContentLength) { [long]$response.Content.Headers.ContentLength + $offset } else { [long]0 }
                if ($total -le 0 -or $total -gt 32GB) { throw 'The ISO size reported by Microsoft is invalid.' }
                $root = [IO.Path]::GetPathRoot($target)
                if ($root -match '^[A-Za-z]:\\$') {   # DriveInfo rejects UNC roots; shares are checked by the write itself
                    $drive = [IO.DriveInfo]::new($root)
                    if ($drive.AvailableFreeSpace -lt ($total - $offset + 1GB)) { throw ("Not enough free space on {0}: {1:N1} GB needed (plus a 1 GB margin)." -f $drive.Name, (($total - $offset) / 1GB)) }
                }
                $etag = if ($response.Headers.ETag) { $response.Headers.ETag.ToString() } else { '' }
                [IO.File]::WriteAllText($meta, (@{ Resource = $resource; ETag = $etag; Length = $total } | ConvertTo-Json -Compress))
                $saved = [pscustomobject]@{ Resource = $resource; ETag = $etag; Length = $total }
                $netStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $output = New-Object IO.FileStream($part, $(if ($offset -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }), [IO.FileAccess]::Write, [IO.FileShare]::None, 1MB)
                try {
                    $buffer = [byte[]]::new(1MB); $written = $offset; $clock = [Diagnostics.Stopwatch]::StartNew(); $lastReport = -1.0; $startBytes = $offset
                    while (($read = $netStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $output.Write($buffer, 0, $read); $written += $read
                        if ($written -gt $total) { throw 'The server sent more data than the advertised ISO size.' }
                        if ($OnProgress -and $clock.Elapsed.TotalSeconds - $lastReport -ge 0.5) {
                            $lastReport = $clock.Elapsed.TotalSeconds
                            & $OnProgress ([pscustomobject]@{ Phase = 'download'; Bytes = $written; Total = $total; BytesPerSecond = ($written - $startBytes) / [Math]::Max(0.001, $clock.Elapsed.TotalSeconds) })
                        }
                    }
                    $output.Flush($true)
                } finally { $output.Dispose(); $netStream.Dispose(); $response.Dispose() }
                if ((Get-Item -LiteralPath $part).Length -ne $total) { throw 'The download ended early.' }
                break
            } catch {
                $attempt++
                if (-not (Test-TransientDownloadError -ErrorRecord $_) -or $attempt -gt $Retries) { throw }
                $wait = $RetryDelaySeconds[[Math]::Min($attempt - 1, $RetryDelaySeconds.Count - 1)]
                Write-Host "Connection problem ($($_.Exception.Message)); resuming in $wait s (attempt $attempt of $Retries)..."
                if ($wait -gt 0) { Start-Sleep -Seconds $wait }
            }
        }
    } finally { if ($ownsClient) { $client.Dispose() } }

    $verification = $null
    if (-not $SkipVerification) {
        $hashProgress = if ($OnProgress) { { param($p) & $OnProgress ([pscustomobject]@{ Phase = 'verify'; Bytes = $p; Total = 100; BytesPerSecond = 0 }) }.GetNewClosure() } else { $null }
        $sha = Get-FileSha256WithProgress -Path $part -OnProgress $hashProgress
        if ($ExpectedSha256 -and $sha -ne $ExpectedSha256.Trim().ToUpperInvariant()) {
            throw "SHA-256 mismatch ($sha). The file was kept as $part and NOT accepted; delete it and download again."
        }
        $verification = Test-WindowsIsoAuthenticity -Path $part -Sha256 $sha -Catalog $Catalog
    }
    [IO.File]::Move($part, $target)
    Remove-Item -LiteralPath $meta -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Path = $target; Bytes = (Get-Item -LiteralPath $target).Length; Verification = $verification }
}

function Get-UserDownloadsFolder {
    # The user's real Downloads folder (it can be relocated), read-only from the
    # per-user shell-folder registry key; falls back to %USERPROFILE%\Downloads.
    $known = '{374DE290-123F-4565-9164-39C4925E467B}'
    foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
                     'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders') {
        try {
            $value = (Get-ItemProperty -LiteralPath $key -Name $known -ErrorAction Stop).$known
            $path = [Environment]::ExpandEnvironmentVariables([string]$value)
            if ($path -and (Test-Path -LiteralPath $path -PathType Container)) { return $path }
        } catch { Write-Verbose "Downloads folder from ${key}: $_" }
    }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Find-OfficialIsoHandoff {
    # Assisted "one-click" download. The user picks the ISO on Microsoft's page
    # in their own browser; this notices the result, on each poll:
    #   1. a Microsoft ISO link copied to the clipboard -> @{ Kind='Link'; Url }
    #   2. a NEW .iso finished in the watched folder   -> @{ Kind='File'; Path }
    # A file counts as finished when its size is unchanged since the previous
    # poll and nothing holds it open for writing (browsers rename .crdownload /
    # .part to .iso only at the end). Returns $null while still waiting.
    param(
        [string]$ClipboardText,
        [string[]]$Baseline = @(),
        [string]$Folder,
        [Parameter(Mandatory = $true)][hashtable]$SizeMemory,
        [long]$MinimumBytes = 1GB
    )
    if ($ClipboardText -and $ClipboardText.Trim() -match '^https://\S+$') {
        try { return [pscustomobject]@{ Kind = 'Link'; Url = (Test-MicrosoftIsoUrl -Url $ClipboardText.Trim()).AbsoluteUri } }
        catch { Write-Verbose 'Clipboard holds a non-Microsoft link; ignored.' }
    }
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder -PathType Container)) { return $null }
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Filter '*.iso' -File -ErrorAction SilentlyContinue)) {
        if ($Baseline -contains $file.FullName -or $file.Length -lt $MinimumBytes) { continue }
        if ($SizeMemory[$file.FullName] -ne $file.Length) { $SizeMemory[$file.FullName] = $file.Length; continue }
        try { ([IO.File]::Open($file.FullName, 'Open', 'Read', 'Read')).Dispose() } catch { continue }
        return [pscustomobject]@{ Kind = 'File'; Path = $file.FullName }
    }
    return $null
}

function Get-LocalIsoCandidates {
    # Windows ISOs already on this PC (top level of Downloads/Desktop and any
    # extra folders), newest first. Read-only; nothing is opened or hashed.
    param([string[]]$Folder = @(), [int]$Max = 15, [long]$MinimumBytes = 1GB, [switch]$OnlyGivenFolders)
    $defaults = if ($OnlyGivenFolders) { @() } else { @((Get-UserDownloadsFolder), [Environment]::GetFolderPath('Desktop')) }
    $folders = @($Folder) + $defaults | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    $files = foreach ($dir in $folders) { Get-ChildItem -LiteralPath $dir -Filter '*.iso' -File -ErrorAction SilentlyContinue }
    return @($files | Where-Object { $_.Length -ge $MinimumBytes } | Sort-Object LastWriteTime -Descending | Select-Object -First $Max |
        ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Bytes = $_.Length; LastWriteTime = $_.LastWriteTime } })
}

Export-ModuleMember -Function *-*
