import Foundation

enum ConnectionReachability: Equatable, Sendable {
    case unchecked
    case checking
    case reachable(milliseconds: Int)
    case unreachable

    var label: String {
        switch self {
        case .unchecked: "Not checked"
        case .checking: "Checking…"
        case .reachable(let milliseconds): "Reachable (\(milliseconds) ms)"
        case .unreachable: "Unreachable"
        }
    }
}

enum ConnectionReachabilityChecker {
    static func arguments(host: String, port: Int) -> [String] {
        ["-G", "5", "-z", host, String(port)]
    }

    static func check(_ record: ConnectionRecord) async -> ConnectionReachability {
        await Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = arguments(host: record.host, port: record.port)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    return .unreachable
                }
                let duration = start.duration(to: .now)
                let milliseconds = Int(
                    duration.components.seconds * 1_000
                    + duration.components.attoseconds / 1_000_000_000_000_000
                )
                return .reachable(milliseconds: max(milliseconds, 0))
            } catch {
                return .unreachable
            }
        }.value
    }
}
