import Foundation
import XCTest
@testable import MyShell

final class LiveSyncHubIntegrationTests: XCTestCase {
    func testTwoMacsRoundTripAndDetectConflict() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let urlText = environment["MYSHELL_LIVE_SYNC_URL"],
              let baseURL = URL(string: urlText),
              let appID = environment["MYSHELL_LIVE_SYNC_APP_ID"],
              let tokenA = environment["MYSHELL_LIVE_SYNC_TOKEN_A"],
              let tokenB = environment["MYSHELL_LIVE_SYNC_TOKEN_B"]
        else {
            throw XCTSkip("Live Sync Hub credentials were not supplied.")
        }

        let root = FileManager.default.temporaryDirectory
            .appending(path: "myshell-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storeA = try SQLiteConnectionStore(url: root.appending(path: "a.sqlite3"))
        let storeB = try SQLiteConnectionStore(url: root.appending(path: "b.sqlite3"))
        addTeardownBlock {
            await storeA.close()
            await storeB.close()
        }
        let key = Data(repeating: 0x42, count: 32)
        let coordinatorA = try makeCoordinator(appID: appID, baseURL: baseURL, store: storeA, key: key)
        let coordinatorB = try makeCoordinator(appID: appID, baseURL: baseURL, store: storeB, key: key)
        let authA = Data(tokenA.utf8)
        let authB = Data(tokenB.utf8)

        var local = ConnectionRecord(
            name: "Live Integration",
            host: "integration.invalid",
            user: "tester",
            identityFile: "/Users/local/.ssh/id_ed25519"
        )
        try await storeA.upsert(local)
        try await ConnectionSyncOutbox(appID: appID, store: storeA, key: key).enqueueUpsert(local)
        let firstPushCount = try await coordinatorA.pushPending(token: authA)
        XCTAssertEqual(firstPushCount, 1)
        _ = try await coordinatorB.pullUntilCaughtUp(token: authB)

        let recordsOnB = try await storeB.fetchActiveConnections()
        var remote = try XCTUnwrap(recordsOnB.first)
        XCTAssertEqual(remote.name, local.name)
        XCTAssertEqual(remote.identityFile, "")

        let group = CommandGroupRecord(
            name: "Live Commands",
            commands: [
                CommandShortcut(name: "Path", text: "pwd"),
                CommandShortcut(name: "Status", text: "git status --short"),
            ]
        )
        try await storeA.upsertCommandGroup(group)
        try await CommandGroupSyncOutbox(
            appID: appID,
            store: storeA,
            key: key
        ).enqueueUpsert(group)
        let commandPushCount = try await coordinatorA.pushPending(token: authA)
        XCTAssertEqual(commandPushCount, 1)
        _ = try await coordinatorB.pullUntilCaughtUp(token: authB)
        let groupsOnB = try await storeB.fetchActiveCommandGroups()
        XCTAssertEqual(groupsOnB.first?.commands.map(\.text), ["pwd", "git status --short"])

        local.name = "Changed on A"
        let recordsOnA = try await storeA.fetchActiveConnections()
        local.serverVersion = try XCTUnwrap(recordsOnA.first?.serverVersion)
        local.updatedAt = .now
        try await storeA.upsert(local)
        try await ConnectionSyncOutbox(appID: appID, store: storeA, key: key).enqueueUpsert(local)

        remote.name = "Changed on B"
        remote.updatedAt = .now
        try await storeB.upsert(remote)
        try await ConnectionSyncOutbox(appID: appID, store: storeB, key: key).enqueueUpsert(remote)

        let secondPushCount = try await coordinatorA.pushPending(token: authA)
        XCTAssertEqual(secondPushCount, 1)
        do {
            _ = try await coordinatorB.pushPending(token: authB)
            XCTFail("Expected a stale write conflict.")
        } catch SyncHubError.conflict {
            let conflicts = try await storeB.fetchConflicts()
            XCTAssertEqual(conflicts.count, 1)
        }
    }

    private func makeCoordinator(
        appID: String,
        baseURL: URL,
        store: SQLiteConnectionStore,
        key: Data
    ) throws -> SyncCoordinator {
        let client = try SyncHubClient(baseURL: baseURL, appID: appID)
        return SyncCoordinator(
            appID: appID,
            store: store,
            hub: client,
            applier: MyShellEnvelopeApplier(appID: appID, store: store, key: key)
        )
    }
}
