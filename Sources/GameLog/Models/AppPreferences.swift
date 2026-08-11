import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum RecordingResolution: String, CaseIterable, Identifiable {
    case device
    case p720

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: String(localized: "设备原生")
        case .p720: String(localized: "720p 兼容")
        }
    }

    var adbSize: String? {
        switch self {
        case .device: nil
        case .p720: "720x1280"
        }
    }
}

enum RecordingBitRate: String, CaseIterable, Identifiable {
    case automatic
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "自动")
        case .balanced: String(localized: "平衡（4 Mbps）")
        case .high: String(localized: "高质量（8 Mbps）")
        }
    }

    var bitsPerSecond: Int? {
        switch self {
        case .automatic: nil
        case .balanced: 4_000_000
        case .high: 8_000_000
        }
    }
}
