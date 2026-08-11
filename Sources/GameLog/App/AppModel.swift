import AppKit
import Foundation
import Observation
import OSLog

enum ADBAvailability: Equatable, Sendable {
    case checking
    case ready(version: String)
    case missing
    case failed(message: String)
}

private enum ADBPreferenceKey {
    static let customExecutablePath = "customADBExecutablePath"
    static let bundledADBMigrated = "bundledADBMigrated"
    static let legacyExecutablePath = "adbExecutablePath"
}

@MainActor
@Observable
final class AppModel {
    private(set) var adbAvailability: ADBAvailability = .checking
    private(set) var adbPath = ""
    private(set) var adbVersion = ""
    private(set) var adbSource: ADBInstallationSource?
    private(set) var wirelessADBStatus = ""
    private(set) var isWirelessADBWorking = false
    private(set) var devices: [AndroidDevice] = []
    private(set) var processes: [AndroidProcess] = []
    var selectedDeviceSerial: String?
    var selectedProcessID: Int?
    private(set) var selectedPackageName: String?
    var packageInput = ""
    private(set) var recentPackages: [String] = []
    var preset: LogPreset = .all {
        didSet {
            switch preset {
            case .all:
                filterConfiguration.enabledLevels = Set(LogLevel.allCases)
            case .warnings:
                filterConfiguration.enabledLevels = [.warning, .error, .fatal]
            case .errors:
                filterConfiguration.enabledLevels = [.error, .fatal]
            }
        }
    }
    var searchText = "" {
        didSet {
            if filterConfiguration.query != searchText {
                filterConfiguration.query = searchText
            }
        }
    }
    var filterConfiguration = LogFilterConfiguration() {
        didSet {
            if searchText != filterConfiguration.query {
                searchText = filterConfiguration.query
            }
            scheduleFilterUpdate()
        }
    }
    private(set) var savedFilterPresets: [SavedFilterPreset] = []
    private(set) var customRedactionRules: [CustomRedactionRule] = []
    private(set) var filterError: String?
    private(set) var events: [LogEvent] = []
    private(set) var filteredEvents: [LogEvent] = []
    var selectedEventIDs: Set<UUID> = []
    private(set) var bookmarkedEventIDs: Set<UUID> = []
    private(set) var incidents: [IncidentRecord] = []
    private(set) var diagnosticIssues: [DiagnosticIssue] = []
    private(set) var evidence: [CaptureEvidence] = []
    private(set) var recoverableRecordings: [RecoverableRecording] = []
    private(set) var currentSession: DebugSession?
    private(set) var currentSessionPaths: SessionPaths?
    private(set) var recoverableSessions: [RecoverableSession] = []
    private(set) var sessionState: DebugSessionState = .ready
    var isInspectorPresented = true {
        didSet {
            UserDefaults.standard.set(isInspectorPresented, forKey: "defaultInspectorVisible")
        }
    }
    var followLatest = true
    private(set) var isStreaming = false
    private(set) var isCapturing = false
    private(set) var isRecording = false
    private(set) var recordingState: RecordingWorkflowState = .idle
    private(set) var recordingSafetyStatus: RecordingSafetyStatus = .unavailable
    private(set) var isExporting = false
    var exportPreview: ExportPreviewState?
    private(set) var recordingStartedAt: Date?
    private(set) var currentTargetPIDs: Set<Int> = []
    private(set) var sessionTargetPIDs: Set<Int> = []
    private(set) var evictedEventCount: UInt64 = 0
    private(set) var transportDroppedEventCount: UInt64 = 0
    private(set) var inputRatePerSecond: Double = 0
    var visibleLogColumns: Set<LogTableColumn> = Set(LogTableColumn.allCases) {
        didSet {
            if !visibleLogColumns.contains(.message) {
                visibleLogColumns.insert(.message)
            }
            UserDefaults.standard.set(
                visibleLogColumns.map(\.rawValue).sorted(),
                forKey: "visibleLogColumns"
            )
        }
    }
    private(set) var statusMessage = String(localized: "正在查找 ADB…")
    private(set) var lastExportURL: URL?
    private(set) var availableStorageBytes: Int64 = 0
    private(set) var sessionRootDirectory: URL
    var recordingResolution: RecordingResolution = .device {
        didSet {
            UserDefaults.standard.set(recordingResolution.rawValue, forKey: "recordingResolution")
        }
    }
    var recordingBitRate: RecordingBitRate = .automatic {
        didSet {
            UserDefaults.standard.set(recordingBitRate.rawValue, forKey: "recordingBitRate")
        }
    }
    var temporaryRetentionDays = 7 {
        didSet {
            temporaryRetentionDays = min(max(temporaryRetentionDays, 1), 30)
            UserDefaults.standard.set(temporaryRetentionDays, forKey: "temporaryRetentionDays")
        }
    }
    var selectedLogBuffers: Set<LogBufferName> = [.main, .system, .crash] {
        didSet {
            if selectedLogBuffers.isEmpty {
                selectedLogBuffers = [.main]
            }
            UserDefaults.standard.set(
                selectedLogBuffers.map(\.rawValue).sorted(),
                forKey: "selectedLogBuffers"
            )
        }
    }
    var maximumLogCount = 50_000 {
        didSet {
            maximumLogCount = min(max(maximumLogCount, 10_000), 100_000)
            UserDefaults.standard.set(maximumLogCount, forKey: "maximumLogCount")
            buffer.updateCapacity(maximumLogCount)
            events = buffer.events
            scheduleFilterUpdate(delay: .zero)
        }
    }

    @ObservationIgnored private var executor: ADBExecutor?
    @ObservationIgnored private var deviceService: DeviceService?
    @ObservationIgnored private var logService: LogStreamingService?
    @ObservationIgnored private var captureService: CaptureService?
    @ObservationIgnored private var sessionStore: SessionStore
    @ObservationIgnored private var buffer = LogBuffer(capacity: 50_000)
    @ObservationIgnored private var pendingEvents: [LogEvent] = []
    @ObservationIgnored private var logTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticTask: Task<Void, Never>?
    @ObservationIgnored private var deviceMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var processMonitorTask: Task<Void, Never>?
    @ObservationIgnored private var logRestartTask: Task<Void, Never>?
    @ObservationIgnored private var recordingTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotTask: Task<Void, Never>?
    @ObservationIgnored private var recordingSafetyTask: Task<Void, Never>?
    @ObservationIgnored private var lastAnnouncedRecordingSafetyLevel: RecordingSafetyLevel?
    @ObservationIgnored private var wasDeviceDisconnected = false
    @ObservationIgnored private var currentSessionBuffers: Set<LogBufferName> = [.main, .system, .crash]
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var startSessionToken: UUID?
    @ObservationIgnored private var inputRateSampleStartedAt = Date()
    @ObservationIgnored private var inputRateSampleCount = 0

    private let sessionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.kkxx.gamelog",
        category: "Session"
    )

    init(sessionStore: SessionStore? = nil) {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: ADBPreferenceKey.bundledADBMigrated) {
            defaults.removeObject(forKey: ADBPreferenceKey.legacyExecutablePath)
            defaults.set(true, forKey: ADBPreferenceKey.bundledADBMigrated)
        }
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/GameLog/Sessions", directoryHint: .isDirectory)
        let configuredRoot = defaults.string(forKey: "sessionRootDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? defaultRoot
        self.sessionRootDirectory = configuredRoot
        self.sessionStore = sessionStore ?? SessionStore(rootDirectory: configuredRoot)
        if defaults.object(forKey: "defaultInspectorVisible") != nil {
            isInspectorPresented = defaults.bool(forKey: "defaultInspectorVisible")
        }
        let storedMaximum = defaults.integer(forKey: "maximumLogCount")
        if storedMaximum > 0 {
            maximumLogCount = min(max(storedMaximum, 10_000), 100_000)
            buffer = LogBuffer(capacity: maximumLogCount)
        }
        if let raw = defaults.string(forKey: "recordingResolution"),
           let resolution = RecordingResolution(rawValue: raw) {
            recordingResolution = resolution
        }
        if let raw = defaults.string(forKey: "recordingBitRate"),
           let bitRate = RecordingBitRate(rawValue: raw) {
            recordingBitRate = bitRate
        }
        let retention = defaults.integer(forKey: "temporaryRetentionDays")
        if retention > 0 {
            temporaryRetentionDays = min(max(retention, 1), 30)
        }
        if let rawBuffers = defaults.stringArray(forKey: "selectedLogBuffers") {
            let buffers = Set(rawBuffers.compactMap(LogBufferName.init(rawValue:)))
            if !buffers.isEmpty {
                selectedLogBuffers = buffers
            }
        }
        if let rawColumns = defaults.stringArray(forKey: "visibleLogColumns") {
            let columns = Set(rawColumns.compactMap(LogTableColumn.init(rawValue:)))
            if columns.contains(.message) {
                visibleLogColumns = columns
            }
        }
        if let data = UserDefaults.standard.data(forKey: "savedFilterPresets"),
           let presets = try? JSONDecoder().decode([SavedFilterPreset].self, from: data) {
            savedFilterPresets = presets
        }
        if let data = defaults.data(forKey: "customRedactionRules"),
           let rules = try? JSONDecoder().decode([CustomRedactionRule].self, from: data) {
            customRedactionRules = rules
        }
    }

    deinit {
        logTask?.cancel()
        flushTask?.cancel()
        filterTask?.cancel()
        diagnosticTask?.cancel()
        deviceMonitorTask?.cancel()
        processMonitorTask?.cancel()
        logRestartTask?.cancel()
        recordingTask?.cancel()
        screenshotTask?.cancel()
        recordingSafetyTask?.cancel()
    }

    var selectedDevice: AndroidDevice? {
        devices.first { $0.serial == selectedDeviceSerial }
    }

    var selectedProcess: AndroidProcess? {
        processes.first { $0.pid == selectedProcessID }
    }

    var selectedEvent: LogEvent? {
        events.first { selectedEventIDs.contains($0.id) }
    }

    var selectedIncident: IncidentRecord? {
        guard let eventID = selectedEvent?.id else { return nil }
        return incidents.first { $0.eventID == eventID }
    }

    var selectedDiagnosticIssue: DiagnosticIssue? {
        guard let eventID = selectedEvent?.id else { return nil }
        return DiagnosticAggregator.issue(containing: eventID, in: diagnosticIssues)
    }

    var canStartSession: Bool {
        selectedDevice?.state == .online
            && selectedPackageName != nil
            && !sessionState.isActive
    }

    var visibleEvents: [LogEvent] {
        filteredEvents
    }

    var requiresTerminationPreparation: Bool {
        sessionState.isActive || isExporting || isCapturing || isRecording
    }

    var outputDirectory: URL {
        currentSessionPaths?.root
            ?? sessionRootDirectory
    }

    var usesBundledADB: Bool {
        adbSource == .bundled
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            _ = try await sessionStore.cleanupRecoverableSessions(
                olderThanDays: temporaryRetentionDays
            )
            recoverableSessions = try await sessionStore.recoverableSessions()
            availableStorageBytes = try await sessionStore.availableCapacity()
        } catch {
            statusMessage = String(localized: "检查未完成会话失败：\(error.localizedDescription)")
        }
        await configureADB(
            savedPath: UserDefaults.standard.string(forKey: ADBPreferenceKey.customExecutablePath)
        )
    }

    func chooseADBExecutable() async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再更改 ADB 路径")
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: "选择 adb 可执行文件")
        panel.prompt = String(localized: "选择")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !adbPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: adbPath).deletingLastPathComponent()
        }

        guard await panel.begin() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: ADBPreferenceKey.customExecutablePath)
        await configureADB(savedPath: url.path)
    }

    func redetectADB() async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再重新检测 ADB")
            return
        }
        await configureADB(
            savedPath: UserDefaults.standard.string(forKey: ADBPreferenceKey.customExecutablePath)
        )
    }

    func useBundledADB() async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再切换 ADB")
            return
        }
        UserDefaults.standard.removeObject(forKey: ADBPreferenceKey.customExecutablePath)
        await configureADB(savedPath: nil)
    }

    func refreshDevices() async {
        guard let deviceService else { return }
        statusMessage = String(localized: "正在刷新设备…")
        do {
            let newDevices = try await deviceService.listDevices()
            let activeSerial = selectedDeviceSerial
            devices = newDevices

            if let activeSerial,
               !newDevices.contains(where: { $0.serial == activeSerial && $0.state == .online }),
               sessionState.isActive {
                await handleActiveDeviceDisconnected(serial: activeSerial)
                return
            }
            if let activeSerial, sessionState.isActive, wasDeviceDisconnected,
               newDevices.contains(where: { $0.serial == activeSerial && $0.state == .online }) {
                await recoverActiveDevice(serial: activeSerial)
                return
            }

            if !newDevices.contains(where: { $0.serial == selectedDeviceSerial && $0.state == .online }) {
                selectedDeviceSerial = newDevices.first(where: { $0.state == .online })?.serial
            }
            if selectedDeviceSerial == nil {
                processes = []
                selectedProcessID = nil
                statusMessage = newDevices.isEmpty ? String(localized: "未发现 Android 设备") : String(localized: "设备尚未授权或处于离线状态")
            } else {
                statusMessage = String(localized: "已连接 \(selectedDevice?.displayName ?? String(localized: "Android 设备"))")
                loadRecentPackages()
                await refreshProcesses()
            }
        } catch {
            adbAvailability = .failed(message: error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func pairWirelessDevice(host: String, port: Int, pairingCode: String) async {
        guard let deviceService else {
            wirelessADBStatus = String(localized: "ADB 尚未就绪")
            return
        }
        isWirelessADBWorking = true
        wirelessADBStatus = String(localized: "正在配对…")
        defer { isWirelessADBWorking = false }
        do {
            _ = try await deviceService.pairWirelessDevice(
                host: host,
                port: port,
                pairingCode: pairingCode
            )
            wirelessADBStatus = String(localized: "配对成功；请输入设备显示的调试端口进行连接")
        } catch {
            wirelessADBStatus = String(localized: "配对失败：\(error.localizedDescription)")
        }
    }

    func connectWirelessDevice(host: String, port: Int) async {
        guard let deviceService else {
            wirelessADBStatus = String(localized: "ADB 尚未就绪")
            return
        }
        isWirelessADBWorking = true
        wirelessADBStatus = String(localized: "正在连接…")
        defer { isWirelessADBWorking = false }
        do {
            _ = try await deviceService.connectWirelessDevice(host: host, port: port)
            wirelessADBStatus = String(localized: "无线设备已连接")
            await refreshDevices()
        } catch {
            wirelessADBStatus = String(localized: "连接失败：\(error.localizedDescription)")
        }
    }

    func disconnectWirelessDevice(host: String, port: Int) async {
        guard let deviceService else {
            wirelessADBStatus = String(localized: "ADB 尚未就绪")
            return
        }
        isWirelessADBWorking = true
        defer { isWirelessADBWorking = false }
        do {
            _ = try await deviceService.disconnectWirelessDevice(host: host, port: port)
            wirelessADBStatus = String(localized: "无线设备已断开")
            await refreshDevices()
        } catch {
            wirelessADBStatus = String(localized: "断开失败：\(error.localizedDescription)")
        }
    }

    func selectDevice(_ serial: String?) async {
        guard serial != selectedDeviceSerial else { return }
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再切换设备")
            return
        }
        selectedDeviceSerial = serial
        selectedProcessID = nil
        selectedPackageName = nil
        packageInput = ""
        processes = []
        loadRecentPackages()
        await refreshProcesses()
    }

    func refreshProcesses() async {
        guard let serial = selectedDeviceSerial, let deviceService else { return }
        do {
            let newProcesses = try await deviceService.listProcesses(serial: serial)
            processes = newProcesses
            if !newProcesses.contains(where: { $0.pid == selectedProcessID }) {
                selectedProcessID = nil
            }
            if let selectedPackageName, selectedProcessID == nil {
                selectedProcessID = newProcesses.first {
                    $0.name == selectedPackageName || $0.name.hasPrefix(selectedPackageName + ":")
                }?.pid
            }
            statusMessage = newProcesses.isEmpty
                ? String(localized: "设备已连接；未找到应用进程")
                : String(localized: "已加载 \(newProcesses.count) 个应用进程")
        } catch {
            processes = []
            statusMessage = String(localized: "读取进程失败：\(error.localizedDescription)")
        }
    }

    func selectProcess(_ pid: Int?) {
        guard pid != selectedProcessID else { return }
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再切换目标进程")
            return
        }
        selectedProcessID = pid
        if let process = processes.first(where: { $0.pid == pid }) {
            guard AndroidPackageName.isValid(process.name) else {
                statusMessage = String(localized: "所选进程不是有效的 Android 包名")
                selectedProcessID = nil
                return
            }
            selectedPackageName = process.name
            packageInput = process.name
            rememberPackage(process.name)
        }
    }

    func selectPackageName(_ packageName: String) async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再切换目标包名")
            return
        }
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            selectedPackageName = nil
            selectedProcessID = nil
            return
        }
        guard AndroidPackageName.isValid(trimmed) else {
            selectedPackageName = nil
            selectedProcessID = nil
            statusMessage = String(localized: "包名格式无效；请输入类似 com.example.game 的 Android 包名")
            return
        }
        selectedPackageName = trimmed
        packageInput = trimmed
        rememberPackage(trimmed)
        guard let serial = selectedDeviceSerial, let deviceService else { return }
        let pids = (try? await deviceService.pids(forPackage: trimmed, serial: serial)) ?? []
        selectedProcessID = pids.sorted().first
        statusMessage = pids.isEmpty
            ? String(localized: "已选择 \(trimmed)；开始会话后将等待进程启动")
            : String(localized: "已选择 \(trimmed) · PID \(pids.sorted().map(String.init).joined(separator: ", "))")
    }

    func toggleSession() async {
        if sessionState.isActive {
            await stopSession()
        } else {
            await startSession()
        }
    }

    func startSession() async {
        guard !sessionState.isActive,
              let device = selectedDevice,
              device.state == .online,
              let targetPackage = selectedPackageName,
              let deviceService,
              logService != nil else {
            statusMessage = selectedPackageName == nil ? String(localized: "请选择目标包名或应用进程") : String(localized: "设备或 ADB 尚未就绪")
            return
        }

        let startToken = UUID()
        startSessionToken = startToken
        sessionState = .starting
        statusMessage = String(localized: "正在创建调试会话…")
        resetVisibleSession()

        do {
            let initialPIDs = try await deviceService.pids(
                forPackage: targetPackage,
                serial: device.serial
            )
            guard startSessionToken == startToken else { return }
            let (session, paths) = try await sessionStore.create(
                device: device,
                targetPackage: targetPackage,
                pids: initialPIDs.sorted(),
                adbPath: adbPath,
                adbVersion: adbVersion,
                buffers: selectedLogBuffers,
                initialPreset: preset,
                initialFilterConfiguration: filterConfiguration
            )
            guard startSessionToken == startToken else {
                try? await sessionStore.discard(sessionID: session.id)
                return
            }
            startSessionToken = nil
            currentSession = session
            currentSessionPaths = paths
            currentTargetPIDs = initialPIDs
            sessionTargetPIDs = initialPIDs
            currentSessionBuffers = selectedLogBuffers
            scheduleFilterUpdate(delay: .zero)
            sessionState = initialPIDs.isEmpty ? .recovering : .capturing
            statusMessage = initialPIDs.isEmpty
                ? String(localized: "会话已创建，等待 \(targetPackage) 进程启动…")
                : String(localized: "正在捕获 \(targetPackage) 的日志")
            sessionLogger.info("Started session \(session.id.uuidString, privacy: .public)")
            launchLogStream(session: session, serial: device.serial)
            startProcessMonitoring()
        } catch {
            guard startSessionToken == startToken else { return }
            startSessionToken = nil
            sessionState = .failed
            isStreaming = false
            statusMessage = String(localized: "启动会话失败：\(error.localizedDescription)")
            sessionLogger.error("Session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopSession() async {
        if sessionState == .starting, currentSession == nil {
            startSessionToken = nil
            sessionState = .ready
            statusMessage = String(localized: "已取消启动会话")
            return
        }
        guard sessionState.isActive, let session = currentSession else { return }
        sessionState = .stopping
        statusMessage = String(localized: "正在停止会话并写入磁盘…")
        if recordingTask != nil {
            recordingState = .stopping
            recordingTask?.cancel()
            await recordingTask?.value
        }
        if let screenshotTask {
            screenshotTask.cancel()
            await screenshotTask.value
            self.screenshotTask = nil
        }
        logTask?.cancel()
        logTask = nil
        logRestartTask?.cancel()
        logRestartTask = nil
        processMonitorTask?.cancel()
        processMonitorTask = nil
        flushPendingEvents()
        isStreaming = false

        do {
            let finalized = try await sessionStore.finalize(sessionID: session.id)
            currentSession = finalized
            scheduleFilterUpdate(delay: .zero)
            sessionState = .stopped
            statusMessage = String(localized: "会话已停止，可导出或在 Finder 中查看")
            sessionLogger.info("Finalized session \(session.id.uuidString, privacy: .public)")
        } catch {
            sessionState = .failed
            statusMessage = String(localized: "停止会话失败：\(error.localizedDescription)")
        }
    }

    func setFollowingLatest(_ enabled: Bool) {
        followLatest = enabled
        if sessionState == .capturing || sessionState == .followingPaused {
            sessionState = enabled ? .capturing : .followingPaused
        }
    }

    func toggleLevel(_ level: LogLevel) {
        if filterConfiguration.enabledLevels.contains(level) {
            filterConfiguration.enabledLevels.remove(level)
        } else {
            filterConfiguration.enabledLevels.insert(level)
        }
    }

    func toggleLogBuffer(_ buffer: LogBufferName) {
        if selectedLogBuffers.contains(buffer), selectedLogBuffers.count > 1 {
            selectedLogBuffers.remove(buffer)
        } else {
            selectedLogBuffers.insert(buffer)
        }
    }

    func toggleLogColumn(_ column: LogTableColumn) {
        guard column != .message else { return }
        if visibleLogColumns.contains(column) {
            visibleLogColumns.remove(column)
        } else {
            visibleLogColumns.insert(column)
        }
    }

    func saveCurrentFilter(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedFilterPresets.append(SavedFilterPreset(
            name: trimmed,
            configuration: filterConfiguration
        ))
        persistSavedFilterPresets()
        statusMessage = String(localized: "已保存过滤预设“\(trimmed)”")
    }

    func applySavedFilter(_ savedPreset: SavedFilterPreset) {
        filterConfiguration = savedPreset.configuration
        statusMessage = String(localized: "已应用过滤预设“\(savedPreset.name)”")
    }

    func applyBuiltInFilter(_ builtInPreset: BuiltInFilterPreset) {
        filterConfiguration = builtInPreset.configuration
        statusMessage = String(localized: "已应用 \(builtInPreset.name) 过滤预设")
    }

    func renameSavedFilter(_ savedPreset: SavedFilterPreset, to name: String) {
        guard let index = savedFilterPresets.firstIndex(where: { $0.id == savedPreset.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedFilterPresets[index].name = trimmed
        persistSavedFilterPresets()
    }

    func deleteSavedFilter(_ savedPreset: SavedFilterPreset) {
        savedFilterPresets.removeAll { $0.id == savedPreset.id }
        persistSavedFilterPresets()
        statusMessage = String(localized: "已删除过滤预设“\(savedPreset.name)”")
    }

    func upsertCustomRedactionRule(_ rule: CustomRedactionRule) -> String? {
        let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let packagePattern = rule.packagePattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return String(localized: "请输入规则名称。") }
        guard !pattern.isEmpty else { return String(localized: "请输入正则表达式。") }
        do {
            _ = try NSRegularExpression(pattern: pattern)
        } catch {
            return String(localized: "正则表达式无效：\(error.localizedDescription)")
        }
        if !packagePattern.isEmpty {
            let exactPackage = packagePattern.hasSuffix(".*")
                ? String(packagePattern.dropLast(2))
                : packagePattern
            guard AndroidPackageName.isValid(exactPackage) else {
                return String(localized: "包名范围无效；可使用 com.example.game 或 com.example.*。")
            }
        }
        var normalized = rule
        normalized.name = name
        normalized.pattern = pattern
        normalized.replacement = rule.replacement.isEmpty
            ? String(localized: "‹已脱敏:\(name)›")
            : rule.replacement
        normalized.packagePattern = packagePattern
        if let index = customRedactionRules.firstIndex(where: { $0.id == rule.id }) {
            customRedactionRules[index] = normalized
        } else {
            customRedactionRules.append(normalized)
        }
        persistCustomRedactionRules()
        return nil
    }

    func setCustomRedactionRuleEnabled(_ ruleID: UUID, enabled: Bool) {
        guard let index = customRedactionRules.firstIndex(where: { $0.id == ruleID }) else {
            return
        }
        customRedactionRules[index].isEnabled = enabled
        persistCustomRedactionRules()
    }

    func deleteCustomRedactionRule(_ ruleID: UUID) {
        customRedactionRules.removeAll { $0.id == ruleID }
        persistCustomRedactionRules()
    }

    func selectNextMatch(direction: Int) {
        guard !filteredEvents.isEmpty else {
            selectedEventIDs = []
            return
        }
        let currentID = selectedEvent?.id
        let currentIndex = currentID.flatMap { id in
            filteredEvents.firstIndex { $0.id == id }
        }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = (currentIndex + direction + filteredEvents.count) % filteredEvents.count
        } else {
            nextIndex = direction >= 0 ? 0 : filteredEvents.count - 1
        }
        selectedEventIDs = [filteredEvents[nextIndex].id]
        setFollowingLatest(false)
    }

    func selectEvent(near date: Date) {
        guard let closest = events.min(by: {
            abs($0.occurredAt.timeIntervalSince(date))
                < abs($1.occurredAt.timeIntervalSince(date))
        }) else {
            return
        }
        selectedEventIDs = [closest.id]
        isInspectorPresented = true
        setFollowingLatest(false)
    }

    func toggleBookmark(for eventID: UUID) {
        if bookmarkedEventIDs.contains(eventID) {
            bookmarkedEventIDs.remove(eventID)
        } else {
            bookmarkedEventIDs.insert(eventID)
        }
        guard let sessionID = currentSession?.id else { return }
        let snapshot = bookmarkedEventIDs
        Task {
            try? await sessionStore.updateBookmarks(snapshot, sessionID: sessionID)
        }
    }

    func markIncident() async {
        guard sessionState.isActive, let session = currentSession else {
            statusMessage = String(localized: "请先开始调试会话")
            return
        }
        let marker = evidenceEvent(kind: .incident, message: String(localized: "问题标记"))
        let recordingOffset = recordingStartedAt.map {
            max(0, marker.occurredAt.timeIntervalSince($0))
        }
        let incident = IncidentRecord(
            createdAt: marker.occurredAt,
            eventID: marker.id,
            title: String(localized: "问题 \(Self.incidentTimeFormatter.string(from: marker.occurredAt))"),
            recordingOffset: recordingOffset
        )
        do {
            try await sessionStore.append(events: [marker], sessionID: session.id)
            try await sessionStore.upsert(incident: incident, sessionID: session.id)
            incidents.append(incident)
            enqueue([marker])
            selectedEventIDs = [marker.id]
            isInspectorPresented = true
            statusMessage = String(localized: "问题已标记，正在补充现场截图…")
            announceAccessibility(String(localized: "问题已标记"))
        } catch {
            statusMessage = String(localized: "标记问题失败：\(error.localizedDescription)")
            return
        }

        guard screenshotTask == nil else {
            statusMessage = String(localized: "问题已标记；当前截图任务完成后可手动补充证据")
            return
        }
        screenshotTask = Task { [weak self] in
            await self?.takeScreenshot(attachingToIncidentID: incident.id)
            self?.screenshotTask = nil
        }
    }

    func updateIncident(id: UUID, title: String, note: String) async {
        guard let index = incidents.firstIndex(where: { $0.id == id }),
              let sessionID = currentSession?.id else {
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        incidents[index].title = trimmedTitle.isEmpty ? incidents[index].title : trimmedTitle
        incidents[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await sessionStore.upsert(incident: incidents[index], sessionID: sessionID)
            statusMessage = String(localized: "问题说明已保存")
        } catch {
            statusMessage = String(localized: "保存问题说明失败：\(error.localizedDescription)")
        }
    }

    func selectDiagnosticIssue(_ issue: DiagnosticIssue) {
        guard let eventID = issue.firstEventID else { return }
        selectedEventIDs = [eventID]
        isInspectorPresented = true
        setFollowingLatest(false)
    }

    func evidenceURL(for evidenceID: UUID) -> URL? {
        evidence.first { $0.id == evidenceID }?.fileURL
    }

    func handleLogTableAction(_ action: LogTableContextAction) {
        switch action {
        case .showInInspector(let eventID):
            selectedEventIDs = [eventID]
            isInspectorPresented = true
        case .showOnlyTag(let tag):
            filterConfiguration.includedTags = tag
            filterConfiguration.excludedTags = ""
        case .excludeTag(let tag):
            var tags = filterConfiguration.excludedTags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tags.contains(tag) {
                tags.append(tag)
            }
            filterConfiguration.excludedTags = tags.joined(separator: ", ")
        case .showOnlyPID(let pid):
            filterConfiguration.pidScope = .custom
            filterConfiguration.customPIDs = String(pid)
        case .toggleBookmark(let eventID):
            toggleBookmark(for: eventID)
        case .revealEvidence(let evidenceID):
            guard let url = evidenceURL(for: evidenceID) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyEvidencePath(let evidenceID):
            guard let path = evidenceURL(for: evidenceID)?.path else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        case .exportEvidence(let evidenceID):
            guard let source = evidenceURL(for: evidenceID) else { return }
            Task { await exportEvidenceFile(source) }
        }
    }

    func exportEvidence(_ item: CaptureEvidence) async {
        await exportEvidenceFile(item.fileURL)
    }

    func clearLogs() {
        pendingEvents.removeAll(keepingCapacity: true)
        buffer.removeAll()
        events = []
        selectedEventIDs = []
        let marker = systemEvent(String(localized: "本地视图已清空；设备 Logcat 缓冲区未改变"))
        buffer.append(contentsOf: [marker])
        events = buffer.events
        scheduleFilterUpdate(delay: .zero)
        if let sessionID = currentSession?.id {
            Task {
                try? await sessionStore.append(events: [marker], sessionID: sessionID)
            }
        }
        statusMessage = String(localized: "本地日志视图已清空")
    }

    func takeScreenshot(attachingToIncidentID incidentID: UUID? = nil) async {
        guard sessionState.isActive,
              let serial = selectedDeviceSerial,
              let captureService,
              let session = currentSession,
              let paths = currentSessionPaths,
              !isCapturing else {
            statusMessage = String(localized: "请先开始调试会话")
            return
        }
        isCapturing = true
        statusMessage = String(localized: "正在截取设备屏幕…")
        defer { isCapturing = false }

        do {
            let item = try await captureService.takeScreenshot(
                serial: serial,
                destinationDirectory: paths.screenshotsDirectory
            )
            try await sessionStore.append(artifact: item, sessionID: session.id)
            let marker = evidenceEvent(
                kind: .screenshot,
                message: String(localized: "屏幕截图 · \(item.fileURL.lastPathComponent)"),
                evidenceID: item.id
            )
            try await sessionStore.append(events: [marker], sessionID: session.id)
            evidence.insert(item, at: 0)
            if let incidentID {
                await attachEvidence(item, toIncidentID: incidentID)
            }
            enqueue([marker])
            isInspectorPresented = true
            statusMessage = String(localized: "截图已保存到当前会话")
            announceAccessibility(String(localized: "屏幕截图已保存"))
        } catch is CancellationError {
            await persistFailureEvent(String(localized: "截图已取消"), kind: .system)
            statusMessage = String(localized: "截图已取消")
            announceAccessibility(String(localized: "屏幕截图已取消"))
        } catch {
            await persistFailureEvent(String(localized: "截图失败：\(error.localizedDescription)"), kind: .system)
            statusMessage = String(localized: "截图失败：\(error.localizedDescription)")
            announceAccessibility(String(localized: "屏幕截图失败"))
        }
    }

    func requestScreenshot() {
        guard screenshotTask == nil else { return }
        screenshotTask = Task { [weak self] in
            await self?.takeScreenshot()
            self?.screenshotTask = nil
        }
    }

    func toggleRecording() {
        if recordingTask != nil {
            recordingState = .stopping
            statusMessage = String(localized: "正在停止录屏并保存文件…")
            recordingTask?.cancel()
            return
        }
        recordingTask = Task { [weak self] in
            await self?.recordScreen()
            self?.recordingTask = nil
        }
    }

    func cancelCurrentTask() async {
        if recordingTask != nil {
            toggleRecording()
            return
        }
        if let screenshotTask {
            screenshotTask.cancel()
            return
        }
        if sessionState.isActive {
            await stopSession()
        }
    }

    func recordScreen() async {
        guard sessionState.isActive,
              let serial = selectedDeviceSerial,
              let captureService,
              let session = currentSession,
              let paths = currentSessionPaths,
              !isRecording else {
            statusMessage = String(localized: "请先开始调试会话")
            return
        }
        let freeBytes = (try? await sessionStore.availableCapacity()) ?? 0
        availableStorageBytes = freeBytes
        guard freeBytes == 0 || freeBytes >= 500_000_000 else {
            recordingState = .failed(message: String(localized: "磁盘剩余空间不足 500 MB"))
            statusMessage = String(localized: "磁盘空间不足；请更改位置或清理临时会话")
            await persistFailureEvent(String(localized: "录屏未开始：Mac 磁盘空间不足"), kind: .recordingFailed)
            return
        }
        isRecording = true
        recordingStartedAt = Date()
        startRecordingSafetyMonitoring()
        recordingState = .starting
        let startMarker = evidenceEvent(kind: .recordingStart, message: String(localized: "录屏开始"))
        try? await sessionStore.append(events: [startMarker], sessionID: session.id)
        enqueue([startMarker])
        announceAccessibility(String(localized: "设备录屏开始"))
        recordingState = .recording(startedAt: recordingStartedAt ?? Date())
        statusMessage = String(localized: "正在录屏；再次点击录屏按钮结束…")
        defer {
            recordingSafetyTask?.cancel()
            recordingSafetyTask = nil
            lastAnnouncedRecordingSafetyLevel = nil
            isRecording = false
            recordingStartedAt = nil
            recordingTask = nil
            if case .failed = recordingState {
                // Preserve the failure description until the next recording starts.
            } else {
                recordingState = .idle
            }
        }

        do {
            let item = try await captureService.recordScreen(
                serial: serial,
                size: recordingResolution.adbSize,
                bitRate: recordingBitRate.bitsPerSecond,
                destinationDirectory: paths.recordingsDirectory
            )
            recordingState = .finalizing
            try await sessionStore.append(artifact: item, sessionID: session.id)
            let marker = evidenceEvent(
                kind: .recordingEnd,
                message: String(localized: "录屏结束 · \(item.fileURL.lastPathComponent)"),
                evidenceID: item.id
            )
            try await sessionStore.append(events: [marker], sessionID: session.id)
            evidence.insert(item, at: 0)
            await attachRecordingToMatchingIncidents(item)
            enqueue([marker])
            isInspectorPresented = true
            statusMessage = String(localized: "录屏已保存到当前会话")
            announceAccessibility(String(localized: "设备录屏结束，文件已保存"))
        } catch is CancellationError {
            await persistFailureEvent(String(localized: "录屏已取消，未生成可播放文件"), kind: .system)
            statusMessage = String(localized: "录屏已取消")
            announceAccessibility(String(localized: "设备录屏已取消"))
        } catch let CaptureError.recoverableRecording(remotePath, localFileName, reason) {
            let recoverable = RecoverableRecording(
                deviceSerial: serial,
                remotePath: remotePath,
                localFileName: localFileName,
                reason: reason
            )
            try? await sessionStore.append(
                recoverableRecording: recoverable,
                sessionID: session.id
            )
            recoverableRecordings.append(recoverable)
            recordingState = .failed(message: String(localized: "录屏待重连恢复"))
            await persistFailureEvent(
                String(localized: "录屏中断，远端文件待恢复 · \(remotePath)"),
                kind: .recordingFailed
            )
            statusMessage = String(localized: "录屏中断；重连设备后可尝试恢复")
            announceAccessibility(String(localized: "设备录屏中断，可在重连后恢复"))
        } catch {
            recordingState = .failed(message: error.localizedDescription)
            await persistFailureEvent(String(localized: "录屏失败：\(error.localizedDescription)"), kind: .recordingFailed)
            statusMessage = String(localized: "录屏失败：\(error.localizedDescription)")
            announceAccessibility(String(localized: "设备录屏失败"))
        }
    }

    func exportWholeSession() async {
        await prepareExportPreview(kind: .session(.wholeSession))
    }

    func exportFilteredLogs() async {
        await prepareExportPreview(kind: .session(.filtered(visibleEvents)))
    }

    func exportSelectedLogs() async {
        let selected = events.filter { selectedEventIDs.contains($0.id) }
        guard !selected.isEmpty else {
            statusMessage = String(localized: "请先选择要导出的日志")
            return
        }
        await prepareExportPreview(kind: .session(.selected(selected)))
    }

    func exportVisibleLogs() async {
        await exportFilteredLogs()
    }

    func exportIncidentPackage(_ incident: IncidentRecord) async {
        guard !isRecording else {
            statusMessage = String(localized: "请先停止录屏，确保问题包包含完整视频")
            return
        }
        await prepareExportPreview(kind: .incident(incident.id))
    }

    func setExportRedactionEnabled(_ enabled: Bool) {
        guard var preview = exportPreview else { return }
        preview.configuration.isEnabled = enabled
        exportPreview = preview
    }

    func toggleExportRedactionCategory(_ category: RedactionCategory) {
        guard var preview = exportPreview else { return }
        if preview.configuration.categories.contains(category) {
            preview.configuration.categories.remove(category)
        } else {
            preview.configuration.categories.insert(category)
        }
        exportPreview = preview
    }

    func setExportCustomRuleEnabled(_ ruleID: UUID, enabled: Bool) {
        guard var preview = exportPreview,
              let index = preview.configuration.customRules.firstIndex(
                  where: { $0.id == ruleID }
              ) else {
            return
        }
        preview.configuration.customRules[index].isEnabled = enabled
        exportPreview = preview
    }

    func cancelExportPreview() {
        exportPreview = nil
    }

    func confirmExportPreview() async {
        guard let preview = exportPreview,
              let session = currentSession,
              !isExporting else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = previewTitle(for: preview.kind)
        panel.prompt = String(localized: "导出")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard await panel.begin() == .OK, let destination = panel.url else { return }

        exportPreview = nil
        isExporting = true
        statusMessage = String(localized: "正在原子导出并应用脱敏规则…")
        defer { isExporting = false }
        do {
            let url: URL
            switch preview.kind {
            case .session(let scope):
                url = try await sessionStore.export(
                    sessionID: session.id,
                    scope: scope,
                    destinationDirectory: destination,
                    redactionConfiguration: preview.configuration
                )
            case .incident(let incidentID):
                url = try await sessionStore.exportIncident(
                    sessionID: session.id,
                    incidentID: incidentID,
                    destinationDirectory: destination,
                    redactionConfiguration: preview.configuration
                )
            }
            lastExportURL = url
            statusMessage = String(localized: "已导出到 \(url.lastPathComponent)")
        } catch {
            statusMessage = String(localized: "导出失败，原始会话已保留：\(error.localizedDescription)")
        }
    }

    func restoreRecoverableSession(_ recoverable: RecoverableSession) async {
        guard !sessionState.isActive else { return }
        do {
            let (session, paths, storedEvents, storedEvidence) = try await sessionStore.load(
                sessionID: recoverable.id,
                retainingLast: maximumLogCount
            )
            resetVisibleSession()
            currentSession = session
            currentSessionPaths = paths
            selectedDeviceSerial = session.device.serial
            selectedPackageName = session.targetPackage
            packageInput = session.targetPackage
            buffer.append(contentsOf: Array(storedEvents.suffix(maximumLogCount)))
            sessionTargetPIDs = Set(storedEvents.compactMap { event in
                event.kind == .log ? event.pid : nil
            }).union(session.initialPIDs)
            currentTargetPIDs = Set(session.initialPIDs)
            events = buffer.events
            scheduleFilterUpdate(delay: .zero)
            scheduleDiagnosticUpdate()
            evidence = storedEvidence.sorted { $0.createdAt > $1.createdAt }
            recoverableRecordings = (
                try? await sessionStore.recoverableRecordings(sessionID: session.id)
            ) ?? []
            bookmarkedEventIDs = (try? await sessionStore.bookmarks(sessionID: session.id)) ?? []
            incidents = (try? await sessionStore.incidents(sessionID: session.id)) ?? []
            let finalized = try await sessionStore.finalizeRecovered(sessionID: session.id)
            currentSession = finalized
            recoverableSessions.removeAll { $0.id == session.id }
            sessionState = .stopped
            statusMessage = String(localized: "已恢复未完成会话的数据，可导出或在 Finder 中查看")
        } catch {
            statusMessage = String(localized: "恢复会话失败：\(error.localizedDescription)")
        }
    }

    func discardRecoverableSession(_ recoverable: RecoverableSession) async {
        do {
            try await sessionStore.discard(sessionID: recoverable.id)
            recoverableSessions.removeAll { $0.id == recoverable.id }
            statusMessage = String(localized: "已清理未完成会话")
        } catch {
            statusMessage = String(localized: "清理失败：\(error.localizedDescription)")
        }
    }

    func revealOutputDirectory() {
        let url = lastExportURL ?? outputDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshStorageCapacity() async {
        availableStorageBytes = (try? await sessionStore.availableCapacity()) ?? 0
    }

    func chooseSessionRootDirectory() async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话，再更改会话目录")
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: "选择 GameLog 会话目录")
        panel.prompt = String(localized: "使用此目录")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = sessionRootDirectory
        guard await panel.begin() == .OK, let url = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appending(path: ".gamelog-write-test-\(UUID().uuidString)")
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            sessionRootDirectory = url
            try await sessionStore.updateRootDirectory(url)
            UserDefaults.standard.set(url.path, forKey: "sessionRootDirectory")
            recoverableSessions = try await sessionStore.recoverableSessions()
            await refreshStorageCapacity()
            statusMessage = String(localized: "会话目录已更新")
        } catch {
            statusMessage = String(localized: "所选目录不可写：\(error.localizedDescription)")
        }
    }

    func recoverRecording(_ recoverable: RecoverableRecording) async {
        guard let captureService,
              let session = currentSession,
              let paths = currentSessionPaths,
              selectedDeviceSerial == recoverable.deviceSerial,
              selectedDevice?.state == .online else {
            statusMessage = String(localized: "请连接原设备 \(recoverable.deviceSerial) 后重试")
            return
        }
        recordingState = .finalizing
        statusMessage = String(localized: "正在恢复设备端录屏…")
        do {
            let item = try await captureService.recoverRecording(
                serial: recoverable.deviceSerial,
                remotePath: recoverable.remotePath,
                localFileName: recoverable.localFileName,
                destinationDirectory: paths.recordingsDirectory
            )
            try await sessionStore.append(artifact: item, sessionID: session.id)
            try await sessionStore.removeRecoverableRecording(
                id: recoverable.id,
                sessionID: session.id
            )
            recoverableRecordings.removeAll { $0.id == recoverable.id }
            evidence.insert(item, at: 0)
            let marker = evidenceEvent(
                kind: .recordingEnd,
                message: String(localized: "录屏已恢复 · \(item.fileURL.lastPathComponent)"),
                evidenceID: item.id
            )
            try? await sessionStore.append(events: [marker], sessionID: session.id)
            enqueue([marker])
            recordingState = .idle
            statusMessage = String(localized: "设备端录屏已恢复并校验")
        } catch {
            recordingState = .failed(message: error.localizedDescription)
            statusMessage = String(localized: "录屏恢复失败，远端文件已保留：\(error.localizedDescription)")
        }
    }

    func cleanupExpiredTemporarySessions() async {
        do {
            let count = try await sessionStore.cleanupRecoverableSessions(
                olderThanDays: temporaryRetentionDays
            )
            recoverableSessions = try await sessionStore.recoverableSessions()
            await refreshStorageCapacity()
            statusMessage = count == 0 ? String(localized: "没有过期临时会话") : String(localized: "已清理 \(count) 个过期临时会话")
        } catch {
            statusMessage = String(localized: "临时会话清理失败：\(error.localizedDescription)")
        }
    }

    func cleanupAllRecoverableSessions() async {
        guard !sessionState.isActive else {
            statusMessage = String(localized: "请先停止当前会话")
            return
        }
        do {
            let count = try await sessionStore.cleanupRecoverableSessions(olderThanDays: nil)
            recoverableSessions = try await sessionStore.recoverableSessions()
            await refreshStorageCapacity()
            statusMessage = count == 0 ? String(localized: "没有可清理的异常会话") : String(localized: "已清理 \(count) 个异常会话")
        } catch {
            statusMessage = String(localized: "异常会话清理失败：\(error.localizedDescription)")
        }
    }

    func discardCurrentSession() async {
        guard sessionState == .stopped, let session = currentSession else {
            statusMessage = String(localized: "请先停止当前会话")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "丢弃当前会话？")
        alert.informativeText = String(localized: "当前会话的日志、截图、录屏和书签将被永久删除。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "取消"))
        alert.addButton(withTitle: String(localized: "丢弃"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        do {
            try await sessionStore.discard(sessionID: session.id)
            currentSession = nil
            currentSessionPaths = nil
            resetVisibleSession()
            sessionState = .ready
            statusMessage = String(localized: "当前会话已丢弃")
            await refreshStorageCapacity()
        } catch {
            statusMessage = String(localized: "丢弃会话失败：\(error.localizedDescription)")
        }
    }

    func prepareForTermination() async {
        while isExporting {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if sessionState.isActive {
            await stopSession()
        } else if let sessionID = currentSession?.id {
            try? await sessionStore.flush(sessionID: sessionID)
        }
        logTask?.cancel()
        logRestartTask?.cancel()
        deviceMonitorTask?.cancel()
        processMonitorTask?.cancel()
        recordingTask?.cancel()
        screenshotTask?.cancel()
        recordingSafetyTask?.cancel()
    }

    func flushForTermination() async {
        guard let sessionID = currentSession?.id, sessionState.isActive else { return }
        flushPendingEvents()
        try? await sessionStore.flush(sessionID: sessionID)
    }

    private func prepareExportPreview(kind: PendingExportKind) async {
        guard let session = currentSession, !isExporting else {
            statusMessage = String(localized: "当前没有可导出的会话")
            return
        }
        statusMessage = String(localized: "正在检查导出内容中的敏感信息…")
        do {
            let configuration = RedactionConfiguration(
                isEnabled: true,
                categories: Set(RedactionCategory.allCases),
                customRules: customRedactionRules.filter {
                    $0.applies(to: session.targetPackage)
                }
            )
            let preview: RedactionPreview
            switch kind {
            case .session(let scope):
                preview = try await sessionStore.redactionPreview(
                    sessionID: session.id,
                    scope: scope,
                    configuration: configuration
                )
            case .incident(let incidentID):
                preview = try await sessionStore.incidentRedactionPreview(
                    sessionID: session.id,
                    incidentID: incidentID,
                    configuration: configuration
                )
            }
            exportPreview = ExportPreviewState(
                kind: kind,
                preview: preview,
                configuration: configuration
            )
            statusMessage = preview.totalMatchCount == 0
                ? String(localized: "未发现常见敏感信息；请确认后导出")
                : String(localized: "发现 \(preview.totalMatchCount) 处可能的敏感信息")
        } catch {
            statusMessage = String(localized: "生成脱敏预览失败：\(error.localizedDescription)")
        }
    }

    private func previewTitle(for kind: PendingExportKind) -> String {
        switch kind {
        case .session: String(localized: "选择会话导出位置")
        case .incident: String(localized: "选择问题包导出位置")
        }
    }

    private func exportEvidenceFile(_ source: URL) async {
        let panel = NSSavePanel()
        panel.title = String(localized: "导出证据")
        panel.prompt = String(localized: "导出")
        panel.nameFieldStringValue = source.lastPathComponent
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            statusMessage = String(localized: "证据已导出")
        } catch {
            statusMessage = String(localized: "证据导出失败：\(error.localizedDescription)")
        }
    }

    private func attachEvidence(
        _ item: CaptureEvidence,
        toIncidentID incidentID: UUID
    ) async {
        guard let index = incidents.firstIndex(where: { $0.id == incidentID }),
              let sessionID = currentSession?.id else {
            return
        }
        if !incidents[index].evidenceIDs.contains(item.id) {
            incidents[index].evidenceIDs.append(item.id)
        }
        if item.kind == .recording {
            incidents[index].recordingID = item.id
            incidents[index].recordingOffset = max(
                0,
                incidents[index].createdAt.timeIntervalSince(item.createdAt)
            )
        }
        try? await sessionStore.upsert(
            incident: incidents[index],
            sessionID: sessionID
        )
    }

    private func attachRecordingToMatchingIncidents(_ item: CaptureEvidence) async {
        guard item.kind == .recording,
              let sessionID = currentSession?.id else {
            return
        }
        let end = item.createdAt.addingTimeInterval(item.duration ?? 0)
        for index in incidents.indices {
            let wasMarkedDuringRecording = incidents[index].recordingOffset != nil
            let fallsInsideRecording = item.createdAt <= incidents[index].createdAt
                && incidents[index].createdAt <= end
            guard incidents[index].recordingID == nil,
                  wasMarkedDuringRecording || fallsInsideRecording else {
                continue
            }
            incidents[index].recordingID = item.id
            incidents[index].recordingOffset = max(
                0,
                incidents[index].createdAt.timeIntervalSince(item.createdAt)
            )
            if !incidents[index].evidenceIDs.contains(item.id) {
                incidents[index].evidenceIDs.append(item.id)
            }
            try? await sessionStore.upsert(
                incident: incidents[index],
                sessionID: sessionID
            )
        }
    }

    private func startRecordingSafetyMonitoring() {
        recordingSafetyTask?.cancel()
        recordingSafetyTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isRecording {
                await self.refreshRecordingSafetyStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refreshRecordingSafetyStatus() async {
        let macBytes = (try? await sessionStore.availableCapacity()) ?? 0
        let deviceBytes: Int64?
        if let serial = selectedDeviceSerial, let deviceService {
            deviceBytes = try? await deviceService.availableStorageBytes(serial: serial)
        } else {
            deviceBytes = nil
        }
        availableStorageBytes = macBytes
        let status = RecordingSafetyEvaluator.evaluate(
            macAvailableBytes: macBytes,
            deviceAvailableBytes: deviceBytes,
            configuredBitsPerSecond: recordingBitRate.bitsPerSecond
        )
        recordingSafetyStatus = status
        guard status.level != .normal else {
            lastAnnouncedRecordingSafetyLevel = nil
            return
        }
        if lastAnnouncedRecordingSafetyLevel != status.level {
            announceAccessibility(String(localized: "录屏\(status.level.title)"))
            lastAnnouncedRecordingSafetyLevel = status.level
        }
        statusMessage = status.level == .critical
            ? String(localized: "录屏继续进行；空间严重不足，请尽快停止并保存")
            : String(localized: "录屏继续进行；剩余空间偏低")
    }

    private func configureADB(savedPath: String?) async {
        adbAvailability = .checking
        statusMessage = String(localized: "正在查找 ADB…")
        guard let installation = await ADBLocator().locate(savedPath: savedPath) else {
            adbAvailability = .missing
            adbPath = ""
            adbVersion = ""
            adbSource = nil
            executor = nil
            deviceService = nil
            logService = nil
            captureService = nil
            statusMessage = String(localized: "内置 ADB 缺失或不可执行；请重新安装 GameLog，或选择外部 ADB")
            return
        }

        adbPath = installation.executableURL.path
        adbVersion = installation.versionText
        adbSource = installation.source
        adbAvailability = .ready(version: installation.versionText)
        let executor = ADBExecutor(executableURL: installation.executableURL)
        self.executor = executor
        deviceService = DeviceService(executor: executor)
        logService = LogStreamingService(executor: executor)
        captureService = CaptureService(executor: executor)
        await refreshDevices()
        startDeviceMonitoring()
    }

    private func launchLogStream(session: DebugSession, serial: String) {
        guard let logService else { return }
        logTask?.cancel()
        isStreaming = true
        logTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await batch in logService.events(
                    serial: serial,
                    buffers: currentSessionBuffers
                ) {
                    guard !Task.isCancelled else { break }
                    try await sessionStore.append(events: batch, sessionID: session.id)
                    enqueue(batch)
                }
                streamDidFinish(error: nil)
            } catch {
                streamDidFinish(error: error)
            }
        }
    }

    private func startDeviceMonitoring() {
        deviceMonitorTask?.cancel()
        deviceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, let deviceService = self.deviceService else { continue }
                do {
                    let snapshot = try await deviceService.listDevices()
                    await self.applyDeviceSnapshot(snapshot)
                    self.updateInputRateIfIdle()
                } catch {
                    // A transient polling error must not replace the last known device state.
                }
            }
        }
    }

    private func applyDeviceSnapshot(_ snapshot: [AndroidDevice]) async {
        guard snapshot != devices else { return }
        devices = snapshot

        guard let selectedSerial = selectedDeviceSerial else {
            selectedDeviceSerial = snapshot.first(where: { $0.state == .online })?.serial
            if selectedDeviceSerial != nil {
                loadRecentPackages()
                await refreshProcesses()
            }
            return
        }

        let selectedState = snapshot.first { $0.serial == selectedSerial }?.state
        if sessionState.isActive {
            if selectedState != .online {
                await handleActiveDeviceDisconnected(serial: selectedSerial)
            } else if wasDeviceDisconnected {
                await recoverActiveDevice(serial: selectedSerial)
            }
        } else if selectedState == nil {
            selectedDeviceSerial = snapshot.first(where: { $0.state == .online })?.serial
            selectedProcessID = nil
            selectedPackageName = nil
            packageInput = ""
            loadRecentPackages()
            await refreshProcesses()
        }
    }

    private func handleActiveDeviceDisconnected(serial: String) async {
        guard !wasDeviceDisconnected else { return }
        wasDeviceDisconnected = true
        logTask?.cancel()
        logTask = nil
        logRestartTask?.cancel()
        logRestartTask = nil
        isStreaming = false
        sessionState = .recovering
        statusMessage = String(localized: "设备 \(serial) 已断开，正在等待重连…")
        await persistSystemEvent(String(localized: "设备已断开 · \(serial)"))
        announceAccessibility(String(localized: "Android 设备已断开，正在等待重连"))
    }

    private func recoverActiveDevice(serial: String) async {
        guard let session = currentSession, let deviceService else { return }
        do {
            let pids = try await deviceService.pids(forPackage: session.targetPackage, serial: serial)
            guard !pids.isEmpty else {
                statusMessage = String(localized: "设备已重连，等待 \(session.targetPackage) 进程启动…")
                return
            }
            wasDeviceDisconnected = false
            currentTargetPIDs = pids
            scheduleFilterUpdate(delay: .zero)
            selectedProcessID = pids.sorted().first
            await refreshProcesses()
            await persistSystemEvent(String(localized: "设备已重连 · PID \(pids.sorted().map(String.init).joined(separator: ", "))"))
            sessionState = followLatest ? .capturing : .followingPaused
            statusMessage = String(localized: "会话已自动恢复")
            announceAccessibility(String(localized: "Android 设备已重连，会话已恢复"))
            logRestartTask?.cancel()
            logRestartTask = nil
            launchLogStream(session: session, serial: serial)
            if let pending = recoverableRecordings.first(where: { $0.deviceSerial == serial }) {
                await recoverRecording(pending)
            }
        } catch {
            statusMessage = String(localized: "设备恢复失败，2 秒后重试：\(error.localizedDescription)")
        }
    }

    private func startProcessMonitoring() {
        processMonitorTask?.cancel()
        processMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled,
                      let self,
                      self.sessionState.isActive,
                      !self.wasDeviceDisconnected,
                      let serial = self.selectedDeviceSerial,
                      let session = self.currentSession,
                      let deviceService = self.deviceService else {
                    continue
                }
                do {
                    let pids = try await deviceService.pids(
                        forPackage: session.targetPackage,
                        serial: serial
                    )
                    await self.applyTargetPIDs(pids, session: session, serial: serial)
                } catch {
                    // Device monitoring owns connection-level errors.
                }
            }
        }
    }

    private func applyTargetPIDs(_ pids: Set<Int>, session: DebugSession, serial: String) async {
        guard pids != currentTargetPIDs else { return }
        let previous = currentTargetPIDs
        let hasPreviouslyRun = !sessionTargetPIDs.isEmpty
        currentTargetPIDs = pids
        sessionTargetPIDs.formUnion(pids)
        try? await sessionStore.mergeObservedTargetPIDs(
            sessionTargetPIDs,
            sessionID: session.id
        )
        scheduleFilterUpdate(delay: .zero)
        if pids.isEmpty {
            await persistSystemEvent(
                String(localized: "目标进程已退出 · 原 PID \(previous.sorted().map(String.init).joined(separator: ", "))")
            )
            sessionState = .recovering
            statusMessage = String(localized: "等待 \(session.targetPackage) 重新启动…")
            return
        }

        selectedProcessID = pids.sorted().first
        let lifecycle = previous.isEmpty && !hasPreviouslyRun
            ? String(localized: "目标进程已启动")
            : String(localized: "目标进程已重启")
        await persistSystemEvent(
            "\(lifecycle) · PID \(pids.sorted().map(String.init).joined(separator: ", "))"
        )
        sessionState = followLatest ? .capturing : .followingPaused
        statusMessage = String(localized: "已恢复目标进程日志")
        if logTask == nil {
            launchLogStream(session: session, serial: serial)
        }
    }

    private func enqueue(_ batch: [LogEvent]) {
        transportDroppedEventCount += batch.reduce(into: UInt64(0)) { count, event in
            count += LogDropDetector.reportedDroppedLineCount(in: event)
        }
        pendingEvents.append(contentsOf: batch)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.flushPendingEvents()
            self?.flushTask = nil
        }
    }

    private func flushPendingEvents() {
        guard !pendingEvents.isEmpty else { return }
        inputRateSampleCount += pendingEvents.filter { !$0.isMarker }.count
        let now = Date()
        let sampleDuration = now.timeIntervalSince(inputRateSampleStartedAt)
        if sampleDuration >= 0.75 {
            inputRatePerSecond = Double(inputRateSampleCount) / sampleDuration
            inputRateSampleCount = 0
            inputRateSampleStartedAt = now
        }
        let removed = buffer.append(contentsOf: pendingEvents)
        evictedEventCount += UInt64(removed)
        pendingEvents.removeAll(keepingCapacity: true)
        events = buffer.events
        scheduleFilterUpdate(delay: .zero)
        scheduleDiagnosticUpdate()
    }

    private func streamDidFinish(error: Error?) {
        flushPendingEvents()
        isStreaming = false
        logTask = nil
        guard sessionState != .stopping && sessionState != .stopped else { return }
        if let error, !(error is CancellationError) {
            sessionState = .recovering
            statusMessage = String(localized: "日志流已中断，等待设备恢复：\(error.localizedDescription)")
        } else if sessionState.isActive {
            sessionState = .recovering
            statusMessage = String(localized: "日志流已结束，等待恢复")
        }
        scheduleLogStreamRestart()
    }

    private func scheduleLogStreamRestart() {
        logRestartTask?.cancel()
        guard sessionState.isActive,
              !wasDeviceDisconnected,
              selectedDevice?.state == .online,
              currentSession != nil,
              selectedDeviceSerial != nil else {
            return
        }
        logRestartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled,
                  let self,
                  self.sessionState.isActive,
                  !self.wasDeviceDisconnected,
                  self.logTask == nil,
                  let session = self.currentSession,
                  let serial = self.selectedDeviceSerial,
                  self.selectedDevice?.state == .online else {
                return
            }
            self.logRestartTask = nil
            await self.persistSystemEvent(String(localized: "日志流已重新连接"))
            self.sessionState = self.followLatest ? .capturing : .followingPaused
            self.statusMessage = String(localized: "日志流已恢复")
            self.launchLogStream(session: session, serial: serial)
        }
    }

    private func persistFailureEvent(_ message: String, kind: LogEventKind) async {
        let marker = evidenceEvent(kind: kind, message: message)
        if let sessionID = currentSession?.id {
            try? await sessionStore.append(events: [marker], sessionID: sessionID)
        }
        enqueue([marker])
    }

    private func persistSystemEvent(_ message: String) async {
        let marker = systemEvent(message)
        if let sessionID = currentSession?.id {
            try? await sessionStore.append(events: [marker], sessionID: sessionID)
        }
        enqueue([marker])
    }

    private func systemEvent(_ message: String) -> LogEvent {
        evidenceEvent(kind: .system, message: message)
    }

    private func evidenceEvent(
        kind: LogEventKind,
        message: String,
        evidenceID: UUID? = nil
    ) -> LogEvent {
        LogEvent(
            timestampText: Self.timeFormatter.string(from: Date()),
            pid: selectedProcessID,
            tid: nil,
            level: kind == .recordingFailed ? .error : .info,
            tag: "GameLog",
            message: message,
            rawText: message,
            kind: kind,
            evidenceID: evidenceID
        )
    }

    private func resetVisibleSession() {
        pendingEvents.removeAll(keepingCapacity: true)
        buffer.removeAll()
        events = []
        filteredEvents = []
        evidence = []
        recoverableRecordings = []
        bookmarkedEventIDs = []
        incidents = []
        diagnosticIssues = []
        selectedEventIDs = []
        evictedEventCount = 0
        sessionTargetPIDs = []
        transportDroppedEventCount = 0
        inputRatePerSecond = 0
        inputRateSampleCount = 0
        inputRateSampleStartedAt = Date()
        lastExportURL = nil
        exportPreview = nil
    }

    private func scheduleDiagnosticUpdate() {
        diagnosticTask?.cancel()
        let sourceEvents = events
        let targetPIDs = sessionTargetPIDs
        let targetPackage = currentSession?.targetPackage ?? selectedPackageName
        diagnosticTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let issues = await Task.detached(priority: .utility) {
                DiagnosticAggregator.aggregate(
                    events: sourceEvents,
                    targetPIDs: targetPIDs,
                    targetPackage: targetPackage
                )
            }.value
            guard !Task.isCancelled else { return }
            self?.diagnosticIssues = issues
        }
    }

    private func scheduleFilterUpdate(delay: Duration = .milliseconds(150)) {
        filterTask?.cancel()
        let sourceEvents = events
        let configuration = filterConfiguration
        let targetPIDs = sessionTargetPIDs
        filterTask = Task { [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LogFilterEngine.filter(
                        events: sourceEvents,
                        configuration: configuration,
                        targetPIDs: targetPIDs
                    )
                }.value
                guard !Task.isCancelled else { return }
                self?.filteredEvents = result
                self?.filterError = nil
                if let self {
                    let visibleIDs = Set(result.map(\.id))
                    let retainedSelection = self.selectedEventIDs.intersection(visibleIDs)
                    if retainedSelection.isEmpty, !self.selectedEventIDs.isEmpty {
                        self.selectedEventIDs = result.first.map { [$0.id] } ?? []
                    } else {
                        self.selectedEventIDs = retainedSelection
                    }
                }
            } catch {
                self?.filterError = error.localizedDescription
            }
        }
    }

    private func persistSavedFilterPresets() {
        guard let data = try? JSONEncoder().encode(savedFilterPresets) else { return }
        UserDefaults.standard.set(data, forKey: "savedFilterPresets")
    }

    private func persistCustomRedactionRules() {
        guard let data = try? JSONEncoder().encode(customRedactionRules) else { return }
        UserDefaults.standard.set(data, forKey: "customRedactionRules")
    }

    private func updateInputRateIfIdle() {
        let now = Date()
        let sampleDuration = now.timeIntervalSince(inputRateSampleStartedAt)
        guard sampleDuration >= 1.5 else { return }
        inputRatePerSecond = Double(inputRateSampleCount) / sampleDuration
        inputRateSampleCount = 0
        inputRateSampleStartedAt = now
    }

    private func announceAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }

    private func loadRecentPackages() {
        guard let serial = selectedDeviceSerial,
              let data = UserDefaults.standard.data(forKey: "recentPackagesByDevice"),
              let all = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            recentPackages = []
            return
        }
        recentPackages = all[serial] ?? []
    }

    private func rememberPackage(_ packageName: String) {
        guard let serial = selectedDeviceSerial else { return }
        let defaults = UserDefaults.standard
        var all: [String: [String]] = [:]
        if let data = defaults.data(forKey: "recentPackagesByDevice"),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            all = decoded
        }
        var values = all[serial] ?? []
        values.removeAll { $0 == packageName }
        values.insert(packageName, at: 0)
        all[serial] = Array(values.prefix(10))
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: "recentPackagesByDevice")
        }
        recentPackages = all[serial] ?? []
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let incidentTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
