import Combine
import Foundation

actor FixtureConnector: HostConnecting {
    private var calls: [(String, Bool, Bool)] = []
    var failing = false
    var delay: UInt64 = 0
    private var slowHost: String?
    private var slowContinuation: CheckedContinuation<Void, Never>?
    func configure(failing: Bool, delay: UInt64 = 0) { self.failing = failing; self.delay = delay }
    func count() -> Int { calls.count }
    func count(for id: String) -> Int { calls.filter { $0.0 == id }.count }
    func setSlowHost(_ id: String) { slowHost = id }
    func releaseSlowHost() { slowContinuation?.resume(); slowContinuation = nil }
    func lastInstall() -> Bool { calls.last?.2 ?? false }
    func connect(_ host: Host, force: Bool, installRuntime: Bool,
                 progress: @escaping RemoteRuntimeManager.Progress) async throws -> HostConnectionResult {
        calls.append((host.id, force, installRuntime))
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if slowHost == host.id { await withCheckedContinuation { slowContinuation = $0 } }
        await progress("正在检查远端环境…")
        await progress("正在恢复工作区…")
        if failing { throw AshError(message: "Permission denied (publickey)") }
        if !host.managed { return HostConnectionResult() }
        let health = Health(protocol: 1, version: "0.1.2", platform: "macos", arch: "aarch64", tmux: "/fixture/tmux",
                            socket: "/fixture/socket", root: "/fixture", agents: [], concurrency: 4)
        return HostConnectionResult(health: health, snapshot: RunList(runs: [], concurrency: 4))
    }
}

@main struct HostManagementChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ash-host-checks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let connector = FixtureConnector()
        let store = AppStore(directory: root, hostConnector: connector)
        store.hosts = []
        var draft = HostDraft()
        draft.address = "  user@server  "
        draft.autoInstallRuntime = false
        let host = try store.saveHost(draft)
        precondition(host.address == "user@server" && host.name == "user@server")
        precondition(!host.installsRuntimeAutomatically)
        do { _ = try store.saveHost(draft); fatalError("Duplicate accepted") } catch {}
        draft.name = "Development"
        let edited = try store.saveHost(draft, replacing: host.id)
        precondition(edited.id == host.id && store.hosts.count == 1)
        precondition(AppStore(directory: root).hosts.contains { $0.id == host.id && $0.name == "Development" })
        store.workspaces = [Workspace(id: "w", name: "W", path: "/tmp", hostID: host.id, archived: true)]
        draft.address = "other-server"
        do { _ = try store.saveHost(draft, replacing: host.id); fatalError("Rebound workspace to another host") } catch {}
        do { try store.removeHost(edited); fatalError("Removed host with hidden workspace") } catch {}
        precondition(store.hosts[0].address == "user@server")
        store.workspaces = []

        await connector.configure(failing: false, delay: 150_000_000)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { await store.connectHost(edited) } }
        }
        let deduplicated = await connector.count()
        precondition(deduplicated == 1 && store.connectingHosts.isEmpty)
        let installed = await connector.lastInstall()
        precondition(!installed && store.hosts[0].autoInstallRuntime == false)
        await store.connectHost(edited, installRuntime: true)
        let manual = await connector.lastInstall()
        precondition(manual && store.hosts[0].autoInstallRuntime == false)
        var phases: [String] = []
        let observer = store.$runtimeSetup.sink { values in if let value = values[edited.id] { phases.append(value) } }
        await store.refresh()
        precondition(!phases.contains("正在恢复工作区…") && !phases.contains("正在检查远端环境…"), "Healthy polling must be silent")
        phases = []
        await store.connectHost(edited)
        precondition(phases.contains("正在恢复工作区…"), "Explicit reconnect still shows progress")
        observer.cancel()
        await connector.configure(failing: true)
        await store.connectHost(edited)
        precondition(store.hostStatus(edited) == "需要 SSH 认证")
        let failedCount = await connector.count()
        await store.refresh()
        let backedOff = await connector.count()
        precondition(failedCount == backedOff)
        await connector.configure(failing: false)
        await store.connectHost(edited)
        precondition(store.connectionErrors[host.id] == nil && store.hostStatus(edited) == "已连接")

        // A stale transport result cannot recreate a removed host's connection state.
        await connector.configure(failing: false, delay: 150_000_000)
        let pending = Task { await store.connectHost(edited) }
        try await Task.sleep(nanoseconds: 20_000_000)
        store.hosts = []
        store.runtimeSetup = [:]
        store.hostLastConnected = [:]
        store.health = [:]
        await pending.value
        precondition(store.runtimeSetup.isEmpty && store.hostLastConnected.isEmpty && store.health.isEmpty)
        precondition(store.connectingHosts.isEmpty)

        let savedOnlyConnector = FixtureConnector()
        let savedOnlyStore = AppStore(directory: root.appendingPathComponent("saved-only"), hostConnector: savedOnlyConnector)
        savedOnlyStore.hosts = []
        var savedOnlyDraft = HostDraft(); savedOnlyDraft.address = "saved-only"; savedOnlyDraft.autoInstallRuntime = false
        let savedOnly = try savedOnlyStore.saveHost(savedOnlyDraft, connectAutomatically: false)
        await savedOnlyStore.refresh()
        let unconnectedCount = await savedOnlyConnector.count()
        precondition(unconnectedCount == 0 && savedOnlyStore.hostLastConnected.isEmpty)
        await savedOnlyStore.connectHost(savedOnly)
        let connectedCount = await savedOnlyConnector.count()
        precondition(connectedCount == 1 && savedOnlyStore.hosts[0].connectsAutomatically)
        let independent = FixtureConnector()
        let separate = AppStore(directory: root.appendingPathComponent("separate"), hostConnector: independent)
        let slow = Host(id: "slow", name: "Slow", address: "slow", autoInstallRuntime: false)
        let fast = Host(id: "fast", name: "Fast", address: "fast", autoInstallRuntime: false)
        separate.hosts = [slow, fast]
        await independent.setSlowHost(slow.id)
        let firstRefresh = Task { await separate.refresh() }
        try await Task.sleep(nanoseconds: 40_000_000)
        await separate.refresh()
        let fastChecks = await independent.count(for: fast.id)
        let slowChecks = await independent.count(for: slow.id)
        precondition(fastChecks == 2 && slowChecks == 1 && separate.connectingHosts.contains(slow.id))
        await independent.releaseSlowHost()
        await firstRefresh.value
        for address in ["host:22", "user@", "@host", "user@@host", "[]", "user@[bad]", "-option"] {
            draft.address = address
            do { _ = try draft.host(); fatalError("Invalid address accepted: \(address)") } catch {}
        }
        draft.address = "user@[::1]"
        _ = try draft.host()
        var policy = HostRetryPolicy()
        let now = Date(timeIntervalSince1970: 100)
        policy.failed("host", now: now)
        precondition(!policy.permits("host", now: now.addingTimeInterval(2)))
        precondition(policy.permits("host", now: now.addingTimeInterval(3)))
        precondition(policy.permits("another", now: now))
        policy.reset("host")
        precondition(policy.permits("host", now: now))
        precondition(HostConnectionIssue("Host key verification failed").kind == .hostKey)
        precondition(HostConnectionIssue("Connection refused").kind == .network)
        precondition(HostConnectionIssue("ash-runtime: command not found").kind == .runtime)

        let config = root.appendingPathComponent("config")
        let included = root.appendingPathComponent("included config")
        try "Host included second\nHost * !excluded\nInclude \"\(config.path)\"\n".write(to: included, atomically: true, encoding: .utf8)
        try "Host main # comment alias\nHOST=quoted\nHost =second-quoted\nInclude \"\(included.path)\"\nHost main\nMatch exec \"touch forbidden\"\n".write(to: config, atomically: true, encoding: .utf8)
        precondition(SSHConfigDiscovery.aliases(at: config) == ["included", "main", "quoted", "second", "second-quoted"])

        let bad = root.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        let file = bad.appendingPathComponent("state.json")
        try Data("broken".utf8).write(to: file)
        let protected = AppStore(directory: bad)
        draft.address = "valid-host"
        do { _ = try protected.saveHost(draft); fatalError("Unsaved host accepted") } catch {}
        precondition(protected.hosts == [.local])
        print("PASS host management: normalized CRUD, duplicates, linked-workspace protection, atomic save failure, deduplicated checks, paused updates, retry backoff, stale response rejection, safe SSH alias discovery")
    }
}
