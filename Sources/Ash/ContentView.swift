import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var panels = SidePanelStore()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        HSplitView {
            if sidebarVisibility != .detailOnly {
                SidebarView { sidebarVisibility = .detailOnly }
                    .padding(.top, 28)
                    .overlay(alignment: .top) {
                        AshWindowDragArea().padding(.leading, 76).frame(height: 28)
                    }
                    .background(AshStyle.sidebar)
                    .frame(minWidth: 210, idealWidth: 232, maxWidth: 300, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
            HSplitView {
                WorkspaceView(sidebarVisibility: $sidebarVisibility)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
                if store.showInspector, let workspace = store.selectedWorkspace {
                    let context = PanelContext(
                        host: store.selectedHost, workspaceID: workspace.id,
                        cwd: store.selectedRun?.cwd ?? workspace.path,
                        base: store.selectedRun?.baseCommit)
                    SidePanelView(session: panels.session(for: context), context: context)
                        .id(context.key).frame(minWidth: 360, idealWidth: 520, maxWidth: 1000, maxHeight: .infinity)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(AshStyle.canvas)
        .background(AshWindowMovementPolicy())
        .navigationTitle(store.selectedWorkspace?.name ?? "Ash")
        .tint(ashAccent)
        .sheet(isPresented: $store.showNewWorkspace) { WorkspaceSheet() }
        .sheet(isPresented: $store.showNewTask) { TaskSheet() }
        .sheet(isPresented: $store.showHosts) { HostsSheet() }
        .sheet(isPresented: $store.showSettings) { SettingsSheet() }
        .sheet(item: $store.terminalRenameTarget) { TerminalRenameSheet(target: $0) }
        .alert("Ash", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
        .task {
            while !Task.isCancelled {
                store.refreshInBackground()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: store.fontSize) { _, _ in store.save() }
    }
}
