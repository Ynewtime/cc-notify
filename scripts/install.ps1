# cc-notify installer for Windows
# Supports both local (git clone) and remote (irm | iex) execution.
# Usage: install.ps1 [-DryRun] [-Yes]
#Requires -Version 5.1
param(
  [switch]$DryRun,
  [Alias("y")]
  [switch]$Yes
)
$ErrorActionPreference = "Stop"

$RepoRaw = if ($env:CC_NOTIFY_REPO) { $env:CC_NOTIFY_REPO } `
  else { "https://raw.githubusercontent.com/Ynewtime/cc-notify/main" }

# -- Output helpers ------------------------------------------

function Write-Dots {
  param([string]$Label, [string]$Key, [string]$Value)
  $n = [Math]::Max(1, 22 - $Key.Length)
  $dots = "." * $n
  Write-Host ("  {0,-8}{1} {2} {3}" -f $Label, $Key, $dots, $Value)
}

function Stop-Install {
  param([string]$Message)
  Write-Host ("  {0,-8}{1}" -f "ERROR", $Message) -ForegroundColor Red
  exit 1
}

function Write-Warn {
  param([string]$Message)
  Write-Host ("  {0,-8}{1}" -f "WARN", $Message) -ForegroundColor Yellow
}

# -- Resolve project files -----------------------------------

$CleanupDir = $null

function Resolve-Source {
  $script:ProjectDir = $null
  $script:MergeScript = $null

  # Try local: running from git clone (scripts\install.ps1)
  $scriptPath = $MyInvocation.ScriptName
  if ($scriptPath -and (Test-Path $scriptPath)) {
    $sd = Split-Path -Parent $scriptPath
    $pd = Split-Path -Parent $sd
    if (Test-Path (Join-Path $pd "terminal-status.ps1")) {
      $script:ProjectDir = $pd
      $script:MergeScript = Join-Path $sd "merge-hooks.js"
      return
    }
  }

  # In dry-run + remote mode, skip download
  if ($DryRun) {
    Write-Dots "fetch" "4 files from remote" "(skip, dry run)"
    return
  }

  # Remote mode: download files to temp dir
  $tmpDir = Join-Path ([IO.Path]::GetTempPath()) "cc-notify-$(Get-Random)"
  New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null
  $script:CleanupDir = $tmpDir

  $files = @(
    @{ Name = "terminal-status.ps1"; Path = "terminal-status.ps1" }
    @{ Name = "toast-extract.js";    Path = "toast-extract.js" }
    @{ Name = "toast.ps1";           Path = "toast.ps1" }
    @{ Name = "merge-hooks.js";      Path = "scripts/merge-hooks.js" }
  )

  foreach ($f in $files) {
    Write-Dots "fetch" $f.Name ""
    $url = "$RepoRaw/$($f.Path)"
    try {
      Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmpDir $f.Name) -UseBasicParsing
    } catch {
      Stop-Install "Failed to download $($f.Name) from $url"
    }
  }
  Write-Host ""

  $script:ProjectDir = $tmpDir
  $script:MergeScript = Join-Path $tmpDir "merge-hooks.js"
}

# -- Detect Windows Terminal settings ------------------------

function Find-WtSettings {
  $localAppData = $env:LOCALAPPDATA
  if (-not $localAppData) { return $null }

  $candidates = @(
    (Join-Path $localAppData "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $localAppData "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
    (Join-Path $localAppData "Microsoft\Windows Terminal\settings.json")
  )

  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# ============================================================
# Phase 1: Checks
# ============================================================

Write-Host "cc-notify install"
Write-Host ""

# Node.js
$nodePath = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodePath) {
  Stop-Install "Node.js is required but not found."
}
$nodeVer = & node --version 2>$null
Write-Dots "check" "Node.js" $nodeVer

# Claude Code config directory
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) {
  $env:CLAUDE_CONFIG_DIR
} else {
  Join-Path $env:USERPROFILE ".claude"
}
Write-Dots "check" "Claude Code config" $ClaudeDir

# Windows Terminal
$wtSettings = Find-WtSettings
$wtNeedsUpdate = $false
if ($wtSettings) {
  & node -e "
    var s = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    process.exit(s.windowingBehavior === 'useExisting' ? 0 : 1);
  " $wtSettings 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Dots "check" "Windows Terminal" "already set"
  } else {
    Write-Dots "check" "Windows Terminal" "found, windowingBehavior not set"
    $wtNeedsUpdate = $true
  }
}

Write-Host ""

# ============================================================
# Phase 2: Show plan
# ============================================================

Write-Host "  The following changes will be made:"
Write-Host ""
Write-Host "    copy    terminal-status.ps1, toast-extract.js, toast.ps1"
Write-Host "            > $ClaudeDir"
Write-Host "    config  Merge 5 hook events into settings.json"
if ($wtNeedsUpdate) {
  Write-Host "    config  Set Windows Terminal windowingBehavior (optional)"
}
Write-Host ""

# ============================================================
# Phase 3: Confirm or dry-run
# ============================================================

if ($DryRun) {
  Write-Host "Dry run complete. No changes were made."
  exit 0
}

if ($Yes) {
  Write-Host "Proceed? [y/N] y (--yes)"
} else {
  $reply = Read-Host "Proceed? [y/N]"
  if ($reply -ne "y" -and $reply -ne "Y") {
    Write-Host "Cancelled."
    exit 0
  }
}
Write-Host ""

# ============================================================
# Phase 4: Execute
# ============================================================

# Resolve project files (local or remote)
Resolve-Source

try {
  # Create config directory
  if (-not (Test-Path $ClaudeDir)) {
    New-Item -Path $ClaudeDir -ItemType Directory -Force | Out-Null
  }

  # Copy files
  $SettingsFile = Join-Path $ClaudeDir "settings.json"

  Copy-Item (Join-Path $ProjectDir "terminal-status.ps1") $ClaudeDir -Force
  Write-Dots "copy" "terminal-status.ps1" "ok"

  Copy-Item (Join-Path $ProjectDir "toast-extract.js") $ClaudeDir -Force
  Write-Dots "copy" "toast-extract.js" "ok"

  Copy-Item (Join-Path $ProjectDir "toast.ps1") $ClaudeDir -Force
  Write-Dots "copy" "toast.ps1" "ok"

  Write-Host ""

  # Backup settings.json
  if (Test-Path $SettingsFile) {
    $BackupDir = Join-Path $ClaudeDir "backups"
    if (-not (Test-Path $BackupDir)) {
      New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = Join-Path $BackupDir "settings.json.$timestamp"
    Copy-Item $SettingsFile $backupFile
    Write-Dots "backup" "settings.json" "ok"
  }

  # Merge hooks
  & node $MergeScript $SettingsFile $ClaudeDir --windows
  if ($LASTEXITCODE -ne 0) {
    Stop-Install "Failed to merge hooks config."
  }

  # Windows Terminal settings
  if ($wtNeedsUpdate) {
    Write-Host ""
    $wtReply = Read-Host "  config  Set Windows Terminal windowingBehavior to useExisting? [y/N]"
    if ($wtReply -eq "y" -or $wtReply -eq "Y") {
      Copy-Item $wtSettings "$wtSettings.bak"
      & node -e "
        var fs = require('fs');
        var p = process.argv[1];
        var s = JSON.parse(fs.readFileSync(p, 'utf8'));
        s.windowingBehavior = 'useExisting';
        fs.writeFileSync(p, JSON.stringify(s, null, 4) + '\n', 'utf8');
      " $wtSettings
      Write-Dots "config" "Windows Terminal" "ok"
    } else {
      Write-Dots "config" "Windows Terminal" "skipped"
    }
  }

} finally {
  # Cleanup temp dir if in remote mode
  $tempRoot = [IO.Path]::GetTempPath()
  if (
    $CleanupDir -and
    (Test-Path $CleanupDir) -and
    $CleanupDir.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)
  ) {
    Remove-Item $CleanupDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host ""
Write-Host "Done. Restart Claude Code to activate."
