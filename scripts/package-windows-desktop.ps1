param(
  [string]$DataRoot = "D:\00Docker\multica",
  [ValidateSet("x64", "arm64")]
  [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$downloads = Join-Path $DataRoot "downloads"
New-Item -ItemType Directory -Force -Path $downloads | Out-Null

$makeBin = Join-Path $env:LOCALAPPDATA "Programs\GnuWin32\make-3.81\bin"
$goBin = Join-Path $env:LOCALAPPDATA "Programs\Go\go1.26.1\bin"
$gitUsrBin = "C:\Program Files\Git\usr\bin"
$env:Path = "$makeBin;$gitUsrBin;$goBin;$env:Path"
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
if (-not $env:ELECTRON_BUILDER_BINARIES_MIRROR -and
    -not $env:npm_config_electron_builder_binaries_mirror -and
    -not $env:NPM_CONFIG_ELECTRON_BUILDER_BINARIES_MIRROR) {
  $env:ELECTRON_BUILDER_BINARIES_MIRROR = "https://npmmirror.com/mirrors/electron-builder-binaries/"
}

Write-Host "==> Packaging Windows desktop app ($Arch)"
Push-Location $repoRoot
try {
  pnpm --filter "@multica/desktop" package -- --win "--$Arch" --publish never "--config.win.signAndEditExecutable=false"
} finally {
  Pop-Location
}

if ($LASTEXITCODE -ne 0) {
  throw "Desktop packaging failed"
}

Get-ChildItem -Path $downloads -Filter "multica-desktop-*-windows-*.exe" -File -ErrorAction SilentlyContinue |
  Remove-Item -Force

$dist = Join-Path $repoRoot "apps\desktop\dist"
$installer = Get-ChildItem -Path $dist -Recurse -Filter "multica-desktop-*-windows-$Arch.exe" -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $installer) {
  throw "No Windows installer found under $dist"
}

Copy-Item -LiteralPath $installer.FullName -Destination $downloads -Force
Write-Host "==> Copied $($installer.Name) to $downloads"
