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
            Button(String(localized: "新建日志窗口")) {
                openWindow(id: "session")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(String(localized: "会话归档")) {
                openWindow(id: "archive")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button(String(localized: "导入会话包…")) {
                openWindow(id: "archive")
                Task { await archiveModel.chooseAndImportSession() }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu(String(localized: "日志")) {
            Button(model?.sessionState.isActive == true ? String(localized: "停止会话") : String(localized: "开始会话")) {
                guard let model else { return }
                Task { await model.toggleSession() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(
                model == nil
                    || (model?.sessionState.isActive != true
                        && model?.canStartSession != true)
            )

            Button(String(localized: "清空日志")) {
                model?.clearLogs()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(model == nil)

            Button(String(localized: "停止当前任务")) {
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

            Button(String(localized: "导出完整会话…")) {
                guard let model else { return }
                Task { await model.exportWholeSession() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(model?.currentSession == nil || model?.isExporting == true)

            Button(String(localized: "导出当前过滤结果…")) {
                guard let model else { return }
                Task { await model.exportFilteredLogs() }
            }
            .disabled(model?.currentSession == nil || model?.isExporting == true)

            Button(String(localized: "导出所选日志…")) {
                guard let model else { return }
                Task { await model.exportSelectedLogs() }
            }
            .disabled(model?.selectedEvent == nil || model?.isExporting == true)

            Divider()

            Button(String(localized: "丢弃当前会话…"), role: .destructive) {
                guard let model else { return }
                Task { await model.discardCurrentSession() }
            }
            .disabled(model?.sessionState != .stopped || model?.currentSession == nil)
        }

        CommandMenu(String(localized: "设备")) {
            Button(String(localized: "刷新设备")) {
                guard let model else { return }
                Task { await model.refreshDevices() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model == nil)

            Button(String(localized: "屏幕截图")) {
                model?.requestScreenshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)

            Button(String(localized: "标记问题")) {
                guard let model else { return }
                Task { await model.markIncident() }
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)

            Button(model?.isRecording == true ? String(localized: "停止录屏") : String(localized: "开始录屏")) {
                model?.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(model?.sessionState.isActive != true)
        }

        CommandMenu(String(localized: "视图")) {
            Button(model?.followLatest == true ? String(localized: "暂停跟随") : String(localized: "回到最新")) {
                guard let model else { return }
                model.setFollowingLatest(!model.followLatest)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(model == nil)

            Button(model?.isInspectorPresented == true ? String(localized: "隐藏检查器") : String(localized: "显示检查器")) {
                model?.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model == nil)

            Divider()

            Menu(String(localized: "日志列")) {
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
