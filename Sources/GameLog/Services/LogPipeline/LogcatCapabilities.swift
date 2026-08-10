import Foundation

struct LogcatCapabilities: Equatable, Sendable {
    let supportsPIDFilter: Bool
    let supportsYearModifier: Bool
    let supportsZoneModifier: Bool
    let supportsTailFrom: Bool

    static let conservative = LogcatCapabilities(
        supportsPIDFilter: false,
        supportsYearModifier: false,
        supportsZoneModifier: false,
        supportsTailFrom: false
    )

    static func parse(helpText: String) -> LogcatCapabilities {
        let normalized = helpText.replacingOccurrences(of: "\r\n", with: "\n")
        return LogcatCapabilities(
            supportsPIDFilter: normalized.contains("--pid=PID"),
            supportsYearModifier: normalized.range(
                of: #"(?m)^\s+year\s+Add the year"#,
                options: .regularExpression
            ) != nil,
            supportsZoneModifier: normalized.range(
                of: #"(?m)^\s+zone\s+Add the local timezone"#,
                options: .regularExpression
            ) != nil,
            supportsTailFrom: normalized.range(
                of: #"(?m)^\s+-T\s"#,
                options: .regularExpression
            ) != nil
        )
    }
}
