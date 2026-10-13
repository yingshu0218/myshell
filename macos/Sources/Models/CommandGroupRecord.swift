import Foundation

struct CommandShortcut: Identifiable, Codable, Equatable, Sendable {
    static let maximumNameLength = 200
    static let maximumTextLength = 10_000

    var id: UUID
    var name: String
    var text: String

    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        self.name = name
        self.text = text
    }
}

struct CommandGroupRecord: Identifiable, Codable, Equatable, Sendable {
    static let maximumNameLength = 200
    static let maximumCommands = 100
    static let maximumBatchBytes = 256 * 1024

    var id: UUID
    var name: String
    var commands: [CommandShortcut]
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64?

    init(
        id: UUID = UUID(),
        name: String,
        commands: [CommandShortcut] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.commands = commands
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
    }

    func validated() throws -> CommandGroupRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= Self.maximumNameLength else {
            throw CommandGroupError.invalidGroupName
        }
        guard commands.count <= Self.maximumCommands else {
            throw CommandGroupError.tooManyCommands
        }
        var seen = Set<UUID>()
        for command in commands {
            let name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= CommandShortcut.maximumNameLength else {
                throw CommandGroupError.invalidCommandName
            }
            guard !command.text.isEmpty,
                  command.text.count <= CommandShortcut.maximumTextLength else {
                throw CommandGroupError.invalidCommandText
            }
            guard seen.insert(command.id).inserted else {
                throw CommandGroupError.duplicateCommandID
            }
        }
        guard try executionPayload().count <= Self.maximumBatchBytes else {
            throw CommandGroupError.batchTooLarge
        }
        var result = self
        result.name = trimmedName
        result.commands = commands.map {
            CommandShortcut(
                id: $0.id,
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                text: $0.text
            )
        }
        return result
    }

    func executionPayload() throws -> Data {
        var result = Data()
        for command in commands {
            guard let data = command.text.data(using: .utf8) else {
                throw CommandGroupError.invalidCommandText
            }
            result.append(data)
            if !command.text.hasSuffix("\n") {
                result.append(0x0A)
            }
            guard result.count <= Self.maximumBatchBytes else {
                throw CommandGroupError.batchTooLarge
            }
        }
        return result
    }
}

enum CommandGroupError: LocalizedError, Equatable {
    case invalidGroupName
    case tooManyCommands
    case invalidCommandName
    case invalidCommandText
    case duplicateCommandID
    case batchTooLarge
    case terminalUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidGroupName: "Enter a group name between 1 and 200 characters."
        case .tooManyCommands: "A group can contain at most 100 commands."
        case .invalidCommandName: "Enter a command name between 1 and 200 characters."
        case .invalidCommandText: "Command text must be between 1 and 10,000 characters."
        case .duplicateCommandID: "A command group contains duplicate command identifiers."
        case .batchTooLarge: "The combined command batch exceeds 256 KiB."
        case .terminalUnavailable: "Open and select a running terminal first."
        }
    }
}
