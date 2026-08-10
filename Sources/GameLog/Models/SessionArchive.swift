import Foundation

struct SessionAnnotation: Hashable, Codable, Sendable {
    var title: String
    var note: String
    var labels: [String]
    var updatedAt: Date

    static let empty = SessionAnnotation(
        title: "",
        note: "",
        labels: [],
        updatedAt: .distantPast
    )
}

struct SessionArchiveEntry: Identifiable, Hashable, Sendable {
    let session: DebugSession
    let directoryURL: URL
    let logByteCount: Int64
    let incidentCount: Int
    let annotation: SessionAnnotation
    let isInProgress: Bool

    var id: UUID { session.id }
}

struct SessionTagCount: Identifiable, Hashable, Codable, Sendable {
    let tag: String
    let count: Int

    var id: String { tag }
}

struct SessionAnalysisSnapshot: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let formatVersion: Int?
    let sessionID: UUID
    let targetPackage: String
    let deviceSerial: String
    let sessionCreatedAt: Date
    let generatedAt: Date
    let eventCount: Int
    let logEventCount: Int
    let markerCount: Int
    let levelCounts: [String: Int]
    let tagCounts: [String: Int]
    let incidentCount: Int
    let artifactCount: Int
    let logByteCount: Int64
    let diagnosticIssues: [DiagnosticIssue]

    init(
        id: UUID = UUID(),
        formatVersion: Int? = 2,
        sessionID: UUID,
        targetPackage: String,
        deviceSerial: String,
        sessionCreatedAt: Date,
        generatedAt: Date = Date(),
        eventCount: Int,
        logEventCount: Int,
        markerCount: Int,
        levelCounts: [String: Int],
        tagCounts: [String: Int],
        incidentCount: Int,
        artifactCount: Int,
        logByteCount: Int64,
        diagnosticIssues: [DiagnosticIssue]
    ) {
        self.id = id
        self.formatVersion = formatVersion
        self.sessionID = sessionID
        self.targetPackage = targetPackage
        self.deviceSerial = deviceSerial
        self.sessionCreatedAt = sessionCreatedAt
        self.generatedAt = generatedAt
        self.eventCount = eventCount
        self.logEventCount = logEventCount
        self.markerCount = markerCount
        self.levelCounts = levelCounts
        self.tagCounts = tagCounts
        self.incidentCount = incidentCount
        self.artifactCount = artifactCount
        self.logByteCount = logByteCount
        self.diagnosticIssues = diagnosticIssues
    }

    var topTags: [SessionTagCount] {
        tagCounts
            .map { SessionTagCount(tag: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.tag.localizedStandardCompare($1.tag) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    var errorCount: Int {
        (levelCounts[LogLevel.error.rawValue] ?? 0)
            + (levelCounts[LogLevel.fatal.rawValue] ?? 0)
    }
}

struct DiagnosticTrend: Identifiable, Hashable, Sendable {
    let kind: DiagnosticIssueKind
    let signature: String
    let title: String
    let firstOccurredAt: Date
    let lastOccurredAt: Date
    let sessionCount: Int
    let occurrenceCount: Int
    let sessionIDs: [UUID]
    let symbolHint: String?
    let sourceLocationHint: String?

    var id: String { "\(kind.rawValue):\(signature)" }
}

struct SessionMetricDelta: Identifiable, Hashable, Sendable {
    let title: String
    let baseline: Int
    let comparison: Int

    var id: String { title }
    var delta: Int { comparison - baseline }
}

struct SessionComparison: Hashable, Sendable {
    let baselineSessionID: UUID
    let comparisonSessionID: UUID
    let metrics: [SessionMetricDelta]
    let addedDiagnostics: [DiagnosticIssue]
    let resolvedDiagnostics: [DiagnosticIssue]
    let recurringDiagnostics: [DiagnosticIssue]
    let changedTags: [SessionMetricDelta]
}
