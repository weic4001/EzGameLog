import Foundation

struct LogStreamingService: Sendable {
    let executor: any ADBExecuting

    func events(
        serial: String,
        buffers: Set<LogBufferName>
    ) -> AsyncThrowingStream<[LogEvent], Error> {
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let capabilities: LogcatCapabilities
                    if let help = try? await executor.run(
                        ["logcat", "--help"],
                        serial: serial,
                        timeout: .seconds(5)
                    ) {
                        capabilities = .parse(
                            helpText: help.stdoutText + "\n" + help.stderrText
                        )
                    } else {
                        capabilities = .conservative
                    }

                    var arguments = ["logcat"]
                    for buffer in buffers where buffer != .unknown {
                        arguments += ["-b", buffer.rawValue]
                    }
                    // Keep a single unfiltered stream so switching between
                    // target PID and all-device scope never restarts ADB.
                    let format = capabilities.supportsYearModifier
                        && capabilities.supportsZoneModifier
                        ? "threadtime,year,zone"
                        : "threadtime"
                    arguments += ["-v", format]
                    if capabilities.supportsTailFrom {
                        // Start at the live edge without clearing device buffers.
                        arguments += ["-T", "1"]
                    }

                    var parser = LogcatParser()
                    let byteStream = executor.stream(arguments, serial: serial)
                    for try await data in byteStream {
                        try Task.checkCancellation()
                        let parsed = parser.consume(data)
                        if !parsed.isEmpty {
                            continuation.yield(parsed)
                        }
                    }
                    let parsedTrailing = parser.finish()
                    if !parsedTrailing.isEmpty {
                        continuation.yield(parsedTrailing)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
