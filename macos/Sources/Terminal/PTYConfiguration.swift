import Foundation

struct PTYConfiguration: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?
    let columns: UInt16
    let rows: UInt16

    init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = SanitizedEnvironment.terminal(),
        workingDirectory: String? = nil,
        columns: UInt16 = 80,
        rows: UInt16 = 24
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
    }

    static func loginZsh(
        workingDirectory: String? = nil,
        columns: UInt16 = 80,
        rows: UInt16 = 24
    ) -> PTYConfiguration {
        var environment = SanitizedEnvironment.terminal()
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        return PTYConfiguration(
            executable: "/bin/zsh",
            arguments: ["-l"],
            environment: environment,
            workingDirectory: workingDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser.path,
            columns: columns,
            rows: rows
        )
    }
}
