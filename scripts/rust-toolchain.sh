#!/bin/bash
# Source after changing to the project root. Prefer the caller's Cargo installation.
if command -v cargo >/dev/null; then
  CARGO="$(command -v cargo)"
else
  export CARGO_HOME="$PWD/.tools/cargo" RUSTUP_HOME="$PWD/.tools/rustup"
  CARGO="$CARGO_HOME/bin/cargo"
fi
if [[ ! -x "$CARGO" ]]; then
  echo 'Rust is required. Install rustup or see README.md.' >&2
  exit 1
fi
