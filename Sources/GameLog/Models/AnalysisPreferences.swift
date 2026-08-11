import Foundation

enum SessionImportIntegrityStatus: String, Codable, Sendable {
    case verified
    case legacyUnverified

    var title: String {
        switch self {
        case .verified: String(localized: "完整性已验证")
        case .legacyUnverified: String(localized: "旧格式，未提供校验清单")
        }
    }
}

enum SessionImportPreviewDisposition: String, Codable, Sendable {
    case newSession
    case mergeAnnotation

    var title: String {
        switch self {
        case .newSession: String(localized: "导入为新会话")
        case .mergeAnnotation: String(localized: "仅合并注释与标签")
        }
    }
}

struct SessionImportPreview: Identifiable, Hashable, Sendable {
    let sourceURL: URL
    let sessionID: UUID
    let targetPackage: String
    let deviceDisplayName: String
    let deviceSerial: String
    let createdAt: Date
    let endedAt: Date?
    let eventCount: Int
    let artifactCount: Int
    let screenshotCount: Int
    let recordingCount: Int
    let totalByteCount: Int64
    let integrityStatus: SessionImportIntegrityStatus
    let disposition: SessionImportPreviewDisposition
    let importedTitle: String
    let importedLabels: [String]

    var id: UUID { sessionID }

    var duration: TimeInterval? {
        endedAt.map { max(0, $0.timeIntervalSince(createdAt)) }
    }
}

struct RegressionThresholds: Hashable, Codable, Sendable {
    var recurringDiagnosticIncrease: Int
    var errorAbsoluteIncrease: Int
    var errorRelativeIncrease: Double
    var tagAbsoluteIncrease: Int
    var tagRelativeIncrease: Double
    var logMinimumBaseline: Int
    var logAbsoluteIncrease: Int
    var logRelativeIncrease: Double

    static let recommended = RegressionThresholds(
        recurringDiagnosticIncrease: 1,
        errorAbsoluteIncrease: 3,
        errorRelativeIncrease: 0.25,
        tagAbsoluteIncrease: 20,
        tagRelativeIncrease: 1,
        logMinimumBaseline: 100,
        logAbsoluteIncrease: 100,
        logRelativeIncrease: 0.5
    )

    func normalized() -> RegressionThresholds {
        RegressionThresholds(
            recurringDiagnosticIncrease: max(1, recurringDiagnosticIncrease),
            errorAbsoluteIncrease: max(1, errorAbsoluteIncrease),
            errorRelativeIncrease: min(max(0, errorRelativeIncrease), 10),
            tagAbsoluteIncrease: max(1, tagAbsoluteIncrease),
            tagRelativeIncrease: min(max(0, tagRelativeIncrease), 10),
            logMinimumBaseline: max(0, logMinimumBaseline),
            logAbsoluteIncrease: max(1, logAbsoluteIncrease),
            logRelativeIncrease: min(max(0, logRelativeIncrease), 10)
        )
    }
}

struct RegressionConfiguration: Hashable, Codable, Sendable {
    let targetPackage: String
    var thresholds: RegressionThresholds
    var ignoredAlertKeys: Set<String>
    var updatedAt: Date

    static func recommended(for targetPackage: String) -> RegressionConfiguration {
        RegressionConfiguration(
            targetPackage: targetPackage,
            thresholds: .recommended,
            ignoredAlertKeys: [],
            updatedAt: .distantPast
        )
    }
}
