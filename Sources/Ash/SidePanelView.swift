import AppKit
import SwiftUI

struct SidePanelView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: SidePanelSession
    let context: PanelContext
    @State private var showAddress = false
    @State private var address = "3000"
    @State private var addressError: String?
    var body: some View {
        VStack(spacing: 0) {
            tabBar
            AshHairline()
            Group {
                if session.selection.isFile {
                    FileWorkspaceView(context: context, tree: session.tree, path: session.selection.path) {
                        session.open(.file($0))
                    }
                } else {
                    switch session.selection {
                    case .tasks:
                        WorkspaceChecklistView(
                            checklist: store.checklist, hostID: context.host.id,
                            workspaceID: context.workspaceID, workspaceName: store.selectedWorkspace?.name ?? "工作区"
                        )
                        .id("\(context.host.id):\(context.workspaceID)")
                    case .sessionInfo: SessionInfoView()
                    case .review: GitReviewView(context: context)
                    case .web(_, let address):
                        BrowserPanelView(
                            model: session.browser(for: session.selection), address: address, host: context.host
                        )
                        .id(session.selection.id)
                    default: EmptyView()
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            AshHairline()
            HStack(spacing: 8) {
                Image(systemName: context.host.symbol)
                Text(context.host.name)
                Text(session.selection == .tasks ? (store.selectedWorkspace?.path ?? context.cwd) : context.cwd)
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(
                height: AshStyle.statusHeight)
        }.background(AshStyle.canvas)
    }
    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(session.tabs) { tab in
                            HStack(spacing: 0) {
                                Button {
                                    session.selection = tab
                                } label: {
                                    Label(tab.title, systemImage: tab.symbol).font(.system(size: 11))
                                        .lineLimit(1).padding(.leading, 12).padding(.trailing, 8).frame(
                                            height: AshStyle.toolbarHeight)
                                }.help(tab.path ?? tab.title)
                                Button {
                                    session.close(tab)
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9)).frame(
                                        width: 24, height: AshStyle.toolbarHeight)
                                }.help("关闭 \(tab.title)").accessibilityLabel("关闭 \(tab.title)")
                            }.buttonStyle(.plain)
                                .foregroundStyle(session.selection == tab ? Color.primary : .secondary)
                                .ashTab(selected: session.selection == tab)
                                .id(tab.id)
                        }
                    }
                }.onChange(of: session.selection) { _, tab in proxy.scrollTo(tab.id) }
            }
            Menu {
                Button("打开文件", systemImage: "folder") { session.open(.files) }
                Button("打开端口或网页…", systemImage: "globe") { showAddress = true }
                Button("Git Diff", systemImage: "arrow.triangle.branch") { session.open(.review) }
                Divider()
                Button("任务清单", systemImage: "checklist") { session.open(.tasks) }
                Button("会话信息", systemImage: "info.circle") { session.open(.sessionInfo) }
            } label: {
                Image(systemName: "plus").frame(width: 32, height: AshStyle.toolbarHeight)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("添加侧栏标签").accessibilityLabel("添加侧栏标签")
            .popover(isPresented: $showAddress) { addressForm }
            Button {
                store.showInspector = false
                store.save()
            } label: {
                Image(systemName: "sidebar.right").frame(width: 32, height: AshStyle.toolbarHeight)
            }.buttonStyle(AshIconButtonStyle()).help("收起右边栏").accessibilityLabel("收起右边栏")
        }.frame(height: AshStyle.toolbarHeight).background(AshStyle.chrome).clipped()
    }
    private var addressForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("打开端口或网页", systemImage: "globe").font(.headline)
            Label(context.host.name, systemImage: context.host.symbol)
                .font(.caption).foregroundStyle(.secondary)
            TextField("端口号或网址", text: $address).textFieldStyle(.roundedBorder).onSubmit(openAddress)
            if let addressError { Text(addressError).font(.caption).foregroundStyle(.orange) }
            HStack {
                ForEach(["3000", "5173", "8080"], id: \.self) { port in
                    Button(port) { address = port }.font(.caption.monospacedDigit())
                }
                Spacer()
                Button("打开", action: openAddress).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 340)
    }
    private func openAddress() {
        do {
            let url = try PreviewAddress.url(address)
            session.open(.web(UUID(), url.absoluteString))
            showAddress = false
            addressError = nil
        } catch { addressError = error.localizedDescription }
    }
}
