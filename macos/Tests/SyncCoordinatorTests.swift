import Foundation
import XCTest
@testable import MyShell

final class SyncCoordinatorTests: XCTestCase {
    func testCommitsCursorOnlyAfterPageIsApplied() async throws {
        let fixture = try makeFixture()
        let hub = StubSyncHub(
            page: SyncChangesPage(changes: [], cursor: "next-cursor")
        )
        let applier = RecordingApplier()
        let coordinator = SyncCoordinator(
            appID: "myshell",
            store: fixture.store,
            hub: hub,
            applier: applier
        )

        let state = try await coordinator.pullOnce(token: Data("token".utf8))
        let applicationCount = await applier.applicationCount()
        let receivedCursor = await hub.receivedCursor()

        XCTAssertEqual(state.cursor, "next-cursor")
        XCTAssertEqual(applicationCount, 1)
        XCTAssertNil(receivedCursor)
        await fixture.store.close()
        try FileManager.default.removeItem(at: fixture.directory)
    }

    func testFailedApplicationDoesNotAdvanceCursor() async throws {
        let fixture = try makeFixture()
        try await fixture.store.commitSyncCursor(
            appID: "myshell",
            cursor: "existing"
        )
        let coordinator = SyncCoordinator(
            appID: "myshell",
            store: fixture.store,
            hub: StubSyncHub(
                page: SyncChangesPage(changes: [], cursor: "must-not-commit")
            ),
            applier: RecordingApplier(shouldFail: true)
        )

        do {
            _ = try await coordinator.pullOnce(token: Data("token".utf8))
            XCTFail("Expected application failure")
        } catch is ApplyError {
            let state = try await fixture.store.syncState(appID: "myshell")
            XCTAssertEqual(state.cursor, "existing")
        }
        await fixture.store.close()
        try FileManager.default.removeItem(at: fixture.directory)
    }

    func testPushAppliesResponseBeforeRemovingStableQueueItem() async throws {
        let fixture = try makeFixture()
        let operation = PendingSyncOperation(
            kind: .put,
            collection: "connections",
            recordID: UUID(),
            baseVersion: 4,
            encryptedPayload: Data([1, 2, 3]),
            checksum: "checksum"
        )
        try await fixture.store.enqueue(operation)
        let hub = StubSyncHub(
            page: SyncChangesPage(changes: [], cursor: "")
        )
        let applier = RecordingApplier()
        let coordinator = SyncCoordinator(
            appID: "myshell",
            store: fixture.store,
            hub: hub,
            applier: applier
        )

        let completed = try await coordinator.pushPending(
            token: Data("token".utf8)
        )
        let queue = try await fixture.store.pendingOperations()
        let key = await hub.receivedIdempotencyKey()
        let applicationCount = await applier.applicationCount()
        XCTAssertEqual(completed, 1)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(key, operation.idempotencyKey)
        XCTAssertEqual(applicationCount, 1)
        await fixture.store.close()
        try FileManager.default.removeItem(at: fixture.directory)
    }

    func testConflictFetchesRemoteAndPersistsUserChoice() async throws {
        let fixture = try makeFixture()
        let operation = PendingSyncOperation(
            kind: .put,
            collection: "connections",
            recordID: UUID(),
            baseVersion: 2,
            encryptedPayload: Data([1]),
            checksum: "checksum"
        )
        try await fixture.store.enqueue(operation)
        let hub = StubSyncHub(
            page: SyncChangesPage(changes: [], cursor: ""),
            conflictOnPut: true
        )
        let coordinator = SyncCoordinator(
            appID: "myshell",
            store: fixture.store,
            hub: hub,
            applier: RecordingApplier()
        )

        do {
            _ = try await coordinator.pushPending(token: Data("token".utf8))
            XCTFail("Expected conflict")
        } catch SyncHubError.conflict {
            let storedConflicts = try await fixture.store.fetchConflicts()
            let conflict = try XCTUnwrap(storedConflicts.first)
            XCTAssertEqual(conflict.operationID, operation.id)
            XCTAssertEqual(conflict.remote.version, 5)
            try await fixture.store.resolveConflictKeepingLocal(conflict)
            let pending = try await fixture.store.pendingOperations()
            let retried = try XCTUnwrap(pending.first)
            XCTAssertEqual(retried.baseVersion, 5)
            XCTAssertNotEqual(retried.idempotencyKey, operation.idempotencyKey)
            let remaining = try await fixture.store.fetchConflicts()
            XCTAssertTrue(remaining.isEmpty)
        }
        await fixture.store.close()
        try FileManager.default.removeItem(at: fixture.directory)
    }

    private func makeFixture() throws -> (
        directory: URL,
        store: SQLiteConnectionStore
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            directory,
            try SQLiteConnectionStore(
                url: directory.appending(path: "test.sqlite3")
            )
        )
    }
}

private actor StubSyncHub: SyncHubServing {
    let page: SyncChangesPage
    let conflictOnPut: Bool
    private var cursor: String?
    private var idempotencyKey: UUID?

    init(page: SyncChangesPage, conflictOnPut: Bool = false) {
        self.page = page
        self.conflictOnPut = conflictOnPut
    }

    func changes(
        cursor: String?,
        limit: Int,
        token: Data
    ) async throws -> SyncChangesPage {
        self.cursor = cursor
        return page
    }

    func receivedCursor() -> String? {
        cursor
    }

    func get(
        collection: String,
        recordID: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        envelope(
            collection: collection,
            recordID: recordID,
            payload: Data([1, 2, 3]),
            checksum: "checksum"
        )
    }

    func put(
        collection: String,
        recordID: UUID,
        request: SyncWriteRequest,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        if conflictOnPut {
            throw SyncHubError.conflict
        }
        self.idempotencyKey = idempotencyKey
        return envelope(
            collection: collection,
            recordID: recordID,
            payload: request.payload,
            checksum: request.checksum
        )
    }

    func delete(
        collection: String,
        recordID: UUID,
        baseVersion: Int64,
        idempotencyKey: UUID,
        token: Data
    ) async throws -> SyncRecordEnvelope {
        self.idempotencyKey = idempotencyKey
        return envelope(
            collection: collection,
            recordID: recordID,
            payload: nil,
            checksum: nil
        )
    }

    func receivedIdempotencyKey() -> UUID? {
        idempotencyKey
    }

    private func envelope(
        collection: String,
        recordID: UUID,
        payload: Data?,
        checksum: String?
    ) -> SyncRecordEnvelope {
        SyncRecordEnvelope(
            appID: "myshell",
            collection: collection,
            recordID: recordID.uuidString,
            baseVersion: nil,
            version: 5,
            deleted: payload == nil,
            updatedAt: .now,
            payload: payload,
            checksum: checksum
        )
    }
}

private struct ApplyError: Error {}

private actor RecordingApplier: SyncEnvelopeApplying {
    private let shouldFail: Bool
    private var count = 0

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func apply(_ changes: [SyncRecordEnvelope]) async throws {
        if shouldFail {
            throw ApplyError()
        }
        count += 1
    }

    func applicationCount() -> Int {
        count
    }
}
