#!/bin/sh
# cc-notify installer for Linux / macOS
# Supports both local (git clone) and remote (curl | sh) execution.
set -e

REPO_RAW="${CC_NOTIFY_REPO:-https://raw.githubusercontent.com/Ynewtime/cc-notify/main}"

# -- Output helpers ------------------------------------------

pad_dots() {
  # Usage: pad_dots <label> <key> <value>
  n=$((22 - ${#2}))
  [ "$n" -lt 1 ] && n=1
  dots=$(printf '%*s' "$n" '' | tr ' ' '.')
  printf "  %-8s%s %s %s\n" "$1" "$2" "$dots" "$3"
}

die() {
  printf "  %-8s%s\n" "ERROR" "$1" >&2
  exit 1
}

warn() {
  printf "  %-8s%s\n" "WARN" "$1"
}

# Read a y/N answer from the user, even when stdin is a pipe.
prompt_yn() {
  printf "%s" "$1"
  if [ -t 0 ]; then
    read -r REPLY
  else
    read -r REPLY < /dev/tty 2>/dev/null || REPLY=""
  fi
}

# -- Resolve project files -----------------------------------

CLEANUP_DIR=""

resolve_source() {
  # Try local: running from git clone (scripts/install.sh)
  if [ -f "${0:-}" ]; then
    _dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _dir=""
    if [ -n "$_dir" ] && [ -f "$_dir/../terminal-status.sh" ]; then
      PROJECT_DIR="$(cd "$_dir/.." && pwd)"
      MERGE_SCRIPT="$_dir/merge-hooks.js"
      return
    fi
  fi

  # Remote mode: download files to temp dir
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required for remote installation."
  fi

  TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'cc-notify')
  CLEANUP_DIR="$TMPDIR"

  pad_dots "fetch" "terminal-status.sh" ""
  curl -fsSL "$REPO_RAW/terminal-status.sh"    -o "$TMPDIR/terminal-status.sh"
  pad_dots "fetch" "toast-extract.js" ""
  curl -fsSL "$REPO_RAW/toast-extract.js"      -o "$TMPDIR/toast-extract.js"
  pad_dots "fetch" "toast.ps1" ""
  curl -fsSL "$REPO_RAW/toast.ps1"             -o "$TMPDIR/toast.ps1"
  pad_dots "fetch" "merge-hooks.js" ""
  curl -fsSL "$REPO_RAW/scripts/merge-hooks.js" -o "$TMPDIR/merge-hooks.js"
  echo ""

  PROJECT_DIR="$TMPDIR"
  MERGE_SCRIPT="$TMPDIR/merge-hooks.js"
}

cleanup() {
  if [ -n "$CLEANUP_DIR" ]; then rm -rf "$CLEANUP_DIR"; fi
}
trap cleanup EXIT

# -- Platform detection --------------------------------------

IS_WSL=false
IS_MAC=false

if [ "$(uname -s)" = "Darwin" ]; then
  IS_MAC=true
elif [ -f /proc/sys/fs/binfmt_misc/WSLInterop ] || grep -qsi microsoft /proc/version 2>/dev/null; then
  IS_WSL=true
fi

# -- Begin ---------------------------------------------------

echo "cc-notify install"
echo ""

# 1. Check Node.js
if ! command -v node >/dev/null 2>&1; then
  die "Node.js is required but not found."
fi
NODE_VER=$(node --version 2>/dev/null)
pad_dots "check" "Node.js" "$NODE_VER"

# 2. Platform-specific checks
if [ "$IS_WSL" = true ]; then
  if command -v powershell.exe >/dev/null 2>&1; then
    pad_dots "check" "powershell.exe" "ok"
  else
    warn "powershell.exe not found. Toast notifications unavailable."
  fi
elif [ "$IS_MAC" = true ]; then
  pad_dots "check" "platform" "macOS (toast and tab animation unavailable)"
else
  pad_dots "check" "platform" "Linux (toast unavailable without WSL)"
fi

# 3. Detect Claude Code config directory
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
pad_dots "check" "Claude Code config" "$CLAUDE_DIR"

if [ ! -d "$CLAUDE_DIR" ]; then
  mkdir -p "$CLAUDE_DIR"
fi

echo ""

# 4. Resolve project files (local or remote)
resolve_source

# 5. Copy files
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

cp "$PROJECT_DIR/terminal-status.sh" "$CLAUDE_DIR/"
chmod +x "$CLAUDE_DIR/terminal-status.sh"
pad_dots "copy" "terminal-status.sh" "ok"

cp "$PROJECT_DIR/toast-extract.js" "$CLAUDE_DIR/"
pad_dots "copy" "toast-extract.js" "ok"

cp "$PROJECT_DIR/toast.ps1" "$CLAUDE_DIR/"
pad_dots "copy" "toast.ps1" "ok"

echo ""

# 6. Backup settings.json
if [ -f "$SETTINGS_FILE" ]; then
  BACKUP_DIR="$CLAUDE_DIR/backups"
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/settings.json.$TIMESTAMP"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  pad_dots "backup" "settings.json" "ok"
fi

# 7. Merge hooks
node "$MERGE_SCRIPT" "$SETTINGS_FILE" "$CLAUDE_DIR"

echo ""

# 8. Windows Terminal settings (WSL only)
if [ "$IS_WSL" = true ]; then
  WT_SETTINGS=""

  # Detect LOCALAPPDATA via cmd.exe
  WIN_LOCALAPPDATA=""
  if command -v cmd.exe >/dev/null 2>&1; then
    WIN_LOCALAPPDATA=$(cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
  fi

  if [ -n "$WIN_LOCALAPPDATA" ]; then
    WSL_LOCALAPPDATA=$(wslpath -u "$WIN_LOCALAPPDATA" 2>/dev/null) || WSL_LOCALAPPDATA=""

    if [ -n "$WSL_LOCALAPPDATA" ]; then
      # Store stable
      CANDIDATE="$WSL_LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
      [ -f "$CANDIDATE" ] && WT_SETTINGS="$CANDIDATE"

      # Store preview
      if [ -z "$WT_SETTINGS" ]; then
        CANDIDATE="$WSL_LOCALAPPDATA/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
        [ -f "$CANDIDATE" ] && WT_SETTINGS="$CANDIDATE"
      fi

      # Unpackaged (scoop/chocolatey)
      if [ -z "$WT_SETTINGS" ]; then
        CANDIDATE="$WSL_LOCALAPPDATA/Microsoft/Windows Terminal/settings.json"
        [ -f "$CANDIDATE" ] && WT_SETTINGS="$CANDIDATE"
      fi
    fi
  fi

  if [ -n "$WT_SETTINGS" ]; then
    # Check if windowingBehavior is already set (pass path via argv, not string interpolation)
    if node -e "
      var s = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      process.exit(s.windowingBehavior === 'useExisting' ? 0 : 1);
    " "$WT_SETTINGS" 2>/dev/null; then
      pad_dots "config" "Windows Terminal" "already set"
    else
      prompt_yn "  config  Set Windows Terminal windowingBehavior to useExisting? [y/N] "
      if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
        cp "$WT_SETTINGS" "$WT_SETTINGS.bak"
        node -e "
          var fs = require('fs');
          var p = process.argv[1];
          var s = JSON.parse(fs.readFileSync(p,'utf8'));
          s.windowingBehavior = 'useExisting';
          fs.writeFileSync(p, JSON.stringify(s, null, 4) + '\n', 'utf8');
        " "$WT_SETTINGS"
        pad_dots "config" "Windows Terminal" "ok"
      else
        pad_dots "config" "Windows Terminal" "skipped"
      fi
    fi
  else
    pad_dots "config" "Windows Terminal" "not found, skipped"
  fi
fi

echo ""
echo "Done. Restart Claude Code to activate."
