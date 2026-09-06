import Combine
import Foundation

struct DirectoryQuery: Equatable {
    let host: Host
    let input: String
}

struct DirectorySuggestion: Identifiable, Equatable {
    let path: String
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

struct DirectoryListing: Equatable {
    let directory: String
    let resolvedPath: String?
    let entries: [DirectorySuggestion]
    let truncated: Bool
}

protocol DirectoryListingProvider: Sendable {
    func list(_ query: DirectoryQuery) async throws -> DirectoryListing
}

struct DirectoryListingService: DirectoryListingProvider {
    // Use the same portable, read-only operation locally and over SSH. No remote
    // runtime upgrade or Python installation is needed to select a workspace.
    static let script = #"""
        set -eu
        input=$1
        case "$input" in
            ''|'~') input=$HOME ;;
            '~/'*) input="$HOME/${input#\~/}" ;;
            /*) ;;
            *) printf '请输入绝对路径或 ~/ 开头的路径。\n' >&2; exit 1 ;;
        esac
        resolved=''
        prefix=''
        if [ -d "$input" ]; then
            cd -P "$input" || exit 1
            directory=$PWD
            resolved=$directory
        else
            case "$input" in
                */) printf '目录不存在或无法访问。\n' >&2; exit 1 ;;
            esac
            parent=${input%/*}
            [ -n "$parent" ] || parent=/
            prefix=${input##*/}
            cd -P "$parent" || exit 1
            directory=$PWD
        fi
        printf 'ASH_DIRECTORIES\000%s\000%s\000' "$directory" "$resolved"
        count=0
        for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
            [ -d "$entry" ] || continue
            name=${entry##*/}
            case "$name" in "$prefix"*) ;; *) continue ;; esac
            case "$name" in .*) case "$prefix" in .*) ;; *) continue ;; esac ;; esac
            count=$((count + 1))
            if [ "$count" -gt 200 ]; then printf 'TRUNCATED\000'; break; fi
            # Avoid a double slash for root-directory suggestions.
            printf 'DIRECTORY\000%s/%s\000' "${directory%/}" "$name"
        done
        printf 'END\000'
        """#

    func list(_ query: DirectoryQuery) async throws -> DirectoryListing {
        let input = query.input
        guard !input.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw AshError(message: "目录路径包含无效字符。")
        }
        let arguments = ["-c", Self.script, "ash-directories", input]
        let spec: LaunchSpec
        if query.host.isLocal {
            spec = LaunchSpec(executable: "/bin/sh", arguments: arguments)
        } else {
            guard validSSHAddress(query.host.address) else { throw AshError(message: "无效的 SSH 主机地址。") }
            let command = (["sh"] + arguments).map(shellQuote).joined(separator: " ")
            spec = LaunchSpec(
                executable: "/usr/bin/ssh",
                arguments: RuntimeClient.sshOptions
                    + ["-o", "BatchMode=yes", "-T", query.host.address, command])
        }
        let output = try await RuntimeClient.execute(spec, timeoutSeconds: 20)
        return try Self.decode(output)
    }

    static func decode(_ output: Data) throws -> DirectoryListing {
        let marker = Data("ASH_DIRECTORIES\0".utf8)
        guard let start = output.range(of: marker) else { throw AshError(message: "主机未返回有效的目录列表。") }
        let fields = output[start.upperBound...].split(separator: 0, omittingEmptySubsequences: false)
        guard fields.count >= 4 else { throw AshError(message: "主机返回的目录列表不完整。") }
        let directory = String(decoding: fields[0], as: UTF8.self)
        let resolved = String(decoding: fields[1], as: UTF8.self)
        var entries: [DirectorySuggestion] = []
        var truncated = false
        var index = 2
        while index < fields.count {
            let kind = String(decoding: fields[index], as: UTF8.self)
            if kind == "END" {
                return DirectoryListing(
                    directory: directory, resolvedPath: resolved.isEmpty ? nil : resolved,
                    entries: entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    truncated: truncated)
            }
            if kind == "TRUNCATED" {
                truncated = true
                index += 1
                continue
            }
            guard kind == "DIRECTORY", index + 1 < fields.count else { break }
            entries.append(DirectorySuggestion(path: String(decoding: fields[index + 1], as: UTF8.self)))
            index += 2
        }
        throw AshError(message: "主机返回的目录列表不完整。")
    }
}

@MainActor final class DirectorySuggestions: ObservableObject {
    @Published private(set) var query: DirectoryQuery?
    @Published private(set) var listing: DirectoryListing?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private let provider: any DirectoryListingProvider
    private var generation = UUID()

    init(provider: any DirectoryListingProvider = DirectoryListingService()) { self.provider = provider }

    func load(_ query: DirectoryQuery, debounce: Bool = true) async {
        let token = UUID()
        generation = token
        self.query = query
        listing = nil
        error = nil
        loading = true
        defer { if generation == token { loading = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(220)) }
            try Task.checkCancellation()
            let result = try await provider.list(query)
            guard generation == token, !Task.isCancelled else { return }
            listing = result
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
