#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --ssh ) ]]; then
  echo 'Usage: scripts/test.sh [--ssh]' >&2; exit 1
fi
source scripts/rust-toolchain.sh
"$CARGO" test --locked --manifest-path runtime/Cargo.toml
"$CARGO" build --locked --manifest-path runtime/Cargo.toml
for check in ModelChecks TerminalLayoutChecks TerminalGroupChecks TerminalEnvironmentChecks ChecklistChecks SidePanelChecks TerminalTabChecks AppStoreChecks HostManagementChecks DirectorySuggestionsChecks; do
  scripts/swift-check.sh "$check"
  ".build/$check"
done
for check in runtime_integration terminal_colors_integration agent_tasks_integration panel_integration installer_smoke app_installation; do
  python3 "tests/$check.py"
done
if [[ "${1:-}" == --ssh ]]; then
  scripts/swift-check.sh AppStoreRecoveryChecks .build/appstore-recovery-checks
  scripts/swift-check.sh BootstrapChecks .build/bootstrap-checks
  for check in ssh_integration ssh_recovery bootstrap_integration panel_ssh_integration; do
    python3 "tests/$check.py"
  done
fi
python3 scripts/verify-runtime-packages.py
