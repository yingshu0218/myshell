import Foundation
import XCTest
@testable import MyShell

final class PTYSessionTests: XCTestCase {
    func testCommandOutputAndExitCode() async throws {
        let session = try PTYSession.start(
            PTYConfiguration(
                executable: "/bin/sh",
                arguments: ["-c", "printf 'ready'; exit 7"]
            )
        )

        async let output = Self.collect(session.output)
        let exitCode = try await Self.firstValue(from: session.termination)

        XCTAssertEqual(exitCode, 7)
        let text = String(decoding: await output, as: UTF8.self)
        XCTAssertTrue(text.contains("ready"))
    }

    func testInitialTerminalSizeIsApplied() async throws {
        let session = try PTYSession.start(
            PTYConfiguration(
                executable: "/bin/sh",
                arguments: ["-c", "stty size"],
                columns: 100,
                rows: 40
            )
        )

        let output = await Self.collect(session.output)
        let text = String(decoding: output, as: UTF8.self)

        XCTAssertTrue(text.contains("40 100"))
    }

    func testInteractiveInputAndRuntimeResize() async throws {
        let session = try PTYSession.start(
            PTYConfiguration(
                executable: "/bin/sh",
                arguments: ["-c", "stty size; IFS= read -r line; stty size; printf '<%s>' \"$line\""],
                columns: 80,
                rows: 24
            )
        )

        async let output = Self.collect(session.output)
        try await Task.sleep(for: .milliseconds(100))
        try session.resize(columns: 132, rows: 48)
        try session.write("hello, 世界\n")

        let exitCode = try await Self.firstValue(from: session.termination)
        XCTAssertEqual(exitCode, 0)
        let text = String(decoding: await output, as: UTF8.self)
        XCTAssertTrue(text.contains("24 80"))
        XCTAssertTrue(text.contains("48 132"))
        XCTAssertTrue(text.contains("<hello, 世界>"))
    }

    func testCloseTerminatesChildAndRejectsFurtherWrites() async throws {
        let session = try PTYSession.start(
            PTYConfiguration(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 30"]
            )
        )

        session.close()

        let exitCode = try await Self.firstValue(from: session.termination)
        XCTAssertEqual(exitCode, 137)
        XCTAssertThrowsError(try session.write("ignored")) { error in
            XCTAssertEqual(error as? PTYError, .closed)
        }
    }

    func testInvalidExecutableIsRejectedBeforeFork() {
        XCTAssertThrowsError(
            try PTYSession.start(
                PTYConfiguration(executable: "/missing/myshell-test")
            )
        ) { error in
            XCTAssertEqual(error as? PTYError, .invalidExecutable)
        }
    }

    private static func collect(_ stream: AsyncStream<Data>) async -> Data {
        var result = Data()
        for await chunk in stream {
            result.append(chunk)
        }
        return result
    }

    private static func firstValue<T: Sendable>(
        from stream: AsyncStream<T>
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                for await value in stream {
                    return value
                }
                throw TestError.streamFinished
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw TestError.timedOut
            }

            guard let result = try await group.next() else {
                throw TestError.streamFinished
            }
            group.cancelAll()
            return result
        }
    }

    private enum TestError: Error {
        case streamFinished
        case timedOut
    }
}
