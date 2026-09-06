import XCTest
@testable import Ash

final class ModelTests: XCTestCase {
    func testSSHAddressRejectsOptionAndCommandInjection() {
        for invalid in ["", "-oProxyCommand=evil", "user@host;id", "host\ncommand", "$(id)", "a b"] { XCTAssertFalse(validSSHAddress(invalid), invalid) }
        for valid in ["dev-server", "user@host.example", "user@[::1]"] { XCTAssertTrue(validSSHAddress(valid), valid) }
    }
    func testShellQuotingProtectsSpacesApostrophesAndSubstitution() {
        XCTAssertEqual(shellQuote("a'b $(id)\nnext"), "'a'\\''b $(id)\nnext'")
    }
    func testRemoteExecutableCannotEscapeShellArgument() {
        let h = Host(name: "test", address: "test", runtimePath: ".local/bin/ash' x")
        XCTAssertTrue(RuntimeClient.remoteRuntime(h).contains("$HOME/'.local/bin/ash'\\'' x' request"))
    }
    func testExitIsNotTaskCompletion() throws {
        let data = Data("""
        {"id":"r","taskId":"t","workspaceId":"w","title":"task","agent":"pi","prompt":"","cwd":"/tmp","session":"ash-r","status":"exited","createdAt":1,"exitCode":0,"archived":false}
        """.utf8)
        let r = try JSONDecoder().decode(Run.self, from:data)
        XCTAssertFalse(r.active); XCTAssertEqual(r.label,"已退出 · 待检查")
    }
}
