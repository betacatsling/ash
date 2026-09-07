import AppKit
import SwiftUI

class TerminalPointerView: NSView {
    var onClick: (Int) -> Void = { _ in }
    var onDrag: (CGPoint) -> Void = { _ in }
    var onDrop: (CGPoint) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var cursorStyle: NSCursor = .openHand
    var draggingCursor: NSCursor = .closedHand
    var minimumDragDistance: CGFloat = 6
    var dragOrigin: CGPoint? { start }
    var isDragging: Bool { dragging }
    private var start: CGPoint?
    private var dragging = false
    private var mouseMonitor: Any?
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursorStyle) }
    func ownsMouseDown(_ event: NSEvent) -> Bool {
        bounds.intersection(visibleRect).contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        cancelDrag()
        window?.makeKeyAndOrderFront(nil)
        start = event.locationInWindow
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.start != nil, event.keyCode == 53 else { return event }
            self.cancelDrag()
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in self?.cancelDrag() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let location = event.locationInWindow
        guard dragging || hypot(location.x - start.x, location.y - start.y) >= minimumDragDistance else { return }
        dragging = true
        draggingCursor.set()
        onDrag(location)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        if dragging {
            onDrop(event.locationInWindow)
        } else if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick(event.clickCount)
        }
        clearTracking()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelDrag()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        guard window != nil else { return }
        // The titlebar and SwiftUI's ancestor recognizers can consume a click before
        // NSView.mouseDown. Claim only this label's mouse sequence before either does.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
            [weak self] event in
            guard let self, let window = self.window, event.window === window,
                window.attachedSheet == nil
            else { return event }
            switch event.type {
            case .leftMouseDown:
                guard !event.modifierFlags.contains(.control),
                    self.ownsMouseDown(event)
                else { return event }
                self.mouseDown(with: event)
            case .leftMouseDragged:
                guard self.start != nil else { return event }
                self.mouseDragged(with: event)
            case .leftMouseUp:
                guard self.start != nil else { return event }
                self.mouseUp(with: event)
            default: return event
            }
            return nil
        }
    }
    func cancelDrag() {
        if start != nil { onCancel() }
        clearTracking()
    }
    private func clearTracking() {
        start = nil
        dragging = false
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        window?.invalidateCursorRects(for: self)
        NSCursor.arrow.set()
    }
    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
