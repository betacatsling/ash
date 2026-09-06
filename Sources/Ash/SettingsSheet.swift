import AppKit
import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = ShortcutRecorder()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeading(title: "设置", subtitle: "Ash · 0.1.2", symbol: "slider.horizontal.3")
            Form {
                Section("显示") {
                    Picker("外观", selection: $store.appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }.pickerStyle(.segmented)
                    Stepper("终端字号  \(Int(store.fontSize)) pt", value: $store.fontSize, in: 10...24)
                }
                Section {
                    ForEach(TerminalShortcutAction.settingsActions) { action in
                        let shortcut = store.shortcut(for: action)
                        let label = action.index == nil ? shortcut.label : shortcut.numberedLabel
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(action.settingsTitle)
                                Spacer()
                                Button {
                                    if recorder.action == action {
                                        recorder.stop()
                                    } else {
                                        recorder.start(action, store: store)
                                    }
                                } label: {
                                    Text(recorder.action == action ? "请按快捷键…" : label)
                                        .monospaced().frame(minWidth: 104)
                                }
                                .accessibilityLabel("\(action.settingsTitle)，\(label)，点击修改")
                                .tint(recorder.action == action ? ashAccent : nil)
                            }
                            if recorder.action == action {
                                Text(
                                    recorder.message
                                        ?? (action.index == nil
                                            ? "按下新的组合键，Esc 取消。"
                                            : "按住 ⌘ 或 ⌃，搭配任意数字 1–9，统一设置整组按键。Esc 取消。")
                                )
                                .font(.caption)
                                .foregroundStyle(recorder.message == nil ? Color.secondary : .orange)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    HStack {
                        Text("点击右侧录入，Esc 取消。左右切换会在首尾循环。")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            recorder.stop()
                            store.resetTerminalShortcuts()
                        }
                    }
                } header: {
                    Text("终端快捷键")
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("完成") {
                    store.save()
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).background(AshStyle.canvas).frame(width: 560, height: 560)
            .onDisappear { recorder.stop() }
    }
}

@MainActor final class ShortcutRecorder: ObservableObject {
    @Published var action: TerminalShortcutAction?
    @Published var message: String?
    private var monitor: Any?

    func start(_ action: TerminalShortcutAction, store: AppStore) {
        stop()
        self.action = action
        let recordingWindow = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak store] event in
            guard let self, let store, self.action != nil else { return event }
            guard event.window === recordingWindow else {
                self.stop()
                return event
            }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            guard let shortcut = TerminalShortcut.from(event) else {
                self.message = "请使用 ⌘ 或 ⌃，搭配字母、数字、符号或方向键。"
                return nil
            }
            if let error = store.setShortcut(shortcut, for: action) { self.message = error } else { self.stop() }
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        message = nil
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
