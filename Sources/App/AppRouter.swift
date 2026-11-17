import SwiftUI
import AppKit

// MARK: - Navigation and presentation state
//
// Shared by views AND menu commands.

final class AppRouter: ObservableObject {
    @Published var selection: SidebarItem? = .library
    @Published var selectedGameID: InstalledGame.ID?
    @Published var isGamepadSelected = false

    @Published var showingGameSettings = false
    @Published var showingUpdateSheet = false
    @Published var showingLiveLog = false
    @Published var showingImportSheet = false
    @Published var showingSetup = false
    @Published var statusTargetGame: InstalledGame? = nil

    var hasActiveSheet: Bool {
        showingGameSettings ||
        showingUpdateSheet ||
        showingLiveLog ||
        showingImportSheet ||
        showingSetup ||
        statusTargetGame != nil
    }

    func dismissTopSheet() {
        if showingGameSettings {
            showingGameSettings = false
        } else if statusTargetGame != nil {
            statusTargetGame = nil
        } else if showingUpdateSheet {
            showingUpdateSheet = false
        } else if showingLiveLog {
            showingLiveLog = false
        } else if showingImportSheet {
            showingImportSheet = false
        } else if showingSetup {
            showingSetup = false
        }
    }
}

// MARK: - Game actions (used by views and menu commands)

enum GameActions {
    static func launch(_ game: InstalledGame, forceFullscreen: Bool = false) {
        launch(appPath: game.path, titleId: game.titleId, forceFullscreen: forceFullscreen)
    }

    static func launch(appPath: String, titleId: String? = nil, forceFullscreen: Bool = false) {
        let tid = titleId ?? GameBundleInfo(appPath: appPath)?.titleId
        var skipLauncher = AppPreferences.shared.skipGameLauncher
        if let tid = tid {
            let envValues = EnvFile.load(path: NXPaths.envFilePath(titleId: tid))?.values
            if let val = envValues?["DM_LAUNCHER"] {
                skipLauncher = (val == "0")
            }
        }

        let url = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        var env: [String: String] = [:]
        var args: [String] = []

        if skipLauncher {
            args.append("--no-launcher")
            env["DM_LAUNCHER"] = "0"
        }
        if forceFullscreen {
            env["DM_FULLSCREEN"] = "1"
        }

        if !args.isEmpty {
            config.arguments = args
        }
        if !env.isEmpty {
            config.environment = env
        }

        // An approved save is brought up to date first, so the game starts from the newest state.
        SaveSyncManager.shared.syncApproved(titleId: tid) {
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if error != nil {
                    NSWorkspace.shared.open(url)
                }
            }
        }
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
