import SwiftUI

struct HostEditorSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let host: Host?
    var didSave: (Host) -> Void = { _ in }
    @State private var draft: HostDraft
    @State private var aliases: [String] = []
    @State private var advanced = false
    @State private var saveError: String?
    @FocusState private var addressFocused: Bool

    init(host: Host? = nil, didSave: @escaping (Host) -> Void = { _ in }) {
        self.host = host
        self.didSave = didSave
        _draft = State(initialValue: host.map(HostDraft.init) ?? HostDraft())
    }

    private var addressLocked: Bool { host.map { host in store.workspaces.contains { $0.hostID == host.id } } ?? false }
    private var validation: String? {
        do {
            let candidate = try draft.host(id: host?.id ?? "draft")
            try store.validateHost(candidate)
            return nil
        } catch { return error.localizedDescription }
    }
    private var changed: Bool { host.map { HostDraft($0) != draft } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(
                title: host == nil ? "添加主机" : "编辑主机",
                symbol: host == nil ? "plus.circle" : "server.rack"
            ).padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("SSH 地址或别名")
                        HStack(spacing: 8) {
                            TextField("user@host 或 SSH 别名", text: $draft.address)
                                .textFieldStyle(.roundedBorder).focused($addressFocused).disabled(addressLocked)
                                .accessibilityLabel("SSH 地址或别名")
                            if !aliases.isEmpty && !addressLocked {
                                Menu("选择别名") {
                                    ForEach(aliases, id: \.self) { alias in Button(alias) { draft.address = alias } }
                                }.fixedSize()
                            }
                        }
                        if addressLocked {
                            Text("此主机关联着工作区。连接另一台服务器时，请添加新主机。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("沿用 SSH 配置中的端口、密钥和跳板。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            fieldLabel("显示名称")
                            Text("可选").font(.caption).foregroundStyle(.tertiary)
                        }
                        TextField("留空时使用 SSH 地址", text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel(
                            "显示名称")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        fieldLabel("连接方式")
                        Picker("连接方式", selection: $draft.managed) {
                            Text("托管主机").tag(true)
                            Text("直接 SSH").tag(false)
                        }.pickerStyle(.segmented).labelsHidden()
                        Text(draft.managed ? "终端与 Agent 会话可在关闭 Ash 后继续运行。" : "使用交互 SSH 终端，无需安装远端运行程序。")
                            .font(.caption).foregroundStyle(.secondary)
                        if draft.managed {
                            Toggle("自动安装与更新运行环境", isOn: $draft.autoInstallRuntime)
                            if host != nil { Toggle("自动连接此主机", isOn: $draft.autoConnect) }
                            DisclosureGroup("运行程序路径", isExpanded: $advanced) {
                                TextField(".local/bin/ash-runtime", text: $draft.runtimePath)
                                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                                    .accessibilityLabel("运行程序路径").padding(.top, 8)
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let message = saveError ?? (draft.address.isEmpty ? nil : validation) {
                        Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(24)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if host == nil {
                    Button("添加") { save(connect: false) }.disabled(validation != nil)
                }
                Button(host == nil ? "添加并连接" : "保存") { save(connect: host == nil) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validation != nil || !changed)
            }.controlSize(.large).padding(24)
        }.frame(width: 540, height: 572).background(AshStyle.canvas).tint(ashAccent)
            .task {
                aliases = await Task.detached { SSHConfigDiscovery.aliases() }.value
                addressFocused = host == nil
            }
            .onChange(of: draft) { _, _ in saveError = nil }
    }

    private func fieldLabel(_ text: String) -> some View { Text(text).font(.system(size: 12, weight: .medium)) }
    private func save(connect: Bool) {
        do {
            let saved = try store.saveHost(
                draft, replacing: host?.id, connectAutomatically: host == nil ? connect : nil)
            didSave(saved)
            dismiss()
            if connect || (host.map { !$0.hasSameConnection(as: saved) } ?? false) {
                Task { await store.connectHost(saved) }
            }
        } catch { saveError = error.localizedDescription }
    }
}
