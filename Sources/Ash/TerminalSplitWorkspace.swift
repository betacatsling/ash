import AppKit
import SwiftUI

struct TerminalPaneFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor final class TerminalDragState: ObservableObject {
    @Published var source: TerminalDrag?
    @Published var location = CGPoint.zero
    var frames: [String: CGRect] = [:]

    func side(for id: String) -> TerminalDropSide? {
        guard let source, source.runID != id, let frame = frames[id], frame.contains(location) else { return nil }
        return location.x < frame.midX ? .left : .right
    }
    func finish(store: AppStore) {
        defer { source = nil }
        guard let source else { return }
        for run in store.visibleRuns {
            if let side = side(for: run.id) {
                store.moveTerminal(source, beside: run.id, side: side)
                return
            }
        }
    }
}

struct TerminalDragModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var drag: TerminalDragState
    let run: Run
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .updating($isDragging) { _, state, _ in state = true }
                .onChanged { value in
                    drag.source = TerminalDrag(workspaceID: run.workspaceId, runID: run.id)
                    drag.location = value.location
                }
                .onEnded { value in
                    drag.location = value.location
                    drag.finish(store: store)
                }
        )
        .onChange(of: isDragging) { _, active in
            // Gesture cancellation (including leaving the window) must never leave a preview behind.
            if !active { drag.source = nil }
        }
    }
}

struct TerminalWorkspaceDragModifier: ViewModifier {
    @EnvironmentObject var store: AppStore
    @StateObject private var drag = TerminalDragState()
    func body(content: Content) -> some View {
        content
            .environmentObject(drag)
            .onPreferenceChange(TerminalPaneFramesKey.self) { drag.frames = $0 }
            .onChange(of: store.selectedWorkspaceID) { _, _ in drag.source = nil }
    }
}

struct TerminalSplitWorkspace: View {
    @EnvironmentObject var store: AppStore
    @State private var weights: [String: CGFloat] = [:]
    @State private var resizeStart: [String: CGFloat]?
    private let minimumWidth: CGFloat = 220
    private let dividerWidth: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let runs = store.visibleRuns
            let total = max(
                geometry.size.width, CGFloat(runs.count) * minimumWidth + CGFloat(max(0, runs.count - 1)) * dividerWidth
            )
            let widths = paneWidths(runs: runs, total: total)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        TerminalDropPane(run: run).frame(width: widths[run.id] ?? minimumWidth)
                        if index + 1 < runs.count {
                            resizeHandle(left: run.id, right: runs[index + 1].id, widths: widths)
                        }
                    }
                }
                .frame(width: total, height: geometry.size.height)
            }
        }
        .onChange(of: store.visibleRuns.map(\.id)) { _, _ in
            weights = [:]
            resizeStart = nil
        }
        .transaction { $0.animation = nil }
    }

    private func paneWidths(runs: [Run], total: CGFloat) -> [String: CGFloat] {
        let extra = max(0, total - CGFloat(runs.count) * minimumWidth - CGFloat(max(0, runs.count - 1)) * dividerWidth)
        let sum = runs.reduce(CGFloat.zero) { $0 + weights[$1.id, default: 1] }
        return Dictionary(
            uniqueKeysWithValues: runs.map { run in
                (
                    run.id,
                    minimumWidth + extra
                        * (sum > 0 ? weights[run.id, default: 1] / sum : 1 / CGFloat(max(1, runs.count)))
                )
            })
    }

    private func resizeHandle(left: String, right: String, widths: [String: CGFloat]) -> some View {
        Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.25))
            .frame(width: dividerWidth)
            .overlay { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if resizeStart == nil { resizeStart = widths }
                        guard let start = resizeStart, let a = start[left], let b = start[right] else { return }
                        let adjusted = min(a + b - minimumWidth, max(minimumWidth, a + value.translation.width))
                        var next = start.mapValues { max(0, $0 - minimumWidth) }
                        next[left] = adjusted - minimumWidth
                        next[right] = a + b - adjusted - minimumWidth
                        weights = next
                    }
                    .onEnded { _ in resizeStart = nil }
            )
            .accessibilityLabel("调整终端分屏宽度")
    }
}

private struct TerminalDropPane: View {
    @EnvironmentObject var drag: TerminalDragState
    let run: Run
    var body: some View {
        TerminalPane(run: run)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TerminalPaneFramesKey.self, value: [run.id: geometry.frame(in: .global)])
                }
            }
            .overlay {
                if let side = drag.side(for: run.id) {
                    HStack(spacing: 0) {
                        if side == .right { Color.clear }
                        Rectangle().fill(ashAccent.opacity(0.22))
                            .overlay { Rectangle().strokeBorder(ashAccent, lineWidth: 2) }
                            .overlay {
                                Label(side == .left ? "放到左侧" : "放到右侧", systemImage: "rectangle.split.2x1")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                        if side == .left { Color.clear }
                    }.allowsHitTesting(false)
                }
            }
    }
}
