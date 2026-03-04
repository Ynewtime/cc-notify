# cc-notify

Claude Code 的跨平台通知系统。通过 hooks 提供 Windows Terminal 标签页进度动画和桌面 toast 通知。

## 项目结构

```
cc-notify/
├── terminal-status.sh      # 运行时脚本（Unix/WSL），POSIX sh
├── terminal-status.ps1     # 运行时脚本（Windows），PowerShell 5.1+
├── toast-extract.js        # 从 hook JSON 提取 toast 消息（Node.js）
├── toast.ps1               # Windows toast 发送器（WinRT API）
├── scripts/
│   ├── install.sh          # 安装器（Linux/macOS/WSL）
│   ├── install.ps1         # 安装器（Windows）
│   ├── uninstall.sh        # 卸载器（Linux/macOS/WSL）
│   ├── uninstall.ps1       # 卸载器（Windows）
│   └── merge-hooks.js      # hooks JSON 合并工具
├── README.md               # 英文文档
└── README_ZH.md            # 中文文档
```

## 核心机制

### Hook 状态机

5 个 Claude Code hook 事件驱动 5 个动作：

| Hook 事件 | 动作 | 行为 |
|-----------|------|------|
| SessionStart | `reset` | 清除旧标记和进度 |
| UserPromptSubmit | `working` | 清除标记，显示进度动画 |
| PostToolUse (AskUserQuestion\|ExitPlanMode) | `mark` | 创建标记文件 |
| PermissionRequest (.*) | `alert` | 响铃 + toast，保持动画 |
| Stop | `done` | 清除动画，响铃，根据标记文件选择 toast 消息 |

### 终端写入

Hook 子进程的 stdout 被 Claude Code 重定向到内部管道，无法直接输出到终端：
- **Unix/WSL**：`find_tty()` 遍历进程树找到祖先 Claude 进程的 PTY（`/dev/pts/*`），直接写入该设备
- **Windows**：打开 `CONOUT$` 文件句柄绕过 stdout 重定向

### 转义序列

- `\033]9;4;3;0\007` — OSC 9;4 indeterminate 进度动画（Windows Terminal 专有）
- `\033]9;4;0;0\007` — 清除进度动画
- `\a` (BEL) — 响铃

### Toast 通知

- `toast-extract.js` 从 hook JSON 的 `cwd` 字段提取项目路径最后两段作为消息
- `toast.ps1` 通过 WinRT API 发送，AUMID 为 `Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`
- Toast XML 使用 `activationType="protocol" launch=""` 使点击仅关闭通知

### 标记文件

用于在 `mark` 和 `done` 之间传递状态：
- Unix: `$TMPDIR/claude-hook-asking-$(id -u)`
- Windows: `$env:TEMP/claude-hook-asking`

## 安装器架构

两个安装脚本共享相同的 4 阶段流程：Checks > Plan > Confirm > Execute。

支持双模式运行：
- **本地模式**：从 git clone 目录运行，直接使用本地文件
- **远程模式**：`curl | sh` 或 `irm | iex`，先下载到临时目录

关键参数：`--dry-run`、`-y`/`--yes`

### 卸载器

卸载脚本（`uninstall.sh` / `uninstall.ps1`）与安装脚本相同的 4 阶段流程。自包含设计——hooks 移除逻辑内联 Node.js 代码，不依赖 `merge-hooks.js`，远程卸载无需额外下载。使用相同的 `terminal-status` 指纹匹配 cc-notify hook group。

### merge-hooks.js

- 接口：`node merge-hooks.js <settings-path> <claude-dir> [--windows]`
- 以 `terminal-status` 字符串为指纹识别 cc-notify hook group
- 合并策略：不存在则添加，已有则替换，其他 group 保留
- `--windows` 生成 `powershell.exe -File` 格式命令

### 路径检测

- Claude Code 配置目录：`$CLAUDE_CONFIG_DIR` 环境变量 > `~/.claude` (Unix) / `%USERPROFILE%\.claude` (Windows)
- Windows Terminal 配置：按优先级检测 Store 稳定版 > Preview > 非打包版

## 编码规范

- **Shell**：POSIX sh 兼容（不用 bash-ism），`set -e`，`trap cleanup EXIT`
- **PowerShell**：兼容 5.1+（不用 `\u{xxxx}` 转义，用 `[char]0xXX`）
- **输出风格**：`pad_dots` 点阵对齐，标签 8 字符左对齐，无 emoji，无箭头符号（`->` `→`），需要箭头时用 `>`
- **错误处理**：运行时脚本静默失败（exit 0），安装脚本 `die()` / `Stop-Install` 明确报错
- **临时文件**：总是 trap 清理，mktemp 用 BSD 兼容格式
- **引号安全**：Shell 单引号 + `'"'"'` 转义，PowerShell Start-Process 用单字符串参数而非数组
- **JSON 操作**：一律用 Node.js（避免 jq 依赖和 PowerShell ConvertTo-Json 的深度/排序问题）

## 依赖

- Node.js（必须，所有平台）
- PowerShell 5.1+（Windows 运行时）或 powershell.exe（WSL toast）
- curl（远程安装，Unix）

## 已知限制

- OSC 9;4 仅 Windows Terminal 支持（iTerm2/Ghostty/WezTerm 也已支持，但 Kitty/Alacritty 不支持）
- Toast 仅 Windows 可用（WSL 通过 powershell.exe，纯 Linux/macOS 无 toast）
- 无法通过 toast 点击跳转到对应标签页（WT 不暴露 tab index 给 WSL 进程）
