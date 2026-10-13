import SwiftUI

struct ConnectionsView: View {
    @Bindable var workspace: TerminalWorkspace
    @Bindable var library: ConnectionLibrary
    @State private var draft = SSHConnectionDraft()
    @State private var validationMessage: String?
    @State private var searchText = ""
    @State private var operationMessage: String?
    @State private var isListVisible = true
    @State private var isCreating = false
    @State private var isShowingTerminal = false
    @AppStorage("connectionMonitoringEnabled")
    private var connectionMonitoringEnabled = false

    var body: some View {
        Group {
            if isShowingTerminal {
                TerminalWorkspaceView(workspace: workspace)
            } else {
                HSplitView {
                    if isListVisible {
                        connectionList
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                            .frame(maxHeight: .infinity)
                    }
                    connectionDetail
                        .frame(minWidth: 480, maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isShowingTerminal {
                    Button {
                        isShowingTerminal = false
                    } label: {
                        Label("Connection Manager", systemImage: "chevron.backward")
                    }
                } else {
                    Button {
                        isListVisible.toggle()
                    } label: {
                        Label(
                            isListVisible ? "Hide Connection List" : "Show Connection List",
                            systemImage: "sidebar.left"
                        )
                    }

                    Button {
                        beginNewConnection()
                    } label: {
                        Label("New Connection", systemImage: "plus")
                    }
                }
            }
        }
        .task {
            await library.load()
            if library.selectedID == nil, let first = library.records.first {
                library.selectedID = first.id
                draft = first.draft
            }
        }
        .task(id: connectionMonitoringEnabled) {
            guard connectionMonitoringEnabled else { return }
            while !Task.isCancelled {
                await library.checkAllConnections()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: library.selectedID) {
            if let record = library.selectedRecord {
                draft = record.draft
                isCreating = false
                validationMessage = nil
            }
        }
    }

    private var connectionList: some View {
        VStack(spacing: 0) {
            List(filteredRecords, selection: $library.selectedID) { record in
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name)
                            .lineLimit(1)
                        Text(destination(for: record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Circle()
                        .fill(reachabilityColor(for: record))
                        .frame(width: 7, height: 7)
                        .help((library.reachability[record.id] ?? .unchecked).label)
                }
                .tag(record.id)
                .contextMenu {
                    Button("Connect") {
                        selectAndConnect(record)
                    }
                    Button("Check Connection") {
                        Task { await library.check(record) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        library.selectedID = record.id
                        Task {
                            await library.deleteSelected()
                            selectFirstConnection()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search connections")

            Divider()
            HStack {
                Button {
                    beginNewConnection()
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .labelStyle(.iconOnly)

                Spacer()

                Text("\(filteredRecords.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var connectionDetail: some View {
        if library.selectedRecord != nil || isCreating {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isCreating ? "New Connection" : draft.displayName)
                                .font(.title2.weight(.semibold))
                            if !isCreating {
                                Text(destination(for: library.selectedRecord!))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        connectionActions
                    }

                    connectionForm
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView {
                Label("No Connection Selected", systemImage: "server.rack")
            } description: {
                Text("Select a saved connection from the list or create a new one.")
            } actions: {
                Button("New Connection") {
                    beginNewConnection()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var connectionActions: some View {
        HStack(spacing: 8) {
            if !isCreating {
                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            Button("Save") {
                Task {
                    if await library.save(draft) != nil {
                        validationMessage = nil
                        isCreating = false
                    }
                }
            }

            Menu {
                if let record = library.selectedRecord {
                    Button("Check Connection") {
                        Task { await library.check(record) }
                    }
                }
                Button("Import Connections…") {
                    importConnections()
                }
                Button("Export Connections…") {
                    exportConnections()
                }
                .disabled(library.records.isEmpty)
                if !isCreating {
                    Divider()
                    Button("Delete Connection", role: .destructive) {
                        Task {
                            await library.deleteSelected()
                            selectFirstConnection()
                        }
                    }
                }
            } label: {
                Label("More Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var connectionForm: some View {
        Form {
            Section("SSH Destination") {
                TextField("Name", text: $draft.name)
                TextField("Host", text: $draft.host)
                    .textContentType(.URL)
                TextField("User (optional)", text: $draft.user)
                LabeledContent("Port") {
                    TextField("Port", value: $draft.port, format: .number)
                        .frame(width: 90)
                }
                TextField("Group", text: $draft.groupName)
                TextField("Tags (comma separated)", text: $draft.tags)
            }

            Section("Advanced") {
                TextField("Identity file (optional)", text: $draft.identityFile)
                TextField("ProxyJump (optional)", text: $draft.proxyJump)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...4)
                Toggle(
                    "Check saved targets every minute",
                    isOn: $connectionMonitoringEnabled
                )
            }

            if let message = validationMessage ?? library.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }
            if let operationMessage {
                Text(operationMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var filteredRecords: [ConnectionRecord] {
        guard !searchText.isEmpty else {
            return library.records
        }
        return library.records.filter {
            [$0.name, $0.host, $0.user, $0.groupName, $0.tags.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func destination(for record: ConnectionRecord) -> String {
        let user = record.user.isEmpty ? "" : "\(record.user)@"
        return "\(user)\(record.host):\(record.port)"
    }

    private func reachabilityColor(for record: ConnectionRecord) -> Color {
        switch library.reachability[record.id] ?? .unchecked {
        case .reachable:
            return .green
        case .unreachable:
            return .red
        case .checking:
            return .orange
        case .unchecked:
            return .secondary.opacity(0.5)
        }
    }

    private func beginNewConnection() {
        library.selectedID = nil
        draft = SSHConnectionDraft()
        validationMessage = nil
        operationMessage = nil
        isCreating = true
        isShowingTerminal = false
    }

    private func selectFirstConnection() {
        if let first = library.records.first {
            library.selectedID = first.id
            draft = first.draft
            isCreating = false
        } else {
            library.selectedID = nil
            draft = SSHConnectionDraft()
            isCreating = false
        }
    }

    private func selectAndConnect(_ record: ConnectionRecord) {
        library.selectedID = record.id
        draft = record.draft
        connect()
    }

    private func connect() {
        do {
            let configuration = try SSHCommandBuilder.configuration(for: draft)
            workspace.createSession(
                configuration: configuration,
                title: draft.displayName
            )
            validationMessage = nil
            isShowingTerminal = true
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func importConnections() {
        guard let url = ConnectionArchivePanel.chooseImportURL() else {
            return
        }
        Task {
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: url.path
                )
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard size <= ConnectionArchiveCodec.maximumBytes else {
                    throw ConnectionArchiveError.tooLarge
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if await library.importArchive(data) {
                    operationMessage = "Connections imported."
                    draft = SSHConnectionDraft()
                }
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    private func exportConnections() {
        guard let url = ConnectionArchivePanel.chooseExportURL() else {
            return
        }
        do {
            let data = try library.exportArchive()
            try data.write(to: url, options: [.atomic])
            operationMessage = "Connections exported."
        } catch {
            operationMessage = error.localizedDescription
        }
    }
}
