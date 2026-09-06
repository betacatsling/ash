import AppKit
import SwiftUI

struct WorkspaceWelcome: View {
    @EnvironmentObject var store: AppStore
    let workspace: Workspace
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("工作区", systemImage: "folder")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(workspace.name).font(.system(size: 30, weight: .medium)).tracking(-0.7)
                            .lineLimit(2).textSelection(.enabled)
                        Text(workspace.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            terminalButton
                            taskButton
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            terminalButton
                            taskButton
                        }
                    }
                    AshHairline()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AGENTS").font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.6).foregroundStyle(.secondary)
                        ForEach(Agent.all) { agent in
                            agentRow(agent)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { shortcuts }
                        VStack(alignment: .leading, spacing: 10) { shortcuts }
                    }
                }
                .frame(maxWidth: 440).padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(AshStyle.canvas)
    }
    private var terminalButton: some View {
        Button {
            Task { await store.startShell() }
        } label: {
            Label("打开终端", systemImage: "terminal").padding(.horizontal, 4).padding(.vertical, 3)
        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy)
    }
    private var taskButton: some View {
        Button {
            store.showNewTask = true
        } label: {
            Label("新建 Agent 任务", systemImage: "plus").padding(.vertical, 3)
        }.buttonStyle(.bordered).controlSize(.large).disabled(store.busy)
    }
    private func agentRow(_ agent: Agent) -> some View {
        let health = store.health[workspace.hostID]
        let available = health?.agents.first { $0.id == agent.id }?.path != nil
        return HStack(spacing: 12) {
            Image(systemName: agent.symbol).font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary).frame(width: 24)
            Text(agent.name).font(.system(size: 13, weight: .medium))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(available ? AshStyle.success : Color.secondary.opacity(0.45)).frame(width: 5, height: 5)
                Text(available ? "已就绪" : health == nil ? "等待检测" : "未检测到")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10)
    }
    @ViewBuilder private var shortcuts: some View {
        shortcut("新终端", "⌘ T")
        shortcut("新任务", "⌘ N")
        shortcut("分屏", "⌘ D")
    }
    private func shortcut(_ title: String, _ key: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            AshKeycap(key: key)
        }.fixedSize()
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 32, weight: .light))
                            .foregroundStyle(ashAccent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("从一个工作区开始").font(.system(size: 30, weight: .medium)).tracking(-0.8)
                            Text("在同一处，连接终端、项目与 Agent。")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 0) {
                        entry("打开本地文件夹", detail: "在这台 Mac 上开始工作", symbol: "folder", key: "⌘ O") {
                            store.chooseFolder()
                        }
                        AshHairline().padding(.leading, 52)
                        entry("添加远程主机", detail: "通过 SSH 连接你的服务器", symbol: "network") {
                            store.showHosts = true
                        }
                    }
                }.frame(maxWidth: 420).padding(32)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }.background(AshStyle.canvas)
    }
    private func entry(
        _ title: String, detail: String, symbol: String, key: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 20, weight: .light))
                    .foregroundStyle(ashAccent).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let key { AshKeycap(key: key) }
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).padding(.vertical, 18).contentShape(Rectangle())
        }.buttonStyle(.plain).ashHover()
    }
}
