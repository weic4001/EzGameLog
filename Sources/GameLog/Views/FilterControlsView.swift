import SwiftUI

struct FilterControlsView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("advancedFilterExpanded") private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            AdvancedFilterInlineView()
                .environment(model)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Text("高级过滤")
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if model.filterConfiguration.activeAdvancedFilterCount > 0 {
                    Text("\(model.filterConfiguration.activeAdvancedFilterCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                } else {
                    Text("未启用")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct AdvancedFilterInlineView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            filterSectionTitle("日志等级")

            VStack(spacing: 7) {
                filterRow("最低等级") {
                    Picker("最低等级", selection: $model.filterConfiguration.minimumLevel) {
                        Text("不限").tag(nil as LogLevel?)
                        ForEach(
                            LogLevel.allCases.filter { $0 != .unknown },
                            id: \.self
                        ) { level in
                            Text(level.title).tag(level as LogLevel?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                filterRow("包含等级") {
                    Menu {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Toggle(
                                "\(level.rawValue) · \(level.title)",
                                isOn: Binding(
                                    get: { model.filterConfiguration.enabledLevels.contains(level) },
                                    set: { _ in model.toggleLevel(level) }
                                )
                            )
                        }
                    } label: {
                        Text(model.filterConfiguration.enabledLevelSummary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityLabel("包含等级")
                    .accessibilityValue(model.filterConfiguration.enabledLevelSummary)
                }
            }
            .help("日志需同时满足最低等级和包含等级")

            Divider()

            filterSectionTitle("范围与 Tag")

            VStack(spacing: 7) {
                filterRow("进程范围") {
                    Picker("进程范围", selection: $model.filterConfiguration.pidScope) {
                        ForEach(LogPIDScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if model.filterConfiguration.pidScope == .custom {
                    filterRow("指定 PID") {
                        TextField(
                            "例如 1234, 5678",
                            text: Binding(
                                get: { model.filterConfiguration.customPIDs ?? "" },
                                set: { model.filterConfiguration.customPIDs = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("指定 PID")
                    }
                }

                filterRow("包含 Tag") {
                    TextField(
                        "逗号分隔",
                        text: $model.filterConfiguration.includedTags
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("包含 Tag")
                }

                filterRow("排除 Tag") {
                    TextField(
                        "逗号分隔",
                        text: $model.filterConfiguration.excludedTags
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("排除 Tag")
                }
            }

            Divider()

            filterSectionTitle("搜索匹配")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    searchMatchToggles(model: model)
                }

                VStack(alignment: .leading, spacing: 6) {
                    searchMatchToggles(model: model)
                }
            }
            .font(.caption)
            .help("这些选项作用于工具栏的“搜索 Tag 或消息”")

            if let error = model.filterError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if model.filterConfiguration.activeAdvancedFilterCount > 0 {
                HStack {
                    Spacer()
                    Button("重置") {
                        model.preset = .all
                        model.filterConfiguration = LogFilterConfiguration()
                    }
                    .buttonStyle(.borderless)
                    .help("重置所有高级过滤条件")
                }
            }
        }
        .controlSize(.small)
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func filterRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: FilterLayout.spacing) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: FilterLayout.labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func searchMatchToggles(model: AppModel) -> some View {
        @Bindable var model = model

        Group {
            Toggle(
                "区分大小写",
                isOn: $model.filterConfiguration.isCaseSensitive
            )
            Toggle(
                "正则表达式",
                isOn: $model.filterConfiguration.usesRegularExpression
            )
        }
        .toggleStyle(.checkbox)
    }

    private enum FilterLayout {
        static let labelWidth: CGFloat = 56
        static let spacing: CGFloat = 8
    }
}

private extension LogFilterConfiguration {
    var activeAdvancedFilterCount: Int {
        var count = 0
        if enabledLevels != Set(LogLevel.allCases) { count += 1 }
        if minimumLevel != nil { count += 1 }
        if !includedTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !excludedTags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if pidScope != .target { count += 1 }
        if isCaseSensitive { count += 1 }
        if usesRegularExpression { count += 1 }
        return count
    }

    var advancedFilterSummary: String {
        activeAdvancedFilterCount == 0 ? "未启用" : "\(activeAdvancedFilterCount) 项已启用"
    }

    var enabledLevelSummary: String {
        switch enabledLevels.count {
        case LogLevel.allCases.count:
            "全部等级"
        case 0:
            "未选择"
        default:
            "已选 \(enabledLevels.count) 项"
        }
    }
}

struct SavedFiltersView: View {
    @Environment(AppModel.self) private var model
    @State private var newPresetName = ""
    @State private var editingPreset: SavedFilterPreset?
    @State private var renameText = ""
    @State private var pendingDelete: SavedFilterPreset?

    var body: some View {
        ForEach(BuiltInFilterPreset.allCases) { builtInPreset in
            Button {
                model.applyBuiltInFilter(builtInPreset)
            } label: {
                Label(builtInPreset.name, systemImage: builtInPreset.systemImage)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("应用内置 \(builtInPreset.name) 日志预设")
        }

        if !model.savedFilterPresets.isEmpty {
            Divider()
        }

        ForEach(model.savedFilterPresets) { savedPreset in
            HStack(spacing: 4) {
                Button {
                    model.applySavedFilter(savedPreset)
                } label: {
                    Label(savedPreset.name, systemImage: "line.3.horizontal.decrease.circle")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Menu {
                    Button("重命名…") {
                        beginRenaming(savedPreset)
                    }
                    Button("删除", role: .destructive) {
                        pendingDelete = savedPreset
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("管理过滤预设")
            }
            .contextMenu {
                Button("重命名…") {
                    beginRenaming(savedPreset)
                }
                Button("删除", role: .destructive) {
                    pendingDelete = savedPreset
                }
            }
        }

        HStack(spacing: 6) {
            TextField("新预设名称", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button(action: save) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("保存当前过滤条件")
        }
        .alert(
            "重命名过滤预设",
            isPresented: Binding(
                get: { editingPreset != nil },
                set: { if !$0 { editingPreset = nil } }
            )
        ) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {
                editingPreset = nil
            }
            Button("保存") {
                if let editingPreset {
                    model.renameSavedFilter(editingPreset, to: renameText)
                }
                editingPreset = nil
            }
        }
        .alert(
            "删除过滤预设？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    model.deleteSavedFilter(pendingDelete)
                }
                pendingDelete = nil
            }
        } message: {
            Text("该操作不会删除日志或会话数据。")
        }
    }

    private func save() {
        model.saveCurrentFilter(named: newPresetName)
        newPresetName = ""
    }

    private func beginRenaming(_ savedPreset: SavedFilterPreset) {
        renameText = savedPreset.name
        editingPreset = savedPreset
    }
}
