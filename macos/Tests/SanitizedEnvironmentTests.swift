import XCTest
@testable import MyShell

final class SanitizedEnvironmentTests: XCTestCase {
    func testRemovesCommonSecretsAndPreservesTerminalRequirements() {
        let sanitized = SanitizedEnvironment.terminal(from: [
            "PATH": "/usr/bin",
            "SSH_AUTH_SOCK": "/tmp/agent.sock",
            "GITHUB_TOKEN": "secret",
            "DATABASE_PASSWORD": "secret",
            "SERVICE_API_KEY": "secret",
            "NORMAL_SETTING": "safe",
        ])

        XCTAssertEqual(sanitized["PATH"], "/usr/bin")
        XCTAssertEqual(sanitized["SSH_AUTH_SOCK"], "/tmp/agent.sock")
        XCTAssertEqual(sanitized["NORMAL_SETTING"], "safe")
        XCTAssertNil(sanitized["GITHUB_TOKEN"])
        XCTAssertNil(sanitized["DATABASE_PASSWORD"])
        XCTAssertNil(sanitized["SERVICE_API_KEY"])
    }
}
