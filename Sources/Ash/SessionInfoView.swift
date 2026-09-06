import SwiftUI

struct SessionInfoView: View {
    @EnvironmentObject var store: AppStore
    @State private var stopConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    taskContent
                }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 20)
            }
            Spacer(minLength: 0)
        }.background(AshStyle.canvas)
            .confirmationDialog("停止这个会话？", isPresented: $stopConfirmation, titleVisibility: .visible) {
                Button("停止会话", role: .destructive) { if let r = store.selectedRun { Task { await store.cancel(r) } } }
            } message: {
                Text("停止当前程序，保留工作区与文件变更。")
            }
    }
    @ViewBuilder var taskContent: some View {
        if let run = store.selectedRun {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: run.symbol).font(.system(size: 22, weight: .light)).foregroundStyle(ashAccent)
                Text(store.terminalTitle(run, hostID: store.selectedHost.id))
                    .font(.system(size: 20, weight: .medium)).textSelection(.enabled)
                Text(run.agentName).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Circle().fill(run.active ? AshStyle.success : Color.secondary).frame(width: 6, height: 6)
                Text(run.label).font(.caption)
            }
            if let error = run.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !run.prompt.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    eyebrow("任务内容")
                    Text(run.prompt).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled)
                }
            }
            AshHairline()
            VStack(alignment: .leading, spacing: 12) {
                detail("执行主机", store.selectedHost.name)
                detail(
                    "启动时间", Date(timeIntervalSince1970: run.createdAt).formatted(date: .abbreviated, time: .shortened))
                detail("执行目录", run.cwd)
                if let base = run.baseCommit { detail("基准提交", String(base.prefix(10))) }
                detail("执行编号", String(run.id.prefix(8)).lowercased())
            }
            VStack(spacing: 8) {
                if run.active {
                    Button {
                        stopConfirmation = true
                    } label: {
                        Label(run.status == "queued" ? "取消排队" : "停止会话", systemImage: "stop").frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        Task {
                            await store.start(
                                agent: run.agent, prompt: run.prompt, title: run.title, isolated: false, retry: run)
                        }
                    } label: {
                        Label("重新运行", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    Button {
                        Task { await store.archive(run) }
                    } label: {
                        Label("归档记录", systemImage: "archivebox").frame(maxWidth: .infinity)
                    }
                }
                if run.status != "direct" {
                    Button {
                        Task { await store.export(run) }
                    } label: {
                        Label("导出终端记录", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                }
            }.controlSize(.large)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checklist").font(.system(size: 25, weight: .light)).foregroundStyle(.secondary)
                Text("暂无会话").font(.headline)
                Button("新建 Agent 任务") { store.showNewTask = true }.buttonStyle(.bordered)
            }
        }
    }
    func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
    func detail(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow(key)
            Text(value).font(.system(size: 12)).textSelection(.enabled)
        }
    }
}
