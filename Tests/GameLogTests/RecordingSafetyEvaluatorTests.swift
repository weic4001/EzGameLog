import XCTest
@testable import GameLog

final class RecordingSafetyEvaluatorTests: XCTestCase {
    func testUsesMostConstrainedStorageForSafetyLevel() {
        let status = RecordingSafetyEvaluator.evaluate(
            macAvailableBytes: 10_000_000_000,
            deviceAvailableBytes: 300_000_000,
            configuredBitsPerSecond: 4_000_000
        )

        XCTAssertEqual(status.level, .critical)
        XCTAssertGreaterThan(status.estimatedMacRemainingSeconds ?? 0, 0)
    }

    func testEstimatesRemainingTimeConservativelyForAutomaticBitrate() {
        let status = RecordingSafetyEvaluator.evaluate(
            macAvailableBytes: 1_500_000_000,
            deviceAvailableBytes: nil,
            configuredBitsPerSecond: nil
        )

        XCTAssertEqual(status.level, .warning)
        XCTAssertEqual(status.estimatedMacRemainingSeconds, 1_000)
    }
}
