import AppKit
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    var body: some View {
        VStack(spacing: 0) {
            tabs
            AshHairline()
            if let workspace = store.selectedWorkspace {
                if let message = store.connectionErrors[workspace.hostID] {
                    HStack(alignment: .top) {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("连接中断 · 正在自动重连").font(.caption.weight(.medium))
                            Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer()
                        Button("重试") { Task { await store.refresh() } }.controlSize(.small)
                    }.padding(12).background(Color.orange.opacity(0.07))
                }
                if let message = store.workspaceErrors[workspace.id] {
                    Label(message, systemImage: "icloud.slash").font(.caption).foregroundStyle(.orange).padding(10)
                }
                if store.workspaceRuns.isEmpty {
                    WorkspaceWelcome(workspace: workspace)
                } else {
                    TerminalSplitWorkspace()
                }
                bottomBar(workspace)
            } else {
                WelcomeView()
            }
        }
        .background(AshStyle.canvas)
        .modifier(TerminalWorkspaceDragModifier())
        // Loading must not resize the PTY and reflow its contents twice.
        .overlay(alignment: .top) {
            if store.busy {
                ProgressView().progressViewStyle(.linear).frame(height: 2)
                    .allowsHitTesting(false).accessibilityLabel("正在创建会话")
            }
        }
    }
    var tabs: some View {
        HStack(spacing: 0) {
            if sidebarVisibility == .detailOnly {
                // Reserve the titlebar's traffic-light controls when the left sidebar is hidden.
                Color.clear.frame(width: 76)
                Button {
                    sidebarVisibility = .all
                } label: {
                    Image(systemName: "sidebar.left").frame(width: 36, height: AshStyle.toolbarHeight)
                }.buttonStyle(AshIconButtonStyle())
                    .help("显示工作区侧栏").accessibilityLabel("显示工作区侧栏")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.workspaceRuns) { run in
                            let selected = store.selectedRun?.id == run.id
                            let title = store.terminalTitle(run, hostID: store.selectedHost.id)
                            HStack(spacing: 0) {
                                Button {
                                    store.selectRun(run)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: run.symbol).font(.caption)
                                        Text(title).font(.system(size: 12, weight: .medium))
                                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 200)
                                        if run.status == "queued" {
                                            Image(systemName: "clock").font(.caption2)
                                        } else {
                                            Circle().fill(run.active ? AshStyle.success : Color.secondary.opacity(0.5))
                                                .frame(width: 5, height: 5)
                                        }
                                    }
                                    .padding(.leading, 15).padding(.trailing, 7).frame(height: AshStyle.toolbarHeight)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded { store.beginRenamingTerminal(run) }
                                    )
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                    .modifier(TerminalDragModifier(run: run))
                                    .help("\(title)\n双击重命名；拖到另一个终端的左侧或右侧分屏")
                                Button {
                                    Task { await store.closeTerminal(run) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                        .frame(width: 24, height: 28).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .opacity(selected ? 1 : 0)
                                    .allowsHitTesting(selected)
                                    .accessibilityHidden(!selected)
                                    .disabled(!selected || store.closingRunIDs.contains(run.id))
                                    .help(run.active ? "关闭终端并停止会话，保留文件与记录" : "关闭终端，保留记录")
                                    .accessibilityLabel("关闭终端：\(title)")
                            }
                            .padding(.trailing, 5).frame(height: AshStyle.toolbarHeight)
                            .foregroundStyle(selected ? Color.primary : .secondary)
                            .ashTab(selected: selected)
                            .id(run.id)
                            .contextMenu {
                                Button("重命名…") { store.beginRenamingTerminal(run) }
                                    .disabled(store.closingRunIDs.contains(run.id))
                                Button("关闭终端") { Task { await store.closeTerminal(run) } }
                                    .disabled(store.closingRunIDs.contains(run.id))
                                Divider()
                                Button("查找终端内容") {
                                    store.selectRun(run)
                                    DispatchQueue.main.async { store.terminalSearchRequest = UUID() }
                                }
                                if store.visibleRuns.count > 1,
                                    store.visibleRuns.contains(where: { $0.id == run.id })
                                {
                                    Button("收起此分屏") { store.hidePane(run.id) }
                                }
                            }
                        }
                    }
                }
                .onChange(of: store.selectedRun?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            Button {
                Task { await store.startShell() }
            } label: {
                Image(systemName: "plus").font(.system(size: 13))
                    .frame(width: 40, height: AshStyle.toolbarHeight).contentShape(Rectangle())
            }.buttonStyle(AshIconButtonStyle())
                .disabled(store.busy || store.selectedWorkspace == nil).help("新建终端 ⌘T").accessibilityLabel("新建终端")
            if !store.showInspector, store.selectedWorkspace != nil {
                Button {
                    store.showInspector = true
                    store.save()
                } label: {
                    Image(systemName: "sidebar.right").frame(width: 36, height: AshStyle.toolbarHeight)
                }.buttonStyle(AshIconButtonStyle())
                    .help("显示右边栏 ⌥⌘I").accessibilityLabel("显示右边栏")
            }
        }
        .frame(height: AshStyle.toolbarHeight)
        .background(AshStyle.chrome)
        .clipped()
        // Native terminal views should change at their final size, without
        // inheriting an insertion or selection animation from a parent.
        .transaction { $0.animation = nil }
    }
    func bottomBar(_ w: Workspace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: store.selectedHost.symbol)
            Text(store.selectedHost.name)
            Divider().frame(height: 10)
            Text(w.path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(store.selectedHost.managed ? "托管会话" : "直接 SSH")
            Text("UTF-8").foregroundStyle(.tertiary)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 14).frame(
            height: AshStyle.statusHeight
        ).background(
            AshStyle.chrome
        )
        .overlay(alignment: .top) { AshHairline() }
    }
}
