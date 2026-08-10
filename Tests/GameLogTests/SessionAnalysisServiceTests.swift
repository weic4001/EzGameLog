import XCTest
@testable import GameLog

final class SessionAnalysisServiceTests: XCTestCase {
    func testBuildsTrendsWithJavaSourceHintAcrossSessions() {
        let firstSession = makeSession(createdAt: Date(timeIntervalSince1970: 100))
        let secondSession = makeSession(createdAt: Date(timeIntervalSince1970: 200))
        let first = SessionAnalysisService.snapshot(
            session: firstSession,
            events: crashEvents(at: Date(timeIntervalSince1970: 110)),
            incidentCount: 1,
            logByteCount: 1_000
        )
        let second = SessionAnalysisService.snapshot(
            session: secondSession,
            events: crashEvents(at: Date(timeIntervalSince1970: 210)),
            incidentCount: 0,
            logByteCount: 2_000
        )

        let trends = SessionAnalysisService.trends(
            snapshots: [first, second],
            targetPackage: "com.example.game"
        )

        XCTAssertEqual(trends.count, 1)
        XCTAssertEqual(trends.first?.sessionCount, 2)
        XCTAssertEqual(trends.first?.occurrenceCount, 2)
        XCTAssertEqual(trends.first?.symbolHint, "com.example.Game.run")
        XCTAssertEqual(trends.first?.sourceLocationHint, "Game.java:42")
    }

    func testComparesMetricsTagsAndDiagnostics() {
        let baseline = SessionAnalysisService.snapshot(
            session: makeSession(createdAt: Date(timeIntervalSince1970: 100)),
            events: crashEvents(at: Date(timeIntervalSince1970: 110)),
            incidentCount: 1,
            logByteCount: 1_000
        )
        let comparison = SessionAnalysisService.snapshot(
            session: makeSession(createdAt: Date(timeIntervalSince1970: 200)),
            events: [
                makeEvent(tag: "Network", message: "request"),
                makeEvent(tag: "Network", message: "response")
            ],
            incidentCount: 0,
            logByteCount: 500
        )

        let result = SessionAnalysisService.compare(
            baseline: baseline,
            comparison: comparison
        )

        XCTAssertEqual(result.resolvedDiagnostics.count, 1)
        XCTAssertTrue(result.addedDiagnostics.isEmpty)
        XCTAssertTrue(result.changedTags.contains { $0.title == "Network" && $0.delta == 2 })
        XCTAssertEqual(result.metrics.first { $0.title == "问题标记" }?.delta, -1)
    }

    func testBuiltInEnginePresetsUseTargetScopeAndExpectedTags() {
        XCTAssertEqual(BuiltInFilterPreset.unity.configuration.pidScope, .target)
        XCTAssertTrue(
            BuiltInFilterPreset.unity.configuration.includedTags.contains("Unity")
        )
        XCTAssertTrue(
            BuiltInFilterPreset.unreal.configuration.includedTags.contains("UE")
        )
    }

    private func makeSession(createdAt: Date) -> DebugSession {
        DebugSession(
            id: UUID(),
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(30),
            timeZoneIdentifier: "UTC",
            device: AndroidDevice(
                serial: "serial-1",
                state: .online,
                model: "Device",
                product: "test",
                transportID: "1"
            ),
            targetPackage: "com.example.game",
            initialPIDs: [42],
            adbPath: "/tmp/adb",
            adbVersion: "1.0.41",
            buffers: [.main, .crash],
            initialPreset: .all,
            initialFilterConfiguration: nil,
            artifacts: []
        )
    }

    private func crashEvents(at date: Date) -> [LogEvent] {
        [
            LogEvent(
                occurredAt: date,
                timestampText: "12:00:00.000",
                pid: 42,
                tid: 42,
                level: .fatal,
                tag: "AndroidRuntime",
                message: "FATAL EXCEPTION: main",
                rawText: "FATAL EXCEPTION: main",
                buffer: .crash
            ),
            LogEvent(
                occurredAt: date.addingTimeInterval(0.1),
                timestampText: "12:00:00.100",
                pid: 42,
                tid: 42,
                level: .error,
                tag: "AndroidRuntime",
                message: "at com.example.Game.run(Game.java:42)",
                rawText: "at com.example.Game.run(Game.java:42)",
                buffer: .crash
            )
        ]
    }

    private func makeEvent(tag: String, message: String) -> LogEvent {
        LogEvent(
            timestampText: "12:00:00.000",
            pid: 42,
            tid: 42,
            level: .info,
            tag: tag,
            message: message,
            rawText: message,
            buffer: .main
        )
    }
}
