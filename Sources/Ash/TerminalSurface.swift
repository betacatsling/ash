import AppKit
import SwiftTerm
import SwiftUI

final class TerminalContainerView: NSView {
    var onFocus: (() -> Void)?
    private var focusMonitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let focusMonitor {
            NSEvent.removeMonitor(focusMonitor)
            self.focusMonitor = nil
        }
        guard window != nil else { return }
        focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let clickedInside =
                event.type == .leftMouseDown && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
            if clickedInside { self.onFocus?() }
            return event
        }
    }
    deinit { if let focusMonitor { NSEvent.removeMonitor(focusMonitor) } }
}

@MainActor final class TerminalRegistry {
    static let shared = TerminalRegistry()
    @MainActor final class Entry: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let view: LocalProcessTerminalView
        var ended = false
        let startedAt = Date()
        init(spec: LaunchSpec, fontSize: Double) {
            view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
            super.init()
            view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            view.nativeBackgroundColor = terminalBackgroundColor
            view.nativeForegroundColor = NSColor(red: 0.89, green: 0.9, blue: 0.87, alpha: 1)
            view.caretColor = NSColor(red: 0.88, green: 0.66, blue: 0.38, alpha: 1)
            view.processDelegate = self
            view.startProcess(
                executable: spec.executable, args: spec.arguments,
                environment: RuntimeClient.terminalEnvironment.map { "\($0.key)=\($0.value)" }, currentDirectory: spec.directory
            )
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) { ended = true }
    }
    var entries: [String: Entry] = [:]
    func view(id: String, spec: LaunchSpec, fontSize: Double) -> LocalProcessTerminalView {
        if let entry = entries[id] { return entry.view }
        let entry = Entry(spec: spec, fontSize: fontSize)
        entries[id] = entry
        return entry.view
    }
    func close(_ id: String) {
        if let entry = entries.removeValue(forKey: id) {
            entry.view.terminate()
            entry.view.removeFromSuperview()
        }
    }
    func hasEnded(_ id: String) -> Bool { entries[id]?.ended == true }
    func isStable(_ id: String) -> Bool {
        guard let entry = entries[id] else { return false }
        return !entry.ended && Date().timeIntervalSince(entry.startedAt) > 15
    }
    @discardableResult
    func find(_ text: String, id: String, previous: Bool = false) -> Bool {
        guard let view = entries[id]?.view else { return false }
        return previous ? view.findPrevious(text) : view.findNext(text)
    }
    func clearSearch(id: String) { entries[id]?.view.clearSearch() }
    func focus(id: String) {
        guard let view = entries[id]?.view else { return }
        view.window?.makeFirstResponder(view)
    }
    func detachAll() { for key in Array(entries.keys) { close(key) } }
}
struct TerminalSurface: NSViewRepresentable {
    let id: String
    let spec: LaunchSpec
    let fontSize: Double
    var isFocused: Bool = true
    var onFocus: () -> Void = {}
    final class Coordinator { var wasFocused = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        let view = TerminalRegistry.shared.view(id: id, spec: spec, fontSize: fontSize)
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }
    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        guard let view = TerminalRegistry.shared.entries[id]?.view else { return }
        nsView.onFocus = onFocus
        let shouldFocus = isFocused && !context.coordinator.wasFocused
        context.coordinator.wasFocused = isFocused
        if shouldFocus {
            let coordinator = context.coordinator
            DispatchQueue.main.async {
                if coordinator.wasFocused, view.isDescendant(of: nsView) { view.window?.makeFirstResponder(view) }
            }
        }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // Status polling and tab insertion also update this view. Reapplying
        // the same font needlessly recalculates the terminal grid and scrollback.
        if view.font != font { view.font = font }
    }
}
