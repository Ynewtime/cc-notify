# Claude Code hook: update Windows Terminal tab status (Windows native).
# Usage:
#   terminal-status.ps1 working  -- show progress animation
#   terminal-status.ps1 done     -- clear progress, bell, toast
#   terminal-status.ps1 mark     -- mark that Claude is asking a question
#   terminal-status.ps1 alert    -- bell + toast, keep loading
#   terminal-status.ps1 reset    -- clear progress only

param(
  [Parameter(Position = 0)]
  [string]$Action = "done"
)

$ErrorActionPreference = "SilentlyContinue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AskingMarker = Join-Path $env:TEMP "claude-hook-asking"

# -- Feature toggles ----------------------------------------
$EnableToast = $true
# ------------------------------------------------------------

# ESC and BEL characters for terminal sequences
$ESC = [char]0x1B
$BEL = [char]0x07

# Save stdin (hook event JSON) to temp file
$HookFile = [IO.Path]::GetTempFileName()
try {
  $stdinData = @($input) -join "`n"
  if (-not $stdinData) {
    # Fallback: try reading from Console.In directly
    try { $stdinData = [Console]::In.ReadToEnd() } catch {}
  }
  if ($stdinData) {
    [IO.File]::WriteAllText($HookFile, $stdinData, [Text.Encoding]::UTF8)
  }
} catch {}

# Write directly to console, bypassing stdout redirection.
function Write-Console {
  param([string]$Text)
  try {
    $conout = [IO.FileStream]::new(
      'CONOUT$',
      [IO.FileMode]::Open,
      [IO.FileAccess]::Write,
      [IO.FileShare]::Write
    )
    $bytes = [Text.Encoding]::ASCII.GetBytes($Text)
    $conout.Write($bytes, 0, $bytes.Length)
    $conout.Flush()
    $conout.Close()
  } catch {}
}

# Send toast notification.
function Send-Toast {
  param([string]$Type)
  $msg = "Task completed"
  try {
    $nodePath = (Get-Command node -ErrorAction Stop).Source
    $extractScript = Join-Path $ScriptDir "toast-extract.js"
    $result = & $nodePath $extractScript $Type $HookFile 2>$null
    if ($result) { $msg = $result }
  } catch {}

  $toastScript = Join-Path $ScriptDir "toast.ps1"
  $distro = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "Windows" }
  $title = "$distro $([char]0xB7) CC"
  # Use a single argument string with proper quoting for Start-Process
  Start-Process -NoNewWindow -FilePath "powershell.exe" -ArgumentList `
    "-NoProfile -ExecutionPolicy Bypass -File `"$toastScript`" -Title `"$title`" -Message `"$msg`""
}

switch ($Action) {
  "working" {
    Remove-Item $AskingMarker -Force -ErrorAction SilentlyContinue
    Write-Console "${ESC}]9;4;0;0${BEL}${ESC}]9;4;3;0${BEL}"
  }
  "mark" {
    New-Item $AskingMarker -ItemType File -Force | Out-Null
  }
  "done" {
    Write-Console "${ESC}]9;4;0;0${BEL}${BEL}"
    if ($EnableToast) {
      if (Test-Path $AskingMarker) {
        Remove-Item $AskingMarker -Force
        Send-Toast "notify"
      } else {
        Send-Toast "done"
      }
    }
  }
  "alert" {
    Write-Console "${BEL}"
    if ($EnableToast) { Send-Toast "notify" }
  }
  "reset" {
    Remove-Item $AskingMarker -Force -ErrorAction SilentlyContinue
    Write-Console "${ESC}]9;4;0;0${BEL}"
  }
}

Remove-Item $HookFile -Force -ErrorAction SilentlyContinue
