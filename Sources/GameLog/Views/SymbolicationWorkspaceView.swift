import SwiftUI

struct SymbolicationWorkspaceView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var resultFilter = SymbolicationResultFilter.all

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("NDK Native 符号化")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Picker("目标包", selection: $model.symbolPackage) {
                        ForEach(model.availablePackages, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .frame(width: 300)
                }

                symbolizerConfiguration
                symbolRoots
                sessionSymbolication
            }
            .padding(20)
        }
    }

    private var symbolizerConfiguration: some View {
        GroupBox("llvm-symbolizer") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        model.resolvedSymbolizerPath.isEmpty
                            ? "尚未找到 Android NDK llvm-symbolizer"
                            : model.resolvedSymbolizerPath
                    )
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    Text("优先自动读取 ANDROID_NDK_HOME / ANDROID_HOME，也可手动选择。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("选择工具…") {
                    Task { await model.chooseSymbolizerExecutable() }
                }
            }
            .padding(4)
        }
    }

    private var symbolRoots: some View {
        GroupBox("符号目录") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(model.visibleSymbolFileCount) 个 ELF 库已建立索引")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isIndexingSymbols {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("添加目录…") {
                        Task { await model.chooseAndIndexSymbols() }
                    }
                    .disabled(
                        model.symbolPackage.isEmpty
                            || model.isIndexingSymbols
                    )
                }
                if model.visibleSymbolRoots.isEmpty {
                    Text("尚未为该目标添加符号目录。选择包含未剥离 .so 的目录即可递归索引 ABI 和 GNU Build ID。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.visibleSymbolRoots) { root in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(root.path)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer()
                        Button("移除索引", role: .destructive) {
                            Task { await model.removeSymbolRoot(root.id) }
                        }
                        .help("只移除 GameLog 索引，不删除源符号文件")
                    }
                }
            }
            .padding(4)
        }
    }

    private var sessionSymbolication: some View {
        GroupBox("会话符号化") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sessionPicker
                    if model.isSymbolicating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("符号化所选会话") {
                        Task { await model.symbolicateSelectedSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.selectedSnapshot == nil
                            || model.isSymbolicating
                    )
                }
                if let report = model.selectedSymbolicationReport {
                    symbolicationSummary(report)
                    symbolicationIssues(report)
                    HStack {
                        Picker("结果", selection: $resultFilter) {
                            ForEach(SymbolicationResultFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        Spacer()
                        Button("复制完整结果") {
                            model.copySelectedSymbolicationReport()
                        }
                        Button("导出文本…") {
                            model.exportSelectedSymbolicationReport()
                        }
                    }
                    let visibleFrames = report.frames.filter {
                        resultFilter.includes($0.status)
                    }
                    if visibleFrames.isEmpty {
                        Text("当前筛选下没有 Native 帧。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(visibleFrames.prefix(200)) { frame in
                            SymbolicatedFrameRow(value: frame)
                        }
                    }
                } else {
                    Text("选择包含 Native Crash 的会话并执行符号化，结果会保存到会话目录的 symbolication.json。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private func symbolicationSummary(
        _ report: SessionSymbolicationReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(
                    "覆盖率 "
                        + report.coverageRatio.formatted(
                            .percent.precision(.fractionLength(1))
                        )
                )
                .font(.headline)
                Spacer()
                Text(
                    report.generatedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            ProgressView(value: report.coverageRatio)
                .tint(report.coverageRatio >= 0.8 ? .green : .orange)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 5
                ),
                spacing: 8
            ) {
                resultMetric(
                    "已解析",
                    value: report.count(for: .symbolicated),
                    color: .green
                )
                resultMetric(
                    "日志已有",
                    value: report.count(for: .alreadySymbolicated),
                    color: .mint
                )
                resultMetric(
                    "缺少符号",
                    value: report.count(for: .missingSymbolFile),
                    color: .orange
                )
                resultMetric(
                    "未解析",
                    value: report.count(for: .unresolved),
                    color: .orange
                )
                resultMetric(
                    "失败",
                    value: report.count(for: .failed),
                    color: .red
                )
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func symbolicationIssues(
        _ report: SessionSymbolicationReport
    ) -> some View {
        let missing = report.count(for: .missingSymbolFile)
        let unresolved = report.count(for: .unresolved)
        let failed = report.count(for: .failed)
        if missing + unresolved + failed > 0 {
            GroupBox("未解析原因与处理建议") {
                VStack(alignment: .leading, spacing: 7) {
                    if !report.missingLibraryNames.isEmpty {
                        Label(
                            "缺少或无法唯一匹配："
                                + report.missingLibraryNames.joined(separator: "、"),
                            systemImage: "questionmark.folder"
                        )
                        Text("添加包含对应 ABI 未剥离 .so 的目录；同名库较多时需保留 Build ID。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if unresolved > 0 {
                        Label(
                            "\(unresolved) 帧被 llvm-symbolizer 接收，但没有返回函数或源码位置。",
                            systemImage: "questionmark.circle"
                        )
                    }
                    if failed > 0 {
                        Label(
                            "\(failed) 帧执行失败；在下方帧详情查看超时、权限或工具错误。",
                            systemImage: "xmark.circle"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }
    }

    private func resultMetric(
        _ title: String,
        value: Int,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionPicker: some View {
        @Bindable var model = model
        return Picker("会话", selection: $model.selectedSessionID) {
            Text("未选择").tag(Optional<UUID>.none)
            ForEach(model.entries.filter {
                model.symbolPackage.isEmpty
                    || $0.session.targetPackage == model.symbolPackage
            }) { entry in
                Text(
                    "\(entry.session.targetPackage) · "
                        + entry.session.createdAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                )
                .tag(Optional(entry.id))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SymbolicatedFrameRow: View {
    let value: SymbolicatedNativeFrame

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    "#\(value.frame.frameIndex) \(value.frame.libraryName) + 0x\(value.frame.address)"
                )
                .font(.caption.monospaced())
                if let function = value.bestFunction {
                    ForEach(
                        Array(value.sourceFrames.prefix(4).enumerated()),
                        id: \.offset
                    ) { index, source in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(index == 0 ? function : "↳ \(source.function)")
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            if let file = source.file {
                                Text(
                                    source.line.map { "\(file):\($0)" } ?? file
                                )
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                if let path = value.symbolFilePath {
                    Text("符号文件：\(path)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(path)
                }
                if let error = value.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(
                            value.status == .failed ? .red : .secondary
                        )
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Text(value.status.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch value.status {
        case .symbolicated, .alreadySymbolicated: "checkmark.circle.fill"
        case .missingSymbolFile: "questionmark.folder"
        case .unresolved: "questionmark.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch value.status {
        case .symbolicated, .alreadySymbolicated: .green
        case .missingSymbolFile, .unresolved: .orange
        case .failed: .red
        }
    }
}

private enum SymbolicationResultFilter: String, CaseIterable, Identifiable {
    case all
    case symbolicated
    case alreadySymbolicated
    case missingSymbolFile
    case unresolved
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .symbolicated: "已解析"
        case .alreadySymbolicated: "日志已有"
        case .missingSymbolFile: "缺少符号"
        case .unresolved: "未解析"
        case .failed: "失败"
        }
    }

    func includes(_ status: SymbolicationFrameStatus) -> Bool {
        switch self {
        case .all: true
        case .symbolicated: status == .symbolicated
        case .alreadySymbolicated: status == .alreadySymbolicated
        case .missingSymbolFile: status == .missingSymbolFile
        case .unresolved: status == .unresolved
        case .failed: status == .failed
        }
    }
}
