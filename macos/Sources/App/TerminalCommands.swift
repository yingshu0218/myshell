import SwiftUI

struct TerminalActions {
    let newTerminal: () -> Void
    let closeTerminal: () -> Void
    let nextTerminal: () -> Void
    let previousTerminal: () -> Void
}

private struct TerminalActionsKey: FocusedValueKey {
    typealias Value = TerminalActions
}

extension FocusedValues {
    var terminalActions: TerminalActions? {
        get { self[TerminalActionsKey.self] }
        set { self[TerminalActionsKey.self] = newValue }
    }
}

struct TerminalCommands: Commands {
    @FocusedValue(\.terminalActions) private var actions

    var body: some Commands {
        CommandMenu("Shell") {
            Button("New Local Terminal") {
                actions?.newTerminal()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(actions == nil)

            Button("Close Terminal") {
                actions?.closeTerminal()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Divider()

            Button("Next Terminal") {
                actions?.nextTerminal()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("Previous Terminal") {
                actions?.previousTerminal()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(actions == nil)
        }
    }
}
