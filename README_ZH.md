# Claude Code 通知系统

> **已废弃**：本仓库已合并至 [Ynewtime/dotai](https://github.com/Ynewtime/dotai)，后续更新将在该仓库发布。最新版本见 [hooks/cc-notify](https://github.com/Ynewtime/dotai/tree/main/hooks/cc-notify)。

[English](README.md)

为 Claude Code 提供标签页状态指示和桌面通知。

支持 **Linux / macOS / WSL** 和 **Windows 原生**。

## 功能概览

| 功能 | 表现 |
|------|------|
| **工作中指示** | 标签页显示进度动画（Windows Terminal、iTerm2、Ghostty、WezTerm、Konsole） |
| **任务完成通知** | 清除动画 + 响铃 + toast 弹窗（`<项目路径> · 完成`） |
| **等待决策通知** | 清除动画 + 响铃 + toast 弹窗（`<项目路径> · 等待决策`） |
| **权限审批通知** | 保持动画 + 响铃 + toast 弹窗（`<项目路径> · 等待决策`） |

> 标签页动画使用 OSC 9;4 序列，支持 Windows Terminal、iTerm2 (v3.5.6+)、Ghostty (v1.2.0+)、WezTerm、Konsole 和 VTE/Ptyxis。Toast 通知当前需要 Windows（WSL 或原生）环境。响铃在所有平台可用。

## 文件说明

```
cc-notify/
├── terminal-status.sh        # 运行时脚本（Linux / macOS / WSL）
├── terminal-status.ps1       # 运行时脚本（Windows 原生）
├── toast-extract.js          # 从 hook 数据中提取 toast 通知内容
├── toast.ps1                 # PowerShell 脚本：发送 Windows toast 通知
└── scripts/
    ├── install.sh            # 安装脚本（Linux / macOS）
    ├── install.ps1           # 安装脚本（Windows）
    ├── uninstall.sh          # 卸载脚本（Linux / macOS）
    ├── uninstall.ps1         # 卸载脚本（Windows）
    └── merge-hooks.js        # JSON 合并工具（安装脚本调用）
```

## 快速安装

### 一键安装（推荐）

```bash
# Linux / macOS / WSL
curl -fsSL https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/install.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/install.ps1 | iex"
```

### 从源码安装

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

安装脚本会自动：
1. 复制运行时脚本到 Claude Code 配置目录
2. 备份现有 `settings.json`
3. 合并 hooks 配置
4. 可选：设置 Windows Terminal `windowingBehavior`（WSL / Windows）

安装完成后需重启 Claude Code。

> 配置目录优先读取 `CLAUDE_CONFIG_DIR` 环境变量，未设置则使用 `~/.claude`（Unix）或 `%USERPROFILE%\.claude`（Windows）。

### 卸载

```bash
# Linux / macOS / WSL
curl -fsSL https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/uninstall.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/Ynewtime/cc-notify/main/scripts/uninstall.ps1 | iex"
```

或从源码卸载：

```bash
# Linux / macOS / WSL
bash scripts/uninstall.sh

# Windows (PowerShell)
.\scripts\uninstall.ps1
```

卸载脚本会移除运行时文件和 hooks 配置，不影响 `settings.json` 中的其他设置。卸载前会自动备份 `settings.json`。

## 手动安装

<details>
<summary>展开查看手动步骤</summary>

### 1. 复制脚本文件

将运行时脚本复制到 Claude Code 配置目录（`~/.claude/`）：

```bash
cp terminal-status.sh toast-extract.js toast.ps1 ~/.claude/
chmod +x ~/.claude/terminal-status.sh
```

Windows 环境请复制 `terminal-status.ps1`、`toast-extract.js`、`toast.ps1`。

### 2. 配置 Claude Code Hooks

将以下 `hooks` 配置合并到 `~/.claude/settings.json` 中：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<你的用户名>/.claude/terminal-status.sh reset"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<你的用户名>/.claude/terminal-status.sh working"
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
            "command": "/home/<你的用户名>/.claude/terminal-status.sh mark"
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
            "command": "/home/<你的用户名>/.claude/terminal-status.sh alert"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/<你的用户名>/.claude/terminal-status.sh done"
          }
        ]
      }
    ]
  }
}
```

> **注意**：将 `<你的用户名>` 替换为实际用户名。

Windows 环境请使用 `terminal-status.ps1` 配合 PowerShell 命令格式。以 `Stop` 事件为例：

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<你的用户名>\\.claude\\terminal-status.ps1\" done"
    }
  ]
}
```

### 3. 推荐：优化 Windows Terminal 窗口行为

在 Windows Terminal 配置中添加以下设置，使新终端操作复用现有窗口而非打开新窗口：

**文件路径**：`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`

```json
{
  "windowingBehavior": "useExisting"
}
```

### 4. 重启 Claude Code

修改 hooks 配置后需要重启 Claude Code 会话才能生效。

</details>

## Hook 状态机

```
用户提交 prompt > [working] > 标签页 loading 动画
                                      |
                  .-------------------+
                  |                   |
         Claude 提问/提交计划    Claude 正常完成
         [mark] 写标记                |
                  |                   v
                  v             [done] 无标记
            [done] 有标记             |
                  |                   v
                  v             Toast: 完成
            Toast: 等待决策

                  v （非 bypass 模式）
            权限审批弹出
            [alert] 铃声 + Toast
            loading 保持
```

## 配置开关

### 关闭 Toast 通知

编辑 `terminal-status.sh`（Windows 下为 `terminal-status.ps1`），修改顶部开关：

```sh
ENABLE_TOAST=false    # terminal-status.sh
```

```powershell
$EnableToast = $false  # terminal-status.ps1
```

此时仅保留标签页 loading 动画和响铃，不再发送 Windows 桌面通知。

## 环境要求

| 平台 | 要求 |
|------|------|
| **WSL** | Windows Terminal、Node.js、PowerShell（通过 `powershell.exe`） |
| **Windows 原生** | Windows Terminal、Node.js、PowerShell 5.1+ |
| **Linux（非 WSL）** | Node.js；标签页动画在支持的终端中可用，toast 不可用 |
| **macOS** | Node.js；标签页动画在 iTerm2 中可用，toast 不可用 |

## 技术细节

### 为什么 hook 脚本不能直接用 `printf '\a'`？

Claude Code 的 hook 命令以子进程运行，其 stdout 被重定向到内部管道。在 Linux/WSL 下，脚本通过遍历进程树找到 Claude 所在的 PTY（如 `/dev/pts/0`），然后直接写入该设备。在 Windows 下，脚本通过打开 `CONOUT$` 句柄绕过 stdout 重定向。

### 标签页进度动画（OSC 9;4）

使用 OSC 9;4 转义序列（源自 ConEmu，现已被广泛采纳）：

- `\033]9;4;3;0\007` -- 开启 indeterminate 进度动画（loading 圆环）
- `\033]9;4;0;0\007` -- 清除进度动画

支持的终端：Windows Terminal、iTerm2 (v3.5.6+)、Ghostty (v1.2.0+)、WezTerm、Konsole (KDE Gear 2025-04)、VTE/Ptyxis。不支持：Kitty（与 OSC 9 通知冲突）、Alacritty。

### 为什么不用 OSC 0 修改标签页标题？

Claude Code 作为 TUI 应用持续管理终端标题，任何外部写入的 OSC 0 序列会被立即覆盖。OSC 9;4 不受 Claude Code 标题管理的影响。

### Toast 通知

**AUMID**：使用 `Microsoft.WindowsTerminal_8wekyb3d8bbwe!App` 作为通知发送者，使 toast 显示 Windows Terminal 图标。

**点击行为**：Toast XML 设置了 `activationType="protocol" launch=""`，点击通知时仅关闭弹窗，不会激活 Windows Terminal（避免新建标签页）。

> **已知限制**：由于 Windows Terminal 不暴露 tab index 给 WSL 进程（[WT Discussion #17963](https://github.com/microsoft/terminal/discussions/17963)），无法实现"点击通知跳转到对应标签页"。当前方案是点击后仅关闭通知。
