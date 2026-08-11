import Foundation

enum LogTableColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case time
    case level
    case pid
    case tag
    case message

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: String(localized: "时间")
        case .level: String(localized: "级别")
        case .pid: "PID/TID"
        case .tag: "Tag"
        case .message: String(localized: "消息")
        }
    }
}
