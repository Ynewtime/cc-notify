#!/bin/sh
# Claude Code hook: update Windows Terminal tab status.
# Usage:
#   terminal-status.sh working  — clear stale progress, then show progress animation
#   terminal-status.sh done     — clear progress, send bell, toast ("完成" or "等待决策")
#   terminal-status.sh mark     — mark that Claude is asking a question (PostToolUse)
#   terminal-status.sh alert    — bell + toast "等待决策", keep loading (PermissionRequest)
#   terminal-status.sh reset    — clear progress only (for SessionStart)

ACTION="${1:-done}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASKING_MARKER="/tmp/claude-hook-asking"

# ── Feature toggles ─────────────────────────────
ENABLE_TOAST=true
# ─────────────────────────────────────────────────

# Save stdin (hook event JSON) to temp file for safe handling
HOOK_FILE=$(mktemp /tmp/claude-hook-XXXXXX.json 2>/dev/null || echo /tmp/claude-hook-$$.json)
cat > "$HOOK_FILE"

# Find the PTY of the ancestor Claude process.
find_tty() {
  p=$PPID
  while [ "${p:-0}" -gt 1 ]; do
    t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "?" ]; then
      echo "/dev/$t"
      return
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
}

# Send toast notification
# Args: $1 = toast type ("done" or "notify")
send_toast() {
  DISTRO="${WSL_DISTRO_NAME:-$(hostname)}"
  MSG=$(node "$SCRIPT_DIR/toast-extract.js" "$1" "$HOOK_FILE" 2>/dev/null || echo "Task completed")
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$SCRIPT_DIR/toast.ps1")" \
    -Title "$DISTRO · CC" \
    -Message "$MSG" >/dev/null 2>&1 &
}

TTY=$(find_tty)
[ -z "$TTY" ] && { rm -f "$HOOK_FILE"; exit 0; }

case "$ACTION" in
  working)
    # Clear marker + stale progress, then show loading
    rm -f "$ASKING_MARKER"
    printf '\033]9;4;0;0\007\033]9;4;3;0\007' > "$TTY" 2>/dev/null
    ;;
  mark)
    # AskUserQuestion was called — set marker for Stop hook
    touch "$ASKING_MARKER"
    ;;
  done)
    printf '\033]9;4;0;0\007\a' > "$TTY" 2>/dev/null
    if [ "$ENABLE_TOAST" = true ]; then
      if [ -f "$ASKING_MARKER" ]; then
        rm -f "$ASKING_MARKER"
        send_toast notify
      else
        send_toast done
      fi
    fi
    ;;
  alert)
    # PermissionRequest: bell + toast, keep loading (Claude resumes after approval)
    printf '\a' > "$TTY" 2>/dev/null
    [ "$ENABLE_TOAST" = true ] && send_toast notify
    ;;
  reset)
    rm -f "$ASKING_MARKER"
    printf '\033]9;4;0;0\007' > "$TTY" 2>/dev/null
    ;;
esac

rm -f "$HOOK_FILE"
