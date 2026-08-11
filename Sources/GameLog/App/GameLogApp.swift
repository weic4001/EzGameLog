import AppKit
import SwiftUI

@main
@MainActor
struct GameLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let sessionStore: SessionStore
    @State private var sessionRegistry = SessionRegistry()
    @State private var settingsModel: AppModel
    @State private var archiveModel: ArchiveModel
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue

    init() {
        let configuredRoot = UserDefaults.standard.string(forKey: "sessionRootDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let store = SessionStore(rootDirectory: configuredRoot)
        let symbolStore = SymbolCatalogStore()
        sessionStore = store
        _settingsModel = State(initialValue: AppModel(sessionStore: store))
        _archiveModel = State(initialValue: ArchiveModel(
            store: store,
            symbolStore: symbolStore
        ))
    }

    var body: some Scene {
        WindowGroup("GameLog", id: "session") {
            SessionSceneView(
                registry: sessionRegistry,
                sessionStore: sessionStore
            )
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .frame(minWidth: 1_100, minHeight: 700)
                .onAppear {
                    appDelegate.registry = sessionRegistry
                }
        }
        .defaultSize(width: 1_440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            GameLogCommands(archiveModel: archiveModel)
        }

        Window(String(localized: "会话归档"), id: "archive") {
            SessionArchiveView()
                .environment(archiveModel)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1_180, height: 780)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(settingsModel)
                .environment(sessionRegistry)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .frame(width: 680, height: 520)
                .task {
                    await settingsModel.bootstrap()
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var registry: SessionRegistry?
    private var isPreparingToTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let registry, registry.requiresTerminationPreparation else {
            return .terminateNow
        }
        guard !isPreparingToTerminate else {
            return .terminateLater
        }
        isPreparingToTerminate = true
        Task {
            await registry.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
