import Foundation
import OSLog

protocol AppLogging: Sendable {
    func record(_ event: PublicLogEvent)
}

enum PublicLogEvent: String, Sendable {
    case appStarted = "app_started"
    case selectionChanged = "selection_changed"
    case localTerminalRequested = "local_terminal_requested"
}

struct AppLogger: AppLogging {
    private let logger = Logger(
        subsystem: "com.yingshu0218.myshell",
        category: "application"
    )

    func record(_ event: PublicLogEvent) {
        logger.info("event=\(event.rawValue, privacy: .public)")
    }
}

struct NullLogger: AppLogging {
    func record(_ event: PublicLogEvent) {}
}

@MainActor
final class PerformanceLatencyProbe {
    static let shared = PerformanceLatencyProbe()

    private let logger = Logger(
        subsystem: "com.yingshu0218.myshell",
        category: "TerminalLatency"
    )
    private var sampleID: Int?
    private var startedAt: UInt64?
    private var recordedStages: Set<Stage> = []

    private enum Stage: String {
        case output
        case feed
        case displayCommit = "display_commit"
    }

    private init() {}

    var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["MYSHELL_PERFORMANCE_MODE"] == "1"
            && environment["MYSHELL_PERFORMANCE_LATENCY_SAMPLES"] != nil
    }

    func begin(sample: Int) {
        guard isEnabled else {
            return
        }
        sampleID = sample
        startedAt = DispatchTime.now().uptimeNanoseconds
        recordedStages.removeAll(keepingCapacity: true)
    }

    func markOutputReceived() {
        mark(.output)
    }

    func markFeedCompleted() {
        mark(.feed)
    }

    func markDisplayCommitCompleted() {
        mark(.displayCommit)
    }

    private func mark(_ stage: Stage) {
        guard isEnabled,
              let sampleID,
              let startedAt,
              !recordedStages.contains(stage) else {
            return
        }
        recordedStages.insert(stage)
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        logger.info("sample=\(sampleID, privacy: .public) stage=\(stage.rawValue, privacy: .public) latency_us=\(elapsed / 1_000, privacy: .public)")
    }
}

@MainActor
final class PerformanceResizeProbe {
    static let shared = PerformanceResizeProbe()

    private(set) var terminalResizeEvents = 0

    private init() {}

    func reset() {
        terminalResizeEvents = 0
    }

    func recordTerminalResize() {
        guard ProcessInfo.processInfo.environment[
            "MYSHELL_PERFORMANCE_RESIZE_INTERVAL_MS"
        ] != nil else {
            return
        }
        terminalResizeEvents += 1
    }
}

@MainActor
final class PerformanceTUIProbe {
    static let shared = PerformanceTUIProbe()

    private let logger = Logger(
        subsystem: "com.yingshu0218.myshell",
        category: "TerminalTUI"
    )

    private init() {}

    func consumeCompletionTitleIfExpected(_ title: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_TUI_FRAMES"] != nil,
              title == "__myshell_tui_complete__" else {
            return false
        }
        logger.info("event=tui_completed")
        return true
    }
}
