import Foundation

enum AppPaths {
    static var dataDirectory: URL {
        ProcessInfo.processInfo.environment["ASH_APP_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ash")
    }
}

/// Both client stores use atomic JSON writes and preserve files that failed to load.
final class JSONFileStore<Value: Codable> {
    private let url: URL
    private var loadError: Error?

    init(url: URL) { self.url = url }

    func load() throws -> Value? {
        do {
            let value =
                FileManager.default.fileExists(atPath: url.path)
                ? try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) : nil
            loadError = nil
            return value
        } catch {
            loadError = error
            throw error
        }
    }

    func save(_ value: Value) throws {
        // A failed read must not turn the fallback in-memory state into a destructive write.
        if let loadError { throw loadError }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
