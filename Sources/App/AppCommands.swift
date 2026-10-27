import SwiftUI

// MARK: - Menu bar
//
// "Check for Updates…" lives in the app menu, as is customary on macOS.
// ⌘, is left to the standard Settings window (HIG).

struct AppCommands: Commands {
    @ObservedObject var router: AppRouter
    @ObservedObject var library: GameLibraryManager
    @ObservedObject var builderForm: BuilderFormModel
    @ObservedObject var buildManager: BuildManager
    @ObservedObject var buildMonitor: ActiveBuildMonitor
    @ObservedObject var prefs: AppPreferences
    let updater: UpdateManager
    let gameSettings: GameSettingsModel
    let importManager: ImportBatchManager
    /// Rebuilds menu titles when the UI language changes.
    @ObservedObject var lang = LanguageManager.shared

    private var selectedGame: InstalledGame? {
        library.games.first { $0.id == router.selectedGameID }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .appInfo) {
            Button(tr("Nach Updates suchen …", "Check for Updates…")) {
                router.showingUpdateSheet = true
                updater.checkForUpdates()
            }
        }

        SidebarCommands()

        CommandGroup(after: .help) {
            Button(tr("Einrichtung prüfen …", "Check Setup…")) {
                router.showingSetup = true
            }
        }

        CommandGroup(before: .sidebar) {
            Button(SidebarItem.library.title) { router.selection = .library }
                .keyboardShortcut("1", modifiers: .command)
            Button(SidebarItem.builder.title) { router.selection = .builder }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
        }

        CommandMenu(LocalizedStringKey(tr("Spiel", "Game"))) {
            Button(tr("Spielen", "Play")) {
                if let game = selectedGame { GameActions.launch(game) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(selectedGame == nil)

            Button(tr("Spiel-Einstellungen …", "Game Settings…")) {
                if let game = selectedGame {
                    GameActions.openSettings(appPath: game.path, settings: gameSettings, router: router)
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(selectedGame == nil)

            Divider()

            Button(tr("Spiel bauen", "Build Game")) {
                router.selection = .builder
                builderForm.startBuild(manager: buildManager, monitor: buildMonitor, prefs: prefs, library: library)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!builderForm.canStart(manager: buildManager, monitor: buildMonitor, prefs: prefs))

            Button(tr("Spiele-Import öffnen …", "Open Game Import…")) {
                importManager.scanImportFolder()
                router.showingImportSheet = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button(tr("Bibliothek neu laden", "Reload Library")) {
                library.refreshLibrary()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(tr("Live-Protokoll", "Live Log")) {
                router.showingLiveLog = true
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(buildMonitor.activeBuild == nil)
        }
    }
}
