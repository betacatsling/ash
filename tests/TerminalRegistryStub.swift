import Foundation

// Replace only the native terminal view; keep store, persistence, transport and SSH real.
@MainActor final class TerminalRegistry {
    static let shared = TerminalRegistry()
    var failed: Set<String> = []
    var closed: [String] = []
    func close(_ id: String) { failed.remove(id); closed.append(id) }
    func hasEnded(_ id: String) -> Bool { failed.contains(id) }
    func isStable(_ id: String) -> Bool { false }
    func focus(id: String) {}
}
