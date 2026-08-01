[CmdletBinding()]
param(
    [string]$ModelSource = "C:\Users\tianw\.ollama\models",
    [string]$OutputDirectory = "C:\Users\tianw\source\repos\qwen2.5-coder-git"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$manifestRelative = "manifests\registry.ollama.ai\library\qwen2.5-coder\7b"
$manifestSource = Join-Path $ModelSource $manifestRelative
$staging = Join-Path $OutputDirectory "staging"
$stagingModels = Join-Path $staging "models"
$partsDirectory = Join-Path $OutputDirectory "parts"
$archivePath = Join-Path $OutputDirectory "qwen2.5-coder-7b.tar"
$chunkSize = 90MB

if (-not (Test-Path -LiteralPath $manifestSource -PathType Leaf)) {
    throw "Model manifest not found: $manifestSource"
}

New-Item -ItemType Directory -Force -Path (Join-Path $stagingModels "blobs") | Out-Null
$manifestTarget = Join-Path $stagingModels $manifestRelative
New-Item -ItemType Directory -Force -Path (Split-Path $manifestTarget) | Out-Null
New-Item -ItemType Directory -Force -Path $partsDirectory | Out-Null
Copy-Item -LiteralPath $manifestSource -Destination $manifestTarget -Force

$manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
$digests = @($manifest.config.digest)
$digests += @($manifest.layers | ForEach-Object { $_.digest })
$digests = $digests | Sort-Object -Unique

foreach ($digest in $digests) {
    $blobName = $digest.Replace(":", "-")
    $source = Join-Path (Join-Path $ModelSource "blobs") $blobName
    $target = Join-Path (Join-Path $stagingModels "blobs") $blobName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required blob not found: $source"
    }
    Write-Host "Copying $blobName"
    Copy-Item -LiteralPath $source -Destination $target -Force
}

Write-Host "Creating TAR archive..."
& tar -cf $archivePath -C $staging models
if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $partsDirectory "archive.sha256") -Value $archiveHash -Encoding ascii

Write-Host "Splitting archive into 90 MiB parts..."
$input = [IO.File]::OpenRead($archivePath)
try {
    $buffer = New-Object byte[] (4MB)
    $partIndex = 0
    while ($input.Position -lt $input.Length) {
        $partPath = Join-Path $partsDirectory ("qwen2.5-coder-7b.tar.part-{0:D4}" -f $partIndex)
        $output = [IO.File]::Create($partPath)
        try {
            $written = 0L
            while ($written -lt $chunkSize -and $input.Position -lt $input.Length) {
                $wanted = [Math]::Min($buffer.Length, $chunkSize - $written)
                $read = $input.Read($buffer, 0, [int]$wanted)
                if ($read -eq 0) { break }
                $output.Write($buffer, 0, $read)
                $written += $read
            }
        }
        finally {
            $output.Dispose()
        }
        Write-Host ("Created {0} ({1:N2} MiB)" -f (Split-Path $partPath -Leaf), ($written / 1MB))
        $partIndex++
    }
}
finally {
    $input.Dispose()
}

Write-Host "Verifying joined parts..."
$joinedHash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
try {
    Get-ChildItem -LiteralPath $partsDirectory -Filter "*.part-*" | Sort-Object Name | ForEach-Object {
        $stream = [IO.File]::OpenRead($_.FullName)
        try {
            $buffer = New-Object byte[] (4MB)
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $joinedHash.AppendData($buffer, 0, $read)
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    $joinedDigest = [Convert]::ToHexString($joinedHash.GetHashAndReset()).ToLowerInvariant()
}
finally {
    $joinedHash.Dispose()
}

if ($joinedDigest -ne $archiveHash) {
    throw "Part verification failed. Expected $archiveHash, got $joinedDigest"
}

Remove-Item -LiteralPath $archivePath -Force
Remove-Item -LiteralPath $staging -Recurse -Force

$partCount = (Get-ChildItem -LiteralPath $partsDirectory -Filter "*.part-*" -File).Count
$totalBytes = (Get-ChildItem -LiteralPath $partsDirectory -Filter "*.part-*" -File | Measure-Object Length -Sum).Sum
Write-Host "Package ready: $partCount parts, $([Math]::Round($totalBytes / 1GB, 2)) GiB"

