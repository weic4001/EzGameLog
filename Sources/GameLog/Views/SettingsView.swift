import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            ADBSettingsView()
                .tabItem { Label("ADB", systemImage: "terminal") }
            RecordingSettingsView()
                .tabItem { Label("录制", systemImage: "record.circle") }
            PrivacySettingsView()
                .tabItem { Label("隐私", systemImage: "checkmark.shield") }
            StorageSettingsView()
                .tabItem { Label("存储", systemImage: "externaldrive") }
        }
        .environment(model)
        .scenePadding()
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    var body: some View {
        @Bindable var model = model

        Form {
            Picker("外观", selection: $appearance) {
                ForEach(AppAppearance.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            Toggle("默认显示检查器", isOn: $model.isInspectorPresented)
            Picker("内存事件上限", selection: $model.maximumLogCount) {
                Text("10,000 条").tag(10_000)
                Text("50,000 条").tag(50_000)
                Text("100,000 条").tag(100_000)
            }

            Section("默认 Logcat 缓冲区") {
                ForEach([LogBufferName.main, .system, .crash], id: \.self) { buffer in
                    Toggle(
                        buffer.rawValue,
                        isOn: Binding(
                            get: { model.selectedLogBuffers.contains(buffer) },
                            set: { _ in model.toggleLogBuffer(buffer) }
                        )
                    )
                }
                Text("活动会话中修改的缓冲区将在下次会话生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ADBSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionRegistry.self) private var sessionRegistry
    @State private var wirelessHost = ""
    @State private var pairingPort = ""
    @State private var connectionPort = ""
    @State private var pairingCode = ""

    var body: some View {
        Form {
            Section("ADB 工具") {
                LabeledContent("状态", value: adbStatus)
                LabeledContent("来源", value: model.adbSource?.title ?? "未就绪")
                LabeledContent("实际路径") {
                    Text(model.adbPath.isEmpty ? "未配置" : model.adbPath)
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("重新检测") {
                        Task { await model.redetectADB() }
                    }
                    Button("选择外部 ADB…") {
                        Task { await model.chooseADBExecutable() }
                    }
                    if !model.usesBundledADB {
                        Button("恢复内置 ADB") {
                            Task { await model.useBundledADB() }
                        }
                    }
                }
                .disabled(sessionRegistry.hasActiveSessions)
                Text("GameLog 默认使用随 App 提供的 ADB；外部路径仅作为高级覆盖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("无线调试（Android 11+）") {
                TextField("设备 IP 或主机名", text: $wirelessHost)
                HStack {
                    TextField("配对端口", text: $pairingPort)
                    SecureField("6 位配对码", text: $pairingCode)
                    Button("配对") {
                        Task {
                            await model.pairWirelessDevice(
                                host: wirelessHost,
                                port: Int(pairingPort) ?? 0,
                                pairingCode: pairingCode
                            )
                        }
                    }
                    .disabled(model.isWirelessADBWorking)
                }
                HStack {
                    TextField("调试端口", text: $connectionPort)
                    Button("连接") {
                        Task {
                            await model.connectWirelessDevice(
                                host: wirelessHost,
                                port: Int(connectionPort) ?? 0
                            )
                        }
                    }
                    Button("断开") {
                        Task {
                            await model.disconnectWirelessDevice(
                                host: wirelessHost,
                                port: Int(connectionPort) ?? 0
                            )
                        }
                    }
                    .disabled(model.isWirelessADBWorking)
                }
                if !model.wirelessADBStatus.isEmpty {
                    Text(model.wirelessADBStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("配对端口与调试端口通常不同，请分别使用设备“使用配对码配对”和“无线调试”页面显示的端口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var adbStatus: String {
        switch model.adbAvailability {
        case .checking: "正在检查"
        case .ready(let version): version
        case .missing: "未找到"
        case .failed(let message): message
        }
    }
}

private struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var packagePattern = ""
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var validationMessage = ""

    var body: some View {
        Form {
            Section("项目级脱敏规则") {
                if model.customRedactionRules.isEmpty {
                    Text("尚未添加自定义规则。系统内置六类常见敏感信息规则仍会默认启用。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.customRedactionRules) { rule in
                    HStack {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { rule.isEnabled },
                                set: {
                                    model.setCustomRedactionRuleEnabled(
                                        rule.id,
                                        enabled: $0
                                    )
                                }
                            )
                        )
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text(
                                rule.packagePattern.isEmpty
                                    ? "所有项目 · \(rule.pattern)"
                                    : "\(rule.packagePattern) · \(rule.pattern)"
                            )
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        Spacer()
                        Button("编辑") {
                            beginEditing(rule)
                        }
                        Button("删除", role: .destructive) {
                            model.deleteCustomRedactionRule(rule.id)
                            if editingID == rule.id {
                                clearEditor()
                            }
                        }
                    }
                }
            }

            Section(editingID == nil ? "添加规则" : "编辑规则") {
                TextField("规则名称", text: $name)
                TextField("包名范围（留空、精确包名或 com.example.*）", text: $packagePattern)
                TextField("正则表达式", text: $pattern)
                    .font(.body.monospaced())
                TextField("替换文本（留空使用默认文案）", text: $replacement)
                if !validationMessage.isEmpty {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button(editingID == nil ? "添加规则" : "保存修改") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("清空") {
                        clearEditor()
                    }
                }
            }

            Text("规则只在本机导出阶段执行。自定义正则会按目标包名范围启用，并在导出预览中单独显示命中数量。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func beginEditing(_ rule: CustomRedactionRule) {
        editingID = rule.id
        name = rule.name
        packagePattern = rule.packagePattern
        pattern = rule.pattern
        replacement = rule.replacement
        validationMessage = ""
    }

    private func save() {
        let rule = CustomRedactionRule(
            id: editingID ?? UUID(),
            name: name,
            pattern: pattern,
            replacement: replacement,
            packagePattern: packagePattern
        )
        if let error = model.upsertCustomRedactionRule(rule) {
            validationMessage = error
        } else {
            clearEditor()
        }
    }

    private func clearEditor() {
        editingID = nil
        name = ""
        packagePattern = ""
        pattern = ""
        replacement = ""
        validationMessage = ""
    }
}

private struct RecordingSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Picker("默认分辨率", selection: $model.recordingResolution) {
                ForEach(RecordingResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution)
                }
            }
            Picker("码率策略", selection: $model.recordingBitRate) {
                ForEach(RecordingBitRate.allCases) { bitRate in
                    Text(bitRate.title).tag(bitRate)
                }
            }
            Text("录屏由工具栏手动开始和停止，不设置固定时长。设备仅支持短分段时会自动续录并合并；录制期间每 5 秒检查 Mac 与设备空间。录屏不包含音频。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct StorageSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionRegistry.self) private var sessionRegistry
    @State private var confirmCleanupAll = false

    var body: some View {
        @Bindable var model = model

        Form {
            LabeledContent("会话目录") {
                Text(model.sessionRootDirectory.path)
                    .font(.caption.monospaced())
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            LabeledContent(
                "剩余空间",
                value: ByteCountFormatter.string(
                    fromByteCount: model.availableStorageBytes,
                    countStyle: .file
                )
            )
            Stepper(
                "异常会话保留：\(model.temporaryRetentionDays) 天",
                value: $model.temporaryRetentionDays,
                in: 1...30
            )
            HStack {
                Button("更改目录…") {
                    Task { await model.chooseSessionRootDirectory() }
                }
                .disabled(sessionRegistry.hasActiveSessions)
                Button("在 Finder 中显示") {
                    model.revealOutputDirectory()
                }
                Button("清理过期临时会话") {
                    Task { await model.cleanupExpiredTemporarySessions() }
                }
                .disabled(sessionRegistry.hasActiveSessions)
                Button("立即清理全部…", role: .destructive) {
                    confirmCleanupAll = true
                }
                .disabled(sessionRegistry.hasActiveSessions)
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refreshStorageCapacity()
        }
        .alert("清理全部异常会话？", isPresented: $confirmCleanupAll) {
            Button("取消", role: .cancel) {}
            Button("全部清理", role: .destructive) {
                Task { await model.cleanupAllRecoverableSessions() }
            }
        } message: {
            Text("所有未完成会话的日志、截图、录屏与待恢复文件都会被删除，此操作无法撤销。")
        }
    }
}
