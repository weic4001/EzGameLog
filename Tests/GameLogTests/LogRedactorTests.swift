import XCTest
@testable import GameLog

final class LogRedactorTests: XCTestCase {
    func testRedactsRecommendedSensitiveValuesAndProducesPreview() {
        let session = makeSession()
        let raw = """
        Authorization: Bearer abcdefghijklmnop user_id=player_123 \
        email=test@example.com ip=192.168.1.2 serial=SERIAL-123 \
        path=/Users/tester/project/file.json
        """
        let event = LogEvent(
            timestampText: "12:00:00.000",
            pid: 1,
            tid: 1,
            level: .info,
            tag: "Auth",
            message: raw,
            rawText: raw,
            buffer: .main
        )

        let redacted = LogRedactor.redact(
            event: event,
            configuration: .recommended,
            deviceSerial: session.device.serial
        )
        let preview = LogRedactor.preview(
            events: [event],
            session: session
        )

        XCTAssertFalse(redacted.rawText.contains("abcdefghijklmnop"))
        XCTAssertFalse(redacted.rawText.contains("player_123"))
        XCTAssertFalse(redacted.rawText.contains("test@example.com"))
        XCTAssertFalse(redacted.rawText.contains("192.168.1.2"))
        XCTAssertFalse(redacted.rawText.contains("SERIAL-123"))
        XCTAssertFalse(redacted.rawText.contains("/Users/tester"))
        XCTAssertGreaterThanOrEqual(preview.totalMatchCount, 6)
        XCTAssertNotNil(preview.sampleAfter)
    }

    func testDisabledConfigurationPreservesEvent() {
        let event = LogEvent(
            timestampText: "12:00:00.000",
            pid: nil,
            tid: nil,
            level: .info,
            tag: "Auth",
            message: "Bearer abcdefgh",
            rawText: "Bearer abcdefgh"
        )
        XCTAssertEqual(
            LogRedactor.redact(
                event: event,
                configuration: .disabled,
                deviceSerial: "SERIAL"
            ),
            event
        )
    }

    func testAppliesPackageScopedCustomRuleAndReportsItsCount() {
        let session = makeSession()
        let rule = CustomRedactionRule(
            name: "游戏会话 ID",
            pattern: #"session-[A-Z0-9]{6}"#,
            replacement: "‹SESSION›",
            packagePattern: "com.example.*"
        )
        let configuration = RedactionConfiguration(
            isEnabled: true,
            categories: [],
            customRules: [rule]
        )
        let event = LogEvent(
            timestampText: "12:00:00.000",
            pid: 1,
            tid: 1,
            level: .info,
            tag: "Game",
            message: "join session-ABC123",
            rawText: "join session-ABC123"
        )

        XCTAssertTrue(rule.applies(to: session.targetPackage))
        XCTAssertFalse(rule.applies(to: "org.other.game"))
        let redacted = LogRedactor.redact(
            event: event,
            configuration: configuration,
            deviceSerial: session.device.serial
        )
        let preview = LogRedactor.preview(
            events: [event],
            session: session,
            configuration: configuration
        )

        XCTAssertEqual(redacted.message, "join ‹SESSION›")
        XCTAssertEqual(preview.customRuleCounts[rule.id], 1)
        XCTAssertEqual(preview.totalMatchCount, 1)
    }

    private func makeSession() -> DebugSession {
        DebugSession(
            id: UUID(),
            createdAt: Date(),
            endedAt: nil,
            timeZoneIdentifier: "UTC",
            device: AndroidDevice(
                serial: "SERIAL-123",
                state: .online,
                model: "Device",
                product: "test",
                transportID: "1"
            ),
            targetPackage: "com.example.game",
            initialPIDs: [1],
            adbPath: "/Users/tester/Library/Android/sdk/platform-tools/adb",
            adbVersion: "1.0.41",
            buffers: [.main, .crash],
            initialPreset: .all,
            initialFilterConfiguration: nil,
            artifacts: []
        )
    }
}
