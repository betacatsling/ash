import Darwin
import Foundation

/// Discover static aliases only. OpenSSH still evaluates Host/Match and connection options.
/// In particular, discovery never executes Match exec or a shell command from the config.
enum SSHConfigDiscovery {
    static func aliases(at url: URL? = nil) -> [String] {
        let directory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        let file =
            url ?? ProcessInfo.processInfo.environment["ASH_SSH_CONFIG"].map { URL(fileURLWithPath: $0) }
            ?? directory.appendingPathComponent("config")
        var visited = Set<URL>()
        var aliases = Set<String>()
        func visit(_ file: URL, depth: Int) {
            let file = file.standardizedFileURL.resolvingSymlinksInPath()
            guard depth < 12, visited.count < 128, visited.insert(file).inserted,
                let handle = try? FileHandle(forReadingFrom: file)
            else { return }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: 1_048_577), data.count <= 1_048_576,
                let text = String(data: data, encoding: .utf8)
            else { return }
            for line in text.split(separator: "\n") {
                let fields = tokens(String(line))
                guard let directive = fields.first?.lowercased() else { continue }
                if directive == "host" {
                    for alias in fields.dropFirst() where validSSHAddress(alias) { aliases.insert(alias) }
                } else if directive == "include" {
                    for pattern in fields.dropFirst() {
                        let path = (pattern as NSString).expandingTildeInPath
                        let absolute = path.hasPrefix("/") ? path : directory.appendingPathComponent(path).path
                        var matches = glob_t()
                        defer { globfree(&matches) }
                        if glob(absolute, 0, nil, &matches) == 0, let paths = matches.gl_pathv {
                            for index in 0..<min(Int(matches.gl_pathc), 128) {
                                if let path = paths[index] {
                                    visit(URL(fileURLWithPath: String(cString: path)), depth: depth + 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        visit(file, depth: 0)
        return aliases.sorted()
    }

    private static func tokens(_ line: String) -> [String] {
        var result: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                token.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let delimiter = quote {
                if character == delimiter { quote = nil } else { token.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                break
            } else if character.isWhitespace
                || (character == "=" && (result.isEmpty || (result.count == 1 && token.isEmpty)))
            {
                if !token.isEmpty {
                    result.append(token)
                    token = ""
                }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty && quote == nil { result.append(token) }
        // Whitespace around the optional '=' is accepted by OpenSSH.
        return result.filter { $0 != "=" }
    }
}
