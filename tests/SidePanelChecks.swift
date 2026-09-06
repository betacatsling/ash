// Standalone checks for machines with Command Line Tools but without XCTest.
import Foundation
@main struct SidePanelChecks {
    @MainActor static func main() async throws {
        let url = try PreviewAddress.url(" 3000 ")
        precondition(url.absoluteString == "http://127.0.0.1:3000")
        let loopback = try PreviewAddress.url("http://[::1]:8000")
        precondition(PreviewAddress.isLoopback(loopback))
        for invalid in ["", "0", "65536", "https://localhost:99999", "file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.com"] {
            do { _ = try PreviewAddress.url(invalid); fatalError("Accepted invalid address: \(invalid)") }
            catch {}
        }
        let session = SidePanelSession()
        session.open(.files); session.open(.file("Sources/main.swift")); session.open(.file("Sources/main.swift"))
        precondition(session.tabs == [.tasks, .file("Sources/main.swift")])
        let fileTabID = session.selection.id
        session.open(.review); session.open(.file("README.md"))
        precondition(session.tabs == [.tasks, .file("README.md"), .review])
        precondition(session.selection.id == fileTabID)
        session.open(.review); session.open(.files)
        precondition(session.selection == .file("README.md") && session.tabs.count == 3)
        session.close(.review)
        session.close(.tasks); session.close(.file("README.md"))
        precondition(session.tabs == [.files] && session.selection == .files)
        let store = SidePanelStore()
        let first = PanelContext(host: .local, workspaceID: "w", cwd: "/one", base: nil)
        let second = PanelContext(host: .local, workspaceID: "w", cwd: "/worktree", base: nil)
        store.session(for: first).open(.file("README.md"))
        precondition(store.session(for: second).selection == .tasks)
        precondition(store.session(for: first).selection == .file("README.md"))
        print("PASS: preview URL validation, tab lifecycle, workspace/worktree isolation")
        if let port = ProcessInfo.processInfo.environment["ASH_PANEL_TEST_PORT"],
           let directory = ProcessInfo.processInfo.environment["ASH_PANEL_TEST_DIRECTORY"],
           let runtime = ProcessInfo.processInfo.environment["ASH_PANEL_TEST_RUNTIME"] {
            let host = Host(id: "fixture", name: "Loopback SSH", address: "ash-panel-fixture", runtimePath: runtime)
            let context = PanelContext(host: host, workspaceID: "fixture", cwd: directory, base: nil)
            let file: FilePreview = try await context.call("readFile", path: "index.html")
            precondition(file.text.contains("PANEL_SSH_OK"))
            let browser = PanelBrowserModel()
            await browser.navigate(port, host: host)
            for _ in 0..<50 {
                if browser.webView.url != nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            precondition(browser.forwarded && browser.error == nil, browser.error ?? "Tunnel was not started")
            let url = browser.webView.url!
            let (data, _) = try await URLSession.shared.data(from: url)
            precondition(String(decoding: data, as: UTF8.self).contains("PANEL_SSH_OK"))
            browser.stop()
            precondition(!browser.forwarded)
            try await Task.sleep(for: .milliseconds(400))
            do {
                _ = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2))
                fatalError("Tunnel remained open after closing")
            } catch {}
            print("PASS: real SSH file preview, HTTP forwarding, and tunnel cleanup")
        }
    }
}
