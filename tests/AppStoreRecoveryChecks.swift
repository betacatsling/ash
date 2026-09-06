import Foundation

// Only the view is substituted; AppStore, persistence, RuntimeClient and SSH are production code.
@main struct AppStoreRecoveryChecks {
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "restore"
        let store = AppStore()
        let hostID = "ssh-recovery"
        if mode == "offline" {
            precondition(store.workspaces.contains { $0.hostID == hostID }, "Workspace cache must be present before connecting")
            let before = store.runs[hostID] ?? []
            precondition(!before.isEmpty, "Session cache must survive quitting")
            await store.refresh()
            precondition(store.connectionErrors[hostID] != nil)
            precondition(store.runs[hostID] == before, "Offline must not become failed or empty")
            let index = store.workspaces.firstIndex { $0.hostID == hostID }!
            store.workspaces[index].name = "离线修改保留"
            store.save()
            precondition(store.workspaces[index].syncPending == true)
            print("PASS actual AppStore preserves workspaces and session state while offline")
            return
        }
        await store.refresh()
        let workspace = store.workspaces.first { $0.hostID == hostID && $0.id == "ssh-workspace" }!
        precondition(workspace.name == (mode == "restore-edits" ? "离线修改保留" : "服务器上的研发工作区"))
        precondition(workspace.split && workspace.selectedRunID != nil && workspace.secondaryRunID != nil)
        precondition(store.selectedWorkspaceID != nil)
        if mode == "restore-edits" {
            let client = RuntimeClient()
            var synchronized = false
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(200))
                let snapshot: RunList = try await client.call(store.host(for: hostID), "list")
                if snapshot.workspaces?.first(where: { $0.id == workspace.id })?.name == workspace.name,
                   store.workspaces.first(where: { $0.id == workspace.id })?.syncPending == false {
                    synchronized = true; break
                }
            }
            precondition(synchronized, "Offline edits must sync to the server once reconnected")
            print("PASS offline workspace edits survive restart and synchronize after reconnection")
        }
        let restored = store.runs[hostID] ?? []
        precondition(restored.count == 2 && restored.allSatisfy { $0.status == "running" })
        let ids = restored.map(\.id)
        TerminalRegistry.shared.failed.insert(ids[0])
        await store.refresh()
        precondition(store.terminalGeneration[ids[0]] == 1, "Lost terminal attachment must reconnect automatically")
        precondition(TerminalRegistry.shared.closed == [ids[0]])
        precondition((store.runs[hostID] ?? []).map(\.id) == ids, "Reconnect must never launch replacement tasks")
        print("PASS actual AppStore restores server workspace, split layout and original session IDs")
        print("PASS actual AppStore automatically reattaches an ended terminal transport")
    }
}
