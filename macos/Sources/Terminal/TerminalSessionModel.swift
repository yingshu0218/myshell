import Foundation
import Observation

@MainActor
@Observable
final class TerminalSessionModel: Identifiable {
    enum State: Equatable, Sendable {
        case running
        case exited(Int32)
        case failed(String)
    }

    let id = UUID()
    let launchConfiguration: PTYConfiguration
    private(set) var title = "Zsh"
    private(set) var currentDirectory: String?
    private(set) var state: State = .running

    @ObservationIgnored private let pty: PTYSession
    @ObservationIgnored private var replayBuffer = BoundedByteBuffer(capacity: 4 * 1024 * 1024)
    @ObservationIgnored private var outputTask: Task<Void, Never>?
    @ObservationIgnored private var terminationTask: Task<Void, Never>?
    @ObservationIgnored private var consumerID: UUID?
    @ObservationIgnored private var outputConsumer: ((Data) -> Void)?

    init(
        configuration: PTYConfiguration = .loginZsh(),
        title: String = "Zsh"
    ) throws {
        self.title = title
        launchConfiguration = configuration
        pty = try PTYSession.start(configuration)
        observeProcess()
    }

    var statusDescription: String {
        Self.statusDescription(
            for: state,
            executable: launchConfiguration.executable
        )
    }

    static func statusDescription(
        for state: State,
        executable: String
    ) -> String {
        switch state {
        case .running:
            "Running"
        case .exited(0):
            "Exited normally"
        case .exited(255) where executable == "/usr/bin/ssh":
            "SSH connection ended. Check the host, network, credentials, and host key."
        case .exited(let code):
            "Exited with status \(code)"
        case .failed(let message):
            message
        }
    }

    deinit {
        outputTask?.cancel()
        terminationTask?.cancel()
        pty.close()
    }

    func attachOutputConsumer(
        id: UUID,
        _ consumer: @escaping (Data) -> Void
    ) {
        consumerID = id
        outputConsumer = consumer
        if !replayBuffer.data.isEmpty {
            consumer(replayBuffer.data)
        }
    }

    func detachOutputConsumer(id: UUID) {
        guard consumerID == id else {
            return
        }
        consumerID = nil
        outputConsumer = nil
    }

    func send(_ bytes: ArraySlice<UInt8>) {
        do {
            try pty.write(Data(bytes))
        } catch {
            state = .failed("Unable to write to the terminal.")
        }
    }

    func resize(columns: Int, rows: Int) {
        do {
            try pty.resize(
                columns: UInt16(clamping: max(columns, 1)),
                rows: UInt16(clamping: max(rows, 1))
            )
        } catch {
            state = .failed("Unable to resize the terminal.")
        }
    }

    func updateTitle(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Zsh" : String(trimmed.prefix(80))
    }

    func updateCurrentDirectory(_ value: String?) {
        currentDirectory = value
    }

    func close() {
        pty.close()
    }

    private func observeProcess() {
        let output = pty.output
        outputTask = Task { [weak self] in
            for await chunk in output {
                guard !Task.isCancelled, let self else {
                    return
                }
                replayBuffer.append(chunk)
                outputConsumer?(chunk)
            }
        }

        let termination = pty.termination
        terminationTask = Task { [weak self] in
            for await exitCode in termination {
                guard !Task.isCancelled else {
                    return
                }
                self?.state = .exited(exitCode)
            }
        }
    }
}
