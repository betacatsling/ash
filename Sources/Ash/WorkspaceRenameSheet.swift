import AppKit
import SwiftUI

struct WorkspaceRenameSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("工作区名称").font(.headline)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder)
            Text(workspace.path).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    if let i = store.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                        store.workspaces[i].name = name
                        store.save()
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 420).onAppear { name = workspace.name }
    }
}
