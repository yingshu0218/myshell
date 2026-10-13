import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private(set) var selectedSection: AppSection?
    private(set) var localTerminalRequestCount = 0

    private let logger: any AppLogging

    init(
        selectedSection: AppSection? = .localShell,
        logger: any AppLogging
    ) {
        self.selectedSection = selectedSection
        self.logger = logger
    }

    static func live() -> AppEnvironment {
        AppEnvironment(logger: AppLogger())
    }

    func select(_ section: AppSection?) {
        selectedSection = section
        logger.record(.selectionChanged)
    }

    func requestLocalTerminal() {
        localTerminalRequestCount += 1
        selectedSection = .localShell
        logger.record(.localTerminalRequested)
    }
}
