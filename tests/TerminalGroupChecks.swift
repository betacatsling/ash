import Foundation

@main struct TerminalGroupChecks {
    static func main() throws {
        let ids = ["a", "b", "c", "d"]
        var workspace = Workspace(id: "w", name: "Tabs", path: "/tmp", selectedRunID: "a")
        precondition(workspace.terminalTabs(available: ids).count == 4)
        precondition(workspace.moveTerminal("b", beside: "a", side: .right, available: ids, wholeTab: true))
        let combined = workspace.activeTerminalTab(available: ids)!
        precondition(combined.runIDs == ["a", "b"] && workspace.terminalTabs(available: ids).count == 3)
        let splitID = TerminalSplitGeometry(layout: combined.layout, size: CGSize(width: 900, height: 600)).dividers[0]
            .id
        workspace.resizeTerminalSplit(splitID, fraction: 0.65, available: ids)
        let savedSplit = workspace.activeTerminalTab(available: ids)!
        workspace.selectTerminal("c", available: ids)
        precondition(workspace.visibleRunIDs(available: ids) == ["c"], "Independent tabs must replace the whole page")
        precondition(
            workspace.terminalTabs(available: ids).first { $0.id == combined.id } == savedSplit,
            "Switching away must preserve both the group and its resized layout")
        workspace.selectTerminalPage(combined.id, available: ids)
        precondition(workspace.visibleRunIDs(available: ids) == ["a", "b"] && workspace.selectedRunID == "b")
        workspace.selectTerminal("a", available: ids)
        precondition(workspace.visibleRunIDs(available: ids) == ["a", "b"])
        precondition(workspace.activeTerminalTab(available: ids)!.layout == savedSplit.layout)
        workspace.selectTerminal("d", available: ids)
        precondition(workspace.visibleRunIDs(available: ids) == ["d"])
        workspace.moveTerminal("d", beside: "c", side: .bottom, available: ids, wholeTab: true)
        precondition(workspace.terminalTabs(available: ids).count == 2)
        let secondGroup = workspace.activeTerminalTab(available: ids)!
        workspace.selectTerminal("a", available: ids)
        precondition(workspace.moveTerminal("c", beside: "b", side: .right, available: ids, wholeTab: true))
        precondition(workspace.terminalTabs(available: ids).count == 1)
        precondition(workspace.visibleRunIDs(available: ids) == ids)
        let mergedGeometry = TerminalSplitGeometry(
            layout: workspace.visibleLayout(available: ids)!, size: CGSize(width: 1000, height: 700))
        precondition(
            mergedGeometry.panes["c"]!.maxY + 1 == mergedGeometry.panes["d"]!.minY,
            "Merging an existing group must preserve its internal vertical split")
        let beforeInvalid = workspace
        precondition(!workspace.moveTerminal("a", beside: "b", side: .left, available: ids, wholeTab: true))
        precondition(!workspace.moveTerminal("missing", beside: "a", side: .right, available: ids))
        precondition(workspace == beforeInvalid)
        workspace.detachTerminal("c", available: ids)
        precondition(workspace.visibleRunIDs(available: ids) == ["c"])
        precondition(workspace.terminalTabs(available: ids).count == 2)
        precondition(Set(workspace.terminalTabs(available: ids).flatMap(\.runIDs)) == Set(ids))
        let roundtrip = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        precondition(roundtrip == workspace)
        workspace.selectTerminal("a", available: ids)
        let activeID = workspace.activeTerminalTab(available: ids)!.id
        workspace.removeTerminal("c", available: ids)
        precondition(
            workspace.activeTerminalTab(available: ["a", "b", "d"])!.id == activeID,
            "Closing an inactive tab must not change the active group")
        workspace.removeTerminal("a", available: ["a", "b", "d"])
        precondition(workspace.visibleRunIDs(available: ["b", "d"]) == ["b", "d"])
        workspace.ungroupTerminalTab(activeID, available: ["b", "d"])
        precondition(workspace.terminalTabs(available: ["b", "d"]).count == 2)
        precondition(workspace.visibleRunIDs(available: ["b", "d"]).count == 1)
        workspace.removeTerminal("b", available: ["b", "d"])
        workspace.removeTerminal("d", available: ["d"])
        precondition(workspace.visibleRunIDs(available: []) == [] && workspace.terminalGroups == [])

        var detachable = Workspace(id: "detach", name: "Detach", path: "/tmp", selectedRunID: "a")
        detachable.moveTerminal("b", beside: "a", side: .right, available: ids, wholeTab: true)
        detachable.moveTerminal("d", beside: "c", side: .bottom, available: ids, wholeTab: true)
        let otherGroup = detachable.activeTerminalTab(available: ids)!
        detachable.selectTerminal("b", available: ids)
        detachable.detachTerminal("b", available: ids, atEnd: true)
        precondition(detachable.terminalTabs(available: ids).map(\.runIDs) == [["a"], ["c", "d"], ["b"]])
        precondition(detachable.visibleRunIDs(available: ids) == ["b"])
        precondition(
            detachable.terminalTabs(available: ids).first { $0.id == otherGroup.id } == otherGroup,
            "Dragging a member out must not alter another group's layout or focus")
        precondition(detachable.moveTerminal("b", beside: "c", side: .left, available: ids))
        precondition(detachable.visibleRunIDs(available: ids) == ["b", "c", "d"])
        precondition(detachable.terminalTabs(available: ids).first?.runIDs == ["a"])

        let legacy = try JSONDecoder().decode(
            Workspace.self,
            from: Data(
                """
                {"id":"legacy","name":"Legacy","path":"/tmp","hostID":"local","split":true,"selectedRunID":"b","paneRunIDs":["a","b"]}
                """.utf8))
        precondition(legacy.terminalTabs(available: ids).map(\.runIDs) == [["a", "b"], ["c"], ["d"]])
        precondition(legacy.visibleRunIDs(available: ids) == ["a", "b"])
        precondition(legacy.activeTerminalTab(available: ids)?.focusedRunID == "b")
        var malformed = legacy
        malformed.terminalGroups = [secondGroup, secondGroup, .single("c"), .single("missing")]
        let cleaned = malformed.terminalTabs(available: ids)
        precondition(cleaned.flatMap(\.runIDs).count == ids.count && Set(cleaned.flatMap(\.runIDs)) == Set(ids))
        precondition(Set(cleaned.map(\.id)).count == cleaned.count)
        print(
            "PASS: grouped tabs, whole-page switching, retained focus/proportions, merging groups, detaching, closing, ungrouping, persistence and legacy migration"
        )
    }
}
