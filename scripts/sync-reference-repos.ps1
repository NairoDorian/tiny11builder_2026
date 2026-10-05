#requires -Version 5.1
<#
.SYNOPSIS
    Download/update the studied forks on the branches in data/reference-repos.json.
.DESCRIPTION
    Reference source only: never executes a fork's scripts or changes host setup.
    Existing dirty, detached or divergent checkouts are preserved and reported.
    repos/ remains Git-ignored; a compact version/update audit is committed.
#>
param([string]$ReportPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$references=Get-Content -Raw -LiteralPath (Join-Path $repo 'data\reference-repos.json') | ConvertFrom-Json
$referenceRoot=[IO.Path]::GetFullPath((Join-Path $repo 'repos'))
if (-not $ReportPath) { $ReportPath=Join-Path $repo 'docs\verification\reference-sync.json' }
if ((Test-Path -LiteralPath $referenceRoot) -and ((Get-Item -LiteralPath $referenceRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Refusing redirected reference root.' }
New-Item -ItemType Directory -Path $referenceRoot -Force | Out-Null
$results=New-Object 'System.Collections.Generic.List[object]'
function Invoke-ReferenceGit {
    param([string[]]$Arguments)
    $output=@(& git @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments[0]) failed (exit $LASTEXITCODE)." }
    return $output
}
foreach ($reference in $references) {
    $result=[ordered]@{ Name=$reference.Name; Url=$reference.Url; Branch=$reference.Branch; Before=$null; After=$null; Status=$null; Detail=$null }
    try {
        if ($reference.Name -notmatch '^[A-Za-z0-9_-]+$' -or $reference.Url -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$') { throw 'Unsafe reference name or URL.' }
        $path=[IO.Path]::GetFullPath((Join-Path $referenceRoot $reference.Name))
        if (-not $path.StartsWith($referenceRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Reference checkout is outside repos/.' }
        $null=Invoke-ReferenceGit @('check-ref-format','--branch',$reference.Branch)
        if (Test-Path -LiteralPath $path) {
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Redirected reference checkout.' }
            $origin=(Invoke-ReferenceGit @('-C',$path,'remote','get-url','origin')) -join ''
            if ($origin -ine $reference.Url) { throw 'Existing origin differs from the recorded reference; preserving checkout.' }
            $result.Before=(Invoke-ReferenceGit @('-C',$path,'rev-parse','HEAD')) -join ''
            $dirty=@(Invoke-ReferenceGit @('-C',$path,'status','--porcelain'))
            $branch=(Invoke-ReferenceGit @('-C',$path,'branch','--show-current')) -join ''
            $null=Invoke-ReferenceGit @('-C',$path,'fetch','--quiet','--prune','--no-tags','origin')
            if ($dirty.Count -or $branch -ne $reference.Branch) {
                $result.Status='preserved'; $result.Detail='Dirty/different/detached checkout; fetched remote refs without changing files.'
            } else {
                $null=Invoke-ReferenceGit @('-C',$path,'merge','--ff-only','--quiet',('origin/'+$reference.Branch))
                $result.Status='updated'
            }
        } else {
            $null=Invoke-ReferenceGit @('clone','--quiet','--single-branch','--no-tags','--branch',$reference.Branch,$reference.Url,$path)
            $result.Status='cloned'
        }
        $result.After=(Invoke-ReferenceGit @('-C',$path,'rev-parse','HEAD')) -join ''
        if ($result.Status -eq 'updated' -and $result.Before -eq $result.After) { $result.Status='current' }
    } catch { $result.Status='failed'; $result.Detail=$_.Exception.Message }
    $results.Add([pscustomobject]$result)
    Write-Host "$($result.Name): $($result.Status) $($result.After)"
}
$report=[ordered]@{ Checked=(Get-Date).ToString('o'); Policy='Reference source only; no fork scripts executed. Fast-forward only; modified checkouts preserved.'; Results=$results.ToArray() }
$reportFolder=Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
[IO.File]::WriteAllText($ReportPath,($report | ConvertTo-Json -Depth 6)+"`r`n",(New-Object Text.UTF8Encoding $false))
if (@($results | Where-Object Status -in 'failed','preserved').Count) { throw "Some reference checkouts require attention; see $ReportPath." }
