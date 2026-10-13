import XCTest
@testable import MyShell

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testDefaultSelectionIsLocalShell() {
        let environment = AppEnvironment(logger: NullLogger())

        XCTAssertEqual(environment.selectedSection, .localShell)
        XCTAssertEqual(environment.localTerminalRequestCount, 0)
    }

    func testRequestingLocalTerminalSelectsShellAndTracksRequest() {
        let environment = AppEnvironment(
            selectedSection: .connections,
            logger: NullLogger()
        )

        environment.requestLocalTerminal()

        XCTAssertEqual(environment.selectedSection, .localShell)
        XCTAssertEqual(environment.localTerminalRequestCount, 1)
    }

    func testSelectionCanBeCleared() {
        let environment = AppEnvironment(logger: NullLogger())

        environment.select(nil)

        XCTAssertNil(environment.selectedSection)
    }
}
