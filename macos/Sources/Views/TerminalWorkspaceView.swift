import SwiftUI

struct TerminalWorkspaceView: View {
    @Bindable var workspace: TerminalWorkspace
    @AppStorage("terminalFontSize") private var terminalFontSize = 14.0
    @AppStorage("terminalTheme") private var terminalThemeRawValue = TerminalTheme.system.rawValue

    private var theme: TerminalTheme {
        TerminalTheme(rawValue: terminalThemeRawValue) ?? .system
    }

    private var retainsTerminalViews: Bool {
        ProcessInfo.processInfo.environment[
            "MYSHELL_PERFORMANCE_RETAIN_TERMINAL_VIEWS"
        ] == "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalTabBar
            Divider()

            if let selectedSession = workspace.selectedSession {
                Group {
                    if retainsTerminalViews {
                        ZStack {
                            ForEach(workspace.sessions) { session in
                                let isSelected = session.id == selectedSession.id
                                terminalSurface(for: session, isActive: isSelected)
                                    .opacity(isSelected ? 1 : 0)
                                    .allowsHitTesting(isSelected)
                                    .accessibilityHidden(!isSelected)
                            }
                        }
                    } else {
                        terminalSurface(for: selectedSession, isActive: true)
                            .id(selectedSession.id)
                    }
                }
                Divider()
                HStack {
                    Label(
                        selectedSession.statusDescription,
                        systemImage: statusImage(for: selectedSession)
                    )
                    .lineLimit(1)
                    .foregroundStyle(
                        selectedSession.state == .running ? .secondary : .primary
                    )
                    Spacer()
                    if selectedSession.state != .running {
                        Button("Restart") {
                            workspace.restartSelectedSession()
                        }
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.bar)
            } else {
                ContentUnavailableView {
                    Label("No Terminal", systemImage: "terminal")
                } description: {
                    Text(workspace.lastError ?? "Open a new local terminal to begin.")
                } actions: {
                    Button("New Terminal") {
                        workspace.createSession()
                    }
                    .keyboardShortcut("t", modifiers: .command)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    workspace.createSession()
                } label: {
                    Label("New Terminal", systemImage: "plus")
                }
                .help("New Terminal (⌘T)")

                Button {
                    workspace.closeSelectedSession()
                } label: {
                    Label("Close Terminal", systemImage: "xmark")
                }
                .disabled(workspace.selectedSession == nil)
                .help("Close Terminal (⇧⌘W)")
            }
        }
    }

    private var terminalTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(workspace.sessions) { session in
                    Button {
                        workspace.selectedSessionID = session.id
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(statusColor(for: session))
                                .frame(width: 7, height: 7)
                            Text(session.title)
                                .lineLimit(1)
                            Button {
                                workspace.selectedSessionID = session.id
                                workspace.closeSelectedSession()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(session.title)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            session.id == workspace.selectedSessionID
                                ? AnyShapeStyle(.quaternary)
                                : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        session.id == workspace.selectedSessionID ? .isSelected : []
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private func terminalSurface(
        for session: TerminalSessionModel,
        isActive: Bool
    ) -> some View {
        TerminalSurface(
            session: session,
            theme: theme,
            fontSize: terminalFontSize,
            isActive: isActive
        )
        .accessibilityLabel("Terminal: \(session.title)")
    }

    private func statusColor(for session: TerminalSessionModel) -> Color {
        switch session.state {
        case .running: .green
        case .exited: .secondary
        case .failed: .red
        }
    }

    private func statusImage(for session: TerminalSessionModel) -> String {
        switch session.state {
        case .running: "circle.fill"
        case .exited(0): "checkmark.circle"
        case .exited: "exclamationmark.triangle"
        case .failed: "xmark.circle"
        }
    }
}
