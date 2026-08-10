import XCTest
@testable import GameLog

final class LogcatCapabilitiesTests: XCTestCase {
    func testParsesCapabilitiesFromDeviceHelpInsteadOfAPILevel() {
        let help = """
          --pid=PID     Only print logs from the given pid.
          -T N         Print most recent lines.
            year       Add the year to the displayed time.
            zone       Add the local timezone to the displayed time.
        """

        let capabilities = LogcatCapabilities.parse(helpText: help)

        XCTAssertTrue(capabilities.supportsPIDFilter)
        XCTAssertTrue(capabilities.supportsYearModifier)
        XCTAssertTrue(capabilities.supportsZoneModifier)
        XCTAssertTrue(capabilities.supportsTailFrom)
    }

    func testMissingHelpFeaturesProducesConservativeFormat() {
        XCTAssertEqual(
            LogcatCapabilities.parse(helpText: "Usage: logcat [-v FORMAT]"),
            .conservative
        )
    }
}
