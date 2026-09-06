#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/rust-toolchain.sh
export PATH="$PWD/.tools/cross/bin:$(dirname "$CARGO"):$PATH"
command -v cargo-zigbuild >/dev/null || { echo 'See docs/remote-updates.md for the cross-build toolchain.' >&2; exit 1; }
rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-unknown-linux-musl x86_64-unknown-linux-musl
cargo build --release --locked --manifest-path runtime/Cargo.toml --target aarch64-apple-darwin --target x86_64-apple-darwin
cargo zigbuild --release --locked --manifest-path runtime/Cargo.toml --target aarch64-unknown-linux-musl --target x86_64-unknown-linux-musl
for target in macos-aarch64 macos-x86_64 linux-aarch64 linux-x86_64; do
  if [[ ! -f ".build/portable/$target/install/bin/tmux" ]]; then python3 scripts/build-portable.py "$target"; fi
done
python3 scripts/package-runtimes.py
