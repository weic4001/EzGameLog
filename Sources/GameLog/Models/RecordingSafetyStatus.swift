import Foundation

enum RecordingSafetyLevel: String, Codable, Sendable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: "空间充足"
        case .warning: "空间偏低"
        case .critical: "空间严重不足"
        }
    }
}

struct RecordingSafetyStatus: Equatable, Codable, Sendable {
    let macAvailableBytes: Int64
    let deviceAvailableBytes: Int64?
    let estimatedMacRemainingSeconds: TimeInterval?
    let level: RecordingSafetyLevel
    let checkedAt: Date

    static let unavailable = RecordingSafetyStatus(
        macAvailableBytes: 0,
        deviceAvailableBytes: nil,
        estimatedMacRemainingSeconds: nil,
        level: .normal,
        checkedAt: .distantPast
    )
}
