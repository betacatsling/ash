import Foundation

struct LaunchSpec {
    var executable: String
    var arguments: [String]
    var directory: String? = nil
}
struct RuntimeClient {
    static var environment: [String: String] {
        var e = ProcessInfo.processInfo.environment
        let h = NSHomeDirectory()
        e["PATH"] =
            "\(h)/.local/bin:\(h)/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:"
            + (e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return e
    }
    static var terminalEnvironment: [String: String] { TerminalEnvironment.make(from: environment) }
    static var executable: String {
        if let p = ProcessInfo.processInfo.environment["ASH_RUNTIME_BIN"] { return p }
        if let p = Bundle.main.path(forResource: "ash-runtime", ofType: nil) { return p }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "runtime/target/debug/ash-runtime"
        ).path
    }
    static var sshOptions: [String] {
        let directory = NSHomeDirectory() + "/.local/share/ash/ssh"
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let customConfig = ProcessInfo.processInfo.environment["ASH_SSH_CONFIG"].map { ["-F", $0] } ?? []
        return customConfig + [
            "-o", "ConnectTimeout=12", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=auto", "-o", "ControlPersist=600", "-o", "ControlPath=\(directory)/%C",
        ]
    }
    static func remoteRuntime(_ host: Host) -> String {
        let path = host.runtimePath
        let executable =
            path.hasPrefix("/")
            ? shellQuote(path) : "$HOME/" + shellQuote(path.hasPrefix("~/") ? String(path.dropFirst(2)) : path)
        return
            "export PATH=\"$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; exec \(executable) request"
    }
    func call<T: Decodable>(_ host: Host, _ action: String, _ values: [String: Any] = [:], as type: T.Type = T.self)
        async throws -> T
    {
        guard host.isLocal || (validSSHAddress(host.address) && validRuntimePath(host.runtimePath)) else {
            throw AshError(message: "SSH 主机地址或运行程序路径无效。")
        }
        var request = values
        request["protocol"] = 1
        request["action"] = action
        let input = try JSONSerialization.data(withJSONObject: request)
        let spec =
            host.isLocal
            ? LaunchSpec(executable: Self.executable, arguments: ["request"])
            : LaunchSpec(
                executable: "/usr/bin/ssh",
                arguments: Self.sshOptions + ["-o", "BatchMode=yes", "-T", host.address, Self.remoteRuntime(host)])
        let data = try await Self.execute(spec, input: input)
        // Login scripts may print a banner; the runtime owns the final JSON envelope.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        guard let line = lines.last(where: { $0.hasPrefix("{") }),
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        else {
            throw AshError(
                message: "运行程序没有返回有效响应。请检查 SSH 认证与 ash-runtime 安装。\n"
                    + String(decoding: data.prefix(2000), as: UTF8.self))
        }
        guard obj["ok"] as? Bool == true else { throw AshError(message: obj["error"] as? String ?? "运行程序请求失败") }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: obj["data"] ?? [:]))
    }
    static func execute(_ spec: LaunchSpec, input: Data? = nil, timeoutSeconds: Double = 45) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let p = Process()
            let out = Pipe()
            let stdin = Pipe()
            p.executableURL = URL(fileURLWithPath: spec.executable)
            p.arguments = spec.arguments
            p.environment = Self.environment
            p.standardOutput = out
            p.standardError = out
            if let d = spec.directory { p.currentDirectoryURL = URL(fileURLWithPath: d) }
            p.standardInput = input == nil ? FileHandle.nullDevice : stdin
            try p.run()
            let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            if let input {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
            let result = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            timeout.cancel()
            guard p.terminationStatus == 0 else {
                let message = String(decoding: result.prefix(4000), as: UTF8.self)
                throw AshError(
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "操作未完成或连接超时" : message)
            }
            return result
        }.value
    }
    static func terminalSpec(host: Host, run: Run, health: Health?) -> LaunchSpec {
        if run.status == "direct" {
            let directory = run.cwd.hasPrefix("/") ? "cd \(shellQuote(run.cwd)) && " : ""
            let command = TerminalEnvironment.remoteSetup + directory + "exec \"${SHELL:-/bin/sh}\" -l"
            return LaunchSpec(executable: "/usr/bin/ssh", arguments: sshOptions + ["-tt", host.address, command])
        }
        guard let health else {
            return LaunchSpec(executable: "/bin/sh", arguments: ["-c", "printf 'Ash: 主机信息尚未就绪\\n'"])
        }
        let args = ["-S", health.socket, "attach-session", "-t", "=\(run.session)"]
        if host.isLocal { return LaunchSpec(executable: health.tmux, arguments: args) }
        let termInfo = health.termInfo.map { "export TERMINFO_DIRS=\(shellQuote($0)); " } ?? ""
        let command = TerminalEnvironment.remoteSetup + termInfo + "exec " + ([health.tmux] + args).map(shellQuote).joined(separator: " ")
        return LaunchSpec(executable: "/usr/bin/ssh", arguments: sshOptions + ["-tt", host.address, command])
    }
}
