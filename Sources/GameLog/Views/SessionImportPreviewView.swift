import SwiftUI

struct SessionImportPreviewView: View {
    @Environment(ArchiveModel.self) private var model
    let preview: SessionImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("导入预检", systemImage: "checkmark.shield")
                    .font(.headline)
                Text(preview.disposition.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dispositionColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        dispositionColor.opacity(0.12),
                        in: .capsule
                    )
                Spacer()
                Button("取消") {
                    model.cancelPendingImport()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    Task { await model.confirmPendingImport() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isImporting)
            }

            LazyVGrid(columns: previewColumns, alignment: .leading, spacing: 8) {
                ImportPreviewFact(
                    title: "目标包",
                    value: preview.targetPackage
                )
                ImportPreviewFact(
                    title: "设备",
                    value: "\(preview.deviceDisplayName) · \(preview.deviceSerial)"
                )
                ImportPreviewFact(
                    title: "日志",
                    value: "\(preview.eventCount) 条"
                )
                ImportPreviewFact(
                    title: "证据",
                    value: "\(preview.screenshotCount) 截图 · \(preview.recordingCount) 录屏"
                )
                ImportPreviewFact(
                    title: "大小",
                    value: ByteCountFormatter.string(
                        fromByteCount: preview.totalByteCount,
                        countStyle: .file
                    )
                )
                ImportPreviewFact(
                    title: "完整性",
                    value: preview.integrityStatus.title,
                    systemImage: integrityIcon,
                    tint: integrityColor
                )
            }

            if preview.disposition == .mergeAnnotation {
                Text(mergeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if preview.integrityStatus == .legacyUnverified {
                Text("此旧格式会话通过了结构和内容校验，但没有 SHA-256 协作清单；请确认来源可信。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var previewColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 0),
                spacing: 8,
                alignment: .topLeading
            ),
            count: 3
        )
    }

    private var confirmTitle: String {
        preview.disposition == .newSession ? "确认导入" : "合并注释"
    }

    private var mergeDescription: String {
        let title = preview.importedTitle.isEmpty
            ? "无标题"
            : "标题“\(preview.importedTitle)”"
        let labels = preview.importedLabels.isEmpty
            ? "无新增标签"
            : "\(preview.importedLabels.count) 个导入标签"
        return "本地日志和证据不会被替换；将按更新时间合并\(title)及\(labels)。"
    }

    private var dispositionColor: Color {
        preview.disposition == .newSession ? .blue : .orange
    }

    private var integrityIcon: String {
        preview.integrityStatus == .verified
            ? "checkmark.seal.fill"
            : "exclamationmark.triangle.fill"
    }

    private var integrityColor: Color {
        preview.integrityStatus == .verified ? .green : .orange
    }
}

private struct ImportPreviewFact: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let systemImage {
                Label(value, systemImage: systemImage)
                    .foregroundStyle(tint)
            } else {
                Text(value)
            }
        }
        .font(.caption)
        .lineLimit(1)
        .help(value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}
