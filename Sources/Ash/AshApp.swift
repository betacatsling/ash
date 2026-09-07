import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        TerminalRegistry.shared.detachAll()
        PanelTunnelRegistry.shared.stopAll()
    }
}
@main struct AshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        Window("Ash", id: "main") {
            ContentView().environmentObject(store)
                .preferredColorScheme(store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil)
                .frame(minWidth: 960, minHeight: 620)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1320, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开文件夹…") { store.chooseFolder() }.keyboardShortcut("o")
                Button("新建工作区…") { store.showNewWorkspace = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建终端") { Task { await store.startShell() } }.keyboardShortcut("t")
                Button("新建 Agent 任务…") { store.showNewTask = true }.keyboardShortcut("n")
            }
            // Replace the native Close command so ⌘W never falls back to closing the window.
            CommandGroup(replacing: .saveItem) {
                Button("关闭当前标签页") {
                    guard store.canCloseSelectedTerminal, let tab = store.selectedTerminalTab else { return }
                    Task { await store.closeTerminalTab(tab) }
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(!store.canCloseSelectedTerminal)
            }
            CommandGroup(replacing: .appSettings) { Button("设置…") { store.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(after: .textEditing) {
                Button("查找终端内容") { store.terminalSearchRequest = UUID() }
                    .keyboardShortcut("f").disabled(store.selectedRun == nil)
            }
            CommandMenu("工作区") {
                ForEach(TerminalShortcutAction.allCases) { action in
                    let shortcut = store.shortcut(for: action)
                    Button(action.title) { store.selectTerminal(action) }
                        .keyboardShortcut(shortcut.equivalent, modifiers: shortcut.modifiers)
                        .disabled(!store.canSelectTerminal(action))
                }
                Divider()
                Button("分屏") { store.toggleSplit() }.keyboardShortcut("d")
                Button("显示或隐藏右边栏") {
                    store.showInspector.toggle()
                    store.save()
                }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("管理主机…") { store.showHosts = true }.keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("放大字体") {
                    store.fontSize = min(24, store.fontSize + 1)
                    store.save()
                }.keyboardShortcut("+")
                Button("缩小字体") {
                    store.fontSize = max(10, store.fontSize - 1)
                    store.save()
                }.keyboardShortcut("-")
            }
        }
    }
}
