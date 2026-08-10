import SwiftUI

struct SessionSceneView: View {
    let registry: SessionRegistry
    @State private var model: AppModel
    @State private var windowID = UUID()

    init(registry: SessionRegistry, sessionStore: SessionStore) {
        self.registry = registry
        _model = State(initialValue: AppModel(sessionStore: sessionStore))
    }

    var body: some View {
        RootView()
            .environment(model)
            .focusedSceneValue(\.gameLogModel, model)
            .onAppear {
                registry.register(model, id: windowID)
            }
            .onDisappear {
                let closingID = windowID
                Task {
                    await registry.closeWindow(id: closingID)
                }
            }
    }
}
