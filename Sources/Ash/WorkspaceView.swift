import AppKit
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @State private var tabContentWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        ForEach(store.workspaceTabs) { tab in
                            TerminalTabItem(tab: tab).id(tab.id)
                                .transition(.opacity.combined(with: .scale(scale: 0.86)))
                        }
                    }
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84),
                        value: store.workspaceTabs.map { $0.id + $0.runIDs.joined() }
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: TerminalTabContentWidthKey.self, value: geometry.size.width)
                        }
                    }
                }
                .onPreferenceChange(TerminalTabContentWidthKey.self) { tabContentWidth = $0 }
                .onChange(of: store.selectedTerminalTab?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            .frame(maxWidth: tabContentWidth)
            .layoutPriority(1)
            AshWindowDragArea().frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .background(TerminalDetachDropTarget())
                .layoutPriority(-1)
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
