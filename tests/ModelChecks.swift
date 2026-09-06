import Foundation

@main struct ModelChecks {
    static func main() throws {
        for invalid in ["", "-oProxyCommand=evil", "user@host;id", "host\ncommand", "$(id)", "a b"] { precondition(!validSSHAddress(invalid), invalid) }
        for valid in ["dev-server", "user@host.example", "user@[::1]"] { precondition(validSSHAddress(valid), valid) }
        precondition(shellQuote("a'b $(id)\nnext") == "'a'\\''b $(id)\nnext'")
        let h = Host(name: "test", address: "test", runtimePath: ".local/bin/ash' x")
        precondition(RuntimeClient.remoteRuntime(h).contains("$HOME/'.local/bin/ash'\\'' x' request"))
        let data = Data("""
        {"id":"r","taskId":"t","workspaceId":"w","title":"task","agent":"pi","prompt":"","cwd":"/tmp","session":"ash-r","status":"exited","createdAt":1,"exitCode":0,"archived":false}
        """.utf8)
        let r = try JSONDecoder().decode(Run.self, from:data)
        precondition(!r.active && r.label == "已退出 · 待检查")
        let spec = RuntimeClient.terminalSpec(host: Host(name:"Remote",address:"test",managed:false), run: Run(id:"x",taskId:"x",workspaceId:"w",title:"SSH",agent:"shell",prompt:"",cwd:"/tmp/a'b",session:"",status:"direct",createdAt:0), health:nil)
        precondition(spec.arguments.last?.contains("'/tmp/a'\\''b'") == true)
        let snapshot = try JSONDecoder().decode(AgentTaskSnapshot.self, from: Data("""
        {"sessions":[{"id":"session","agent":"claude","tasks":[{"id":"1","title":"测试","status":"completed"},{"id":"2","title":"下一步","status":"new_status"}]}]}
        """.utf8))
        precondition(snapshot.sessions[0].name == "Claude Code")
        precondition(snapshot.sessions[0].completedCount == 1)
        precondition(snapshot.sessions[0].tasks[1].label == "状态未知")
        var policy = AttachmentRetryPolicy()
        let instant = Date(timeIntervalSince1970: 100)
        precondition(policy.shouldRetry(id: "r", live: true, ended: true, now: instant))
        precondition(!policy.shouldRetry(id: "r", live: true, ended: true, now: instant.addingTimeInterval(1)))
        precondition(!policy.shouldRetry(id: "r", live: false, ended: true, now: instant.addingTimeInterval(10)))
        precondition(policy.shouldRetry(id: "r", live: true, ended: true, now: instant.addingTimeInterval(3)))
        let original = Workspace(id: "w", name: "离线修改", path: "/tmp", hostID: "remote", split: true, archived: true, syncPending: true)
        var server = ServerWorkspace(original); server.name = "旧的远端名称"
        let recoverySnapshot = RunList(runs: [r], concurrency: 4, workspaces: [server])
        let merged = WorkspaceRecovery.merge(local: [original], hostID: "remote", snapshot: recoverySnapshot)
        precondition(merged.first == original, "Do not overwrite local edits or hidden workspaces")
        let recovered = WorkspaceRecovery.merge(local: [], hostID: "remote", snapshot: recoverySnapshot)
        precondition(recovered.first?.hostID == "remote" && recovered.first?.split == true)
        let legacy = WorkspaceRecovery.merge(local: [], hostID: "legacy", snapshot: RunList(runs: [r], concurrency: 4))
        precondition(legacy.first?.id == "w" && legacy.first?.selectedRunID == "r")
        let legacyLayout = Data("""
        {"id":"layout","name":"Layout","path":"/tmp","hostID":"local","split":true,"selectedRunID":"a","secondaryRunID":"b"}
        """.utf8)
        var layout = try JSONDecoder().decode(Workspace.self, from: legacyLayout)
        let available = ["a", "b", "c", "d"]
        precondition(layout.visibleRunIDs(available: available) == ["a", "b"])
        precondition(layout.moveTerminal("c", beside: "a", side: .left, available: available))
        precondition(layout.paneRunIDs == ["c", "a", "b"])
        precondition(layout.moveTerminal("c", beside: "b", side: .right, available: available))
        precondition(layout.paneRunIDs == ["a", "b", "c"])
        layout.selectTerminal("b", available: available)
        precondition(layout.paneRunIDs == ["a", "b", "c"], "Focusing a visible pane must not move or duplicate it")
        layout.selectTerminal("d", available: available)
        precondition(layout.paneRunIDs == ["a", "d", "c"], "A hidden tab replaces only the focused pane")
        let beforeInvalidMove = layout
        precondition(!layout.moveTerminal("d", beside: "d", side: .left, available: available))
        precondition(!layout.moveTerminal("missing", beside: "a", side: .right, available: available))
        precondition(!layout.moveTerminal("b", beside: "missing", side: .left, available: available))
        precondition(layout == beforeInvalidMove)
        precondition(layout.visibleRunIDs(available: ["a", "c"]) == ["a", "c"], "Archived sessions should disappear without displacing surviving panes")
        precondition(layout.visibleRunIDs(available: ["b"]) == ["b"])
        precondition(layout.visibleRunIDs(available: []) == [])
        let savedLayout = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(layout))
        precondition(savedLayout == layout)
        let serverLayout = try JSONDecoder().decode(ServerWorkspace.self, from: JSONEncoder().encode(ServerWorkspace(layout)))
        precondition(serverLayout.workspace(hostID: "remote").paneRunIDs == ["a", "d", "c"])
        layout.paneRunIDs = ["a", "a", "missing", "c"]
        precondition(layout.visibleRunIDs(available: available) == ["a", "c"])
        layout.setPanes(["c"], focused: "a")
        precondition(!layout.split && layout.selectedRunID == "c" && layout.secondaryRunID == nil)
        print("PASS dynamic split: left/right insertion, movement, focus, tab replacement, invalid drops, cleanup, legacy migration and persistence")
        print("PASS recovery models: retry backoff, offline edits, hidden workspaces, legacy runtime")
        print("PASS Swift model checks: SSH validation, quoting, remote paths, process/result semantics")
    }
}
