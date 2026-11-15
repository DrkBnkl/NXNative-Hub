import Foundation

// MARK: - Game settings
//
// Drawn from the game's launcher.json; choices go into the game's saved choices
// (docs/frontends.md, "Saved choices"), not into env.txt.

final class GameSettingsModel: ObservableObject {
    struct StatusMessage: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var titleId: String = ""
    @Published private(set) var gameName: String = ""
    @Published private(set) var associatedAppPath: String?
    /// Determined once on load (not on every view redraw).
    @Published private(set) var ryujinxSavePath: String?

    /// The game's settings list (launcher.json); empty if the app has none.
    @Published private(set) var settings: [LauncherSetting] = []
    /// Values an env file sets: shown, but the game ignores a saved choice for them.
    @Published private(set) var fixed: [String: String] = [:]
    /// The value per setting as shown in the sheet.
    @Published var values: [String: String] = [:]
    @Published private(set) var bundleId: String?

    @Published var statusMessage: StatusMessage?

    var hasGame: Bool { !titleId.isEmpty }
    var hasSettingsList: Bool { !settings.isEmpty }
    var envFilePath: String { NXPaths.envFilePath(titleId: titleId) }

    func load(titleId: String, gameName: String, appPath: String? = nil) {
        self.titleId = titleId
        self.gameName = gameName
        self.associatedAppPath = appPath
        self.statusMessage = nil

        if let appPath, let info = GameBundleInfo(appPath: appPath) {
            LegacyEnvMigration.migrateIfNeeded(info: info)
            let snapshot = GameSettingsSnapshot(info: info)
            settings = snapshot.settings
            fixed = snapshot.fixed
            values = snapshot.values
            bundleId = info.bundleId
        } else {
            settings = []
            fixed = [:]
            values = [:]
            bundleId = nil
        }

        ryujinxSavePath = nil
        let tid = titleId
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let path = SaveGameImporter.ryujinxSavePath(titleId: tid)
            DispatchQueue.main.async {
                if self?.titleId == tid { self?.ryujinxSavePath = path }
            }
        }
    }

    // MARK: Layout (as upstream's settings window: basic settings first, then the rest)

    func isFixed(_ setting: LauncherSetting) -> Bool { fixed[setting.env] != nil }

    func value(_ setting: LauncherSetting) -> String { values[setting.env] ?? setting.defaultValue }

    /// A row with `needs` is drawn only while the row it names has that value; a row naming a
    /// variable the list does not have stays drawn.
    func isVisible(_ setting: LauncherSetting) -> Bool {
        guard let req = setting.requirement, let current = values[req.key] else { return true }
        return current == req.value
    }

    func sections(basic: Bool) -> [String] {
        settings.filter { $0.isBasic == basic }.reduce(into: [String]()) { result, s in
            if !result.contains(s.sectionTitle) { result.append(s.sectionTitle) }
        }
    }

    func rows(in section: String, basic: Bool) -> [LauncherSetting] {
        settings.filter { $0.sectionTitle == section && $0.isBasic == basic && isVisible($0) }
    }

    /// Whether any changeable setting differs from the tested default.
    var differsFromDefaults: Bool {
        settings.contains { !isFixed($0) && !$0.isDefault(value($0)) }
    }

    /// Back to the tested defaults on screen; written on save. Values set by env.txt stay.
    func resetToDefaults() {
        for setting in settings where !isFixed(setting) {
            values[setting.env] = setting.defaultValue
        }
    }

    // MARK: Saving

    /// Writes the choices into the game's preferences domain (`launcher.<ENV>`); a choice equal
    /// to the tested default is removed, so a later build's defaults apply. Returns `false` on failure.
    @discardableResult
    func save() -> Bool {
        guard hasGame else { return false }
        guard hasSettingsList, let bundleId else {
            showStatus(tr("Dieses Spiel hat keine Einstellungsliste. Bitte mit aktuellem nxnative neu bauen.",
                          "This game has no settings list. Please rebuild it with current nxnative."), isError: true)
            return false
        }
        let store = SavedChoices(bundleId: bundleId)
        for setting in settings where !isFixed(setting) {
            let v = value(setting)
            guard setting.accepts(v) else { continue }
            store.store(v, for: setting)
        }
        guard store.synchronize() else {
            showStatus(tr("Speichern fehlgeschlagen", "Saving failed"), isError: true)
            return false
        }
        showStatus(tr("Einstellungen gespeichert", "Settings saved"), isError: false)
        return true
    }

    /// Saves and launches the game – only if saving succeeded. A game without a settings
    /// list has nothing to save: it is launched as it is, with its own window if it has one.
    @discardableResult
    func saveAndLaunch() -> Bool {
        guard hasGame else { return false }
        guard hasSettingsList else {
            guard let app = associatedAppPath, FileManager.default.fileExists(atPath: app) else { return false }
            GameActions.launch(appPath: app)
            return true
        }
        guard save() else { return false }
        if let app = associatedAppPath, FileManager.default.fileExists(atPath: app) {
            // The Hub already showed the settings: skip the game's own window.
            GameActions.launch(appPath: app, skipSettingsWindow: true)
        }
        return true
    }

    func showStatus(_ text: String, isError: Bool) {
        let message = StatusMessage(text: text, isError: isError)
        statusMessage = message
        guard !isError else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
