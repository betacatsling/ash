import Foundation

@main struct AppStoreChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ash-store-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")

        // The error message promises to preserve a damaged file, including after automatic saves.
        let damaged = Data("invalid saved state".utf8)
        try damaged.write(to: stateURL)
        let unreadable = AppStore(directory: directory)
        precondition(unreadable.error != nil)
        unreadable.fontSize = 18
        unreadable.save()
        let retained = try Data(contentsOf: stateURL)
        precondition(retained == damaged)

        let host = Host(id: "remote", name: "Remote", address: "fixture", autoInstallRuntime: false)
        let workspace = Workspace(id: "workspace", name: "Work", path: "/fixture", hostID: host.id)
        let saved = SavedState(hosts: [.local, host], workspaces: [workspace], selectedWorkspaceID: workspace.id)
        try JSONEncoder().encode(saved).write(to: stateURL)
        let store = AppStore(directory: directory)
        let direct = Run(id: "direct", taskId: "direct", workspaceId: workspace.id, title: "SSH", agent: "shell",
                         prompt: "", cwd: workspace.path, session: "", status: "direct", createdAt: 1)
        let managed = Run(id: "managed", taskId: "managed", workspaceId: workspace.id, title: "Managed", agent: "shell",
                          prompt: "", cwd: workspace.path, session: "ash-managed", status: "running", createdAt: 2)
        store.runs[host.id] = [direct]
        store.selectRun(direct)
        // Simulate the first managed snapshot after switching a direct SSH host to managed mode.
        let health = Health(protocol: 1, version: "0.1.2", platform: "macos", arch: "aarch64",
                            tmux: "/fixture/tmux", socket: "/fixture/socket", root: "/fixture", agents: [], concurrency: 4)
        let snapshot = RunList(runs: [managed], concurrency: 4)
        store.applySnapshot(snapshot, health: health, hostID: host.id)
        store.applySnapshot(snapshot, health: health, hostID: host.id)
        precondition(Set(store.workspaceRuns.map(\.id)) == [direct.id, managed.id])
        precondition(store.workspaceRuns.count == 2 && store.selectedRun?.id == direct.id)
        store.toggleSplit()
        precondition(store.visibleRuns.map(\.id) == [direct.id, managed.id])
        store.workspaces[0].name = "Offline edit"
        store.save()
        let reopened = AppStore(directory: directory)
        precondition(reopened.workspaces[0].name == "Offline edit" && reopened.workspaces[0].syncPending == true)
        precondition(reopened.runs[host.id] == [managed], "Direct transports must remain excluded from restart caches")
        await store.cancel(direct)
        precondition(store.workspaceRuns == [managed] && TerminalRegistry.shared.closed == [direct.id])
        precondition(store.visibleRuns == [managed])
        // Copied server registries may contain the same workspace ID on different hosts.
        var other = workspace
        other.hostID = "other-host"
        other.name = "Other host"
        other.syncPending = false
        var original = workspace
        original.syncPending = false
        let separate = SavedState(hosts: [.local, host], workspaces: [original, other], selectedWorkspaceID: workspace.id)
        try JSONEncoder().encode(separate).write(to: stateURL)
        let scoped = AppStore(directory: directory)
        scoped.save()
        precondition(scoped.workspaces.allSatisfy { $0.syncPending == false })
        scoped.workspaces[1].name = "Changed on other host"
        scoped.save()
        precondition(scoped.workspaces[0].syncPending == false && scoped.workspaces[1].syncPending == true)
        print("PASS: damaged app state is preserved; managed refresh retains direct SSH tabs; layouts and offline edits persist")
    }
}
