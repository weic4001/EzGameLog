import Foundation
import Observation

@MainActor
@Observable
final class SessionRegistry {
    private(set) var models: [UUID: AppModel] = [:]

    var requiresTerminationPreparation: Bool {
        models.values.contains(where: \.requiresTerminationPreparation)
    }

    var hasActiveSessions: Bool {
        models.values.contains { $0.sessionState.isActive }
    }

    func register(_ model: AppModel, id: UUID) {
        models[id] = model
    }

    func closeWindow(id: UUID) async {
        guard let model = models[id] else { return }
        await model.prepareForTermination()
        models[id] = nil
    }

    func prepareForTermination() async {
        for model in models.values {
            await model.prepareForTermination()
        }
    }
}
