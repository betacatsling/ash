<div align="center">

# Ash

**为终端与 AI 编程 Agent 准备的原生 macOS 工作台。**

本地项目 · SSH 工作区 · 持久会话 · 多栏分屏

[![macOS](https://img.shields.io/badge/macOS-15%2B-343A35?style=flat-square)](#安装)
[![Preview](https://img.shields.io/badge/version-0.1.2_preview-94633F?style=flat-square)](https://github.com/betacatsling/ash/releases/tag/v0.1.2)
[![License: MIT](https://img.shields.io/badge/license-MIT-58725A?style=flat-square)](LICENSE)

[下载预览版](https://github.com/betacatsling/ash/releases/tag/v0.1.2) · [使用指南](docs/user-guide.md) · [English](README.en.md) · [反馈问题](https://github.com/betacatsling/ash/issues)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/workspace-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/workspace-light.png">
  <img src="docs/images/workspace-light.png" alt="Ash 工作区欢迎页：左侧项目导航，右侧终端与 Agent 入口，简洁的灰阶与铜色界面" width="1040">
</picture>

<p align="center"><sub>原生视图渲染，使用示例工作区。支持浅色与深色外观。</sub></p>

## 为什么做 Ash

当你同时维护本地项目、远程服务器和多个编程 Agent，工作很容易散落在不同终端窗口里。Ash 把这些会话按工作区组织起来，让你能打开项目、并排运行终端、查看改动，并在下次打开时回到原来的工作现场。

界面由 **SwiftUI / AppKit** 构建，终端使用 **SwiftTerm**，运行端使用 **Rust、OpenSSH 和 tmux**。Pi、Codex CLI 与 Claude Code 继续使用各自的登录、模型和权限配置。

## 你可以用它做什么

| 能力 | 使用方式 |
| --- | --- |
| **组织本地与远程项目** | 按主机管理工作区，浏览真实目录，重命名、隐藏与恢复项目。 |
| **并排运行多个终端** | 标签切换、拖放多栏分屏、调整宽度、查找内容、独立命名。 |
| **运行编程 Agent** | 在工作区启动 Pi、Codex CLI 或 Claude Code；支持按主机排队及独立 Git worktree。 |
| **恢复工作现场** | 托管会话在关闭应用后继续运行；重新打开时恢复标签与分屏，断线后自动尝试重新连接。 |
| **就地检查结果** | 在右侧查看文件、逐文件 Git Diff、网页预览与 SSH 转发端口。 |
| **维护工作区待办** | 手动管理任务与子任务，所有终端共享同一份清单。 |

> **开发预览版：** 当前发布的 Mac 客户端面向 Apple Silicon，尚未完成 Developer ID 签名与公证。Linux 支持指远端运行组件，并非 Linux 桌面客户端。

## 安装

需要 **macOS 15+、Apple Silicon 和 tmux 3.3+**。本地托管会话使用系统 tmux：

```sh
brew install tmux
```

1. 从 [v0.1.2 Releases](https://github.com/betacatsling/ash/releases/tag/v0.1.2) 下载 **`Ash-0.1.2-macOS-arm64.zip`**。
2. 解压，将 **Ash.app** 拖入“应用程序”。
3. 打开 Ash，选择本地文件夹或添加 SSH 主机。

预览版使用 ad-hoc 签名，macOS 首次打开可能显示安全提示。请先确认下载来源；需要时按 macOS“系统设置 → 隐私与安全性”中的提示允许打开。发布页提供 SHA-256 校验文件。

使用 Agent 前，请在对应执行主机上安装并登录 [Pi](https://github.com/earendil-works/pi/tree/main/packages/coding-agent)、[Codex CLI](https://github.com/openai/codex) 或 [Claude Code](https://code.claude.com/docs/en/overview)。仅使用普通终端时无需安装 Agent。

## 第一个工作区

1. 按 **⌘O** 打开一个项目文件夹。
2. 按 **⌘T** 打开终端，或按 **⌘N** 创建 Agent 任务。
3. 将终端标签拖到另一个终端的左侧或右侧，即可分屏。
4. 在右边栏的 **＋** 中打开文件、Git Diff、网页或任务清单。

需要隔离代码修改时，可为 Agent 任务启用独立 worktree。它从 Git **HEAD** 创建，不包含尚未提交的改动；普通目录应关闭此选项。

### 关闭终端与退出应用

| 操作 | 结果 |
| --- | --- |
| **⌘W** 或标签上的 **×** | 关闭当前终端；托管会话先停止、再归档。保留文件与执行记录。 |
| 关闭最后一个终端 | 返回工作区欢迎页，应用窗口保持打开。 |
| 收起一个分屏 | 仅收起面板，会话仍保留在标签栏。 |
| 关闭应用窗口或退出 Ash | 断开显示，托管会话在执行主机仍然存活的前提下继续运行。 |

直接 SSH 模式提供普通交互连接，不具备 Ash 托管会话的恢复保证。

## 连接远程主机

在“管理主机”中填写 `user@host` 或已有 SSH config 别名。Ash 沿用系统 OpenSSH 配置，包括端口、密钥与跳板机。

- **直接 SSH**：打开普通远程终端，无需在服务器安装 Ash。
- **托管主机**：支持持久会话、远程工作区与 Agent 任务。首次连接可自动传输并安装应用自带的运行组件，后续随客户端版本更新。

托管组件覆盖 **Linux / macOS × arm64 / x86_64**，包含 tmux。远端无需联网下载组件，也不需要 Rust 或编译器；Git 和 Agent CLI 仍需自行准备。安装使用当前 SSH 用户，不申请 root。

远端主机重启、tmux 退出或任务被终止后，Ash 无法恢复已丢失的进程。Linux 两种架构已完成交叉编译和包检查，独立 Linux 主机上的完整验收仍待补充。[了解连接、升级与恢复机制 →](docs/remote-updates.md)

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开本地文件夹 | ⌘O |
| 新建工作区 | ⇧⌘N |
| 新建终端 / Agent 任务 | ⌘T / ⌘N |
| 关闭当前终端，保留窗口 | ⌘W |
| 选择第 1–9 个终端 | ⌘1–⌘9 |
| 切换到左 / 右终端 | ⌥⌘← / ⌥⌘→ |
| 查找当前终端内容 | ⌘F |
| 切换分屏 | ⌘D |
| 显示或隐藏右边栏 | ⌥⌘I |
| 管理主机 / 设置 | ⇧⌘H / ⌘, |

终端选择快捷键可在设置中修改。双击终端标签可以重命名。[更多终端操作 →](docs/terminal-tabs.md)

## 从源码运行

需要 **Swift 6.2+ / macOS SDK、Rust stable、Python 3、Git 和 tmux**。可使用 Xcode 26+，或提供相应 Swift 版本的 Command Line Tools。

```sh
git clone https://github.com/betacatsling/ash.git
cd ash
cargo build --locked --manifest-path runtime/Cargo.toml
swift run Ash
```

以上适合本地开发，不会生成完整的远端安装资源。打包 `.app` 时，先准备匹配版本的运行组件：

```sh
# 使用 GitHub CLI 下载预编译组件，也可从发布页手动下载。
mkdir -p dist
gh release download v0.1.2 --repo betacatsling/ash \
  --pattern 'Ash-runtime-packages-0.1.2.zip' --dir dist
unzip -q dist/Ash-runtime-packages-0.1.2.zip -d dist
python3 scripts/verify-runtime-packages.py

./scripts/build.sh debug                  # .build/dev/Ash.app
./scripts/build.sh release --no-install   # dist/Ash.app
```

`./scripts/build.sh release` 还会将构建安装到 `/Applications/Ash.app`。若修改了运行端，应更新版本并重新构建四个平台的组件；完整源码构建流程见 [远端组件构建](docs/remote-updates.md#构建与发布)。

### 测试

```sh
# 仅运行端单元测试
cargo test --locked --manifest-path runtime/Cargo.toml

# 完整本地回归，需要先准备上述运行组件
./scripts/test.sh

# 可选：隔离的真实 SSH 测试
./scripts/test.sh --ssh
```

测试使用临时目录和专用 tmux socket，不连接已保存的远程主机，也不调用真实 Agent 模型。完整 Xcode 环境还可运行 `swift test`。[验证范围与已知限制 →](docs/validation.md)

## 数据与边界

- 应用配置和会话缓存保存在 `~/Library/Application Support/Ash/`；执行端数据位于各主机的 `~/.local/share/ash/`。
- Ash 不保存模型 API 密钥，Agent 的鉴权与权限继续由各自 CLI 管理。
- 任务清单由用户手动维护，不等同于 Agent 的内部计划，也不跨设备同步。
- 文件面板是只读预览；Ash 尚不提供完整 IDE、跨主机文件同步、自动合并或定时调度。
- worktree 隔离文件 checkout，不隔离端口、数据库或运行权限。
- 会话退出码为 0，不代表 Agent 的任务目标一定完成；仍应检查产物和差异。

## 文档与贡献

[使用指南](docs/user-guide.md) · [主机管理](docs/host-management.md) · [右侧工作面板](docs/sidebar.md) · [架构](docs/architecture.md) · [设计规范](docs/design-system.md)

欢迎提交问题、改进文档和发起 Pull Request。请先阅读 [贡献指南](CONTRIBUTING.md)；报告问题时请删除日志中的密钥、主机地址和私人路径。漏洞反馈方式见 [安全说明](SECURITY.md)。

## 许可证与致谢

Ash 使用 [MIT License](LICENSE)。感谢 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)、[tmux](https://github.com/tmux/tmux)、[OpenSSH](https://www.openssh.com/) 及 Rust 生态的维护者。依赖保留各自许可证，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

Ash 是独立项目，与上述 Agent 产品的提供方没有隶属关系。
