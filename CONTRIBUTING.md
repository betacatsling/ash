# Contributing to Ash

感谢你帮助改进 Ash。Issues 和 Pull Requests 可以使用中文或英文。

## Before making a change

- Search existing issues first. For a substantial feature or redesign, open an issue describing the user problem and proposed behavior.
- Keep changes focused. Explain the trigger, the behavior before and after the change, and how you verified it.
- Do not include credentials, real SSH hosts, personal paths, session transcripts, or local agent configuration.

## Development

See the [README](README.en.md#run-from-source) for dependencies and build instructions. SwiftUI / AppKit code lives in `Sources/Ash`; the Rust runtime lives in `runtime/src`.

```sh
cargo build --locked --manifest-path runtime/Cargo.toml
swift build
cargo test --locked --manifest-path runtime/Cargo.toml
```

After preparing the runtime bundles described in the README, run `./scripts/test.sh` for the full local suite. With full Xcode installed, `swift test` runs the XCTest checks. Real SSH coverage is optional via `./scripts/test.sh --ssh` and must remain isolated from personal hosts.

## Review expectations

- Use the existing formatting conventions; Swift configuration is in `.swift-format`.
- Add meaningful regression coverage for behavior changes, especially session lifecycle, quoting, persistence, and remote installation.
- For UI changes, include light and dark previews and check narrow layouts, keyboard shortcuts, and terminal focus. Do not animate terminal size changes.
- Preserve the distinction between closing a terminal (stop and archive) and quitting the UI (detach managed sessions).
- Keep remote operations within the user's SSH trust and permissions. Never add flags that bypass agent approval controls.
- Update relevant documentation and both README files when public behavior or setup changes.
- If runtime code or the protocol changes, review version compatibility and rebuild all four runtime bundles before release.

## Pull requests

Describe what changed, why, and the validation performed. Mention any checks you could not run. Small fixes do not need a long proposal.

Contributions to Ash are made under the project's [MIT License](LICENSE). Third-party code must retain its original notices and compatible licensing.
