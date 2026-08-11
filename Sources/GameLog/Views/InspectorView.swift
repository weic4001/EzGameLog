import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var isRawExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.diagnosticIssues.isEmpty {
                    diagnosticSection
                    Divider()
                }
                selectedLogSection
                Divider()
                evidenceSection
                if !model.recoverableRecordings.isEmpty {
                    Divider()
                    recoverableRecordingSection
                }
            }
            .padding(16)
        }
    }

    private var diagnosticSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "自动诊断"))
                    .font(.headline)
                Spacer()
                Text("\(model.diagnosticIssues.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(model.diagnosticIssues.prefix(6)) { issue in
                Button {
                    model.selectDiagnosticIssue(issue)
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: issue.kind.systemImage)
                            .foregroundStyle(issue.kind == .anr ? .orange : .red)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text(issue.kind.title)
                                if issue.occurrenceCount > 1 {
                                    Text(String(localized: "重复 \(issue.occurrenceCount) 次"))
                                }
                                Text(issue.lastOccurredAt, style: .time)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recoverableRecordingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "待恢复录屏"), systemImage: "externaldrive.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(model.recoverableRecordings) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.remotePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text(item.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "连接原设备并尝试恢复")) {
                        Task { await model.recoverRecording(item) }
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var selectedLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "日志详情"))
                .font(.headline)

            if let event = model.selectedEvent {
                if model.selectedEventIDs.count > 1 {
                    Label(String(localized: "已选择 \(model.selectedEventIDs.count) 条；下方显示第一条"), systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button {
                        model.toggleBookmark(for: event.id)
                    } label: {
                        Label(
                            model.bookmarkedEventIDs.contains(event.id) ? String(localized: "取消书签") : String(localized: "添加书签"),
                            systemImage: model.bookmarkedEventIDs.contains(event.id) ? "bookmark.fill" : "bookmark"
                        )
                    }
                }
                if let incident = model.selectedIncident {
                    IncidentEditorCard(incident: incident)
                        .id(incident.id)
                }
                if let issue = model.selectedDiagnosticIssue {
                    Label(
                        String(localized: "\(issue.kind.title) · \(issue.occurrenceCount) 次"),
                        systemImage: issue.kind.systemImage
                    )
                    .font(.caption)
                    .foregroundStyle(issue.kind == .anr ? .orange : .red)
                }
                LabeledContent(String(localized: "级别")) {
                    Text("\(event.level.rawValue) · \(event.level.title)")
                        .foregroundStyle(color(for: event.level))
                }
                LabeledContent(String(localized: "时间")) {
                    Text(event.occurredAt.formatted(
                        .dateTime.year().month().day().hour().minute().second()
                    ))
                    .textSelection(.enabled)
                }
                if let receivedAt = event.receivedAtHostTime {
                    LabeledContent(String(localized: "主机接收"), value: receivedAt.formatted(
                        .dateTime.hour().minute().second()
                    ))
                }
                LabeledContent("PID / TID", value: "\(event.pid.map(String.init) ?? "—") / \(event.tid.map(String.init) ?? "—")")
                LabeledContent("Tag", value: event.tag)
                LabeledContent("Buffer", value: event.buffer.rawValue)
                LabeledContent(String(localized: "类型"), value: event.kind.rawValue)

                Text(event.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

                DisclosureGroup("Raw Text", isExpanded: $isRawExpanded) {
                    Text(event.rawText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            } else {
                Text(String(localized: "选择一条日志后在这里查看完整内容。"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "设备证据"))
                    .font(.headline)
                Spacer()
                if !model.evidence.isEmpty {
                    Button(String(localized: "显示全部")) {
                        model.revealOutputDirectory()
                    }
                    .buttonStyle(.link)
                }
            }

            if model.evidence.isEmpty {
                Text(String(localized: "开始会话后使用工具栏的截图或录屏按钮，证据会保存到当前会话目录。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relatedEvidence.prefix(6)) { item in
                    EvidenceCard(item: item)
                }
            }
        }
    }

    private var relatedEvidence: [CaptureEvidence] {
        guard let selected = model.selectedEvent else { return model.evidence }
        return model.evidence.sorted {
            abs($0.createdAt.timeIntervalSince(selected.occurredAt))
                < abs($1.createdAt.timeIntervalSince(selected.occurredAt))
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .warning: .orange
        case .error, .fatal: .red
        case .info: .blue
        case .debug: .secondary
        case .verbose, .unknown: .secondary
        }
    }
}

private struct IncidentEditorCard: View {
    @Environment(AppModel.self) private var model
    let incident: IncidentRecord
    @State private var title: String
    @State private var note: String

    init(incident: IncidentRecord) {
        self.incident = incident
        _title = State(initialValue: incident.title)
        _note = State(initialValue: incident.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(String(localized: "问题标记"), systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            TextField(String(localized: "问题名称"), text: $title)
            TextField(String(localized: "复现步骤或补充说明"), text: $note, axis: .vertical)
                .lineLimit(2...5)
            HStack {
                if let offset = incident.recordingOffset {
                    Label(
                        String(localized: "录屏 \(offset.formatted(.number.precision(.fractionLength(1)))) 秒"),
                        systemImage: "record.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "保存")) {
                    Task {
                        await model.updateIncident(
                            id: incident.id,
                            title: title,
                            note: note
                        )
                    }
                }
                Button(String(localized: "导出问题包…")) {
                    Task { await model.exportIncidentPackage(incident) }
                }
                .disabled(model.isRecording || model.isExporting)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: .rect(cornerRadius: 9))
    }
}

private struct EvidenceCard: View {
    @Environment(AppModel.self) private var model
    let item: CaptureEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if item.kind == .screenshot,
                   let image = NSImage(contentsOf: item.thumbnailURL ?? item.fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else if item.kind == .recording {
                    RecordingPlayerView(url: item.fileURL)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(.black.opacity(0.85), in: .rect(cornerRadius: 8))
            .clipShape(.rect(cornerRadius: 8))

            HStack {
                Label(item.kind.title, systemImage: item.kind == .screenshot ? "camera" : "record.circle")
                Spacer()
                if let duration = item.duration {
                    Text(duration.formatted(.number.precision(.fractionLength(1))) + String(localized: " 秒"))
                }
                Text(item.createdAt, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let width = item.pixelWidth, let height = item.pixelHeight {
                    Text("\(width) × \(height)")
                }
                if let byteCount = item.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                }
                Text(item.deviceSerial)
                if item.kind == .recording {
                    Text(String(localized: "无音频"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            ViewThatFits(in: .horizontal) {
                evidenceActions(compact: false)
                evidenceActions(compact: true)
                VStack(alignment: .leading, spacing: 6) {
                    primaryEvidenceActions(compact: true)
                    secondaryEvidenceActions(compact: true)
                }
            }
        }
        .contextMenu {
            Button(String(localized: "在 Finder 中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
        }
    }

    private func evidenceActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            primaryEvidenceActions(compact: compact)
            Spacer(minLength: 12)
            secondaryEvidenceActions(compact: compact)
        }
    }

    private func primaryEvidenceActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            Button(compact ? String(localized: "预览") : String(localized: "快速查看")) {
                QuickLookPresenter.shared.present(item.fileURL)
            }
            .help(String(localized: "使用系统快速查看预览文件"))

            if item.kind == .recording {
                Button(compact ? String(localized: "开始") : String(localized: "跳到录屏开始")) {
                    model.selectEvent(near: item.createdAt)
                }
                .help(String(localized: "在日志中选择最接近录屏开始的位置"))

                if let duration = item.duration {
                    Button(compact ? String(localized: "结束") : String(localized: "跳到录屏结束")) {
                        model.selectEvent(
                            near: item.createdAt.addingTimeInterval(duration)
                        )
                    }
                    .help(String(localized: "在日志中选择最接近录屏结束的位置"))
                }
            }
        }
        .buttonStyle(.link)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func secondaryEvidenceActions(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            Button(compact ? String(localized: "导出") : String(localized: "导出…")) {
                Task { await model.exportEvidence(item) }
            }
            .help(String(localized: "导出这个证据文件"))

            Button(compact ? "Finder" : String(localized: "在 Finder 中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
            .help(String(localized: "在 Finder 中显示这个文件"))
        }
        .buttonStyle(.link)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
