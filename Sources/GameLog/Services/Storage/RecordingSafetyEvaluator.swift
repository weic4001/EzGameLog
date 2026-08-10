import Foundation

enum RecordingSafetyEvaluator {
    static let warningThreshold: Int64 = 2_000_000_000
    static let criticalThreshold: Int64 = 500_000_000

    static func evaluate(
        macAvailableBytes: Int64,
        deviceAvailableBytes: Int64?,
        configuredBitsPerSecond: Int?
    ) -> RecordingSafetyStatus {
        let relevantValues = [macAvailableBytes, deviceAvailableBytes]
            .compactMap { $0 }
            .filter { $0 > 0 }
        let minimum = relevantValues.min() ?? 0
        let level: RecordingSafetyLevel
        if minimum > 0 && minimum < criticalThreshold {
            level = .critical
        } else if minimum > 0 && minimum < warningThreshold {
            level = .warning
        } else {
            level = .normal
        }
        let bitsPerSecond = Int64(configuredBitsPerSecond ?? 8_000_000)
        let bytesPerSecond = max(1, bitsPerSecond / 8)
        let usableBytes = max(0, macAvailableBytes - criticalThreshold)
        let estimate = macAvailableBytes > 0
            ? TimeInterval(usableBytes / bytesPerSecond)
            : nil
        return RecordingSafetyStatus(
            macAvailableBytes: macAvailableBytes,
            deviceAvailableBytes: deviceAvailableBytes,
            estimatedMacRemainingSeconds: estimate,
            level: level,
            checkedAt: Date()
        )
    }
}
