import Foundation

struct SyncState: Equatable, Sendable {
    let appID: String
    var cursor: String?
    var lastSuccessfulSyncAt: Date?
}

enum PendingSyncOperationKind: String, Codable, Sendable {
    case put
    case delete
}

struct PendingSyncOperation: Equatable, Sendable {
    static let maximumQueuedOperations = 1_000

    let id: UUID
    let kind: PendingSyncOperationKind
    let collection: String
    let recordID: UUID
    let baseVersion: Int64
    let encryptedPayload: Data?
    let checksum: String?
    let idempotencyKey: UUID
    let createdAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        kind: PendingSyncOperationKind,
        collection: String,
        recordID: UUID,
        baseVersion: Int64,
        encryptedPayload: Data? = nil,
        checksum: String? = nil,
        idempotencyKey: UUID = UUID(),
        createdAt: Date = .now,
        retryCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.collection = collection
        self.recordID = recordID
        self.baseVersion = baseVersion
        self.encryptedPayload = encryptedPayload
        self.checksum = checksum
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}

struct StoredSyncConflict: Identifiable, Equatable, Sendable {
    var id: UUID { operationID }
    let operationID: UUID
    let collection: String
    let recordID: UUID
    let remote: SyncRecordEnvelope
    let detectedAt: Date
}
