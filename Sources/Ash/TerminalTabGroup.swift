import Foundation

struct TerminalTabGroup: Codable, Hashable, Identifiable {
    var id: String
    var layout: TerminalLayout
    var focusedRunID: String
    var runIDs: [String] { layout.runIDs }
    var isSplit: Bool { runIDs.count > 1 }

    static func single(_ id: String) -> Self {
        Self(id: "tab-\(id)", layout: .pane(id), focusedRunID: id)
    }
    func keeping(_ available: Set<String>) -> Self? {
        guard let retained = layout.keeping(available) else { return nil }
        var seen = Set<String>()
        let ids = retained.runIDs.filter { seen.insert($0).inserted }
        let clean = retained.runIDs == ids ? retained : TerminalLayout.horizontal(ids)!
        return Self(id: id, layout: clean, focusedRunID: ids.contains(focusedRunID) ? focusedRunID : ids[0])
    }
}
