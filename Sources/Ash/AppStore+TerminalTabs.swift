import AppKit
import SwiftUI

extension AppStore {
    var workspaceTabs: [TerminalTabGroup] {
        selectedWorkspace?.terminalTabs(available: workspaceRuns.map(\.id)) ?? []
    }
    var selectedTerminalTab: TerminalTabGroup? {
        selectedWorkspace?.activeTerminalTab(available: workspaceRuns.map(\.id))
    }
    func runs(in tab: TerminalTabGroup) -> [Run] {
        tab.runIDs.compactMap { id in workspaceRuns.first { $0.id == id } }
    }
    func title(for tab: TerminalTabGroup) -> String {
        runs(in: tab).map { terminalTitle($0, hostID: selectedHost.id) }.joined(separator: " · ")
    }
    func selectTerminalTab(_ tab: TerminalTabGroup) {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces[i].selectTerminalPage(tab.id, available: workspaceRuns.map(\.id))
        save()
        if let id = selectedRun?.id { DispatchQueue.main.async { TerminalRegistry.shared.focus(id: id) } }
    }
    func closeTerminalTab(_ tab: TerminalTabGroup) async {
        let members = runs(in: tab)
        let hostID = selectedHost.id
        for run in members {
            await closeTerminal(run)
            // A failed stop keeps this session and the unprocessed remainder in their page.
            if self.runs[hostID]?.contains(where: { $0.id == run.id && !$0.archived }) == true { break }
        }
    }
    @discardableResult
    func detachTerminal(_ id: String, atEnd: Bool = false) -> Bool {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }),
            workspaceTabs.contains(where: { $0.isSplit && $0.runIDs.contains(id) })
        else { return false }
        workspaces[i].detachTerminal(id, available: workspaceRuns.map(\.id), atEnd: atEnd)
        save()
        DispatchQueue.main.async { TerminalRegistry.shared.focus(id: id) }
        return true
    }
    func ungroupTerminalTab(_ tab: TerminalTabGroup) {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces[i].ungroupTerminalTab(tab.id, available: workspaceRuns.map(\.id))
        save()
    }
    func arrangeTerminalTab(_ tab: TerminalTabGroup, axis: TerminalSplitAxis) {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces[i].arrangeTerminalTab(tab.id, axis: axis, available: workspaceRuns.map(\.id))
        save()
    }
    func toggleSplit() {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }), let selected = selectedRun else {
            return
        }
        if let tab = selectedTerminalTab, tab.isSplit {
            workspaces[i].ungroupTerminalTab(tab.id, available: workspaceRuns.map(\.id))
        } else if let other = workspaceTabs.first(where: { !$0.runIDs.contains(selected.id) }) {
            workspaces[i].moveTerminal(
                other.focusedRunID, beside: selected.id, side: .right,
                available: workspaceRuns.map(\.id), wholeTab: true)
        }
        save()
    }
    @discardableResult
    func moveTerminal(_ drag: TerminalDrag, beside target: String, side: TerminalDropSide) -> Bool {
        guard drag.workspaceID == selectedWorkspaceID,
            drag.tabID == nil
                || workspaceTabs.contains(where: { $0.id == drag.tabID && $0.runIDs.contains(drag.runID) }),
            let i = workspaces.firstIndex(where: { $0.id == drag.workspaceID }),
            workspaces[i].moveTerminal(
                drag.runID, beside: target, side: side, available: workspaceRuns.map(\.id), wholeTab: drag.tabID != nil)
        else { return false }
        save()
        DispatchQueue.main.async { TerminalRegistry.shared.focus(id: drag.runID) }
        return true
    }
    func resizeTerminalSplit(_ id: String, fraction: Double) {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        workspaces[i].resizeTerminalSplit(id, fraction: fraction, available: workspaceRuns.map(\.id))
        save()
    }
    func hidePane(_ id: String) {
        guard let i = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }), visibleRuns.count > 1 else {
            return
        }
        workspaces[i].detachTerminal(id, available: workspaceRuns.map(\.id), selectDetached: false)
        save()
    }

}
