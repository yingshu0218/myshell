import Foundation
import Testing
@testable import MyShell

struct ConnectionSyncAdapterTests {
    private let appID = "myshell-test"
    private let key = Data(repeating: 7, count: 32)

    @Test func codecExcludesDeviceLocalIdentityPath() throws {
        let record = sampleRecord(identityFile: "/Users/alice/.ssh/id_private")
        let encoded = try ConnectionSyncCodec.encode(record)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("identityFile"))
        #expect(!text.contains("id_private"))
        #expect(!text.localizedCaseInsensitiveContains("password"))

        let decoded = try ConnectionSyncCodec.decode(
            encoded,
            expectedID: record.id,
            serverVersion: 4
        )
        #expect(decoded.identityFile.isEmpty)
        #expect(decoded.groupName == "Production")
        #expect(decoded.serverVersion == 4)
    }

    @Test func outboxEncryptsConnectionAndUsesConfirmedVersion() async throws {
        let store = try temporaryStore()
        defer { Task { await store.close() } }
        var record = sampleRecord()
        record.serverVersion = 3
        try await ConnectionSyncOutbox(appID: appID, store: store, key: key)
            .enqueueUpsert(record)

        let operation = try #require(await store.pendingOperations().first)
        #expect(try await store.fetchConnectionsNeedingSync().isEmpty)
        #expect(operation.baseVersion == 3)
        #expect(operation.collection == "connections")
        let payload = try #require(operation.encryptedPayload)
        let checksum = try #require(operation.checksum)
        let plaintext = try EnvelopeCrypto.open(
            payload: payload,
            checksum: checksum,
            key: key,
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: "connections",
                recordID: record.id,
                schemaID: "connection-v1"
            )
        )
        #expect(try ConnectionSyncCodec.decode(
            plaintext,
            expectedID: record.id,
            serverVersion: 3
        ).host == record.host)
    }

    @Test func applierIsAtomicAndPreservesLocalIdentityPath() async throws {
        let store = try temporaryStore()
        defer { Task { await store.close() } }
        let original = sampleRecord(identityFile: "/local/private/key")
        try await store.upsert(original)

        var remote = original
        remote.name = "Remote Name"
        remote.identityFile = "/must/not/sync"
        remote.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = try envelope(for: remote, version: 2)
        let invalid = SyncRecordEnvelope(
            appID: appID,
            collection: "connections",
            recordID: UUID().uuidString,
            baseVersion: 0,
            version: 1,
            deleted: false,
            updatedAt: .now,
            payload: Data("invalid".utf8),
            checksum: "sha256:bad"
        )
        let applier = ConnectionEnvelopeApplier(appID: appID, store: store, key: key)
        await #expect(throws: EnvelopeError.checksumMismatch) {
            try await applier.apply([valid, invalid])
        }
        #expect(try await store.fetchActiveConnections().first?.name == original.name)

        try await applier.apply([valid])
        let applied = try #require(await store.fetchActiveConnections().first)
        #expect(applied.name == "Remote Name")
        #expect(applied.identityFile == "/local/private/key")
        #expect(applied.serverVersion == 2)
    }

    private func envelope(
        for record: ConnectionRecord,
        version: Int64
    ) throws -> SyncRecordEnvelope {
        let plaintext = try ConnectionSyncCodec.encode(record)
        let sealed = try EnvelopeCrypto.seal(
            plaintext: plaintext,
            key: key,
            nonce: Data(repeating: UInt8(version), count: 12),
            aad: EnvelopeCrypto.aad(
                appID: appID,
                collection: "connections",
                recordID: record.id,
                schemaID: "connection-v1"
            )
        )
        return SyncRecordEnvelope(
            appID: appID,
            collection: "connections",
            recordID: record.id.uuidString,
            baseVersion: max(0, version - 1),
            version: version,
            deleted: false,
            updatedAt: record.updatedAt,
            payload: sealed.payload,
            checksum: sealed.checksum
        )
    }

    private func sampleRecord(identityFile: String = "") -> ConnectionRecord {
        ConnectionRecord(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            name: "Example",
            host: "example.test",
            user: "alice",
            port: 22,
            identityFile: identityFile,
            proxyJump: "jump.example.test",
            groupName: "Production",
            tags: ["demo"],
            notes: "Shared safely",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
    }

    private func temporaryStore() throws -> SQLiteConnectionStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "myshell-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try SQLiteConnectionStore(url: directory.appending(path: "test.sqlite3"))
    }
}
