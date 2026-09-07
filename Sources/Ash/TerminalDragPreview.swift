import AppKit
import SwiftUI

struct TerminalDragPreview: NSViewRepresentable {
    @ObservedObject var drag: TerminalDragState
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> TerminalDragPreviewAnchor { TerminalDragPreviewAnchor() }
    func updateNSView(_ view: TerminalDragPreviewAnchor, context: Context) {
        if let source = drag.source {
            let tab = store.workspaceTabs.first { $0.id == source.tabID }
            let member = store.workspaceRuns.first { $0.id == source.runID }
            let title =
                tab.map { store.title(for: $0) }
                ?? member.map { store.terminalTitle($0, hostID: store.selectedHost.id) } ?? "终端"
            let side = store.visibleRuns.first(where: {
                drag.acceptsPane($0.id, store: store) && drag.side(for: $0.id) != nil
            })
            .flatMap { drag.side(for: $0.id) }
            let hint =
                drag.isOverDetachTarget
                ? "松开 · 移到独立标签页"
                : drag.hoveredTabID != nil
                    ? "松开合并 · ⌥ 上下分屏"
                    : side.map { "松开合并 · " + $0.label } ?? "拖到标签栏空白处或终端边缘 · Esc 取消"
            view.show(
                title: title, count: tab?.runIDs.count ?? 1, hint: hint, location: drag.location,
                scheme: colorScheme, reduceMotion: reduceMotion)
        } else {
            var target: CGRect?
            if drag.didCompleteDrop, let id = drag.lastDrop?.tabID, let tabView = drag.tabTargets[id]?.view,
                let window = tabView.window
            {
                target = window.convertToScreen(tabView.convert(tabView.bounds, to: nil))
            }
            view.dismiss(toward: target, reduceMotion: reduceMotion)
        }
    }
    static func dismantleNSView(_ view: TerminalDragPreviewAnchor, coordinator: ()) { view.dismissImmediately() }
}

final class TerminalDragPreviewAnchor: NSView {
    private var panel: NSPanel?
    private var showing = false
    private var generation = 0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dismissImmediately() }
    }

    func show(title: String, count: Int, hint: String, location: CGPoint, scheme: ColorScheme, reduceMotion: Bool) {
        guard let window else { return }
        if panel == nil {
            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 270, height: 76),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = true
            panel.level = .floating
            panel.animationBehavior = .none
            self.panel = panel
        }
        guard let panel else { return }
        panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        panel.contentView = NSHostingView(
            rootView: TerminalDragBadge(title: title, count: count, hint: hint)
                .environment(\.colorScheme, scheme).frame(width: 270, height: 76))
        let point = window.convertPoint(toScreen: location)
        panel.setFrame(CGRect(x: point.x + 16, y: point.y - 90, width: 270, height: 76), display: true)
        if !showing {
            showing = true
            generation += 1
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.12
                panel.animator().alphaValue = 1
            }
        }
    }
    func dismiss(toward frame: CGRect?, reduceMotion: Bool) {
        guard showing, let panel else { return }
        showing = false
        let token = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.22
            if let frame, !reduceMotion {
                panel.animator().setFrame(
                    CGRect(x: frame.midX - 70, y: frame.midY - 18, width: 140, height: 36), display: true)
            }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == token, !self.showing else { return }
            self.panel?.orderOut(nil)
        }
    }
    func dismissImmediately() {
        generation += 1
        showing = false
        panel?.orderOut(nil)
    }
}

private struct TerminalDragBadge: View {
    let title: String
    let count: Int
    let hint: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: count > 1 ? "rectangle.split.2x1" : "terminal").foregroundStyle(ashAccent)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if count > 1 { Text("\(count)").foregroundStyle(.secondary) }
            }.font(.system(size: 12, weight: .medium))
            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AshStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ashAccent.opacity(0.6), lineWidth: 1))
        .padding(3)
    }
}
