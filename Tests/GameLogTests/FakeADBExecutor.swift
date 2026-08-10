import Foundation
@testable import GameLog

struct FakeADBExecutor: ADBExecuting {
    typealias RunHandler = @Sendable ([String], String?) async throws -> ADBCommandResult

    let runHandler: RunHandler
    var streamedChunks: [Data] = []
    var streamError: Error?

    func run(
        _ arguments: [String],
        serial: String?,
        timeout: Duration?
    ) async throws -> ADBCommandResult {
        try await runHandler(arguments, serial)
    }

    func stream(_ arguments: [String], serial: String?) -> AsyncThrowingStream<Data, Error> {
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
