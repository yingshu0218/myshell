import Foundation
import Observation

@MainActor
@Observable
final class CommandGroupLibrary {
    private(set) var groups: [CommandGroupRecord] = []
    var selectedID: UUID?
    private(set) var errorMessage: String?
    private(set) var isLoaded = false

    @ObservationIgnored private let database: SQLiteConnectionStore?

    init(databaseURL: URL? = nil) {
        do {
            let url = try databaseURL ?? ApplicationPaths.databaseURL()
            database = try SQLiteConnectionStore(url: url)
        } catch {
            database = nil
            errorMessage = error.localizedDescription
        }
    }

    var selectedGroup: CommandGroupRecord? {
        groups.first { $0.id == selectedID }
    }

    func load() async {
        guard let database else { return }
        do {
            groups = try await database.fetchActiveCommandGroups()
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(_ group: CommandGroupRecord) async -> Bool {
        do {
            var value = try group.validated()
            value.updatedAt = .now
            guard let database else {
                throw DatabaseError.open("database unavailable")
            }
            try await database.upsertCommandGroup(value)
            if let index = groups.firstIndex(where: { $0.id == value.id }) {
                groups[index] = value
            } else {
                groups.append(value)
            }
            groups.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            selectedID = value.id
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSelected() async {
        guard let selectedID, let database else { return }
        do {
            try await database.markCommandGroupDeleted(id: selectedID)
            groups.removeAll { $0.id == selectedID }
            self.selectedID = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
