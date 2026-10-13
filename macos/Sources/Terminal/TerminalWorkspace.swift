import Foundation
import Observation

@MainActor
@Observable
final class TerminalWorkspace {
    static let maximumSessionCount = 12

    private(set) var sessions: [TerminalSessionModel] = []
    var selectedSessionID: UUID?
    private(set) var lastError: String?

    init(createInitialSession: Bool = true, initialSessionCount: Int? = nil) {
        let requestedCount = initialSessionCount ?? (createInitialSession ? 1 : 0)
        let count = min(max(requestedCount, 0), Self.maximumSessionCount)
        for _ in 0..<count {
            createSession()
        }
    }

    var selectedSession: TerminalSessionModel? {
        sessions.first { $0.id == selectedSessionID }
    }

    func createSession() {
        createSession(configuration: .loginZsh(), title: "Zsh")
    }

    func createSession(
        configuration: PTYConfiguration,
        title: String
    ) {
        do {
            let session = try TerminalSessionModel(
                configuration: configuration,
                title: title
            )
            sessions.append(session)
            selectedSessionID = session.id
            lastError = nil
        } catch {
            lastError = "Unable to start \(configuration.executable)."
        }
    }

    func closeSelectedSession() {
        guard let selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
            return
        }

        sessions[index].close()
        sessions.remove(at: index)
        if sessions.isEmpty {
            self.selectedSessionID = nil
        } else {
            self.selectedSessionID = sessions[min(index, sessions.count - 1)].id
        }
    }

    func restartSelectedSession() {
        guard let selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
            return
        }
        let oldSession = sessions[index]
        let configuration = oldSession.launchConfiguration
        let title = oldSession.title
        oldSession.close()
        sessions.remove(at: index)
        createSession(configuration: configuration, title: title)
    }

    func selectNextSession() {
        moveSelection(by: 1)
    }

    func selectPreviousSession() {
        moveSelection(by: -1)
    }

    func insertCommandText(_ text: String) throws {
        guard let session = selectedSession, session.state == .running else {
            throw CommandGroupError.terminalUnavailable
        }
        let bytes = try commandBytes(for: text)
        session.send(bytes[...])
    }

    func insertCommandTextIntoAllSessions(_ text: String) throws {
        let runningSessions = sessions.filter { $0.state == .running }
        guard !runningSessions.isEmpty else {
            throw CommandGroupError.terminalUnavailable
        }
        let bytes = try commandBytes(for: text)
        for session in runningSessions {
            session.send(bytes[...])
        }
    }

    func closeAllSessions() {
        for session in sessions {
            session.close()
        }
        sessions.removeAll()
        selectedSessionID = nil
    }

    private func commandBytes(for text: String) throws -> [UInt8] {
        guard let data = text.data(using: .utf8),
              data.count <= CommandGroupRecord.maximumBatchBytes else {
            throw CommandGroupError.batchTooLarge
        }
        return [UInt8](data)
    }

    func executeCommandGroup(_ group: CommandGroupRecord) throws {
        guard let session = selectedSession, session.state == .running else {
            throw CommandGroupError.terminalUnavailable
        }
        let payload = try group.validated().executionPayload()
        let bytes = [UInt8](payload)
        session.send(bytes[...])
    }

    private func moveSelection(by offset: Int) {
        guard sessions.count > 1,
              let selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
            return
        }
        let nextIndex = (index + offset + sessions.count) % sessions.count
        self.selectedSessionID = sessions[nextIndex].id
    }
}
