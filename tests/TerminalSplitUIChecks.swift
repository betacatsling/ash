import AppKit
import SwiftUI

@testable import Ash

@main struct TerminalSplitUIChecks {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            ".build/split-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let stateDirectory = output.appendingPathComponent("state-" + UUID().uuidString)
        let store = AppStore(directory: stateDirectory)
        store.hosts = [.local]
        store.workspaces = [Workspace(id: "test", name: "Split QA", path: output.path)]
        store.selectedWorkspaceID = "test"
        let runs = ["a", "b", "c"].enumerated().map { index, id in
            Run(
                id: id, taskId: id, workspaceId: "test", title: "终端 \(index + 1)", agent: "shell", prompt: "",
                cwd: output.path, session: id, status: "running", createdAt: Double(index))
        }
        store.runs["local"] = runs
        store.workspaces[0].setPanes(["a"], focused: "a")
        for run in runs {
            let terminal = TerminalRegistry.shared.view(
                id: run.id, spec: LaunchSpec(executable: "/bin/cat", arguments: []),
                fontSize: 13, colorScheme: .dark)
            terminal.feed(text: "\u{1B}[32m❯\u{1B}[0m \(run.title)\r\n\r\nSplit workspace preview\r\n")
        }
        defer { TerminalRegistry.shared.detachAll() }
        store.health["local"] = Health(
            protocol: 1, version: "test", platform: "macos", arch: "aarch64", tmux: "/bin/cat",
            socket: "unused", root: output.path, agents: [], concurrency: 1)
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(
            rootView: WorkspaceView(sidebarVisibility: .constant(.detailOnly))
                .environmentObject(store).environment(\.colorScheme, .dark).ignoresSafeArea(.container, edges: .top)
                .background(AshWindowMovementPolicy()))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settle(host)
        precondition(
            !window.isMovable && !window.isMovableByWindowBackground,
            "Disable server-side dragging before mouse down; synthetic events alone cannot test WindowServer")
        let tabViews = descendants(host).compactMap { $0 as? TerminalTabMouseView }
        for blank in descendants(host).compactMap({ $0 as? WindowDragAreaView }) {
            let area = blank.convert(blank.bounds, to: nil)
            precondition(
                tabViews.allSatisfy { !area.intersects($0.convert($0.bounds, to: nil)) },
                "Window drag regions must not overlap terminal labels")
        }
        let originalWindowFrame = window.frame
        let originals = TerminalRegistry.shared.entries.mapValues { $0.view }

        func tab(_ index: Int) -> TerminalTabMouseView {
            let tabs = descendants(host).compactMap { $0 as? TerminalTabMouseView }.filter {
                $0.identifier?.rawValue.hasPrefix("tab:") == true
            }
            .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            precondition(tabs.count == store.workspaceTabs.count, "Each tab group must have one native mouse target")
            return tabs[index]
        }
        func target(_ id: String, _ side: TerminalDropSide) -> CGPoint {
            let view = descendants(host).compactMap { $0 as? TerminalDropTargetView }.first { $0.runID == id }!
            let frame = view.convert(view.bounds.intersection(view.visibleRect), to: nil)
            switch side {
            case .left: return CGPoint(x: frame.minX + 24, y: frame.midY)
            case .right: return CGPoint(x: frame.maxX - 24, y: frame.midY)
            case .top: return CGPoint(x: frame.midX, y: frame.maxY - 24)
            case .bottom: return CGPoint(x: frame.midX, y: frame.minY + 24)
            }
        }
        var eventNumber = 0
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, count: Int = 1) {
            eventNumber += 1
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: count,
                pressure: 1)!
            NSApp.sendEvent(event)
            settle(host)
        }
        func drag(_ index: Int, to point: CGPoint) {
            let view = tab(index)
            precondition(!view.mouseDownCanMoveWindow)
            let rect = view.convert(view.bounds, to: nil)
            mouse(.leftMouseDown, CGPoint(x: rect.midX, y: rect.midY))
            mouse(.leftMouseDragged, CGPoint(x: rect.midX, y: rect.midY - 12))
            mouse(.leftMouseDragged, point)
            mouse(.leftMouseUp, point)
            precondition(window.frame == originalWindowFrame, "Dragging a terminal tab must never move the window")
        }
        // Merge an independent tab into the visible terminal; the header shrinks to two pages.
        drag(1, to: target("a", .left))
        precondition(store.workspaceTabs.count == 2 && store.workspaces[0].paneRunIDs == ["b", "a"])
        precondition(window.firstResponder === originals["b"])
        let grouped = store.selectedTerminalTab!
        store.selectTerminal(.terminal2)
        settle(host)
        precondition(store.visibleRuns.map(\.id) == ["c"], "Independent tabs must fill the whole page")
        store.selectTerminal(.terminal1)
        settle(host)
        precondition(store.visibleRuns.map(\.id) == ["b", "a"] && store.selectedTerminalTab?.layout == grouped.layout)
        drag(1, to: target("a", .bottom))
        precondition(store.workspaceTabs.count == 1 && store.visibleRuns.count == 3)
        precondition(TerminalRegistry.shared.entries.allSatisfy { originals[$0.key] === $0.value.view })
        let member = descendants(host).compactMap { $0 as? TerminalTabMouseView }
            .first { $0.identifier?.rawValue == "member:c" }!
        let memberRect = member.convert(member.bounds, to: nil)
        let blank = descendants(host).compactMap { $0 as? WindowDragAreaView }.last!
        let blankRect = blank.convert(blank.bounds.intersection(blank.visibleRect), to: nil)
        mouse(.leftMouseDown, CGPoint(x: memberRect.midX, y: memberRect.midY))
        mouse(.leftMouseDragged, CGPoint(x: blankRect.midX, y: blankRect.midY))
        mouse(.leftMouseUp, CGPoint(x: blankRect.midX, y: blankRect.midY))
        settle(host)
        precondition(window.frame == originalWindowFrame, "Dragging a group member out must not move the window")
        precondition(store.workspaceTabs.count == 2 && store.visibleRuns.map(\.id) == ["c"])
        let single = tab(1).convert(tab(1).bounds, to: nil)
        mouse(.leftMouseDown, CGPoint(x: single.midX, y: single.midY), count: 2)
        mouse(.leftMouseUp, CGPoint(x: single.midX, y: single.midY), count: 2)
        precondition(store.terminalRenameTarget?.run.id == "c")
        store.terminalRenameTarget = nil
        store.selectTerminal(.terminal1)
        settle(host)
        let saved = store.workspaces[0].terminalGroups
        let rect = tab(1).convert(tab(1).bounds, to: nil)
        mouse(.leftMouseDown, CGPoint(x: rect.midX, y: rect.midY))
        mouse(.leftMouseDragged, target("b", .top))
        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53)!
        NSApp.sendEvent(escape)
        mouse(.leftMouseUp, target("b", .top))
        precondition(store.workspaces[0].terminalGroups == saved, "Escape must cancel a merge")
        drag(1, to: CGPoint(x: -50, y: -50))
        precondition(store.workspaces[0].terminalGroups == saved, "An outside drop must not merge pages")
        // Resize both orientations through the real window's mouse dispatch.
        for axis in [TerminalSplitAxis.horizontal, .vertical] {
            store.arrangeTerminalTab(store.selectedTerminalTab!, axis: axis)
            settle(host)
            let ids = Set(store.visibleRuns.map(\.id))
            let targets = descendants(host).compactMap { $0 as? TerminalDropTargetView }.filter {
                ids.contains($0.runID)
            }
            let area = targets.map { $0.convert($0.bounds, to: nil) }.reduce(CGRect.null) { $0.union($1) }
            let layout = store.workspaces[0].terminalLayout!
            let divider = TerminalSplitGeometry(layout: layout, size: area.size).dividers.first { $0.axis == axis }!
            let point = CGPoint(x: area.minX + divider.frame.midX, y: area.maxY - divider.frame.midY)
            let end = CGPoint(x: point.x + (axis == .horizontal ? 40 : 0), y: point.y - (axis == .vertical ? 30 : 0))
            mouse(.leftMouseDown, point)
            mouse(.leftMouseDragged, end)
            mouse(.leftMouseUp, end)
            precondition(store.workspaces[0].terminalLayout != layout, "Divider must resize through its visible line")
            precondition(window.frame == originalWindowFrame, "Resizing a split must never move the window")
        }
        precondition(
            AppStore(directory: stateDirectory).workspaces[0].terminalLayout == store.workspaces[0].terminalLayout)
        let pane = descendants(host).compactMap { $0 as? TerminalDropTargetView }.first { $0.runID == "b" }!
        let bounds = pane.convert(pane.bounds, to: nil)
        mouse(.leftMouseDown, CGPoint(x: bounds.midX, y: bounds.midY))
        mouse(.leftMouseUp, CGPoint(x: bounds.midX, y: bounds.midY))
        precondition(
            store.selectedRun?.id == "b" && window.firstResponder === originals["b"],
            "Clicking a pane must focus its terminal")
        store.selectTerminal(.terminal1)
        settle(host)
        precondition(
            window.firstResponder === originals["b"], "Keyboard page selection must restore the last focused pane")
        try snapshot(host, to: output.appendingPathComponent("mixed-dark.png"))
        host.rootView = WorkspaceView(sidebarVisibility: .constant(.detailOnly))
            .environmentObject(store).environment(\.colorScheme, .light).ignoresSafeArea(.container, edges: .top)
            .background(AshWindowMovementPolicy())
        window.appearance = NSAppearance(named: .aqua)
        settle(host)
        try snapshot(host, to: output.appendingPathComponent("mixed-light.png"))
        print(
            "PASS: divider dragging on both axes, persisted proportions, pane click and keyboard focus, light/dark previews"
        )
        print(
            "PASS: grouped tab drag, whole-page switching, horizontal/vertical/mixed drops, stable window, terminal identity/focus, rename and cancellation"
        )
        window.orderOut(nil)
        window.contentView = nil
    }
    @MainActor static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        host.layoutSubtreeIfNeeded()
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor static func snapshot(_ view: NSView, to url: URL) throws {
        if ProcessInfo.processInfo.environment["ASH_UI_SCREENSHOTS"] == "1", let window = view.window {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Window screenshot failed")
            return
        }
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
