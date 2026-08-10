import XCTest
@testable import GameLog

final class LogStreamingServiceTests: XCTestCase {
    func testDetectsModernFormatAndEmitsParsedDeviceLog() async throws {
        let fake = FakeADBExecutor(
            runHandler: { arguments, _ in
                XCTAssertEqual(arguments, ["logcat", "--help"])
                return FakeADBExecutor.result("""
                  -T N
                  --pid=PID
                    year       Add the year to the displayed time.
                    zone       Add the local timezone to the displayed time.
                """)
            },
            streamedChunks: [
                Data("--------- beginning of main\n".utf8),
                Data("2026-07-23 12:00:00.123 +0800  101  102 I Game: Ready\n".utf8)
            ]
        )
        let service = LogStreamingService(executor: fake)
        var events: [LogEvent] = []

        for try await batch in service.events(serial: "usb-1", buffers: [.main]) {
            events.append(contentsOf: batch)
        }

        XCTAssertEqual(events.last?.pid, 101)
        XCTAssertEqual(events.last?.tid, 102)
        XCTAssertEqual(events.last?.tag, "Game")
        XCTAssertEqual(events.last?.message, "Ready")
        XCTAssertEqual(events.last?.buffer, .main)
    }
}
