import SwiftUI
import AppKit

// MARK: - App delegate (quit guard while a build is running)

final class NXNativeAppDelegate: NSObject, NSApplicationDelegate {
    weak var buildManager: BuildManager?
    weak var importManager: ImportBatchManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isBuilding = (buildManager?.isRunning == true) || (importManager?.isConverting == true)
        guard isBuilding else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tr("Build läuft noch – trotzdem beenden?",
                               "Build Still Running – Quit Anyway?")
        alert.informativeText = tr(
            "Wenn du NXNative Hub jetzt beendest, wird der laufende Build abgebrochen und die App nicht fertig verpackt. Bereits kompilierte Shader bleiben im Cache erhalten.",
            "Quitting NXNative Hub now will cancel the running build before the app is packaged. Already compiled shaders will remain in the cache."
        )
        alert.addButton(withTitle: tr("Weiterlaufen lassen", "Keep Running"))
        let quitButton = alert.addButton(withTitle: tr("Build abbrechen & beenden", "Cancel Build & Quit"))
        quitButton.hasDestructiveAction = true

        if alert.runModal() == .alertSecondButtonReturn {
            if buildManager?.isRunning == true { buildManager?.cancel() }
            if importManager?.isConverting == true { importManager?.cancelBatch() }
            return .terminateNow
        }
        return .terminateCancel
    }
}

// MARK: - App entry point
//
//  - `Window` instead of `WindowGroup`: the app manages exactly one build/import state,
//    so additional windows with independent managers must not exist.
//  - All state objects are created once here and distributed via the environment.
//  - `Settings` scene for the standard settings window (⌘,).

@main
struct NXNativeHubApp: App {
    @NSApplicationDelegateAdaptor(NXNativeAppDelegate.self) private var appDelegate
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
    @StateObject private var gamepad = GamepadManager.shared

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
                .environmentObject(gamepad)
                .onAppear {
                    appDelegate.buildManager = buildManager
                    appDelegate.importManager = importManager
                }
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
                .environmentObject(gamepad)
                .onAppear {
                    appDelegate.buildManager = buildManager
                    appDelegate.importManager = importManager
                }
        }
    }
}
