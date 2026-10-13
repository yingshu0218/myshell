import CryptoKit
import Foundation

private struct ConnectionPayloadV1: Codable {
    let schemaVersion: Int
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let user: String
    let proxyJump: String?
    let groupName: String
    let tags: [String]
    let notes: String
    let terminalProfileId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, host, port, user, proxyJump, groupName
        case tags, notes, terminalProfileId, createdAt, updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(user, forKey: .user)
        if let proxyJump {
            try container.encode(proxyJump, forKey: .proxyJump)
        } else {
            try container.encodeNil(forKey: .proxyJump)
        }
        try container.encode(groupName, forKey: .groupName)
        try container.encode(tags, forKey: .tags)
        try container.encode(notes, forKey: .notes)
        if let terminalProfileId {
            try container.encode(terminalProfileId, forKey: .terminalProfileId)
        } else {
            try container.encodeNil(forKey: .terminalProfileId)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum ConnectionSyncError: LocalizedError, Equatable {
    case unsupportedCollection
    case invalidMetadata
    case missingEncryptedContent
    case invalidSchema(String)
    case recordIDMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedCollection: "The sync page contains an unsupported collection."
        case .invalidMetadata: "The sync record metadata is invalid."
        case .missingEncryptedContent: "The sync record is missing encrypted content."
        case .invalidSchema(let field):
            "The decrypted connection has an invalid \(field) field."
        case .recordIDMismatch: "The encrypted connection ID does not match its record ID."
        }
    }
}

enum ConnectionSyncCodec {
    static let collection = "connections"
    static let schemaID = "connection-v1"

    static func encode(_ record: ConnectionRecord) throws -> Data {
        let payload = ConnectionPayloadV1(
            schemaVersion: 1,
            id: record.id,
            name: record.name,
            host: record.host,
            port: record.port,
            user: record.user,
            proxyJump: record.proxyJump.isEmpty ? nil : record.proxyJump,
            groupName: record.groupName,
            tags: record.tags,
            notes: record.notes,
            terminalProfileId: nil,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
        if let issue = validationIssue(payload) {
            throw ConnectionSyncError.invalidSchema(issue)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func decode(
        _ data: Data,
        expectedID: UUID,
        serverVersion: Int64
    ) throws -> ConnectionRecord {
        guard data.count <= EnvelopeCrypto.maximumPlaintextBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == expectedKeys
        else {
            throw ConnectionSyncError.invalidSchema("shape")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(ConnectionPayloadV1.self, from: data) else {
            throw ConnectionSyncError.invalidSchema("shape")
        }
        if let issue = validationIssue(payload) {
            throw ConnectionSyncError.invalidSchema(issue)
        }
        guard payload.id == expectedID else {
            throw ConnectionSyncError.recordIDMismatch
        }
        return ConnectionRecord(
            id: payload.id,
            name: payload.name,
            host: payload.host,
            user: payload.user,
            port: payload.port,
            identityFile: "",
            proxyJump: payload.proxyJump ?? "",
            groupName: payload.groupName,
            tags: payload.tags,
            notes: payload.notes,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            serverVersion: serverVersion
        )
    }

    private static let expectedKeys = Set([
        "schemaVersion", "id", "name", "host", "port", "user", "proxyJump",
        "groupName", "tags", "notes", "terminalProfileId", "createdAt", "updatedAt",
    ])

    private static func validationIssue(_ value: ConnectionPayloadV1) -> String? {
        if value.schemaVersion != 1 { return "schemaVersion" }
        if value.name.isEmpty || value.name.count > 200 { return "name" }
        if value.host.isEmpty || value.host.count > 253 { return "host" }
        if value.port < 1 || value.port > 65_535 { return "port" }
        if value.user.count > 255 { return "user" }
        if let proxyJump = value.proxyJump,
           proxyJump.isEmpty || proxyJump.count > 500 {
            return "proxyJump"
        }
        if value.groupName.count > 200 { return "groupName" }
        if value.tags.count > 64 { return "tags" }
        if Set(value.tags).count != value.tags.count { return "tags" }
        if value.tags.contains(where: { $0.isEmpty || $0.count > 100 }) {
            return "tags"
        }
        if value.notes.count > 10_000 { return "notes" }
        return nil
    }
}

struct ConnectionSyncOutbox: Sendable {
    let appID: String
    let store: SQLiteConnectionStore
    let key: Data

    func enqueueUpsert(_ record: ConnectionRecord) async throws {
        let plaintext = try ConnectionSyncCodec.encode(record)
        let nonce = AES.GCM.Nonce()
        let aad = EnvelopeCrypto.aad(
            appID: appID,
            collection: ConnectionSyncCodec.collection,
            recordID: record.id,
            schemaID: ConnectionSyncCodec.schemaID
        )
        let sealed = try EnvelopeCrypto.seal(
            plaintext: plaintext,
            key: key,
            nonce: Data(nonce),
            aad: aad
        )
        try await store.enqueueAndMarkQueued(PendingSyncOperation(
            kind: .put,
            collection: ConnectionSyncCodec.collection,
            recordID: record.id,
            baseVersion: record.serverVersion ?? 0,
            encryptedPayload: sealed.payload,
            checksum: sealed.checksum
        ))
    }

    func enqueueDelete(recordID: UUID, baseVersion: Int64) async throws {
        try await store.enqueueAndMarkQueued(PendingSyncOperation(
            kind: .delete,
            collection: ConnectionSyncCodec.collection,
            recordID: recordID,
            baseVersion: baseVersion
        ))
    }
}

struct ConnectionEnvelopeApplier: SyncEnvelopeApplying {
    let appID: String
    let store: SQLiteConnectionStore
    let key: Data

    func apply(_ changes: [SyncRecordEnvelope]) async throws {
        var mutations: [SyncedConnectionMutation] = []
        mutations.reserveCapacity(changes.count)
        for change in changes {
            guard change.appID == appID,
                  change.collection == ConnectionSyncCodec.collection,
                  let recordID = UUID(uuidString: change.recordID),
                  change.version > 0 else {
                throw change.collection == ConnectionSyncCodec.collection
                    ? ConnectionSyncError.invalidMetadata
                    : ConnectionSyncError.unsupportedCollection
            }
            if change.deleted {
                mutations.append(.delete(
                    recordID: recordID,
                    version: change.version,
                    updatedAt: change.updatedAt
                ))
                continue
            }
            guard let payload = change.payload, let checksum = change.checksum else {
                throw ConnectionSyncError.missingEncryptedContent
            }
            let aad = EnvelopeCrypto.aad(
                appID: appID,
                collection: change.collection,
                recordID: recordID,
                schemaID: ConnectionSyncCodec.schemaID
            )
            let plaintext = try EnvelopeCrypto.open(
                payload: payload,
                checksum: checksum,
                key: key,
                aad: aad
            )
            mutations.append(.upsert(try ConnectionSyncCodec.decode(
                plaintext,
                expectedID: recordID,
                serverVersion: change.version
            )))
        }
        try await store.applySyncedConnections(mutations)
    }
}
