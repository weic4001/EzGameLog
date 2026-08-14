import SwiftUI

struct LogWorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            if let recoverable = model.recoverableSessions.first,
               model.currentSession == nil {
                RecoveryBanner(recoverable: recoverable)
            }

            if !model.hasAnyDeviceToolReady,
               case .missing = model.adbAvailability,
               case .missing = model.iosDeviceToolAvailability {
                MissingADBView()
            } else if !model.hasAnyDeviceToolReady,
                      case .failed(let message) = model.adbAvailability {
                FailedADBView(message: message)
            } else if model.selectedDeviceSerial == nil,
                      model.devices.contains(where: { $0.state == .unauthorized }) {
                ContentUnavailableView {
                    Label(String(localized: "请在设备上允许连接"), systemImage: "lock.trianglebadge.exclamationmark")
                } description: {
                    Text(String(localized: "Android 请允许 USB 调试；iOS 请解锁并信任这台 Mac。"))
                } actions: {
                    Button(String(localized: "重新检查")) {
                        Task { await model.refreshDevices() }
                    }
                }
            } else if model.selectedDeviceSerial == nil,
                      model.devices.contains(where: { $0.state == .offline }) {
                ContentUnavailableView {
                    Label(String(localized: "设备离线"), systemImage: "iphone.slash")
                } description: {
                    Text(String(localized: "保持 USB 连接，等待设备恢复；当前会话数据不会被清除。"))
                } actions: {
                    Button(String(localized: "重新检查")) {
                        Task { await model.refreshDevices() }
                    }
                }
            } else if model.selectedDeviceSerial == nil {
                ContentUnavailableView {
                    Label(String(localized: "连接 Android 或 iOS 测试机"), systemImage: "cable.connector")
                } description: {
                    Text(String(localized: "使用 USB 连接设备，完成调试授权或信任确认，然后刷新设备列表。"))
                } actions: {
                    Button(String(localized: "刷新设备")) {
                        Task { await model.refreshDevices() }
                    }
                }
            } else {
                LogTableView(
                    rows: model.visibleEvents,
                    selectedIDs: $model.selectedEventIDs,
                    followLatest: model.followLatest,
                    visibleColumns: model.visibleLogColumns,
                    onFollowingChanged: { model.setFollowingLatest($0) },
                    evidenceURL: { model.evidenceURL(for: $0) },
                    onContextAction: { model.handleLogTableAction($0) }
                )
            }

            Divider()
            statusBar
        }
        .navigationTitle(workspaceTitle)
    }

    private var workspaceTitle: String {
        model.selectedProcess?.name ?? model.selectedDevice?.displayName ?? "GameLog"
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isStreaming {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "实时"))
                    .foregroundStyle(.green)
            }
            if model.isRecording, let startedAt = model.recordingStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        durationText(context.date.timeIntervalSince(startedAt)),
                        systemImage: "record.circle.fill"
                    )
                    .foregroundStyle(.red)
                }
                if model.recordingSafetyStatus.macAvailableBytes > 0 {
                    Label(
                        recordingSafetyText,
                        systemImage: model.recordingSafetyStatus.level == .normal
                            ? "externaldrive"
                            : "externaldrive.badge.exclamationmark"
                    )
                    .foregroundStyle(recordingSafetyColor)
                    .help(String(localized: "录屏期间每 5 秒检查 Mac 与设备剩余空间"))
                }
            } else if model.recordingState != .idle {
                Text(model.recordingState.title)
                    .foregroundStyle(.orange)
            }
            Text(model.statusMessage)
                .lineLimit(1)
            Spacer()
            if !model.searchText.isEmpty {
                Text(String(localized: "\(model.visibleEvents.count.formatted()) 个匹配"))
                Button {
                    model.selectNextMatch(direction: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "上一个匹配"))
                Button {
                    model.selectNextMatch(direction: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "下一个匹配"))
            }
            Text(String(localized: "显示 \(model.visibleEvents.count.formatted()) / \(model.events.count.formatted())"))
            if let issue = model.diagnosticIssues.first {
                Button {
                    model.selectDiagnosticIssue(issue)
                } label: {
                    Label(
                        "\(model.diagnosticIssues.count)",
                        systemImage: "exclamationmark.triangle"
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(String(localized: "查看自动识别的 Crash / ANR"))
            }
            Toggle(String(localized: "跟随最新"), isOn: Binding(
                get: { model.followLatest },
                set: { model.setFollowingLatest($0) }
            ))
            .toggleStyle(.checkbox)
            if !model.followLatest {
                Button(String(localized: "回到最新")) {
                    model.setFollowingLatest(true)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.downArrow, modifiers: [.command])
            }
            Text(String(localized: "淘汰 \(model.evictedEventCount.formatted())"))
            Text(String(localized: "传输丢失 \(model.transportDroppedEventCount.formatted())"))
            Text(String(localized: "\(model.inputRatePerSecond.formatted(.number.precision(.fractionLength(0)))) 行/秒"))
            Text(model.sessionState.title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var recordingSafetyText: String {
        let free = ByteCountFormatter.string(
            fromByteCount: model.recordingSafetyStatus.macAvailableBytes,
            countStyle: .file
        )
        guard let seconds = model.recordingSafetyStatus.estimatedMacRemainingSeconds else {
            return free
        }
        return String(localized: "\(free) · 约 \(durationText(seconds))")
    }

    private var recordingSafetyColor: Color {
        switch model.recordingSafetyStatus.level {
        case .normal: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct RecoveryBanner: View {
    @Environment(AppModel.self) private var model
    let recoverable: RecoverableSession
    @State private var confirmDiscard = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "发现未完成会话"))
                    .font(.headline)
                Text("\(recoverable.session.targetPackage) · \(recoverable.session.createdAt.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "恢复数据")) {
                Task { await model.restoreRecoverableSession(recoverable) }
            }
            Button(String(localized: "清理"), role: .destructive) {
                confirmDiscard = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.orange.opacity(0.08))
        .alert(String(localized: "清理未完成会话？"), isPresented: $confirmDiscard) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "清理"), role: .destructive) {
                Task { await model.discardRecoverableSession(recoverable) }
            }
        } message: {
            Text(String(localized: "日志、截图和录屏文件将一并删除，此操作无法撤销。"))
        }
    }
}

private struct FailedADBView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "ADB 无法使用"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "重新检测")) {
                Task { await model.redetectADB() }
            }
            Button(String(localized: "选择外部 ADB…")) {
                Task { await model.chooseADBExecutable() }
            }
        }
    }
}

private struct MissingADBView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "内置设备工具无法使用"), systemImage: "terminal")
        } description: {
            Text(String(localized: "请重新安装 GameLog。Android 也可以临时选择一个可用的外部 ADB。"))
        } actions: {
            Button(String(localized: "选择外部 ADB…")) {
                Task { await model.chooseADBExecutable() }
            }
        }
    }
}
