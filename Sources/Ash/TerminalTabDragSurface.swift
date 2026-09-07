import AppKit
import SwiftUI

/// A real mouse target prevents AppKit's titlebar dragging from taking the gesture.
struct TerminalTabDragSurface: NSViewRepresentable {
    let onClick: (Int) -> Void
    let onDrag: (CGPoint) -> Void
    let onDrop: (CGPoint) -> Void
    let onCancel: () -> Void
    var identifier: String? = nil

    func makeNSView(context: Context) -> TerminalTabMouseView { TerminalTabMouseView() }
    func updateNSView(_ view: TerminalTabMouseView, context: Context) {
        view.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
        view.onClick = onClick
        view.onDrag = onDrag
        view.onDrop = onDrop
        view.onCancel = onCancel
    }
    static func dismantleNSView(_ view: TerminalTabMouseView, coordinator: ()) { view.cancelDrag() }
}

final class TerminalTabMouseView: TerminalPointerView {}

final class TerminalDividerMouseView: TerminalPointerView {}

struct TerminalResizeDragSurface: NSViewRepresentable {
    let axis: TerminalSplitAxis
    let onResize: (CGPoint, CGPoint) -> Void
    let onEnd: (CGPoint, CGPoint) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> TerminalDividerMouseView { TerminalDividerMouseView() }
    func updateNSView(_ view: TerminalDividerMouseView, context: Context) {
        view.minimumDragDistance = 1
        view.cursorStyle = axis == .horizontal ? .resizeLeftRight : .resizeUpDown
        view.draggingCursor = view.cursorStyle
        view.onDrag = { [weak view] location in onResize(location, view?.dragOrigin ?? location) }
        view.onDrop = { [weak view] location in onEnd(location, view?.dragOrigin ?? location) }
        view.onCancel = onCancel
    }
    static func dismantleNSView(_ view: TerminalDividerMouseView, coordinator: ()) { view.cancelDrag() }
}

struct TerminalDropTarget: NSViewRepresentable {
    let id: String
    let drag: TerminalDragState
    func makeNSView(context: Context) -> TerminalDropTargetView { TerminalDropTargetView() }
    func updateNSView(_ view: TerminalDropTargetView, context: Context) {
        view.runID = id
        drag.targets[id] = TerminalDropTargetReference(view)
    }
}

final class TerminalDropTargetView: NSView {
    var runID = ""
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class TerminalDropTargetReference {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

struct TerminalTabDropTarget: NSViewRepresentable {
    let id: String
    let drag: TerminalDragState
    func makeNSView(context: Context) -> TerminalDropTargetView { TerminalDropTargetView() }
    func updateNSView(_ view: TerminalDropTargetView, context: Context) {
        view.runID = id
        drag.tabTargets[id] = TerminalDropTargetReference(view)
    }
}

struct TerminalDetachDropTarget: NSViewRepresentable {
    @EnvironmentObject var drag: TerminalDragState
    func makeNSView(context: Context) -> TerminalDropTargetView { TerminalDropTargetView() }
    func updateNSView(_ view: TerminalDropTargetView, context: Context) {
        drag.detachTarget = TerminalDropTargetReference(view)
    }
}
