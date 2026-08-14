import Foundation

enum IOSDeviceTool: String, CaseIterable, Sendable {
    case deviceID = "idevice_id"
    case deviceInfo = "ideviceinfo"
    case devicePair = "idevicepair"
    case deviceSyslog = "idevicesyslog"
}

protocol IOSDeviceExecuting: Sendable {
    func run(
        _ tool: IOSDeviceTool,
        arguments: [String],
        timeout: Duration?
    ) async throws -> ADBCommandResult

    func stream(
        _ tool: IOSDeviceTool,
        arguments: [String]
    ) -> AsyncThrowingStream<Data, Error>
}

extension IOSDeviceExecuting {
    func run(
        _ tool: IOSDeviceTool,
        arguments: [String]
    ) async throws -> ADBCommandResult {
        try await run(tool, arguments: arguments, timeout: nil)
    }
}

struct IOSDeviceToolExecutor: IOSDeviceExecuting, Sendable {
    private let executors: [IOSDeviceTool: ADBExecutor]

    init(toolURLs: [IOSDeviceTool: URL]) {
        executors = toolURLs.mapValues(ADBExecutor.init(executableURL:))
    }

    func run(
        _ tool: IOSDeviceTool,
        arguments: [String],
        timeout: Duration? = nil
    ) async throws -> ADBCommandResult {
        guard let executor = executors[tool] else {
            throw IOSDeviceToolError.missingTool(tool.rawValue)
        }
        return try await executor.run(arguments, timeout: timeout)
    }

    func stream(
        _ tool: IOSDeviceTool,
        arguments: [String]
    ) -> AsyncThrowingStream<Data, Error> {
        guard let executor = executors[tool] else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: IOSDeviceToolError.missingTool(tool.rawValue))
            }
        }
        return executor.stream(arguments)
    }
}

enum IOSDeviceToolError: LocalizedError, Sendable {
    case missingTool(String)
    case incompleteInstallation
    case unsupportedArchitecture

    var errorDescription: String? {
        switch self {
        case .missingTool:
            String(localized: "iOS 设备工具不完整。请重新安装 GameLog。")
        case .incompleteInstallation:
            String(localized: "内置 iOS 设备工具不完整。请重新安装 GameLog。")
        case .unsupportedArchitecture:
            String(localized: "当前 Mac 架构暂不支持内置 iOS 设备工具。")
        }
    }
}
