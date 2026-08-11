import SwiftUI

struct SessionArchiveView: View {
    @Environment(ArchiveModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            if let preview = model.pendingImportPreview {
                SessionImportPreviewView(preview: preview)
                Divider()
            }
            TabView {
                ArchiveBrowserView()
                    .tabItem { Label(String(localized: "会话"), systemImage: "archivebox") }
                DiagnosticTrendsView()
                    .tabItem { Label(String(localized: "趋势"), systemImage: "chart.line.uptrend.xyaxis") }
                SessionComparisonView()
                    .tabItem { Label(String(localized: "对比"), systemImage: "rectangle.split.2x1") }
                SymbolicationWorkspaceView()
                    .tabItem { Label(String(localized: "符号"), systemImage: "curlybraces.square") }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isLoading || model.isPreviewingImport || model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "归档操作进行中"))
                }
                Button {
                    Task { await model.chooseAndImportSession() }
                } label: {
                    Label(String(localized: "导入会话"), systemImage: "square.and.arrow.down")
                }
                .disabled(model.isImporting || model.isPreviewingImport)
                .help(String(localized: "导入其他成员导出的 GameLog 会话目录（⇧⌘I）"))
                Button {
                    Task { await model.refresh(forceAnalysis: true) }
                } label: {
                    Label(String(localized: "重新分析"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .help(String(localized: "重新读取日志并刷新归档分析"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(model.statusMessage)
                    .lineLimit(1)
                    .accessibilityLabel(String(localized: "归档状态"))
                    .accessibilityValue(model.statusMessage)
                Spacer()
                Text(String(localized: "\(model.entries.count) 个会话"))
                    .monospacedDigit()
                    .accessibilityLabel(String(localized: "归档会话数量"))
                    .accessibilityValue("\(model.entries.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
        .task {
            if model.entries.isEmpty {
                await model.refresh()
            }
        }
    }
}

private struct ArchiveBrowserView: View {
    @Environment(ArchiveModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(model.entries, selection: $model.selectedSessionID) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(
                            entry.annotation.title.isEmpty
                                ? entry.session.targetPackage
                                : entry.annotation.title
                        )
                        .lineLimit(1)
                        if entry.isInProgress {
                            Image(systemName: "record.circle")
                                .foregroundStyle(.orange)
                                .accessibilityLabel(String(localized: "会话尚未完成"))
                        }
                        if let report = model.automaticRegressionReport(
                            for: entry.id
                        ),
                        let severity = report.highestSeverity {
                            Image(systemName: regressionImage(severity))
                                .foregroundStyle(regressionColor(severity))
                                .help(String(localized: "\(severity.title)回归告警"))
                                .accessibilityLabel(String(localized: "\(severity.title)回归告警"))
                        }
                    }
                    Text(
                        "\(entry.session.device.displayName) · "
                            + entry.session.createdAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .tag(entry.id)
            }
            .listStyle(.sidebar)
            .navigationTitle(String(localized: "会话归档"))
            .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 340)
        } detail: {
            if let entry = model.selectedEntry {
                ArchiveSessionDetailView(entry: entry)
                    .id(entry.id)
            } else {
                ContentUnavailableView(
                    String(localized: "选择一个会话"),
                    systemImage: "archivebox",
                    description: Text(String(localized: "在左侧选择会话后查看分析和本地注释。"))
                )
            }
        }
    }

    private func regressionImage(_ severity: RegressionSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    private func regressionColor(_ severity: RegressionSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct ArchiveSessionDetailView: View {
    @Environment(ArchiveModel.self) private var model
    let entry: SessionArchiveEntry
    @State private var title: String
    @State private var note: String
    @State private var labels: String

    init(entry: SessionArchiveEntry) {
        self.entry = entry
        _title = State(initialValue: entry.annotation.title)
        _note = State(initialValue: entry.annotation.note)
        _labels = State(initialValue: entry.annotation.labels.joined(separator: ", "))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.session.targetPackage)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                        Text(sessionSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack {
                        if model.isOfficialBaseline(entry.id) {
                            Label(String(localized: "回归基线"), systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button(String(localized: "设为回归基线")) {
                                Task {
                                    await model.setRegressionBaseline(
                                        sessionID: entry.id
                                    )
                                }
                            }
                        }
                        Button(String(localized: "在 Finder 中显示")) {
                            model.revealSelectedSession()
                        }
                    }
                }

                if let snapshot = model.selectedSnapshot {
                    metrics(snapshot)
                    diagnostics(snapshot)
                    topTags(snapshot)
                } else {
                    ContentUnavailableView(
                        String(localized: "分析尚不可用"),
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text(String(localized: "点击工具栏“重新分析”生成该会话的统计。"))
                    )
                    .frame(maxWidth: .infinity)
                }

                GroupBox(String(localized: "本地注释")) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(String(localized: "会话标题"), text: $title)
                        TextField(String(localized: "标签，逗号分隔"), text: $labels)
                        TextEditor(text: $note)
                            .font(.body)
                            .frame(minHeight: 90)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator)
                            }
                        HStack {
                            Spacer()
                            Button(String(localized: "保存注释")) {
                                Task {
                                    await model.saveAnnotation(
                                        sessionID: entry.id,
                                        title: title,
                                        note: note,
                                        labelsText: labels
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(4)
                }
            }
            .padding(20)
        }
    }

    private var sessionSubtitle: String {
        let duration = entry.session.endedAt.map {
            $0.timeIntervalSince(entry.session.createdAt).formattedDuration
        } ?? String(localized: "未完成")
        return "\(entry.session.device.displayName) · "
            + "\(entry.session.createdAt.formatted(date: .long, time: .standard)) · "
            + duration
    }

    private func metrics(_ snapshot: SessionAnalysisSnapshot) -> some View {
        HStack(spacing: 10) {
            ArchiveMetricCard(title: String(localized: "日志"), value: "\(snapshot.logEventCount)")
            ArchiveMetricCard(title: String(localized: "错误"), value: "\(snapshot.errorCount)")
            ArchiveMetricCard(title: String(localized: "诊断"), value: "\(snapshot.diagnosticIssues.count)")
            ArchiveMetricCard(title: String(localized: "问题"), value: "\(snapshot.incidentCount)")
            ArchiveMetricCard(title: String(localized: "证据"), value: "\(snapshot.artifactCount)")
        }
    }

    @ViewBuilder
    private func diagnostics(_ snapshot: SessionAnalysisSnapshot) -> some View {
        if !snapshot.diagnosticIssues.isEmpty {
            GroupBox("Crash / ANR") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.diagnosticIssues.prefix(8)) { issue in
                        HStack(alignment: .top) {
                            Image(systemName: issue.kind.systemImage)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.title)
                                    .lineLimit(2)
                                Text(String(localized: "\(issue.kind.title) · \(issue.occurrenceCount) 次"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let symbolicated = model.symbolicatedFrames(
                                    for: issue.id
                                )
                                if let frame = symbolicated.first,
                                   let function = frame.bestFunction {
                                    Text(function)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private func topTags(_ snapshot: SessionAnalysisSnapshot) -> some View {
        GroupBox(String(localized: "高频 Tag")) {
            VStack(spacing: 7) {
                ForEach(snapshot.topTags.prefix(10)) { item in
                    HStack {
                        Text(item.tag)
                            .font(.body.monospaced())
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(4)
        }
    }
}

private struct DiagnosticTrendsView: View {
    @Environment(ArchiveModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "跨会话 Crash / ANR 趋势"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker(String(localized: "目标包"), selection: $model.trendPackageFilter) {
                    Text(String(localized: "全部项目")).tag("")
                    ForEach(model.availablePackages, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .frame(width: 280)
            }

            if model.trends.isEmpty {
                ContentUnavailableView(
                    String(localized: "暂无可聚合诊断"),
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text(String(localized: "完成包含 Crash 或 ANR 的会话后会在这里形成趋势。"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.trends) { trend in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: trend.kind.systemImage)
                            .foregroundStyle(.orange)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trend.title)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Text(String(localized: "\(trend.sessionCount) 个会话"))
                                Text(String(localized: "\(trend.occurrenceCount) 次"))
                                Text(String(localized: "最近 \(trend.lastOccurredAt.formatted(date: .abbreviated, time: .shortened))"))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let symbol = trend.symbolHint {
                                Text(symbol)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            if let location = trend.sourceLocationHint {
                                Text(location)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(20)
    }
}

private struct SessionComparisonView: View {
    @Environment(ArchiveModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "双会话差异"))
                    .font(.title2.weight(.semibold))
                HStack {
                    sessionPicker(String(localized: "基准"), selection: $model.baselineSessionID)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    sessionPicker(String(localized: "对比"), selection: $model.comparisonSessionID)
                }

                if let comparison = model.comparison {
                    HStack(spacing: 10) {
                        ForEach(comparison.metrics) { metric in
                            ArchiveMetricCard(
                                title: metric.title,
                                value: signed(metric.delta),
                                subtitle: "\(metric.baseline) → \(metric.comparison)"
                            )
                        }
                    }
                    regressionSummary
                    alignmentSummary
                    comparisonDiagnostics(comparison)
                    changedTags(comparison)
                } else {
                    ContentUnavailableView(
                        String(localized: "请选择两个不同会话"),
                        systemImage: "rectangle.split.2x1",
                        description: Text(String(localized: "建议选择相同目标包的两个会话进行对比。"))
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var regressionSummary: some View {
        if let report = model.regressionReport,
           let targetPackage = model.comparisonTargetPackage {
            let configuration = model.regressionConfiguration(
                for: targetPackage
            )
            GroupBox(String(localized: "自动回归基线检查")) {
                VStack(alignment: .leading, spacing: 8) {
                    if report.alerts.isEmpty {
                        Label(String(localized: "未发现显著回归"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(report.alerts) { alert in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: regressionIcon(alert.severity))
                                    .foregroundStyle(regressionColor(alert.severity))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.title)
                                    Text(alert.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task {
                                        await model.ignoreRegressionAlert(
                                            alert,
                                            targetPackage: targetPackage
                                        )
                                    }
                                } label: {
                                    Label(
                                        String(localized: "忽略此项"),
                                        systemImage: "speaker.slash"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: "后续对比中忽略同一诊断或指标，可在告警规则中恢复"))
                                .accessibilityHint(String(localized: "后续对比会隐藏同一项，可在告警规则中恢复"))
                            }
                        }
                    }
                    if report.suppressedAlertCount > 0 {
                        Label(
                            String(localized: "已隐藏 \(report.suppressedAlertCount) 项已知告警"),
                            systemImage: "speaker.slash.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                        .padding(.vertical, 2)
                    DisclosureGroup(String(localized: "告警规则与降噪")) {
                        RegressionConfigurationEditor(
                            configuration: configuration
                        )
                        .id(configuration.updatedAt)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private var alignmentSummary: some View {
        if let alignment = model.alignment {
            GroupBox(String(localized: "时间轴对齐")) {
                HStack {
                    LabeledContent(String(localized: "方式"), value: alignment.method.title)
                    Divider()
                    LabeledContent(
                        String(localized: "对比会话偏移"),
                        value: signedSeconds(alignment.comparisonOffset)
                    )
                    Divider()
                    LabeledContent(
                        String(localized: "置信度"),
                        value: alignment.confidence.formatted(.percent.precision(
                            .fractionLength(0)
                        ))
                    )
                }
                Text(String(localized: "锚点：\(alignment.anchor.title)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
                if model.timelineAlignments.count > 1 {
                    Divider()
                        .padding(.vertical, 4)
                    Text(String(localized: "同项目会话（相对当前基准）"))
                        .font(.caption.weight(.semibold))
                    ForEach(
                        model.timelineAlignments,
                        id: \.comparisonSessionID
                    ) { item in
                        HStack {
                            Text(alignmentSessionTitle(item.comparisonSessionID))
                                .lineLimit(1)
                            Spacer()
                            Text(item.method.title)
                                .foregroundStyle(.secondary)
                            Text(signedSeconds(item.comparisonOffset))
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func sessionPicker(
        _ title: String,
        selection: Binding<UUID?>
    ) -> some View {
        Picker(title, selection: selection) {
            Text(String(localized: "未选择")).tag(Optional<UUID>.none)
            ForEach(model.snapshots) { snapshot in
                Text(
                    "\(snapshot.targetPackage) · "
                        + snapshot.sessionCreatedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
                .tag(Optional(snapshot.sessionID))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonDiagnostics(_ comparison: SessionComparison) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DiagnosticDifferenceGroup(
                title: String(localized: "新增"),
                color: .red,
                issues: comparison.addedDiagnostics
            )
            DiagnosticDifferenceGroup(
                title: String(localized: "已消失"),
                color: .green,
                issues: comparison.resolvedDiagnostics
            )
            DiagnosticDifferenceGroup(
                title: String(localized: "持续存在"),
                color: .orange,
                issues: comparison.recurringDiagnostics
            )
        }
    }

    private func changedTags(_ comparison: SessionComparison) -> some View {
        GroupBox(String(localized: "Tag 变化（绝对差值前 20）")) {
            VStack(spacing: 7) {
                ForEach(comparison.changedTags) { tag in
                    HStack {
                        Text(tag.title)
                            .font(.body.monospaced())
                        Spacer()
                        Text("\(tag.baseline) → \(tag.comparison)")
                            .foregroundStyle(.secondary)
                        Text(signed(tag.delta))
                            .foregroundStyle(tag.delta > 0 ? .red : .green)
                            .monospacedDigit()
                    }
                }
            }
            .padding(4)
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func signedSeconds(_ value: TimeInterval) -> String {
        let formatted = abs(value).formatted(
            .number.precision(.fractionLength(3))
        )
        if value == 0 { return String(localized: "0.000 秒") }
        return value > 0 ? String(localized: "+\(formatted) 秒") : String(localized: "-\(formatted) 秒")
    }

    private func regressionIcon(_ severity: RegressionSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    private func regressionColor(_ severity: RegressionSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private func alignmentSessionTitle(_ sessionID: UUID) -> String {
        guard let snapshot = model.snapshots.first(where: {
            $0.sessionID == sessionID
        }) else {
            return sessionID.uuidString
        }
        return snapshot.sessionCreatedAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}

private struct DiagnosticDifferenceGroup: View {
    let title: String
    let color: Color
    let issues: [DiagnosticIssue]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                if issues.isEmpty {
                    Text(String(localized: "无"))
                        .foregroundStyle(.secondary)
                }
                ForEach(issues.prefix(8)) { issue in
                    Text(issue.title)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("\(title) \(issues.count)", systemImage: "circle.fill")
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ArchiveMetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let value = max(0, Int(self.rounded()))
        return String(format: "%02d:%02d:%02d", value / 3_600, (value / 60) % 60, value % 60)
    }
}
