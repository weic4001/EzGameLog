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
            Text(String(localized: "阈值同时满足“绝对增量”和“相对增量”中的较高者时才告警。新增 Crash / ANR 仍会直接标为严重。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                headerRow
                thresholdRow(
                    String(localized: "错误 / Fatal"),
                    absolute: $thresholds.errorAbsoluteIncrease,
                    relative: $thresholds.errorRelativeIncrease
                )
                thresholdRow(
                    String(localized: "单个 Tag"),
                    absolute: $thresholds.tagAbsoluteIncrease,
                    relative: $thresholds.tagRelativeIncrease
                )
                thresholdRow(
                    String(localized: "整体日志"),
                    absolute: $thresholds.logAbsoluteIncrease,
                    relative: $thresholds.logRelativeIncrease
                )
                GridRow {
                    Text(String(localized: "重复诊断"))
                    TextField(
                        String(localized: "次数"),
                        value: $thresholds.recurringDiagnosticIncrease,
                        format: .number
                    )
                    .frame(width: 80)
                    .accessibilityLabel(String(localized: "重复诊断绝对增量"))
                    Text(String(localized: "新增出现次数"))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "基线最少日志"))
                    TextField(
                        String(localized: "条数"),
                        value: $thresholds.logMinimumBaseline,
                        format: .number
                    )
                    .frame(width: 80)
                    .accessibilityLabel(String(localized: "告警所需的基线最少日志条数"))
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                if !configuration.ignoredAlertKeys.isEmpty {
                    Button(
                        String(localized: "恢复已忽略项（\(configuration.ignoredAlertKeys.count)）")
                    ) {
                        Task {
                            await model.restoreIgnoredRegressionAlerts(
                                targetPackage: configuration.targetPackage
                            )
                        }
                    }
                }
                Spacer()
                Button(String(localized: "恢复推荐阈值")) {
                    thresholds = .recommended
                }
                Button(String(localized: "保存规则")) {
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
            Text(String(localized: "指标"))
            Text(String(localized: "绝对增量"))
            Text(String(localized: "相对增量"))
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
            TextField(String(localized: "条数"), value: absolute, format: .number)
                .frame(width: 80)
                .accessibilityLabel(String(localized: "\(title)绝对增量"))
            TextField(
                String(localized: "比例"),
                value: relative,
                format: .percent.precision(.fractionLength(0))
            )
            .frame(width: 80)
            .accessibilityLabel(String(localized: "\(title)相对增量"))
            Text("")
            Text("")
        }
    }
}
