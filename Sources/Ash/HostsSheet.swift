import SwiftUI

private enum HostSheetRoute: Identifiable {
    case add
    case edit(Host)
    case authenticate(Host)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let host): return "edit-\(host.id)"
        case .authenticate(let host): return "auth-\(host.id)"
        }
    }
}

struct HostsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var expanded: String?
    @State private var route: HostSheetRoute?
    @State private var removing: Host?
    @State private var actionError: String?

    private var filtered: [Host] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.hosts.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.address.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                SheetHeading(
                    title: "主机",
                    subtitle: "这台 Mac · \(store.hosts.filter { !$0.isLocal }.count) 台远端主机",
                    symbol: "network")
                Spacer()
                Button {
                    route = .add
                } label: {
                    Label("添加主机", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding(24)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索名称或地址", text: $search).textFieldStyle(.plain).accessibilityLabel("搜索主机")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("清除主机搜索")
                }
            }.padding(10).ashField()
                .padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { host in
                            VStack(spacing: 0) {
                                hostRow(host)
                                if expanded == host.id {
                                    HostDetailsView(
                                        host: host, edit: { route = .edit(host) },
                                        authenticate: { route = .authenticate(host) }, remove: { removing = host }
                                    )
                                    .padding(.horizontal, 24).padding(.bottom, 20)
                                }
                            }.background(expanded == host.id ? ashAccent.opacity(0.035) : Color.clear).id(host.id)
                            Divider().padding(.leading, 24)
                        }
                        if filtered.isEmpty {
                            PanelPlaceholder(title: "没有匹配的主机", symbol: "magnifyingglass", detail: "试试其他名称或地址。")
                                .frame(height: 200)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: expanded) { _, id in
                        if let id { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) } }
                    }
                    .onChange(of: store.connectionErrors[expanded ?? ""]) { _, _ in
                        if let expanded { DispatchQueue.main.async { proxy.scrollTo(expanded, anchor: .top) } }
                    }
            }
            Divider()
            HStack {
                Text("选择主机展开设置").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.large)
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: 620, height: 560).background(AshStyle.canvas).tint(ashAccent)
            .sheet(item: $route) { route in
                switch route {
                case .add:
                    HostEditorSheet { host in
                        search = ""
                        expanded = host.id
                    }
                case .edit(let host): HostEditorSheet(host: host)
                case .authenticate(let host): AuthenticationSheet(host: host)
                }
            }
            .confirmationDialog(
                "移除主机“\(removing?.name ?? "")”？",
                isPresented: Binding(
                    get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible
            ) {
                Button("移除主机", role: .destructive) {
                    guard let host = removing else { return }
                    do {
                        try store.removeHost(host)
                        expanded = nil
                    } catch { actionError = error.localizedDescription }
                    removing = nil
                }
            } message: {
                Text("仅移除此 Mac 保存的连接配置。服务器上的运行环境和文件会保留。")
            }
            .alert("无法完成操作", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("好") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
    }

    private func hostRow(_ host: Host) -> some View {
        Button {
            expanded = expanded == host.id ? nil : host.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: host.symbol).font(.system(size: 20, weight: .light)).foregroundStyle(ashAccent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(host.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(host.isLocal ? "本地托管" : host.address).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    if store.connectingHosts.contains(host.id) && store.hostLastConnected[host.id] == nil {
                        ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    } else {
                        Image(
                            systemName: store.connectionErrors[host.id] != nil
                                ? "exclamationmark.circle"
                                : store.runtimeUpdateErrors[host.id] != nil
                                    ? "arrow.triangle.2.circlepath"
                                    : store.hostLastConnected[host.id] != nil ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 10))
                    }
                    Text(store.hostStatus(host)).font(.system(size: 11)).lineLimit(1)
                }.foregroundStyle(
                    store.connectionErrors[host.id] != nil || store.runtimeUpdateErrors[host.id] != nil
                        ? Color.orange : Color.secondary)
                Image(systemName: expanded == host.id ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).frame(width: 12)
            }.padding(.horizontal, 24).frame(minHeight: 72).contentShape(Rectangle())
        }.buttonStyle(.plain).ashHover().accessibilityLabel(
            "\(host.name)，\(store.hostStatus(host))，\(expanded == host.id ? "收起设置" : "展开设置")")
    }
}

private struct HostDetailsView: View {
    @EnvironmentObject var store: AppStore
    let host: Host
    let edit: () -> Void
    let authenticate: () -> Void
    let remove: () -> Void
    private var busy: Bool { store.connectingHosts.contains(host.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                metric("连接方式", host.isLocal ? "本地托管" : host.managed ? "托管主机" : "直接 SSH")
                metric("工作区", "\(store.workspaces.filter { $0.hostID == host.id && $0.archived != true }.count)")
                if host.isLocal || host.managed, let health = store.health[host.id] {
                    metric("运行版本", health.version)
                    metric("平台", "\(health.platform == "macos" ? "macOS" : health.platform) · \(health.arch)")
                }
            }
            if let detail = store.connectionErrors[host.id] {
                let issue = HostConnectionIssue(detail)
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.suggestion).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("错误详情") {
                        Text(detail).font(.caption.monospaced()).textSelection(.enabled).padding(.top, 8)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else if let detail = store.runtimeUpdateErrors[host.id] {
                DisclosureGroup("更新未完成，当前版本仍可使用") {
                    Text(detail).font(.caption.monospaced()).textSelection(.enabled).padding(.top, 8)
                }.font(.caption).foregroundStyle(.orange)
            }
            if !host.isLocal && host.managed {
                HStack {
                    Text("自动安装与更新").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(host.installsRuntimeAutomatically ? "已开启" : "已暂停").font(.caption)
                }
            }
            HStack(spacing: 8) {
                Button("检查连接") { Task { await store.connectHost(host) } }.disabled(busy)
                if !host.isLocal {
                    Button("SSH 终端", action: authenticate)
                    if host.managed {
                        Button("安装 / 更新") { Task { await store.connectHost(host, installRuntime: true) } }
                            .disabled(busy).help("检查应用自带的运行包；本次操作不会更改自动更新设置。")
                    }
                    Spacer(minLength: 0)
                    Button("编辑", action: edit)
                }
            }.controlSize(.regular)
            HStack {
                if busy, let phase = store.runtimeSetup[host.id], phase != "已就绪" {
                    Text(phase)  // Visible connection work only; normal polling keeps the timestamp.
                        .font(.caption2).foregroundStyle(.secondary)
                } else if let date = store.hostLastConnected[host.id] {
                    Text("最近连接 · \(date.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(
                        .tertiary)
                }
                Spacer()
                if !host.isLocal {
                    Button("移除主机", role: .destructive, action: remove).buttonStyle(.plain).font(.caption)
                        .disabled(store.removalReason(for: host) != nil).help(
                            store.removalReason(for: host) ?? "移除连接配置")
                }
            }
            if !host.isLocal, let reason = store.removalReason(for: host), !busy {
                Text(reason).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
    }
}
