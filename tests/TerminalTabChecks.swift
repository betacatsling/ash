import AppKit
import Foundation

@main struct TerminalTabChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: "/tmp/ash-tabs-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(directory: root)
        let workspace = Workspace(id: "tabs", name: "Tabs", path: root.path)
        store.workspaces = [workspace]
        store.selectedWorkspaceID = workspace.id
        let tabs = (1...3).map { index in
            Run(
                id: "tab-\(index)", taskId: "task-\(index)", workspaceId: workspace.id,
                title: "Terminal \(index)", agent: "shell", prompt: "", cwd: root.path,
                session: "", status: "direct", createdAt: Double(index))
        }
        store.runs["local"] = tabs.reversed()
        precondition(store.terminalTitle(tabs[0], hostID: "local") == tabs[0].title)
        precondition(store.renameTerminal(tabs[0], hostID: "local", name: "  前端开发 🚀  "))
        precondition(store.terminalTitle(tabs[0], hostID: "local") == "前端开发 🚀")
        precondition(store.terminalTitle(tabs[1], hostID: "local") == tabs[1].title)
        precondition(store.terminalTitle(tabs[0], hostID: "other-host") == tabs[0].title)
        precondition(!store.renameTerminal(tabs[0], hostID: "local", name: " \n "))
        precondition(!store.renameTerminal(tabs[0], hostID: "local", name: "a\nb"))
        precondition(!store.renameTerminal(tabs[0], hostID: "local", name: String(repeating: "名", count: 121)))
        precondition(AppStore(directory: root).terminalTitle(tabs[0], hostID: "local") == "前端开发 🚀")
        store.beginRenamingTerminal(tabs[0])
        precondition(!store.canSelectTerminal(.terminal1))
        store.terminalRenameTarget = nil
        precondition(store.renameTerminal(tabs[0], hostID: "local", name: tabs[0].title))
        precondition(AppStore(directory: root).terminalTitle(tabs[0], hostID: "local") == tabs[0].title)
        store.selectTerminal(.terminal1)
        precondition(store.selectedRun == tabs[0])
        store.selectTerminal(.previous)
        precondition(store.selectedRun == tabs[2])
        store.selectTerminal(.next)
        precondition(store.selectedRun == tabs[0])
        store.selectTerminal(.terminal9)
        precondition(store.selectedRun == tabs[0])
        store.toggleSplit()
        store.selectRun(tabs[1])
        precondition(store.visibleRuns == [tabs[0], tabs[1]] && store.selectedRun == tabs[1])
        store.selectTerminal(.terminal2)
        precondition(store.visibleRuns == [tabs[2]], "Numbered shortcuts select whole tab pages")
        store.selectTerminal(.terminal1)
        precondition(store.visibleRuns == [tabs[0], tabs[1]], "The split group survives switching away")
        store.selectTerminal(.terminal2)
        store.showSettings = true
        precondition(!store.canCloseSelectedTerminal, "Settings must suppress terminal closing")
        store.selectTerminal(.terminal1)
        precondition(store.selectedRun == tabs[2], "Settings must suppress terminal navigation")
        store.showSettings = false
        precondition(store.canCloseSelectedTerminal)
        store.closingRunIDs.insert(tabs[2].id)
        precondition(!store.canCloseSelectedTerminal, "Repeated close commands must be disabled")
        store.closingRunIDs.remove(tabs[2].id)
        store.beginRenamingTerminal(tabs[2])
        precondition(!store.canCloseSelectedTerminal, "Renaming must not close the terminal underneath")
        store.terminalRenameTarget = nil
        precondition(TerminalShortcut(key: "w").reservedAction == "关闭当前标签页")
        precondition(store.setShortcut(.init(key: "w"), for: .next)?.contains("关闭当前标签页") == true)

        precondition(store.shortcut(for: .terminal1).label == "⌘1")
        precondition(store.shortcut(for: .previous).label == "⌥⌘←")
        precondition(TerminalShortcutAction.settingsActions.count == 3)
        precondition(store.setShortcut(.init(key: "0"), for: .terminal1) != nil)
        precondition(store.setShortcut(.init(key: "t"), for: .terminal1) != nil)
        precondition(store.setShortcut(.init(key: "x", command: false), for: .terminal1) != nil)
        precondition(store.setShortcut(.init(key: "3", option: true), for: .terminal1) == nil)
        for action in TerminalShortcutAction.allCases where action.index != nil {
            precondition(store.shortcut(for: action) == TerminalShortcut(key: String(action.index! + 1), option: true))
        }
        precondition(AppStore(directory: root).shortcut(for: .terminal9).label == "⌥⌘9")
        precondition(store.setShortcut(.init(key: "8", option: true), for: .next) != nil)
        // A family update must be atomic if any number conflicts with a directional shortcut.
        precondition(store.setShortcut(.init(key: "8"), for: .next) == nil)
        precondition(store.setShortcut(.init(key: "1"), for: .terminal1) != nil)
        precondition(store.shortcut(for: .terminal1).label == "⌥⌘1")
        store.resetTerminalShortcuts()
        let migrated = TerminalShortcut.migratePreferences([
            "terminal1": .init(key: "1", option: true), "terminal2": .init(key: "j"),
            "previous": .init(key: "k", option: true),
        ])
        precondition(migrated["numbered"] == .init(key: "1", option: true))
        precondition(migrated["terminal2"] == nil && migrated["previous"] == .init(key: "k", option: true))
        let conflicting = TerminalShortcut.migratePreferences([
            "terminal1": .init(key: "j"), "previous": .init(key: "1"),
            "next": TerminalShortcutAction.previous.defaultShortcut,
        ])
        precondition(conflicting["numbered"] == .init(key: "1"))
        precondition(conflicting["previous"] == nil && conflicting["next"] == nil)
        print(
            "PASS: three settings rows, unified numbered shortcuts, atomic conflict rejection, persistence and legacy migration"
        )
        let custom = TerminalShortcut(key: "j", option: true)
        precondition(store.setShortcut(custom, for: .previous) == nil)
        let reopened = AppStore(directory: root)
        precondition(reopened.shortcut(for: .previous) == custom)
        store.resetTerminalShortcuts()
        precondition(
            AppStore(directory: root).shortcut(for: .previous) == TerminalShortcutAction.previous.defaultShortcut)
        // Existing state files without shortcut preferences keep the requested defaults.
        var json =
            try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("state.json")))
            as! [String: Any]
        json.removeValue(forKey: "terminalShortcuts")
        json.removeValue(forKey: "terminalTitles")
        try JSONSerialization.data(withJSONObject: json).write(to: root.appendingPathComponent("state.json"))
        precondition(AppStore(directory: root).shortcut(for: .next).label == "⌥⌘→")
        precondition(AppStore(directory: root).terminalTitles.isEmpty)
        // A failed save must not display a name that will disappear after relaunch.
        let invalidRoot = root.appendingPathComponent("invalid")
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        try Data("broken state".utf8).write(to: invalidRoot.appendingPathComponent("state.json"))
        let invalidStore = AppStore(directory: invalidRoot)
        precondition(!invalidStore.renameTerminal(tabs[0], hostID: "local", name: "Unsaved"))
        precondition(invalidStore.terminalTitle(tabs[0], hostID: "local") == tabs[0].title)
        print(
            "PASS: per-terminal names, Unicode, host isolation, validation, restore default, old state and failed-save rollback"
        )

        await store.closeTerminal(tabs[2])
        precondition(store.visibleRuns == [tabs[0], tabs[1]] && store.selectedRun == tabs[1])
        store.selectTerminal(.terminal2)
        await store.closeTerminal(tabs[1])
        precondition(store.selectedRun == tabs[0])
        await store.closeTerminal(tabs[0])
        precondition(store.workspaceRuns.isEmpty && store.visibleRuns.isEmpty && store.selectedRun == nil)
        precondition(
            !store.canCloseSelectedTerminal && store.selectedWorkspaceID == workspace.id,
            "Closing the last terminal must leave the workspace open with closing disabled")
        precondition(store.workspaces[0].paneRunIDs == [])
        print(
            "PASS: tab order, numeric selection, wrapping, split focus, direct close, empty state, conflicts and persistence"
        )

        // Real runtime and tmux, isolated from the user's managed sessions.
        setenv("ASH_RUNTIME_HOME", root.appendingPathComponent("runtime").path, 1)
        let client = RuntimeClient()
        let health: Health = try await client.call(.local, "health")
        defer {
            let cleanup = Process()
            cleanup.executableURL = URL(fileURLWithPath: health.tmux)
            cleanup.arguments = ["-S", health.socket, "kill-server"]
            cleanup.standardError = FileHandle.nullDevice
            try? cleanup.run()
            cleanup.waitUntilExit()
        }
        let _: [String: Int] = try await client.call(.local, "settings", ["concurrency": 1])
        func start(_ id: String) async throws -> Run {
            try await client.call(
                .local, "start",
                [
                    "id": id, "workspaceId": workspace.id, "cwd": root.path,
                    "title": id, "agent": "command", "arguments": ["/bin/sh", "-c", "sleep 120"],
                ])
        }
        let running = try await start("running")
        let queued = try await start("queued")
        precondition(running.active && queued.status == "queued")
        store.runs["local"] = [running, queued]
        precondition(store.renameTerminal(running, hostID: "local", name: "后台服务"))
        let refreshed: RunList = try await client.call(.local, "list")
        store.applySnapshot(refreshed, health: health, hostID: "local")
        let restarted = AppStore(directory: root)
        precondition(
            restarted.terminalTitle(restarted.runs["local"]!.first { $0.id == running.id }!, hostID: "local") == "后台服务")
        print("PASS: managed terminal custom names survive real runtime refresh and restart")
        store.selectRun(queued)
        await store.closeTerminal(queued)
        precondition(store.error == nil && store.selectedRun?.id == running.id)
        await store.closeTerminal(running)
        precondition(store.error == nil && store.workspaceRuns.isEmpty)
        let list: RunList = try await client.call(.local, "list")
        precondition(list.runs.count == 2 && list.runs.allSatisfy { $0.archived && !$0.active })
        store.applySnapshot(list, health: health, hostID: "local")
        precondition(store.workspaceRuns.isEmpty, "Refresh must not resurrect closed tabs")

        let groupFirst = try await start("group-close-first")
        let groupSecond = try await start("group-close-second")
        store.runs["local"] = [groupFirst, groupSecond]
        store.selectRun(groupFirst)
        precondition(
            store.moveTerminal(
                TerminalDrag(workspaceID: workspace.id, runID: groupSecond.id),
                beside: groupFirst.id, side: .right))
        await store.closeTerminalTab(store.selectedTerminalTab!)
        precondition(store.error == nil && store.workspaceTabs.isEmpty && store.workspaceRuns.isEmpty)
        print("PASS: closing a grouped page stops and archives every member")

        let failed = try await start("failure")
        store.runs["local"] = [failed]
        store.selectRun(failed)
        setenv("ASH_RUNTIME_BIN", "/nonexistent/ash-tabs-runtime", 1)
        await store.closeTerminal(failed)
        precondition(store.error != nil && store.selectedRun == failed && store.closingRunIDs.isEmpty)
        unsetenv("ASH_RUNTIME_BIN")
        let waiting = try await start("group-failure")
        store.runs["local"] = [failed, waiting]
        store.error = nil
        precondition(
            store.moveTerminal(
                TerminalDrag(workspaceID: workspace.id, runID: waiting.id),
                beside: failed.id, side: .right))
        setenv("ASH_RUNTIME_BIN", "/nonexistent/ash-tabs-runtime", 1)
        await store.closeTerminalTab(store.selectedTerminalTab!)
        unsetenv("ASH_RUNTIME_BIN")
        precondition(
            store.error != nil && store.visibleRuns.count == 2 && store.closingRunIDs.isEmpty,
            "A failed group close must preserve the failed session and unprocessed members")
        print("PASS: real running/queued sessions stop and archive; refresh preserves closure; failure retains the tab")
    }
}
