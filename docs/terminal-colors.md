# 终端颜色与进程环境边界

## 外观跟随

终端跟随应用的浅色、深色或系统外观。`TerminalSurface` 读取 SwiftUI 的有效
`colorScheme`，同时更新终端和外围留白；普通终端、分屏和 SSH 认证窗口共用此路径。
`TerminalTheme` 设置默认背景、文字、光标、选区和 16 色 ANSI 调色板。浅色模式使用
较深的彩色文字；深色模式保留原有默认背景、文字和 ANSI 配色。标准 256 色扩展色与
程序指定的 RGB 颜色保持原样，因此具有独立主题的终端程序仍由其自身配置决定外观。

已有终端原位更新，不重建进程、清空内容或调整网格。缓存中的终端重新显示时也会同步
当前外观；只有有效外观改变时才重新应用主题，避免状态轮询覆盖程序自行设置的颜色。

## 进程环境

2026-09-06 修复。

## 根因与复现

实际 Ash 专用 tmux 服务的全局环境包含 `NO_COLOR=1`，同时也包含
`TERM=xterm-256color` 和 `COLORTERM=truecolor`。原先客户端把应用进程环境直接
复制给终端与后台请求；tmux 首次启动时保存这些变量，应用重启后服务仍会继续传给新会话。

fastfetch 2.56.1 在真实 PTY 中的对照结果：设置 `NO_COLOR=1` 时，图标、标题不输出
前景色序列，但 Colors 模块仍输出 `40..47`、`100..107` 背景色；移除变量后恢复
`32`、`33`、`31`、`35`、`34` 等前景色。这解释了截图中的白色苹果图标、白色标题、
彩色调色板与彩色 shell 提示符。程序在产生输出时就关闭了颜色，SwiftTerm 没有丢失它们。

## 处理机制

- `RuntimeClient.environment` 只承担通用进程环境和 PATH，不给后台请求强加终端能力。
- `TerminalEnvironment` 为交互 PTY 单独构建环境：移除从启动器继承的 `NO_COLOR`、
  `FORCE_COLOR`、`CLICOLOR_FORCE`，设置 `CLICOLOR=1`、`TERM=xterm-256color`、
  `COLORTERM=truecolor`、`TERM_PROGRAM=Ash`，替换父终端的版本标识。
- SwiftTerm 启动本地 tmux/SSH 客户端时使用该环境。SSH 远端命令也在进入登录 shell
  或 tmux attach 前设置相同默认值，不依赖 SSH SendEnv/AcceptEnv 转发 COLORTERM。
- Rust `terminal_environment::configure` 在最终启动 shell、命令或 Agent 前应用同一策略，
  防止历史 tmux 服务、旧 scheduler、非交互 SSH 控制连接再次传入禁色设置。
- PATH、认证代理、语言和业务变量继续保留。用户在 shell 配置中设置 `NO_COLOR`，或者
  执行 `NO_COLOR=1 command`，仍可以主动关闭颜色；没有全局设置 FORCE_COLOR。

tmux 中原有真彩色能力配置与 SwiftTerm 保持不变。不能通过重新绘制给没有颜色序列的
旧输出补色。已有 shell 的环境属于运行中的进程，不会在安装更新时被后台修改；在受影响
的旧终端执行一次 `unset NO_COLOR FORCE_COLOR CLICOLOR_FORCE; export CLICOLOR=1 COLORTERM=truecolor`
并重新运行命令即可。新建终端会自动使用修复后的策略。

## 参考实现

- [VS Code 终端环境构建](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/terminal/common/terminalEnvironment.ts)：
  分离基础环境、环境清理、用户覆盖与终端能力标识。Ash 参考的是这种边界设计，具体清理变量由本次根因确定。
- [SwiftTerm 环境构建](https://github.com/migueldeicaza/SwiftTerm/blob/v1.20.0/Sources/SwiftTerm/Terminal.swift)：
  `getEnvironmentVariables` 自行声明 TERM、COLORTERM，并选择继承的环境变量。
- [fastfetch NO_COLOR 行为](https://github.com/fastfetch-cli/fastfetch/blob/dev/CHANGELOG.md)：
  设置 NO_COLOR 会启用禁色的 pipe 模式。
- [tmux 颜色能力说明](https://github.com/tmux/tmux/wiki/FAQ)：
  程序所在终端能力与外部客户端真彩色能力都必须正确声明。

## 验证

- `TerminalEnvironmentChecks`：父进程环境隔离、变量保留、远端 shell 实际执行、用户显式覆盖。
- `terminal_colors_integration.py`：预先创建受污染的真实 tmux 服务，再从干净的请求进程启动
  新程序；验证三路 PTY、ANSI/256/RGB 颜色、服务 PID 未变、原服务仍带 NO_COLOR，以及
  fastfetch 修复前后对照（未安装 fastfetch 时仅跳过该可选对照）。
- 以上检查已加入 `scripts/test.sh`。本机只有 Command Line Tools，`swift test` 无法导入
  XCTest，因此 Swift 回归使用项目已有的独立检查程序机制；正式 Swift 应用构建成功。
- `scripts/test.sh` 全部通过；另行通过 `ssh_integration.py` 与 `bootstrap_integration.py`，
  覆盖 SSH 附着/断开及远端安装升级后原进程保持。
- 已构建四个平台运行组件、更新 `/Applications/Ash.app` 与当前分发 ZIP（旧 ZIP 已归档）。
  重启应用前后三个用户会话的 pane PID 完全一致。实际界面确认旧终端手动清理后恢复颜色，
  新建终端启动时自动运行的 fastfetch 无需任何手动设置即显示彩色图标和标题。
