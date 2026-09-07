import AppKit
import SwiftUI

@MainActor final class AppStore: ObservableObject {
    let checklist: WorkspaceChecklistStore
    @Published var hosts: [Host] = [.local]
    @Published var workspaces: [Workspace] = []
    @Published var selectedWorkspaceID: String?
    @Published var runs: [String: [Run]] = [:]
    @Published var health: [String: Health] = [:]
    @Published var connectionErrors: [String: String] = [:]
    @Published var runtimeSetup: [String: String] = [:]
    @Published var runtimeUpdateErrors: [String: String] = [:]
    @Published var workspaceErrors: [String: String] = [:]
    @Published var error: String?
    @Published var busy = false
    @Published var showNewWorkspace = false
    @Published var showNewTask = false
    @Published var showHosts = false
    @Published var showSettings = false
    @Published var showInspector = true
    @Published var fontSize: Double = 13
    @Published var appearance = "system"
    @Published var terminalShortcuts: [String: TerminalShortcut] = [:]
    @Published var terminalTitles: [String: [String: String]] = [:]
    @Published var terminalRenameTarget: TerminalRenameTarget?
    @Published var closingRunIDs: Set<String> = []
    @Published var terminalGeneration: [String: Int] = [:]
    @Published var terminalSearchRequest = UUID()
    private let client = RuntimeClient()
    @Published var connectingHosts: Set<String> = []
    @Published var hostLastConnected: [String: Date] = [:]
    let hostConnector: any HostConnecting
    var hostConnectionTasks: [String: (token: UUID, force: Bool, installRuntime: Bool, task: Task<Void, Never>)] = [:]
    var hostRetry = HostRetryPolicy()
    private var synchronizedInFlight: Set<String> = []
    private var persistedWorkspaces: [WorkspaceKey: ServerWorkspace] = [:]
    private var attachmentRetry = AttachmentRetryPolicy()
    private let stateFile: JSONFileStore<SavedState>
    var selectedWorkspace: Workspace? { workspaces.first { $0.id == selectedWorkspaceID } }
    var selectedHost: Host { host(for: selectedWorkspace?.hostID ?? "local") }
    var workspaceRuns: [Run] {
        guard let w = selectedWorkspace else { return [] }
        return availableRuns(in: w)
    }
    private func availableRuns(in workspace: Workspace) -> [Run] {
        (runs[workspace.hostID] ?? []).filter { $0.workspaceId == workspace.id && !$0.archived }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var selectedRun: Run? {
        guard let w = selectedWorkspace else { return nil }
        let available = workspaceRuns
        let visible = w.visibleRunIDs(available: available.map(\.id))
        return available.first { $0.id == w.selectedRunID && visible.contains($0.id) }
            ?? available.first { $0.id == visible.first }
    }
    var activeCount: Int { runs.values.flatMap { $0 }.filter { $0.active && $0.agent != "shell" }.count }
    var visibleRuns: [Run] {
        let available = workspaceRuns
        return (selectedWorkspace?.visibleRunIDs(available: available.map(\.id)) ?? []).compactMap { id in
            available.first { $0.id == id }
        }
    }
    init(directory: URL? = nil, hostConnector: any HostConnecting = HostConnectionService()) {
        self.hostConnector = hostConnector
        let root = directory ?? AppPaths.dataDirectory
        checklist = WorkspaceChecklistStore(directory: root)
        stateFile = JSONFileStore(url: root.appendingPathComponent("state.json"))
        do {
            if let saved = try stateFile.load() {
                hosts = saved.hosts
                workspaces = saved.workspaces
                selectedWorkspaceID = saved.selectedWorkspaceID
                runs = saved.runCache ?? [:]
                fontSize = saved.fontSize
                appearance = saved.appearance
                showInspector = saved.showInspector
                terminalShortcuts = TerminalShortcut.migratePreferences(saved.terminalShortcuts ?? [:])
                terminalTitles = saved.terminalTitles ?? [:]
            }
        } catch { self.error = "无法读取已保存的工作区；原文件已保留。\n\(error.localizedDescription)" }
        if !hosts.contains(where: { $0.isLocal }) { hosts.insert(.local, at: 0) }
        if workspaces.isEmpty, let initial = ProcessInfo.processInfo.environment["ASH_INITIAL_WORKSPACE"] {
            let w = Workspace(name: URL(fileURLWithPath: initial).lastPathComponent, path: initial)
            workspaces = [w]
            selectedWorkspaceID = w.id
        }
        persistedWorkspaces = Dictionary(
            workspaces.map { (WorkspaceKey($0), ServerWorkspace($0)) }, uniquingKeysWith: { _, latest in latest })
    }
    func host(for id: String) -> Host { hosts.first { $0.id == id } ?? .local }
    func save() {
        for i in workspaces.indices
        where persistedWorkspaces[WorkspaceKey(workspaces[i])] != ServerWorkspace(workspaces[i]) {
            workspaces[i].syncPending = true
        }
        persistState()
    }
    @discardableResult
    func persistState() -> Bool {
        do {
            let state = SavedState(
                hosts: hosts, workspaces: workspaces, selectedWorkspaceID: selectedWorkspaceID, fontSize: fontSize,
                appearance: appearance, showInspector: showInspector,
                runCache: runs.mapValues { $0.filter { $0.status != "direct" } }, terminalShortcuts: terminalShortcuts,
                terminalTitles: terminalTitles)
            try stateFile.save(state)
            persistedWorkspaces = Dictionary(
                workspaces.map { (WorkspaceKey($0), ServerWorkspace($0)) }, uniquingKeysWith: { _, latest in latest })
            return true
        } catch {
            self.error = "无法保存工作区：\(error.localizedDescription)"
            return false
        }
    }
    func selectWorkspace(_ id: String) {
        selectedWorkspaceID = id
        save()
    }
    func selectRun(_ run: Run) {
        if let i = workspaces.firstIndex(where: { $0.id == run.workspaceId }) {
            let available = availableRuns(in: workspaces[i]).map(\.id)
            workspaces[i].selectTerminal(run.id, available: available)
            save()
        }
    }
    func shortcut(for action: TerminalShortcutAction) -> TerminalShortcut {
        if let index = action.index {
            return (terminalShortcuts["numbered"] ?? .init(key: "1")).withKey(String(index + 1))
        }
        return terminalShortcuts[action.rawValue] ?? action.defaultShortcut
    }
    func terminalTitle(_ run: Run, hostID: String) -> String {
        terminalTitles[hostID]?[run.id] ?? run.title
    }
    func beginRenamingTerminal(_ run: Run) {
        terminalRenameTarget = TerminalRenameTarget(hostID: selectedHost.id, run: run)
    }
    static func terminalTitleError(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "请输入标签名称。" }
        if name.count > 120 { return "标签名称最多 120 个字符。" }
        if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "标签名称不能包含换行或控制字符。"
        }
        return nil
    }
    @discardableResult
    func renameTerminal(_ run: Run, hostID: String, name value: String) -> Bool {
        guard Self.terminalTitleError(value) == nil else { return false }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = terminalTitles
        // Display names are client preferences, so offline refreshes and older SSH runtimes cannot overwrite them.
        terminalTitles[hostID, default: [:]][run.id] = name == run.title ? nil : name
        if terminalTitles[hostID]?.isEmpty == true { terminalTitles[hostID] = nil }
        guard persistState() else {
            terminalTitles = previous
            return false
        }
        return true
    }
    func setShortcut(_ shortcut: TerminalShortcut, for action: TerminalShortcutAction) -> String? {
        guard shortcut.isValid else { return "请使用 ⌘ 或 ⌃ 搭配一个按键。" }
        if action.index != nil {
            guard (1...9).contains(Int(shortcut.key) ?? 0) else {
                return "请按住 ⌘ 或 ⌃，搭配任意数字 1–9；整组数字会统一更新。"
            }
            for other in [TerminalShortcutAction.previous, .next] {
                if (1...9).contains(where: { shortcut.withKey(String($0)) == self.shortcut(for: other) }) {
                    return "这组按键与「\(other.title)」冲突，请换一组修饰键。"
                }
            }
            terminalShortcuts["numbered"] = shortcut.withKey("1")
            save()
            return nil
        }
        if let title = shortcut.reservedAction { return "\(shortcut.label) 已用于「\(title)」。请换一组按键。" }
        if let other = TerminalShortcutAction.allCases.first(where: {
            $0 != action && self.shortcut(for: $0) == shortcut
        }) {
            return "\(shortcut.label) 已用于「\(other.settingsTitle)」。请换一组按键。"
        }
        terminalShortcuts[action.rawValue] = shortcut
        save()
        return nil
    }
    func resetTerminalShortcuts() {
        terminalShortcuts = [:]
        save()
    }
    func canSelectTerminal(_ action: TerminalShortcutAction) -> Bool {
        guard !showSettings, !showNewWorkspace, !showNewTask, !showHosts,
            terminalRenameTarget == nil, error == nil
        else { return false }
        return action.index.map { workspaceTabs.indices.contains($0) } ?? (workspaceTabs.count > 1)
    }
    func selectTerminal(_ action: TerminalShortcutAction) {
        guard canSelectTerminal(action) else { return }
        let tabs = workspaceTabs
        let current = tabs.firstIndex { $0.id == selectedTerminalTab?.id } ?? 0
        let index = action.index ?? ((current + (action == .previous ? -1 : 1) + tabs.count) % tabs.count)
        selectTerminalTab(tabs[index])
    }

    var canCloseSelectedTerminal: Bool {
        guard !showSettings, !showNewWorkspace, !showNewTask, !showHosts,
            terminalRenameTarget == nil, error == nil,
            NSApp?.modalWindow == nil, NSApp?.keyWindow?.sheetParent == nil,
            NSApp?.mainWindow?.attachedSheet == nil,
            let run = selectedRun
        else { return false }
        return !closingRunIDs.contains(run.id)
            && !(selectedTerminalTab?.runIDs.contains(where: { closingRunIDs.contains($0) }) ?? false)
    }

    /// Stop first, then archive. A failed stop must never make a live session disappear.
    func closeTerminal(_ run: Run) async {
        guard let workspace = workspaces.first(where: { $0.id == run.workspaceId }),
            closingRunIDs.insert(run.id).inserted
        else { return }
        defer { closingRunIDs.remove(run.id) }
        let host = host(for: workspace.hostID)
        do {
            if run.status != "direct" {
                // The runtime checks current status; the displayed snapshot may be stale.
                let stopped: Run = try await client.call(host, "cancel", ["id": run.id])
                if let i = runs[host.id]?.firstIndex(where: { $0.id == run.id }) { runs[host.id]?[i] = stopped }
                let _: Run = try await client.call(host, "archive", ["id": run.id])
            }
            guard let i = workspaces.firstIndex(where: { $0.id == workspace.id && $0.hostID == host.id }) else {
                return
            }
            let available = availableRuns(in: workspaces[i]).map(\.id)
            workspaces[i].removeTerminal(run.id, available: available)
            runs[host.id]?.removeAll { $0.id == run.id }
            TerminalRegistry.shared.close(run.id)
            save()
            if selectedWorkspaceID == workspace.id, let focusedID = workspaces[i].selectedRunID {
                DispatchQueue.main.async { TerminalRegistry.shared.focus(id: focusedID) }
            }
        } catch {
            self.error = "无法关闭「\(terminalTitle(run, hostID: host.id))」：\(error.localizedDescription)"
        }
    }
    func addWorkspace(name: String, path: String, hostID: String) {
        let w = Workspace(name: name, path: path, hostID: hostID)
        workspaces.append(w)
        selectedWorkspaceID = w.id
        save()
        Task { await refresh() }
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "添加工作区"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addWorkspace(name: url.lastPathComponent, path: url.path, hostID: "local")
    }
    func applySnapshot(_ list: RunList, health h: Health, hostID id: String) {
        // Direct SSH transports remain client-owned when managed mode is enabled.
        let direct = (runs[id] ?? []).filter { $0.status == "direct" }
        let merged = list.runs + direct.filter { run in !list.runs.contains { $0.id == run.id } }
        let snapshotChanged = runs[id] != merged
        health[id] = h
        runs[id] = merged
        connectionErrors[id] = nil
        let recovered = WorkspaceRecovery.merge(local: workspaces, hostID: id, snapshot: list)
        if recovered != workspaces || snapshotChanged {
            workspaces = recovered
            persistState()
        }
        if selectedWorkspace == nil, let first = workspaces.first(where: { $0.archived != true }) {
            selectedWorkspaceID = first.id
            persistState()
        }
        if h.supportsWorkspaces {
            for w in workspaces.filter({ $0.hostID == id && $0.syncPending != false }) {
                let key = id + ":" + w.id
                if synchronizedInFlight.insert(key).inserted {
                    Task {
                        await self.synchronizeWorkspace(w, host: self.host(for: id))
                        self.synchronizedInFlight.remove(key)
                    }
                }
            }
        }
        for run in list.runs where run.status == "running" && !run.archived {
            let ended = TerminalRegistry.shared.hasEnded(run.id)
            if attachmentRetry.shouldRetry(id: run.id, live: true, ended: ended) {
                reconnect(run, automatic: true)
            } else if TerminalRegistry.shared.isStable(run.id) {
                attachmentRetry.reset(run.id)
            }
        }
    }
    private func prepareHost(_ host: Host) async throws -> Health {
        let result = try await HostConnectionService.prepare(host) { [weak self] message in
            guard let self, self.hosts.contains(where: { $0.hasSameConnection(as: host) }) else { return }
            self.runtimeSetup[host.id] = message
        }
        runtimeUpdateErrors[host.id] = result.updateError
        runtimeSetup[host.id] = result.updateError == nil ? "已就绪" : "更新未完成 · 继续使用当前版本"
        guard let health = result.health else { throw AshError(message: "运行程序没有返回主机信息。") }
        return health
    }
    func startShell() async {
        guard let w = selectedWorkspace else {
            showNewWorkspace = true
            return
        }
        let h = host(for: w.hostID)
        if !h.managed && !h.isLocal {
            let id = UUID().uuidString
            let r = Run(
                id: id, taskId: id, workspaceId: w.id, title: h.name, agent: "shell", prompt: "", cwd: w.path,
                session: "", status: "direct", createdAt: Date().timeIntervalSince1970)
            runs[h.id, default: []].append(r)
            selectRun(r)
            return
        }
        await start(agent: "shell", prompt: "", title: "终端", isolated: false)
    }
    func start(agent: String, prompt: String, title: String, isolated: Bool, retry: Run? = nil) async {
        guard var w = selectedWorkspace else { return }
        let h = host(for: w.hostID)
        busy = true
        defer { busy = false }
        do {
            if !h.isLocal && !h.managed { throw AshError(message: "Agent 任务需要托管主机。请在主机设置中启用并安装 ash-runtime。") }
            health[h.id] = try await prepareHost(h)
            if isolated {
                let id = UUID().uuidString
                let result: WorktreeResult = try await client.call(h, "worktree", ["cwd": w.path, "id": id])
                w = Workspace(id: id, name: title, path: result.path, hostID: h.id, branch: result.branch)
                workspaces.append(w)
                selectedWorkspaceID = id
                save()
            }
            if health[h.id]?.supportsWorkspaces == true {
                let record = ServerWorkspace(w)
                let _: ServerWorkspace = try await client.call(
                    h, "workspace", ["workspace": try workspacePayload(record)])
            }
            let id = UUID().uuidString
            let r: Run = try await client.call(
                h, "start",
                [
                    "id": id, "taskId": retry?.taskId ?? id, "workspaceId": w.id, "cwd": w.path, "agent": agent,
                    "prompt": prompt, "title": title,
                ])
            runs[h.id, default: []].append(r)
            selectRun(r)
            if r.status == "failedToStart" { error = r.error }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ run: Run) async {
        let h = host(for: workspaces.first { $0.id == run.workspaceId }?.hostID ?? "local")
        if run.status == "direct" {
            TerminalRegistry.shared.close(run.id)
            runs[h.id]?.removeAll { $0.id == run.id }
            return
        }
        do {
            let _: Run = try await client.call(h, "cancel", ["id": run.id])
            TerminalRegistry.shared.close(run.id)
            await refresh()
        } catch { self.error = "尚未确认停止：\(error.localizedDescription)" }
    }
    func archive(_ run: Run) async {
        let h = host(for: workspaces.first { $0.id == run.workspaceId }?.hostID ?? "local")
        do {
            let _: Run = try await client.call(h, "archive", ["id": run.id])
            TerminalRegistry.shared.close(run.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func workspacePayload(_ record: ServerWorkspace) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
    }
    private func synchronizeWorkspace(_ w: Workspace, host: Host) async {
        let record = ServerWorkspace(w)
        do {
            let _: ServerWorkspace = try await client.call(
                host, "workspace", ["workspace": try workspacePayload(record)])
            if let i = workspaces.firstIndex(where: { $0.id == w.id && $0.hostID == host.id }),
                ServerWorkspace(workspaces[i]) == record
            {
                workspaces[i].syncPending = false
                workspaceErrors[w.id] = nil
                persistState()
            }
        } catch { workspaceErrors[w.id] = "工作区信息尚未同步到主机：\(error.localizedDescription)" }
    }
    func reconnect(_ run: Run, automatic: Bool = false) {
        if !automatic { attachmentRetry.reset(run.id) }
        TerminalRegistry.shared.close(run.id)
        terminalGeneration[run.id, default: 0] += 1
    }
    func export(_ run: Run) async {
        do {
            let transcript: Transcript = try await client.call(selectedHost, "transcript", ["id": run.id])
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Ash-\(run.agent)-\(run.id.prefix(8)).txt"
            if panel.runModal() == .OK, let url = panel.url {
                try transcript.text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch { self.error = error.localizedDescription }
    }
    func setConcurrency(_ n: Int, host: Host) async {
        do {
            let _: [String: Int] = try await client.call(host, "settings", ["concurrency": n])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
}

private struct WorkspaceKey: Hashable {
    let hostID: String
    let workspaceID: String
    init(_ workspace: Workspace) {
        hostID = workspace.hostID
        workspaceID = workspace.id
    }
}
