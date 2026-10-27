import SwiftUI

// MARK: - App entry point
//
//  - `Window` instead of `WindowGroup`: the app manages exactly one build/import state,
//    so additional windows with independent managers must not exist.
//  - All state objects are created once here and distributed via the environment.
//  - `Settings` scene for the standard settings window (⌘,).

@main
struct NXNativeHubApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var prefs = AppPreferences.shared
    @StateObject private var library = GameLibraryManager()
    @StateObject private var buildManager = BuildManager()
    @StateObject private var builderForm = BuilderFormModel()
    @StateObject private var updater = UpdateManager()
    @StateObject private var gameSettings = GameSettingsModel()
    @StateObject private var buildMonitor = ActiveBuildMonitor()
    @StateObject private var importManager = ImportBatchManager()
    @StateObject private var setupChecker = SetupChecker()

    var body: some Scene {
        Window("NXNative Hub", id: "main") {
            ContentView()
                .environmentObject(router)
                .environmentObject(prefs)
                .environmentObject(library)
                .environmentObject(buildManager)
                .environmentObject(builderForm)
                .environmentObject(updater)
                .environmentObject(gameSettings)
                .environmentObject(buildMonitor)
                .environmentObject(importManager)
                .environmentObject(setupChecker)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            AppCommands(router: router,
                        library: library,
                        builderForm: builderForm,
                        buildManager: buildManager,
                        buildMonitor: buildMonitor,
                        prefs: prefs,
                        updater: updater,
                        gameSettings: gameSettings,
                        importManager: importManager)
        }

        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environmentObject(library)
                .environmentObject(updater)
                .environmentObject(importManager)
                .environmentObject(setupChecker)
        }
    }
}
