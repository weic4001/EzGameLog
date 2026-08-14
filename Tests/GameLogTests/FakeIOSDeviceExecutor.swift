import Foundation
@testable import GameLog

struct FakeIOSDeviceExecutor: IOSDeviceExecuting {
    typealias RunHandler = @Sendable (IOSDeviceTool, [String]) async throws -> ADBCommandResult

    let runHandler: RunHandler
    var streamedChunks: [Data] = []
    var streamError: Error?

    func run(
        _ tool: IOSDeviceTool,
        arguments: [String],
        timeout: Duration?
    ) async throws -> ADBCommandResult {
        try await runHandler(tool, arguments)
    }

    func stream(
        _ tool: IOSDeviceTool,
        arguments: [String]
    ) -> AsyncThrowingStream<Data, Error> {
        let chunks = streamedChunks
        let error = streamError
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    static func result(_ text: String, stderr: String = "") -> ADBCommandResult {
        ADBCommandResult(
            stdout: Data(text.utf8),
            stderr: Data(stderr.utf8),
            exitCode: 0
        )
    }
}
