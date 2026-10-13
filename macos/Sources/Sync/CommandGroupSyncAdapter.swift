import CryptoKit
import Foundation

private struct CommandGroupPayloadV1: Codable {
    let schemaVersion: Int
    let id: UUID
    let name: String
    let commands: [CommandShortcut]
    let createdAt: Date
    let updatedAt: Date
}

enum CommandGroupSyncError: LocalizedError, Equatable {
    case invalidMetadata
    case missingEncryptedContent
    case invalidSchema
    case recordIDMismatch
    case unsupportedCollection

    var errorDescription: String? {
        switch self {
        case .invalidMetadata: "The synchronized command group metadata is invalid."
        case .missingEncryptedContent: "The synchronized command group has no encrypted content."
        case .invalidSchema: "The synchronized command group does not match command-group-v1."
        case .recordIDMismatch: "The command group ID does not match its record ID."
        case .unsupportedCollection: "The sync page contains an unsupported collection."
        }
    }
}

enum CommandGroupSyncCodec {
    static let collection = "command-groups"
    static let schemaID = "command-group-v1"

    static func encode(_ record: CommandGroupRecord) throws -> Data {
        let value = try record.validated()
        let payload = CommandGroupPayloadV1(
            schemaVersion: 1,
            id: value.id,
            name: value.name,
            commands: value.commands,
            createdAt: value.createdAt,
            updatedAt: value.updatedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func decode(
        _ data: Data,
        expectedID: UUID,
        serverVersion: Int64
    ) throws -> CommandGroupRecord {
        guard data.count <= EnvelopeCrypto.maximumPlaintextBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == expectedKeys,
              let rawCommands = object["commands"] as? [[String: Any]],
              rawCommands.allSatisfy({ Set($0.keys) == commandKeys })
        else {
            throw CommandGroupSyncError.invalidSchema
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(CommandGroupPayloadV1.self, from: data),
              payload.schemaVersion == 1 else {
            throw CommandGroupSyncError.invalidSchema
        }
        guard payload.id == expectedID else {
            throw CommandGroupSyncError.recordIDMismatch
        }
        do {
            return try CommandGroupRecord(
                id: payload.id,
                name: payload.name,
                commands: payload.commands,
                createdAt: payload.createdAt,
                updatedAt: payload.updatedAt,
                serverVersion: serverVersion
            ).validated()
        } catch {
            throw CommandGroupSyncError.invalidSchema
        }
    }

    private static let expectedKeys = Set([
        "schemaVersion", "id", "name", "commands", "createdAt", "updatedAt",
    ])
    private static let commandKeys = Set(["id", "name", "text"])
}

struct CommandGroupSyncOutbox: Sendable {
    let appID: String
    let store: SQLiteConnectionStore
    let key: Data

    func enqueueUpsert(_ record: CommandGroupRecord) async throws {
        let plaintext = try CommandGroupSyncCodec.encode(record)
        let aad = EnvelopeCrypto.aad(
            appID: appID,
            collection: CommandGroupSyncCodec.collection,
            recordID: record.id,
            schemaID: CommandGroupSyncCodec.schemaID
        )
        let sealed = try EnvelopeCrypto.seal(
            plaintext: plaintext,
            key: key,
            nonce: Data(AES.GCM.Nonce()),
            aad: aad
        )
        try await store.enqueueAndMarkQueued(PendingSyncOperation(
            kind: .put,
            collection: CommandGroupSyncCodec.collection,
            recordID: record.id,
            baseVersion: record.serverVersion ?? 0,
            encryptedPayload: sealed.payload,
            checksum: sealed.checksum
        ))
    }

    func enqueueDelete(recordID: UUID, baseVersion: Int64) async throws {
        try await store.enqueueAndMarkQueued(PendingSyncOperation(
            kind: .delete,
            collection: CommandGroupSyncCodec.collection,
            recordID: recordID,
            baseVersion: baseVersion
        ))
    }
}

struct MyShellEnvelopeApplier: SyncEnvelopeApplying {
    let appID: String
    let store: SQLiteConnectionStore
    let key: Data

    func apply(_ changes: [SyncRecordEnvelope]) async throws {
        var mutations: [SyncedAppMutation] = []
        mutations.reserveCapacity(changes.count)
        for change in changes {
            guard change.appID == appID,
                  let recordID = UUID(uuidString: change.recordID),
                  change.version > 0 else {
                throw CommandGroupSyncError.invalidMetadata
            }
            switch change.collection {
            case ConnectionSyncCodec.collection:
                mutations.append(try connectionMutation(change, recordID: recordID))
            case CommandGroupSyncCodec.collection:
                mutations.append(try commandGroupMutation(change, recordID: recordID))
            default:
                throw CommandGroupSyncError.unsupportedCollection
            }
        }
        try await store.applySyncedMutations(mutations)
    }

    private func connectionMutation(
        _ change: SyncRecordEnvelope,
        recordID: UUID
    ) throws -> SyncedAppMutation {
        if change.deleted {
            return .connection(.delete(
                recordID: recordID,
                version: change.version,
                updatedAt: change.updatedAt
            ))
        }
        guard let payload = change.payload, let checksum = change.checksum else {
            throw ConnectionSyncError.missingEncryptedContent
        }
        let plaintext = try EnvelopeCrypto.open(
            payload: payload,
            checksum: checksum,
            key: key,
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: change.collection,
                recordID: recordID,
                schemaID: ConnectionSyncCodec.schemaID
            )
        )
        return .connection(.upsert(try ConnectionSyncCodec.decode(
            plaintext,
            expectedID: recordID,
            serverVersion: change.version
        )))
    }

    private func commandGroupMutation(
        _ change: SyncRecordEnvelope,
        recordID: UUID
    ) throws -> SyncedAppMutation {
        if change.deleted {
            return .commandGroup(.delete(
                recordID: recordID,
                version: change.version,
                updatedAt: change.updatedAt
            ))
        }
        guard let payload = change.payload, let checksum = change.checksum else {
            throw CommandGroupSyncError.missingEncryptedContent
        }
        let plaintext = try EnvelopeCrypto.open(
            payload: payload,
            checksum: checksum,
            key: key,
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: change.collection,
                recordID: recordID,
                schemaID: CommandGroupSyncCodec.schemaID
            )
        )
        return .commandGroup(.upsert(try CommandGroupSyncCodec.decode(
            plaintext,
            expectedID: recordID,
            serverVersion: change.version
        )))
    }
}
