import Foundation

struct SSHConnectionDraft: Equatable, Sendable {
    var name = ""
    var host = ""
    var user = ""
    var port = 22
    var identityFile = ""
    var proxyJump = ""
    var groupName = ""
    var tags = ""
    var notes = ""

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? host : trimmedName
    }

    var normalizedTags: [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
