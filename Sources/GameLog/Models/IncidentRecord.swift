import Foundation

struct IncidentRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let eventID: UUID
    var title: String
    var note: String
    var evidenceIDs: [UUID]
    var recordingID: UUID?
    var recordingOffset: TimeInterval?
    let logWindowBefore: TimeInterval
    let logWindowAfter: TimeInterval

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        eventID: UUID,
        title: String,
        note: String = "",
        evidenceIDs: [UUID] = [],
        recordingID: UUID? = nil,
        recordingOffset: TimeInterval? = nil,
        logWindowBefore: TimeInterval = 30,
        logWindowAfter: TimeInterval = 30
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventID = eventID
        self.title = title
        self.note = note
        self.evidenceIDs = evidenceIDs
        self.recordingID = recordingID
        self.recordingOffset = recordingOffset
        self.logWindowBefore = logWindowBefore
        self.logWindowAfter = logWindowAfter
    }
}

struct IncidentPackageManifest: Codable, Sendable {
    let generatedAt: Date
    let incident: IncidentRecord
    let sessionID: UUID
    let targetPackage: String
    let deviceDisplayName: String
    let diagnosticIssues: [DiagnosticIssue]
    let redactionApplied: Bool
}
