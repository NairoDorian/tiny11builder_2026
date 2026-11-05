#requires -Version 5.1
<#
.SYNOPSIS
    Tests for lib\tiny11download.psm1 (ISO recognition and resumable download).
    No network: Microsoft's page is a fixture and the download goes through an
    in-memory HttpMessageHandler that serves Range requests, ETags and resets.
#>
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'lib\tiny11download.psm1') -Force -DisableNameChecking
Add-Type -AssemblyName System.Net.Http

$script:pass = 0; $script:fail = 0
function Check([string]$name, [bool]$cond) { if ($cond) { $script:pass++ } else { Write-Host "  FAIL: $name" -ForegroundColor Red; $script:fail++ } }
function CheckThrows([string]$name, [scriptblock]$sb) { $threw = $false; try { & $sb | Out-Null } catch { $threw = $true }; Check $name $threw }

$handlerSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;

public class Tiny11FakeIsoServer : HttpMessageHandler
{
    public byte[] Data = new byte[0];
    public string ETag = "\"v1\"";
    public int FailFirstAfter = -1;      // bytes served by the first response before a simulated reset
    public int Requests;
    public List<string> Ranges = new List<string>();
    public string RedirectTo;            // first request answers 302 to this URL

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        Requests++;
        if (RedirectTo != null && Requests == 1)
        {
            HttpResponseMessage redirect = new HttpResponseMessage(HttpStatusCode.Redirect);
            redirect.Headers.Location = new Uri(RedirectTo);
            return Task.FromResult(redirect);
        }
        long from = 0;
        if (request.Headers.Range != null) foreach (RangeItemHeaderValue r in request.Headers.Range.Ranges) from = r.From ?? 0;
        bool ifRangeMatches = request.Headers.IfRange == null || (request.Headers.IfRange.EntityTag != null && request.Headers.IfRange.EntityTag.Tag == ETag);
        if (!ifRangeMatches) from = 0;
        Ranges.Add(from.ToString());
        HttpResponseMessage response = new HttpResponseMessage(from > 0 ? HttpStatusCode.PartialContent : HttpStatusCode.OK);
        byte[] slice = new byte[Data.Length - from];
        Array.Copy(Data, from, slice, 0, slice.Length);
        Stream body = (FailFirstAfter >= 0 && Ranges.Count == 1) ? (Stream)new ResettingStream(slice, FailFirstAfter) : new MemoryStream(slice);
        response.Content = new StreamContent(body);
        response.Content.Headers.ContentLength = slice.Length;
        if (from > 0) response.Content.Headers.ContentRange = new ContentRangeHeaderValue(from, Data.Length - 1, Data.Length);
        response.Headers.ETag = new EntityTagHeaderValue(ETag);
        return Task.FromResult(response);
    }
}

public class ResettingStream : MemoryStream
{
    private readonly int limit;
    public ResettingStream(byte[] data, int limit) : base(data) { this.limit = limit; }
    public override int Read(byte[] buffer, int offset, int count)
    {
        if (Position >= limit) throw new IOException("simulated connection reset");
        return base.Read(buffer, offset, (int)Math.Min(count, limit - Position));
    }
}
'@
# PowerShell 7 references the full .NET reference set by default; 5.1 needs System.Net.Http.
if (-not ('Tiny11FakeIsoServer' -as [type])) {
    if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -TypeDefinition $handlerSource }
    else { Add-Type -TypeDefinition $handlerSource -ReferencedAssemblies 'System.Net.Http' }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("t11-iso-test-$PID-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    Write-Host '== Microsoft hash page parsing =='
    $html = '<p>Version 26H2</p><table><tbody><tr><th>Country Locale</th><th>Hash Code</th></tr>' +
        '<tr><td>English 64-bit</td><td>bd4307df32bc8af33b39ccecb1174aeb345386630f89a2b86c7a4e36b55ea650</td></tr>' +
        '<tr><td>English International 64-bit</td><td>7E3F373BD3C2321B5D5125DFCF718DFBF1A0ABC50A267118669951890DF98A5D</td></tr>' +
        '<tr><td>Chinese&#160;Simplified 64-bit</td><td>' + ('A' * 64) + '</td></tr></tbody></table>'
    $entries = @(ConvertFrom-WindowsIsoHashPage -Html $html -Architecture x64)
    Check 'all hash rows parsed'                     ($entries.Count -eq 3)
    Check 'hash normalised to upper case'            ($entries[0].Sha256 -eq 'BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650')
    Check 'language label without the bitness'       ($entries[0].Language -eq 'English' -and $entries[1].Language -eq 'English International')
    Check 'HTML entities decoded'                    ($entries[2].Language -match 'Chinese.Simplified')
    Check 'release label read from the page'         ($entries[0].Release -eq '26H2' -and $entries[0].Architecture -eq 'x64')
    Check 'a page without the table yields nothing'  (@(ConvertFrom-WindowsIsoHashPage -Html '<html></html>').Count -eq 0)
    $catalog = [pscustomobject]@{ Entries = $entries; Errors = @(); Retrieved = '' }

    Write-Host '== Local ISO recognition (informational) =='
    $iso = Join-Path $root 'sample.iso'
    [IO.File]::WriteAllBytes($iso, [byte[]](1..255))
    $sha = Get-FileSha256WithProgress -Path $iso
    Check 'streamed SHA-256 equals Get-FileHash'     ($sha -eq (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash)
    $progress = [Collections.Generic.List[int]]::new()
    $null = Get-FileSha256WithProgress -Path $iso -OnProgress { param($p) $progress.Add($p) }
    Check 'hash progress reaches 100'                ($progress.Count -ge 1 -and $progress[-1] -eq 100)
    $known = [pscustomobject]@{ Entries = @($entries + [pscustomobject]@{ Architecture = 'x64'; Language = 'Test'; Label = 'Test 64-bit'; Sha256 = $sha; Release = '26H2' }); Errors = @() }
    $result = Test-WindowsIsoAuthenticity -Path $iso -Catalog $known
    Check 'listed hash is Verified'                  ($result.Status -eq 'Verified' -and $result.Language -eq 'Test' -and $result.Message -match 'Official Microsoft ISO')
    $result = Test-WindowsIsoAuthenticity -Path $iso -Catalog $catalog
    Check 'unknown hash is NotListed, not an error'  ($result.Status -eq 'NotListed' -and $result.Message -match 'not affected')
    $result = Test-WindowsIsoAuthenticity -Path $iso -Catalog ([pscustomobject]@{ Entries = @(); Errors = @('offline') })
    Check 'offline is Unavailable and never blocks'  ($result.Status -eq 'Unavailable' -and $result.Message -match 'not affected')
    Check 'precomputed hash is reused'               ((Test-WindowsIsoAuthenticity -Path 'Z:\never\read.iso' -Sha256 $sha -Catalog $known).Status -eq 'Verified')

    Write-Host '== Link and host validation =='
    $good = 'https://software.download.prss.microsoft.com/dbazure/Win11_26H2_English_x64.iso?t=abc&e=1'
    Check 'Microsoft ISO link accepted'              ((Test-MicrosoftIsoUrl -Url $good).Host -eq 'software.download.prss.microsoft.com')
    CheckThrows 'plain HTTP refused'                 { Test-MicrosoftIsoUrl -Url 'http://software.download.prss.microsoft.com/a.iso' }
    CheckThrows 'third-party host refused'           { Test-MicrosoftIsoUrl -Url 'https://example.com/Win11.iso' }
    CheckThrows 'lookalike host refused'             { Test-MicrosoftIsoUrl -Url 'https://software.download.prss.microsoft.com.evil.example/a.iso' }
    CheckThrows 'non-ISO path refused'               { Test-MicrosoftIsoUrl -Url 'https://download.microsoft.com/a.exe' }
    CheckThrows 'credentials in URL refused'         { Test-MicrosoftIsoUrl -Url 'https://user:pw@download.microsoft.com/a.iso' }
    CheckThrows 'non-default port refused'           { Test-MicrosoftIsoUrl -Url 'https://download.microsoft.com:8443/a.iso' }
    Check 'file name taken from the link'            ((Get-IsoFileNameFromUrl -Uri ([uri]$good)) -eq 'Win11_26H2_English_x64.iso')

    Write-Host '== Resumable download through a fake Microsoft server =='
    $data = [byte[]]::new(3MB); (New-Object Random 7).NextBytes($data)
    $dataSha = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($data)) -replace '-', '')
    $dataCatalog = [pscustomobject]@{ Entries = @([pscustomobject]@{ Architecture = 'x64'; Language = 'English'; Label = 'English 64-bit'; Sha256 = $dataSha; Release = '26H2' }); Errors = @() }
    $newClient = { param($server) $c = New-Object System.Net.Http.HttpClient($server); $c }

    $server = New-Object Tiny11FakeIsoServer; $server.Data = $data; $server.FailFirstAfter = 1MB + 12345
    $dest = Join-Path $root 'dl1'
    $saved = Save-WindowsIsoDownload -Url $good -Destination $dest -Client (& $newClient $server) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null
    Check 'interrupted transfer resumed automatically' ($server.Ranges.Count -eq 2 -and $server.Ranges[0] -eq '0' -and [long]$server.Ranges[1] -eq (1MB + 12345))
    Check 'downloaded bytes are exact'               ((Get-FileHash -LiteralPath $saved.Path -Algorithm SHA256).Hash -eq $dataSha)
    Check 'download recognised from the catalog'     ($saved.Verification.Status -eq 'Verified' -and $saved.Verification.Language -eq 'English')
    Check 'part and metadata removed after success'  (-not (Test-Path -LiteralPath "$($saved.Path).part") -and -not (Test-Path -LiteralPath "$($saved.Path).part.json"))
    CheckThrows 'existing ISO is never overwritten'  { Save-WindowsIsoDownload -Url $good -Destination $dest -Client (& $newClient $server) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null }

    # Resume across runs (new link token, same file) from a kept .part.
    $dest2 = Join-Path $root 'dl2'; New-Item -ItemType Directory -Path $dest2 | Out-Null
    $target2 = Join-Path $dest2 'Win11_26H2_English_x64.iso'
    [IO.File]::WriteAllBytes("$target2.part", $data[0..(2MB - 1)])
    [IO.File]::WriteAllText("$target2.part.json", (@{ Resource = 'https://software.download.prss.microsoft.com/dbazure/Win11_26H2_English_x64.iso'; ETag = '"v1"'; Length = $data.Length } | ConvertTo-Json -Compress))
    $server2 = New-Object Tiny11FakeIsoServer; $server2.Data = $data
    $saved2 = Save-WindowsIsoDownload -Url ($good -replace 't=abc', 't=fresh') -Destination $dest2 -Client (& $newClient $server2) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null
    Check 'kept .part resumes with a fresh link'     ($server2.Ranges[0] -eq [string](2MB) -and (Get-FileHash -LiteralPath $saved2.Path -Algorithm SHA256).Hash -eq $dataSha)

    # Changed file on the server (ETag differs): restart from zero, never splice.
    $dest3 = Join-Path $root 'dl3'; New-Item -ItemType Directory -Path $dest3 | Out-Null
    $target3 = Join-Path $dest3 'Win11_26H2_English_x64.iso'
    [IO.File]::WriteAllBytes("$target3.part", [byte[]]::new(1MB))
    [IO.File]::WriteAllText("$target3.part.json", (@{ Resource = 'https://software.download.prss.microsoft.com/dbazure/Win11_26H2_English_x64.iso'; ETag = '"old"'; Length = $data.Length } | ConvertTo-Json -Compress))
    $server3 = New-Object Tiny11FakeIsoServer; $server3.Data = $data
    $saved3 = Save-WindowsIsoDownload -Url $good -Destination $dest3 -Client (& $newClient $server3) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null
    Check 'changed ETag restarts instead of splicing' ($server3.Ranges[0] -eq '0' -and (Get-FileHash -LiteralPath $saved3.Path -Algorithm SHA256).Hash -eq $dataSha)

    # Expected hash mismatch: rejected, partial kept for inspection.
    $dest4 = Join-Path $root 'dl4'
    $server4 = New-Object Tiny11FakeIsoServer; $server4.Data = $data
    CheckThrows 'expected SHA-256 mismatch is rejected' { Save-WindowsIsoDownload -Url $good -Destination $dest4 -ExpectedSha256 ('0' * 64) -Client (& $newClient $server4) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null }
    Check 'rejected download not published as .iso'  (-not (Test-Path -LiteralPath (Join-Path $dest4 'Win11_26H2_English_x64.iso')) -and (Test-Path -LiteralPath (Join-Path $dest4 'Win11_26H2_English_x64.iso.part')))

    # Redirects are followed only to Microsoft hosts.
    $server5 = New-Object Tiny11FakeIsoServer; $server5.Data = $data; $server5.RedirectTo = 'https://evil.example/Win11.iso'
    CheckThrows 'redirect to a non-Microsoft host refused' { Save-WindowsIsoDownload -Url $good -Destination (Join-Path $root 'dl5') -Client (& $newClient $server5) -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null }
    $server6 = New-Object Tiny11FakeIsoServer; $server6.Data = $data; $server6.RedirectTo = 'https://software-static.download.prss.microsoft.com/x/Win11_26H2_English_x64.iso'
    $saved6 = Save-WindowsIsoDownload -Url $good -Destination (Join-Path $root 'dl6') -Client (& $newClient $server6) -RetryDelaySeconds @(0) -SkipVerification 6>$null
    Check 'redirect within Microsoft hosts followed' ((Get-FileHash -LiteralPath $saved6.Path -Algorithm SHA256).Hash -eq $dataSha -and $null -eq $saved6.Verification)

    # Persistent failure gives up after the retry budget and keeps the partial.
    $server7 = New-Object Tiny11FakeIsoServer; $server7.Data = $data; $server7.FailFirstAfter = 100
    $c7 = & $newClient $server7
    CheckThrows 'retry budget is bounded'            { Save-WindowsIsoDownload -Url $good -Destination (Join-Path $root 'dl7') -Client $c7 -Retries 0 -RetryDelaySeconds @(0) -Catalog $dataCatalog 6>$null }
    Check 'partial kept for a later resume'          (Test-Path -LiteralPath (Join-Path $root 'dl7\Win11_26H2_English_x64.iso.part'))

    # A failing progress display must not abort the transfer.
    $server8 = New-Object Tiny11FakeIsoServer; $server8.Data = $data
    $saved8 = Save-WindowsIsoDownload -Url $good -Destination (Join-Path $root 'dl8') -Client (& $newClient $server8) -RetryDelaySeconds @(0) -SkipVerification -OnProgress { param($p) throw 'display broke' } 6>$null 3>$null
    Check 'throwing progress callback does not abort' ($saved8 -and (Get-FileHash -LiteralPath $saved8.Path -Algorithm SHA256).Hash -eq $dataSha)

    Write-Host '== Progress formatting for real ISO sizes (> Int32) =='
    # Same record shape the downloader emits; 9062821888 bytes is a real 26H2 ISO.
    $big = [long]9062821888
    $view = Format-IsoDownloadProgress -Progress ([pscustomobject]@{ Phase = 'download'; Bytes = [long]4531410944; Total = $big; BytesPerSecond = 25MB })
    Check 'percent of a 9 GB total'                  ($view.Percent -eq 50)
    Check 'GB amounts in the status line'            ($view.Text -match '^4[.,]22 of 8[.,]44 GB at 25[.,]0 MB/s, about 0:02:52 left$')
    $view = Format-IsoDownloadProgress -Progress ([pscustomobject]@{ Phase = 'download'; Bytes = [long]0; Total = $big; BytesPerSecond = 50000 })
    Check 'estimates beyond 24 hours are not wrapped' ($view.Percent -eq 0 -and $view.Text -match 'about 50:20:56 left$')
    $view = Format-IsoDownloadProgress -Progress ([pscustomobject]@{ Phase = 'download'; Bytes = [long]1; Total = $big; BytesPerSecond = 0.0000001 })
    Check 'absurd estimate shows ?'                  ($view.Text -match 'about \? left$')
    $view = Format-IsoDownloadProgress -Progress ([pscustomobject]@{ Phase = 'download'; Bytes = $big; Total = $big; BytesPerSecond = 0 })
    Check 'complete download is 100 percent'         ($view.Percent -eq 100 -and $view.Text -match 'about \? left$')
    $view = Format-IsoDownloadProgress -Progress ([pscustomobject]@{ Phase = 'verify'; Bytes = 37; Total = 100; BytesPerSecond = 0 })
    Check 'verify phase reports the hash percent'    ($view.Percent -eq 37 -and $view.Text -match '37%')
    $callers = (Get-Content -Raw -LiteralPath (Join-Path $repo 'lib\tiny11gui.psm1')) + (Get-Content -Raw -LiteralPath (Join-Path $repo 'tiny11iso.ps1'))
    Check 'GUI and CLI share the formatter'          (([regex]::Matches($callers, 'Format-IsoDownloadProgress -Progress \$p')).Count -eq 2 -and $callers -notmatch '\[Math\]::Max\(1, \$p\.Total\)')

    Write-Host '== Assisted "Get Windows 11" hand-off =='
    $watch = Join-Path $root 'watch'; New-Item -ItemType Directory -Path $watch | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $watch 'already-here.iso'), [byte[]]::new(64))
    $baseline = @(Get-ChildItem -LiteralPath $watch -Filter '*.iso' | ForEach-Object FullName)
    $sizes = @{}
    Check 'nothing found while waiting'              ($null -eq (Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory $sizes -MinimumBytes 1))
    $fresh = Join-Path $watch 'Win11_26H2_English_x64.iso'
    [IO.File]::WriteAllBytes($fresh, [byte[]]::new(64))
    Check 'a new file is not taken on first sight'   ($null -eq (Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory $sizes -MinimumBytes 1))
    [IO.File]::WriteAllBytes($fresh, [byte[]]::new(128))
    Check 'a still-growing file keeps waiting'       ($null -eq (Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory $sizes -MinimumBytes 1))
    $hit = Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory $sizes -MinimumBytes 1
    Check 'a finished new ISO is picked up'          ($hit.Kind -eq 'File' -and $hit.Path -eq $fresh)
    Check 'ISOs present before the click are ignored' ($null -eq (Find-OfficialIsoHandoff -Baseline @($baseline + $fresh) -Folder $watch -SizeMemory @{ $fresh = [long]128 } -MinimumBytes 1))
    $locked = [IO.File]::Open($fresh, 'Open', 'ReadWrite', 'None')
    try { Check 'a file still open for writing waits' ($null -eq (Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory @{ $fresh = [long]128 } -MinimumBytes 1)) } finally { $locked.Dispose() }
    Check 'small placeholder files are ignored'      ($null -eq (Find-OfficialIsoHandoff -Baseline $baseline -Folder $watch -SizeMemory @{ $fresh = [long]128 }))
    $link = Find-OfficialIsoHandoff -ClipboardText "  $good  " -Baseline $baseline -Folder $watch -SizeMemory @{}
    Check 'a copied Microsoft link is taken over'    ($link.Kind -eq 'Link' -and $link.Url -like 'https://software.download.prss.microsoft.com/*')
    Check 'a non-Microsoft clipboard link is ignored' ($null -eq (Find-OfficialIsoHandoff -ClipboardText 'https://example.com/Win11.iso' -Baseline $baseline -Folder (Join-Path $root 'none') -SizeMemory @{}))
    Check 'ordinary clipboard text is ignored'       ($null -eq (Find-OfficialIsoHandoff -ClipboardText 'my password 1234' -Baseline $baseline -Folder (Join-Path $root 'none') -SizeMemory @{}))
    $downloads = Get-UserDownloadsFolder
    Check 'the Downloads folder is resolved'          ($downloads -and [IO.Path]::IsPathRooted($downloads))

    Write-Host '== Local ISO discovery =='
    $scan = Join-Path $root 'scan'; New-Item -ItemType Directory -Path $scan | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $scan 'old.iso'), [byte[]]::new(10)); (Get-Item (Join-Path $scan 'old.iso')).LastWriteTime = (Get-Date).AddDays(-3)
    [IO.File]::WriteAllBytes((Join-Path $scan 'new.iso'), [byte[]]::new(10))
    [IO.File]::WriteAllBytes((Join-Path $scan 'notes.txt'), [byte[]]::new(10))
    $found = @(Get-LocalIsoCandidates -Folder $scan -OnlyGivenFolders -MinimumBytes 1)
    Check 'only .iso files, newest first'            ($found.Count -eq 2 -and $found[0].Path -like '*new.iso' -and $found[1].Path -like '*old.iso')
    Check 'small files ignored by default size'      (@(Get-LocalIsoCandidates -Folder $scan -OnlyGivenFolders).Count -eq 0)
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "RESULT: $script:pass ISO download/recognition checks passed, $script:fail failed."
if ($script:fail) { exit 1 }
exit 0
