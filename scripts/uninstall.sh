#!/bin/sh
# cc-notify uninstaller for Linux / macOS / WSL
# Supports both local (git clone) and remote (curl | sh) execution.
# Usage: uninstall.sh [--dry-run] [-y|--yes]
set -e

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

# Read a y/N answer from the user, even when stdin is a pipe.
prompt_yn() {
  printf "%s" "$1"
  if [ -t 0 ]; then
    read -r REPLY
  else
    read -r REPLY < /dev/tty 2>/dev/null || REPLY=""
  fi
}

# ============================================================
# Phase 1: Detect
# ============================================================

echo "cc-notify uninstall"
echo ""

# Node.js
if ! command -v node >/dev/null 2>&1; then
  die "Node.js is required but not found."
fi
NODE_VER=$(node --version 2>/dev/null)
pad_dots "check" "Node.js" "$NODE_VER"

# Claude Code config directory
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
pad_dots "check" "Claude Code config" "$CLAUDE_DIR"

# Scan for cc-notify files
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
FILES_TO_REMOVE=""
FILE_COUNT=0

# NOTE: 'terminal-status' fingerprint must match MARKER in merge-hooks.js
for f in terminal-status.sh terminal-status.ps1 toast-extract.js toast.ps1; do
  if [ -f "$CLAUDE_DIR/$f" ]; then
    pad_dots "found" "$f" "yes"
    FILES_TO_REMOVE="$FILES_TO_REMOVE $f"
    FILE_COUNT=$((FILE_COUNT + 1))
  else
    pad_dots "found" "$f" "no"
  fi
done

# Scan for cc-notify hooks in settings.json
HOOK_COUNT=0
if [ -f "$SETTINGS_FILE" ]; then
  HOOK_COUNT=$(node -e "
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
  " "$SETTINGS_FILE" 2>/dev/null || echo 0)
  HOOK_COUNT=${HOOK_COUNT:-0}
  pad_dots "found" "hooks" "$HOOK_COUNT groups"
else
  pad_dots "found" "hooks" "no settings.json"
fi

# Check if there is anything to uninstall
if [ "$FILE_COUNT" -eq 0 ] && [ "$HOOK_COUNT" -eq 0 ]; then
  echo ""
  echo "cc-notify is not installed. Nothing to do."
  exit 0
fi

echo ""

# ============================================================
# Phase 2: Show plan
# ============================================================

printf "  The following changes will be made:\n\n"
if [ "$FILE_COUNT" -gt 0 ]; then
  printf "    remove  %s\n" "$(echo $FILES_TO_REMOVE | sed 's/^ //; s/ /, /g')"
  printf "            > %s\n" "$CLAUDE_DIR"
fi
if [ "$HOOK_COUNT" -gt 0 ]; then
  printf "    remove  %s cc-notify hook groups from settings.json\n" "$HOOK_COUNT"
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

# Backup settings.json before modifying
if [ -f "$SETTINGS_FILE" ] && [ "$HOOK_COUNT" -gt 0 ]; then
  BACKUP_DIR="$CLAUDE_DIR/backups"
  mkdir -p "$BACKUP_DIR"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_FILE="$BACKUP_DIR/settings.json.$TIMESTAMP"
  cp "$SETTINGS_FILE" "$BACKUP_FILE"
  pad_dots "backup" "settings.json" "ok"
fi

# Remove cc-notify hooks from settings.json
if [ "$HOOK_COUNT" -gt 0 ]; then
  node -e "
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
  " "$SETTINGS_FILE" 2>&1 || printf "  %-8s%s\n" "WARN" "Failed to remove hooks. Backup saved at $BACKUP_FILE" >&2
fi

# Remove runtime files
for f in $FILES_TO_REMOVE; do
  rm -f "$CLAUDE_DIR/$f"
  pad_dots "remove" "$f" "ok"
done

# Clean up marker files
TMP_BASE="${TMPDIR:-/tmp}"
MARKER="$TMP_BASE/claude-hook-asking-$(id -u 2>/dev/null || echo 0)"
if [ -f "$MARKER" ]; then
  rm -f "$MARKER"
fi
pad_dots "remove" "marker files" "ok"

echo ""
echo "Done. Restart Claude Code to deactivate."
