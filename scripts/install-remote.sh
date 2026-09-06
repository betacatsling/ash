#!/bin/bash
# Optional command-line entry to the same prebuilt packages used by the app.
set -euo pipefail
HOST="${1:?Usage: install-remote.sh user@host [runtime-path]}"
if [[ "$HOST" == -* || ! "$HOST" =~ ^[a-zA-Z0-9@._:-]+$ ]]; then
  echo 'Invalid SSH address; use a host alias or user@host.' >&2; exit 1
fi
LAUNCHER="${2:-.local/bin/ash-runtime}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "$SCRIPT_DIR/runtime-packages" ]]; then PACKAGES="$SCRIPT_DIR/runtime-packages"; else PACKAGES="$SCRIPT_DIR/../dist/runtime-packages"; fi
BOOTSTRAP="$(cat "$SCRIPT_DIR/remote-bootstrap.sh")"
SSH=(ssh -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
if [[ -n "${ASH_SSH_CONFIG:-}" ]]; then SSH+=(-F "$ASH_SSH_CONFIG"); fi
remote_command() {
  python3 - "$BOOTSTRAP" "$@" <<'PYCOMMAND'
import sys
print(' '.join("'"+arg.replace("'", "'\\''")+"'" for arg in ['sh','-c',sys.argv[1],'ash-bootstrap',*sys.argv[2:]]))
PYCOMMAND
}
PROBE="$("${SSH[@]}" -T "$HOST" "$(remote_command probe "$LAUNCHER" "${ASH_REMOTE_RUNTIME_HOME:-}")")"
METADATA="$(python3 - "$PACKAGES" "$PROBE" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); manifest=json.loads((root/'manifest.json').read_text())
probe=next(l for l in reversed(sys.argv[2].splitlines()) if l.startswith('ASH_PROBE|')).split('|')
assert manifest['format']==1 and manifest['protocol']==1
if len(probe)==8 and probe[3]=='ASH_READY':
    assert probe[5]=='1','Protocol incompatible; update Ash'
    if tuple(map(int,probe[4].split('.'))) >= tuple(map(int,manifest['version'].split('.'))):
        print('ready');sys.exit()
package=next(p for p in manifest['packages'] if p['target']==probe[1]+'-'+probe[2])
assert pathlib.Path(package['file']).name==package['file']
payload=(root/package['file']).read_bytes()
assert len(payload)==package['size'] and hashlib.sha256(payload).hexdigest()==package['sha256'],'Package checksum mismatch'
print(package['file']);print(manifest['version']);print(package['sha256'])
PY
)"
if [[ "$METADATA" == ready ]]; then echo 'Ash runtime is already up to date.'; exit 0; fi
FILE="$(sed -n '1p' <<< "$METADATA")"
VERSION="$(sed -n '2p' <<< "$METADATA")"
DIGEST="$(sed -n '3p' <<< "$METADATA")"
echo "Installing Ash $VERSION using the bundled package…"
"${SSH[@]}" -T "$HOST" "$(remote_command install "$LAUNCHER" "${ASH_REMOTE_RUNTIME_HOME:-}" "$VERSION" "$DIGEST")" < "$PACKAGES/$FILE"
echo 'Installed. Existing terminal sessions have been retained.'
