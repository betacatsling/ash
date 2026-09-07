import Darwin
import Foundation

struct Host: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var address: String = ""
    var managed: Bool = true
    var runtimePath: String = ".local/bin/ash-runtime"
    var autoInstallRuntime: Bool? = nil
    var autoConnect: Bool? = nil
    var connectsAutomatically: Bool { autoConnect ?? true }
    var installsRuntimeAutomatically: Bool { autoInstallRuntime ?? (runtimePath == ".local/bin/ash-runtime") }
    var isLocal: Bool { id == "local" }
    static let local = Host(id: "local", name: "这台 Mac")
    var symbol: String { isLocal ? "laptopcomputer" : "server.rack" }
}
struct Workspace: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var path: String
    var hostID: String = "local"
    var branch: String? = nil
    var split: Bool = false
    var selectedRunID: String? = nil
    var secondaryRunID: String? = nil
    var archived: Bool? = nil
    var syncPending: Bool? = nil
    // Legacy-compatible pane order; terminalLayout additionally preserves local split directions and proportions.
    var paneRunIDs: [String]? = nil
    var terminalLayout: TerminalLayout? = nil
    var terminalGroups: [TerminalTabGroup]? = nil

}
struct TerminalDrag: Codable {
    let workspaceID: String
    let runID: String
    var tabID: String? = nil
}
struct Agent: Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    static let all: [Agent] = [
        Agent(id: "pi", name: "Pi", symbol: "sparkle"),
        Agent(id: "codex", name: "Codex CLI", symbol: "chevron.left.forwardslash.chevron.right"),
        Agent(id: "claude", name: "Claude Code", symbol: "asterisk"),
    ]
}
struct Run: Codable, Identifiable, Hashable {
    var id: String
    var taskId: String
    var workspaceId: String
    var title: String
    var agent: String
    var prompt: String
    var cwd: String
    var session: String
    var status: String
    var createdAt: Double
    var exitCode: Int?
    var error: String?
    var baseCommit: String?
    var archived: Bool = false
    var active: Bool { ["queued", "starting", "running", "direct"].contains(status) }
    var label: String {
        switch status {
        case "queued": return "排队中"
        case "starting": return "启动中"
        case "running": return "运行中"
        case "direct": return "直接 SSH"
        case "cancelled": return "已停止"
        case "exited": return exitCode == 0 ? "已退出 · 待检查" : "退出码 \(exitCode.map(String.init) ?? "—")"
        case "lost": return "会话已中断"
        default: return "启动失败"
        }
    }
    var symbol: String { Agent.all.first { $0.id == agent }?.symbol ?? "terminal" }
    var agentName: String { Agent.all.first { $0.id == agent }?.name ?? "Shell" }
}
struct AgentHealth: Codable {
    var id: String
    var path: String?
}
struct Health: Codable {
    var `protocol`: Int
    var version: String
    var platform: String
    var arch: String
    var tmux: String
    var socket: String
    var root: String
    var agents: [AgentHealth]
    var concurrency: Int
    var capabilities: [String]? = nil
    var termInfo: String? = nil
    var supportsWorkspaces: Bool { capabilities?.contains("workspace-registry") == true }
}
struct RunList: Codable {
    var runs: [Run]
    var concurrency: Int
    var workspaces: [ServerWorkspace]? = nil
}
struct ServerWorkspace: Codable, Equatable {
    var id: String
    var name: String
    var path: String
    var branch: String?
    var split: Bool = false
    var selectedRunId: String?
    var secondaryRunId: String?
    var archived: Bool = false
    var paneRunIds: [String]? = nil
    init(_ w: Workspace) {
        id = w.id
        name = w.name
        path = w.path
        branch = w.branch
        split = w.split
        selectedRunId = w.selectedRunID
        secondaryRunId = w.secondaryRunID
        archived = w.archived == true
        paneRunIds = w.paneRunIDs
    }
    func workspace(hostID: String) -> Workspace {
        Workspace(
            id: id, name: name, path: path, hostID: hostID, branch: branch, split: split,
            selectedRunID: selectedRunId, secondaryRunID: secondaryRunId, archived: archived, syncPending: false,
            paneRunIDs: paneRunIds)
    }
}
// Shared by the application and headless recovery tests. Never turn reconnect into startRun.
enum WorkspaceRecovery {
    static func merge(local: [Workspace], hostID: String, snapshot: RunList) -> [Workspace] {
        var result = local
        let records = snapshot.workspaces ?? []
        for record in records {
            // This Mac's saved layout and offline edits win. Server records recover missing workspaces.
            if !result.contains(where: { $0.hostID == hostID && $0.id == record.id }) {
                result.append(record.workspace(hostID: hostID))
            }
        }
        // Older runtimes can still recover the grouping of all non-archived sessions.
        for run in snapshot.runs.filter({ !$0.archived }) {
            if !result.contains(where: { $0.hostID == hostID && $0.id == run.workspaceId }) {
                result.append(
                    Workspace(
                        id: run.workspaceId, name: URL(fileURLWithPath: run.cwd).lastPathComponent,
                        path: run.cwd, hostID: hostID, selectedRunID: run.id, syncPending: true))
            }
        }
        if snapshot.workspaces != nil {
            for i in result.indices where result[i].hostID == hostID {
                if !records.contains(where: { $0.id == result[i].id }) { result[i].syncPending = true }
            }
        }
        return result
    }
}
struct AttachmentRetryPolicy {
    private var failures: [String: Int] = [:]
    private var nextAttempt: [String: Date] = [:]
    mutating func shouldRetry(id: String, live: Bool, ended: Bool, now: Date = Date()) -> Bool {
        guard live && ended else { return false }
        guard now >= (nextAttempt[id] ?? .distantPast) else { return false }
        let count = failures[id, default: 0]
        nextAttempt[id] = now.addingTimeInterval(min(30, 3 * pow(2, Double(min(count, 4)))))
        failures[id] = count + 1
        return true
    }
    mutating func reset(_ id: String) {
        failures[id] = nil
        nextAttempt[id] = nil
    }
}
struct WorktreeResult: Codable {
    var path: String
    var branch: String
    var base: String
}
struct Transcript: Codable { var text: String }
struct SavedState: Codable {
    var hosts: [Host]
    var workspaces: [Workspace]
    var selectedWorkspaceID: String?
    var fontSize: Double = 13
    var appearance: String = "system"
    var showInspector: Bool = true
    var runCache: [String: [Run]]? = nil
    var terminalShortcuts: [String: TerminalShortcut]? = nil
    var terminalTitles: [String: [String: String]]? = nil
}
struct TerminalRenameTarget: Identifiable {
    let hostID: String
    let run: Run
    var id: String { "\(hostID):\(run.id)" }
}
struct AshError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func validSSHAddress(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("-"), value.count < 256,
        value.unicodeScalars.allSatisfy({
            CharacterSet(
                charactersIn:
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-:[]"
            ).contains($0)
        })
    else { return false }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), let destination = parts.last else { return false }
    if parts.count == 2, parts[0].contains(where: { ":[]".contains($0) }) { return false }
    let host = String(destination)
    guard !host.hasPrefix("-"), host != ".", host != ".." else { return false }
    if host.contains(":") || host.contains("[") || host.contains("]") {
        let address = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        var binary = in6_addr()
        return inet_pton(AF_INET6, address, &binary) == 1
    }
    return true
}

struct AgentTaskSnapshot: Decodable { var sessions: [TerminalAgentSession] }
struct TerminalAgentSession: Decodable, Identifiable {
    var id: String
    var agent: String
    var tasks: [TerminalAgentTask]
    var notice: String?
    var name: String { Agent.all.first { $0.id == agent }?.name ?? agent }
    var completedCount: Int { tasks.filter { $0.status == "completed" }.count }
}
struct TerminalAgentTask: Decodable, Identifiable {
    var id: String
    var title: String
    var status: String
    var detail: String?
    var label: String {
        switch status {
        case "pending": return "待办"
        case "in_progress": return "进行中"
        case "completed": return "已完成"
        default: return "状态未知"
        }
    }
    var symbol: String {
        switch status {
        case "pending": return "circle"
        case "in_progress": return "circle.lefthalf.filled"
        case "completed": return "checkmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
}
