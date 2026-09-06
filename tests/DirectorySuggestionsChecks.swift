import Darwin
import Foundation

actor DelayedDirectoryProvider: DirectoryListingProvider {
    private var pending: CheckedContinuation<DirectoryListing, Never>?
    func waiting() -> Bool { pending != nil }
    func finish() { pending?.resume(returning: DirectoryListing(directory: "/old", resolvedPath: "/old", entries: [], truncated: false)); pending = nil }
    func list(_ query: DirectoryQuery) async throws -> DirectoryListing {
        if query.input == "old" { return await withCheckedContinuation { pending = $0 } }
        return DirectoryListing(directory: "/new", resolvedPath: "/new", entries: [], truncated: false)
    }
}

@main struct DirectorySuggestionsChecks {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ash-directories-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for name in ["alpha", "alpine", "中文 ' folder", "line\nbreak", "trailing\n", ".hidden", "dollar$(literal)"] {
            try manager.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("file, not a folder".utf8).write(to: root.appendingPathComponent("ordinary-file"))
        try manager.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: root.appendingPathComponent("alpha").path)
        let service = DirectoryListingService()
        let full = try await service.list(DirectoryQuery(host: .local, input: root.path + "/"))
        precondition(full.resolvedPath != nil && full.entries.count == 7)
        precondition(!full.entries.contains { $0.name == "ordinary-file" || $0.name == ".hidden" })
        let partial = try await service.list(DirectoryQuery(host: .local, input: root.path + "/al"))
        precondition(partial.resolvedPath == nil && partial.entries.map(\.name) == ["alpha", "alpine"])
        let hidden = try await service.list(DirectoryQuery(host: .local, input: root.path + "/.h"))
        precondition(hidden.entries.map(\.name) == [".hidden"])
        for name in ["中文 ' folder", "line\nbreak", "trailing\n", "dollar$(literal)"] {
            let result = try await service.list(DirectoryQuery(host: .local, input: root.appendingPathComponent(name).path))
            precondition(result.resolvedPath?.hasSuffix(name) == true)
        }
        let home = try await service.list(DirectoryQuery(host: .local, input: "~/"))
        precondition(home.resolvedPath == URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path)
        let empty = try await service.list(DirectoryQuery(host: .local, input: ""))
        precondition(empty.resolvedPath == home.resolvedPath)
        let rootListing = try await service.list(DirectoryQuery(host: .local, input: "/"))
        precondition(rootListing.resolvedPath == "/" && rootListing.entries.allSatisfy { !$0.path.hasPrefix("//") })
        for input in ["relative", root.path + "/absent/", "bad\0path"] {
            do { _ = try await service.list(DirectoryQuery(host: .local, input: input)); fatalError("Invalid path accepted") } catch {}
        }
        let many = root.appendingPathComponent("many")
        try manager.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<205 { try manager.createDirectory(at: many.appendingPathComponent("dir-\(index)"), withIntermediateDirectories: true) }
        let limited = try await service.list(DirectoryQuery(host: .local, input: many.path))
        precondition(limited.truncated && limited.entries.count == 200)
        do { _ = try DirectoryListingService.decode(Data("ASH_DIRECTORIES\0/\0/\0".utf8)); fatalError("Truncated frame accepted") } catch {}

        let provider = DelayedDirectoryProvider()
        let model = DirectorySuggestions(provider: provider)
        let old = Task { await model.load(DirectoryQuery(host: .local, input: "old"), debounce: false) }
        while !(await provider.waiting()) { await Task.yield() }
        let next = DirectoryQuery(host: Host(name: "Another host", address: "fixture"), input: "new")
        await model.load(next, debounce: false)
        await provider.finish()
        await old.value
        precondition(model.query == next && model.listing?.directory == "/new" && model.error == nil && !model.loading)
        print("PASS directory suggestions: real directories, partial paths, home/root navigation, Unicode/quotes/newlines, hidden folders, symlinks, bounded results, invalid paths, stale response protection")

        if let address = ProcessInfo.processInfo.environment["ASH_DIRECTORY_REMOTE"],
           let remoteRoot = ProcessInfo.processInfo.environment["ASH_DIRECTORY_PATH"] {
            let host = Host(name: "SSH fixture", address: address, managed: false, runtimePath: "/missing-runtime")
            let remote = try await service.list(DirectoryQuery(host: host, input: remoteRoot))
            // Foundation can preserve the /tmp alias; compare against POSIX physical cwd,
            // the same contract returned by the remote shell's cd -P.
            guard let physical = realpath(remoteRoot, nil) else { fatalError("Missing SSH fixture") }
            let expected = String(cString: physical)
            free(physical)
            precondition(remote.resolvedPath == expected, "Remote: \(remote.resolvedPath ?? "nil") / Expected: \(expected)")
            let remoteHome = try await service.list(DirectoryQuery(host: host, input: "~/"))
            precondition(remoteHome.resolvedPath?.hasPrefix("/") == true)
            print("PASS real SSH directory browsing and remote home resolution without a managed runtime")
        }
    }
}
