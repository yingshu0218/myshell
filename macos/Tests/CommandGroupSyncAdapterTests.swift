import Foundation
import Testing
@testable import MyShell

struct CommandGroupSyncAdapterTests {
    private let appID = "myshell-test"
    private let key = Data(repeating: 9, count: 32)

    @Test func codecRoundTripsOrderedCommands() throws {
        let group = sampleGroup()
        let encoded = try CommandGroupSyncCodec.encode(group)
        let decoded = try CommandGroupSyncCodec.decode(
            encoded,
            expectedID: group.id,
            serverVersion: 7
        )

        #expect(decoded.name == group.name)
        #expect(decoded.commands.map(\.text) == ["pwd", "git status --short"])
        #expect(decoded.serverVersion == 7)
    }

    @Test func outboxEncryptsCommandGroupAndMarksItQueued() async throws {
        let store = try temporaryStore()
        defer { Task { await store.close() } }
        var group = sampleGroup()
        group.serverVersion = 3
        try await store.upsertCommandGroup(group)
        try await CommandGroupSyncOutbox(appID: appID, store: store, key: key)
            .enqueueUpsert(group)

        let operation = try #require(await store.pendingOperations().first)
        #expect(operation.collection == "command-groups")
        #expect(operation.baseVersion == 3)
        #expect(try await store.fetchCommandGroupsNeedingSync().isEmpty)
        let plaintext = try EnvelopeCrypto.open(
            payload: try #require(operation.encryptedPayload),
            checksum: try #require(operation.checksum),
            key: key,
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: "command-groups",
                recordID: group.id,
                schemaID: "command-group-v1"
            )
        )
        #expect(try CommandGroupSyncCodec.decode(
            plaintext,
            expectedID: group.id,
            serverVersion: 3
        ).commands == group.commands)
    }

    @Test func mixedPageIsAtomicWhenAnyEnvelopeFails() async throws {
        let store = try temporaryStore()
        defer { Task { await store.close() } }
        let group = sampleGroup()
        let valid = try envelope(for: group, version: 1)
        let invalid = SyncRecordEnvelope(
            appID: appID,
            collection: "connections",
            recordID: UUID().uuidString,
            baseVersion: 0,
            version: 1,
            deleted: false,
            updatedAt: .now,
            payload: Data("bad".utf8),
            checksum: "sha256:bad"
        )
        let applier = MyShellEnvelopeApplier(appID: appID, store: store, key: key)

        await #expect(throws: EnvelopeError.checksumMismatch) {
            try await applier.apply([valid, invalid])
        }
        #expect(try await store.fetchActiveCommandGroups().isEmpty)

        try await applier.apply([valid])
        #expect(try await store.fetchActiveCommandGroups().first?.name == group.name)
    }

    private func envelope(
        for group: CommandGroupRecord,
        version: Int64
    ) throws -> SyncRecordEnvelope {
        let sealed = try EnvelopeCrypto.seal(
            plaintext: CommandGroupSyncCodec.encode(group),
            key: key,
            nonce: Data(repeating: UInt8(version), count: 12),
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: "command-groups",
                recordID: group.id,
                schemaID: "command-group-v1"
            )
        )
        return SyncRecordEnvelope(
            appID: appID,
            collection: "command-groups",
            recordID: group.id.uuidString,
            baseVersion: 0,
            version: version,
            deleted: false,
            updatedAt: group.updatedAt,
            payload: sealed.payload,
            checksum: sealed.checksum
        )
    }

    private func sampleGroup() -> CommandGroupRecord {
        CommandGroupRecord(
            id: UUID(uuidString: "d38f6f3f-7d3d-4eb1-a327-a477912b4041")!,
            name: "Service checks",
            commands: [
                CommandShortcut(
                    id: UUID(uuidString: "18c5c055-c42f-457d-b6d9-3370f5ee6638")!,
                    name: "Working directory",
                    text: "pwd"
                ),
                CommandShortcut(
                    id: UUID(uuidString: "81556bd0-6f62-4d71-8449-3475943da6f5")!,
                    name: "Git status",
                    text: "git status --short"
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func temporaryStore() throws -> SQLiteConnectionStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "myshell-command-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try SQLiteConnectionStore(url: directory.appending(path: "test.sqlite3"))
    }
}
