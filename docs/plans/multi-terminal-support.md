# 多终端支持调研与规划

> 调研日期：2026-03-04

## 背景

cc-notify 当前仅针对 Windows Terminal 实现进度动画（OSC 9;4）和 toast 通知（PowerShell WinRT）。本文调研将支持范围扩展到其他主流终端的可行性。

## 终端能力矩阵

### 进度动画（OSC 9;4）

| 终端 | 支持 | 版本要求 | 显示形式 |
|------|------|----------|----------|
| Windows Terminal | Yes | 原始实现 | Tab 图标 + 任务栏 |
| iTerm2 | Yes | v3.5.6+ | Tab 饼图动画 |
| Ghostty | Yes | v1.2.0+ | 窗口顶部原生进度条 |
| WezTerm | Yes | 2025-02+ | Tab 栏，Lua API 可读取 |
| Konsole | Yes | KDE Gear 2025-04 | Tab 栏 |
| VTE/Ptyxis | Yes | 2024-12+ | 原生 widget |
| Kitty | **No** | N/A | 维护者拒绝，与 OSC 9 通知冲突 |
| Alacritty | **No** | N/A | Issue #5201 无计划 |
| foot | **No** | N/A | 静默忽略 |
| GNOME Terminal | 部分 | 依赖发行版 VTE 补丁 | 取决于发行版 |
| Hyper | 需插件 | @xterm/addon-progress | 非原生 |
| tmux | 透传 | 3.3+ (allow-passthrough) | 依赖外层终端 |

**结论**：OSC 9;4 已被广泛采纳（受 systemd v257 推动），当前代码无需修改即可在 iTerm2/Ghostty/WezTerm 上工作。关键例外是 Kitty——它将 `OSC 9;*` 解释为通知文本，必须跳过。

### 桌面通知转义序列

| 终端 | OSC 9 | OSC 777 | OSC 99 |
|------|-------|---------|--------|
| iTerm2 | Yes | No | No |
| Ghostty | Yes | Yes | 计划 v1.3 |
| WezTerm | Yes | Yes | No |
| Kitty | Yes (旧) | No | **Yes** (原生) |
| Konsole | No | Yes | No |
| foot | No | Yes | No |
| GNOME Terminal | No | 部分 (Fedora VTE 补丁) | No |
| Alacritty | No | No | No |
| Windows Terminal | No (OSC 9 = 进度) | No | No |

**协议说明**：

- **OSC 9**：`\033]9;message\007`。iTerm2 发起，Ghostty/WezTerm 支持。注意 Windows Terminal 将 OSC 9 用于进度而非通知。
- **OSC 777**：`\033]777;notify;title;body\007`。rxvt-unicode 发起。标题和正文不能包含分号。
- **OSC 99**：`\033]99;metadata;payload\033\\`。Kitty 原生协议，功能最丰富（标题/正文/优先级/图标/按钮/分块/base64）。

### Bell（BEL / `\a`）行为

所有终端均支持 BEL，行为包括：音频响铃、视觉闪烁、任务栏/Dock 高亮。BEL 可透传 tmux，是最通用的注意力机制。

当前实现已使用 BEL，无需修改。

### 平台原生通知（终端无关的回退方案）

| 平台 | 命令 | 可用性 |
|------|------|--------|
| macOS | `osascript -e 'display notification "body" with title "title"'` | 系统自带 |
| Linux | `notify-send -u normal "title" "body"` | 需 libnotify（多数桌面环境预装） |
| Windows | 当前 PowerShell WinRT 实现 | 已有 |

### tmux 支持策略

1. BEL 默认透传（无需配置）
2. DCS passthrough 传递 OSC 序列到外层终端：`\033Ptmux;\033\033]9;4;3;0\007\033\\`（需 `allow-passthrough on`，tmux 3.3+）
3. `tmux display-message` 作为状态栏内指示器
4. 平台原生通知（`notify-send` / `osascript`）在 tmux 内同样可用

### iTerm2 专有序列

| 序列 | 用途 |
|------|------|
| `OSC 1337;RequestAttention=yes` | Dock 持续弹跳 |
| `OSC 1337;RequestAttention=once` | Dock 单次弹跳 |
| `OSC 1337;RequestAttention=fireworks` | 光标处烟花效果 |
| `OSC 1337;SetBadgeFormat=<base64>` | 设置 badge 文本 |
| `OSC 9;message` | 桌面通知 |

## 终端检测方案

通过环境变量识别终端类型：

```sh
detect_terminal() {
  case "${TERM_PROGRAM:-}" in
    iTerm.app)  echo "iterm2" ; return ;;
    WezTerm)    echo "wezterm" ; return ;;
    ghostty)    echo "ghostty" ; return ;;
  esac
  [ -n "${KITTY_WINDOW_ID:-}" ]  && echo "kitty"            && return
  [ -n "${WT_SESSION:-}" ]       && echo "windows-terminal"  && return
  [ -n "${KONSOLE_VERSION:-}" ]  && echo "konsole"           && return
  [ -n "${VTE_VERSION:-}" ]      && echo "vte"               && return
  [ -n "${TMUX:-}" ]             && echo "tmux"              && return
  # foot: TERM=foot or foot-extra
  # Alacritty: TERM_PROGRAM=Alacritty (v0.13+)
  echo "unknown"
}
```

## 实施规划

### 阶段一：平台原生通知回退（高收益低成本）

**目标**：解决非 WSL 环境 toast 不可用的问题，约 50-80 行新增代码。

1. 在 `terminal-status.sh` 中添加终端检测函数
2. 替换 `send_toast()` 为分发函数：
   - WSL：保持现有 `powershell.exe` toast
   - macOS：`osascript -e 'display notification ...'`
   - Linux（非 WSL）：`notify-send`（检测可用性）
3. 对 Kitty 跳过 OSC 9;4（避免误触发通知）
4. OSC 9;4 对其他未知终端保持发送（大多数会静默忽略）

**覆盖率**：~90% 用户获得某种形式的通知。

### 阶段二：多协议通知分发

**目标**：通过终端原生转义序列提供更好的通知体验。

1. 根据检测到的终端选择最佳通知协议：
   - iTerm2：`OSC 9` 通知
   - Ghostty/WezTerm/Konsole/foot：`OSC 777` 通知
   - Kitty：`OSC 99` 通知
   - 其他：平台原生回退
2. tmux DCS passthrough 支持
3. iTerm2 `RequestAttention` Dock 弹跳

### 阶段三：进阶功能

- 用户可配置终端类型覆盖（环境变量 `CC_NOTIFY_TERMINAL`）
- 通知优先级/静默模式
- 自定义通知消息模板

## 优先级排序

| 优先级 | 目标 | 工作量 | 理由 |
|--------|------|--------|------|
| 1 | 平台原生通知回退 | 低 | 覆盖所有终端，3 行核心代码 |
| 2 | tmux 支持 | 中 | CLI 高级用户常用 |
| 3 | Ghostty | 低 | 增长迅速，OSC 9 + OSC 777 + OSC 9;4 全支持 |
| 4 | iTerm2 | 低 | macOS 主流终端，OSC 9 通知 + OSC 9;4 进度 |
| 5 | WezTerm | 低 | 跨平台，OSC 777 + OSC 9;4 |
| 6 | Kitty | 中 | 需 OSC 99（不同协议），无 OSC 9;4 |
| 7 | Konsole | 低 | OSC 777 + OSC 9;4 |
| 8 | foot | 低 | OSC 777，Wayland 小众 |
| 9 | Alacritty | N/A | 明确拒绝通知功能，仅可用 bell + 平台原生回退 |
| 10 | Hyper | N/A | 无通知转义支持，仅平台原生回退 |

## 参考资料

- [Kitty OSC 99 桌面通知协议](https://sw.kovidgoyal.net/kitty/desktop-notifications/)
- [OSC 9;4 进度条序列参考](https://rockorager.dev/misc/osc-9-4-progress-bars/)
- [iTerm2 专有转义码](https://iterm2.com/documentation-escape-codes.html)
- [WezTerm 转义序列](https://wezterm.org/escape-sequences.html)
- [Ghostty 1.2.0 发布说明](https://ghostty.org/docs/install/release-notes/1-2-0)
- [Ghostty OSC 99 Issue (v1.3)](https://github.com/ghostty-org/ghostty/issues/5634)
- [Alacritty OSC 通知 Issue #7105](https://github.com/alacritty/alacritty/issues/7105)
- [Konsole OSC 9;4 MR](https://invent.kde.org/utilities/konsole/-/merge_requests/1054)
- [VTE/Ptyxis 进度支持 (2024-12)](https://blogs.gnome.org/chergert/2024/12/03/ptyxis-progress-support/)
- [tmux allow-passthrough](https://tmuxai.dev/tmux-allow-passthrough/)
