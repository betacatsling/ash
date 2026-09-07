import AppKit
import SwiftUI

struct AuthenticationSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let host: Host
    @State private var sessionID = "auth-" + UUID().uuidString
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(host.name) · SSH").font(.headline)
                Spacer()
                Button("关闭") {
                    TerminalRegistry.shared.close(sessionID)
                    dismiss()
                }
            }.padding(16)
            TerminalSurface(
                id: sessionID,
                spec: LaunchSpec(
                    executable: "/usr/bin/ssh", arguments: RuntimeClient.sshOptions + ["-tt", host.address]),
                fontSize: 13
            )
        }.background(AshStyle.canvas).frame(width: 850, height: 550)
            .onDisappear {
                TerminalRegistry.shared.close(sessionID)
                Task { await store.connectHost(host) }
            }
    }
}
