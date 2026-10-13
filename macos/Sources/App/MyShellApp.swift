import AppKit
import OSLog
import SwiftUI

@main
struct MyShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.live()
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.system.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup("MyShell", id: "main") {
            ContentView(environment: environment)
                .frame(minWidth: 900, minHeight: 560)
                .environment(\.locale, appLanguage.locale)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            TerminalCommands()
        }

        Settings {
            SettingsView()
                .environment(\.locale, appLanguage.locale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let performanceLogger = Logger(
        subsystem: "com.yingshu0218.myshell",
        category: "WindowResize"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        schedulePerformanceResizeIfRequested()
    }

    private func schedulePerformanceResizeIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let intervalValue = environment[
                "MYSHELL_PERFORMANCE_RESIZE_INTERVAL_MS"
              ],
              let intervalMilliseconds = Int(intervalValue),
              intervalMilliseconds >= 50 else {
            return
        }
        let cycles = min(
            max(
                Int(environment["MYSHELL_PERFORMANCE_RESIZE_CYCLES"] ?? "") ?? 40,
                1
            ),
            500
        )
        let startDelayMilliseconds = min(
            max(
                Int(
                    environment[
                        "MYSHELL_PERFORMANCE_RESIZE_START_DELAY_MS"
                    ] ?? ""
                ) ?? 3_000,
                0
            ),
            30_000
        )
        let logger = performanceLogger

        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(startDelayMilliseconds)
            )
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && !($0 is NSPanel)
            }) else {
                return
            }

            let visibleSize = window.screen?.visibleFrame.size
                ?? NSScreen.main?.visibleFrame.size
                ?? CGSize(width: 1_440, height: 900)
            let compactSize = CGSize(
                width: min(900, visibleSize.width),
                height: min(560, visibleSize.height)
            )
            let expandedSize = CGSize(
                width: max(compactSize.width, visibleSize.width * 0.78),
                height: max(compactSize.height, visibleSize.height * 0.78)
            )

            PerformanceResizeProbe.shared.reset()
            logger.info(
                "event=resize_started cycles=\(cycles, privacy: .public) interval_ms=\(intervalMilliseconds, privacy: .public)"
            )
            for cycle in 0..<cycles {
                guard !Task.isCancelled else {
                    return
                }
                window.setContentSize(
                    cycle.isMultiple(of: 2) ? compactSize : expandedSize
                )
                try? await Task.sleep(
                    for: .milliseconds(min(intervalMilliseconds, 5_000))
                )
            }
            let terminalResizeEvents =
                PerformanceResizeProbe.shared.terminalResizeEvents
            logger.info("event=resize_completed cycles=\(cycles, privacy: .public) terminal_resize_events=\(terminalResizeEvents, privacy: .public)")
        }
    }
}
