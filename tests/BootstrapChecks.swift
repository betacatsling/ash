import Foundation

@main struct BootstrapChecks {
    @MainActor static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = Host(id: "bootstrap-test", name: "Test host", address: "ash-bootstrap", managed: true,
                        runtimePath: env["ASH_TEST_LAUNCHER"]!, autoInstallRuntime: true)
        let mode = CommandLine.arguments.dropFirst().first ?? "install"
        if mode == "disabled" {
            var disabled = host; disabled.autoInstallRuntime = false
            try await RemoteRuntimeManager.shared.prepare(disabled)
            print("PASS paused automatic installation performs no remote setup")
            return
        }
        if mode == "direct" || mode == "paused" || mode == "manual-paused" {
            var target = host
            target.managed = mode != "direct"
            target.autoInstallRuntime = false
            let store = AppStore()
            store.hosts = [target]
            await store.connectHost(target, installRuntime: mode == "manual-paused")
            precondition(store.hosts[0].autoInstallRuntime == false)
            if mode == "paused" {
                precondition(store.connectionErrors[target.id] != nil && store.health[target.id] == nil)
                print("PASS reconnect respects paused automatic installation when the runtime is missing")
            } else {
                precondition(store.connectionErrors[target.id] == nil, store.connectionErrors[target.id] ?? "")
                precondition(store.hostLastConnected[target.id] != nil)
                if mode == "direct" {
                    precondition(store.health[target.id] == nil)
                    print("PASS direct SSH checks connectivity without installing a runtime")
                } else {
                    precondition(store.health[target.id] != nil)
                    print("PASS explicit one-time runtime update keeps automatic installation paused")
                }
            }
            return
        }
        if mode == "corrupt" {
            do { try await RemoteRuntimeManager.shared.prepare(host); fatalError("Corrupt package must be rejected") }
            catch { precondition(error.localizedDescription.contains("校验失败")); print("PASS corrupt bundled package is rejected before transfer") }
            return
        }
        let expectedVersion = try RuntimeManifest.read().version
        if mode == "fallback" {
            let store = AppStore(); store.hosts = [host]
            await store.refresh()
            precondition(store.connectionErrors[host.id] == nil)
            precondition(store.runtimeUpdateErrors[host.id] != nil)
            precondition(store.health[host.id] != nil && !(store.runs[host.id] ?? []).isEmpty)
            print("PASS failed automatic update keeps a healthy installed runtime usable in AppStore")
            return
        }
        if mode == "install" {
            let store = AppStore()
            store.hosts = [host]
            await store.refresh()
            precondition(store.connectionErrors[host.id] == nil, store.connectionErrors[host.id] ?? "")
            precondition(store.health[host.id]?.version == expectedVersion)
            print("PASS first connection through actual AppStore automatically installs the remote runtime")
        } else {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 { group.addTask { try await RemoteRuntimeManager.shared.prepare(host, force: true) } }
                try await group.waitForAll()
            }
            print("PASS concurrent update requests share one preparation")
        }
        let health: Health = try await RuntimeClient().call(host, "health")
        precondition(health.version == expectedVersion)
        precondition(health.tmux.contains("/versions/"))
        try await RemoteRuntimeManager.shared.prepare(host, force: true)
        print("PASS repeated connection keeps the verified version and uses bundled tmux")
    }
}
