import Foundation

enum DeviceConnectionState: String, Codable, Sendable {
    case online = "device"
    case offline
    case unauthorized
    case unknown

    var displayName: String {
        switch self {
        case .online: "已连接"
        case .offline: "离线"
        case .unauthorized: "待授权"
        case .unknown: "未知"
        }
    }
}

enum DeviceConnectionType: String, Codable, Sendable {
    case usb = "USB"
    case wireless = "Wi-Fi"
    case emulator = "模拟器"
    case unknown = "未知"
}

struct AndroidDevice: Identifiable, Hashable, Codable, Sendable {
    let serial: String
    let state: DeviceConnectionState
    let model: String?
    let product: String?
    let transportID: String?
    let androidVersion: String?
    let apiLevel: Int?
    let connectionType: DeviceConnectionType

    var id: String { serial }
    var displayName: String { model?.replacingOccurrences(of: "_", with: " ") ?? serial }

    init(
        serial: String,
        state: DeviceConnectionState,
        model: String?,
        product: String?,
        transportID: String?,
        androidVersion: String? = nil,
        apiLevel: Int? = nil,
        connectionType: DeviceConnectionType? = nil
    ) {
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
        self.transportID = transportID
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.connectionType = connectionType ?? Self.inferConnectionType(serial: serial)
    }

    private static func inferConnectionType(serial: String) -> DeviceConnectionType {
        if serial.hasPrefix("emulator-") { return .emulator }
        if serial.contains(":") { return .wireless }
        if !serial.isEmpty { return .usb }
        return .unknown
    }
}

struct AndroidProcess: Identifiable, Hashable, Codable, Sendable {
    let pid: Int
    let name: String

    var id: Int { pid }
    var displayName: String { "\(name)  ·  \(pid)" }
}
