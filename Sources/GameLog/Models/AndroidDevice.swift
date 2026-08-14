import Foundation

enum DevicePlatform: String, Codable, CaseIterable, Sendable {
    case android
    case iOS = "ios"

    var displayName: String {
        switch self {
        case .android: "Android"
        case .iOS: "iOS"
        }
    }

    var systemImage: String {
        switch self {
        case .android: "apps.iphone"
        case .iOS: "apple.logo"
        }
    }
}

enum DeviceConnectionState: String, Codable, Sendable {
    case online = "device"
    case offline
    case unauthorized
    case unknown

    var displayName: String {
        switch self {
        case .online: String(localized: "已连接")
        case .offline: String(localized: "离线")
        case .unauthorized: String(localized: "待授权")
        case .unknown: String(localized: "未知")
        }
    }
}

enum DeviceConnectionType: String, Codable, Sendable {
    case usb = "USB"
    case wireless = "Wi-Fi"
    case emulator = "模拟器"
    case unknown = "未知"

    var displayName: String {
        switch self {
        case .usb: "USB"
        case .wireless: "Wi-Fi"
        case .emulator: String(localized: "模拟器")
        case .unknown: String(localized: "未知")
        }
    }
}

struct AndroidDevice: Identifiable, Hashable, Codable, Sendable {
    let platform: DevicePlatform
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
    var operatingSystemVersion: String? { androidVersion }
    var supportsScreenRecording: Bool { platform == .android }

    init(
        platform: DevicePlatform = .android,
        serial: String,
        state: DeviceConnectionState,
        model: String?,
        product: String?,
        transportID: String?,
        androidVersion: String? = nil,
        apiLevel: Int? = nil,
        connectionType: DeviceConnectionType? = nil
    ) {
        self.platform = platform
        self.serial = serial
        self.state = state
        self.model = model
        self.product = product
        self.transportID = transportID
        self.androidVersion = androidVersion
        self.apiLevel = apiLevel
        self.connectionType = connectionType ?? Self.inferConnectionType(serial: serial)
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case serial
        case state
        case model
        case product
        case transportID
        case androidVersion
        case apiLevel
        case connectionType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(DevicePlatform.self, forKey: .platform) ?? .android
        serial = try container.decode(String.self, forKey: .serial)
        state = try container.decode(DeviceConnectionState.self, forKey: .state)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        product = try container.decodeIfPresent(String.self, forKey: .product)
        transportID = try container.decodeIfPresent(String.self, forKey: .transportID)
        androidVersion = try container.decodeIfPresent(String.self, forKey: .androidVersion)
        apiLevel = try container.decodeIfPresent(Int.self, forKey: .apiLevel)
        connectionType = try container.decodeIfPresent(
            DeviceConnectionType.self,
            forKey: .connectionType
        ) ?? Self.inferConnectionType(serial: serial)
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
