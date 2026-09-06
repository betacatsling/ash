# 使用指南

[返回项目首页](../README.md)

原生 macOS 终端与 Agent 工作空间。使用 SwiftUI / AppKit 构建界面，SwiftTerm 显示终端，Rust 运行程序管理本地与远端任务，OpenSSH 与 tmux 提供连接和托管会话。

当前版本：**0.1.2，开发预览版**。设计方案见 [架构文档](architecture.md)，实际实现取舍见 [v0.1 实现说明](v0.1-implementation.md)，SSH 恢复机制见 [v0.1.1 更新说明](v0.1.1-recovery.md)，自动安装与更新见 [远端更新说明](remote-updates.md)。

## 开始使用

发布构建会自动安装到 `/Applications/Ash.app`，日常从“应用程序”打开 Ash。项目内 `dist/Ash.app` 保留为构建和打包产物。

当前安装包为 `dist/Ash-0.1.2-macOS-arm64.zip`。旧版本统一放在 `dist/archive/releases/`，历史测试应用压缩保存在 `dist/archive/qa/`。目录约定见 [构建产物说明](build-artifacts.md)。

1. 打开本地文件夹，或在“管理主机”中添加 SSH 主机。“添加”仅保存配置，“添加并连接”立即检查连接；主机设置可在列表中展开和编辑。详见 [主机管理](host-management.md)。
2. `⌘T` 打开托管终端，`⌘N` 新建 Agent 任务。
3. 选择 **Pi / Codex CLI / Claude Code**，填写任务说明。
4. 修改 Git 项目时，可为任务创建独立 worktree。它从 HEAD 开始，不复制未提交改动；普通目录应关闭此选项。
5. 在右边栏的「+」打开文件、端口或网页、Git Diff；「任务清单」管理工作区手动任务，「会话信息」提供进程信息、停止、重试、归档和导出。文件区为左侧内容、右侧目录树，点击文件会在同一个标签内切换内容；各功能可切换标签，侧栏宽度可拖动调整。详见 [右边栏说明](sidebar.md)。

添加工作区时，路径框下方会列出当前主机的真实目录，支持输入筛选、逐层浏览和键盘选择。详见 [目录选择与静默刷新](workspace-directory-picker.md)。

Agent 登录、模型和权限沿用各自 CLI 配置。Ash 不添加绕过权限的启动参数，不存储模型 API 密钥。交互 Agent 等待输入时仍占用一个并发位置。

## 已实现

- 原生 macOS 窗口、菜单、快捷键、系统明暗外观和可调终端字号。
- 本地工作区、远端工作区、重命名、隐藏与恢复工作区。
- 多会话标签、拖放多栏分屏、终端搜索、复制粘贴、中文与 Unicode 显示。
- 系统 OpenSSH、已有主机别名发现、交互认证窗口、连接复用和直接 SSH。
- Pi、Codex CLI、Claude Code 交互入口，初始 prompt 以独立参数传递。
- 每主机并发限制、后台排队、取消、重试、独立 Git worktree。
- SQLite 执行记录、稳定 Run ID、幂等启动、调度器恢复与会话对账。
- Git 状态、相对执行基准的 diff、未跟踪文件列表、最近终端内容导出。
- 右边栏多标签工作面板：本地/远程文件树、带行号的只读文本预览、逐文件彩色 Git Diff、内嵌网页与 SSH 端口转发。
- 工作区手动任务清单：任务与子任务两层，编辑、勾选、折叠、排序和删除；所有终端共用，退出重开后保留。
- 退出 GUI 后托管会话继续；重开自动恢复会话，断线后自动重新附着。
- 执行主机持久保存工作区名称、目录、分屏和会话关联；本地工作区清单丢失时，可从已配置的托管主机恢复。
- 托管 SSH 首次连接自动安装，后续随客户端版本自动更新；应用自带 Linux / macOS、arm64 / x86_64 安装包和 tmux。
- 校验安装包、版本目录隔离、原子切换、激活失败回退、并发安装合并和禁止降级。

## 系统依赖

- macOS 15+。当前构建实际验证于 Apple Silicon Mac。
- 本地安装 **tmux 3.3+**，例如 `brew install tmux`。
- Agent CLI 已安装且可在运行程序 PATH 中找到。额外搜索 `~/.local/bin`、`~/.cargo/bin`、`/opt/homebrew/bin`、`/usr/local/bin`。
- 运行程序使用系统 Git。创建 worktree 需要 Git 仓库至少已有一个 commit。

当前 `.app` 为本机 ad-hoc 签名开发构建，未进行 Developer ID 签名、公证或 Mac 客户端的在线更新发布。本地会话仍使用系统 tmux；远端自动安装包已包含 tmux。

## SSH 与远端安装

“直接 SSH”无需远端安装 Ash。它提供交互终端，并继承系统 OpenSSH 配置。完整远端工作区和 Agent 编排需要开启“托管主机”；新添加的主机默认开启托管模式。

1. 添加 `user@host` 或 SSH config 别名，保留“托管终端与工作区”和“自动安装与更新”两个选项。
2. 首次主机指纹确认、密码或 MFA 认证通过“认证 / 终端”完成，关闭认证窗口后会自动继续准备。
3. Ash 识别服务器平台，自动传输应用自带的安装包，校验并安装到当前用户目录。服务器不需要联网下载，也不需要 Rust/Cargo、编译器或手动安装 tmux。
4. 添加远程工作区，填写服务器上的绝对路径。使用 Agent 时，仍需在远端安装并登录对应 CLI；Git 功能需要远端已有 Git。

更新 Ash 客户端后，下次连接会自动准备对应的远端版本。已有终端保持原进程；新版本校验或启动失败时保留原入口。主机菜单中的“检查更新 / 修复连接”可手动重试，“暂停自动安装与更新”用于自行管理运行程序的主机。

自动安装沿用当前 SSH 信任链，以普通用户权限运行，不申请 root，不修改 SSH 配置，不开放额外公网端口。已有直接 SSH 会话不会自动迁移；开启托管模式后新建终端即可获得保活与恢复。

独立命令行入口也使用相同的预编译安装包（本地需要 Python 3）：

```sh
./scripts/install-remote.sh user@host
```

本版包含 Linux/macOS 的 arm64、x86_64 四种包。Linux 二进制静态链接，不依赖服务器的 glibc 版本；macOS 包仅依赖系统动态库。真实自动安装、升级与断线测试运行于隔离 loopback SSH；独立 Linux 机器的实际验收仍待完成。

## 构建

需要 Swift 6.2+ / macOS SDK 和 Rust stable。无需通过 Xcode 工程构建；本项目使用 Swift Package Manager。

```sh
./scripts/build.sh
# 或快速开发构建
./scripts/build.sh debug
# 仅生成发布应用，不安装到本机
./scripts/build.sh release --no-install
# 安装已经构建好的当前应用
python3 scripts/install-app.py
```

首次从源码构建还需先运行 `./scripts/build-runtime-packages.sh` 生成四个平台的远端安装包；工具链准备见 [远端更新说明](remote-updates.md)。已有安装包时，普通界面修改只需运行上述应用构建命令。

正式构建生成 `dist/Ash.app`，签名完成后自动安装或更新 `/Applications/Ash.app`；`debug` 构建只输出到 `.build/dev/Ash.app`。安装先校验完整的新应用再替换旧应用，替换失败时恢复旧应用；不会自动退出正在运行的 Ash，也不修改会话数据。安装目录不可写时会明确报错，构建产物仍保留；可用 `--no-install` 跳过本机安装。ZIP 安装包需在发布时另行打包，下载 ZIP 后解压不会自动安装。脚本优先使用 PATH 上的 Cargo，也支持项目内 `.tools/cargo` / `.tools/rustup`。构建依赖固定在 `Package.resolved` 和 `runtime/Cargo.lock`。

没有 Rust 时可按官方 rustup 安装方式准备工具链。也可以使用项目内的独立 Rust 工具链，构建脚本会在 PATH 上没有 Cargo 时尝试 `.tools/cargo`。

## 验证

```sh
./scripts/test.sh
# macOS 上可选的隔离真实 SSH 测试
./scripts/test.sh --ssh
# 安装了完整 Xcode 时，也可运行 XCTest 版本
swift test
```

测试使用临时目录、临时 Git 仓库和 Ash 专属 tmux socket，不连接已保存的远端主机，不向 Agent 发送模型任务。

`tests/ModelChecks.swift` 可在只有 Command Line Tools、没有 XCTest 的机器上验证 Swift 模型和 SSH 参数处理。测试结果与人工检查范围见 [验证记录](validation.md)，本次结构整理及完整回归见 [2026-09-06 代码审核](code-review-2026-09-06.md)。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开本地文件夹 | ⌘O |
| 新建工作区 | ⇧⌘N |
| 新建终端 | ⌘T |
| 关闭当前终端（保留应用窗口） | ⌘W |
| 新建 Agent 任务 | ⌘N |
| 选中第 1–9 个终端 | ⌘1–⌘9 |
| 切换到左 / 右侧终端（首尾循环） | ⌥⌘← / ⌥⌘→ |
| 查找当前终端内容 | ⌘F（Esc 关闭） |
| 切换分屏 / 收起为当前终端 | ⌘D |
| 显示或隐藏右边栏 | ⌥⌘I |
| 管理主机 | ⇧⌘H |
| 设置 | ⌘, |

在「设置 → 终端快捷键」统一配置「按编号切换终端」和左、右切换，共三项。编号切换只需录入修饰键加任意数字 1–9，即可同时更新整组数字键；默认 ⌘1–⌘9。Esc 取消录入；修改立即保存，支持冲突提示和恢复默认。数字键按标签从左到右选择，不足对应数量时不执行；分屏时优先聚焦已显示的终端，否则替换当前面板。

双击终端标签，或右键选择「重命名…」，可以为每个终端设置独立名称；支持中文和恢复原名称。名称保存在当前 Mac，后台刷新和重启后保留，本地与 SSH 终端均可使用。

选中的终端标签显示关闭叉号，也可右键选择「关闭终端」。关闭会停止会话并归档记录，保留工作区与文件；停止失败时保留标签并提示错误。关闭后选择相邻标签；分屏时保留其余面板。

按 ⌘W 同样关闭当前选中的终端；分屏时只关闭当前面板对应的会话。关闭最后一个终端后返回工作区欢迎页，应用窗口保持打开。没有终端或正在操作弹窗时，该快捷键不关闭窗口或后台终端。

终端内容直接接在标签栏下方。按 ⌘F 在当前终端右上角打开查找浮层，输入后高亮匹配，Enter 或上下箭头切换结果；Esc 关闭并回到终端输入。浮层不改变终端尺寸。终端输出持续更新，托管连接中断会自动重连，无需手动刷新。

拖动顶部会话标签，移到另一个终端的左半边或右半边；高亮区域会预览落点，松开后就在对应一侧分屏。可以继续拖入更多会话，也可以拖动已经显示的终端调整左右顺序。拖动分隔线可调整宽度；分屏较多时可以水平滚动。

点击终端会将其设为当前面板。点击尚未显示的标签只替换当前面板；点击已显示的标签直接聚焦对应终端。右键点击标签，选择「收起此分屏」只收起面板，会话仍保留在标签栏。⌘D 可快速分成两栏或收起为当前终端。分屏顺序随工作区保存，并同步到支持该字段的新版托管主机；旧版双栏布局会自动兼容。同一个会话始终只显示在一个面板中，拖动不会重新启动进程。

窗口顶部只保留标签栏和必要的侧栏开关；新建终端使用标签旁的「+」或 ⌘T。左侧栏开关位于工作区标题旁，收起后出现在终端标签左边；右侧栏开关位于标签栏右端。

## 数据和生命周期

- 客户端布局、工作区与最近会话缓存：`~/Library/Application Support/Ash/state.json`。
- 人工任务清单：`~/Library/Application Support/Ash/workspace-tasks.json`，按主机和工作区分开保存，不按终端会话区分。
- 自动安装的运行环境：`~/.local/share/ash/versions/`，入口 `~/.local/bin/ash-runtime`。
- 每台执行主机的记录、日志、worktree、tmux socket：`~/.local/share/ash/`。
- Ash 自有 SSH 复用 socket：`~/.local/share/ash/ssh/`。
- 执行端 SQLite 同时保存工作区清单和布局备份；已有本地布局及离线编辑优先，缺失的工作区从服务器导入。
- 每个托管会话为独立 tmux session；后台队列由 Ash 自有 `ash-scheduler` session 中的运行程序处理。

收起分屏、关闭窗口或退出应用只断开显示；标签上的叉号会停止并归档该会话。要终止任务，使用“停止会话”。归档保留记录，隐藏工作区保留目录和会话。首版不提供自动删除 worktree、自动提交或自动合并。

主机重启或 tmux 服务退出会丢失活进程；Ash 保留执行记录并标记中断。Mac 睡眠期间本地任务不保证推进；远端任务在远端仍存活的前提下继续。

调试可设置 `ASH_APP_HOME`、`ASH_RUNTIME_HOME`、`ASH_RUNTIME_BIN`、`ASH_INITIAL_WORKSPACE`。不要把它们指向敏感或共享可写目录。

## 当前边界

- 状态是排队、启动、运行、退出、中断或停止。未接入三个 Provider 的结构化“思考/等待输入/完成”事件，退出码 0 不等于任务目标完成。
- 任务清单仅由用户手动管理，不读取或同步 Claude Code、Codex CLI 的计划。清单保存在当前 Mac，跨会话共用；暂不提供跨设备或多人同步。
- 当前结果检查覆盖 Git diff 和有限的终端记录；未跟踪文件内容不在 diff 中，不保证导出整个无限历史。
- 不包含跨主机文件同步、任务依赖图、调度定时器、模型路由、完整 IDE 或 GPU 性能承诺。
- worktree 隔离文件 checkout，不隔离端口、数据库、缓存或网络权限。
- Agent 自己守护化、脱离前台进程组的子进程不在首版的强制取消保证内。
- 尚未完成输入法候选框、VoiceOver、所有现代图形协议与长时间性能验收。

## 项目结构

代码按界面、状态协调、存储、运行调度和协议请求划分；具体模块职责见 [代码审核与整理](code-review-2026-09-06.md)。独立 Swift 检查统一通过 `scripts/swift-check.sh` 编译。

```text
Sources/Ash/       SwiftUI / AppKit 应用、终端适配、SSH 客户端
runtime/           Rust 主机运行程序与 SQLite / tmux / Git 实现
tests/             独立 Swift 检查与真实运行/SSH 集成测试
tests/AshTests/    完整 Xcode 环境下的 XCTest 模型测试
scripts/           构建、测试、图标生成、远端安装
Resources/         应用元数据
docs/              架构、实现决策、验证记录
```

依赖来源： [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)、[tmux](https://github.com/tmux/tmux)、[OpenSSH](https://www.openssh.com/)。Agent 启动方式参考 [Pi](https://github.com/earendil-works/pi/tree/main/packages/coding-agent)、[Codex CLI](https://developers.openai.com/codex/cli/reference)、[Claude Code](https://code.claude.com/docs/en/cli-reference)。
