@preconcurrency import Foundation

protocol SymbolizerExecuting: Sendable {
    func symbolize(
        executableURL: URL,
        objectURL: URL,
        address: String
    ) async throws -> String
}

struct LLVMSymbolizerExecutor: SymbolizerExecuting {
    func symbolize(
        executableURL: URL,
        objectURL: URL,
        address: String
    ) async throws -> String {
        let controller = SmallToolProcess(
            executableURL: executableURL,
            arguments: [
                "--obj=\(objectURL.path)",
                "--demangle",
                "--functions=linkage",
                "--inlines",
                "--output-style=GNU",
                "0x\(address)"
            ]
        )
        let execute: @Sendable () async throws -> String = {
            try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try controller.run()
                }.value
            } onCancel: {
                controller.cancel()
            }
        }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await execute()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw NativeSymbolicationError.toolTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }
}

enum NativeSymbolicationService {
    static func parseFrames(issues: [DiagnosticIssue]) -> [NativeStackFrame] {
        issues
            .filter { $0.kind == .nativeCrash }
            .flatMap { issue in
                issue.summary
                    .split(whereSeparator: \.isNewline)
                    .compactMap { parseFrame(line: String($0), diagnosticID: issue.id) }
            }
    }

    static func symbolicate(
        sessionID: UUID,
        targetPackage: String,
        issues: [DiagnosticIssue],
        catalog: SymbolCatalog,
        symbolizerURL: URL,
        executor: any SymbolizerExecuting = LLVMSymbolizerExecutor()
    ) async throws -> SessionSymbolicationReport {
        let frames = parseFrames(issues: issues)
        let packageFiles = catalog.files(for: targetPackage)
        var results: [SymbolicatedNativeFrame] = []
        results.reserveCapacity(frames.count)

        for frame in frames {
            try Task.checkCancellation()
            switch resolve(frame: frame, files: packageFiles) {
            case .missing:
                if let existing = frame.existingSymbol, !existing.isEmpty {
                    results.append(SymbolicatedNativeFrame(
                        frame: frame,
                        status: .alreadySymbolicated,
                        symbolFilePath: nil,
                        sourceFrames: [
                            SymbolizedSourceFrame(
                                function: existing,
                                file: nil,
                                line: nil,
                                column: nil
                            )
                        ],
                        errorMessage: "日志已有函数名，但未找到对应符号文件。"
                    ))
                } else {
                    results.append(SymbolicatedNativeFrame(
                        frame: frame,
                        status: .missingSymbolFile,
                        symbolFilePath: nil,
                        sourceFrames: [],
                        errorMessage: "缺少 \(frame.libraryName) 的匹配符号文件。"
                    ))
                }
            case .ambiguous(let count):
                results.append(SymbolicatedNativeFrame(
                    frame: frame,
                    status: .missingSymbolFile,
                    symbolFilePath: nil,
                    sourceFrames: [],
                    errorMessage: "找到 \(count) 个同名库，缺少可用于消歧的 Build ID 或 ABI。"
                ))
            case .record(let record):
                do {
                    let output = try await executor.symbolize(
                        executableURL: symbolizerURL,
                        objectURL: URL(fileURLWithPath: record.path),
                        address: frame.address
                    )
                    let sourceFrames = parseSymbolizerOutput(output)
                    results.append(SymbolicatedNativeFrame(
                        frame: frame,
                        status: sourceFrames.isEmpty ? .unresolved : .symbolicated,
                        symbolFilePath: record.path,
                        sourceFrames: sourceFrames,
                        errorMessage: sourceFrames.isEmpty
                            ? "llvm-symbolizer 未返回可用函数或源码位置。"
                            : nil
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    results.append(SymbolicatedNativeFrame(
                        frame: frame,
                        status: .failed,
                        symbolFilePath: record.path,
                        sourceFrames: [],
                        errorMessage: error.localizedDescription
                    ))
                }
            }
        }

        return SessionSymbolicationReport(
            sessionID: sessionID,
            symbolizerPath: symbolizerURL.path,
            catalogRevision: catalog.revisedAt,
            frames: results
        )
    }

    static func parseSymbolizerOutput(_ output: String) -> [SymbolizedSourceFrame] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        var frames: [SymbolizedSourceFrame] = []
        var index = 0
        while index < lines.count {
            let function = lines[index]
            let location = index + 1 < lines.count ? lines[index + 1] : ""
            index += 2
            guard function != "??" || (!location.isEmpty && !location.hasPrefix("??")) else {
                continue
            }
            let parsedLocation = parseLocation(location)
            frames.append(SymbolizedSourceFrame(
                function: function == "??" ? "未知函数" : function,
                file: parsedLocation.file,
                line: parsedLocation.line,
                column: parsedLocation.column
            ))
        }
        return frames
    }

    private static func parseFrame(
        line: String,
        diagnosticID: UUID
    ) -> NativeStackFrame? {
        guard let expression = try? NSRegularExpression(
            pattern: #"#(\d+)\s+pc\s+([0-9a-fA-F]+)\s+(\S+)"#
        ) else {
            return nil
        }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let frameRange = Range(match.range(at: 1), in: line),
              let addressRange = Range(match.range(at: 2), in: line),
              let libraryRange = Range(match.range(at: 3), in: line),
              let frameIndex = Int(line[frameRange]) else {
            return nil
        }
        let libraryPath = String(line[libraryRange])
        let existingSymbol = capture(
            pattern: #"\((?!BuildId:)([^)+]+)(?:\+(?:0x)?[0-9a-fA-F]+)?\)"#,
            group: 1,
            in: line
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildID = capture(
            pattern: #"BuildId:\s*([0-9a-fA-F]+)"#,
            group: 1,
            in: line
        )?.lowercased()
        return NativeStackFrame(
            diagnosticID: diagnosticID,
            frameIndex: frameIndex,
            address: String(line[addressRange]).lowercased(),
            libraryPath: libraryPath,
            libraryName: URL(fileURLWithPath: libraryPath).lastPathComponent,
            existingSymbol: existingSymbol,
            buildID: buildID,
            abi: inferABI(from: libraryPath),
            rawLine: line
        )
    }

    private enum Resolution {
        case missing
        case ambiguous(Int)
        case record(SymbolFileRecord)
    }

    private static func resolve(
        frame: NativeStackFrame,
        files: [SymbolFileRecord]
    ) -> Resolution {
        var matches = files.filter {
            $0.libraryName.caseInsensitiveCompare(frame.libraryName) == .orderedSame
        }
        guard !matches.isEmpty else { return .missing }

        if let buildID = frame.buildID {
            let buildMatches = matches.filter {
                $0.buildID?.caseInsensitiveCompare(buildID) == .orderedSame
            }
            if buildMatches.count == 1 {
                return .record(buildMatches[0])
            }
            if !buildMatches.isEmpty {
                matches = buildMatches
            }
        }
        if frame.abi != .unknown {
            let abiMatches = matches.filter { $0.abi == frame.abi }
            if abiMatches.count == 1 {
                return .record(abiMatches[0])
            }
            if !abiMatches.isEmpty {
                matches = abiMatches
            }
        }
        if matches.count == 1 {
            return .record(matches[0])
        }
        return .ambiguous(matches.count)
    }

    private static func inferABI(from path: String) -> NativeABI {
        let lowercased = path.lowercased()
        if lowercased.contains("arm64") || lowercased.contains("aarch64") {
            return .arm64
        }
        if lowercased.contains("armeabi") || lowercased.contains("/arm/") {
            return .arm
        }
        if lowercased.contains("x86_64") {
            return .x86_64
        }
        if lowercased.contains("/x86/") {
            return .x86
        }
        return .unknown
    }

    private static func capture(
        pattern: String,
        group: Int,
        in value: String
    ) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let swiftRange = Range(match.range(at: group), in: value) else {
            return nil
        }
        return String(value[swiftRange])
    }

    private static func parseLocation(
        _ value: String
    ) -> (file: String?, line: Int?, column: Int?) {
        guard !value.isEmpty, !value.hasPrefix("??") else {
            return (nil, nil, nil)
        }
        guard let expression = try? NSRegularExpression(
            pattern: #"^(.*?):(\d+)(?::(\d+))?$"#
        ) else {
            return (value, nil, nil)
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              let fileRange = Range(match.range(at: 1), in: value),
              let lineRange = Range(match.range(at: 2), in: value) else {
            return (value, nil, nil)
        }
        let column = Range(match.range(at: 3), in: value).flatMap {
            Int(value[$0])
        }
        return (String(value[fileRange]), Int(value[lineRange]), column)
    }
}

private final class SmallToolProcess: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let lock = NSLock()
    private var cancelled = false

    init(executableURL: URL, arguments: [String]) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput
    }

    func run() throws -> String {
        lock.lock()
        let cancelledBeforeStart = cancelled
        lock.unlock()
        if cancelledBeforeStart {
            throw CancellationError()
        }
        try process.run()
        lock.lock()
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            process.terminate()
        }
        process.waitUntilExit()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errorOutput.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            throw NativeSymbolicationError.toolFailed(
                String(decoding: stderr, as: UTF8.self)
            )
        }
        return String(decoding: stdout, as: UTF8.self)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process.isRunning
        lock.unlock()
        if running {
            process.terminate()
        }
    }
}

enum NativeSymbolicationError: LocalizedError, Sendable {
    case toolTimedOut
    case toolFailed(String)
    case symbolizerUnavailable

    var errorDescription: String? {
        switch self {
        case .toolTimedOut:
            "llvm-symbolizer 执行超时。"
        case .toolFailed(let detail):
            detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "llvm-symbolizer 执行失败。"
                : detail
        case .symbolizerUnavailable:
            "未找到 llvm-symbolizer，请选择 Android NDK 中的可执行文件。"
        }
    }
}
