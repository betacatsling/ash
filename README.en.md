<div align="center">

# Ash

**A native macOS workspace for terminals and AI coding agents.**

Local projects · SSH workspaces · Persistent sessions · Split terminals

[![macOS](https://img.shields.io/badge/macOS-15%2B-343A35?style=flat-square)](#install)
[![Preview](https://img.shields.io/badge/version-0.1.2_preview-94633F?style=flat-square)](https://github.com/betacatsling/ash/releases/tag/v0.1.2)
[![License: MIT](https://img.shields.io/badge/license-MIT-58725A?style=flat-square)](LICENSE)

[Download](https://github.com/betacatsling/ash/releases/tag/v0.1.2) · [简体中文](README.md) · [Report an issue](https://github.com/betacatsling/ash/issues)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/workspace-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/workspace-light.png">
  <img src="docs/images/workspace-light.png" alt="Ash workspace welcome screen with project navigation and terminal and agent entry points" width="1040">
</picture>

<p align="center"><sub>Native views rendered with sample workspace data. Light and dark appearances are supported; the current app interface is in Chinese.</sub></p>

## Why Ash

Working across local projects, remote servers, and coding agents often means keeping track of a growing collection of terminal windows. Ash organizes those sessions into workspaces so you can run terminals side by side, inspect changes, and return to the same working context later.

The interface is built with **SwiftUI / AppKit**, terminal rendering uses **SwiftTerm**, and **Rust, OpenSSH, and tmux** manage execution. Pi, Codex CLI, and Claude Code keep their own authentication, model settings, and permission controls.

## What it does

| Capability | In practice |
| --- | --- |
| **Local and remote workspaces** | Organize projects by host, browse real directories, and rename, hide, or restore workspaces. |
| **Split terminals** | Switch tabs, drag them into multiple columns, resize panes, search output, and name each terminal. |
| **Coding agents** | Start Pi, Codex CLI, or Claude Code, with per-host queuing and optional Git worktree isolation. |
| **Persistent sessions** | Managed sessions survive closing the app while the host process remains alive. Reopen to restore tabs and layouts; interrupted connections retry automatically. |
| **Results alongside your terminal** | Preview files, inspect per-file Git diffs, open web pages, and forward remote development ports through SSH. |
| **Workspace checklists** | Maintain manual tasks and subtasks shared by all terminals in a workspace. |

> **Developer preview:** The downloadable Mac client targets Apple Silicon and is not Developer ID signed or notarized. Linux support refers to the remote runtime, not a Linux desktop app.

## Install

Requires **macOS 15+, Apple Silicon, and tmux 3.3+**. Local managed sessions use your installed tmux:

```sh
brew install tmux
```

1. Download **`Ash-0.1.2-macOS-arm64.zip`** from [v0.1.2 Releases](https://github.com/betacatsling/ash/releases/tag/v0.1.2).
2. Unzip it and drag **Ash.app** into Applications.
3. Open Ash and choose a local folder or add an SSH host.

This preview uses ad-hoc signing. macOS may show a security prompt on first launch. Verify the download source, then follow the prompt under System Settings → Privacy & Security if needed. SHA-256 checksums are included on the release page.

To use an agent, install and sign in to [Pi](https://github.com/earendil-works/pi/tree/main/packages/coding-agent), [Codex CLI](https://github.com/openai/codex), or [Claude Code](https://code.claude.com/docs/en/overview) on the machine where it will run. Ordinary terminals do not require an agent.

## Your first workspace

1. Press **⌘O** to open a project folder.
2. Press **⌘T** for a terminal or **⌘N** for an agent task.
3. Drag a terminal tab to the left or right half of another terminal to split the workspace.
4. Use **＋** in the right panel to open files, Git Diff, a web preview, or your checklist.

Optional worktrees start from Git **HEAD** and do not copy uncommitted changes. Turn this option off for directories that are not Git repositories.

### Closing a terminal versus leaving the app

| Action | Result |
| --- | --- |
| **⌘W** or the tab's **×** | Closes the selected terminal. Managed sessions are stopped and archived; files and execution records remain. |
| Close the last terminal | Returns to the workspace welcome screen and keeps the app window open. |
| Collapse a split pane | Hides the pane while keeping the session in its tab. |
| Close the app window or quit Ash | Detaches the display. Managed sessions continue while their host processes remain alive. |

Direct SSH provides an ordinary interactive connection, without Ash's managed-session recovery guarantees.

## Remote hosts

Add `user@host` or an existing SSH config alias in the host manager. Ash uses system OpenSSH settings, including ports, identity files, and jump hosts.

- **Direct SSH:** An interactive remote terminal with no Ash installation on the server.
- **Managed host:** Persistent terminals, remote workspaces, and agent tasks. Ash can transfer its bundled runtime on first connection and update it with later client versions.

Runtime bundles cover **Linux / macOS × arm64 / x86_64** and include tmux. The remote machine does not need Internet access to download the bundle, Rust, or a compiler. Git and agent CLIs remain your responsibility. Installation uses the current SSH user without requesting root.

A host reboot, tmux exit, or terminated task cannot be recovered into the original live process. Linux bundles are cross-compiled and structurally checked; full acceptance testing on independent Linux hosts is still pending. [Remote installation and recovery details (Chinese) →](docs/remote-updates.md)

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open a local folder | ⌘O |
| New workspace | ⇧⌘N |
| New terminal / agent task | ⌘T / ⌘N |
| Close the current terminal, keep the window | ⌘W |
| Select terminal 1–9 | ⌘1–⌘9 |
| Previous / next terminal | ⌥⌘← / ⌥⌘→ |
| Search the current terminal | ⌘F |
| Toggle split view | ⌘D |
| Toggle the right panel | ⌥⌘I |
| Host manager / settings | ⇧⌘H / ⌘, |

Terminal navigation shortcuts are customizable in settings. Double-click a tab to rename it.

## Run from source

Requires **Swift 6.2+ / macOS SDK, Rust stable, Python 3, Git, and tmux**. Use Xcode 26+ or Command Line Tools with a compatible Swift version.

```sh
git clone https://github.com/betacatsling/ash.git
cd ash
cargo build --locked --manifest-path runtime/Cargo.toml
swift run Ash
```

This is the local development path; it does not bundle remote installation resources. To package the full app, obtain the matching runtime bundles first:

```sh
# GitHub CLI is optional; the same ZIP is available on the release page.
mkdir -p dist
gh release download v0.1.2 --repo betacatsling/ash \
  --pattern 'Ash-runtime-packages-0.1.2.zip' --dir dist
unzip -q dist/Ash-runtime-packages-0.1.2.zip -d dist
python3 scripts/verify-runtime-packages.py

./scripts/build.sh debug                  # .build/dev/Ash.app
./scripts/build.sh release --no-install   # dist/Ash.app
```

`./scripts/build.sh release` also installs the result into `/Applications/Ash.app`. Runtime changes require a version bump and fresh bundles for all four targets. See the [full runtime build instructions (Chinese)](docs/remote-updates.md#构建与发布).

### Tests

```sh
cargo test --locked --manifest-path runtime/Cargo.toml
./scripts/test.sh        # Full regression suite; prepare runtime bundles first.
./scripts/test.sh --ssh  # Optional isolated, real SSH tests.
```

Tests use temporary directories and dedicated tmux sockets. They do not connect to saved remote hosts or submit requests to real agent models. With full Xcode installed, you can also run `swift test`.

## Data and current limits

- Client state lives in `~/Library/Application Support/Ash/`; execution data lives in `~/.local/share/ash/` on each host.
- Ash does not store model API keys. Agent authentication and permissions remain with each CLI.
- Checklists are maintained manually, do not represent an agent's internal plan, and do not sync across devices.
- File previews are read-only. Ash does not yet provide a full IDE, cross-host file synchronization, automatic merging, or scheduled tasks.
- Worktrees isolate file checkouts, not ports, databases, or execution permissions.
- Exit code zero does not prove an agent completed its objective. Review the output and changes.

## Contributing

Issues, documentation improvements, and focused pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before getting started. Remove credentials, host addresses, and private paths from reports. For vulnerabilities, see [SECURITY.md](SECURITY.md).

Most detailed documentation and the current app interface are in Chinese. Start with the [user guide](docs/user-guide.md), [architecture](docs/architecture.md), or [design system](docs/design-system.md).

## License and acknowledgments

Ash is released under the [MIT License](LICENSE). Thanks to the maintainers of [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), [tmux](https://github.com/tmux/tmux), [OpenSSH](https://www.openssh.com/), and the Rust ecosystem. Dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).

Ash is an independent project and is not affiliated with the providers of the supported coding agents.
