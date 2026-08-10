import XCTest
@testable import GameLog

final class LogBufferTests: XCTestCase {
    func testMaintainsRingCapacity() {
        var buffer = LogBuffer(capacity: 3)
        let events = (0..<5).map(makeEvent)

        let removed = buffer.append(contentsOf: events)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(buffer.events.count, 3)
        XCTAssertEqual(buffer.events.map(\.message), ["2", "3", "4"])
    }

    func testShrinkingCapacityDropsOldestEvents() {
        var buffer = LogBuffer(capacity: 5)
        buffer.append(contentsOf: (0..<5).map(makeEvent))

        buffer.updateCapacity(2)

        XCTAssertEqual(buffer.events.map(\.message), ["3", "4"])
    }

    private func makeEvent(_ index: Int) -> LogEvent {
        LogEvent(
            timestampText: "",
            pid: 1,
            tid: 1,
            level: .info,
            tag: "Test",
            message: String(index),
            rawText: String(index)
        )
    }
}
