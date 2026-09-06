import XCTest
@testable import Ash

final class SidePanelTests: XCTestCase {
    func testPreviewAddresses() throws {
        XCTAssertEqual(try PreviewAddress.url(" 3000 ").absoluteString, "http://127.0.0.1:3000")
        XCTAssertEqual(try PreviewAddress.url("localhost:5173/path?q=a").path, "/path")
        XCTAssertTrue(PreviewAddress.isLoopback(try PreviewAddress.url("http://[::1]:8000")))
        XCTAssertFalse(PreviewAddress.isLoopback(try PreviewAddress.url("https://example.com")))
        for invalid in ["", "0", "65536", "https://localhost:99999", "file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.com"] {
            XCTAssertThrowsError(try PreviewAddress.url(invalid), invalid)
        }
    }
    @MainActor func testFileBrowserReusesItsTabAndKeepsOtherPanels() {
        let session = SidePanelSession()
        session.open(.files); session.open(.file("Sources/main.swift"))
        XCTAssertEqual(session.tabs, [.tasks, .file("Sources/main.swift")])
        session.open(.file("Sources/main.swift"))
        XCTAssertEqual(session.tabs.count, 2)
        let fileTabID = session.selection.id
        session.open(.review); session.open(.file("README.md"))
        XCTAssertEqual(session.tabs, [.tasks, .file("README.md"), .review])
        XCTAssertEqual(session.selection.id, fileTabID)
        session.open(.review); session.open(.files)
        XCTAssertEqual(session.selection, .file("README.md"))
        XCTAssertEqual(session.tabs.count, 3)
        session.open(.review); session.close(.review)
        XCTAssertEqual(session.selection, .file("README.md"))
        session.close(.tasks); session.close(.file("README.md"))
        XCTAssertEqual(session.tabs, [.files]); XCTAssertEqual(session.selection, .files)
    }
    @MainActor func testContextsKeepTheirOwnTabs() {
        let store = SidePanelStore()
        let first = PanelContext(host: .local, workspaceID: "w", cwd: "/one", base: nil)
        let second = PanelContext(host: .local, workspaceID: "w", cwd: "/worktree", base: nil)
        store.session(for: first).open(.file("README.md"))
        XCTAssertEqual(store.session(for: second).selection, .tasks)
        XCTAssertEqual(store.session(for: first).selection, .file("README.md"))
    }
}
