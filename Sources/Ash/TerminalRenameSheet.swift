import SwiftUI

struct TerminalRenameSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let target: TerminalRenameTarget
    @State private var name = ""
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("重命名终端").font(.headline)
            TextField("标签名称", text: $name)
                .textFieldStyle(.roundedBorder).focused($nameFocused)
                .onChange(of: name) { _, _ in saveError = nil }
            if let message = saveError ?? AppStore.terminalTitleError(name) {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("恢复原名称") { name = target.run.title }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if store.renameTerminal(target.run, hostID: target.hostID, name: name) {
                        dismiss()
                    } else {
                        saveError = store.error ?? "名称未能保存，请重试。"
                    }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(AppStore.terminalTitleError(name) != nil)
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 440)
            .onAppear {
                name = store.terminalTitle(target.run, hostID: target.hostID)
                nameFocused = true
            }
    }
}
