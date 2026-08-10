import Foundation
import XCTest
@testable import GameLog

final class SessionRegressionServiceTests: XCTestCase {
    func testAlignsTwoRunsUsingUniqueMatchingEvent() {
        let baselineDate = Date(timeIntervalSince1970: 1_000)
        let comparisonDate = Date(timeIntervalSince1970: 2_000)
        let baselineSession = makeSession(createdAt: baselineDate)
        let comparisonSession = makeSession(createdAt: comparisonDate)
        let baselineEvent = makeEvent(
            date: baselineDate.addingTimeInterval(10),
            message: "Loaded deterministic level tutorial"
        )
        let comparisonEvent = makeEvent(
            date: comparisonDate.addingTimeInterval(25),
            message: "Loaded deterministic level tutorial"
        )

        let alignment = SessionRegressionService.align(
            baselineSession: baselineSession,
            baselineEvents: [baselineEvent],
            baselineSnapshot: makeSnapshot(session: baselineSession),
            comparisonSession: comparisonSession,
            comparisonEvents: [comparisonEvent],
            comparisonSnapshot: makeSnapshot(session: comparisonSession)
        )

        XCTAssertEqual(alignment.method, .matchingEvent)
        XCTAssertEqual(alignment.comparisonOffset, -1_015, accuracy: 0.001)
        XCTAssertEqual(
            alignment.alignedComparisonTime(comparisonEvent.occurredAt),
            baselineEvent.occurredAt
        )
    }

    func testFallsBackToSessionStartWhenNoAnchorMatches() {
        let baselineSession = makeSession(
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let comparisonSession = makeSession(
            createdAt: Date(timeIntervalSince1970: 130)
        )

        let alignment = SessionRegressionService.align(
            baselineSession: baselineSession,
            baselineEvents: [],
            baselineSnapshot: makeSnapshot(session: baselineSession),
            comparisonSession: comparisonSession,
            comparisonEvents: [],
            comparisonSnapshot: makeSnapshot(session: comparisonSession)
        )

        XCTAssertEqual(alignment.method, .sessionStart)
        XCTAssertEqual(alignment.comparisonOffset, -30, accuracy: 0.001)
        XCTAssertEqual(alignment.confidence, 0.25)
    }

    func testRegressionReportsNewCrashErrorAndTagSpike() {
        let baselineSession = makeSession(createdAt: Date())
        let candidateSession = makeSession(createdAt: Date().addingTimeInterval(10))
        let newCrash = DiagnosticIssue(
            id: UUID(),
            kind: .nativeCrash,
            signature: "native:new",
            title: "SIGSEGV in Game::Tick",
            summary: "#00 pc 10 libgame.so",
            firstOccurredAt: Date(),
            lastOccurredAt: Date(),
            occurrenceCount: 1,
            eventIDs: [UUID()]
        )
        let baseline = makeSnapshot(
            session: baselineSession,
            logCount: 100,
            errorCount: 2,
            tags: ["Unity": 10]
        )
        let comparison = makeSnapshot(
            session: candidateSession,
            logCount: 300,
            errorCount: 10,
            tags: ["Unity": 45],
            issues: [newCrash]
        )

        let report = SessionRegressionService.regression(
            baseline: baseline,
            comparison: comparison
        )

        XCTAssertEqual(report.highestSeverity, .critical)
        XCTAssertTrue(report.alerts.contains { $0.title.contains("新增Native") })
        XCTAssertTrue(report.alerts.contains { $0.metric == "error-count" })
        XCTAssertTrue(report.alerts.contains { $0.metric == "tag.Unity" })
        XCTAssertTrue(report.alerts.contains { $0.metric == "log-count" })
    }

    func testCustomThresholdsAndIgnoredKeysReduceNoise() {
        let baselineSession = makeSession(createdAt: Date())
        let candidateSession = makeSession(
            createdAt: Date().addingTimeInterval(10)
        )
        let baseline = makeSnapshot(
            session: baselineSession,
            logCount: 100,
            errorCount: 5,
            tags: ["Unity": 20]
        )
        let comparison = makeSnapshot(
            session: candidateSession,
            logCount: 350,
            errorCount: 30,
            tags: ["Unity": 100]
        )
        var configuration = RegressionConfiguration.recommended(
            for: comparison.targetPackage
        )
        configuration.thresholds.errorAbsoluteIncrease = 100
        configuration.ignoredAlertKeys = ["tag.Unity"]

        let report = SessionRegressionService.regression(
            baseline: baseline,
            comparison: comparison,
            configuration: configuration
        )

        XCTAssertFalse(report.alerts.contains { $0.metric == "error-count" })
        XCTAssertFalse(report.alerts.contains { $0.metric == "tag.Unity" })
        XCTAssertTrue(report.alerts.contains { $0.metric == "log-count" })
        XCTAssertEqual(report.suppressedAlertCount, 1)
    }

    private func makeSession(createdAt: Date) -> DebugSession {
        DebugSession(
            id: UUID(),
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(60),
            timeZoneIdentifier: "UTC",
            device: AndroidDevice(
                serial: "serial",
                state: .online,
                model: "Device",
                product: nil,
                transportID: nil
            ),
            targetPackage: "com.example.game",
            initialPIDs: [42],
            adbPath: "/tmp/adb",
            adbVersion: "1.0.41",
            buffers: [.main],
            initialPreset: .all,
            initialFilterConfiguration: nil,
            artifacts: []
        )
    }

    private func makeEvent(date: Date, message: String) -> LogEvent {
        LogEvent(
            occurredAt: date,
            timestampText: "12:00:00.000",
            pid: 42,
            tid: 42,
            level: .info,
            tag: "Game",
            message: message,
            rawText: message,
            buffer: .main
        )
    }

    private func makeSnapshot(
        session: DebugSession,
        logCount: Int = 0,
        errorCount: Int = 0,
        tags: [String: Int] = [:],
        issues: [DiagnosticIssue] = []
    ) -> SessionAnalysisSnapshot {
        SessionAnalysisSnapshot(
            sessionID: session.id,
            targetPackage: session.targetPackage,
            deviceSerial: session.device.serial,
            sessionCreatedAt: session.createdAt,
            eventCount: logCount,
            logEventCount: logCount,
            markerCount: 0,
            levelCounts: errorCount == 0 ? [:] : ["E": errorCount],
            tagCounts: tags,
            incidentCount: 0,
            artifactCount: 0,
            logByteCount: 0,
            diagnosticIssues: issues
        )
    }
}
