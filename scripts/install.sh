#!/bin/sh
# cc-notify installer for Linux / macOS
# Supports both local (git clone) and remote (curl | sh) execution.
# Usage: install.sh [--dry-run] [-y|--yes]
set -e

REPO_RAW="${CC_NOTIFY_REPO:-https://raw.githubusercontent.com/Ynewtime/cc-notify/main}"

# -- Parse arguments -----------------------------------------

DRY_RUN=false
YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -y|--yes)  YES=true ;;
  esac
done

# -- Output helpers ------------------------------------------

pad_dots() {
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

  # In dry-run + remote mode, skip download
  if [ "$DRY_RUN" = true ]; then
    PROJECT_DIR=""
    MERGE_SCRIPT=""
    pad_dots "fetch" "4 files from remote" "(skip, dry run)"
    return
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
  if [ -n "$CLEANUP_DIR" ] && [ -d "$CLEANUP_DIR" ] && [ "$CLEANUP_DIR" != "/" ]; then
    rm -rf -- "$CLEANUP_DIR"
  fi
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

# -- Detect Windows Terminal settings (WSL only) -------------

detect_wt_settings() {
  WT_SETTINGS=""
  if [ "$IS_WSL" != true ]; then return; fi

  WIN_LOCALAPPDATA=""
  if command -v cmd.exe >/dev/null 2>&1; then
    WIN_LOCALAPPDATA=$(cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')
  fi

  if [ -z "$WIN_LOCALAPPDATA" ]; then return; fi
  WSL_LOCALAPPDATA=$(wslpath -u "$WIN_LOCALAPPDATA" 2>/dev/null) || return

  for CANDIDATE in \
    "$WSL_LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
    "$WSL_LOCALAPPDATA/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" \
    "$WSL_LOCALAPPDATA/Microsoft/Windows Terminal/settings.json"; do
    if [ -f "$CANDIDATE" ]; then
      WT_SETTINGS="$CANDIDATE"
      return
    fi
  done
}

# ============================================================
# Phase 1: Checks
# ============================================================

echo "cc-notify install"
echo ""

# Node.js
if ! command -v node >/dev/null 2>&1; then
  die "Node.js is required but not found."
fi
NODE_VER=$(node --version 2>/dev/null)
pad_dots "check" "Node.js" "$NODE_VER"

# Platform
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

# Claude Code config directory
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
pad_dots "check" "Claude Code config" "$CLAUDE_DIR"

# Windows Terminal
detect_wt_settings
WT_NEEDS_UPDATE=false
if [ -n "$WT_SETTINGS" ]; then
  if node -e "
    var s = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    process.exit(s.windowingBehavior === 'useExisting' ? 0 : 1);
  " "$WT_SETTINGS" 2>/dev/null; then
    pad_dots "check" "Windows Terminal" "already set"
  else
    pad_dots "check" "Windows Terminal" "found, windowingBehavior not set"
    WT_NEEDS_UPDATE=true
  fi
fi

echo ""

# ============================================================
# Phase 2: Show plan
# ============================================================

printf "  The following changes will be made:\n\n"
printf "    copy    terminal-status.sh, toast-extract.js, toast.ps1\n"
printf "            > %s\n" "$CLAUDE_DIR"
printf "    config  Merge 5 hook events into settings.json\n"
if [ "$WT_NEEDS_UPDATE" = true ]; then
  printf "    config  Set Windows Terminal windowingBehavior (optional)\n"
fi
echo ""

# ============================================================
# Phase 3: Confirm or dry-run
# ============================================================

if [ "$DRY_RUN" = true ]; then
  echo "Dry run complete. No changes were made."
  exit 0
fi

if [ "$YES" = true ]; then
  echo "Proceed? [y/N] y (--yes)"
else
  prompt_yn "Proceed? [y/N] "
  if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Cancelled."
    exit 0
  fi
fi
echo ""

# ============================================================
# Phase 4: Execute
# ============================================================

# Resolve project files (local or remote)
resolve_source

# Create config directory
if [ ! -d "$CLAUDE_DIR" ]; then
  mkdir -p "$CLAUDE_DIR"
fi

# Copy files
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

cp "$PROJECT_DIR/terminal-status.sh" "$CLAUDE_DIR/"
chmod +x "$CLAUDE_DIR/terminal-status.sh"
pad_dots "copy" "terminal-status.sh" "ok"

cp "$PROJECT_DIR/toast-extract.js" "$CLAUDE_DIR/"
pad_dots "copy" "toast-extract.js" "ok"

cp "$PROJECT_DIR/toast.ps1" "$CLAUDE_DIR/"
pad_dots "copy" "toast.ps1" "ok"

echo ""

# Backup settings.json
if [ -f "$SETTINGS_FILE" ]; then
  BACKUP_DIR="$CLAUDE_DIR/backups"
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/settings.json.$TIMESTAMP"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  pad_dots "backup" "settings.json" "ok"
fi

# Merge hooks
node "$MERGE_SCRIPT" "$SETTINGS_FILE" "$CLAUDE_DIR"

# Windows Terminal settings
if [ "$WT_NEEDS_UPDATE" = true ]; then
  echo ""
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

echo ""
echo "Done. Restart Claude Code to activate."
