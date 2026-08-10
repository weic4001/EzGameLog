import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ArchiveModel {
    private(set) var entries: [SessionArchiveEntry] = []
    private(set) var snapshots: [SessionAnalysisSnapshot] = []
    private(set) var trends: [DiagnosticTrend] = []
    private(set) var comparison: SessionComparison?
    private(set) var alignment: SessionTimelineAlignment?
    private(set) var timelineAlignments: [SessionTimelineAlignment] = []
    private(set) var regressionReport: RegressionReport?
    private(set) var automaticRegressionReports: [UUID: RegressionReport] = [:]
    private(set) var baselines: [RegressionBaseline] = []
    private(set) var regressionConfigurations: [RegressionConfiguration] = []
    private(set) var symbolCatalog = SymbolCatalog.empty
    private(set) var symbolicationReports: [UUID: SessionSymbolicationReport] = [:]
    private(set) var pendingImportPreview: SessionImportPreview?
    private(set) var statusMessage = "准备读取会话归档"
    private(set) var isLoading = false
    private(set) var isPreviewingImport = false
    private(set) var isImporting = false
    private(set) var isIndexingSymbols = false
    private(set) var isSymbolicating = false

    var selectedSessionID: UUID?
    var baselineSessionID: UUID? {
        didSet {
            updateComparison()
            scheduleAdvancedComparison()
        }
    }
    var comparisonSessionID: UUID? {
        didSet {
            updateComparison()
            scheduleAdvancedComparison()
        }
    }
    var trendPackageFilter = "" {
        didSet { updateTrends() }
    }
    var symbolPackage = ""

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let symbolStore: SymbolCatalogStore
    @ObservationIgnored private var advancedComparisonTask: Task<Void, Never>?

    init(
        store: SessionStore? = nil,
        symbolStore: SymbolCatalogStore? = nil
    ) {
        let root = UserDefaults.standard.string(forKey: "sessionRootDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.store = store ?? SessionStore(rootDirectory: root)
        self.symbolStore = symbolStore ?? SymbolCatalogStore()
    }

    var selectedEntry: SessionArchiveEntry? {
        entries.first { $0.id == selectedSessionID }
    }

    var selectedSnapshot: SessionAnalysisSnapshot? {
        snapshots.first { $0.sessionID == selectedSessionID }
    }

    var selectedSymbolicationReport: SessionSymbolicationReport? {
        guard let selectedSessionID else { return nil }
        return symbolicationReports[selectedSessionID]
    }

    var comparisonTargetPackage: String? {
        snapshots.first { $0.sessionID == comparisonSessionID }?.targetPackage
    }

    var availablePackages: [String] {
        Array(Set(entries.map(\.session.targetPackage))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var visibleSymbolRoots: [SymbolCatalogRoot] {
        symbolCatalog.roots(for: symbolPackage)
    }

    var visibleSymbolFileCount: Int {
        symbolCatalog.files(for: symbolPackage).count
    }

    var resolvedSymbolizerPath: String {
        if !symbolCatalog.symbolizerPath.isEmpty {
            return symbolCatalog.symbolizerPath
        }
        return NDKSymbolizerLocator.locate()?.path ?? ""
    }

    func isOfficialBaseline(_ sessionID: UUID) -> Bool {
        baselines.contains { $0.sessionID == sessionID }
    }

    func automaticRegressionReport(
        for sessionID: UUID
    ) -> RegressionReport? {
        automaticRegressionReports[sessionID]
    }

    func regressionConfiguration(
        for targetPackage: String
    ) -> RegressionConfiguration {
        regressionConfigurations.first {
            $0.targetPackage == targetPackage
        } ?? .recommended(for: targetPackage)
    }

    func symbolicatedFrames(
        for diagnosticID: UUID
    ) -> [SymbolicatedNativeFrame] {
        selectedSymbolicationReport?.frames.filter {
            $0.frame.diagnosticID == diagnosticID
        } ?? []
    }

    func refresh(forceAnalysis: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = forceAnalysis ? "正在重新分析全部会话…" : "正在读取会话归档…"
        defer { isLoading = false }
        do {
            async let loadedEntries = store.archiveEntries()
            async let loadedSnapshots = store.analysisSnapshots(
                forceRefresh: forceAnalysis
            )
            async let loadedReports = store.symbolicationReports()
            async let loadedBaselines = store.regressionBaselines()
            async let loadedConfigurations = store.regressionConfigurations()
            async let loadedCatalog = symbolStore.catalog()
            let (
                newEntries,
                newSnapshots,
                newReports,
                newBaselines,
                newConfigurations,
                newCatalog
            ) = try await (
                loadedEntries,
                loadedSnapshots,
                loadedReports,
                loadedBaselines,
                loadedConfigurations,
                loadedCatalog
            )
            entries = newEntries
            snapshots = newSnapshots
            symbolicationReports = newReports
            baselines = newBaselines.filter { baseline in
                newEntries.contains { $0.id == baseline.sessionID }
            }
            regressionConfigurations = newConfigurations
            rebuildAutomaticRegressionReports()
            symbolCatalog = newCatalog
            if selectedSessionID == nil
                || !newEntries.contains(where: { $0.id == selectedSessionID }) {
                selectedSessionID = newEntries.first?.id
            }
            if symbolPackage.isEmpty
                || !newEntries.contains(where: {
                    $0.session.targetPackage == symbolPackage
                }) {
                symbolPackage = newEntries.first?.session.targetPackage ?? ""
            }
            let comparableIDs = newSnapshots.map(\.sessionID)
            if comparisonSessionID == nil
                || !comparableIDs.contains(comparisonSessionID!) {
                comparisonSessionID = comparableIDs.first
            }
            let comparisonPackage = newSnapshots.first {
                $0.sessionID == comparisonSessionID
            }?.targetPackage
            let officialBaseline = newBaselines.first {
                $0.targetPackage == comparisonPackage
                    && comparableIDs.contains($0.sessionID)
                    && $0.sessionID != comparisonSessionID
            }?.sessionID
            if baselineSessionID == nil
                || !comparableIDs.contains(baselineSessionID!)
                || baselineSessionID == comparisonSessionID {
                baselineSessionID = officialBaseline
                    ?? comparableIDs.first { $0 != comparisonSessionID }
                    ?? comparableIDs.first
            }
            updateTrends()
            updateComparison()
            await updateAdvancedComparison(
                baselineID: baselineSessionID,
                comparisonID: comparisonSessionID
            )
            statusMessage = newEntries.isEmpty
                ? "暂无已保存会话"
                : "已索引 \(newEntries.count) 个会话"
        } catch {
            statusMessage = "读取会话归档失败：\(error.localizedDescription)"
        }
    }

    func saveAnnotation(
        sessionID: UUID,
        title: String,
        note: String,
        labelsText: String
    ) async {
        let annotation = SessionAnnotation(
            title: title,
            note: note,
            labels: labelsText
                .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
                .map(String.init),
            updatedAt: Date()
        )
        do {
            try await store.updateAnnotation(annotation, sessionID: sessionID)
            entries = try await store.archiveEntries()
            selectedSessionID = sessionID
            statusMessage = "会话注释已保存"
        } catch {
            statusMessage = "保存会话注释失败：\(error.localizedDescription)"
        }
    }

    func setRegressionBaseline(sessionID: UUID) async {
        do {
            let baseline = try await store.setRegressionBaseline(
                sessionID: sessionID
            )
            baselines.removeAll { $0.targetPackage == baseline.targetPackage }
            baselines.append(baseline)
            rebuildAutomaticRegressionReports()
            baselineSessionID = sessionID
            statusMessage = "已将该会话设为 \(baseline.targetPackage) 的回归基线"
        } catch {
            statusMessage = "设置回归基线失败：\(error.localizedDescription)"
        }
    }

    func chooseAndImportSession() async {
        let panel = NSOpenPanel()
        panel.title = "导入 GameLog 会话包"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await previewImport(from: url)
    }

    func previewImport(from url: URL) async {
        guard !isPreviewingImport, !isImporting else { return }
        isPreviewingImport = true
        statusMessage = "正在校验会话包，生成导入预检…"
        defer { isPreviewingImport = false }
        do {
            pendingImportPreview = try await store.previewImport(from: url)
            statusMessage = "预检完成，请确认导入内容"
        } catch {
            pendingImportPreview = nil
            statusMessage = "导入预检失败：\(error.localizedDescription)"
        }
    }

    func cancelPendingImport() {
        pendingImportPreview = nil
        statusMessage = "已取消导入"
    }

    func confirmPendingImport() async {
        guard let preview = pendingImportPreview else { return }
        await importSession(from: preview.sourceURL)
    }

    func importSession(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        statusMessage = "正在校验并导入会话包…"
        defer { isImporting = false }
        do {
            let result = try await store.importSession(from: url)
            pendingImportPreview = nil
            await refresh(forceAnalysis: true)
            selectedSessionID = result.sessionID
            statusMessage = result.disposition == .imported
                ? "已导入 \(result.targetPackage)，共 \(result.importedEventCount) 条事件"
                : "会话已存在，已安全合并注释与 \(result.mergedLabelCount) 个标签"
        } catch {
            statusMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func chooseAndIndexSymbols() async {
        guard !symbolPackage.isEmpty else {
            statusMessage = "请先选择符号目录对应的目标包"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择 NDK 符号目录"
        panel.prompt = "建立索引"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await indexSymbols(directory: url, packagePattern: symbolPackage)
    }

    func indexSymbols(directory: URL, packagePattern: String) async {
        guard !isIndexingSymbols else { return }
        isIndexingSymbols = true
        statusMessage = "正在扫描 ELF 符号文件…"
        defer { isIndexingSymbols = false }
        do {
            _ = try await symbolStore.index(
                directory: directory,
                packagePattern: packagePattern
            )
            symbolCatalog = try await symbolStore.catalog()
            statusMessage = "符号索引完成，共 \(symbolCatalog.files(for: packagePattern).count) 个库"
        } catch {
            statusMessage = "符号索引失败：\(error.localizedDescription)"
        }
    }

    func removeSymbolRoot(_ id: UUID) async {
        do {
            try await symbolStore.removeRoot(id: id)
            symbolCatalog = try await symbolStore.catalog()
            statusMessage = "符号目录已从索引移除，源文件未删除"
        } catch {
            statusMessage = "移除符号索引失败：\(error.localizedDescription)"
        }
    }

    func chooseSymbolizerExecutable() async {
        let panel = NSOpenPanel()
        panel.title = "选择 Android NDK llvm-symbolizer"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await symbolStore.setSymbolizerPath(url.path)
            symbolCatalog = try await symbolStore.catalog()
            statusMessage = "已选择 llvm-symbolizer"
        } catch {
            statusMessage = "无法使用符号化工具：\(error.localizedDescription)"
        }
    }

    func symbolicateSelectedSession() async {
        guard !isSymbolicating,
              let entry = selectedEntry,
              let snapshot = selectedSnapshot else {
            return
        }
        isSymbolicating = true
        statusMessage = "正在符号化 \(entry.session.targetPackage)…"
        defer { isSymbolicating = false }
        do {
            guard let symbolizerURL = try await symbolStore.resolvedSymbolizerURL() else {
                throw NativeSymbolicationError.symbolizerUnavailable
            }
            let catalog = try await symbolStore.catalog()
            let report = try await NativeSymbolicationService.symbolicate(
                sessionID: entry.id,
                targetPackage: entry.session.targetPackage,
                issues: snapshot.diagnosticIssues,
                catalog: catalog,
                symbolizerURL: symbolizerURL
            )
            try await store.saveSymbolicationReport(
                report,
                sessionID: entry.id
            )
            symbolicationReports[entry.id] = report
            updateTrends()
            statusMessage = "符号化完成：\(report.symbolicatedCount) / \(report.frames.count) 个 Native 帧"
        } catch {
            statusMessage = "符号化失败：\(error.localizedDescription)"
        }
    }

    func copySelectedSymbolicationReport() {
        guard let report = selectedSymbolicationReport else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.plainText, forType: .string)
        statusMessage = "已复制完整符号化结果"
    }

    func exportSelectedSymbolicationReport() {
        guard let report = selectedSymbolicationReport,
              let entry = selectedEntry else {
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出符号化结果"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "GameLog-Symbolicated-\(entry.id.uuidString.prefix(8)).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report.plainText.utf8).write(to: url, options: .atomic)
            statusMessage = "符号化结果已导出"
        } catch {
            statusMessage = "导出符号化结果失败：\(error.localizedDescription)"
        }
    }

    func saveRegressionThresholds(
        _ thresholds: RegressionThresholds,
        targetPackage: String
    ) async {
        var configuration = regressionConfiguration(for: targetPackage)
        configuration.thresholds = thresholds.normalized()
        await persistRegressionConfiguration(
            configuration,
            successMessage: "已保存 \(targetPackage) 的回归阈值"
        )
    }

    func ignoreRegressionAlert(
        _ alert: RegressionAlert,
        targetPackage: String
    ) async {
        var configuration = regressionConfiguration(for: targetPackage)
        configuration.ignoredAlertKeys.insert(alert.suppressionKey)
        await persistRegressionConfiguration(
            configuration,
            successMessage: "已忽略该告警规则，可在告警规则中恢复"
        )
    }

    func restoreIgnoredRegressionAlerts(targetPackage: String) async {
        var configuration = regressionConfiguration(for: targetPackage)
        configuration.ignoredAlertKeys.removeAll()
        await persistRegressionConfiguration(
            configuration,
            successMessage: "已恢复 \(targetPackage) 的全部已忽略告警"
        )
    }

    func revealSelectedSession() {
        guard let selectedEntry else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedEntry.directoryURL])
    }

    private func updateTrends() {
        trends = SessionAnalysisService.trends(
            snapshots: snapshots,
            targetPackage: trendPackageFilter.isEmpty ? nil : trendPackageFilter,
            symbolicationReports: symbolicationReports
        )
    }

    private func rebuildAutomaticRegressionReports() {
        var reports: [UUID: RegressionReport] = [:]
        for baseline in baselines {
            guard let baselineSnapshot = snapshots.first(where: {
                $0.sessionID == baseline.sessionID
            }) else {
                continue
            }
            for candidate in snapshots where
                candidate.targetPackage == baseline.targetPackage
                    && candidate.sessionID != baseline.sessionID {
                reports[candidate.sessionID] = SessionRegressionService.regression(
                    baseline: baselineSnapshot,
                    comparison: candidate,
                    configuration: regressionConfiguration(
                        for: candidate.targetPackage
                    )
                )
            }
        }
        automaticRegressionReports = reports
    }

    private func updateComparison() {
        guard let baselineSessionID,
              let comparisonSessionID,
              baselineSessionID != comparisonSessionID,
              let baseline = snapshots.first(where: {
                  $0.sessionID == baselineSessionID
              }),
              let candidate = snapshots.first(where: {
                  $0.sessionID == comparisonSessionID
              }) else {
            comparison = nil
            regressionReport = nil
            alignment = nil
            timelineAlignments = []
            return
        }
        comparison = SessionAnalysisService.compare(
            baseline: baseline,
            comparison: candidate
        )
        regressionReport = baseline.targetPackage == candidate.targetPackage
            ? SessionRegressionService.regression(
                baseline: baseline,
                comparison: candidate,
                configuration: regressionConfiguration(
                    for: candidate.targetPackage
                )
            )
            : nil
    }

    private func persistRegressionConfiguration(
        _ configuration: RegressionConfiguration,
        successMessage: String
    ) async {
        do {
            let saved = try await store.updateRegressionConfiguration(
                configuration
            )
            regressionConfigurations.removeAll {
                $0.targetPackage == saved.targetPackage
            }
            regressionConfigurations.append(saved)
            rebuildAutomaticRegressionReports()
            updateComparison()
            statusMessage = successMessage
        } catch {
            statusMessage = "保存回归规则失败：\(error.localizedDescription)"
        }
    }

    private func scheduleAdvancedComparison() {
        advancedComparisonTask?.cancel()
        let baselineID = baselineSessionID
        let comparisonID = comparisonSessionID
        advancedComparisonTask = Task { [weak self] in
            await self?.updateAdvancedComparison(
                baselineID: baselineID,
                comparisonID: comparisonID
            )
        }
    }

    private func updateAdvancedComparison(
        baselineID: UUID?,
        comparisonID: UUID?
    ) async {
        guard let baselineID,
              let comparisonID,
              baselineID != comparisonID,
              let baselineSnapshot = snapshots.first(where: {
                  $0.sessionID == baselineID
              }),
              let comparisonSnapshot = snapshots.first(where: {
                  $0.sessionID == comparisonID
              }) else {
            alignment = nil
            timelineAlignments = []
            return
        }
        do {
            async let baselineLoaded = store.load(sessionID: baselineID)
            async let comparisonLoaded = store.load(sessionID: comparisonID)
            let (baseline, candidate) = try await (
                baselineLoaded,
                comparisonLoaded
            )
            try Task.checkCancellation()
            guard baselineSessionID == baselineID,
                  comparisonSessionID == comparisonID else {
                return
            }
            alignment = SessionRegressionService.align(
                baselineSession: baseline.0,
                baselineEvents: baseline.2,
                baselineSnapshot: baselineSnapshot,
                comparisonSession: candidate.0,
                comparisonEvents: candidate.2,
                comparisonSnapshot: comparisonSnapshot
            )
            var allAlignments: [SessionTimelineAlignment] = []
            let candidates = snapshots
                .filter {
                    $0.sessionID != baselineID
                        && $0.targetPackage == baselineSnapshot.targetPackage
                }
                .sorted { $0.sessionCreatedAt > $1.sessionCreatedAt }
                .prefix(20)
            for snapshot in candidates {
                try Task.checkCancellation()
                let loaded: (
                    DebugSession,
                    SessionPaths,
                    [LogEvent],
                    [CaptureEvidence]
                )
                if snapshot.sessionID == comparisonID {
                    loaded = candidate
                } else {
                    loaded = try await store.load(sessionID: snapshot.sessionID)
                }
                allAlignments.append(SessionRegressionService.align(
                    baselineSession: baseline.0,
                    baselineEvents: baseline.2,
                    baselineSnapshot: baselineSnapshot,
                    comparisonSession: loaded.0,
                    comparisonEvents: loaded.2,
                    comparisonSnapshot: snapshot
                ))
            }
            guard baselineSessionID == baselineID else { return }
            timelineAlignments = allAlignments
        } catch is CancellationError {
            return
        } catch {
            alignment = nil
            timelineAlignments = []
            statusMessage = "时间轴对齐失败：\(error.localizedDescription)"
        }
    }
}
