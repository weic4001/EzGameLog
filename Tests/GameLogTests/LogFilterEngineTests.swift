import XCTest
@testable import GameLog

final class LogFilterEngineTests: XCTestCase {
    func testFiltersByLevelTagPIDAndCaseInsensitiveText() throws {
        let events = [
            makeEvent(level: .info, pid: 10, tag: "Unity", message: "Scene loaded"),
            makeEvent(level: .error, pid: 20, tag: "Game", message: "Network Timeout"),
            makeEvent(level: .fatal, pid: 20, tag: "Game.Native", message: "native crash")
        ]
        var configuration = LogFilterConfiguration()
        configuration.enabledLevels = [.error, .fatal]
        configuration.includedTags = "Game"
        configuration.excludedTags = "Native"
        configuration.pidScope = .target
        configuration.query = "timeout"

        let filtered = try LogFilterEngine.filter(
            events: events,
            configuration: configuration,
            targetPIDs: [20]
        )

        XCTAssertEqual(filtered.map(\.message), ["Network Timeout"])
    }

    func testSupportsRegularExpressionAndReportsInvalidPattern() throws {
        let events = [
            makeEvent(level: .error, pid: 10, tag: "Game", message: "Error code 503")
        ]
        var configuration = LogFilterConfiguration()
        configuration.query = #"code\s+\d{3}"#
        configuration.usesRegularExpression = true
        XCTAssertEqual(
            try LogFilterEngine.filter(
                events: events,
                configuration: configuration,
                targetPIDs: [10]
            ).count,
            1
        )

        configuration.query = "("
        XCTAssertThrowsError(try LogFilterEngine.filter(
            events: events,
            configuration: configuration,
            targetPIDs: [10]
        ))
    }

    func testSystemMarkersIgnoreLevelAndPIDFilters() throws {
        let marker = LogEvent(
            timestampText: "",
            pid: nil,
            tid: nil,
            level: .info,
            tag: "GameLog",
            message: "设备已重连",
            rawText: "设备已重连",
            kind: .system
        )
        var configuration = LogFilterConfiguration()
        configuration.enabledLevels = [.fatal]
        configuration.pidScope = .target

        let filtered = try LogFilterEngine.filter(
            events: [marker],
            configuration: configuration,
            targetPIDs: [99]
        )

        XCTAssertEqual(filtered, [marker])
    }

    func testTargetScopeWithNoKnownPIDShowsMarkersButNotDeviceLogs() throws {
        let log = LogEvent(
            timestampText: "12:00:00.000",
            pid: 42,
            tid: 42,
            level: .info,
            tag: "Other",
            message: "device log",
            rawText: "device log"
        )
        let marker = LogEvent(
            timestampText: "12:00:01.000",
            pid: nil,
            tid: nil,
            level: .info,
            tag: "GameLog",
            message: "waiting",
            rawText: "waiting",
            isMarker: true
        )

        let result = try LogFilterEngine.filter(
            events: [log, marker],
            configuration: LogFilterConfiguration(),
            targetPIDs: []
        )

        XCTAssertEqual(result, [marker])
    }

    func testCustomPIDScopeIsPersistableAndFiltersMultiplePIDs() throws {
        var configuration = LogFilterConfiguration()
        configuration.pidScope = .custom
        configuration.customPIDs = "12, 34"
        let events = ([12, 23, 34] as [Int]).map { pid in
            LogEvent(
                timestampText: "12:00:00.000",
                pid: pid,
                tid: pid,
                level: .info,
                tag: "Game",
                message: "\(pid)",
                rawText: "\(pid)"
            )
        }

        let result = try LogFilterEngine.filter(
            events: events,
            configuration: configuration,
            targetPIDs: []
        )

        XCTAssertEqual(result.compactMap(\.pid), [12, 34])
        let encoded = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(LogFilterConfiguration.self, from: encoded), configuration)
    }

    func testMinimumLevelAndExplicitLevelSelectionAreCombined() throws {
        var configuration = LogFilterConfiguration()
        configuration.minimumLevel = .warning
        configuration.enabledLevels = [.warning, .fatal]
        let events = [LogLevel.info, .warning, .error, .fatal].map { level in
            LogEvent(
                timestampText: "12:00:00.000",
                pid: 1,
                tid: 1,
                level: level,
                tag: "Game",
                message: level.title,
                rawText: level.title
            )
        }

        let result = try LogFilterEngine.filter(
            events: events,
            configuration: configuration,
            targetPIDs: [1]
        )

        XCTAssertEqual(result.map(\.level), [.warning, .fatal])
    }

    private func makeEvent(
        level: LogLevel,
        pid: Int,
        tag: String,
        message: String
    ) -> LogEvent {
        LogEvent(
            timestampText: "",
            pid: pid,
            tid: pid,
            level: level,
            tag: tag,
            message: message,
            rawText: message,
            buffer: .main
        )
    }
}
