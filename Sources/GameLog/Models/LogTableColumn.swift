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
        case .time: "时间"
        case .level: "级别"
        case .pid: "PID/TID"
        case .tag: "Tag"
        case .message: "消息"
        }
    }
}
