import AppKit
import SwiftUI

struct TerminalSplitWorkspace: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var fractions: [String: Double] = [:]

    var body: some View {
        GeometryReader { geometry in
            if let layout = store.selectedWorkspace?.visibleLayout(available: store.workspaceRuns.map(\.id)) {
                let minimum = TerminalSplitGeometry.minimumSize(of: layout)
                let size = CGSize(
                    width: max(geometry.size.width, minimum.width),
                    height: max(geometry.size.height, minimum.height))
                let placement = TerminalSplitGeometry(layout: layout, size: size, fractions: fractions)
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // Flat, stable view identities keep the native terminal and its input focus
                        // attached when a pane moves between horizontal and vertical branches.
                        ForEach(store.visibleRuns) { run in
                            if let frame = placement.panes[run.id] {
                                TerminalDropPane(run: run)
                                    .frame(width: frame.width, height: frame.height)
                                    .clipped()
                                    .position(x: frame.midX, y: frame.midY)
                            }
                        }
                        ForEach(placement.dividers) { divider in
                            TerminalResizeHandle(
                                divider: divider,
                                onResize: { value in
                                    fractions[divider.id] = value
                                },
                                onEnd: { value in
                                    store.resizeTerminalSplit(divider.id, fraction: value)
                                    fractions[divider.id] = nil
                                },
                                onCancel: {
                                    fractions[divider.id] = nil
                                }
                            )
                            .frame(
                                width: divider.axis == .horizontal ? 9 : divider.frame.width,
                                height: divider.axis == .vertical ? 9 : divider.frame.height
                            )
                            .position(x: divider.frame.midX, y: divider.frame.midY)
                        }
                    }.frame(width: size.width, height: size.height)
                }
            }
        }
        .background(Color(nsColor: TerminalTheme.background(for: colorScheme)))
        .onChange(of: store.selectedWorkspaceID) { _, _ in fractions = [:] }
        .onChange(of: store.visibleRuns.map(\.id)) { _, _ in fractions = [:] }
        .transaction { $0.animation = nil }
    }
}

private struct TerminalResizeHandle: View {
    let divider: TerminalSplitGeometry.Divider
    let onResize: (Double) -> Void
    let onEnd: (Double) -> Void
    let onCancel: () -> Void
    @State private var start: TerminalSplitGeometry.Divider?
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        Color.clear
            .overlay {
                Rectangle().fill(hovering || dragging ? ashAccent.opacity(0.7) : Color.primary.opacity(0.16))
                    .frame(
                        width: divider.axis == .horizontal ? 1 : nil,
                        height: divider.axis == .vertical ? 1 : nil)
            }
            .contentShape(Rectangle())
            .onHover { active in
                hovering = active
                if active {
                    (divider.axis == .horizontal ? NSCursor.resizeLeftRight : .resizeUpDown).set()
                } else if !dragging {
                    NSCursor.arrow.set()
                }
            }
            .overlay {
                TerminalResizeDragSurface(
                    axis: divider.axis,
                    onResize: { location, origin in
                        if start == nil { start = divider }
                        dragging = true
                        let distance = divider.axis == .horizontal ? location.x - origin.x : origin.y - location.y
                        onResize((start ?? divider).fraction(translatedBy: distance))
                    },
                    onEnd: { location, origin in
                        let distance = divider.axis == .horizontal ? location.x - origin.x : origin.y - location.y
                        onEnd((start ?? divider).fraction(translatedBy: distance))
                        start = nil
                        dragging = false
                    },
                    onCancel: {
                        start = nil
                        dragging = false
                        onCancel()
                    }
                ).accessibilityHidden(true)
            }
            .accessibilityLabel(divider.axis == .horizontal ? "调整终端分屏宽度" : "调整终端分屏高度")
            .accessibilityAdjustableAction { direction in
                onEnd(divider.fraction(translatedBy: direction == .increment ? 24 : -24))
            }
    }
}

private struct TerminalDropPane: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var drag: TerminalDragState
    let run: Run
    var body: some View {
        TerminalPane(run: run)
            .background(TerminalDropTarget(id: run.id, drag: drag))
            .overlay {
                if drag.acceptsPane(run.id, store: store), let side = drag.side(for: run.id) {
                    GeometryReader { geometry in
                        let horizontal = side.axis == .horizontal
                        let width = horizontal ? geometry.size.width / 2 : geometry.size.width
                        let height = horizontal ? geometry.size.height : geometry.size.height / 2
                        Rectangle().fill(ashAccent.opacity(0.25))
                            .overlay { Rectangle().strokeBorder(ashAccent, lineWidth: 2) }
                            .overlay {
                                Label("松开合并 · " + side.label, systemImage: side.symbol)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .frame(width: width, height: height)
                            .offset(x: side == .right ? width : 0, y: side == .bottom ? height : 0)
                    }.allowsHitTesting(false)
                }
            }
    }
}
