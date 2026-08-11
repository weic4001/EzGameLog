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
                                Image(systemName: device.state == .online ? "iphone.gen3" : "exclamationmark.triangle")
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
                    Label(String(localized: "ADB 与隐私设置"), systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(adbStatusText)
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

    private var adbStatusText: String {
        switch model.adbAvailability {
        case .checking: String(localized: "正在检查 ADB")
        case .ready: String(localized: "ADB 已就绪")
        case .missing: String(localized: "未找到 ADB")
        case .failed: String(localized: "ADB 异常")
        }
    }

    private var statusColor: Color {
        switch model.adbAvailability {
        case .ready: .green
        case .checking: .yellow
        case .missing, .failed: .red
        }
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
        if let version = device.androidVersion {
            var android = "Android \(version)"
            if let api = device.apiLevel {
                android += " / API \(api)"
            }
            parts.append(android)
        }
        return parts.joined(separator: " · ")
    }
}
