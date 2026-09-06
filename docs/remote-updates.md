# Ash 0.1.2：SSH 自动安装与更新

日期：2026-09-05；开源发布说明于 2026-09-07 补充。应用使用自带安装包，公开分发见 [GitHub Releases](https://github.com/betacatsling/ash/releases)。

## 使用体验

新增托管主机默认自动安装与更新。SSH 认证成功后，Ash 检查服务器平台和已安装版本，将匹配的安装包传过去，校验并激活，再恢复工作区。服务器不需要联网、Cargo、C 编译器或预先安装 tmux。Git 和各 Agent CLI 仍由用户在服务器上准备。

认证沿用 OpenSSH。需要主机指纹确认、密码或 MFA 时，通过“认证 / 终端”完成，关闭后继续自动准备。主机列表显示检查、校验、传输、恢复和失败信息；失败后可在主机菜单重试。暂停自动安装与更新的主机仍可使用已有运行程序。更新失败但旧版健康且协议兼容时，Ash 会继续使用旧版并显示更新提示，不阻止访问原工作区。

本次自动更新的对象是远端运行环境：更新 Mac 上的 Ash 后，远端随对应版本更新。没有独立“追踪网上 latest”的后台服务，也尚未提供 Mac 应用自身的在线更新渠道。未来配置发布域名、正式签名和公证后，再接入桌面应用更新与在线分发。

## 包与信任来源

应用资源内的 `runtime-packages/manifest.json` 固定运行程序版本、协议、目标平台、文件名、大小和 SHA-256。每个包包含运行程序、tmux 3.6a、静态链接的 libevent/ncurses、所需终端描述及依赖许可证。

| 目标 | 二进制 |
| --- | --- |
| macOS arm64 / x86_64 | 原生 Mach-O，私有依赖静态链接，仅使用系统动态库 |
| Linux arm64 / x86_64 | musl 静态 ELF，无系统动态加载器或 glibc 版本依赖 |

Mac 先校验内置包，再通过已认证的 SSH 传输；服务器再次校验 SHA-256。信任根是用户安装的 Ash 应用及其内置清单，不能把从同一未知服务器下载的散列当成真实性证明。当前仍是本机 ad-hoc 签名开发构建，正式分发需 Developer ID 签名与公证。

清单格式把包选择与传输分开，未来可增加 HTTPS 分发源及本地缓存；本版实际走 SSH 传输，不依赖不存在的下载地址。VS Code 同样支持本地下载后传输的路径，参见 [官方 Remote SSH 说明](https://code.visualstudio.com/docs/remote/ssh)。

## 激活与回退

1. 通过无 PTY SSH 通道探测 OS、CPU 和已安装运行环境，普通控制请求和终端通道沿用原连接配置。
2. 已安装兼容的相同或更新版本时直接使用。旧客户端不会降级服务器；协议不兼容时提示更新客户端。
3. 校验本地包并传输到执行主机的私有临时目录；远端校验失败不修改入口。
4. 候选程序验证平台、版本、协议及随包 tmux 是否可运行。
5. 使用操作系统文件锁串行激活。安装到 `~/.local/share/ash/versions/<version>-<digest>-<nonce>/`，每次激活独立目录。
6. 原子替换 `~/.local/bin/ash-runtime` 启动入口。通过真实 health 请求检查新版本，失败时原子恢复之前的入口；首次安装失败则撤回新入口。
7. 恢复现有会话。旧执行监督进程继续运行旧版本，不迁移其进程内存。调度器在受运行锁保护的操作中交接，新任务使用新版本，现有任务不被终止。

文件锁由操作系统管理，安装进程崩溃或 SSH 断开不会留下永久锁。传输与校验在切换之前完成，已有数据、工作区和 tmux 服务不属于安装器的清理范围。历史版本暂不自动删除，避免删除活进程仍引用的文件。

自动检查使用每主机任务去重、成功缓存和失败退避：同一客户端不会并发重复上传；正常连接每五分钟重新检查，错误后下一次检查退避一分钟，手动重试和认证完成可立即重试。不同客户端在服务器激活锁内再次检查是否会降级。

## 构建与发布

应用构建不会在用户服务器上编译。开发机器一次准备交叉工具链：

```sh
python3 -m venv .tools/cross
.tools/cross/bin/pip install ziglang==0.13.0 cargo-zigbuild==0.23.3
# 为 cargo-zigbuild 提供 Zig 可执行文件。
.tools/cross/bin/python - <<'PYTHON'
from pathlib import Path
import sysconfig
zig = Path(sysconfig.get_paths()["purelib"]) / "ziglang" / "zig"
link = Path(".tools/cross/bin/zig")
if not link.exists():
    link.symlink_to(zig.resolve())
PYTHON
# 先通过 rustup 安装 Rust stable；使用 PATH 上的工具链，或项目内 .tools 工具链。
./scripts/build-runtime-packages.sh
./scripts/build.sh release
```

`build-portable.py` 从固定官方源码地址下载依赖并验证固定 SHA-256，在项目目录中构建，不向系统安装文件。`package-runtimes.py` 打包四个平台并产生清单。`verify-runtime-packages.py` 检查散列、包路径、目标架构、Linux 静态链接和 macOS 动态依赖。缺少包或清单版本不匹配时，应用打包失败，避免发布带有不完整安装功能的构建。

修改运行程序应增加版本号，重建四个平台的包，再构建应用。正式发布流程应在 Linux arm64/x86_64 与 macOS 测试机运行安装和更新验收后签名、归档并发布。

## 验证边界

`./scripts/test.sh --ssh` 使用临时密钥、固定主机公钥、隔离的 loopback sshd 和临时执行目录，不连接用户保存的主机。新增测试覆盖真实 AppStore 首次连接自动安装、重复检查、并发准备、坏包与中断传输、升级后相同 Shell PID 与环境变量、调度器交接、激活失败回退以及拒绝降级。

Linux 两个架构完成交叉编译和包结构检查；本机无法直接执行 Linux 程序，独立 Linux 安装与长时间运行验证仍未完成。
