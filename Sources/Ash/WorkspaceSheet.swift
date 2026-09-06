import AppKit
import SwiftUI

struct WorkspaceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var directories = DirectorySuggestions()
    @State private var name = ""
    @State private var automaticName = ""
    @State private var path = ""
    @State private var hostID = "local"
    @State private var browsing = true
    @State private var highlighted: String?
    @State private var authentication: Host?
    @FocusState private var pathFocused: Bool

    private var host: Host { store.host(for: hostID) }
    private var query: DirectoryQuery { DirectoryQuery(host: host, input: path) }
    private var listing: DirectoryListing? { directories.query == query ? directories.listing : nil }
    private var validPath: String? { path.isEmpty ? nil : listing?.resolvedPath }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(title: "添加工作区", symbol: "folder.badge.plus")
            Form {
                Picker("执行主机", selection: $hostID) { ForEach(store.hosts) { Text($0.name).tag($0.id) } }
                TextField("工作区名称", text: $name, prompt: Text("随目录自动填写"))
                HStack {
                    TextField("目录路径", text: $path, prompt: Text("输入路径或选择下方目录"))
                        .focused($pathFocused).accessibilityLabel("工作区目录路径")
                        .onKeyPress(.downArrow) {
                            moveHighlight(1)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveHighlight(-1)
                            return .handled
                        }
                        .onKeyPress(.return) {
                            if let highlighted {
                                selectDirectory(highlighted)
                            } else {
                                browsing = false
                                pathFocused = false
                            }
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            guard let highlighted else { return .ignored }
                            selectDirectory(highlighted)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            browsing = false
                            pathFocused = false
                            return .handled
                        }
                    if host.isLocal { Button("选择…") { choose() } }
                }
            }.formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
            if browsing {
                directoryBrowser
            } else {
                HStack {
                    if directories.loading {
                        ProgressView().controlSize(.small)
                    } else if validPath != nil {
                        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    }
                    Text(validPath != nil ? "目录已确认" : directories.error ?? "请选择目录").font(.caption).foregroundStyle(
                        .secondary
                    )
                    .lineLimit(2)
                    Spacer()
                    Button("浏览目录") {
                        browsing = true
                        pathFocused = true
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }
            if store.workspaces.contains(where: { $0.archived == true }) {
                Menu("恢复隐藏的工作区") {
                    ForEach(store.workspaces.filter { $0.archived == true }) { workspace in
                        Button(workspace.name) {
                            if let index = store.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                                store.workspaces[index].archived = false
                                store.selectedWorkspaceID = workspace.id
                                store.save()
                                dismiss()
                            }
                        }
                    }
                }
            }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("添加工作区") {
                    guard let validPath else { return }
                    store.addWorkspace(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), path: validPath, hostID: hostID)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validPath == nil)
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 570, height: 530).tint(ashAccent)
            .task(id: query) { await directories.load(query) }
            .onAppear {
                hostID = store.selectedHost.id
                pathFocused = true
            }
            .onChange(of: hostID) { _, _ in
                path = ""
                highlighted = nil
                browsing = true
            }
            .onChange(of: path) { _, _ in highlighted = nil }
            .onChange(of: pathFocused) { _, focused in if focused { browsing = true } }
            .onChange(of: listing?.resolvedPath) { _, resolved in
                if !path.isEmpty, let resolved { updateName(resolved) }
            }
            .onChange(of: store.hosts.map(\.id)) { _, ids in if !ids.contains(hostID) { hostID = "local" } }
            .sheet(
                item: $authentication,
                onDismiss: { Task { await directories.load(query, debounce: false) } },
                content: { AuthenticationSheet(host: $0) })
    }

    private var directoryBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: host.symbol).foregroundStyle(.secondary)
                Text(listing?.directory ?? (path.isEmpty ? "主目录" : path))
                    .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if let listing {
                    Button {
                        selectDirectory((listing.directory as NSString).deletingLastPathComponent)
                    } label: {
                        Image(systemName: "arrow.up")
                    }.disabled(listing.directory == "/").help("上一级目录").accessibilityLabel("上一级目录")
                    Button("使用此目录") { selectDirectory(listing.directory, keepBrowsing: false) }
                }
            }.buttonStyle(.plain).padding(10)
            Divider()
            if directories.loading || directories.query != query {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = directories.error {
                VStack(spacing: 12) {
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .multilineTextAlignment(.center).lineLimit(4)
                    HStack {
                        Button("重试") { Task { await directories.load(query, debounce: false) } }
                        if !host.isLocal { Button("SSH 认证") { authentication = host } }
                    }
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listing {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(listing.entries) { entry in
                                Button {
                                    selectDirectory(entry.path)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder").foregroundStyle(ashAccent)
                                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(
                                            .tertiary)
                                    }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 32)
                                        .background(highlighted == entry.id ? ashAccent.opacity(0.12) : Color.clear)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).id(entry.id).help(entry.path)
                            }
                            if listing.entries.isEmpty {
                                Text(listing.resolvedPath == nil ? "没有匹配的目录" : "没有子目录")
                                    .font(.caption).foregroundStyle(.secondary).padding(24)
                            }
                            if listing.truncated {
                                Text("仅显示前 200 项，继续输入可缩小范围").font(.caption2).foregroundStyle(.secondary).padding(10)
                            }
                        }
                    }.onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }.background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.4)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moveHighlight(_ offset: Int) {
        browsing = true
        guard let entries = listing?.entries, !entries.isEmpty else { return }
        let index = highlighted.flatMap { id in entries.firstIndex { $0.id == id } }
        let next = index.map { min(entries.count - 1, max(0, $0 + offset)) } ?? (offset > 0 ? 0 : entries.count - 1)
        highlighted = entries[next].id
    }

    private func updateName(_ selected: String) {
        guard name.isEmpty || name == automaticName else { return }
        automaticName = URL(fileURLWithPath: selected).lastPathComponent
        if automaticName.isEmpty { automaticName = host.name }
        name = automaticName
    }

    private func selectDirectory(_ selected: String, keepBrowsing: Bool = true) {
        path = keepBrowsing && selected != "/" ? selected + "/" : selected
        updateName(selected)
        highlighted = nil
        browsing = keepBrowsing
        pathFocused = keepBrowsing
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if let validPath { panel.directoryURL = URL(fileURLWithPath: validPath) }
        if panel.runModal() == .OK, let url = panel.url { selectDirectory(url.path, keepBrowsing: false) }
    }
}
