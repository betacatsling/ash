#!/bin/bash
# Native window event checks require a logged-in macOS desktop session.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
BIN_DIR="$(swift build --show-bin-path)"
python3 - "$BIN_DIR" <<'PY'
from pathlib import Path
import subprocess
import sys
build = Path(sys.argv[1])
objects = [line for line in (build / 'Ash.product/Objects.LinkFileList').read_text().splitlines()
           if not line.endswith('/AshApp.swift.o')]
subprocess.run(['swiftc', '-parse-as-library', '-I', str(build / 'Modules'),
                'tests/TerminalSplitUIChecks.swift', *objects, '-o', '.build/TerminalSplitUIChecks'], check=True)
subprocess.run(['.build/TerminalSplitUIChecks'], check=True)
PY
