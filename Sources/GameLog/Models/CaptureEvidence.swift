import Foundation

enum CaptureKind: String, Codable, Sendable {
    case screenshot
    case recording

    var title: String {
        switch self {
        case .screenshot: "屏幕截图"
        case .recording: "屏幕录制"
        }
    }
}

enum RecordingWorkflowState: Equatable, Sendable {
    case idle
    case starting
    case recording(startedAt: Date)
    case stopping
    case finalizing
    case failed(message: String)

    var title: String {
        switch self {
        case .idle: "未录制"
        case .starting: "正在启动录屏"
        case .recording: "录屏中"
        case .stopping: "正在停止录屏"
        case .finalizing: "正在下载并校验"
        case .failed(let message): "录屏失败：\(message)"
        }
    }
}

struct CaptureEvidence: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let kind: CaptureKind
    let fileURL: URL
    let thumbnailURL: URL?
    let createdAt: Date
    let deviceSerial: String
    let duration: TimeInterval?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let byteCount: Int64?
    let remotePath: String?

    init(
        id: UUID = UUID(),
        kind: CaptureKind,
        fileURL: URL,
        thumbnailURL: URL? = nil,
        createdAt: Date = Date(),
        deviceSerial: String,
        duration: TimeInterval? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteCount: Int64? = nil,
        remotePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.createdAt = createdAt
        self.deviceSerial = deviceSerial
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.remotePath = remotePath
    }
}

struct RecoverableRecording: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let deviceSerial: String
    let remotePath: String
    let localFileName: String
    let reason: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        deviceSerial: String,
        remotePath: String,
        localFileName: String,
        reason: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.deviceSerial = deviceSerial
        self.remotePath = remotePath
        self.localFileName = localFileName
        self.reason = reason
    }
}
