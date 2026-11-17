param(
  [string]$Version = $env:KIMI_VERSION
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = if ($env:SMARTBOX_REPOSITORY) { $env:SMARTBOX_REPOSITORY } else { 'mark-sch/kimi-code' }
$InstallDir = if ($env:KIMI_INSTALL_DIR) { $env:KIMI_INSTALL_DIR } else { Join-Path $env:USERPROFILE '.kimi-code' }
$NoModifyPath = [bool]$env:KIMI_NO_MODIFY_PATH

function Test-Sha256([string]$Path, [string]$Expected) {
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected.ToLowerInvariant()) {
    throw "SHA-256 mismatch for ${Path}: expected $Expected, got $actual"
  }
}

$rawArch = try {
  [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
} catch {
  if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
}
$arch = switch ($rawArch) {
  'X64' { 'x64' }
  'AMD64' { 'x64' }
  'Arm64' { 'arm64' }
  'ARM64' { 'arm64' }
  default { throw "Unsupported Windows architecture: $rawArch" }
}
$target = "win32-$arch"

if ($Version) {
  $tag = if ($Version.StartsWith('smartbox-v')) { $Version } else { "smartbox-v$Version" }
} else {
  Write-Host '==> Resolving latest release'
  $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'Smartbox-AI-Installer' }
  $tag = $latest.tag_name
}
if (-not $tag -or -not $tag.StartsWith('smartbox-v')) {
  throw "Could not resolve a Smartbox AI release tag."
}

$downloadBase = "https://github.com/$Repo/releases/download/$tag"
$manifest = Invoke-RestMethod -Uri "$downloadBase/manifest.json" -Headers @{ 'User-Agent' = 'Smartbox-AI-Installer' }
$entry = $manifest.platforms.$target
if (-not $entry) { throw "Release $tag has no package for $target." }
if ($entry.checksum -notmatch '^[a-f0-9]{64}$') { throw 'Invalid binary checksum in manifest.json.' }

$archive = "kimi-code-$target.zip"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
  Write-Host "==> Downloading $archive from $tag"
  $zipPath = Join-Path $tmp $archive
  Invoke-WebRequest -Uri "$downloadBase/$archive" -OutFile $zipPath -UseBasicParsing
  $checksumPath = "$zipPath.sha256"
  Invoke-WebRequest -Uri "$downloadBase/$archive.sha256" -OutFile $checksumPath -UseBasicParsing
  $archiveChecksum = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
  Test-Sha256 $zipPath $archiveChecksum

  $extractDir = Join-Path $tmp 'extract'
  Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
  $sourceBinary = Join-Path $extractDir 'kimi.exe'
  if (-not (Test-Path -LiteralPath $sourceBinary -PathType Leaf)) {
    throw 'The downloaded package does not contain kimi.exe.'
  }
  Test-Sha256 $sourceBinary $entry.checksum

  $binDir = Join-Path $InstallDir 'bin'
  New-Item -ItemType Directory -Path $binDir -Force | Out-Null
  $binaryDest = Join-Path $binDir 'kimi.exe'
  Copy-Item -LiteralPath $sourceBinary -Destination $binaryDest -Force
  Write-Host "==> Installed $binaryDest"

  $versionOutput = (& $binaryDest --version | Out-String).Trim()
  Write-Host $versionOutput
  $expectedVersion = $tag.Substring('smartbox-v'.Length)
  if ($versionOutput -notlike "*$expectedVersion*") {
    throw "Installed version does not match release $tag."
  }

  if (-not $NoModifyPath) {
    $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = if ($currentPath) { $currentPath.Split(';') } else { @() }
    if ($parts -notcontains $binDir) {
      $newPath = if ($currentPath) { "$binDir;$currentPath" } else { $binDir }
      [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
      Write-Host '==> User PATH updated. Open a new terminal afterwards.'
    }
  }
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Smartbox AI installed successfully. Start Kimi Web with:'
Write-Host '  kimi web --no-open'
Write-Host 'The Windows binary is unsigned; Windows SmartScreen may show a warning.'
