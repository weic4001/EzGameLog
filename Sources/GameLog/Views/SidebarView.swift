import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List {
            Section(String(localized: "设备")) {
                if model.devices.isEmpty {
                    Label(String(localized: "未发现设备"), systemImage: "cable.connector.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.devices) { device in
                        Button {
                            Task { await model.selectDevice(device.serial) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: device.state == .online ? device.platform.systemImage : "exclamationmark.triangle")
                                    .foregroundStyle(device.state == .online ? .green : .orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.displayName)
                                        .lineLimit(1)
                                    Text(deviceDetail(device))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .help(device.serial)
                                }
                                Spacer()
                                if model.selectedDeviceSerial == device.serial {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(device.state != .online)
                    }
                }
            }

            Section(String(localized: "快速过滤")) {
                ForEach(LogPreset.allCases) { preset in
                    Button {
                        model.preset = preset
                    } label: {
                        HStack {
                            Label(preset.title, systemImage: icon(for: preset))
                            Spacer()
                            if model.preset == preset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(String(localized: "当前目标")) {
                TargetSelectorView()
            }

            Section(String(localized: "过滤条件")) {
                FilterControlsView()
            }

            Section(String(localized: "已存过滤器")) {
                SavedFiltersView()
            }

            Section(String(localized: "证据")) {
                Label(String(localized: "截图 \(screenshotCount)"), systemImage: "camera")
                Label(String(localized: "录屏 \(recordingCount)"), systemImage: "record.circle")
                Button(String(localized: "在 Finder 中显示")) {
                    model.revealOutputDirectory()
                }
                if model.sessionState == .stopped, model.currentSession != nil {
                    Button(String(localized: "丢弃当前会话…"), role: .destructive) {
                        Task { await model.discardCurrentSession() }
                    }
                }
            }

            Section(String(localized: "工作区")) {
                Button {
                    openWindow(id: "archive")
                } label: {
                    Label(String(localized: "会话归档与对比"), systemImage: "archivebox")
                }
                .buttonStyle(.plain)
                SettingsLink {
                    Label(String(localized: "设备工具与隐私设置"), systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(deviceToolStatusText)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await model.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "刷新设备"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.bar)
        }
    }

    private var screenshotCount: Int { model.evidence.filter { $0.kind == .screenshot }.count }
    private var recordingCount: Int { model.evidence.filter { $0.kind == .recording }.count }

    private var deviceToolStatusText: String {
        let androidReady = if case .ready = model.adbAvailability { true } else { false }
        let iosReady = if case .ready = model.iosDeviceToolAvailability { true } else { false }
        if androidReady && iosReady { return String(localized: "Android 与 iOS 已就绪") }
        if androidReady { return String(localized: "Android 已就绪") }
        if iosReady { return String(localized: "iOS 已就绪") }
        return String(localized: "设备工具未就绪")
    }

    private var statusColor: Color {
        if model.hasAnyDeviceToolReady { return .green }
        if case .checking = model.adbAvailability { return .yellow }
        if case .checking = model.iosDeviceToolAvailability { return .yellow }
        return .red
    }

    private func icon(for preset: LogPreset) -> String {
        switch preset {
        case .all: "text.alignleft"
        case .warnings: "exclamationmark.triangle"
        case .errors: "xmark.octagon"
        }
    }

    private func deviceDetail(_ device: AndroidDevice) -> String {
        var parts = [device.serial, device.connectionType.displayName, device.state.displayName]
        if let version = device.operatingSystemVersion {
            var system = "\(device.platform.displayName) \(version)"
            if device.platform == .android, let api = device.apiLevel {
                system += " / API \(api)"
            }
            parts.append(system)
        }
        return parts.joined(separator: " · ")
    }
}
