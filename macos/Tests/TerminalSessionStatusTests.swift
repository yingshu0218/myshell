import XCTest
@testable import MyShell

@MainActor
final class TerminalSessionStatusTests: XCTestCase {
    func testSSHExit255ProvidesActionableStatus() {
        XCTAssertEqual(
            TerminalSessionModel.statusDescription(
                for: .exited(255),
                executable: "/usr/bin/ssh"
            ),
            "SSH connection ended. Check the host, network, credentials, and host key."
        )
    }

    func testWorkspacePerformanceSessionCountIsBounded() {
        let workspace = TerminalWorkspace(initialSessionCount: 100)

        XCTAssertEqual(
            workspace.sessions.count,
            TerminalWorkspace.maximumSessionCount
        )

        workspace.closeAllSessions()
    }

    func testWorkspaceCanStartWithoutAnInitialSession() {
        let workspace = TerminalWorkspace(initialSessionCount: 0)

        XCTAssertTrue(workspace.sessions.isEmpty)
        XCTAssertNil(workspace.selectedSessionID)
    }

    func testCloseAllSessionsClearsSelectionAndSessions() {
        let workspace = TerminalWorkspace(initialSessionCount: 3)

        workspace.closeAllSessions()

        XCTAssertTrue(workspace.sessions.isEmpty)
        XCTAssertNil(workspace.selectedSessionID)
    }
}
