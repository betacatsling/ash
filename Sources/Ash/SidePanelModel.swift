import Foundation
import SwiftUI

struct PanelContext: Equatable {
    let host: Host
    let workspaceID: String
    let cwd: String
    let base: String?
    var key: String { "\(host.id):\(workspaceID):\(cwd):\(base ?? "HEAD")" }
    var arguments: [String: Any] {
        var values: [String: Any] = ["cwd": cwd]
        if let base { values["base"] = base }
        return values
    }
    func call<T: Decodable>(_ action: String, path: String? = nil) async throws -> T {
        guard host.isLocal || host.managed else { throw AshError(message: "请先为这台远程主机启用托管模式，以浏览文件和 Git 差异。") }
        var values = arguments
        if let path { values["path"] = path }
        do { return try await RuntimeClient().call(host, action, values) } catch {
            if error.localizedDescription.contains("Unknown action") {
                throw AshError(message: "请更新这台主机的运行程序，以使用文件浏览和 Git 差异。")
            }
            throw error
        }
    }
}

enum PanelTab: Hashable, Identifiable {
    case tasks, sessionInfo, files
    case file(String)
    case review
    case web(UUID, String)
    var id: String {
        switch self {
        case .tasks: return "tasks"
        case .sessionInfo: return "sessionInfo"
        case .files: return "files"
        case .file: return "files"
        case .review: return "review"
        case .web(let id, _): return id.uuidString
        }
    }
    var title: String {
        switch self {
        case .tasks: return "任务清单"
        case .sessionInfo: return "会话信息"
        case .files: return "打开文件"
        case .file(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .review: return "Git Diff"
        case .web(_, let address): return address
        }
    }
    var symbol: String {
        switch self {
        case .tasks: return "checklist"
        case .sessionInfo: return "info.circle"
        case .files: return "folder"
        case .file(let path): return FileEntry.symbol(for: path)
        case .review: return "arrow.triangle.branch"
        case .web: return "globe"
        }
    }
    var isFile: Bool {
        if case .files = self { return true }
        if case .file = self { return true }
        return false
    }
    var path: String? {
        if case .file(let path) = self { return path }
        return nil
    }
}

@MainActor final class SidePanelSession: ObservableObject {
    @Published var tabs: [PanelTab] = [.tasks]
    @Published var selection: PanelTab = .tasks
    let tree = FileTreeModel()
    var browsers: [String: PanelBrowserModel] = [:]
    func open(_ tab: PanelTab) {
        // The file browser owns one stable tab; choosing a file replaces its document.
        if tab.isFile, let index = tabs.firstIndex(where: { $0.isFile }) {
            if tab.path != nil { tabs[index] = tab }
            selection = tabs[index]
            return
        }
        if !tabs.contains(tab) { tabs.append(tab) }
        selection = tab
    }
    func close(_ tab: PanelTab) {
        let index = tabs.firstIndex(of: tab) ?? 0
        browsers.removeValue(forKey: tab.id)?.stop()
        tabs.removeAll { $0 == tab }
        if tabs.isEmpty { tabs = [.files] }
        if selection == tab { selection = tabs[min(index, tabs.count - 1)] }
    }
    func browser(for tab: PanelTab) -> PanelBrowserModel {
        if let model = browsers[tab.id] { return model }
        let model = PanelBrowserModel()
        browsers[tab.id] = model
        return model
    }
}

@MainActor final class SidePanelStore: ObservableObject {
    private var sessions: [String: SidePanelSession] = [:]
    func session(for context: PanelContext) -> SidePanelSession {
        if let session = sessions[context.key] { return session }
        let session = SidePanelSession()
        sessions[context.key] = session
        return session
    }
}

struct FileListing: Decodable {
    let entries: [FileEntry]
    let truncated: Bool
}
struct FileEntry: Decodable, Identifiable {
    let name: String
    let path: String
    let directory: Bool
    let size: UInt64
    var id: String { path }
    static func symbol(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "txt": return "doc.text"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}
struct FilePreview: Decodable {
    let text: String
    let binary: Bool
    let truncated: Bool
    let size: UInt64
}
struct ReviewSnapshot: Decodable {
    let root: String
    let branch: String
    let files: [ReviewFile]
}
struct ReviewFile: Decodable, Identifiable {
    let path: String
    let status: String
    var id: String { path }
}
struct ReviewDiff: Decodable {
    let text: String
    let truncated: Bool
}

@MainActor final class FileTreeModel: ObservableObject {
    @Published var children: [String: [FileEntry]] = [:]
    @Published var expanded: Set<String> = []
    @Published var errors: [String: String] = [:]
    @Published var loading: Set<String> = []
    @Published var truncated: Set<String> = []
    @Published var filter = ""
    func load(_ path: String = "", context: PanelContext) async {
        guard !loading.contains(path) else { return }
        loading.insert(path)
        errors[path] = nil
        defer { loading.remove(path) }
        do {
            let listing: FileListing = try await context.call("browseFiles", path: path)
            children[path] = listing.entries
            if listing.truncated { truncated.insert(path) } else { truncated.remove(path) }
        } catch { errors[path] = error.localizedDescription }
    }
    func toggle(_ entry: FileEntry, context: PanelContext) async {
        if expanded.contains(entry.path) {
            expanded.remove(entry.path)
        } else {
            expanded.insert(entry.path)
            if children[entry.path] == nil { await load(entry.path, context: context) }
        }
    }
    func refresh(context: PanelContext) async {
        await load(context: context)
        for path in expanded.sorted() { await load(path, context: context) }
    }
    // Keep directories visible while filtering so an unopened directory can be explored.
    func visible(_ path: String) -> [FileEntry] {
        (children[path] ?? []).filter {
            filter.isEmpty || $0.directory || $0.name.localizedCaseInsensitiveContains(filter)
        }
    }
}

enum PreviewAddress {
    static func url(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(value), (1...65535).contains(port) { return URL(string: "http://127.0.0.1:\(port)")! }
        let address = value.contains("://") ? value : "http://\(value)"
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
            url.port.map({ (1...65535).contains($0) }) ?? true
        else {
            throw AshError(message: "请输入 1–65535 的端口号，或完整的 HTTP / HTTPS 地址。")
        }
        if Int(value) != nil { throw AshError(message: "端口号应在 1–65535 之间。") }
        return url
    }
    static func isLoopback(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "")
    }
}
