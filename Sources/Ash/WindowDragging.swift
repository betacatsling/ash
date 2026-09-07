import AppKit
import SwiftUI

/// Hidden-titlebar windows otherwise let WindowServer start moving before the
/// application's mouse monitors or SwiftUI gestures receive the mouse down.
struct AshWindowMovementPolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowMovementPolicyView { WindowMovementPolicyView() }
    func updateNSView(_ view: WindowMovementPolicyView, context: Context) { view.apply() }
}

final class WindowMovementPolicyView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }
    func apply() {
        window?.isMovableByWindowBackground = false
        window?.isMovable = false
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Move from empty chrome through the application while server-side dragging stays disabled.
struct AshWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragAreaView { WindowDragAreaView() }
    func updateNSView(_ view: WindowDragAreaView, context: Context) {}
}

final class WindowDragAreaView: TerminalPointerView {
    private var windowOrigin: CGPoint?
    private var pointerOrigin: CGPoint?

    override func ownsMouseDown(_ event: NSEvent) -> Bool {
        guard super.ownsMouseDown(event), let frameView = window?.contentView?.superview else { return false }
        // Never claim an overlapping label or control, even during a SwiftUI layout update.
        return frameView.hitTest(frameView.convert(event.locationInWindow, from: nil)) === self
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")?.lowercased() {
            case "minimize": window.performMiniaturize(nil)
            case "none": break
            default: window.performZoom(nil)
            }
            return
        }
        cursorStyle = .arrow
        draggingCursor = .arrow
        super.mouseDown(with: event)
        windowOrigin = window.frame.origin
        pointerOrigin = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard isDragging, let window, let windowOrigin, let pointerOrigin else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.setFrameOrigin(
            CGPoint(
                x: windowOrigin.x + pointer.x - pointerOrigin.x,
                y: windowOrigin.y + pointer.y - pointerOrigin.y))
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        windowOrigin = nil
        pointerOrigin = nil
    }
    override func cancelDrag() {
        super.cancelDrag()
        windowOrigin = nil
        pointerOrigin = nil
    }
}

struct TerminalTabContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
