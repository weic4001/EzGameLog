import XCTest
@testable import GameLog

final class LogDropDetectorTests: XCTestCase {
    func testRecognizesCommonLogdDropDiagnostics() {
        let chatty = makeEvent(
            tag: "chatty",
            message: "uid=10123(com.example.game) expired 37 lines"
        )
        let logcat = makeEvent(
            tag: "Logcat",
            message: "42 lines dropped while reading buffer"
        )

        XCTAssertEqual(LogDropDetector.reportedDroppedLineCount(in: chatty), 37)
        XCTAssertEqual(LogDropDetector.reportedDroppedLineCount(in: logcat), 42)
    }

    func testDoesNotTreatApplicationMessagesAsTransportLoss() {
        let event = makeEvent(
            tag: "Game",
            message: "renderer dropped 5 lines from the debug overlay"
        )

        XCTAssertEqual(LogDropDetector.reportedDroppedLineCount(in: event), 0)
    }

    private func makeEvent(tag: String, message: String) -> LogEvent {
        LogEvent(
            timestampText: "12:00:00.000",
            pid: 42,
            tid: 42,
            level: .info,
            tag: tag,
            message: message,
            rawText: message
        )
    }
}
