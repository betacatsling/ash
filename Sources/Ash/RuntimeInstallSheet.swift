import AppKit
import SwiftUI

struct RuntimeInstallSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let host: Host
    @State private var checking = true
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeading(title: "准备远端环境", subtitle: host.name, symbol: "server.rack")
            HStack(spacing: 12) {
                if checking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(
                        systemName: store.connectionErrors[host.id] == nil && store.runtimeUpdateErrors[host.id] == nil
                            ? "checkmark.circle" : "exclamationmark.circle"
                    ).foregroundStyle(ashAccent)
                }
                Text(store.runtimeSetup[host.id] ?? "正在连接…")
            }
            if let failure = store.connectionErrors[host.id] {
                Text(failure).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("如需 SSH 认证，请打开“认证 / 终端”。").font(.caption).foregroundStyle(.secondary)
            } else if let warning = store.runtimeUpdateErrors[host.id] {
                Text(warning).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("仍可使用当前版本。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !checking, store.connectionErrors[host.id] != nil || store.runtimeUpdateErrors[host.id] != nil {
                    Button("重试") { Task { await check() } }
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 570)
            .task { await check() }
    }
    func check() async {
        checking = true
        await store.connectHost(host, installRuntime: true)
        checking = false
    }
}
