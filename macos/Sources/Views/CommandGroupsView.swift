import SwiftUI

struct CommandGroupsView: View {
    @Bindable var library: CommandGroupLibrary
    let localWorkspace: TerminalWorkspace
    let sshWorkspace: TerminalWorkspace

    @State private var draft: CommandGroupRecord?
    @State private var target: TerminalTarget = .local
    @State private var executionMessage: String?

    var body: some View {
        HSplitView {
            groupList
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
            editor
                .frame(minWidth: 520)
        }
        .navigationTitle("Quick Commands")
        .task {
            await library.load()
            selectDraft()
        }
        .onChange(of: library.selectedID) {
            selectDraft()
        }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            List(library.groups, selection: $library.selectedID) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .lineLimit(1)
                    Text("\(group.commands.count) command(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(group.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        library.selectedID = group.id
                        Task { await library.deleteSelected() }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    createGroup()
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                Spacer()
                Button(role: .destructive) {
                    Task { await library.deleteSelected() }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(library.selectedID == nil)
                .help("Delete selected group")
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        TextField(
                            "Group name",
                            text: Binding(
                                get: { draft.name },
                                set: { self.draft?.name = $0 }
                            )
                        )
                        .font(.title2.weight(.semibold))

                        Button("Save") {
                            Task {
                                if await library.save(draft) {
                                    self.draft = library.selectedGroup
                                }
                            }
                        }
                        .keyboardShortcut("s", modifiers: .command)
                    }

                    HStack {
                        Picker("Target", selection: $target) {
                            ForEach(TerminalTarget.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .frame(maxWidth: 260)

                        Button {
                            execute(draft)
                        } label: {
                            Label("Run Group", systemImage: "play.fill")
                        }
                        .disabled(draft.commands.isEmpty || selectedWorkspace.selectedSession == nil)
                    }

                    Text(
                        "Commands are encrypted for Sync Hub, but become plaintext on "
                            + "trusted devices and in the shell. Do not save passwords or tokens."
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)

                    ForEach(Array(draft.commands.enumerated()), id: \.element.id) { index, command in
                        commandEditor(command, at: index)
                    }

                    Button {
                        self.draft?.commands.append(
                            CommandShortcut(name: "New Command", text: "")
                        )
                    } label: {
                        Label("Add Command", systemImage: "plus")
                    }
                    .disabled(draft.commands.count >= CommandGroupRecord.maximumCommands)

                    if let message = executionMessage ?? library.errorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView {
                Label("No Command Group", systemImage: "text.badge.plus")
            } description: {
                Text("Create a group to save reusable commands.")
            } actions: {
                Button("New Group") {
                    createGroup()
                }
            }
        }
    }

    private func commandEditor(
        _ command: CommandShortcut,
        at index: Int
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(
                        "Command name",
                        text: commandBinding(at: index, keyPath: \.name)
                    )
                    Button {
                        moveCommand(from: index, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        moveCommand(from: index, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index + 1 == draft?.commands.count)
                    Button(role: .destructive) {
                        draft?.commands.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                TextEditor(text: commandBinding(at: index, keyPath: \.text))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 72)

                HStack {
                    Spacer()
                    Button("Add to Terminal") {
                        insert(command.text)
                    }
                    .disabled(command.text.isEmpty || selectedWorkspace.selectedSession == nil)
                }
            }
            .padding(4)
        }
    }

    private func commandBinding(
        at index: Int,
        keyPath: WritableKeyPath<CommandShortcut, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let commands = draft?.commands, commands.indices.contains(index) else {
                    return ""
                }
                return commands[index][keyPath: keyPath]
            },
            set: { value in
                guard self.draft?.commands.indices.contains(index) == true else { return }
                self.draft?.commands[index][keyPath: keyPath] = value
            }
        )
    }

    private var selectedWorkspace: TerminalWorkspace {
        target == .local ? localWorkspace : sshWorkspace
    }

    private func createGroup() {
        let group = CommandGroupRecord(name: "New Group")
        library.selectedID = group.id
        draft = group
        executionMessage = nil
    }

    private func selectDraft() {
        if let selected = library.selectedGroup {
            draft = selected
        } else if draft?.id != library.selectedID {
            draft = nil
        }
        executionMessage = nil
    }

    private func moveCommand(from index: Int, by offset: Int) {
        guard let count = draft?.commands.count else { return }
        let destination = index + offset
        guard (0..<count).contains(index), (0..<count).contains(destination) else { return }
        draft?.commands.swapAt(index, destination)
    }

    private func insert(_ text: String) {
        do {
            try selectedWorkspace.insertCommandText(text)
            executionMessage = "Added to \(target.title)."
        } catch {
            executionMessage = error.localizedDescription
        }
    }

    private func execute(_ group: CommandGroupRecord) {
        do {
            try selectedWorkspace.executeCommandGroup(group)
            executionMessage = "Executed \(group.commands.count) command(s) in \(target.rawValue)."
        } catch {
            executionMessage = error.localizedDescription
        }
    }
}

private enum TerminalTarget: String, CaseIterable, Identifiable {
    case local
    case ssh

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .local: "Local Terminal"
        case .ssh: "SSH Terminal"
        }
    }
}
