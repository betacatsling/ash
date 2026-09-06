import Foundation

@main struct TerminalEnvironmentChecks {
    static func shell(_ command: String, environment: [String: String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.environment = environment
        process.arguments = ["-c", command]
        process.standardOutput = output
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        return String(decoding: result, as: UTF8.self)
    }

    static func main() throws {
        let inherited = [
            "NO_COLOR": "1", "FORCE_COLOR": "0", "CLICOLOR_FORCE": "0", "CLICOLOR": "0",
            "TERM": "dumb", "COLORTERM": "", "TERM_PROGRAM": "parent", "TERM_PROGRAM_VERSION": "999",
            "PATH": "/custom/bin", "SSH_AUTH_SOCK": "/tmp/agent", "LANG": "zh_CN.UTF-8", "CUSTOM": "kept",
        ]
        let environment = TerminalEnvironment.make(from: inherited)
        for key in TerminalEnvironment.colorOverrides { precondition(environment[key] == nil) }
        precondition(environment["TERM"] == "xterm-256color")
        precondition(environment["COLORTERM"] == "truecolor")
        precondition(environment["CLICOLOR"] == "1")
        precondition(environment["TERM_PROGRAM"] == "Ash")
        precondition(environment["TERM_PROGRAM_VERSION"] != "999")
        for key in ["PATH", "SSH_AUTH_SOCK", "LANG", "CUSTOM"] {
            precondition(environment[key] == inherited[key])
        }
        precondition(inherited["NO_COLOR"] == "1")
        precondition(RuntimeClient.environment["NO_COLOR"] == ProcessInfo.processInfo.environment["NO_COLOR"])
        print("PASS terminal color policy is isolated from background commands and preserves unrelated environment")

        let remote = try shell(TerminalEnvironment.remoteSetup +
            "printf '%s' \"${NO_COLOR-unset}|${FORCE_COLOR-unset}|${CLICOLOR_FORCE-unset}|$TERM|$COLORTERM|$CLICOLOR|$TERM_PROGRAM\"",
            environment: inherited)
        precondition(remote == "unset|unset|unset|xterm-256color|truecolor|1|Ash")
        let preference = try shell("export NO_COLOR=1; printf '%s' \"$NO_COLOR\"", environment: environment)
        precondition(preference == "1")
        print("PASS remote shell setup works and explicit user preferences can override defaults")
    }
}
