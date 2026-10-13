import SwiftUI

struct ContentView: View {
    @Bindable var environment: AppEnvironment
    @SceneStorage("sidebarIsCollapsed") private var sidebarIsCollapsed = false
    @State private var terminalWorkspace: TerminalWorkspace
    @State private var sshWorkspace = TerminalWorkspace(createInitialSession: false)
    @State private var connectionLibrary = ConnectionLibrary()
    @State private var commandGroupLibrary = CommandGroupLibrary()

    init(environment: AppEnvironment) {
        self.environment = environment
        _terminalWorkspace = State(
            initialValue: TerminalWorkspace(
                initialSessionCount: Self.performanceTerminalCount
            )
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                selection: Binding(
                    get: { environment.selectedSection },
                    set: { environment.select($0) }
                ),
                isCollapsed: $sidebarIsCollapsed
            )

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusedSceneValue(
            \.terminalActions,
            TerminalActions(
                newTerminal: terminalWorkspace.createSession,
                closeTerminal: terminalWorkspace.closeSelectedSession,
                nextTerminal: terminalWorkspace.selectNextSession,
                previousTerminal: terminalWorkspace.selectPreviousSession
            )
        )
        .task {
            await runPerformanceScenarioIfRequested()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch environment.selectedSection {
        case .localShell:
            TerminalWorkspaceView(workspace: terminalWorkspace)
        case .connections:
            ConnectionsView(
                workspace: sshWorkspace,
                library: connectionLibrary
            )
        case .commandGroups:
            CommandGroupsView(
                library: commandGroupLibrary,
                localWorkspace: terminalWorkspace,
                sshWorkspace: sshWorkspace
            )
        case .sync:
            SyncView()
        case .settings:
            SettingsView(presentation: .sidebar)
        case nil:
            DetailPlaceholderView(section: environment.selectedSection)
        }
    }

    private static var performanceTerminalCount: Int {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_TERMINALS"],
              let value = Int(rawValue) else {
            return 1
        }
        return min(max(value, 0), TerminalWorkspace.maximumSessionCount)
    }

    private static var performanceOutputByteCount: Int? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_OUTPUT_BYTES"],
              let value = Int(rawValue),
              value > 0 else {
            return nil
        }
        return min(value, 64 * 1024 * 1024)
    }

    private static var performanceOutputLineCount: Int? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_OUTPUT_LINES"],
              let value = Int(rawValue),
              value > 0 else {
            return nil
        }
        return min(value, 1_000_000)
    }

    private static var performanceTabSwitchInterval: Duration? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_TAB_SWITCH_MS"],
              let milliseconds = Int(rawValue),
              milliseconds >= 50 else {
            return nil
        }
        return .milliseconds(min(milliseconds, 5_000))
    }

    private static var performanceScenarioDelay: Duration {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_DELAY_MS"],
              let milliseconds = Int(rawValue) else {
            return .seconds(1)
        }
        return .milliseconds(min(max(milliseconds, 0), 30_000))
    }

    private static var performanceOutputAllSessions: Bool {
        ProcessInfo.processInfo.environment["MYSHELL_PERFORMANCE_OUTPUT_ALL"] == "1"
    }

    private static var performanceOutputProfile: String {
        ProcessInfo.processInfo.environment[
            "MYSHELL_PERFORMANCE_OUTPUT_PROFILE"
        ] ?? "ascii"
    }

    private static var performanceExitAfterOutput: Bool {
        ProcessInfo.processInfo.environment[
            "MYSHELL_PERFORMANCE_EXIT_AFTER_OUTPUT"
        ] == "1"
    }

    private static var performanceLatencySampleCount: Int {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_LATENCY_SAMPLES"],
              let value = Int(rawValue) else {
            return 0
        }
        return min(max(value, 0), 100)
    }

    private static var performanceTUIFrameCount: Int {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MYSHELL_PERFORMANCE_MODE"] == "1",
              let rawValue = environment["MYSHELL_PERFORMANCE_TUI_FRAMES"],
              let value = Int(rawValue) else {
            return 0
        }
        return min(max(value, 0), 10_000)
    }

    @MainActor
    private func runPerformanceScenarioIfRequested() async {
        let hasOutputScenario = Self.performanceOutputByteCount != nil
            || Self.performanceOutputLineCount != nil
        let hasTabSwitchScenario = Self.performanceTabSwitchInterval != nil
        let hasLatencyScenario = Self.performanceLatencySampleCount > 0
        let hasTUIScenario = Self.performanceTUIFrameCount > 0
        if hasOutputScenario || hasTabSwitchScenario || hasLatencyScenario
            || hasTUIScenario {
            try? await Task.sleep(for: Self.performanceScenarioDelay)
        }

        if hasLatencyScenario {
            for sample in 1...Self.performanceLatencySampleCount {
                guard !Task.isCancelled else {
                    return
                }
                PerformanceLatencyProbe.shared.begin(sample: sample)
                try? terminalWorkspace.insertCommandText("printf .\n")
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        if hasTUIScenario {
            let frames = Self.performanceTUIFrameCount
            let command = "/usr/bin/awk 'BEGIN { "
                + "printf \"\\033[?1049h\"; "
                + "for (f = 0; f < \(frames); f++) { "
                + "printf \"\\033[H\"; "
                + "for (r = 0; r < 40; r++) "
                + "printf \"\\033[3%dmframe=%06d row=%02d "
                + "cpu=42.0 mem=73.5\\033[0m\\n\", "
                + "(r % 7) + 1, f, r; "
                + "} printf \"\\033[?1049l\"; }'; "
                + "printf '\\033]0;__myshell_tui_complete__\\007'\n"
            try? terminalWorkspace.insertCommandText(command)
        }

        if hasOutputScenario {
            let generator: String
            if Self.performanceOutputProfile == "unicode-ansi" {
                generator = "LC_ALL=en_US.UTF-8 /usr/bin/yes "
                    + "$'\\033[31m中文🙂Ａe\\u0301\\033[0m'"
            } else {
                generator = "LC_ALL=C /usr/bin/yes 0123456789abcdef"
            }
            let limiter: String
            if let lineCount = Self.performanceOutputLineCount {
                limiter = "/usr/bin/head -n \(lineCount)"
            } else {
                limiter = "/usr/bin/head -c \(Self.performanceOutputByteCount!)"
            }
            var command = generator + " | " + limiter
            if Self.performanceExitAfterOutput {
                command += "; exit"
            }
            command += "\n"
            if Self.performanceOutputAllSessions {
                try? terminalWorkspace.insertCommandTextIntoAllSessions(command)
            } else {
                try? terminalWorkspace.insertCommandText(command)
            }
        }

        guard let interval = Self.performanceTabSwitchInterval,
              terminalWorkspace.sessions.count > 1 else {
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else {
                return
            }
            terminalWorkspace.selectNextSession()
        }
    }
}
