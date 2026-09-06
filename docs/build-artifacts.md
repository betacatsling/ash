# 构建产物与版本管理

当前对外版本为 **0.1.2**。`dist` 顶层只保留当前应用、当前安装包与远端组件。

| 位置 | 用途 |
| --- | --- |
| `/Applications/Ash.app` | 日常使用入口，正式构建成功后自动安装或更新 |
| `dist/Ash.app` | 当前构建和打包产物 |
| `dist/Ash-0.1.2-macOS-arm64.zip` | 当前可分发安装包 |
| `dist/runtime-packages/` | 当前远端运行组件，四个文件分别对应不同系统和处理器，并非四个客户端版本 |
| `dist/archive/releases/<版本>/` | 历史安装包，按版本归档 |
| `dist/archive/qa/` | 历史测试应用，以 ZIP 保存，需要时再解压 |
| `dist/archive/qa/support/` | 历史测试数据、诊断记录与辅助产物 |
| `.build/dev/Ash.app` | `./scripts/build.sh debug` 的开发构建 |
| `.build/`、`runtime/target/`、`.tools/` | 编译缓存、依赖和工具链，不是供日常打开的应用版本 |

## 后续发布约定

1. 开发时运行 `./scripts/build.sh debug`，开发应用输出到 `.build/dev/Ash.app`。
2. 准备发布时运行 `./scripts/build.sh`，生成 `dist/Ash.app` 并自动安装到 `/Applications/Ash.app`，检查版本号并验证功能。只打包不安装时使用 `./scripts/build.sh release --no-install`；安装已有产物使用 `python3 scripts/install-app.py`。
3. 把旧版本 ZIP 移入 `dist/archive/releases/<旧版本>/`，再把验证后的应用打包为 `Ash-<版本>-macOS-arm64.zip`。打包前核对应用确实是 arm64 构建。
4. 同版本重新打包也应先保留旧包，以时间命名归档，避免丢失可回退产物。
5. 测试副本统一使用 `.build/qa/`，完成验证后压缩归档；不要在 `dist` 顶层堆放测试应用。

2026-09-06 整理时，确认 0.1.2 ZIP 内的应用程序与 `dist/Ash.app` 一致；归档了 0.1.0、0.1.1 安装包及三个 QA 应用。测试应用逐文件校验压缩包后才移除重复的未压缩副本。原路径、归档路径与 SHA-256 记录在 `dist/archive/inventory-2026-09-06.json`。

本次整理保留了编译缓存和工具链；用户工作区、会话记录及远端运行环境未移动。
