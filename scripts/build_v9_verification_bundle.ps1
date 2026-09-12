param(
  [Parameter(Mandatory = $true)][string]$PackageId,
  [Parameter(Mandatory = $true)][string]$UpgradeDigest,
  [string]$ReleaseLabel = "v13",
  [string]$OutputDirectory = "verification"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$output = Join-Path $root $OutputDirectory
$stage = Join-Path $env:TEMP ("bten-" + $ReleaseLabel + "-verification-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
  # The currently pinned Sui CLI accepts --dependencies-are-root on publish,
  # not on `move build`; the locally pinned Cetus interface still produces the
  # exact bytecode used by the publish transaction.
  & sui move build
  foreach ($item in @('Move.toml', 'Move.lock', 'Published.toml', 'sources', 'assets', 'config')) {
    Copy-Item -Recurse -Force (Join-Path $root $item) (Join-Path $stage $item)
  }
  $bytecode = Join-Path $root 'build\bten\bytecode_modules\bten.mv'
  $buildInfo = Join-Path $root 'build\bten\BuildInfo.yaml'
  if (!(Test-Path -LiteralPath $bytecode) -or !(Test-Path -LiteralPath $buildInfo)) { throw 'Move build did not produce BTEN bytecode and build metadata' }
  New-Item -ItemType Directory -Force -Path (Join-Path $stage 'bytecode') | Out-Null
  Copy-Item -Force $bytecode (Join-Path $stage 'bytecode\bten.mv')
  Copy-Item -Force $buildInfo (Join-Path $stage 'bytecode\BuildInfo.yaml')
  $files = Get-ChildItem -Recurse -File $stage | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($stage.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLowerInvariant() }
  }
  [ordered]@{
    network = 'mainnet'; packageId = $PackageId; upgradeDigest = $UpgradeDigest
    generatedAtUtc = [DateTime]::UtcNow.ToString('o'); files = $files
  } | ConvertTo-Json -Depth 5 | Set-Content -NoNewline (Join-Path $stage 'manifest.json')
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $zip = Join-Path $output ("BTEN-mainnet-" + $ReleaseLabel + "-verification.zip")
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
  Write-Output $zip
} finally {
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
