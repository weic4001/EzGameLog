import Foundation

enum LogPIDScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case target
    case all
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .target: "目标进程"
        case .all: "全部设备日志"
        case .custom: "指定 PID"
        }
    }
}

struct LogFilterConfiguration: Hashable, Codable, Sendable {
    var enabledLevels: Set<LogLevel> = Set(LogLevel.allCases)
    var minimumLevel: LogLevel?
    var includedTags = ""
    var excludedTags = ""
    var pidScope: LogPIDScope = .target
    var customPIDs: String?
    var query = ""
    var isCaseSensitive = false
    var usesRegularExpression = false
}

struct SavedFilterPreset: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var configuration: LogFilterConfiguration

    init(id: UUID = UUID(), name: String, configuration: LogFilterConfiguration) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

enum BuiltInFilterPreset: String, CaseIterable, Identifiable, Sendable {
    case unity
    case unreal

    var id: String { rawValue }

    var name: String {
        switch self {
        case .unity: "Unity 游戏"
        case .unreal: "Unreal Engine"
        }
    }

    var systemImage: String {
        switch self {
        case .unity: "cube"
        case .unreal: "gamecontroller"
        }
    }

    var configuration: LogFilterConfiguration {
        var configuration = LogFilterConfiguration()
        configuration.pidScope = .target
        switch self {
        case .unity:
            configuration.includedTags = "Unity,AndroidRuntime,CRASH"
        case .unreal:
            configuration.includedTags = "UE,UE4,UE5,libUE,AndroidRuntime,CRASH"
        }
        return configuration
    }
}

enum LogFilterError: LocalizedError, Sendable {
    case invalidRegularExpression(String)

    var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let message):
            "正则表达式无效：\(message)"
        }
    }
}
