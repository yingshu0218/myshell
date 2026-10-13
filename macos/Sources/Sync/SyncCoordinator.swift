import Foundation

protocol SyncHubServing: Sendable {
    func changes(
        cursor: String?,
        limit: Int,
        token: Data
    ) async throws -> SyncChangesPage

    func get(
        collection: String,
        recordID: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope

    func put(
        collection: String,
        recordID: UUID,
        request: SyncWriteRequest,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope

    func delete(
        collection: String,
        recordID: UUID,
        baseVersion: Int64,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope
}

extension SyncHubClient: SyncHubServing {}

protocol SyncEnvelopeApplying: Sendable {
    func apply(_ changes: [SyncRecordEnvelope]) async throws
}

actor SyncCoordinator {
    private let appID: String
    private let store: SQLiteConnectionStore
    private let hub: any SyncHubServing
    private let applier: any SyncEnvelopeApplying

    init(
        appID: String,
        store: SQLiteConnectionStore,
        hub: any SyncHubServing,
        applier: any SyncEnvelopeApplying
    ) {
        self.appID = appID
        self.store = store
        self.hub = hub
        self.applier = applier
    }

    @discardableResult
    func pullOnce(token: Data) async throws -> SyncState {
        let current = try await store.syncState(appID: appID)
        let page = try await hub.changes(
            cursor: current.cursor,
            limit: 32,
            token: token
        )

        // The cursor is deliberately committed only after the entire page has
        // been validated, decrypted, and durably applied by the contract layer.
        try await applier.apply(page.changes)
        try await store.commitSyncCursor(appID: appID, cursor: page.cursor)
        return try await store.syncState(appID: appID)
    }

    @discardableResult
    func pullUntilCaughtUp(token: Data) async throws -> SyncState {
        while true {
            let current = try await store.syncState(appID: appID)
            let page = try await hub.changes(
                cursor: current.cursor,
                limit: 32,
                token: token
            )
            try await applier.apply(page.changes)
            try await store.commitSyncCursor(appID: appID, cursor: page.cursor)
            if page.changes.count < 32 {
                return try await store.syncState(appID: appID)
            }
        }
    }

    @discardableResult
    func pushPending(token: Data) async throws -> Int {
        let operations = try await store.pendingOperations(limit: 32)
        var completed = 0
        for operation in operations {
            let response: SyncRecordEnvelope
            do {
                switch operation.kind {
                case .put:
                    guard let payload = operation.encryptedPayload,
                          let checksum = operation.checksum else {
                        throw DatabaseError.decode(
                            "pending write is missing encrypted content"
                        )
                    }
                    response = try await hub.put(
                        collection: operation.collection,
                        recordID: operation.recordID,
                        request: SyncWriteRequest(
                            baseVersion: operation.baseVersion,
                            payload: payload,
                            checksum: checksum
                        ),
                        idempotencyKey: operation.idempotencyKey,
                        token: token
                    )
                case .delete:
                    response = try await hub.delete(
                        collection: operation.collection,
                        recordID: operation.recordID,
                        baseVersion: operation.baseVersion,
                        idempotencyKey: operation.idempotencyKey,
                        token: token
                    )
                }
            } catch SyncHubError.conflict {
                let remote = try await hub.get(
                    collection: operation.collection,
                    recordID: operation.recordID,
                    token: token
                )
                try await store.saveConflict(
                    operationID: operation.id,
                    remote: remote
                )
                throw SyncHubError.conflict
            }

            // A successful server response is durably applied before the queue
            // item is removed. Retries keep the same idempotency key.
            try await applier.apply([response])
            try await store.removePendingOperation(id: operation.id)
            completed += 1
        }
        return completed
    }
}
