#!/bin/sh
# Sent verbatim over an authenticated SSH channel. Package bytes arrive on stdin.
set -eu
umask 077
mode=$1
launcher=$2
case "$launcher" in /*) ;; '~/'*) launcher="$HOME/${launcher#\~/}" ;; *) launcher="$HOME/$launcher" ;; esac
root=${3:-"$HOME/.local/share/ash"}
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
case "$(uname -s)" in Darwin) platform=macos ;; Linux) platform=linux ;; *) echo 'Ash: unsupported server operating system' >&2; exit 2 ;; esac
case "$(uname -m)" in arm64|aarch64) arch=aarch64 ;; x86_64|amd64) arch=x86_64 ;; *) echo 'Ash: unsupported server CPU architecture' >&2; exit 2 ;; esac
if [ "$mode" = probe ]; then
    installed=missing
    if [ -x "$launcher" ]; then
        installed=$("$launcher" --self-check 2>/dev/null | tail -n 1) || installed=unhealthy
        case "$installed" in ASH_READY\|*) ;; *) installed=unhealthy ;; esac
    fi
    printf 'ASH_PROBE|%s|%s|%s\n' "$platform" "$arch" "$installed"
    exit 0
fi
[ "$mode" = install ] || { echo 'Ash: invalid bootstrap action' >&2; exit 2; }
expected_version=$4
digest=$5
case "$digest" in *[!0-9a-f]*|'') echo 'Ash: invalid checksum' >&2; exit 2 ;; esac
[ "${#digest}" = 64 ] || exit 2
mkdir -p "$root"
stage=$(mktemp -d "$root/.install.XXXXXXXX")
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM
cat > "$stage/package.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$stage/package.tar.gz" | cut -d ' ' -f 1)
elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$stage/package.tar.gz" | cut -d ' ' -f 1)
else
    echo 'Ash: SHA-256 verification requires sha256sum or shasum' >&2; exit 1
fi
[ "$actual" = "$digest" ] || { echo 'Ash: package checksum mismatch; installed version unchanged' >&2; exit 1; }
mkdir "$stage/payload"
tar -xzf "$stage/package.tar.gz" -C "$stage/payload"
candidate="$stage/payload/bin/ash-runtime"
chmod 700 "$candidate" "$stage/payload/bin/tmux"
ready=$("$candidate" --self-check)
[ "$ready" = "ASH_READY|$expected_version|1|$platform|$arch" ] || { echo 'Ash: package platform, version or protocol mismatch' >&2; exit 1; }
"$candidate" --install "$root" "$launcher" "$digest"
