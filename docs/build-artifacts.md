# 构建产物与版本管理

当前客户端版本为 **0.1.3**，沿用 **0.1.2** 运行组件和协议。本轮改动在 macOS 客户端，不触发远端运行组件升级。

| 位置 | 用途 |
| --- | --- |
| `/Applications/Ash.app` | 日常使用入口，正式构建成功后自动安装或更新 |
| `dist/Ash.app` | 当前构建和打包产物 |
| `dist/Ash-0.1.3-macOS-arm64.zip` | 当前可分发安装包 |
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

## 从源码准备运行组件

需要 Swift 6.2+、macOS SDK、Rust stable、Python 3、Git 和 tmux。只有 `swift test` 需要完整 Xcode；其余检查可用对应版本的 Command Line Tools。

客户端和运行组件分别版本化。0.1.3 发布页提供的运行组件仍为 0.1.2，普通用户下载应用 ZIP 即可。源码构建可使用 GitHub CLI 下载：

```sh
mkdir -p dist
gh release download v0.1.3 --repo betacatsling/ash \
  --pattern 'Ash-runtime-packages-0.1.2.zip' --dir dist
unzip -q dist/Ash-runtime-packages-0.1.2.zip -d dist
python3 scripts/verify-runtime-packages.py

./scripts/build.sh debug
./scripts/test.sh
./scripts/test.sh --ssh
```

需要从头构建运行组件时，见[远端组件构建](remote-updates.md#构建与发布)。不要只改运行端版本号而继续分发旧组件。

正式发布需核对 `Resources/Info.plist` 中的客户端版本、应用签名、arm64 架构、ZIP 解压后的文件和 SHA-256。应用侧栏从 bundle 读取版本，避免多处手动更新。GitHub 标签应指向通过 CI 的提交。

2026-09-06 整理时，确认 0.1.2 ZIP 内的应用程序与 `dist/Ash.app` 一致；归档了 0.1.0、0.1.1 安装包及三个 QA 应用。测试应用逐文件校验压缩包后才移除重复的未压缩副本。原路径、归档路径与 SHA-256 记录在 `dist/archive/inventory-2026-09-06.json`。

本次整理保留了编译缓存和工具链；用户工作区、会话记录及远端运行环境未移动。
