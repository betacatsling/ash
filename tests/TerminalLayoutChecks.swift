import Foundation

@main struct TerminalLayoutChecks {
    static func main() throws {
        let available = ["a", "b", "c", "d"]
        let frame = CGRect(x: 20, y: 30, width: 800, height: 400)
        for (side, point) in [
            (TerminalDropSide.left, CGPoint(x: 21, y: 230)),
            (.right, CGPoint(x: 819, y: 230)),
            (.top, CGPoint(x: 420, y: 31)), (.bottom, CGPoint(x: 420, y: 429)),
        ] {
            precondition(TerminalDropSide.nearest(to: point, in: frame) == side)
            var workspace = Workspace(id: "w", name: "Split", path: "/tmp", selectedRunID: "a")
            precondition(workspace.moveTerminal("b", beside: "a", side: side, available: available))
            let layout = workspace.visibleLayout(available: available)!
            let geometry = TerminalSplitGeometry(layout: layout, size: CGSize(width: 800, height: 500))
            let a = geometry.panes["a"]!
            let b = geometry.panes["b"]!
            switch side {
            case .left: precondition(b.maxX + 1 == a.minX && a.minY == b.minY)
            case .right: precondition(a.maxX + 1 == b.minX && a.minY == b.minY)
            case .top: precondition(b.maxY + 1 == a.minY && a.minX == b.minX)
            case .bottom: precondition(a.maxY + 1 == b.minY && a.minX == b.minX)
            }
            precondition(!a.intersects(b))
            precondition(workspace.selectedRunID == "b")
        }
        precondition(TerminalDropSide.nearest(to: .zero, in: frame) == nil)
        precondition(TerminalDropSide.nearest(to: .zero, in: .zero) == nil)

        var workspace = Workspace(id: "w", name: "Mixed", path: "/tmp", selectedRunID: "a")
        workspace.moveTerminal("b", beside: "a", side: .right, available: available)
        workspace.moveTerminal("c", beside: "a", side: .bottom, available: available)
        let mixed = workspace.terminalLayout!
        let geometry = TerminalSplitGeometry(layout: mixed, size: CGSize(width: 900, height: 600))
        precondition(geometry.panes["a"]!.maxY + 1 == geometry.panes["c"]!.minY)
        precondition(geometry.panes["b"]!.height == 600, "Splitting the left pane must not split the right pane")
        workspace.selectTerminal("d", available: available)
        precondition(workspace.visibleRunIDs(available: available) == ["d"], "An independent page fills the workspace")
        workspace.selectTerminal("c", available: available)
        precondition(workspace.terminalLayout == mixed, "The original split layout is restored unchanged")
        workspace.selectTerminal("a", available: available)
        let beforeFocus = workspace.terminalLayout
        workspace.selectTerminal("b", available: available)
        precondition(workspace.terminalLayout == beforeFocus)
        workspace.removeTerminal("a", available: available)
        let collapsed = TerminalSplitGeometry(layout: workspace.terminalLayout!, size: CGSize(width: 900, height: 600))
        precondition(collapsed.panes["c"]!.height == 600, "Closing a nested pane should collapse only its empty branch")
        workspace.moveTerminal("b", beside: "c", side: .top, available: ["b", "c", "d"])
        precondition(workspace.terminalLayout!.runIDs == ["b", "c"])
        let moved = TerminalSplitGeometry(layout: workspace.terminalLayout!, size: CGSize(width: 900, height: 600))
        precondition(moved.panes["b"]!.maxY + 1 == moved.panes["c"]!.minY)
        precondition(Set(workspace.terminalLayout!.runIDs).count == 2)

        let divider = moved.dividers[0]
        workspace.resizeTerminalSplit(divider.id, fraction: 0.7, available: ["b", "c", "d"])
        let saved = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        precondition(saved == workspace, "Nested directions and resized proportions must survive restart")
        let resized = TerminalSplitGeometry(layout: saved.terminalLayout!, size: CGSize(width: 900, height: 600))
        precondition(abs(resized.panes["b"]!.height / 599 - 0.7) < 0.0001)
        for distance in [-10000.0, 10000.0] {
            let result = divider.fraction(translatedBy: distance)
            let changed = workspace.terminalLayout!.settingFraction(result, for: divider.id)
            let constrained = TerminalSplitGeometry(layout: changed, size: CGSize(width: 900, height: 600))
            precondition(constrained.panes.values.allSatisfy { $0.height >= 120 && $0.width >= 220 })
        }
        let narrow = TerminalSplitGeometry(layout: mixed, size: CGSize(width: 200, height: 100))
        precondition(narrow.panes.values.allSatisfy { $0.width >= 220 && $0.height >= 120 })
        let legacy = try JSONDecoder().decode(
            Workspace.self,
            from: Data(
                """
                {"id":"w","name":"Legacy","path":"/tmp","hostID":"local","split":true,"paneRunIDs":["a","b","c"]}
                """.utf8))
        let legacyGeometry = TerminalSplitGeometry(
            layout: legacy.visibleLayout(available: available)!, size: CGSize(width: 902, height: 500))
        precondition(legacyGeometry.panes.values.allSatisfy { abs($0.width - 300) < 1 })
        precondition(legacy.visibleLayout(available: ["a", "c"])!.runIDs == ["a", "c"])
        print(
            "PASS: four drop directions, mixed splits, stable tab replacement, branch collapse, moving visible panes, resize limits, narrow layouts, legacy migration and persistence"
        )
    }
}
