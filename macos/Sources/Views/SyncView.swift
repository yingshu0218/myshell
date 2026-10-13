import CryptoKit
import SwiftUI

struct SyncView: View {
    @AppStorage("syncHubBaseURL") private var baseURL = ""
    @AppStorage("syncHubAppID") private var appID = "myshell"
    @State private var token = ""
    @State private var tokenIsStored = false
    @State private var vaultKeyIsStored = false
    @State private var recoveryKeyInput = ""
    @State private var revealedRecoveryKey = ""
    @State private var conflicts: [StoredSyncConflict] = []
    @State private var isChecking = false
    @State private var statusMessage = "Sync is not configured."
    @State private var statusIsError = false
    @State private var showDisableConfirmation = false

    private let secrets = KeychainSecretStore()

    var body: some View {
        Form {
            Section("Sync Hub") {
                TextField("Server URL", text: $baseURL, prompt: Text("https://sync.example.com"))
                    .textContentType(.URL)
                TextField("Application ID", text: $appID)
                SecureField(
                    tokenIsStored ? "Token stored in local Keychain" : "Bearer token",
                    text: $token
                )

                HStack {
                    Button("Save Token") {
                        saveToken()
                    }
                    .disabled(token.isEmpty)

                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isChecking || baseURL.isEmpty || appID.isEmpty || !tokenIsStored)

                    Button("Sync Now") {
                        Task { await syncNow() }
                    }
                    .disabled(
                        isChecking || baseURL.isEmpty || appID.isEmpty
                            || !tokenIsStored || !vaultKeyIsStored
                    )

                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Encryption Key") {
                if !vaultKeyIsStored {
                    Button("Create New Vault Key") {
                        createVaultKey()
                    }
                    SecureField("Import recovery key", text: $recoveryKeyInput)
                    Button("Import Recovery Key") {
                        importRecoveryKey()
                    }
                    .disabled(recoveryKeyInput.isEmpty)
                } else {
                    Button("Reveal Recovery Key") {
                        revealRecoveryKey()
                    }
                    if !revealedRecoveryKey.isEmpty {
                        Text(revealedRecoveryKey)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Store this offline. Anyone with it can decrypt synchronized records.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Status") {
                Label(
                    statusMessage,
                    systemImage: statusIsError
                        ? "exclamationmark.triangle"
                        : "checkmark.circle"
                )
                .foregroundStyle(statusIsError ? .red : .secondary)

                Text(
                    "Connections and non-secret quick commands use their shared v1 "
                    + "schemas and AES-256-GCM envelopes. Passwords and local key "
                    + "paths are excluded."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if !conflicts.isEmpty {
                Section("Conflicts") {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflict.recordID.uuidString)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text(
                                "Remote version \(conflict.remote.version), "
                                    + conflict.remote.updatedAt.formatted()
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack {
                                Button("Keep This Mac") {
                                    Task { await keepLocal(conflict) }
                                }
                                Button("Use Remote") {
                                    Task { await keepRemote(conflict) }
                                }
                            }
                        }
                    }
                    Text(
                        "No automatic overwrite occurs. “Keep This Mac” retries "
                            + "your encrypted value against the displayed remote version."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Local Data") {
                Button("Disable Sync and Remove Local Credentials…", role: .destructive) {
                    showDisableConfirmation = true
                }
                .disabled(!tokenIsStored)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync")
        .task {
            refreshCredentialStatus()
            await refreshConflicts()
        }
        .confirmationDialog(
            "Disable sync on this Mac?",
            isPresented: $showDisableConfirmation
        ) {
            Button("Disable and Remove", role: .destructive) {
                Task { await disableSync() }
            }
        } message: {
            Text(
                "This removes the local Sync Hub token. Saved SSH connections "
                + "remain on this Mac."
            )
        }
    }

    private func refreshCredentialStatus() {
        do {
            tokenIsStored = try secrets.load(kind: .syncHubToken) != nil
            vaultKeyIsStored = try secrets.load(kind: .vaultMasterKey) != nil
            if tokenIsStored {
                statusMessage = "A non-synchronizable local token is stored."
                statusIsError = false
            }
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func refreshConflicts() async {
        do {
            let store = try SQLiteConnectionStore(url: ApplicationPaths.databaseURL())
            conflicts = try await store.fetchConflicts()
            await store.close()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func keepLocal(_ conflict: StoredSyncConflict) async {
        do {
            let store = try SQLiteConnectionStore(url: ApplicationPaths.databaseURL())
            try await store.resolveConflictKeepingLocal(conflict)
            await store.close()
            await refreshConflicts()
            statusMessage = "Local choice saved. Run Sync Now to upload it."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func keepRemote(_ conflict: StoredSyncConflict) async {
        do {
            guard let key = try secrets.load(kind: .vaultMasterKey) else {
                throw EnvelopeError.invalidKey
            }
            let store = try SQLiteConnectionStore(url: ApplicationPaths.databaseURL())
            let applier = MyShellEnvelopeApplier(
                appID: appID,
                store: store,
                key: key
            )
            try await applier.apply([conflict.remote])
            try await store.resolveConflictKeepingRemote(conflict)
            await store.close()
            await refreshConflicts()
            statusMessage = "Remote version applied on this Mac."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func createVaultKey() {
        do {
            let key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            try secrets.save(data, kind: .vaultMasterKey)
            vaultKeyIsStored = true
            revealedRecoveryKey = try EnvelopeCrypto.recoveryKey(for: data)
            statusMessage = "A new local vault key was created."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func importRecoveryKey() {
        do {
            let key = try EnvelopeCrypto.key(fromRecoveryKey: recoveryKeyInput)
            try secrets.save(key, kind: .vaultMasterKey)
            recoveryKeyInput = ""
            revealedRecoveryKey = ""
            vaultKeyIsStored = true
            statusMessage = "The recovery key was imported into local Keychain."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func revealRecoveryKey() {
        do {
            guard let key = try secrets.load(kind: .vaultMasterKey) else {
                throw EnvelopeError.invalidKey
            }
            revealedRecoveryKey = try EnvelopeCrypto.recoveryKey(for: key)
            statusMessage = "Recovery key revealed locally. Do not share it."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func saveToken() {
        do {
            try secrets.save(Data(token.utf8), kind: .syncHubToken)
            token = ""
            tokenIsStored = true
            statusMessage = "Token saved to the local, non-synchronizable Keychain."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func testConnection() async {
        isChecking = true
        defer { isChecking = false }
        do {
            guard let url = URL(string: baseURL),
                  let savedToken = try secrets.load(kind: .syncHubToken) else {
                throw SyncHubError.missingToken
            }
            let client = try SyncHubClient(baseURL: url, appID: appID)
            _ = try await client.changes(
                cursor: nil,
                limit: 1,
                token: savedToken
            )
            statusMessage = "Sync Hub credentials are valid."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func syncNow() async {
        isChecking = true
        defer { isChecking = false }
        do {
            guard let url = URL(string: baseURL),
                  let token = try secrets.load(kind: .syncHubToken) else {
                throw SyncHubError.missingToken
            }
            guard let key = try secrets.load(kind: .vaultMasterKey) else {
                throw EnvelopeError.invalidKey
            }
            let store = try SQLiteConnectionStore(url: ApplicationPaths.databaseURL())
            defer { Task { await store.close() } }
            let client = try SyncHubClient(baseURL: url, appID: appID)
            let applier = MyShellEnvelopeApplier(
                appID: appID,
                store: store,
                key: key
            )
            let coordinator = SyncCoordinator(
                appID: appID,
                store: store,
                hub: client,
                applier: applier
            )

            _ = try await coordinator.pullUntilCaughtUp(token: token)
            let outbox = ConnectionSyncOutbox(appID: appID, store: store, key: key)
            for record in try await store.fetchConnectionsNeedingSync() {
                if record.deletedAt != nil {
                    if let version = record.serverVersion, version > 0 {
                        try await outbox.enqueueDelete(
                            recordID: record.id,
                            baseVersion: version
                        )
                    } else {
                        try await store.markSyncQueued(recordID: record.id)
                    }
                } else {
                    try await outbox.enqueueUpsert(record)
                }
            }
            let commandOutbox = CommandGroupSyncOutbox(
                appID: appID,
                store: store,
                key: key
            )
            for group in try await store.fetchCommandGroupsNeedingSync() {
                if group.deletedAt != nil {
                    if let version = group.serverVersion, version > 0 {
                        try await commandOutbox.enqueueDelete(
                            recordID: group.id,
                            baseVersion: version
                        )
                    } else {
                        try await store.markCommandGroupSyncQueued(recordID: group.id)
                    }
                } else {
                    try await commandOutbox.enqueueUpsert(group)
                }
            }
            var uploaded = 0
            while true {
                let count = try await coordinator.pushPending(token: token)
                uploaded += count
                if count == 0 { break }
            }
            let state = try await coordinator.pullUntilCaughtUp(token: token)
            statusMessage = "Sync complete: \(uploaded) upload(s). Last success: "
                + (state.lastSuccessfulSyncAt?.formatted() ?? "now")
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            await refreshConflicts()
        }
    }

    private func disableSync() async {
        do {
            try secrets.delete(kind: .syncHubToken)
            let store = try SQLiteConnectionStore(
                url: ApplicationPaths.databaseURL()
            )
            try await store.resetSync(appID: appID)
            await store.close()
            token = ""
            tokenIsStored = false
            statusMessage = "Sync is disabled and the local token was removed."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}
