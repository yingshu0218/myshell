import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case open(String)
    case execute(String)
    case prepare(String)
    case bind(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Unable to open the database: \(message)"
        case .execute(let message): "Database operation failed: \(message)"
        case .prepare(let message): "Unable to prepare database operation: \(message)"
        case .bind(let message): "Unable to bind database value: \(message)"
        case .decode(let message): "Unable to decode database value: \(message)"
        }
    }
}

enum SyncedConnectionMutation: Sendable {
    case upsert(ConnectionRecord)
    case delete(recordID: UUID, version: Int64, updatedAt: Date)
}

enum SyncedCommandGroupMutation: Sendable {
    case upsert(CommandGroupRecord)
    case delete(recordID: UUID, version: Int64, updatedAt: Date)
}

enum SyncedAppMutation: Sendable {
    case connection(SyncedConnectionMutation)
    case commandGroup(SyncedCommandGroupMutation)
}

actor SQLiteConnectionStore {
    nonisolated(unsafe) private let database: OpaquePointer
    private var isClosed = false
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown error"
            sqlite3_close(handle)
            throw DatabaseError.open(message)
        }
        database = handle
        try Self.initializeDatabase(handle)
    }

    deinit {
        if !isClosed {
            sqlite3_close(database)
        }
    }

    func close() {
        guard !isClosed else { return }
        sqlite3_close_v2(database)
        isClosed = true
    }

    func fetchActiveConnections() throws -> [ConnectionRecord] {
        let sql = """
        SELECT id, name, host, user, port, identity_file, proxy_jump,
               group_name, tags_json, notes, created_at, updated_at,
               deleted_at, server_version
        FROM connections
        WHERE deleted_at IS NULL
        ORDER BY name COLLATE NOCASE, host COLLATE NOCASE
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var records: [ConnectionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(try decodeRecord(statement))
        }
        return records
    }

    func fetchConnectionsNeedingSync() throws -> [ConnectionRecord] {
        let sql = """
        SELECT id, name, host, user, port, identity_file, proxy_jump,
               group_name, tags_json, notes, created_at, updated_at,
               deleted_at, server_version
        FROM connections
        WHERE needs_sync = 1
        ORDER BY updated_at, id
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var records: [ConnectionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(try decodeRecord(statement))
        }
        return records
    }

    func fetchActiveCommandGroups() throws -> [CommandGroupRecord] {
        let statement = try prepare(
            """
            SELECT id, name, commands_json, created_at, updated_at,
                   deleted_at, server_version
            FROM command_groups
            WHERE deleted_at IS NULL
            ORDER BY name COLLATE NOCASE, id
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [CommandGroupRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decodeCommandGroup(statement))
        }
        return result
    }

    func fetchCommandGroupsNeedingSync() throws -> [CommandGroupRecord] {
        let statement = try prepare(
            """
            SELECT id, name, commands_json, created_at, updated_at,
                   deleted_at, server_version
            FROM command_groups
            WHERE needs_sync = 1
            ORDER BY updated_at, id
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [CommandGroupRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try decodeCommandGroup(statement))
        }
        return result
    }

    func upsertCommandGroup(_ group: CommandGroupRecord) throws {
        let value = try group.validated()
        let statement = try prepare(
            """
            INSERT INTO command_groups (
                id, name, commands_json, created_at, updated_at,
                deleted_at, server_version, needs_sync
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 1)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                commands_json = excluded.commands_json,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at,
                server_version = excluded.server_version,
                needs_sync = 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(value.id.uuidString),
            .text(value.name),
            .blob(try encoder.encode(value.commands)),
            .double(value.createdAt.timeIntervalSince1970),
            .double(value.updatedAt.timeIntervalSince1970),
            value.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            value.serverVersion.map(SQLiteValue.integer) ?? .null,
        ], to: statement)
        try stepDone(statement)
    }

    func markCommandGroupDeleted(id: UUID, at date: Date = .now) throws {
        let statement = try prepare(
            """
            UPDATE command_groups
            SET deleted_at = ?, updated_at = ?, needs_sync = 1
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .double(date.timeIntervalSince1970),
            .double(date.timeIntervalSince1970),
            .text(id.uuidString),
        ], to: statement)
        try stepDone(statement)
    }

    func markCommandGroupSyncQueued(recordID: UUID) throws {
        let statement = try prepare(
            "UPDATE command_groups SET needs_sync = 0 WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(recordID.uuidString)], to: statement)
        try stepDone(statement)
    }

    func upsert(_ record: ConnectionRecord) throws {
        let sql = """
        INSERT INTO connections (
            id, name, host, user, port, identity_file, proxy_jump,
            group_name, tags_json, notes, created_at, updated_at,
            deleted_at, server_version, needs_sync
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            host = excluded.host,
            user = excluded.user,
            port = excluded.port,
            identity_file = excluded.identity_file,
            proxy_jump = excluded.proxy_jump,
            group_name = excluded.group_name,
            tags_json = excluded.tags_json,
            notes = excluded.notes,
            updated_at = excluded.updated_at,
            deleted_at = excluded.deleted_at,
            server_version = excluded.server_version,
            needs_sync = 1
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        let tags = try encoder.encode(record.tags)
        let values: [SQLiteValue] = [
            .text(record.id.uuidString),
            .text(record.name),
            .text(record.host),
            .text(record.user),
            .integer(Int64(record.port)),
            .text(record.identityFile),
            .text(record.proxyJump),
            .text(record.groupName),
            .blob(tags),
            .text(record.notes),
            .double(record.createdAt.timeIntervalSince1970),
            .double(record.updatedAt.timeIntervalSince1970),
            record.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
            record.serverVersion.map(SQLiteValue.integer) ?? .null,
        ]
        try bind(values, to: statement)
        try stepDone(statement)
    }

    func importConnections(_ records: [ConnectionRecord]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for record in records {
                try upsert(record)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func applySyncedConnections(_ mutations: [SyncedConnectionMutation]) throws {
        try applySyncedMutations(mutations.map(SyncedAppMutation.connection))
    }

    func applySyncedMutations(_ mutations: [SyncedAppMutation]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for mutation in mutations {
                switch mutation {
                case .connection(let connection):
                    switch connection {
                    case .upsert(let record):
                        try upsertSynced(record)
                    case .delete(let id, let version, let updatedAt):
                        try applySyncedDeletion(
                            id: id,
                            version: version,
                            updatedAt: updatedAt
                        )
                    }
                case .commandGroup(let commandGroup):
                    switch commandGroup {
                    case .upsert(let record):
                        try upsertSyncedCommandGroup(record)
                    case .delete(let id, let version, let updatedAt):
                        try applySyncedCommandGroupDeletion(
                            id: id,
                            version: version,
                            updatedAt: updatedAt
                        )
                    }
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func markDeleted(id: UUID, at date: Date = .now) throws {
        let statement = try prepare(
            """
            UPDATE connections
            SET deleted_at = ?, updated_at = ?, needs_sync = 1
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [
                .double(date.timeIntervalSince1970),
                .double(date.timeIntervalSince1970),
                .text(id.uuidString),
            ],
            to: statement
        )
        try stepDone(statement)
    }

    func syncState(appID: String) throws -> SyncState {
        let statement = try prepare(
            """
            SELECT cursor, last_successful_sync_at
            FROM sync_state WHERE app_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(appID)], to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return SyncState(appID: appID, cursor: nil, lastSuccessfulSyncAt: nil)
        }
        return SyncState(
            appID: appID,
            cursor: nullableText(statement, 0),
            lastSuccessfulSyncAt: sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        )
    }

    func commitSyncCursor(
        appID: String,
        cursor: String,
        at date: Date = .now
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO sync_state (app_id, cursor, last_successful_sync_at)
            VALUES (?, ?, ?)
            ON CONFLICT(app_id) DO UPDATE SET
                cursor = excluded.cursor,
                last_successful_sync_at = excluded.last_successful_sync_at
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [.text(appID), .text(cursor), .double(date.timeIntervalSince1970)],
            to: statement
        )
        try stepDone(statement)
    }

    func enqueue(_ operation: PendingSyncOperation) throws {
        let countStatement = try prepare(
            "SELECT COUNT(*) FROM pending_sync_operations"
        )
        defer { sqlite3_finalize(countStatement) }
        guard sqlite3_step(countStatement) == SQLITE_ROW else {
            throw DatabaseError.execute(errorMessage)
        }
        guard sqlite3_column_int64(countStatement, 0)
                < PendingSyncOperation.maximumQueuedOperations else {
            throw DatabaseError.execute("sync queue limit reached")
        }

        let statement = try prepare(
            """
            INSERT INTO pending_sync_operations (
                id, kind, collection, record_id, base_version,
                encrypted_payload, checksum, idempotency_key,
                created_at, retry_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [
                .text(operation.id.uuidString),
                .text(operation.kind.rawValue),
                .text(operation.collection),
                .text(operation.recordID.uuidString),
                .integer(operation.baseVersion),
                operation.encryptedPayload.map(SQLiteValue.blob) ?? .null,
                operation.checksum.map(SQLiteValue.text) ?? .null,
                .text(operation.idempotencyKey.uuidString),
                .double(operation.createdAt.timeIntervalSince1970),
                .integer(Int64(operation.retryCount)),
            ],
            to: statement
        )
        try stepDone(statement)
    }

    func enqueueAndMarkQueued(_ operation: PendingSyncOperation) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try enqueue(operation)
            switch operation.collection {
            case ConnectionSyncCodec.collection:
                try markSyncQueued(recordID: operation.recordID)
            case CommandGroupSyncCodec.collection:
                try markCommandGroupSyncQueued(recordID: operation.recordID)
            default:
                throw DatabaseError.execute("unsupported sync collection")
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func pendingOperations(limit: Int = 32) throws -> [PendingSyncOperation] {
        guard (1...32).contains(limit) else {
            throw DatabaseError.execute("invalid sync queue page size")
        }
        let statement = try prepare(
            """
            SELECT id, kind, collection, record_id, base_version,
                   encrypted_payload, checksum, idempotency_key,
                   created_at, retry_count
            FROM pending_sync_operations
            ORDER BY created_at, rowid
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([.integer(Int64(limit))], to: statement)
        var operations: [PendingSyncOperation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)),
                  let kind = PendingSyncOperationKind(rawValue: text(statement, 1)),
                  let recordID = UUID(uuidString: text(statement, 3)),
                  let idempotencyKey = UUID(uuidString: text(statement, 7)) else {
                throw DatabaseError.decode("invalid pending sync operation")
            }
            operations.append(PendingSyncOperation(
                id: id,
                kind: kind,
                collection: text(statement, 2),
                recordID: recordID,
                baseVersion: sqlite3_column_int64(statement, 4),
                encryptedPayload: sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil : blob(statement, 5),
                checksum: nullableText(statement, 6),
                idempotencyKey: idempotencyKey,
                createdAt: Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 8)
                ),
                retryCount: Int(sqlite3_column_int64(statement, 9))
            ))
        }
        return operations
    }

    func removePendingOperation(id: UUID) throws {
        let statement = try prepare(
            "DELETE FROM pending_sync_operations WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(id.uuidString)], to: statement)
        try stepDone(statement)
    }

    func saveConflict(
        operationID: UUID,
        remote: SyncRecordEnvelope,
        at date: Date = .now
    ) throws {
        guard let recordID = UUID(uuidString: remote.recordID) else {
            throw DatabaseError.decode("conflict has invalid record ID")
        }
        let statement = try prepare(
            """
            INSERT INTO sync_conflicts (
                operation_id, collection, record_id, remote_envelope, detected_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(operation_id) DO UPDATE SET
                remote_envelope = excluded.remote_envelope,
                detected_at = excluded.detected_at
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(operationID.uuidString),
            .text(remote.collection),
            .text(recordID.uuidString),
            .blob(try encoder.encode(remote)),
            .double(date.timeIntervalSince1970),
        ], to: statement)
        try stepDone(statement)
    }

    func fetchConflicts() throws -> [StoredSyncConflict] {
        let statement = try prepare(
            """
            SELECT operation_id, collection, record_id, remote_envelope, detected_at
            FROM sync_conflicts
            ORDER BY detected_at, operation_id
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [StoredSyncConflict] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let operationID = UUID(uuidString: text(statement, 0)),
                  let recordID = UUID(uuidString: text(statement, 2)),
                  let remote = try? decoder.decode(
                      SyncRecordEnvelope.self,
                      from: blob(statement, 3)
                  ) else {
                throw DatabaseError.decode("invalid stored sync conflict")
            }
            result.append(StoredSyncConflict(
                operationID: operationID,
                collection: text(statement, 1),
                recordID: recordID,
                remote: remote,
                detectedAt: Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 4)
                )
            ))
        }
        return result
    }

    func resolveConflictKeepingLocal(_ conflict: StoredSyncConflict) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let update = try prepare(
                """
                UPDATE pending_sync_operations
                SET base_version = ?, idempotency_key = ?, retry_count = 0
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(update) }
            try bind([
                .integer(conflict.remote.version),
                .text(UUID().uuidString),
                .text(conflict.operationID.uuidString),
            ], to: update)
            try stepDone(update)
            try deleteConflict(operationID: conflict.operationID)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func resolveConflictKeepingRemote(_ conflict: StoredSyncConflict) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let pending = try prepare(
                "DELETE FROM pending_sync_operations WHERE id = ?"
            )
            defer { sqlite3_finalize(pending) }
            try bind([.text(conflict.operationID.uuidString)], to: pending)
            try stepDone(pending)
            try deleteConflict(operationID: conflict.operationID)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func markSyncQueued(recordID: UUID) throws {
        let statement = try prepare(
            "UPDATE connections SET needs_sync = 0 WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(recordID.uuidString)], to: statement)
        try stepDone(statement)
    }

    func resetSync(appID: String) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let state = try prepare("DELETE FROM sync_state WHERE app_id = ?")
            defer { sqlite3_finalize(state) }
            try bind([.text(appID)], to: state)
            try stepDone(state)

            // The current queue belongs to the single configured Sync Hub app.
            try execute("DELETE FROM sync_conflicts")
            try execute("DELETE FROM pending_sync_operations")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private nonisolated static func initializeDatabase(
        _ database: OpaquePointer
    ) throws {
        try execute(database, "PRAGMA foreign_keys = ON")
        try execute(database, "PRAGMA journal_mode = WAL")
        try execute(database, "BEGIN IMMEDIATE")
        do {
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS connections (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    host TEXT NOT NULL,
                    user TEXT NOT NULL DEFAULT '',
                    port INTEGER NOT NULL,
                    identity_file TEXT NOT NULL DEFAULT '',
                    proxy_jump TEXT NOT NULL DEFAULT '',
                    group_name TEXT NOT NULL DEFAULT '',
                    tags_json BLOB NOT NULL,
                    notes TEXT NOT NULL DEFAULT '',
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_version INTEGER,
                    needs_sync INTEGER NOT NULL DEFAULT 1
                )
                """
            )
            if !columnExists(database, table: "connections", column: "needs_sync") {
                try execute(
                    database,
                    """
                    ALTER TABLE connections
                    ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 1
                    """
                )
            }
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS command_groups (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    commands_json BLOB NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    deleted_at REAL,
                    server_version INTEGER,
                    needs_sync INTEGER NOT NULL DEFAULT 1
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS sync_record_versions (
                    collection TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    server_version INTEGER NOT NULL,
                    deleted INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (collection, record_id)
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS sync_conflicts (
                    operation_id TEXT PRIMARY KEY NOT NULL,
                    collection TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    remote_envelope BLOB NOT NULL,
                    detected_at REAL NOT NULL,
                    FOREIGN KEY (operation_id)
                        REFERENCES pending_sync_operations(id) ON DELETE CASCADE
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value BLOB NOT NULL
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS sync_state (
                    app_id TEXT PRIMARY KEY NOT NULL,
                    cursor TEXT,
                    last_successful_sync_at REAL
                )
                """
            )
            try execute(
                database,
                """
                CREATE TABLE IF NOT EXISTS pending_sync_operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    kind TEXT NOT NULL,
                    collection TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    base_version INTEGER NOT NULL,
                    encrypted_payload BLOB,
                    checksum TEXT,
                    idempotency_key TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    retry_count INTEGER NOT NULL DEFAULT 0
                )
                """
            )
            try execute(
                database,
                """
                CREATE INDEX IF NOT EXISTS pending_sync_created_at
                ON pending_sync_operations(created_at)
                """
            )
            try execute(database, "PRAGMA user_version = 6")
            try execute(database, "COMMIT")
        } catch {
            try? execute(database, "ROLLBACK")
            throw error
        }
    }

    private nonisolated static func execute(
        _ database: OpaquePointer,
        _ sql: String
    ) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.execute(String(cString: sqlite3_errmsg(database)))
        }
    }

    private nonisolated static func columnExists(
        _ database: OpaquePointer,
        table: String,
        column: String
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(table))",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column {
                return true
            }
        }
        return false
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.execute(errorMessage)
        }
    }

    private func upsertSynced(_ record: ConnectionRecord) throws {
        let sql = """
        INSERT INTO connections (
            id, name, host, user, port, identity_file, proxy_jump,
            group_name, tags_json, notes, created_at, updated_at,
            deleted_at, server_version, needs_sync
        ) VALUES (?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?, NULL, ?, 0)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            host = excluded.host,
            user = excluded.user,
            port = excluded.port,
            proxy_jump = excluded.proxy_jump,
            group_name = excluded.group_name,
            tags_json = excluded.tags_json,
            notes = excluded.notes,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at,
            deleted_at = NULL,
            server_version = excluded.server_version,
            needs_sync = 0
        WHERE excluded.server_version > COALESCE(connections.server_version, -1)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let tags = try encoder.encode(record.tags)
        try bind([
            .text(record.id.uuidString),
            .text(record.name),
            .text(record.host),
            .text(record.user),
            .integer(Int64(record.port)),
            .text(record.proxyJump),
            .text(record.groupName),
            .blob(tags),
            .text(record.notes),
            .double(record.createdAt.timeIntervalSince1970),
            .double(record.updatedAt.timeIntervalSince1970),
            .integer(record.serverVersion ?? 0),
        ], to: statement)
        try stepDone(statement)
        try updateConfirmedVersion(
            collection: ConnectionSyncCodec.collection,
            recordID: record.id,
            version: record.serverVersion ?? 0,
            deleted: false
        )
    }

    private func applySyncedDeletion(id: UUID, version: Int64, updatedAt: Date) throws {
        let statement = try prepare(
            """
            UPDATE connections
            SET deleted_at = ?, updated_at = ?, server_version = ?, needs_sync = 0
            WHERE id = ? AND ? > COALESCE(server_version, -1)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .double(updatedAt.timeIntervalSince1970),
            .double(updatedAt.timeIntervalSince1970),
            .integer(version),
            .text(id.uuidString),
            .integer(version),
        ], to: statement)
        try stepDone(statement)
        try updateConfirmedVersion(
            collection: ConnectionSyncCodec.collection,
            recordID: id,
            version: version,
            deleted: true
        )
    }

    private func updateConfirmedVersion(
        collection: String,
        recordID: UUID,
        version: Int64,
        deleted: Bool
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO sync_record_versions (
                collection, record_id, server_version, deleted
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(collection, record_id) DO UPDATE SET
                server_version = excluded.server_version,
                deleted = excluded.deleted
            WHERE excluded.server_version > sync_record_versions.server_version
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(collection),
            .text(recordID.uuidString),
            .integer(version),
            .integer(deleted ? 1 : 0),
        ], to: statement)
        try stepDone(statement)
    }

    private func upsertSyncedCommandGroup(_ group: CommandGroupRecord) throws {
        let value = try group.validated()
        let statement = try prepare(
            """
            INSERT INTO command_groups (
                id, name, commands_json, created_at, updated_at,
                deleted_at, server_version, needs_sync
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, 0)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                commands_json = excluded.commands_json,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                deleted_at = NULL,
                server_version = excluded.server_version,
                needs_sync = 0
            WHERE excluded.server_version > COALESCE(command_groups.server_version, -1)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .text(value.id.uuidString),
            .text(value.name),
            .blob(try encoder.encode(value.commands)),
            .double(value.createdAt.timeIntervalSince1970),
            .double(value.updatedAt.timeIntervalSince1970),
            .integer(value.serverVersion ?? 0),
        ], to: statement)
        try stepDone(statement)
        try updateConfirmedVersion(
            collection: CommandGroupSyncCodec.collection,
            recordID: value.id,
            version: value.serverVersion ?? 0,
            deleted: false
        )
    }

    private func applySyncedCommandGroupDeletion(
        id: UUID,
        version: Int64,
        updatedAt: Date
    ) throws {
        let statement = try prepare(
            """
            UPDATE command_groups
            SET deleted_at = ?, updated_at = ?, server_version = ?, needs_sync = 0
            WHERE id = ? AND ? > COALESCE(server_version, -1)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind([
            .double(updatedAt.timeIntervalSince1970),
            .double(updatedAt.timeIntervalSince1970),
            .integer(version),
            .text(id.uuidString),
            .integer(version),
        ], to: statement)
        try stepDone(statement)
        try updateConfirmedVersion(
            collection: CommandGroupSyncCodec.collection,
            recordID: id,
            version: version,
            deleted: true
        )
    }

    private func deleteConflict(operationID: UUID) throws {
        let statement = try prepare(
            "DELETE FROM sync_conflicts WHERE operation_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(operationID.uuidString)], to: statement)
        try stepDone(statement)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DatabaseError.prepare(errorMessage)
        }
        return statement
    }

    private func bind(
        _ values: [SQLiteValue],
        to statement: OpaquePointer
    ) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(
                    statement,
                    index,
                    value,
                    -1,
                    SQLITE_TRANSIENT
                )
            case .blob(let data):
                result = data.withUnsafeBytes {
                    sqlite3_bind_blob(
                        statement,
                        index,
                        $0.baseAddress,
                        Int32($0.count),
                        SQLITE_TRANSIENT
                    )
                }
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bind(errorMessage)
            }
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.execute(errorMessage)
        }
    }

    private func decodeRecord(
        _ statement: OpaquePointer
    ) throws -> ConnectionRecord {
        guard let id = UUID(uuidString: text(statement, 0)) else {
            throw DatabaseError.decode("invalid connection ID")
        }
        let tagsData = blob(statement, 8)
        guard let tags = try? decoder.decode([String].self, from: tagsData) else {
            throw DatabaseError.decode("invalid tags")
        }
        return ConnectionRecord(
            id: id,
            name: text(statement, 1),
            host: text(statement, 2),
            user: text(statement, 3),
            port: Int(sqlite3_column_int64(statement, 4)),
            identityFile: text(statement, 5),
            proxyJump: text(statement, 6),
            groupName: text(statement, 7),
            tags: tags,
            notes: text(statement, 9),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
            deletedAt: sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 12)),
            serverVersion: sqlite3_column_type(statement, 13) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 13)
        )
    }

    private func decodeCommandGroup(
        _ statement: OpaquePointer
    ) throws -> CommandGroupRecord {
        guard let id = UUID(uuidString: text(statement, 0)),
              let commands = try? decoder.decode(
                  [CommandShortcut].self,
                  from: blob(statement, 2)
              ) else {
            throw DatabaseError.decode("invalid command group")
        }
        return try CommandGroupRecord(
            id: id,
            name: text(statement, 1),
            commands: commands,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            deletedAt: sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            serverVersion: sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil
                : sqlite3_column_int64(statement, 6)
        ).validated()
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func nullableText(
        _ statement: OpaquePointer,
        _ index: Int32
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return text(statement, index)
    }

    private func blob(_ statement: OpaquePointer, _ index: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let value = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: value, count: count)
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(database))
    }
}

private enum SQLiteValue {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
