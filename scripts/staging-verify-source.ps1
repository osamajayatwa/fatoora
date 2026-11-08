param([string]$ArtifactDirectory = '', [string]$SourceDirectory = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$workspace = Split-Path -Parent $PSScriptRoot
if (-not $ArtifactDirectory) { $ArtifactDirectory = Join-Path $workspace 'build/staging/deployed-source' }
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $workspace 'functions' }
$resolvedArtifacts = [IO.Path]::GetFullPath($ArtifactDirectory)
$resolvedSource = [IO.Path]::GetFullPath($SourceDirectory)
if ($resolvedArtifacts -notin @((Join-Path $workspace 'build/staging/deployed-source'), (Join-Path $workspace 'build/staging/deployed-source/runtime-compatible')) -or
    $resolvedSource -notin @((Join-Path $workspace 'functions'), (Join-Path $workspace 'build/staging/functions'))) { throw 'Unexpected artifact/source verification scope.' }
$fileCount = 0
$archiveCount = 0
foreach ($file in Get-ChildItem -LiteralPath $resolvedArtifacts -Filter '*.zip' -File) {
  if ($file.BaseName -notmatch '^[a-f0-9]{64}$') { throw 'Unowned archive filename.' }
  $zip = [IO.Compression.ZipFile]::OpenRead($file.FullName)
  try {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries) {
      if ($entry.FullName.EndsWith('/')) { continue }
      $name = $entry.FullName
      if ($name -match '(^/|\\|(^|/)\.\.(/|$)|(^|/)\.env|(^|/)node_modules/|(^|/)scripts/|(^|/)test/)' -or
          -not $seen.Add($name) -or $entry.Length -gt 10000000) { throw 'Unreviewed or unsafe source archive entry.' }
      $localFile = Join-Path $resolvedSource $name
      if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) { throw "Unreviewed source file in deployed artifact: $name" }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
      finally { $stream.Dispose(); $sha.Dispose() }
      $expected = (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($actual -ne $expected) { throw "Deployed source content differs: $name" }
      $fileCount++
    }
    foreach ($required in @('package.json', 'package-lock.json', 'lib/index.js', 'src/index.ts')) {
      if (-not $seen.Contains($required)) { throw "Required source artifact entry missing: $required" }
    }
    $archiveCount++
  } finally { $zip.Dispose() }
}
if ($archiveCount -lt 1) { throw 'No verified source archives.' }
[PSCustomObject]@{verifiedArchives=$archiveCount;verifiedFiles=$fileCount;allFilesMatchLocalArtifact=$true} | ConvertTo-Json -Compress
