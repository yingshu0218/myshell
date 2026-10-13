import Foundation
import XCTest
@testable import MyShell

final class CommandGroupStoreTests: XCTestCase {
    func testPersistsRenameOrderAndTombstoneAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "test.sqlite3")
        let first = try SQLiteConnectionStore(url: url)
        var group = CommandGroupRecord(
            name: "Checks",
            commands: [
                CommandShortcut(name: "Path", text: "pwd"),
                CommandShortcut(name: "Files", text: "ls -la"),
            ],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try await first.upsertCommandGroup(group)
        await first.close()

        let reopened = try SQLiteConnectionStore(url: url)
        var records = try await reopened.fetchActiveCommandGroups()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].commands.map(\.text), ["pwd", "ls -la"])

        group.name = "Renamed"
        group.commands.reverse()
        group.updatedAt = Date(timeIntervalSince1970: 30)
        try await reopened.upsertCommandGroup(group)
        records = try await reopened.fetchActiveCommandGroups()
        XCTAssertEqual(records[0].name, "Renamed")
        XCTAssertEqual(records[0].commands.map(\.text), ["ls -la", "pwd"])

        try await reopened.markCommandGroupDeleted(id: group.id)
        let activeAfterDelete = try await reopened.fetchActiveCommandGroups()
        let dirtyAfterDelete = try await reopened.fetchCommandGroupsNeedingSync()
        XCTAssertTrue(activeAfterDelete.isEmpty)
        XCTAssertEqual(dirtyAfterDelete.count, 1)
        await reopened.close()
    }

    func testBatchPayloadPreservesOrderAndAddsOneReturn() throws {
        let group = CommandGroupRecord(
            name: "Deploy",
            commands: [
                CommandShortcut(name: "One", text: "echo one"),
                CommandShortcut(name: "Two", text: "echo two\n"),
            ]
        )

        XCTAssertEqual(
            String(decoding: try group.executionPayload(), as: UTF8.self),
            "echo one\necho two\n"
        )
    }

    func testRejectsOversizedAndDuplicateCommands() throws {
        let id = UUID()
        XCTAssertThrowsError(try CommandGroupRecord(
            name: "Invalid",
            commands: [
                CommandShortcut(id: id, name: "One", text: "pwd"),
                CommandShortcut(id: id, name: "Two", text: "ls"),
            ]
        ).validated()) { error in
            XCTAssertEqual(error as? CommandGroupError, .duplicateCommandID)
        }
        XCTAssertThrowsError(try CommandGroupRecord(
            name: "Invalid",
            commands: [
                CommandShortcut(
                    name: "Large",
                    text: String(repeating: "x", count: CommandShortcut.maximumTextLength + 1)
                ),
            ]
        ).validated()) { error in
            XCTAssertEqual(error as? CommandGroupError, .invalidCommandText)
        }
    }
}
