import Foundation

enum DiagnosticIssueKind: String, Codable, CaseIterable, Sendable {
    case javaCrash
    case nativeCrash
    case anr

    var title: String {
        switch self {
        case .javaCrash: "Java 崩溃"
        case .nativeCrash: "Native 崩溃"
        case .anr: "ANR"
        }
    }

    var systemImage: String {
        switch self {
        case .javaCrash: "exclamationmark.bubble"
        case .nativeCrash: "waveform.path.ecg"
        case .anr: "hourglass.badge.exclamationmark"
        }
    }
}

struct DiagnosticIssue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let kind: DiagnosticIssueKind
    let signature: String
    let title: String
    let summary: String
    let firstOccurredAt: Date
    var lastOccurredAt: Date
    var occurrenceCount: Int
    var eventIDs: [UUID]

    var firstEventID: UUID? { eventIDs.first }
}
