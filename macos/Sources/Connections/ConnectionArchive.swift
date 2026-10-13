import Foundation

struct ConnectionArchive: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let exportedAt: Date
    let connections: [ConnectionRecord]
}

enum ConnectionArchiveError: LocalizedError, Equatable {
    case tooLarge
    case unsupportedVersion
    case tooManyRecords
    case duplicateIdentifier
    case invalidConnection(String)
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .tooLarge: "The import file exceeds the 5 MiB limit."
        case .unsupportedVersion: "This connection archive version is not supported."
        case .tooManyRecords: "A connection archive can contain at most 1,000 records."
        case .duplicateIdentifier: "The archive contains duplicate connection IDs."
        case .invalidConnection(let name): "The connection “\(name)” is invalid."
        case .invalidDocument: "The selected file is not a valid MyShell archive."
        }
    }
}

enum ConnectionArchiveCodec {
    static let maximumBytes = 5 * 1_024 * 1_024
    static let maximumRecords = 1_000

    static func encode(
        _ records: [ConnectionRecord],
        at date: Date = .now
    ) throws -> Data {
        guard records.count <= maximumRecords else {
            throw ConnectionArchiveError.tooManyRecords
        }
        let archive = ConnectionArchive(
            schemaVersion: ConnectionArchive.schemaVersion,
            exportedAt: date,
            connections: records.filter { $0.deletedAt == nil }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else {
            throw ConnectionArchiveError.tooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> [ConnectionRecord] {
        guard data.count <= maximumBytes else {
            throw ConnectionArchiveError.tooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(ConnectionArchive.self, from: data) else {
            throw ConnectionArchiveError.invalidDocument
        }
        guard archive.schemaVersion == ConnectionArchive.schemaVersion else {
            throw ConnectionArchiveError.unsupportedVersion
        }
        guard archive.connections.count <= maximumRecords else {
            throw ConnectionArchiveError.tooManyRecords
        }
        guard Set(archive.connections.map(\.id)).count == archive.connections.count else {
            throw ConnectionArchiveError.duplicateIdentifier
        }

        return try archive.connections.map { source in
            var record = source
            record.deletedAt = nil
            record.serverVersion = nil
            do {
                _ = try SSHCommandBuilder.configuration(for: record.draft)
            } catch {
                throw ConnectionArchiveError.invalidConnection(record.name)
            }
            return record
        }
    }
}
