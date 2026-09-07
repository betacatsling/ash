#!/bin/bash
# Shared source groups for the standalone Swift checks (no XCTest required).
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK="${1:?Usage: scripts/swift-check.sh Name [output]}"
OUTPUT="${2:-.build/$CHECK}"
CORE=(Sources/Ash/Models.swift Sources/Ash/TerminalLayout.swift Sources/Ash/TerminalSplitGeometry.swift Sources/Ash/TerminalTabGroup.swift Sources/Ash/Workspace+TerminalTabs.swift Sources/Ash/KeyboardShortcuts.swift Sources/Ash/HostConfiguration.swift Sources/Ash/RuntimeClient.swift Sources/Ash/TerminalEnvironment.swift)
PERSISTENCE=(Sources/Ash/Persistence.swift Sources/Ash/WorkspaceChecklistStore.swift)
STORE=("${CORE[@]}" "${PERSISTENCE[@]}" Sources/Ash/AppStore.swift Sources/Ash/AppStore+TerminalTabs.swift Sources/Ash/AppStore+Hosts.swift Sources/Ash/HostConnectionService.swift Sources/Ash/RemoteRuntimeManager.swift Sources/Ash/SSHConfigDiscovery.swift)
PANEL=("${CORE[@]}" Sources/Ash/SidePanelModel.swift Sources/Ash/PanelBrowserModel.swift)
case "$CHECK" in
  ModelChecks|TerminalLayoutChecks|TerminalGroupChecks|TerminalEnvironmentChecks) SOURCES=("${CORE[@]}") ;;
  DirectorySuggestionsChecks) SOURCES=("${CORE[@]}" Sources/Ash/DirectorySuggestions.swift) ;;
  ChecklistChecks) SOURCES=("${PERSISTENCE[@]}") ;;
  SidePanelChecks) SOURCES=("${PANEL[@]}") ;;
  TerminalTabChecks|HostManagementChecks|AppStoreChecks|AppStoreRecoveryChecks|BootstrapChecks) SOURCES=("${STORE[@]}" tests/TerminalRegistryStub.swift) ;;
  *) echo "Unknown Swift check: $CHECK" >&2; exit 1 ;;
esac
mkdir -p "$(dirname "$OUTPUT")"
swiftc -parse-as-library "${SOURCES[@]}" "tests/$CHECK.swift" -o "$OUTPUT"
