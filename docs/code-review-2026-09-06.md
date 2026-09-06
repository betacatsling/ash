# 2026-09-06 代码审核与整理

本次检查了应用自身的 Swift、Rust、构建安装脚本和测试入口。目标是整理多轮修改后的职责边界、重复实现与残留代码，保持已有操作、界面布局、运行协议和保存格式兼容。第三方依赖和历史设计提案未重写。

## 结构调整

| 范围 | 整理结果 |
| --- | --- |
| Rust 运行程序 | `main.rs` 只负责命令行入口；`runtime.rs` 管理资源与锁；`models.rs` 定义保存记录；`storage.rs` 管理 SQLite 与工作区恢复；`sessions.rs` 管理调度和执行；`requests.rs` 管理协议路由和各操作。模块使用明确导入，保留原来的加锁范围。 |
| Swift 界面 | 从 `ContentView.swift`、`SidePanelView.swift` 和原来的 `Sheets.swift` 拆出工作区侧栏、终端画布、终端面板、欢迎页、文件预览、Git 检查及各个独立弹窗。视图按实际类型命名，`InspectorView.swift` 改为 `SessionInfoView.swift`。 |
| 浏览器预览 | `PanelBrowserModel.swift` 负责网页状态、SSH 转发及清理；`BrowserPanelView.swift` 保留显示与交互。模型检查不再编译整个浏览器视图，也不再需要占位视图替身。 |
| 本地保存 | `Persistence.swift` 集中管理数据目录、JSON 读取和原子写入，工作区状态和手动任务清单共用。 |
| 状态协调 | AppStore 提取统一会话筛选和快照应用逻辑；保存比较使用主机与工作区共同标识。Rust 统一存活和活动状态判定。 |
| 构建与测试 | `rust-toolchain.sh` 统一 Cargo 查找；`swift-check.sh` 统一独立 Swift 检查的源文件分组；终端测试替身集中到一个文件；合并重复 SSH 测试分支。 |

同时移除了没有调用者的客户端旧 Git 检查入口、未使用的 Agent 描述和时间缓存，简化重复错误文本转换及安装脚本的无效分支，统一终端背景颜色定义。Swift 增加 `.swift-format` 配置；Swift 与 Rust 源码均格式化，展开过度压缩的语句。

运行端的旧 `changes` 和 `agentTasks` 协议操作继续保留，避免影响原有调用方。旧双栏布局字段、Run 状态字符串、工作区和任务清单 JSON 格式、SQLite 表结构及协议版本均保留。

## 修复并增加回归检查

1. **损坏工作区文件可能被覆盖。** 原实现读取失败后提示“原文件已保留”，后续自动保存仍可能用默认状态覆盖它。现在读取失败会阻止该存储实例写回原文件，和任务清单的保护原则一致。
2. **直接 SSH 标签可能在切换托管模式后消失。** 原实现用运行端快照替换全部会话；直接 SSH 会话属于客户端，不会出现在该快照中。现在合并时保留这些会话，仍按原有规则不将直接连接保存到重启缓存。
3. **不同主机具有相同工作区 ID 时保存比较不一致。** 原来的字典只按工作区 ID 建立，可能重复键崩溃或产生错误同步标记。现在比较键包含主机，回归检查验证只标记实际修改的工作区。

以上检查位于 `tests/AppStoreChecks.swift`，验证真实 AppStore 和保存逻辑，只替换原生终端视图。

## 验证结果

- 修改前 `scripts/test.sh` 全部通过，建立原有行为基线。
- 最终 `scripts/test.sh --ssh` 全部通过：10 项 Rust 单元测试、4 组独立 Swift 检查、15 项运行集成检查、Agent 记录检查、文件/Git 面板检查、安装检查，以及隔离 loopback SSH 认证、会话恢复、自动安装升级回退和网页端口转发。
- 原来未被总入口调用的 `panel_integration.py` 和 `panel_ssh_integration.py` 已接入，因此今后运行总入口也会检查这两组功能。
- Rust Clippy 严格检查、Rust 格式检查、Swift 严格格式检查、Python 和 Shell 语法检查通过。
- Swift debug 与 release 构建通过；`scripts/build.sh debug` 成功打包应用。
- macOS / Linux × arm64 / x86_64 四个平台运行包从最终源码重新构建，摘要、大小、归档路径、平台依赖检查通过。Linux 交叉链接器输出一条忽略过时优化选项的工具链警告，构建成功。
- 隔离原生应用检查通过：本地终端创建与输入、中文和 Unicode 输出、任务清单创建、只读文件预览与行号、彩色 Git Diff、新终端标签和双栏分屏。验证完成后已退出测试应用并停止测试会话。

`swift test` 已尝试，但当前仅有 Command Line Tools，报 `no such module 'XCTest'`。不能将其记作通过；本次使用独立 Swift 检查和实际集成测试验证。独立 Linux 机器执行、实际中文输入法候选框、复杂 MFA/跳板和长期压力测试未在本次验收中覆盖。

## 产物与回溯

- 修改前源码备份：`.build/review-backups/before-cleanup-20260906.tar.gz`。
- 最终完整测试日志：`.build/review-backups/final-tests.log`。
- 打包日志：`.build/review-backups/debug-build.log`。
- 原生界面验证记录：`.build/review-backups/ui-smoke.log`。
- 验证应用：`.build/dev/Ash.app`。
- 重建的远端包：`dist/runtime-packages/`。

当前项目目录没有 Git 仓库，因此保留源码压缩备份用于比较和恢复。本次没有替换 `/Applications/Ash.app`，也没有重新发布已有 ZIP 安装包。
