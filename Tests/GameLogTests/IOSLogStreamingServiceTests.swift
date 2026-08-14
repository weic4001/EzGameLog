import XCTest
@testable import GameLog

final class IOSLogStreamingServiceTests: XCTestCase {
    func testStreamsFilteredIOSProcessLogs() async throws {
        let fake = FakeIOSDeviceExecutor(
            runHandler: { _, _ in FakeIOSDeviceExecutor.result("") },
            streamedChunks: [
                Data("Aug 11 09:58:01.123456 ExampleGame[42] <Info>: Ready\n".utf8)
            ]
        )
        var events: [LogEvent] = []
        for try await batch in IOSLogStreamingService(executor: fake).events(
            serial: "00008120-TEST",
            processName: "ExampleGame"
        ) {
            events += batch
        }
        XCTAssertEqual(events.map(\.message), ["Ready"])
    }
}
