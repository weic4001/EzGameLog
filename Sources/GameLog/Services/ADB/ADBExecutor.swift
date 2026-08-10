@preconcurrency import Foundation

struct ADBCommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32

    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

struct ADBCommandError: LocalizedError, Sendable {
    let arguments: [String]
    let exitCode: Int32
    let stderr: String

    var errorDescription: String? {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "ADB 命令失败（退出码 \(exitCode)）"
            : detail
    }
}

struct ADBCommandTimeoutError: LocalizedError, Sendable {
    let arguments: [String]

    var errorDescription: String? {
        "ADB 命令执行超时。"
    }
}

protocol ADBExecuting: Sendable {
    func run(
        _ arguments: [String],
        serial: String?,
        timeout: Duration?
    ) async throws -> ADBCommandResult

    func stream(_ arguments: [String], serial: String?) -> AsyncThrowingStream<Data, Error>
}

extension ADBExecuting {
    func run(
        _ arguments: [String],
        serial: String? = nil
    ) async throws -> ADBCommandResult {
        try await run(arguments, serial: serial, timeout: nil)
    }

    func run(
        _ arguments: [String],
        timeout: Duration?
    ) async throws -> ADBCommandResult {
        try await run(arguments, serial: nil, timeout: timeout)
    }
}

final class ADBExecutor: ADBExecuting, @unchecked Sendable {
    let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func run(
        _ arguments: [String],
        serial: String? = nil,
        timeout: Duration? = nil
    ) async throws -> ADBCommandResult {
        let finalArguments = Self.arguments(arguments, serial: serial)
        let controller = ADBOneShotProcess(
            executableURL: executableURL,
            arguments: finalArguments
        )
        let execute: @Sendable () async throws -> ADBCommandResult = {
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try controller.run()
                }.value
            } onCancel: {
                controller.cancel()
            }
        }
        guard let timeout else { return try await execute() }

        return try await withThrowingTaskGroup(of: ADBCommandResult.self) { group in
            group.addTask {
                try await execute()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ADBCommandTimeoutError(arguments: finalArguments)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CancellationError()
            }
            return first
        }
    }

    func stream(_ arguments: [String], serial: String? = nil) -> AsyncThrowingStream<Data, Error> {
        let finalArguments = Self.arguments(arguments, serial: serial)
        return AsyncThrowingStream { continuation in
            let controller = ADBStreamingProcess(
                executableURL: executableURL,
                arguments: finalArguments,
                continuation: continuation
            )
            continuation.onTermination = { @Sendable _ in
                controller.cancel()
            }
            controller.start()
        }
    }

    private static func arguments(_ arguments: [String], serial: String?) -> [String] {
        guard let serial, !serial.isEmpty else { return arguments }
        return ["-s", serial] + arguments
    }
}

private final class ADBStreamingProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var stderr = Data()
    private var didFinish = false

    init(
        executableURL: URL,
        arguments: [String],
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        self.continuation = continuation
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func start() {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.continuation.yield(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendStderr(data)
        }
        process.terminationHandler = { [weak self] process in
            self?.finish(exitCode: process.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            finish(error: error)
        }
    }

    func cancel() {
        lock.lock()
        let shouldStop = !didFinish && process.isRunning
        lock.unlock()
        if shouldStop {
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.process.isRunning else { return }
                self.process.terminate()
            }
        }
    }

    private func appendStderr(_ data: Data) {
        lock.lock()
        stderr.append(data)
        lock.unlock()
    }

    private func finish(exitCode: Int32) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let stderrText = String(decoding: stderr, as: UTF8.self)
        lock.unlock()

        if exitCode == 0 || exitCode == 2 || exitCode == 15 {
            continuation.finish()
        } else {
            continuation.finish(throwing: ADBCommandError(
                arguments: process.arguments ?? [],
                exitCode: exitCode,
                stderr: stderrText
            ))
        }
    }

    private func finish(error: Error) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        continuation.finish(throwing: error)
    }
}

private final class ADBOneShotProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdout = LockedData()
    private let stderr = LockedData()
    private let lock = NSLock()
    private var isCancelled = false

    init(executableURL: URL, arguments: [String]) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    func run() throws -> ADBCommandResult {
        lock.lock()
        let cancelledBeforeStart = isCancelled
        lock.unlock()
        if cancelledBeforeStart {
            throw CancellationError()
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [stdout] handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdout.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [stderr] handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderr.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            clearHandlers()
            throw error
        }

        lock.lock()
        let cancelAfterStart = isCancelled
        lock.unlock()
        if cancelAfterStart {
            process.interrupt()
        }
        process.waitUntilExit()
        clearHandlers()
        stdout.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderr.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        lock.lock()
        let wasCancelled = isCancelled
        lock.unlock()
        if wasCancelled {
            throw CancellationError()
        }

        let result = ADBCommandResult(
            stdout: stdout.value,
            stderr: stderr.value,
            exitCode: process.terminationStatus
        )
        guard result.exitCode == 0 else {
            throw ADBCommandError(
                arguments: process.arguments ?? [],
                exitCode: result.exitCode,
                stderr: result.stderrText
            )
        }
        return result
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let running = process.isRunning
        lock.unlock()
        guard running else { return }
        process.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
    }

    private func clearHandlers() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}
