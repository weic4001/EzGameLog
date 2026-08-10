import Foundation

enum LogLevel: String, CaseIterable, Codable, Sendable {
    case verbose = "V"
    case debug = "D"
    case info = "I"
    case warning = "W"
    case error = "E"
    case fatal = "F"
    case unknown = "?"

    var title: String {
        switch self {
        case .verbose: "Verbose"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        case .fatal: "Fatal"
        case .unknown: "Unknown"
        }
    }

    var severity: Int {
        switch self {
        case .verbose: 0
        case .debug: 1
        case .info: 2
        case .warning: 3
        case .error: 4
        case .fatal: 5
        case .unknown: 0
        }
    }
}

enum LogBufferName: String, Codable, CaseIterable, Sendable {
    case main
    case system
    case crash
    case unknown
}

enum LogEventKind: String, Codable, Sendable {
    case log
    case system
    case incident
    case screenshot
    case recordingStart
    case recordingEnd
    case recordingFailed
}

struct LogEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let occurredAt: Date
    let receivedAtHostTime: Date?
    let timestampText: String
    let pid: Int?
    let tid: Int?
    let level: LogLevel
    let tag: String
    var message: String
    var rawText: String
    let buffer: LogBufferName
    let kind: LogEventKind
    let evidenceID: UUID?

    var isMarker: Bool { kind != .log }

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        receivedAtHostTime: Date? = Date(),
        timestampText: String,
        pid: Int?,
        tid: Int?,
        level: LogLevel,
        tag: String,
        message: String,
        rawText: String,
        isMarker: Bool = false,
        buffer: LogBufferName = .unknown,
        kind: LogEventKind? = nil,
        evidenceID: UUID? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.receivedAtHostTime = receivedAtHostTime
        self.timestampText = timestampText
        self.pid = pid
        self.tid = tid
        self.level = level
        self.tag = tag
        self.message = message
        self.rawText = rawText
        self.buffer = buffer
        self.kind = kind ?? (isMarker ? .system : .log)
        self.evidenceID = evidenceID
    }
}

enum LogPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case warnings
    case errors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部日志"
        case .warnings: "警告及以上"
        case .errors: "仅错误"
        }
    }

    var minimumSeverity: Int {
        switch self {
        case .all: 0
        case .warnings: LogLevel.warning.severity
        case .errors: LogLevel.error.severity
        }
    }
}
