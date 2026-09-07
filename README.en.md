# Ash

Ash is a macOS terminal app for local and SSH projects. It supports grouped split tabs and can run Pi, Codex CLI, and Claude Code. The current app interface is in Chinese.

[Download 0.1.3](https://github.com/betacatsling/ash/releases/tag/v0.1.3) · [User guide (Chinese)](docs/user-guide.md) · [简体中文](README.md)

[![CI](https://github.com/betacatsling/ash/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/betacatsling/ash/actions/workflows/ci.yml)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/workspace-dark.png">
  <img src="docs/images/workspace-light.png" alt="Ash workspace" width="1040">
</picture>

## Install

Requires macOS 15+, Apple Silicon, and tmux 3.3+:

```sh
brew install tmux
```

Download `Ash-0.1.3-macOS-arm64.zip` from the [release page](https://github.com/betacatsling/ash/releases/tag/v0.1.3), unzip it, and move `Ash.app` into Applications.

This is an ad-hoc signed preview and is not notarized. If macOS blocks the first launch, verify the download source and allow it under System Settings → Privacy & Security. SHA-256 checksums are included in the release.

## Use

- **⌘O** opens a project, **⌘T** opens a terminal, and **⌘N** starts an agent task.
- Drag tabs together to create a split group. Each terminal name inside the group is clickable and draggable; drop it on empty tab-bar space to detach it.
- Selecting another tab switches the whole page. Each group's layout and proportions are retained.
- The right panel has file previews, Git diffs, web previews, and a checklist.

**⌘W or a tab's × closes every terminal in that tab**, stopping and archiving managed sessions. Quitting Ash only detaches the display; managed sessions keep running. A host reboot or terminated process cannot be restored to the original live session.

Install and sign in to each agent CLI on the machine where it will run. Ordinary terminals do not require an agent.

## SSH

Add `user@host` or an existing SSH config alias in the host manager. Ash uses your system OpenSSH keys, ports, and jump-host settings.

Direct SSH needs no remote installation. Managed mode installs the bundled runtime for persistent sessions and agent tasks. Bundles cover Linux / macOS on arm64 and x86_64 and include tmux; the remote host needs no Rust toolchain or compiler. [Installation and recovery details (Chinese)](docs/remote-updates.md)

## Run from source

Requires Swift 6.2+, a macOS SDK, Rust stable, Python 3, Git, and tmux. Use Xcode 26+ or compatible Command Line Tools.

```sh
git clone https://github.com/betacatsling/ash.git
cd ash
cargo build --locked --manifest-path runtime/Cargo.toml
swift run Ash
```

Prepare runtime bundles before packaging the app or running the full test suite; see the [build instructions (Chinese)](docs/build-artifacts.md). Client 0.1.3 continues to use runtime 0.1.2.

```sh
./scripts/build.sh debug                # Development app
./scripts/build.sh release --no-install # Release app
./scripts/test.sh                       # Local regression suite
./scripts/test.sh --ssh                 # Also run isolated SSH tests
```

With full Xcode installed, `swift test` is also available. Tests do not connect to saved remote hosts or call real agent models.

## Docs and contributing

[User guide](docs/user-guide.md) · [Terminal tabs](docs/terminal-tabs.md) · [Hosts](docs/host-management.md) · [Architecture](docs/architecture.md) — these documents are in Chinese.

[Issues](https://github.com/betacatsling/ash/issues) and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing and [SECURITY.md](SECURITY.md) for vulnerability reports.

[MIT License](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for dependencies and their licenses.
