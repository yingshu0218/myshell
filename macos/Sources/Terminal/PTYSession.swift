import CMyShellPTY
import Darwin
import Foundation

final class PTYSession: @unchecked Sendable {
    let output: AsyncStream<Data>
    let termination: AsyncStream<Int32>
    let processIdentifier: pid_t

    private let lock = NSLock()
    private let readQueue = DispatchQueue(
        label: "com.yingshu0218.myshell.pty.read",
        qos: .userInitiated
    )
    private let waitQueue = DispatchQueue(
        label: "com.yingshu0218.myshell.pty.wait",
        qos: .utility
    )

    private var masterFileDescriptor: Int32
    private var readSource: DispatchSourceRead?
    private var isClosed = false
    private var hasTerminated = false
    private let outputContinuation: AsyncStream<Data>.Continuation
    private let terminationContinuation: AsyncStream<Int32>.Continuation

    private init(
        masterFileDescriptor: Int32,
        processIdentifier: pid_t,
        output: AsyncStream<Data>,
        outputContinuation: AsyncStream<Data>.Continuation,
        termination: AsyncStream<Int32>,
        terminationContinuation: AsyncStream<Int32>.Continuation
    ) {
        self.masterFileDescriptor = masterFileDescriptor
        self.processIdentifier = processIdentifier
        self.output = output
        self.outputContinuation = outputContinuation
        self.termination = termination
        self.terminationContinuation = terminationContinuation
    }

    deinit {
        close()
    }

    static func start(_ configuration: PTYConfiguration) throws -> PTYSession {
        guard FileManager.default.isExecutableFile(
            atPath: configuration.executable
        ) else {
            throw PTYError.invalidExecutable
        }

        if let workingDirectory = configuration.workingDirectory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: workingDirectory,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw PTYError.invalidWorkingDirectory
            }
        }

        let argv = [configuration.executable] + configuration.arguments
        let environment = configuration.environment
            .map { "\($0.key)=\($0.value)" }
            .sorted()

        let outputPair = AsyncStream<Data>.makeStream()
        let terminationPair = AsyncStream<Int32>.makeStream()

        var masterFileDescriptor: Int32 = -1
        let childPID = try withCStringArray(argv) { argvPointer in
            try withCStringArray(environment) { environmentPointer in
                try configuration.executable.withCString { executablePointer in
                    try withOptionalCString(
                        configuration.workingDirectory
                    ) { workingDirectoryPointer in
                        let result = myshell_forkpty_exec(
                            &masterFileDescriptor,
                            executablePointer,
                            argvPointer,
                            environmentPointer,
                            workingDirectoryPointer,
                            configuration.columns,
                            configuration.rows
                        )

                        guard result >= 0 else {
                            throw PTYError.launchFailed(errno)
                        }
                        return result
                    }
                }
            }
        }

        let session = PTYSession(
            masterFileDescriptor: masterFileDescriptor,
            processIdentifier: childPID,
            output: outputPair.stream,
            outputContinuation: outputPair.continuation,
            termination: terminationPair.stream,
            terminationContinuation: terminationPair.continuation
        )
        session.beginMonitoring()
        return session
    }

    func write(_ data: Data) throws {
        let fileDescriptor = try activeFileDescriptor()
        var writeError: Int32?

        data.withUnsafeBytes { bytes in
            guard var address = bytes.baseAddress else {
                return
            }

            var remaining = bytes.count
            while remaining > 0 {
                let count = Darwin.write(fileDescriptor, address, remaining)
                if count > 0 {
                    remaining -= count
                    address = address.advanced(by: count)
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    writeError = errno
                    return
                }
            }
        }

        if let writeError {
            throw PTYError.writeFailed(writeError)
        }
    }

    func write(_ text: String) throws {
        guard let data = text.data(using: .utf8) else {
            return
        }
        try write(data)
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        let fileDescriptor = try activeFileDescriptor()
        let result = myshell_resize_pty(
            fileDescriptor,
            max(columns, 1),
            max(rows, 1)
        )
        guard result == 0 else {
            throw PTYError.resizeFailed(errno)
        }
    }

    func terminate() {
        lock.lock()
        let shouldTerminate = !isClosed && !hasTerminated
        lock.unlock()

        if shouldTerminate {
            signalProcessGroupOrProcess(SIGHUP)
        }
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }

        isClosed = true
        let shouldTerminate = !hasTerminated
        let fileDescriptor = masterFileDescriptor
        masterFileDescriptor = -1
        let source = readSource
        readSource = nil
        lock.unlock()

        source?.cancel()
        if shouldTerminate {
            signalProcessGroupOrProcess(SIGKILL)
        }
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
        }
        outputContinuation.finish()
    }

    private func activeFileDescriptor() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, masterFileDescriptor >= 0 else {
            throw PTYError.closed
        }
        return masterFileDescriptor
    }

    private func signalProcessGroupOrProcess(_ signal: Int32) {
        _ = Darwin.kill(-processIdentifier, signal)
        _ = Darwin.kill(processIdentifier, signal)
    }

    private func beginMonitoring() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFileDescriptor,
            queue: readQueue
        )
        source.setEventHandler { [weak self] in
            self?.drainAvailableOutput()
        }

        lock.lock()
        readSource = source
        lock.unlock()
        source.resume()

        let processIdentifier = processIdentifier
        waitQueue.async { [weak self] in
            var status: Int32 = 0
            var result: pid_t
            repeat {
                result = Darwin.waitpid(processIdentifier, &status, 0)
            } while result < 0 && errno == EINTR

            guard result == processIdentifier else {
                self?.finish(exitCode: -1)
                return
            }
            self?.finish(exitCode: Int32(myshell_exit_code(status)))
        }
    }

    private func drainAvailableOutput() {
        guard let fileDescriptor = try? activeFileDescriptor() else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(fileDescriptor, bytes.baseAddress, bytes.count)
        }

        if count > 0 {
            outputContinuation.yield(Data(buffer.prefix(count)))
        } else if count == 0 || (count < 0 && errno != EINTR) {
            close()
        }
    }

    private func finish(exitCode: Int32) {
        lock.lock()
        hasTerminated = true
        lock.unlock()

        terminationContinuation.yield(exitCode)
        terminationContinuation.finish()
    }
}

private func withCStringArray<Result>(
    _ strings: [String],
    _ body: (
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    ) throws -> Result
) rethrows -> Result {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer {
        for pointer in pointers where pointer != nil {
            free(pointer)
        }
    }

    return try pointers.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress!)
    }
}

private func withOptionalCString<Result>(
    _ string: String?,
    _ body: (UnsafePointer<CChar>?) throws -> Result
) rethrows -> Result {
    guard let string else {
        return try body(nil)
    }
    return try string.withCString(body)
}
