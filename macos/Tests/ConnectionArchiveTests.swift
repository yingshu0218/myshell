import Foundation
import XCTest
@testable import MyShell

final class ConnectionArchiveTests: XCTestCase {
    func testRoundTripStripsSyncVersionAndContainsNoSecretFields() throws {
        let record = ConnectionRecord(
            name: "Example",
            host: "example.com",
            user: "me",
            serverVersion: 42
        )
        let data = try ConnectionArchiveCodec.encode(
            [record],
            at: Date(timeIntervalSince1970: 1)
        )
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("token"))
        let decoded = try ConnectionArchiveCodec.decode(data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, record.id)
        XCTAssertNil(decoded[0].serverVersion)
    }

    func testRejectsDuplicateIDsBeforeImport() throws {
        let record = ConnectionRecord(name: "One", host: "one.example.com")
        let archive = ConnectionArchive(
            schemaVersion: 1,
            exportedAt: .now,
            connections: [record, record]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        XCTAssertThrowsError(try ConnectionArchiveCodec.decode(data)) {
            XCTAssertEqual(
                $0 as? ConnectionArchiveError,
                .duplicateIdentifier
            )
        }
    }

    func testRejectsInvalidConnectionAndOversizedInput() throws {
        let invalid = ConnectionRecord(name: "Invalid", host: "-oProxyCommand=bad")
        let data = try ConnectionArchiveCodec.encode([invalid])
        XCTAssertThrowsError(try ConnectionArchiveCodec.decode(data))

        XCTAssertThrowsError(
            try ConnectionArchiveCodec.decode(
                Data(count: ConnectionArchiveCodec.maximumBytes + 1)
            )
        ) {
            XCTAssertEqual($0 as? ConnectionArchiveError, .tooLarge)
        }
    }
}
