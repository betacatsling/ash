import Foundation

struct HostDraft: Equatable {
    var name = ""
    var address = ""
    var managed = true
    var autoInstallRuntime = true
    var autoConnect = true
    var runtimePath = ".local/bin/ash-runtime"

    init() {}
    init(_ host: Host) {
        name = host.name
        address = host.address
        managed = host.managed
        autoInstallRuntime = host.installsRuntimeAutomatically
        autoConnect = host.connectsAutomatically
        runtimePath = host.runtimePath
    }

    func host(id: String = UUID().uuidString) throws -> Host {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = runtimePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validSSHAddress(address) else {
            throw AshError(message: "请输入 SSH 别名或 user@host；端口、密钥和跳板请在 SSH 配置中设置。")
        }
        guard !managed || validRuntimePath(path) else {
            throw AshError(message: "运行程序路径不能为空，也不能包含换行或控制字符。")
        }
        return Host(
            id: id, name: name.isEmpty ? address : name, address: address, managed: managed,
            runtimePath: path.isEmpty ? ".local/bin/ash-runtime" : path, autoInstallRuntime: autoInstallRuntime,
            autoConnect: autoConnect)
    }
}

func validRuntimePath(_ path: String) -> Bool {
    !path.isEmpty && !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

extension Host {
    /// Display name changes do not invalidate an in-flight connection.
    func hasSameConnection(as other: Host) -> Bool {
        id == other.id && address == other.address && managed == other.managed
            && runtimePath == other.runtimePath && installsRuntimeAutomatically == other.installsRuntimeAutomatically
    }
}

struct HostConnectionIssue: Equatable {
    enum Kind { case authentication, hostKey, network, runtime, other }
    let kind: Kind
    let title: String
    let suggestion: String
    let detail: String

    init(_ detail: String) {
        self.detail = detail
        let text = detail.lowercased()
        if text.contains("host key verification failed") || text.contains("remote host identification has changed") {
            kind = .hostKey
            title = "需要核对主机指纹"
            suggestion = "打开 SSH 终端核对主机身份；如指纹发生变化，请先确认服务器是否更换。"
        } else if text.contains("permission denied") || text.contains("authentication failed")
            || text.contains("认证")
        {
            kind = .authentication
            title = "需要 SSH 认证"
            suggestion = "打开 SSH 终端完成认证，或检查此主机的密钥配置。"
        } else if [
            "could not resolve hostname", "connection refused", "connection timed out", "operation timed out",
            "network is unreachable", "no route to host", "connection closed", "connection reset", "连接超时",
        ]
        .contains(where: text.contains) {
            kind = .network
            title = "暂时无法连接"
            suggestion = "检查主机地址和网络，再重试连接。"
        } else if ["ash-runtime", "tmux", "协议", "安装包", "运行程序"].contains(where: text.contains) {
            kind = .runtime
            title = "运行环境尚未就绪"
            suggestion = "检查运行程序路径，或安装 / 更新运行环境。"
        } else {
            kind = .other
            title = "连接未完成"
            suggestion = "查看错误详情后重试；需要交互认证时可打开 SSH 终端。"
        }
    }
}

struct HostRetryPolicy {
    private var failures: [String: Int] = [:]
    private var deadlines: [String: Date] = [:]
    func permits(_ id: String, now: Date = Date()) -> Bool { now >= (deadlines[id] ?? .distantPast) }
    mutating func failed(_ id: String, now: Date = Date()) {
        let count = failures[id, default: 0]
        deadlines[id] = now.addingTimeInterval(min(60, 3 * pow(2, Double(min(count, 5)))))
        failures[id] = count + 1
    }
    mutating func reset(_ id: String) {
        failures[id] = nil
        deadlines[id] = nil
    }
}
