import AppKit
import SwiftUI

struct TerminalDropEvent {
    let id = UUID()
    let tabID: String
}

@MainActor final class TerminalDragState: ObservableObject {
    @Published var source: TerminalDrag?
    @Published var location = CGPoint.zero
    @Published var lastDrop: TerminalDropEvent?
    @Published var didCompleteDrop = false
    var targets: [String: TerminalDropTargetReference] = [:]
    var originTabID: String?
    var detachTarget: TerminalDropTargetReference?
    var tabTargets: [String: TerminalDropTargetReference] = [:]

    private func frame(_ reference: TerminalDropTargetReference?) -> CGRect? {
        guard let view = reference?.view, view.window != nil else { return nil }
        return view.convert(view.bounds.intersection(view.visibleRect), to: nil)
    }
    var hoveredTabID: String? {
        guard let source else { return nil }
        return tabTargets.first { id, target in
            id != (originTabID ?? source.tabID) && frame(target)?.contains(location) == true
        }?.key
    }
    var isOverDetachTarget: Bool {
        guard let source, source.tabID == nil else { return false }
        return frame(detachTarget)?.contains(location) == true
    }
    func side(for id: String) -> TerminalDropSide? {
        guard let source, source.runID != id, let frame = frame(targets[id]) else { return nil }
        let topLeftFrame = CGRect(x: frame.minX, y: -frame.maxY, width: frame.width, height: frame.height)
        return TerminalDropSide.nearest(to: CGPoint(x: location.x, y: -location.y), in: topLeftFrame)
    }
    func acceptsPane(_ id: String, store: AppStore) -> Bool {
        guard let source else { return false }
        // A group is moved as a whole, so dropping it into itself is never a valid merge.
        return source.tabID == nil || !store.workspaceTabs.contains { $0.id == source.tabID && $0.runIDs.contains(id) }
    }
    func finish(store: AppStore) {
        defer { source = nil }
        guard let source else { return }
        var moved = false
        if let tabID = hoveredTabID, let tab = store.workspaceTabs.first(where: { $0.id == tabID }) {
            moved = store.moveTerminal(
                source, beside: tab.focusedRunID,
                side: NSEvent.modifierFlags.contains(.option) ? .bottom : .right)
        } else if isOverDetachTarget {
            moved = store.detachTerminal(source.runID, atEnd: true)
        } else {
            for run in store.visibleRuns where acceptsPane(run.id, store: store) {
                if let side = side(for: run.id) {
                    moved = store.moveTerminal(source, beside: run.id, side: side)
                    break
                }
            }
        }
        didCompleteDrop = moved
        if moved, let tab = store.selectedTerminalTab { lastDrop = TerminalDropEvent(tabID: tab.id) }
    }
}

struct TerminalDragModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var drag: TerminalDragState
    let tab: TerminalTabGroup
    var member: Run? = nil

    func body(content: Content) -> some View {
        content.overlay {
            TerminalTabDragSurface(
                onClick: { count in
                    if let member {
                        store.selectRun(member)
                        if count == 2 { store.beginRenamingTerminal(member) }
                    } else {
                        store.selectTerminalTab(tab)
                        if count == 2, !tab.isSplit, let run = store.runs(in: tab).first {
                            store.beginRenamingTerminal(run)
                        }
                    }
                },
                onDrag: { location in
                    if drag.source == nil {
                        drag.didCompleteDrop = false
                        drag.originTabID = tab.id
                        drag.source = TerminalDrag(
                            workspaceID: store.selectedWorkspaceID ?? "",
                            runID: member?.id ?? tab.focusedRunID,
                            tabID: member == nil ? tab.id : nil)
                    }
                    drag.location = location
                },
                onDrop: { location in
                    drag.location = location
                    drag.finish(store: store)
                },
                onCancel: { drag.source = nil },
                identifier: member.map { "member:\($0.id)" } ?? "tab:\(tab.id)"
            ).accessibilityHidden(true)
        }
    }
}

struct TerminalWorkspaceDragModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @StateObject private var drag = TerminalDragState()
    func body(content: Content) -> some View {
        content
            .environmentObject(drag)
            .overlay {
                TerminalDragPreview(drag: drag, store: store).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: store.selectedWorkspaceID) { _, _ in drag.source = nil }
    }
}
