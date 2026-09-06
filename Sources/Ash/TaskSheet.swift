import AppKit
import SwiftUI

struct TaskSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var agent = "pi"
    @State private var title = ""
    @State private var prompt = ""
    @State private var isolated = true
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeading(
                title: "新建 Agent 任务",
                subtitle: store.selectedWorkspace.map { "\($0.name) · \(store.selectedHost.name)" } ?? "请先添加工作区",
                symbol: "sparkles")
            VStack(spacing: 4) {
                ForEach(Agent.all) { item in
                    Button {
                        agent = item.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).font(.system(size: 16)).frame(width: 24)
                            Text(item.name).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: agent == item.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(agent == item.id ? ashAccent : Color.secondary.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).ashHover(selected: agent == item.id)
                        .accessibilityAddTraits(agent == item.id ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("任务名称").font(.caption.weight(.medium))
                TextField("例如：实现设置页面", text: $title).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("任务说明").font(.caption.weight(.medium))
                TextEditor(text: $prompt).font(.system(size: 13)).scrollContentBackground(.hidden).padding(8).frame(
                    height: 120
                ).ashField().accessibilityLabel("任务说明")
            }
            Toggle(isOn: $isolated) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("使用独立 Git worktree").font(.system(size: 12, weight: .medium))
                    Text("从 HEAD 创建，不含未提交改动。").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .help("仅适用于 Git 仓库")
            AshHairline()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("启动任务") {
                    let t = title.isEmpty ? String(prompt.prefix(36)) : title
                    dismiss()
                    Task {
                        await store.start(
                            agent: agent, prompt: prompt, title: t.isEmpty ? "Agent 会话" : t, isolated: isolated)
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(
                    store.selectedWorkspace == nil || store.busy
                        || (!store.selectedHost.managed && !store.selectedHost.isLocal))
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 610)
    }
}
