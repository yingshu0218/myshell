import Foundation
import Observation

@MainActor
@Observable
final class ConnectionLibrary {
    private(set) var records: [ConnectionRecord] = []
    var selectedID: UUID?
    private(set) var errorMessage: String?
    private(set) var isLoaded = false
    private(set) var reachability: [UUID: ConnectionReachability] = [:]

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

    var selectedRecord: ConnectionRecord? {
        records.first { $0.id == selectedID }
    }

    func load() async {
        guard !isLoaded, let database else {
            return
        }
        do {
            records = try await database.fetchActiveConnections()
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: SSHConnectionDraft) async -> ConnectionRecord? {
        do {
            _ = try SSHCommandBuilder.configuration(for: draft)
            var record = selectedRecord ?? ConnectionRecord(draft: draft)
            record.name = draft.displayName
            record.host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
            record.user = draft.user.trimmingCharacters(in: .whitespacesAndNewlines)
            record.port = draft.port
            record.identityFile = draft.identityFile.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            record.proxyJump = draft.proxyJump.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            record.groupName = draft.groupName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            record.tags = draft.normalizedTags
            record.notes = draft.notes
            record.updatedAt = .now

            guard let database else {
                throw DatabaseError.open("database unavailable")
            }
            try await database.upsert(record)
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index] = record
            } else {
                records.append(record)
            }
            records.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            selectedID = record.id
            errorMessage = nil
            return record
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteSelected() async {
        guard let selectedID, let database else {
            return
        }
        do {
            try await database.markDeleted(id: selectedID)
            records.removeAll { $0.id == selectedID }
            self.selectedID = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportArchive() throws -> Data {
        try ConnectionArchiveCodec.encode(records)
    }

    func importArchive(_ data: Data) async -> Bool {
        do {
            let imported = try ConnectionArchiveCodec.decode(data)
            guard let database else {
                throw DatabaseError.open("database unavailable")
            }
            try await database.importConnections(imported)
            records = try await database.fetchActiveConnections()
            selectedID = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func check(_ record: ConnectionRecord) async {
        reachability[record.id] = .checking
        reachability[record.id] = await ConnectionReachabilityChecker.check(record)
    }

    func checkAllConnections() async {
        for start in stride(from: 0, to: records.count, by: 4) {
            let end = min(start + 4, records.count)
            let batch = Array(records[start..<end])
            for record in batch {
                reachability[record.id] = .checking
            }
            await withTaskGroup(
                of: (UUID, ConnectionReachability).self
            ) { group in
                for record in batch {
                    group.addTask {
                        (
                            record.id,
                            await ConnectionReachabilityChecker.check(record)
                        )
                    }
                }
                for await (id, result) in group {
                    reachability[id] = result
                }
            }
        }
    }
}
