import Foundation
import XCTest
@testable import MyShell

final class SQLiteConnectionStoreTests: XCTestCase {
    func testPersistsUpdatesAndTombstonesConnections() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try SQLiteConnectionStore(
            url: directory.appending(path: "test.sqlite3")
        )
        var record = ConnectionRecord(
            name: "Production",
            host: "prod.example.com",
            user: "deploy",
            groupName: "Servers",
            tags: ["critical", "linux"],
            notes: "Primary host"
        )
        try await store.upsert(record)

        var records = try await store.fetchActiveConnections()
        XCTAssertEqual(records.count, 1)
        assertEquivalent(records[0], record)

        record.name = "Production 1"
        record.updatedAt = record.updatedAt.addingTimeInterval(10)
        try await store.upsert(record)
        records = try await store.fetchActiveConnections()
        XCTAssertEqual(records.count, 1)
        assertEquivalent(records[0], record)

        try await store.markDeleted(id: record.id)
        records = try await store.fetchActiveConnections()
        XCTAssertTrue(records.isEmpty)
    }

    func testPersistsCursorAndPendingOperationsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "test.sqlite3")
        let first = try SQLiteConnectionStore(url: url)
        let older = PendingSyncOperation(
            kind: .delete,
            collection: "connections",
            recordID: UUID(),
            baseVersion: 2,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newer = PendingSyncOperation(
            kind: .put,
            collection: "connections",
            recordID: UUID(),
            baseVersion: 3,
            encryptedPayload: Data([1, 2, 3]),
            checksum: "opaque-checksum",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        try await first.enqueue(newer)
        try await first.enqueue(older)
        try await first.commitSyncCursor(
            appID: "myshell",
            cursor: "opaque+/=",
            at: Date(timeIntervalSince1970: 30)
        )

        let queued = try await first.pendingOperations()
        XCTAssertEqual(queued, [older, newer])
        try await first.removePendingOperation(id: older.id)
        let state = try await first.syncState(appID: "myshell")
        XCTAssertEqual(state.cursor, "opaque+/=")
        XCTAssertEqual(state.lastSuccessfulSyncAt, Date(timeIntervalSince1970: 30))

        let reopened = try SQLiteConnectionStore(url: url)
        let reopenedQueue = try await reopened.pendingOperations()
        let reopenedState = try await reopened.syncState(appID: "myshell")
        XCTAssertEqual(reopenedQueue, [newer])
        XCTAssertEqual(reopenedState, state)
    }

    private func assertEquivalent(
        _ actual: ConnectionRecord,
        _ expected: ConnectionRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.name, expected.name, file: file, line: line)
        XCTAssertEqual(actual.host, expected.host, file: file, line: line)
        XCTAssertEqual(actual.user, expected.user, file: file, line: line)
        XCTAssertEqual(actual.port, expected.port, file: file, line: line)
        XCTAssertEqual(actual.identityFile, expected.identityFile, file: file, line: line)
        XCTAssertEqual(actual.proxyJump, expected.proxyJump, file: file, line: line)
        XCTAssertEqual(actual.groupName, expected.groupName, file: file, line: line)
        XCTAssertEqual(actual.tags, expected.tags, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, file: file, line: line)
        XCTAssertEqual(
            actual.createdAt.timeIntervalSince1970,
            expected.createdAt.timeIntervalSince1970,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.updatedAt.timeIntervalSince1970,
            expected.updatedAt.timeIntervalSince1970,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.serverVersion, expected.serverVersion, file: file, line: line)
    }
}
