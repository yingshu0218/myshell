import Foundation
import XCTest
@testable import MyShell

@MainActor
final class ConnectionLibraryTests: XCTestCase {
    func testSaveReloadAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "library.sqlite3")

        let library = ConnectionLibrary(databaseURL: url)
        await library.load()
        let saved = await library.save(
            SSHConnectionDraft(
                name: "Example",
                host: "example.com",
                user: "me",
                groupName: "Work",
                tags: "one, two",
                notes: "Test"
            )
        )

        XCTAssertNotNil(saved)
        XCTAssertEqual(library.records.count, 1)
        XCTAssertEqual(library.records[0].tags, ["one", "two"])

        let reloaded = ConnectionLibrary(databaseURL: url)
        await reloaded.load()
        XCTAssertEqual(reloaded.records.count, 1)
        reloaded.selectedID = reloaded.records[0].id
        await reloaded.deleteSelected()
        XCTAssertTrue(reloaded.records.isEmpty)
    }
}
