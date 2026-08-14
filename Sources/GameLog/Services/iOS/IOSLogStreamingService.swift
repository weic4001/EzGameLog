import Foundation

struct IOSLogStreamingService: Sendable {
    let executor: any IOSDeviceExecuting

    func events(
        serial: String,
        processName: String
    ) -> AsyncThrowingStream<[LogEvent], Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    guard IOSProcessName.isValid(processName) else {
                        throw IOSDeviceServiceError.invalidProcessName
                    }
                    let arguments = [
                        "--no-colors",
                        "--exit",
                        "--udid", serial,
                        "--process", processName
                    ]
                    var parser = IOSLogParser()
                    for try await data in executor.stream(
                        .deviceSyslog,
                        arguments: arguments
                    ) {
                        try Task.checkCancellation()
                        let events = parser.consume(data)
                        if !events.isEmpty {
                            continuation.yield(events)
                        }
                    }
                    let trailing = parser.finish()
                    if !trailing.isEmpty {
                        continuation.yield(trailing)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
