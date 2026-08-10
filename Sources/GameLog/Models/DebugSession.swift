import Foundation

enum DebugSessionState: String, Codable, Sendable {
    case ready
    case starting
    case capturing
    case followingPaused
    case recovering
    case stopping
    case stopped
    case failed

    var title: String {
        switch self {
        case .ready: "准备"
        case .starting: "启动中"
        case .capturing: "采集中"
        case .followingPaused: "暂停跟随"
        case .recovering: "恢复中"
        case .stopping: "停止中"
        case .stopped: "已停止"
        case .failed: "失败"
        }
    }

    var isActive: Bool {
        switch self {
        case .starting, .capturing, .followingPaused, .recovering, .stopping: true
        case .ready, .stopped, .failed: false
        }
    }
}

struct SessionArtifact: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let kind: CaptureKind
    let relativePath: String
    let thumbnailRelativePath: String?
    let createdAt: Date
    let duration: TimeInterval?
    let byteCount: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let remotePath: String?
}

struct DebugSession: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    var endedAt: Date?
    let timeZoneIdentifier: String
    let device: AndroidDevice
    let targetPackage: String
    let initialPIDs: [Int]
    var observedPIDs: [Int]? = nil
    let adbPath: String
    let adbVersion: String
    let buffers: [LogBufferName]
    let initialPreset: LogPreset
    let initialFilterConfiguration: LogFilterConfiguration?
    var artifacts: [SessionArtifact]

    var displayName: String {
        "GameLog · \(targetPackage)"
    }

    var diagnosticTargetPIDs: Set<Int> {
        Set(initialPIDs).union(observedPIDs ?? [])
    }
}

struct SessionPaths: Hashable, Sendable {
    let root: URL
    let metadata: URL
    let jsonLinesLog: URL
    let bookmarks: URL
    let incidents: URL
    let annotation: URL
    let analysis: URL
    let symbolication: URL
    let screenshotsDirectory: URL
    let recordingsDirectory: URL
    let pendingRecordings: URL
    let inProgressMarker: URL
}

enum SessionExportScope: Sendable {
    case wholeSession
    case filtered([LogEvent])
    case selected([LogEvent])
}

struct RecoverableSession: Identifiable, Hashable, Sendable {
    let session: DebugSession
    let paths: SessionPaths

    var id: UUID { session.id }
}
