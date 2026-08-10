import SwiftUI

private struct GameLogModelFocusedKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var gameLogModel: AppModel? {
        get { self[GameLogModelFocusedKey.self] }
        set { self[GameLogModelFocusedKey.self] = newValue }
    }
}

struct GameLogCommands: Commands {
    @FocusedValue(\.gameLogModel) private var model
    @Environment(\.openWindow) private var openWindow
    let archiveModel: ArchiveModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建日志窗口") {
                openWindow(id: "session")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("会话归档") {
                openWindow(id: "archive")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("导入会话包…") {
                openWindow(id: "archive")
                Task { await archiveModel.chooseAndImportSession() }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu("日志") {
            Button(model?.sessionState.isActive == true ? "停止会话" : "开始会话") {
                guard let model else { return }
                Task { await model.toggleSession() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(
                model == nil
                    || (model?.sessionState.isActive != true
                        && model?.canStartSession != true)
            )

            Button("清空日志") {
                model?.clearLogs()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(model == nil)

            Button("停止当前任务") {
                guard let model else { return }
                Task { await model.cancelCurrentTask() }
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(
                model?.sessionState.isActive != true
                    && model?.isCapturing != true
                    && model?.isRecording != true
            )

            Divider()

            Button("导出完整会话…") {
                guard let model else { return }
                Task { await model.exportWholeSession() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model?.currentSession == nil || model?.isExporting == true)

            Button("导出当前过滤结果…") {
                guard let model else { return }
                Task { await model.exportFilteredLogs() }
            }
            .disabled(model?.currentSession == nil || model?.isExporting == true)

            Button("导出所选日志…") {
                guard let model else { return }
                Task { await model.exportSelectedLogs() }
            }
            .disabled(model?.selectedEvent == nil || model?.isExporting == true)

            Divider()

            Button("丢弃当前会话…", role: .destructive) {
                guard let model else { return }
                Task { await model.discardCurrentSession() }
            }
            .disabled(model?.sessionState != .stopped || model?.currentSession == nil)
        }

        CommandMenu("设备") {
            Button("刷新设备") {
                guard let model else { return }
                Task { await model.refreshDevices() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model == nil)

            Button("屏幕截图") {
                model?.requestScreenshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)

            Button("标记问题") {
                guard let model else { return }
                Task { await model.markIncident() }
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)

            Button(model?.isRecording == true ? "停止录屏" : "开始录屏") {
                model?.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)
        }

        CommandMenu("视图") {
            Button(model?.followLatest == true ? "暂停跟随" : "回到最新") {
                guard let model else { return }
                model.setFollowingLatest(!model.followLatest)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(model == nil)

            Button(model?.isInspectorPresented == true ? "隐藏检查器" : "显示检查器") {
                model?.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model == nil)

            Divider()

            Menu("日志列") {
                ForEach(LogTableColumn.allCases) { column in
                    Toggle(
                        column.title,
                        isOn: Binding(
                            get: { model?.visibleLogColumns.contains(column) == true },
                            set: { _ in model?.toggleLogColumn(column) }
                        )
                    )
                    .disabled(column == .message || model == nil)
                }
            }
        }
    }
}
