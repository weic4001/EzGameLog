import SwiftUI

struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                if model.devices.isEmpty {
                    Text("未发现设备")
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
                Button("刷新设备") {
                    Task { await model.refreshDevices() }
                }
            } label: {
                Label(model.selectedDevice?.displayName ?? "选择设备", systemImage: "iphone.gen3")
            }
            .help("选择 Android 设备")

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
                    Text("未找到应用进程")
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
                Label(model.selectedPackageName ?? "选择目标", systemImage: "app.badge")
                    .lineLimit(1)
            }
            .help("选择运行中的应用进程")
            .disabled(model.selectedDeviceSerial == nil)
        }

        ToolbarItemGroup(placement: .principal) {
            Button {
                Task { await model.toggleSession() }
            } label: {
                Label(
                    model.sessionState.isActive ? "停止" : "开始",
                    systemImage: model.sessionState.isActive ? "stop.fill" : "play.fill"
                )
            }
            .help(model.sessionState.isActive ? "停止当前会话 (⌘R)" : "开始调试会话 (⌘R)")
            .disabled(!model.sessionState.isActive && !model.canStartSession)

            Button {
                model.clearLogs()
            } label: {
                Label("清空", systemImage: "trash")
            }
            .help("清空日志 (⌘K)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.requestScreenshot()
            } label: {
                Label("截图", systemImage: "camera")
            }
            .help("截取设备屏幕 (⌥⌘S)")
            .disabled(!model.sessionState.isActive || model.isCapturing)

            Button {
                Task { await model.markIncident() }
            } label: {
                Label("标记问题", systemImage: "exclamationmark.bubble")
            }
            .help("标记当前问题并自动截图 (⌥⌘M)")
            .disabled(!model.sessionState.isActive)

            Button {
                model.toggleRecording()
            } label: {
                Label(
                    model.isRecording ? "停止录屏" : "录屏",
                    systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                )
            }
            .foregroundStyle(model.isRecording ? .red : .primary)
            .help(model.isRecording
                ? "停止设备录屏并保存 (⌥⌘R)"
                : "开始设备录屏；再次点击停止 (⌥⌘R)")
            .disabled(!model.sessionState.isActive)

            Menu {
                Button("导出完整会话…") {
                    Task { await model.exportWholeSession() }
                }
                Button("导出当前过滤结果…") {
                    Task { await model.exportFilteredLogs() }
                }
                Button("导出所选日志…") {
                    Task { await model.exportSelectedLogs() }
                }
                .disabled(model.selectedEvent == nil)
                if let incident = model.incidents.last {
                    Divider()
                    Button("导出最近问题包…") {
                        Task { await model.exportIncidentPackage(incident) }
                    }
                    .disabled(model.isRecording)
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("导出会话或日志 (⇧⌘E)")
            .disabled(model.currentSession == nil || model.isExporting)

            Button {
                model.isInspectorPresented.toggle()
            } label: {
                Label("检查器", systemImage: "sidebar.right")
            }
            .help("显示或隐藏检查器")
        }
    }
}
