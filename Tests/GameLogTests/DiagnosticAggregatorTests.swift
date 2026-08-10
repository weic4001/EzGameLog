import XCTest
@testable import GameLog

final class DiagnosticAggregatorTests: XCTestCase {
    func testAggregatesRepeatedJavaCrashesByNormalizedSignature() {
        let first = makeEvent(
            at: Date(timeIntervalSince1970: 100),
            message: "FATAL EXCEPTION: main"
        )
        let firstCause = makeEvent(
            at: Date(timeIntervalSince1970: 100.1),
            message: "java.lang.IllegalStateException: level 42 failed"
        )
        let second = makeEvent(
            at: Date(timeIntervalSince1970: 200),
            message: "FATAL EXCEPTION: main"
        )
        let secondCause = makeEvent(
            at: Date(timeIntervalSince1970: 200.1),
            message: "java.lang.IllegalStateException: level 99 failed"
        )

        let issues = DiagnosticAggregator.aggregate(
            events: [first, firstCause, second, secondCause]
        )

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .javaCrash)
        XCTAssertEqual(issues.first?.occurrenceCount, 2)
        XCTAssertTrue(issues.first?.eventIDs.contains(firstCause.id) == true)
    }

    func testRecognizesANRAndNativeCrash() {
        let issues = DiagnosticAggregator.aggregate(events: [
            makeEvent(tag: "ActivityManager", message: "ANR in com.example.game"),
            makeEvent(tag: "DEBUG", message: "Fatal signal 11 (SIGSEGV)")
        ])

        XCTAssertEqual(Set(issues.map(\.kind)), [.anr, .nativeCrash])
    }

    func testTargetScopeIgnoresCrashFromScreenCaptureProcess() {
        let targetCrash = makeEvent(
            message: "FATAL EXCEPTION: main"
        )
        let recorderCrash = makeEvent(
            tag: "DEBUG",
            message: "Fatal signal 6 (SIGABRT), pid 28916 (screencap)",
            pid: 28_916
        )

        let issues = DiagnosticAggregator.aggregate(
            events: [targetCrash, recorderCrash],
            targetPIDs: [42],
            targetPackage: "com.example.game"
        )

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.kind, .javaCrash)
    }

    func testTargetScopeRecognizesSystemANRThatNamesPackage() {
        let issue = makeEvent(
            tag: "ActivityManager",
            message: "ANR in com.example.game",
            pid: 1_000
        )

        let issues = DiagnosticAggregator.aggregate(
            events: [issue],
            targetPIDs: [42],
            targetPackage: "com.example.game"
        )

        XCTAssertEqual(issues.first?.kind, .anr)
    }

    private func makeEvent(
        at date: Date = Date(),
        tag: String = "AndroidRuntime",
        message: String,
        pid: Int = 42
    ) -> LogEvent {
        LogEvent(
            occurredAt: date,
            timestampText: "12:00:00.000",
            pid: pid,
            tid: pid,
            level: .error,
            tag: tag,
            message: message,
            rawText: message,
            buffer: .crash
        )
    }
}
