import CryptoKit
import Foundation

struct RuntimePackage: Decodable {
    var target: String
    var file: String
    var sha256: String
    var size: Int
}
struct RuntimeManifest: Decodable {
    var format: Int
    var version: String
    var `protocol`: Int
    var packages: [RuntimePackage]
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["ASH_RUNTIME_PACKAGES"] { return URL(fileURLWithPath: path) }
        return Bundle.main.resourceURL?.appendingPathComponent("runtime-packages")
            ?? URL(fileURLWithPath: "dist/runtime-packages")
    }
    static func read() throws -> RuntimeManifest {
        let manifest = try JSONDecoder().decode(
            Self.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.format == 1, manifest.protocol == 1, RuntimeVersion(manifest.version) != nil else {
            throw AshError(message: "Ash 安装包清单不兼容，请重新安装应用。")
        }
        return manifest
    }
    func payload(target: String) throws -> Data {
        guard let item = packages.first(where: { $0.target == target }) else {
            throw AshError(message: "当前 Ash 安装包尚不支持这台服务器（\(target)）。")
        }
        guard !item.file.isEmpty, item.file == URL(fileURLWithPath: item.file).lastPathComponent,
            !item.file.contains("/"), item.sha256.count == 64, item.sha256.allSatisfy({ $0.isHexDigit }),
            (1...100_000_000).contains(item.size)
        else { throw AshError(message: "Ash 安装包清单无效。") }
        let data = try Data(contentsOf: Self.directory.appendingPathComponent(item.file))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == item.size, hash == item.sha256 else {
            throw AshError(message: "Ash 安装包校验失败；服务器原版本未修改。请重新安装应用。")
        }
        return data
    }
}
struct RuntimeVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ text: String) {
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let parts = fields.compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.parts = parts
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

actor RemoteRuntimeManager {
    static let shared = RemoteRuntimeManager()
    typealias Progress = @MainActor @Sendable (String) -> Void
    private var pending: [String: Task<Void, Error>] = [:]
    private var checked: [String: Date] = [:]
    private var failures: [String: (Date, String)] = [:]

    func prepare(_ host: Host, force: Bool = false, progress: @escaping Progress = { _ in }) async throws {
        guard !host.isLocal, host.managed, host.installsRuntimeAutomatically else { return }
        let key = host.address + "\n" + host.runtimePath
        if let task = pending[key] { return try await task.value }
        if !force {
            if let date = checked[key], Date().timeIntervalSince(date) < 300 { return }
            if let (date, message) = failures[key], Date().timeIntervalSince(date) < 60 {
                throw AshError(message: message)
            }
        }
        let task = Task { try await Self.installIfNeeded(host, progress: progress) }
        pending[key] = task
        defer { pending[key] = nil }
        do {
            try await task.value
            checked[key] = Date()
            failures[key] = nil
            await progress("已就绪")
        } catch {
            checked[key] = nil
            failures[key] = (Date(), error.localizedDescription)
            await progress("准备失败")
            throw error
        }
    }
    func invalidate(_ host: Host) { checked[host.address + "\n" + host.runtimePath] = nil }

    private static func spec(_ host: Host, mode: String, manifest: RuntimeManifest? = nil, target: String? = nil) throws
        -> LaunchSpec
    {
        guard validSSHAddress(host.address), validRuntimePath(host.runtimePath) else {
            throw AshError(message: "SSH 主机地址或安装路径无效。")
        }
        let path =
            ProcessInfo.processInfo.environment["ASH_BOOTSTRAP_SCRIPT"] ?? Bundle.main.path(
                forResource: "remote-bootstrap", ofType: "sh") ?? "scripts/remote-bootstrap.sh"
        let script = try String(contentsOfFile: path, encoding: .utf8)
        var args = [
            "sh", "-c", script, "ash-bootstrap", mode, host.runtimePath,
            ProcessInfo.processInfo.environment["ASH_REMOTE_RUNTIME_HOME"] ?? "",
        ]
        if let manifest, let item = manifest.packages.first(where: { $0.target == target }) {
            args += [manifest.version, item.sha256]
        }
        return LaunchSpec(
            executable: "/usr/bin/ssh",
            arguments: RuntimeClient.sshOptions + [
                "-o", "BatchMode=yes", "-T", host.address, args.map(shellQuote).joined(separator: " "),
            ])
    }
    private static func installIfNeeded(_ host: Host, progress: @escaping Progress) async throws {
        await progress("正在检查远端环境…")
        let manifest = try RuntimeManifest.read()
        let data = try await RuntimeClient.execute(spec(host, mode: "probe"))
        guard
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n").last(where: {
                $0.hasPrefix("ASH_PROBE|")
            })
        else { throw AshError(message: "无法识别服务器环境，请先完成 SSH 认证。") }
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, ["macos", "linux"].contains(parts[1]), ["aarch64", "x86_64"].contains(parts[2]) else {
            throw AshError(message: "服务器平台不受支持。")
        }
        if parts.count == 8, parts[3] == "ASH_READY", let remote = RuntimeVersion(parts[4]),
            let desired = RuntimeVersion(manifest.version)
        {
            guard parts[5] == String(manifest.protocol) else { throw AshError(message: "远端协议与此版本 Ash 不兼容，请更新客户端。") }
            if remote >= desired { return }  // An older client must never downgrade a newer server.
        }
        let target = parts[1] + "-" + parts[2]
        await progress("正在校验安装包…")
        let payload = try manifest.payload(target: target)
        await progress("正在传输并安装 \(manifest.version)…")
        let result = try await RuntimeClient.execute(
            spec(host, mode: "install", manifest: manifest, target: target), input: payload, timeoutSeconds: 180)
        guard
            String(decoding: result, as: UTF8.self).split(separator: "\n").contains(
                Substring("ASH_INSTALLED|" + manifest.version))
        else { throw AshError(message: "服务器未确认安装成功，请重试连接。") }
        await progress("正在恢复工作区…")
    }
}
