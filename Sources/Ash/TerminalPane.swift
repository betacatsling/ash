import AppKit
import SwiftUI

struct TerminalPane: View {
    @EnvironmentObject var store: AppStore
    let run: Run
    @State private var search = ""
    @State private var searching = false
    @State private var noMatches = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if run.status == "queued" || run.status == "starting" {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    Text(run.label)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ["failedToStart", "lost", "cancelled"].contains(run.status) {
                ContentUnavailableView {
                    Label(run.label, systemImage: "terminal")
                } description: {
                    if let error = run.error { Text(error) }
                }
            } else if store.health[store.selectedHost.id] != nil || run.status == "direct" {
                TerminalSurface(
                    id: run.id,
                    spec: RuntimeClient.terminalSpec(
                        host: store.selectedHost, run: run, health: store.health[store.selectedHost.id]),
                    fontSize: store.fontSize,
                    isFocused: store.selectedRun?.id == run.id && !searching,
                    onFocus: { if store.selectedRun?.id != run.id { store.selectRun(run) } }
                )
                .id("\(run.id)-\(store.terminalGeneration[run.id] ?? 0)").background(terminalBackground)
            } else {
                ContentUnavailableView("等待连接主机", systemImage: "network")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if store.visibleRuns.count > 1, store.selectedRun?.id == run.id {
                    Rectangle().strokeBorder(ashAccent.opacity(0.5), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if searching { searchBar.padding(8) }
            }
            .onChange(of: store.terminalSearchRequest) { _, _ in
                guard store.selectedRun?.id == run.id else { return }
                searching = true
                find()
                DispatchQueue.main.async { searchFocused = true }
            }
            .onChange(of: store.selectedRun?.id) { _, id in
                if id != run.id { closeSearch(returnFocus: false) }
            }
            .onDisappear { closeSearch(returnFocus: false) }

    }
    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("查找终端内容", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .frame(minWidth: 40, maxWidth: .infinity)
                    .onSubmit { find() }
                    .onChange(of: search) { _, _ in find() }
                    .onExitCommand { closeSearch() }
                Button {
                    find(previous: true)
                } label: {
                    Image(systemName: "chevron.up").frame(width: 22, height: 24)
                }
                .disabled(search.isEmpty).help("上一个匹配").accessibilityLabel("上一个匹配")
                Button {
                    find()
                } label: {
                    Image(systemName: "chevron.down").frame(width: 22, height: 24)
                }
                .disabled(search.isEmpty).help("下一个匹配 · Enter").accessibilityLabel("下一个匹配")
                Button {
                    closeSearch()
                } label: {
                    Image(systemName: "xmark").frame(width: 22, height: 24)
                }
                .help("关闭查找 · Esc").accessibilityLabel("关闭终端查找")
            }.buttonStyle(.plain)
            if noMatches { Text("没有匹配内容").font(.caption2).foregroundStyle(.secondary) }
        }
        .font(.system(size: 12)).padding(8).frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.separator.opacity(0.5)) }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
    private func find(previous: Bool = false) {
        if search.isEmpty {
            TerminalRegistry.shared.clearSearch(id: run.id)
            noMatches = false
        } else {
            noMatches = !TerminalRegistry.shared.find(search, id: run.id, previous: previous)
        }
    }
    private func closeSearch(returnFocus: Bool = true) {
        guard searching else { return }
        searching = false
        searchFocused = false
        noMatches = false
        TerminalRegistry.shared.clearSearch(id: run.id)
        if returnFocus {
            // Restore the native responder after SwiftUI removes the focused text field.
            DispatchQueue.main.async { TerminalRegistry.shared.focus(id: run.id) }
        }
    }

}
