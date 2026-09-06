#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
INSTALL_APP=true
if [[ "${2:-}" == --no-install && $# -eq 2 ]]; then
  INSTALL_APP=false
elif [[ $# -gt 1 ]]; then
  echo 'Usage: scripts/build.sh [release|debug] [--no-install]' >&2; exit 1
fi
case "$CONFIG" in
  release) APP="$PWD/dist/Ash.app" ;;
  debug) APP="$PWD/.build/dev/Ash.app" ;;
  *) echo 'Usage: scripts/build.sh [release|debug] [--no-install]' >&2; exit 1 ;;
esac
source scripts/rust-toolchain.sh
if [[ "$CONFIG" == release ]]; then
  "$CARGO" build --locked --release --manifest-path runtime/Cargo.toml
else
  "$CARGO" build --locked --manifest-path runtime/Cargo.toml
fi
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Ash" "$APP/Contents/MacOS/Ash.new"
mv "$APP/Contents/MacOS/Ash.new" "$APP/Contents/MacOS/Ash"
cp "runtime/target/$CONFIG/ash-runtime" "$APP/Contents/Resources/ash-runtime.new"
mv "$APP/Contents/Resources/ash-runtime.new" "$APP/Contents/Resources/ash-runtime"
cp scripts/install-remote.sh "$APP/Contents/Resources/install-remote.sh"
cp scripts/remote-bootstrap.sh "$APP/Contents/Resources/remote-bootstrap.sh"
if [[ ! -f dist/runtime-packages/manifest.json ]]; then
  echo 'Remote packages are required. Run scripts/build-runtime-packages.sh first.' >&2; exit 1
fi
python3 scripts/verify-runtime-packages.py
/usr/bin/ditto dist/runtime-packages "$APP/Contents/Resources/runtime-packages"
mkdir -p "$APP/Contents/Resources/runtime-source/src"
cp runtime/Cargo.toml runtime/Cargo.lock "$APP/Contents/Resources/runtime-source/"
cp runtime/src/*.rs "$APP/Contents/Resources/runtime-source/src/"
cp -f .build/checkouts/SwiftTerm/LICENSE "$APP/Contents/Resources/SwiftTerm-LICENSE.txt"
cp LICENSE "$APP/Contents/Resources/Ash-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto docs/licenses "$APP/Contents/Resources/docs/licenses"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftTerm searches native app resource locations without the SwiftPM fatal accessor.
if [[ -d "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" ]]; then
  ditto "$BIN_DIR/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/SwiftTerm_SwiftTerm.bundle"
fi
swift scripts/icon.swift .build/Ash.iconset
iconutil -c icns .build/Ash.iconset -o "$APP/Contents/Resources/Ash.icns"
codesign --force --sign - "$APP/Contents/Resources/ash-runtime"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [[ "$CONFIG" == release && "$INSTALL_APP" == true ]]; then
  python3 scripts/install-app.py "$APP"
fi
