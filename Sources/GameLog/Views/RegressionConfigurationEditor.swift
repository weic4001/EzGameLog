import SwiftUI

struct RegressionConfigurationEditor: View {
    @Environment(ArchiveModel.self) private var model
    let configuration: RegressionConfiguration
    @State private var thresholds: RegressionThresholds

    init(configuration: RegressionConfiguration) {
        self.configuration = configuration
        _thresholds = State(initialValue: configuration.thresholds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("阈值同时满足“绝对增量”和“相对增量”中的较高者时才告警。新增 Crash / ANR 仍会直接标为严重。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                headerRow
                thresholdRow(
                    "错误 / Fatal",
                    absolute: $thresholds.errorAbsoluteIncrease,
                    relative: $thresholds.errorRelativeIncrease
                )
                thresholdRow(
                    "单个 Tag",
                    absolute: $thresholds.tagAbsoluteIncrease,
                    relative: $thresholds.tagRelativeIncrease
                )
                thresholdRow(
                    "整体日志",
                    absolute: $thresholds.logAbsoluteIncrease,
                    relative: $thresholds.logRelativeIncrease
                )
                GridRow {
                    Text("重复诊断")
                    TextField(
                        "次数",
                        value: $thresholds.recurringDiagnosticIncrease,
                        format: .number
                    )
                    .frame(width: 80)
                    .accessibilityLabel("重复诊断绝对增量")
                    Text("新增出现次数")
                        .foregroundStyle(.secondary)
                    Text("基线最少日志")
                    TextField(
                        "条数",
                        value: $thresholds.logMinimumBaseline,
                        format: .number
                    )
                    .frame(width: 80)
                    .accessibilityLabel("告警所需的基线最少日志条数")
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                if !configuration.ignoredAlertKeys.isEmpty {
                    Button(
                        "恢复已忽略项（\(configuration.ignoredAlertKeys.count)）"
                    ) {
                        Task {
                            await model.restoreIgnoredRegressionAlerts(
                                targetPackage: configuration.targetPackage
                            )
                        }
                    }
                }
                Spacer()
                Button("恢复推荐阈值") {
                    thresholds = .recommended
                }
                Button("保存规则") {
                    Task {
                        await model.saveRegressionThresholds(
                            thresholds,
                            targetPackage: configuration.targetPackage
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.caption)
    }

    private var headerRow: some View {
        GridRow {
            Text("指标")
            Text("绝对增量")
            Text("相对增量")
            Text("")
            Text("")
        }
        .foregroundStyle(.secondary)
    }

    private func thresholdRow(
        _ title: String,
        absolute: Binding<Int>,
        relative: Binding<Double>
    ) -> some View {
        GridRow {
            Text(title)
            TextField("条数", value: absolute, format: .number)
                .frame(width: 80)
                .accessibilityLabel("\(title)绝对增量")
            TextField(
                "比例",
                value: relative,
                format: .percent.precision(.fractionLength(0))
            )
            .frame(width: 80)
            .accessibilityLabel("\(title)相对增量")
            Text("")
            Text("")
        }
    }
}
