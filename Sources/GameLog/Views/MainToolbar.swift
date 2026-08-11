import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                if model.devices.isEmpty {
                    Text(String(localized: "未发现设备"))
                }
                ForEach(model.devices) { device in
                    Button {
                        Task { await model.selectDevice(device.serial) }
                    } label: {
                        if device.serial == model.selectedDeviceSerial {
                            Label(device.displayName, systemImage: "checkmark")
                        } else {
                            Text(device.displayName)
                        }
                    }
                    .disabled(device.state != .online)
                }
                Divider()
                Button(String(localized: "刷新设备")) {
                    Task { await model.refreshDevices() }
                }
            } label: {
                Label(model.selectedDevice?.displayName ?? String(localized: "选择设备"), systemImage: "iphone.gen3")
            }
            .help(String(localized: "选择 Android 设备"))

            Menu {
                ForEach(model.recentPackages, id: \.self) { package in
                    Button {
                        Task { await model.selectPackageName(package) }
                    } label: {
                        if package == model.selectedPackageName {
                            Label(package, systemImage: "checkmark")
                        } else {
                            Text(package)
                        }
                    }
                }
                if !model.recentPackages.isEmpty {
                    Divider()
                }
                if model.processes.isEmpty {
                    Text(String(localized: "未找到应用进程"))
                }
                ForEach(model.processes) { process in
                    Button {
                        model.selectProcess(process.pid)
                    } label: {
                        if process.pid == model.selectedProcessID {
                            Label(process.displayName, systemImage: "checkmark")
                        } else {
                            Text(process.displayName)
                        }
                    }
                }
            } label: {
                Label(model.selectedPackageName ?? String(localized: "选择目标"), systemImage: "app.badge")
                    .lineLimit(1)
            }
            .help(String(localized: "选择运行中的应用进程"))
            .disabled(model.selectedDeviceSerial == nil)
        }

        ToolbarItemGroup(placement: .principal) {
            Button {
                Task { await model.toggleSession() }
            } label: {
                Label(
                    model.sessionState.isActive ? String(localized: "停止") : String(localized: "开始"),
                    systemImage: model.sessionState.isActive ? "stop.fill" : "play.fill"
                )
            }
            .help(model.sessionState.isActive ? String(localized: "停止当前会话 (⌘R)") : String(localized: "开始调试会话 (⌘R)"))
            .disabled(!model.sessionState.isActive && !model.canStartSession)

            Button {
                model.clearLogs()
            } label: {
                Label(String(localized: "清空"), systemImage: "trash")
            }
            .help(String(localized: "清空日志 (⌘K)"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.requestScreenshot()
            } label: {
                Label(String(localized: "截图"), systemImage: "camera")
            }
            .help(String(localized: "截取设备屏幕 (⌥⌘S)"))
            .disabled(!model.sessionState.isActive || model.isCapturing)

            Button {
                Task { await model.markIncident() }
            } label: {
                Label(String(localized: "标记问题"), systemImage: "exclamationmark.bubble")
            }
            .help(String(localized: "标记当前问题并自动截图 (⌥⌘M)"))
            .disabled(!model.sessionState.isActive)

            Button {
                model.toggleRecording()
            } label: {
                Label(
                    model.isRecording ? String(localized: "停止录屏") : String(localized: "录屏"),
                    systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .foregroundStyle(model.isRecording ? .red : .primary)
            .help(model.isRecording
                ? String(localized: "停止设备录屏并保存 (⌥⌘R)")
                : String(localized: "开始设备录屏；再次点击停止 (⌥⌘R)"))
            .disabled(!model.sessionState.isActive)

            Menu {
                Button(String(localized: "导出完整会话…")) {
                    Task { await model.exportWholeSession() }
                }
                Button(String(localized: "导出当前过滤结果…")) {
                    Task { await model.exportFilteredLogs() }
                }
                Button(String(localized: "导出所选日志…")) {
                    Task { await model.exportSelectedLogs() }
                }
                .disabled(model.selectedEvent == nil)
                if let incident = model.incidents.last {
                    Divider()
                    Button(String(localized: "导出最近问题包…")) {
                        Task { await model.exportIncidentPackage(incident) }
                    }
                    .disabled(model.isRecording)
                }
            } label: {
                Label(String(localized: "导出"), systemImage: "square.and.arrow.up")
            }
            .help(String(localized: "导出会话或日志 (⇧⌘E)"))
            .disabled(model.currentSession == nil || model.isExporting)

            Button {
                model.isInspectorPresented.toggle()
            } label: {
                Label(String(localized: "检查器"), systemImage: "sidebar.right")
            }
            .help(String(localized: "显示或隐藏检查器"))
        }
    }
}
