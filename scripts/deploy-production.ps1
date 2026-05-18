#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = "",

  [ValidateNotNullOrEmpty()]
  [string]$Remote = "origin",

  [ValidateNotNullOrEmpty()]
  [string]$Branch = "main",

  [ValidateNotNullOrEmpty()]
  [string]$ComposeFile = "docker-compose.production.yml",

  [string]$ExpectedCommit = "",

  [ValidateNotNullOrEmpty()]
  [string]$AppUrl = "http://localhost:60089",

  [ValidateRange(10, 900)]
  [int]$HealthTimeoutSeconds = 180,

  [switch]$SkipPull,
  [switch]$SkipCompose,
  [switch]$SkipHealthCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $scriptRoot = $PSScriptRoot
  if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  }

  $RepoRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
}

function Write-Section {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Invoke-External {
  param(
    [ValidateNotNullOrEmpty()]
    [string]$FilePath,

    [string[]]$Arguments = @()
  )

  Write-Host "+ $FilePath $($Arguments -join ' ')"
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath failed with exit code $LASTEXITCODE"
  }
}

function Get-GitOutput {
  param([string[]]$Arguments)

  $output = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    $message = ($output | Out-String).Trim()
    throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE. $message"
  }

  return ($output | Out-String).Trim()
}

function Test-GitSuccess {
  param([string[]]$Arguments)

  & git @Arguments *> $null
  return $LASTEXITCODE -eq 0
}

function Assert-CommandExists {
  param([string]$CommandName)

  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    throw "Required command '$CommandName' was not found on PATH."
  }
}

function Assert-CleanTrackedWorktree {
  $dirtyTracked = Get-GitOutput @("status", "--porcelain", "--untracked-files=no")
  if (-not [string]::IsNullOrWhiteSpace($dirtyTracked)) {
    throw @"
Production checkout has uncommitted tracked changes:
$dirtyTracked

Commit or stash tracked changes before deploying. Ignored files such as .env are allowed.
"@
  }
}

function Update-ProductionCheckout {
  if ($SkipPull) {
    Write-Section "Skipping git update"
    return
  }

  Write-Section "Checking production checkout"
  Assert-CleanTrackedWorktree

  if ($PSCmdlet.ShouldProcess("$RepoRoot", "fetch and fast-forward $Branch from $Remote")) {
    Invoke-External "git" @("fetch", "--prune", $Remote, $Branch)

    $currentBranch = Get-GitOutput @("branch", "--show-current")
    if ($currentBranch -ne $Branch) {
      Invoke-External "git" @("switch", $Branch)
    }

    $targetRef = "$Remote/$Branch"
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit)) {
      $expectedCommitRef = "$ExpectedCommit^{commit}"
      Get-GitOutput @("rev-parse", "--verify", $expectedCommitRef) | Out-Null

      if (-not (Test-GitSuccess @("merge-base", "--is-ancestor", $ExpectedCommit, $targetRef))) {
        throw "Expected commit $ExpectedCommit is not reachable from $targetRef."
      }

      $targetRef = $ExpectedCommit
    }

    Invoke-External "git" @("merge", "--ff-only", $targetRef)
  }

  $currentCommit = Get-GitOutput @("rev-parse", "HEAD")
  $shortCurrent = $currentCommit.Substring(0, [Math]::Min(12, $currentCommit.Length))
  Write-Host "Production checkout is at $shortCurrent"

  if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $currentCommit -ne $ExpectedCommit) {
    $shortExpected = $ExpectedCommit.Substring(0, [Math]::Min(12, $ExpectedCommit.Length))
    Write-Warning "Trigger SHA was $shortExpected, but production checkout is $shortCurrent. This usually means production was already advanced beyond that completed CI run."
  }
}

function Invoke-ProductionCompose {
  if ($SkipCompose) {
    Write-Section "Skipping Docker Compose"
    return
  }

  $composePath = Join-Path $RepoRoot $ComposeFile
  if (-not (Test-Path $composePath)) {
    throw "Compose file not found: $composePath"
  }

  Write-Section "Building and starting production stack"
  if ($PSCmdlet.ShouldProcess("Docker Compose stack '$ComposeFile'", "up -d --build --remove-orphans")) {
    Invoke-External "docker" @("compose", "-f", $composePath, "up", "-d", "--build", "--remove-orphans")
    Invoke-External "docker" @("compose", "-f", $composePath, "ps")
  }
}

function Wait-HttpOk {
  param(
    [ValidateNotNullOrEmpty()]
    [string]$Uri,

    [ValidateRange(10, 900)]
    [int]$TimeoutSeconds
  )

  Write-Section "Waiting for health check"
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastError = $null

  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 10
      if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
        Write-Host "Health check passed: $Uri returned HTTP $($response.StatusCode)"
        return
      }
    } catch {
      $lastError = $_.Exception.Message
    }

    Start-Sleep -Seconds 5
  }

  throw "Health check failed for $Uri after $TimeoutSeconds seconds. Last error: $lastError"
}

function Invoke-WithDeployLock {
  param([scriptblock]$Body)

  $mutexName = "Global\MulticaProductionDeploy"
  $mutex = [System.Threading.Mutex]::new($false, $mutexName)
  $hasLock = $false

  try {
    Write-Section "Waiting for deployment lock"
    $hasLock = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
    if (-not $hasLock) {
      throw "Timed out waiting for another production deployment to finish."
    }

    & $Body
  } finally {
    if ($hasLock) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }
}

Invoke-WithDeployLock {
  $resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
  Set-Location $resolvedRepoRoot

  Write-Section "Deploying Multica production"
  Write-Host "Repository: $resolvedRepoRoot"
  Write-Host "Branch: $Branch"
  Write-Host "Compose file: $ComposeFile"

  Assert-CommandExists "git"
  Assert-CommandExists "docker"
  Get-GitOutput @("rev-parse", "--is-inside-work-tree") | Out-Null

  Update-ProductionCheckout
  Invoke-ProductionCompose

  if (-not $SkipHealthCheck -and -not $WhatIfPreference) {
    $healthUri = "$($AppUrl.TrimEnd('/'))/api/config"
    Wait-HttpOk -Uri $healthUri -TimeoutSeconds $HealthTimeoutSeconds
  } else {
    Write-Section "Skipping health check"
  }

  Write-Section "Production deployment finished"
}
