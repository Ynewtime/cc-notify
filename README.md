# Claude Code Notification System

[中文文档](README_ZH.md)

Tab status indicators and desktop notifications for Claude Code.

Supports **Linux / macOS / WSL** and **Windows native**.

## Features

| Feature | Behavior |
|---------|----------|
| **Working indicator** | Tab progress animation (Windows Terminal, iTerm2, Ghostty, WezTerm, Konsole) |
| **Task complete** | Clear animation + bell + toast (`<project> · 完成`) |
| **Awaiting decision** | Clear animation + bell + toast (`<project> · 等待决策`) |
| **Permission request** | Keep animation + bell + toast (`<project> · 等待决策`) |

> Tab animation uses OSC 9;4, supported by Windows Terminal, iTerm2 (v3.5.6+), Ghostty (v1.2.0+), WezTerm, Konsole, and VTE/Ptyxis. Toast notifications currently require Windows (WSL or native). Bell works on all platforms.

## Files

```
cc-notify/
├── terminal-status.sh        # Runtime script (Linux / macOS / WSL)
├── terminal-status.ps1       # Runtime script (Windows native)
├── toast-extract.js          # Extracts toast message from hook JSON
├── toast.ps1                 # PowerShell: sends Windows toast notifications
└── scripts/
    ├── install.sh            # Installer for Linux / macOS
    ├── install.ps1           # Installer for Windows
    ├── uninstall.sh          # Uninstaller for Linux / macOS
    ├── uninstall.ps1         # Uninstaller for Windows
    └── merge-hooks.js        # JSON merge utility (used by installers)
```

## Quick Install

### One-liner (recommended)

```bash
# Linux / macOS / WSL
curl -fsSL https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/install.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/install.ps1 | iex"
```

### From source

```bash
# Linux / macOS / WSL
git clone https://github.com/Ynewtime/cc-notify.git && cd cc-notify
bash scripts/install.sh
```

```powershell
# Windows (PowerShell)
git clone https://github.com/Ynewtime/cc-notify.git; cd cc-notify
.\scripts\install.ps1
```

The installer will:
1. Copy runtime scripts to the Claude Code config directory
2. Back up existing `settings.json`
3. Merge hooks configuration
4. Optionally set Windows Terminal `windowingBehavior` (WSL / Windows)

Restart Claude Code after installation.

> The config directory is detected via `CLAUDE_CONFIG_DIR` env var, falling back to `~/.claude` (Unix) or `%USERPROFILE%\.claude` (Windows).

### Uninstall

```bash
# Linux / macOS / WSL
curl -fsSL https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/uninstall.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/uninstall.ps1 | iex"
```

Or from source:

```bash
# Linux / macOS / WSL
bash scripts/uninstall.sh

# Windows (PowerShell)
.\scripts\uninstall.ps1
```

The uninstaller removes runtime files and hooks configuration without affecting other settings in `settings.json`. It automatically backs up `settings.json` before making changes.

## Manual Installation

<details>
<summary>Expand for manual steps</summary>

### 1. Copy script files

Copy the runtime scripts to your Claude Code config directory (`~/.claude/`):

```bash
cp terminal-status.sh toast-extract.js toast.ps1 ~/.claude/
chmod +x ~/.claude/terminal-status.sh
```

On Windows, copy `terminal-status.ps1`, `toast-extract.js`, and `toast.ps1` instead.

### 2. Configure Claude Code Hooks

Merge the following `hooks` config into your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<your-username>/.claude/terminal-status.sh reset"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<your-username>/.claude/terminal-status.sh working"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "AskUserQuestion|ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "/home/<your-username>/.claude/terminal-status.sh mark"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/home/<your-username>/.claude/terminal-status.sh alert"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<your-username>/.claude/terminal-status.sh done"
          }
        ]
      }
    ]
  }
}
```

> **Note**: Replace `<your-username>` with your actual username.

On Windows, use `terminal-status.ps1` with the PowerShell command format. Example for the `Stop` event:

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<your-username>\\.claude\\terminal-status.ps1\" done"
    }
  ]
}
```

### 3. Recommended: Optimize Windows Terminal window behavior

Add the following setting to your Windows Terminal config so that new terminal operations reuse the existing window instead of opening a new one:

**File path**: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`

```json
{
  "windowingBehavior": "useExisting"
}
```

### 4. Restart Claude Code

Hooks configuration changes require restarting the Claude Code session to take effect.

</details>

## Hook State Machine

```
User submits prompt > [working] > Tab loading animation
                                         |
                      .------------------+
                      |                  |
               Claude asks question/  Claude completes
               submits plan           normally
               [mark] set marker         |
                      |                  v
                      v            [done] no marker
                [done] has marker        |
                      |                  v
                      v            Toast: done
                Toast: awaiting

                      v (non-bypass mode)
                Permission prompt
                [alert] bell + Toast
                loading continues
```

## Configuration

### Disable Toast Notifications

Edit `terminal-status.sh` (or `terminal-status.ps1` on Windows) and set the toggle at the top:

```sh
ENABLE_TOAST=false    # terminal-status.sh
```

```powershell
$EnableToast = $false  # terminal-status.ps1
```

This keeps the tab loading animation and bell, but disables Windows desktop notifications.

## Requirements

| Platform | Requirements |
|----------|-------------|
| **WSL** | Windows Terminal, Node.js, PowerShell (via `powershell.exe`) |
| **Windows native** | Windows Terminal, Node.js, PowerShell 5.1+ |
| **Linux (non-WSL)** | Node.js; tab animation works in supported terminals, toast unavailable |
| **macOS** | Node.js; tab animation works in iTerm2, toast unavailable |

## Technical Details

### Why can't hook scripts use `printf '\a'` directly?

Claude Code hook commands run as subprocesses with stdout redirected to an internal pipe. On Linux/WSL, the script walks up the process tree to find the PTY of the ancestor Claude process (e.g., `/dev/pts/0`) and writes directly to that device. On Windows, the script opens `CONOUT$` to bypass stdout redirection.

### Tab progress animation (OSC 9;4)

Uses OSC 9;4 escape sequences (originally from ConEmu, now widely adopted):

- `\033]9;4;3;0\007` -- Start indeterminate progress animation (loading spinner)
- `\033]9;4;0;0\007` -- Clear progress animation

Supported terminals: Windows Terminal, iTerm2 (v3.5.6+), Ghostty (v1.2.0+), WezTerm, Konsole (KDE Gear 2025-04), VTE/Ptyxis. Not supported: Kitty (conflicts with OSC 9 notifications), Alacritty.

### Why not use OSC 0 to change the tab title?

Claude Code is a TUI application that continuously manages the terminal title. Any OSC 0 sequence written externally gets immediately overwritten. OSC 9;4 is an extension not affected by Claude Code's title management.

### Toast Notifications

**AUMID**: Uses `Microsoft.WindowsTerminal_8wekyb3d8bbwe!App` as the notification sender, so the toast displays the Windows Terminal icon.

**Click behavior**: The toast XML sets `activationType="protocol" launch=""`, which simply dismisses the notification on click without activating Windows Terminal (avoiding opening a new tab).

> **Known limitation**: Windows Terminal does not expose tab indices to WSL processes ([WT Discussion #17963](https://github.com/microsoft/terminal/discussions/17963)), so "click notification to jump to the corresponding tab" is not possible. The current behavior is to simply dismiss the notification on click.
