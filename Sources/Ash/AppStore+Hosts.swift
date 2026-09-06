import Foundation

extension AppStore {
    func refreshInBackground() { Task { await refresh() } }

    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for host in hosts where host.isLocal || (host.managed && host.connectsAutomatically) {
                group.addTask { await self.refreshHost(host) }
            }
            await group.waitForAll()
        }
    }

    private func refreshHost(_ host: Host) async {
        guard hostConnectionTasks[host.id] == nil, hostRetry.permits(host.id) else { return }
        await runHostConnection(host, force: false)
    }

    func connectHost(_ host: Host, installRuntime: Bool = false) async {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        if !hosts[index].connectsAutomatically {
            let previous = hosts[index]
            hosts[index].autoConnect = true
            if !persistState() { hosts[index] = previous }
        }
        let current = hosts[index]
        if let pending = hostConnectionTasks[host.id] {
            await pending.task.value
            // A manual retry must still bypass a cached failure after background work finishes.
            if (!installRuntime || pending.installRuntime) && (pending.force || connectionErrors[host.id] == nil) {
                return
            }
        }
        hostRetry.reset(host.id)
        await runHostConnection(current, force: true, installRuntime: installRuntime)
    }

    private func runHostConnection(_ host: Host, force: Bool, installRuntime: Bool = false) async {
        guard hosts.contains(where: { $0.hasSameConnection(as: host) }) else { return }
        if let pending = hostConnectionTasks[host.id] {
            await pending.task.value
            return
        }
        let token = UUID()
        let showRoutineProgress = force || connectionErrors[host.id] != nil || hostLastConnected[host.id] == nil
        connectingHosts.insert(host.id)
        if showRoutineProgress {
            runtimeSetup[host.id] = "正在连接…"
        }
        let task = Task { [self] in
            defer {
                if hostConnectionTasks[host.id]?.token == token {
                    hostConnectionTasks[host.id] = nil
                    connectingHosts.remove(host.id)
                }
            }
            do {
                let result = try await hostConnector.connect(host, force: force, installRuntime: installRuntime) {
                    [weak self] message in
                    guard let self, self.isCurrentConnection(host, token: token) else { return }
                    // Healthy polling is bookkeeping, not a new connection. Real installation
                    // stages still surface even when a scheduled version check triggers them.
                    let routine = ["正在检查远端环境…", "正在恢复工作区…", "已就绪", "准备失败"]
                    if showRoutineProgress || !routine.contains(message) {
                        self.runtimeSetup[host.id] = message
                    }
                }
                guard isCurrentConnection(host, token: token) else { return }
                if let health = result.health, let snapshot = result.snapshot {
                    applySnapshot(snapshot, health: health, hostID: host.id)
                }
                connectionErrors[host.id] = nil
                runtimeUpdateErrors[host.id] = result.updateError
                runtimeSetup[host.id] = result.updateError == nil ? "已就绪" : "更新未完成 · 继续使用当前版本"
                hostLastConnected[host.id] = Date()
                hostRetry.reset(host.id)
            } catch {
                guard isCurrentConnection(host, token: token) else { return }
                connectionErrors[host.id] = error.localizedDescription
                runtimeSetup[host.id] = "连接未完成"
                hostRetry.failed(host.id)
                await RemoteRuntimeManager.shared.invalidate(host)
            }
        }
        hostConnectionTasks[host.id] = (token, force, installRuntime, task)
        await task.value
    }

    private func isCurrentConnection(_ host: Host, token: UUID) -> Bool {
        hostConnectionTasks[host.id]?.token == token && hosts.contains { $0.hasSameConnection(as: host) }
    }

    func validateHost(_ candidate: Host) throws {
        guard !candidate.isLocal, validSSHAddress(candidate.address),
            !candidate.managed || validRuntimePath(candidate.runtimePath)
        else {
            throw AshError(message: "请检查 SSH 地址和运行程序路径。")
        }
        guard !hosts.contains(where: { !$0.isLocal && $0.id != candidate.id && $0.address == candidate.address }) else {
            throw AshError(message: "这个 SSH 地址已添加，请编辑已有主机。")
        }
        if let existing = hosts.first(where: { $0.id == candidate.id }) {
            if !existing.hasSameConnection(as: candidate), connectingHosts.contains(candidate.id) {
                throw AshError(message: "主机正在连接，请完成后再修改连接设置。")
            }
            if existing.address != candidate.address, workspaces.contains(where: { $0.hostID == candidate.id }) {
                throw AshError(message: "主机关联着工作区；连接另一台服务器时，请添加新主机。")
            }
        }
    }

    @discardableResult
    func saveHost(_ draft: HostDraft, replacing id: String? = nil, connectAutomatically: Bool? = nil) throws -> Host {
        var candidate = try draft.host(id: id ?? UUID().uuidString)
        if let connectAutomatically { candidate.autoConnect = connectAutomatically }
        if let id, !hosts.contains(where: { $0.id == id }) { throw AshError(message: "这台主机已被移除。") }
        try validateHost(candidate)
        let oldHosts = hosts
        let previous = hosts.first { $0.id == candidate.id }
        if let index = hosts.firstIndex(where: { $0.id == candidate.id }) {
            hosts[index] = candidate
        } else {
            hosts.append(candidate)
        }
        guard persistState() else {
            hosts = oldHosts
            throw AshError(message: error ?? "主机配置未能保存。")
        }
        if previous?.hasSameConnection(as: candidate) != true {
            connectionErrors[candidate.id] = nil
            runtimeSetup[candidate.id] = nil
            runtimeUpdateErrors[candidate.id] = nil
            hostLastConnected[candidate.id] = nil
            hostRetry.reset(candidate.id)
            if let previous, previous.address != candidate.address {
                health[candidate.id] = nil
                runs[candidate.id] = nil
            }
        }
        return candidate
    }

    func removalReason(for host: Host) -> String? {
        if host.isLocal { return "这台 Mac 是本地主机。" }
        if connectingHosts.contains(host.id) { return "主机正在连接，请完成后再移除。" }
        let count = workspaces.filter { $0.hostID == host.id }.count
        if count > 0 { return "关联 \(count) 个工作区（含隐藏工作区），暂不能移除。" }
        return nil
    }

    func removeHost(_ host: Host) throws {
        if let reason = removalReason(for: host) { throw AshError(message: reason) }
        let oldHosts = hosts
        hosts.removeAll { $0.id == host.id }
        guard persistState() else {
            hosts = oldHosts
            throw AshError(message: error ?? "主机配置未能保存。")
        }
        health[host.id] = nil
        runs[host.id] = nil
        connectionErrors[host.id] = nil
        runtimeUpdateErrors[host.id] = nil
        runtimeSetup[host.id] = nil
        hostLastConnected[host.id] = nil
        hostRetry.reset(host.id)
    }

    func hostStatus(_ host: Host) -> String {
        if connectingHosts.contains(host.id), hostLastConnected[host.id] == nil || connectionErrors[host.id] != nil {
            return runtimeSetup[host.id] ?? "正在连接…"
        }
        if let error = connectionErrors[host.id] { return HostConnectionIssue(error).title }
        if runtimeUpdateErrors[host.id] != nil { return "已连接 · 更新未完成" }
        if hostLastConnected[host.id] != nil || (host.isLocal && health[host.id] != nil) { return "已连接" }
        return host.isLocal ? "准备中" : "尚未连接"
    }
}
