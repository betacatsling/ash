import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    var hideSidebar: () -> Void
    @State private var filter = ""
    @State private var editing: Workspace?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 20, weight: .regular)).foregroundStyle(
                    ashAccent)
                Text("Ash").font(.system(size: 23, weight: .medium)).tracking(-0.7)
                Spacer()
                Button(action: hideSidebar) { Image(systemName: "sidebar.left").frame(width: 28, height: 28) }
                    .buttonStyle(AshIconButtonStyle())
                    .help("收起工作区侧栏").accessibilityLabel("收起工作区侧栏")
            }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 22)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("查找工作区", text: $filter).textFieldStyle(.plain).font(.system(size: 12))
                    .accessibilityLabel("查找工作区")
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("清除工作区搜索")
                }
            }
            .padding(.horizontal, 10).frame(height: 34).ashField()
            .padding(.horizontal, 16).padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(store.hosts) { host in
                        let workspaces = store.workspaces.filter {
                            $0.archived != true && $0.hostID == host.id
                                && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: host.symbol)
                                Text(host.name).lineLimit(1)
                                Spacer()
                                if store.connectionErrors[host.id] != nil {
                                    Image(systemName: "wifi.slash").foregroundStyle(.orange)
                                } else if store.health[host.id] != nil {
                                    Circle().fill(AshStyle.success).frame(width: 5, height: 5)
                                }
                            }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(
                                .horizontal, 10)
                            if let phase = store.runtimeSetup[host.id], phase != "已就绪" {
                                Text(phase).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10)
                            }
                            ForEach(workspaces) { workspace in
                                workspaceRow(workspace, host: host)
                            }
                            if workspaces.isEmpty {
                                Text(filter.isEmpty ? "暂无工作区" : "没有匹配的工作区").font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                        }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 16)
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                sidebarButton("添加工作区", symbol: "plus") { store.showNewWorkspace = true }
                sidebarButton("管理主机", symbol: "network") { store.showHosts = true }
                sidebarButton("设置", symbol: "gearshape") { store.showSettings = true }
            }.padding(12)
            AshHairline().padding(.horizontal, 20)
            HStack {
                Circle().fill(store.activeCount > 0 ? AshStyle.success : Color.secondary.opacity(0.5)).frame(
                    width: 6, height: 6)
                Text(store.activeCount > 0 ? "\(store.activeCount) 个 Agent 会话运行中" : "准备就绪").font(.caption)
                Spacer()
                Text("v0.1.2").font(.caption2).foregroundStyle(.tertiary)
            }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 16)
        }.background(AshStyle.sidebar)
    }
    func sidebarButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                .padding(.horizontal, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).ashHover().foregroundStyle(.secondary)
    }
    func workspaceRow(_ w: Workspace, host: Host) -> some View {
        let count = (store.runs[host.id] ?? []).filter { $0.workspaceId == w.id && $0.active }.count
        return Button {
            store.selectWorkspace(w.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: w.branch == nil ? "folder" : "arrow.triangle.branch").font(.system(size: 14))
                    .foregroundStyle(store.selectedWorkspaceID == w.id ? ashAccent : .secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(w.branch ?? w.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(
                        .system(size: 11)
                    ).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(
                        .secondary
                    ).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(AshStyle.surface.opacity(0.7), in: Capsule())
                }
            }.padding(12).contentShape(Rectangle())
        }.buttonStyle(.plain).ashHover(selected: store.selectedWorkspaceID == w.id)
            .accessibilityAddTraits(store.selectedWorkspaceID == w.id ? .isSelected : [])
            .contextMenu {
                Button("编辑工作区名称…") { editing = w }
                Button("隐藏工作区") {
                    if let i = store.workspaces.firstIndex(where: { $0.id == w.id }) {
                        store.workspaces[i].archived = true
                    }
                    if store.selectedWorkspaceID == w.id {
                        store.selectedWorkspaceID = store.workspaces.first { $0.archived != true }?.id
                    }
                    store.save()
                }
                Divider()
                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: w.path) }
                    .disabled(
                        !host.isLocal)
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(w.path, forType: .string)
                }
            }.sheet(item: $editing) { workspace in WorkspaceRenameSheet(workspace: workspace) }
    }
}
