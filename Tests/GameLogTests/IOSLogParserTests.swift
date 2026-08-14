import XCTest
@testable import GameLog

final class IOSLogParserTests: XCTestCase {
    func testParsesOSTraceLinesAcrossChunksAndMapsLevels() throws {
        let reference = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-11T10:00:00+08:00")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var parser = IOSLogParser(referenceDate: reference, calendar: calendar)

        XCTAssertTrue(parser.consume(Data("Aug 11 09:58:01.123456 Example".utf8)).isEmpty)
        let first = parser.consume(Data("Game[42] <Notice>: Ready\nAug 11 09:58:02.000001 ExampleGame[42] <Fault>: Crash\n".utf8))
        let trailing = parser.finish()

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].pid, 42)
        XCTAssertEqual(first[0].tag, "ExampleGame")
        XCTAssertEqual(first[0].level, .info)
        XCTAssertEqual(first[0].message, "Ready")
        XCTAssertEqual(first[0].buffer, .system)
        XCTAssertEqual(trailing.first?.level, .fatal)
        XCTAssertEqual(trailing.first?.message, "Crash")
    }

    func testJoinsMultilineMessage() {
        var parser = IOSLogParser()
        _ = parser.consume(Data("Aug 11 09:58:01.123456 ExampleGame[42] <Error>: Failure\nframe 1\nframe 2\n".utf8))
        let events = parser.finish()
        XCTAssertEqual(events.first?.message, "Failure\nframe 1\nframe 2")
    }
}
