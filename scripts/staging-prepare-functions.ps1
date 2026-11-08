param([Parameter(Mandatory = $true)][string]$Archive, [Parameter(Mandatory = $true)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$expectedDestination = Join-Path $workspace 'build/staging/functions'
if ([IO.Path]::GetFullPath($Destination) -ne $expectedDestination) { throw 'Unexpected staging artifact destination.' }
$archiveRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'build/staging/deployed-source')) + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath($Archive).StartsWith($archiveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected source evidence path.' }
$zip = [IO.Compression.ZipFile]::OpenRead($Archive)
try {
  foreach ($entry in $zip.Entries) {
    if ($entry.FullName.EndsWith('/')) { continue }
    if ($entry.FullName -match '(^/|\\|(^|/)\.\.(/|$)|(^|/)\.env|(^|/)node_modules/)' -or $entry.Length -gt 10000000) { throw 'Unsafe reviewed artifact entry.' }
    $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
    if (-not $target.StartsWith($expectedDestination + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Source path escapes artifact directory.' }
    if (Test-Path -LiteralPath $target) { continue }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
    $sourceStream = $entry.Open()
    $targetStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
    try { $sourceStream.CopyTo($targetStream) } finally { $sourceStream.Dispose(); $targetStream.Dispose() }
  }
} finally { $zip.Dispose() }
