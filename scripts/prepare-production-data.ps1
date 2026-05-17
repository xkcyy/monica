param(
  [string]$DataRoot = "D:\00Docker\multica",
  [string]$SourceVolume = "multica_pgdata",
  [string]$SourceContainer = "multica-postgres-1",
  [string]$PostgresUser = "multica"
)

$ErrorActionPreference = "Stop"

$postgresData = Join-Path $DataRoot "postgres\data"
$uploads = Join-Path $DataRoot "backend\uploads"
$downloads = Join-Path $DataRoot "downloads"
$backups = Join-Path $DataRoot "backups"

foreach ($dir in @($postgresData, $uploads, $downloads, $backups)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$containerExists = $false
docker inspect $SourceContainer *> $null
if ($LASTEXITCODE -eq 0) {
  $containerExists = $true
  $backupPath = Join-Path $backups "pgdumpall-$timestamp.sql"
  Write-Host "==> Writing logical database backup to $backupPath"
  docker exec $SourceContainer pg_dumpall -U $PostgresUser |
    Set-Content -Path $backupPath -Encoding utf8
  if ($LASTEXITCODE -ne 0) {
    throw "pg_dumpall failed for container $SourceContainer"
  }
}

$hasExistingBindData = Test-Path (Join-Path $postgresData "PG_VERSION")
if ($hasExistingBindData) {
  Write-Host "==> Existing bind-mounted PostgreSQL data found at $postgresData; leaving it untouched."
  exit 0
}

docker volume inspect $SourceVolume *> $null
$volumeExists = $LASTEXITCODE -eq 0
if (-not $volumeExists) {
  Write-Host "==> No source volume named $SourceVolume found. PostgreSQL will initialize a fresh data directory at $postgresData."
  exit 0
}

if ($containerExists) {
  $running = docker inspect -f "{{.State.Running}}" $SourceContainer
  if ($running -eq "true") {
    Write-Host "==> Stopping $SourceContainer for a consistent physical data copy."
    docker stop $SourceContainer | Out-Null
  }
}

Write-Host "==> Copying $SourceVolume into $postgresData"
$mountTo = "${postgresData}:/to"
docker run --rm -v "${SourceVolume}:/from:ro" -v $mountTo alpine sh -c "cp -a /from/. /to/"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to copy PostgreSQL volume $SourceVolume into $postgresData"
}

Write-Host "==> PostgreSQL data prepared under $postgresData"
