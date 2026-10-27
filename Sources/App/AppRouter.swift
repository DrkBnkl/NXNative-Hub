import SwiftUI
import AppKit

// MARK: - Navigation and presentation state
//
// Shared by views AND menu commands.

final class AppRouter: ObservableObject {
    @Published var selection: SidebarItem? = .library
    @Published var selectedGameID: InstalledGame.ID?

    @Published var showingGameSettings = false
    @Published var showingUpdateSheet = false
    @Published var showingLiveLog = false
    @Published var showingImportSheet = false
    @Published var showingSetup = false
}

// MARK: - Game actions (used by views and menu commands)

enum GameActions {
    static func launch(_ game: InstalledGame) {
        launch(appPath: game.path)
    }

    static func launch(appPath: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
    }

    /// Opens the game settings. Does nothing (system beep) if the Info.plist has no title ID.
    @discardableResult
    static func openSettings(appPath: String, settings: GameSettingsModel, router: AppRouter) -> Bool {
        guard let info = GameBundleInfo(appPath: appPath) else {
            NSSound.beep()
            return false
        }
        settings.load(titleId: info.titleId, gameName: info.name, appPath: appPath)
        router.showingGameSettings = true
        return true
    }
}
