import Foundation

struct HostConnectionResult {
    var health: Health?
    var snapshot: RunList?
    var updateError: String?
}

protocol HostConnecting: Sendable {
    func connect(
        _ host: Host, force: Bool, installRuntime: Bool,
        progress: @escaping RemoteRuntimeManager.Progress
    ) async throws -> HostConnectionResult
}

struct HostConnectionService: HostConnecting {
    func connect(
        _ host: Host, force: Bool, installRuntime: Bool,
        progress: @escaping RemoteRuntimeManager.Progress
    ) async throws -> HostConnectionResult {
        guard host.isLocal || validSSHAddress(host.address) else { throw AshError(message: "无效的 SSH 主机地址。") }
        if !host.isLocal && !host.managed {
            await progress("正在测试 SSH 连接…")
            let output = try await RuntimeClient.execute(
                LaunchSpec(
                    executable: "/usr/bin/ssh",
                    arguments: RuntimeClient.sshOptions + [
                        "-o", "BatchMode=yes", "-T", host.address,
                        "printf '\\nASH_SSH_READY\\n'",
                    ]))
            guard String(decoding: output, as: UTF8.self).split(separator: "\n").contains("ASH_SSH_READY") else {
                throw AshError(message: "SSH 未返回连接确认，请检查登录脚本。")
            }
            return HostConnectionResult()
        }
        let prepared = try await Self.prepare(host, force: force, installRuntime: installRuntime, progress: progress)
        await progress("正在恢复工作区…")
        let snapshot: RunList = try await RuntimeClient().call(host, "list")
        return HostConnectionResult(health: prepared.health, snapshot: snapshot, updateError: prepared.updateError)
    }

    static func prepare(
        _ host: Host, force: Bool = false, installRuntime: Bool = false,
        progress: @escaping RemoteRuntimeManager.Progress
    ) async throws -> HostConnectionResult {
        guard host.isLocal || (validSSHAddress(host.address) && validRuntimePath(host.runtimePath)) else {
            throw AshError(message: "SSH 主机地址或运行程序路径无效。")
        }
        var target = host
        // Only the explicit installation action may override a paused automatic-update preference.
        if installRuntime { target.autoInstallRuntime = true }
        let client = RuntimeClient()
        do {
            try await RemoteRuntimeManager.shared.prepare(target, force: force, progress: progress)
        } catch {
            if let existing: Health = try? await client.call(host, "health"), existing.protocol == 1 {
                return HostConnectionResult(health: existing, updateError: error.localizedDescription)
            }
            throw error
        }
        let health: Health = try await client.call(host, "health")
        guard health.protocol == 1 else { throw AshError(message: "远端协议不兼容，请更新 Ash 客户端。") }
        return HostConnectionResult(health: health)
    }
}
