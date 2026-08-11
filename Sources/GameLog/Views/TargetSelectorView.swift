import SwiftUI

struct TargetSelectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                TextField(String(localized: "输入包名"), text: $model.packageInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(selectInput)
                    .disabled(model.sessionState.isActive)
                Button(action: selectInput) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .disabled(model.packageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .disabled(model.sessionState.isActive)
            }

            if let package = model.selectedPackageName {
                Label(package, systemImage: model.selectedProcessID == nil ? "hourglass" : "scope")
                    .font(.caption)
                    .foregroundStyle(model.selectedProcessID == nil ? .orange : .secondary)
                    .lineLimit(1)
            }

            ForEach(model.recentPackages.prefix(4), id: \.self) { package in
                Button {
                    Task { await model.selectPackageName(package) }
                } label: {
                    Label(package, systemImage: "clock")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(model.sessionState.isActive)
            }
        }
    }

    private func selectInput() {
        Task { await model.selectPackageName(model.packageInput) }
    }
}
