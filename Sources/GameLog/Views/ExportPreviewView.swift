import SwiftUI

struct ExportPreviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let state = model.exportPreview {
                Toggle(
                    "导出时自动脱敏",
                    isOn: Binding(
                        get: { state.configuration.isEnabled },
                        set: { model.setExportRedactionEnabled($0) }
                    )
                )
                .font(.headline)

                VStack(spacing: 0) {
                    ForEach(RedactionCategory.allCases, id: \.self) { category in
                        HStack {
                            Toggle(
                                category.title,
                                isOn: Binding(
                                    get: {
                                        model.exportPreview?.configuration.categories
                                            .contains(category) == true
                                    },
                                    set: { _ in
                                        model.toggleExportRedactionCategory(category)
                                    }
                                )
                            )
                            .disabled(!state.configuration.isEnabled)
                            Spacer()
                            Text("\(state.preview.counts[category, default: 0]) 处")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 7)
                        if category != RedactionCategory.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))

                if !state.configuration.customRules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("项目级规则")
                            .font(.headline)
                        VStack(spacing: 0) {
                            ForEach(state.configuration.customRules) { rule in
                                HStack {
                                    Toggle(
                                        rule.name,
                                        isOn: Binding(
                                            get: {
                                                model.exportPreview?.configuration.customRules
                                                    .first(where: { $0.id == rule.id })?
                                                    .isEnabled == true
                                            },
                                            set: {
                                                model.setExportCustomRuleEnabled(
                                                    rule.id,
                                                    enabled: $0
                                                )
                                            }
                                        )
                                    )
                                    .disabled(!state.configuration.isEnabled)
                                    Spacer()
                                    Text(
                                        "\(state.preview.customRuleCounts[rule.id, default: 0]) 处"
                                    )
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                }
                                .padding(.vertical, 7)
                                if rule.id != state.configuration.customRules.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
                    }
                }

                if let before = state.preview.sampleBefore,
                   let after = state.preview.sampleAfter {
                    DisclosureGroup("查看脱敏示例") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原始")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(before)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("导出后")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(after)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.top, 8)
                    }
                }
            }

            Text("GameLog 只处理本地文件，不会上传日志。自动规则无法识别所有业务敏感信息，分享前仍建议检查导出目录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button("取消", role: .cancel) {
                    model.cancelExportPreview()
                }
                Spacer()
                Button("选择位置并导出…") {
                    Task { await model.confirmExportPreview() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isExporting)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("导出脱敏预览")
                    .font(.title3.weight(.semibold))
                if let state = model.exportPreview {
                    Text(
                        state.preview.totalMatchCount == 0
                            ? "未发现常见敏感信息"
                            : "发现 \(state.preview.totalMatchCount) 处可能的敏感信息"
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
