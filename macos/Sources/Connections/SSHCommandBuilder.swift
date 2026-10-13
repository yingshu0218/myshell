import Foundation

enum SSHConfigurationError: LocalizedError, Equatable {
    case invalidHost
    case invalidUser
    case invalidPort
    case invalidIdentityFile
    case invalidProxyJump

    var errorDescription: String? {
        switch self {
        case .invalidHost: "Enter a valid host name or address."
        case .invalidUser: "The user name contains unsupported characters."
        case .invalidPort: "The port must be between 1 and 65535."
        case .invalidIdentityFile: "The identity file must use an absolute path."
        case .invalidProxyJump: "The ProxyJump value is invalid."
        }
    }
}

enum SSHCommandBuilder {
    static func configuration(
        for draft: SSHConnectionDraft
    ) throws -> PTYConfiguration {
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = draft.user.trimmingCharacters(in: .whitespacesAndNewlines)
        let identityFile = NSString(
            string: draft.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        ).expandingTildeInPath
        let proxyJump = draft.proxyJump.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isSafeHost(host) else {
            throw SSHConfigurationError.invalidHost
        }
        guard user.isEmpty || isSafeUser(user) else {
            throw SSHConfigurationError.invalidUser
        }
        guard (1...65_535).contains(draft.port) else {
            throw SSHConfigurationError.invalidPort
        }
        guard identityFile.isEmpty || identityFile.hasPrefix("/") else {
            throw SSHConfigurationError.invalidIdentityFile
        }
        guard proxyJump.isEmpty || isSafeDestination(proxyJump) else {
            throw SSHConfigurationError.invalidProxyJump
        }

        var arguments = [
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-p", String(draft.port),
        ]
        if !identityFile.isEmpty {
            arguments += ["-i", identityFile]
        }
        if !proxyJump.isEmpty {
            arguments += ["-J", proxyJump]
        }
        arguments.append(user.isEmpty ? host : "\(user)@\(host)")

        var environment = SanitizedEnvironment.terminal()
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"

        return PTYConfiguration(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    private static func isSafeHost(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-") else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: ".:-_[]"))
                .contains($0)
        }
    }

    private static func isSafeUser(_ value: String) -> Bool {
        guard !value.hasPrefix("-") else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }

    private static func isSafeDestination(_ value: String) -> Bool {
        guard !value.hasPrefix("-"), !value.contains(where: \.isWhitespace) else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "@.:-_[],"))
                .contains($0)
        }
    }
}
