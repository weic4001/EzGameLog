import XCTest
@testable import GameLog

final class LogcatParserTests: XCTestCase {
    func testParsesYearAndTimeZoneIntoUnambiguousDate() throws {
        var parser = LogcatParser()
        let line = "2026-07-23 11:51:25.042 +0800  3676  3676 I SystemUi: Ready\n"

        let events = parser.consume(Data(line.utf8)) + parser.finish()

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.timestampText, "11:51:25.042")
        XCTAssertEqual(event.pid, 3676)
        XCTAssertEqual(event.tid, 3676)
        XCTAssertEqual(event.tag, "SystemUi")
        XCTAssertEqual(event.message, "Ready")
        XCTAssertEqual(
            ISO8601DateFormatter().string(from: event.occurredAt),
            "2026-07-23T03:51:25Z"
        )
    }

    func testParsesThreadtimeAcrossChunks() {
        var parser = LogcatParser()
        let first = Data("07-23 10:12:13.123  1234  1240 I Unity   : Scene loaded\n07-23 10:12".utf8)
        let second = Data(":14.456  1234  1240 E Game    : Boom\n07-23 10:12:15.000  1234  1240 D Game    : Next\n".utf8)

        XCTAssertTrue(parser.consume(first).isEmpty)
        let parsed = parser.consume(second)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].tag, "Unity")
        XCTAssertEqual(parsed[0].message, "Scene loaded")
        XCTAssertEqual(parsed[0].level, .info)
        XCTAssertEqual(parsed[1].level, .error)

        let trailing = parser.finish()
        XCTAssertEqual(trailing.count, 1)
        XCTAssertEqual(trailing[0].message, "Next")
    }

    func testJoinsStackTraceLines() {
        var parser = LogcatParser()
        let input = Data("07-23 10:12:14.456  1234  1240 E Game: Crash\njava.lang.IllegalStateException\n    at game.Main.run(Main.java:1)\n07-23 10:12:15.000  1234  1240 I Game: Recovered\n".utf8)

        let parsed = parser.consume(input)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].message.contains("IllegalStateException"))
        XCTAssertTrue(parsed[0].message.contains("Main.java:1"))
    }

    func testEmitsBufferMarker() {
        var parser = LogcatParser()
        let parsed = parser.consume(Data("--------- beginning of crash\n07-23 10:12:15.000  1234  1240 I Game: Ready\n".utf8))

        XCTAssertEqual(parsed.count, 1)
        XCTAssertTrue(parsed[0].isMarker)
        XCTAssertEqual(parsed[0].tag, "Logcat")
    }
}
