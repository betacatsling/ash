import Foundation

/// A terminal owns its capabilities; a GUI launcher or background job does not.
/// Keep this policy in sync with runtime/src/terminal_environment.rs, which also
/// protects new processes from the environment retained by an older tmux server.
enum TerminalEnvironment {
    static let colorOverrides = ["NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE"]
    static let capabilities = [
        "TERM": "xterm-256color", "COLORTERM": "truecolor", "CLICOLOR": "1", "TERM_PROGRAM": "Ash",
    ]

    static func make(from inherited: [String: String]) -> [String: String] {
        var environment = inherited
        for key in colorOverrides { environment.removeValue(forKey: key) }
        environment.merge(capabilities) { _, value in value }
        environment.removeValue(forKey: "TERM_PROGRAM_VERSION")
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            environment["TERM_PROGRAM_VERSION"] = version
        }
        return environment
    }

    /// SSH only forwards TERM for a PTY by default. Establish the same boundary
    /// remotely, before the user's login shell can apply its own preferences.
    static var remoteSetup: String {
        "unset \(colorOverrides.joined(separator: " ")); export "
            + capabilities.keys.sorted().map { "\($0)=\(shellQuote(capabilities[$0]!))" }.joined(separator: " ")
            + "; unset TERM_PROGRAM_VERSION; "
    }
}
