import XCTest
@testable import MyShell

final class ConnectionReachabilityTests: XCTestCase {
    func testProbeUsesBoundedSystemNetcatArguments() {
        XCTAssertEqual(
            ConnectionReachabilityChecker.arguments(
                host: "example.com",
                port: 2222
            ),
            ["-G", "5", "-z", "example.com", "2222"]
        )
    }

    func testReachabilityLabelsAreActionable() {
        XCTAssertEqual(ConnectionReachability.unchecked.label, "Not checked")
        XCTAssertEqual(
            ConnectionReachability.reachable(milliseconds: 12).label,
            "Reachable (12 ms)"
        )
        XCTAssertEqual(ConnectionReachability.unreachable.label, "Unreachable")
    }
}
