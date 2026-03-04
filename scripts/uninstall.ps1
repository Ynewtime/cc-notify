# cc-notify uninstaller for Windows
# Supports both local (git clone) and remote (irm | iex) execution.
# Usage: uninstall.ps1 [-DryRun] [-Yes]
#Requires -Version 5.1
param(
  [switch]$DryRun,
  [Alias("y")]
  [switch]$Yes
)
$ErrorActionPreference = "Stop"

# -- Output helpers ------------------------------------------

function Write-Dots {
  param([string]$Label, [string]$Key, [string]$Value)
  $n = [Math]::Max(1, 22 - $Key.Length)
  $dots = "." * $n
  Write-Host ("  {0,-8}{1} {2} {3}" -f $Label, $Key, $dots, $Value)
}

function Stop-Uninstall {
  param([string]$Message)
  Write-Host ("  {0,-8}{1}" -f "ERROR", $Message) -ForegroundColor Red
  exit 1
}

function Write-Warn {
  param([string]$Message)
  Write-Host ("  {0,-8}{1}" -f "WARN", $Message) -ForegroundColor Yellow
}

# ============================================================
# Phase 1: Detect
# ============================================================

Write-Host "cc-notify uninstall"
Write-Host ""

# Node.js
$nodePath = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodePath) {
  Stop-Uninstall "Node.js is required but not found."
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

# Scan for cc-notify files
$SettingsFile = Join-Path $ClaudeDir "settings.json"
$FilesToRemove = @()

# NOTE: 'terminal-status' fingerprint must match MARKER in merge-hooks.js
foreach ($f in @("terminal-status.ps1", "terminal-status.sh", "toast-extract.js", "toast.ps1")) {
  $fp = Join-Path $ClaudeDir $f
  if (Test-Path $fp) {
    Write-Dots "found" $f "yes"
    $FilesToRemove += $f
  } else {
    Write-Dots "found" $f "no"
  }
}

# Scan for cc-notify hooks in settings.json
$HookCount = 0
if (Test-Path $SettingsFile) {
  $HookCount = & node -e "
    var fs = require('fs'), s;
    try { s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8')); } catch(e) { process.stdout.write('0'); process.exit(0); }
    if (!s.hooks) { process.stdout.write('0'); process.exit(0); }
    var c = 0;
    Object.keys(s.hooks).forEach(function(ev) {
      if (!Array.isArray(s.hooks[ev])) return;
      s.hooks[ev].forEach(function(g) {
        if (g.hooks && g.hooks.some(function(h) { return h.command && h.command.indexOf('terminal-status') !== -1; }))
          c++;
      });
    });
    process.stdout.write(String(c));
  " $SettingsFile 2>$null
  if (-not $HookCount) { $HookCount = 0 }
  Write-Dots "found" "hooks" "$HookCount groups"
} else {
  Write-Dots "found" "hooks" "no settings.json"
}

# Check if there is anything to uninstall
if ($FilesToRemove.Count -eq 0 -and [int]$HookCount -eq 0) {
  Write-Host ""
  Write-Host "cc-notify is not installed. Nothing to do."
  exit 0
}

Write-Host ""

# ============================================================
# Phase 2: Show plan
# ============================================================

Write-Host "  The following changes will be made:"
Write-Host ""
if ($FilesToRemove.Count -gt 0) {
  Write-Host ("    remove  " + ($FilesToRemove -join ", "))
  Write-Host "            > $ClaudeDir"
}
if ([int]$HookCount -gt 0) {
  Write-Host "    remove  $HookCount cc-notify hook groups from settings.json"
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

# Backup settings.json before modifying
if ((Test-Path $SettingsFile) -and [int]$HookCount -gt 0) {
  $BackupDir = Join-Path $ClaudeDir "backups"
  if (-not (Test-Path $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
  }
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupFile = Join-Path $BackupDir "settings.json.$timestamp"
  Copy-Item $SettingsFile $backupFile
  Write-Dots "backup" "settings.json" "ok"
}

# Remove cc-notify hooks from settings.json
if ([int]$HookCount -gt 0) {
  & node -e "
    var fs = require('fs'), p = process.argv[1];
    try {
      var s = JSON.parse(fs.readFileSync(p, 'utf8'));
    } catch(e) {
      console.error('  ERROR   Cannot parse ' + p + ': ' + e.message);
      process.exit(1);
    }
    if (!s.hooks) process.exit(0);
    var changed = 0;
    Object.keys(s.hooks).forEach(function(ev) {
      if (!Array.isArray(s.hooks[ev])) return;
      var before = s.hooks[ev].length;
      s.hooks[ev] = s.hooks[ev].filter(function(g) {
        return !(g.hooks && g.hooks.some(function(h) {
          return h.command && h.command.indexOf('terminal-status') !== -1;
        }));
      });
      changed += before - s.hooks[ev].length;
      if (s.hooks[ev].length === 0) delete s.hooks[ev];
    });
    if (Object.keys(s.hooks).length === 0) delete s.hooks;
    if (changed > 0) {
      try {
        fs.writeFileSync(p, JSON.stringify(s, null, 2) + '\n');
      } catch(e) {
        console.error('  ERROR   Cannot write ' + p + ': ' + e.message);
        process.exit(1);
      }
      console.log('  remove  hooks ................. ' + changed + ' groups removed');
    } else {
      console.log('  remove  hooks ................. none found');
    }
  " $SettingsFile 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Failed to remove hooks. Backup saved at $backupFile"
  }
}

# Remove runtime files
foreach ($f in $FilesToRemove) {
  Remove-Item (Join-Path $ClaudeDir $f) -Force
  Write-Dots "remove" $f "ok"
}

# Clean up marker files
$marker = Join-Path $env:TEMP "claude-hook-asking"
if (Test-Path $marker) {
  Remove-Item $marker -Force -ErrorAction SilentlyContinue
}
Write-Dots "remove" "marker files" "ok"

Write-Host ""
Write-Host "Done. Restart Claude Code to deactivate."
