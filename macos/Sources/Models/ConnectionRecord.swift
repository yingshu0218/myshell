import Foundation

struct ConnectionRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var user: String
    var port: Int
    var identityFile: String
    var proxyJump: String
    var groupName: String
    var tags: [String]
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var serverVersion: Int64?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        user: String = "",
        port: Int = 22,
        identityFile: String = "",
        proxyJump: String = "",
        groupName: String = "",
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        serverVersion: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.proxyJump = proxyJump
        self.groupName = groupName
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverVersion = serverVersion
    }

    init(draft: SSHConnectionDraft) {
        self.init(
            name: draft.displayName,
            host: draft.host.trimmingCharacters(in: .whitespacesAndNewlines),
            user: draft.user.trimmingCharacters(in: .whitespacesAndNewlines),
            port: draft.port,
            identityFile: draft.identityFile.trimmingCharacters(in: .whitespacesAndNewlines),
            proxyJump: draft.proxyJump.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: draft.groupName.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draft.normalizedTags,
            notes: draft.notes
        )
    }

    var draft: SSHConnectionDraft {
        SSHConnectionDraft(
            name: name,
            host: host,
            user: user,
            port: port,
            identityFile: identityFile,
            proxyJump: proxyJump,
            groupName: groupName,
            tags: tags.joined(separator: ", "),
            notes: notes
        )
    }
}
