import Foundation
import XCTest
@testable import GameLog

final class ADBExecutorTests: XCTestCase {
    func testOneShotCommandTimesOutAndTerminatesProcess() async throws {
        let executor = ADBExecutor(executableURL: URL(fileURLWithPath: "/bin/sh"))
        let started = Date()

        do {
            _ = try await executor.run(
                ["-c", "sleep 10"],
                timeout: .milliseconds(100)
            )
            XCTFail("Expected timeout")
        } catch is ADBCommandTimeoutError {
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        }
    }

    func testCancellingOneShotCommandTerminatesProcessPromptly() async {
        let executor = ADBExecutor(executableURL: URL(fileURLWithPath: "/bin/sleep"))
        let startedAt = Date()
        let task = Task {
            try await executor.run(["5"])
        }

        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
