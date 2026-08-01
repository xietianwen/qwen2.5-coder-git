[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryUrl,
    [int]$BatchSize = 8
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

if (-not (Test-Path -LiteralPath ".git" -PathType Container)) {
    git init -b main
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
}

$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) {
    git remote add origin $RepositoryUrl
} elseif ($remote -ne $RepositoryUrl) {
    throw "origin already points to '$remote', not '$RepositoryUrl'"
}

$headExists = git rev-parse --verify HEAD 2>$null
if ($LASTEXITCODE -ne 0) {
    git add .gitignore README.md restore.py build-package.ps1 push-in-batches.ps1 parts/archive.sha256
    git commit -m "Add Qwen model restore tooling"
    if ($LASTEXITCODE -ne 0) { throw "Initial commit failed" }
    git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw "Initial push failed" }
}

$parts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "parts") -Filter "*.part-*" -File | Sort-Object Name)
for ($start = 0; $start -lt $parts.Count; $start += $BatchSize) {
    $end = [Math]::Min($start + $BatchSize - 1, $parts.Count - 1)
    $batch = @($parts[$start..$end])
    $untracked = @(
        foreach ($part in $batch) {
            git ls-files --error-unmatch -- $part.FullName *> $null
            if ($LASTEXITCODE -ne 0) { $part }
        }
    )
    if ($untracked.Count -eq 0) {
        Write-Host "Skipping already committed batch $start-$end"
        continue
    }

    git add -- $untracked.FullName
    if ($LASTEXITCODE -ne 0) { throw "git add failed for batch $start-$end" }
    git commit -m ("Add Qwen model parts {0:D4}-{1:D4}" -f $start, $end)
    if ($LASTEXITCODE -ne 0) { throw "git commit failed for batch $start-$end" }
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw "git push failed for batch $start-$end; rerun this script to resume" }
}

Write-Host "All model parts pushed successfully." -ForegroundColor Green
