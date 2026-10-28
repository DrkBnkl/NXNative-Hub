import Foundation

// MARK: - Game settings
//
// Two modes:
//  - Settings list: the game carries launcher.json (current nxnative). The rows come from that
//    list and are stored as saved choices in the game's preferences domain – only values that
//    differ from the tested default. Listed values in env.txt (written by Hub 1.1.0, which would
//    otherwise pin them over the game's tested defaults) are moved there on save.
//  - Legacy: builds without launcher.json. A fixed set of switches is written to env.txt.

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

    // Settings-list mode
    @Published private(set) var list: LauncherSettingsList?
    @Published private(set) var bundleId: String = ""
    /// Current value per listed variable.
    @Published var values: [String: String] = [:]
    /// Listed variables that cannot be changed here, shown read-only: env.txt sets them to a value
    /// the list does not offer, or the build's own dm/env.txt fixes them.
    @Published private(set) var pinnedByEnvFile: [String: String] = [:]
    @Published private(set) var fixedByBuild: [String: String] = [:]
    /// env.txt still holds listed values that will be moved to the saved choices on save.
    @Published private(set) var hasEnvValuesToMigrate = false

    @Published var fpsTarget: String = "60"        // DM_FPS_TARGET
    @Published var opMode: String = "1"            // DM_OPMODE (1 = Docked 1080p, 0 = Handheld 720p)
    @Published var upscaling: String = "metalfx"   // DM_PRESENT_UPSCALE (off, metalfx)
    @Published var showFps: Bool = true            // DM_SHOW_FPS
    @Published var metalHud: Bool = false          // DM_METAL_HUD
    @Published var frameBuffering: Bool = true     // DM_PRESENT_SNAP
    @Published var rumble: Bool = true             // DM_RUMBLE
    @Published var rumbleGain: Double = 1.0        // DM_RUMBLE_GAIN
    @Published var fullscreen: Bool = false        // DM_FULLSCREEN
    @Published var language: String = ""          // DM_LANG

    @Published var statusMessage: StatusMessage?

    /// Keys the legacy editor writes to env.txt (also cleaned up when migrating to the settings list).
    static let managedKeys: Set<String> = [
        "DM_FPS_TARGET", "DM_OPMODE", "DM_PRESENT_UPSCALE", "DM_SHOW_FPS", "DM_METAL_HUD",
        "DM_PRESENT_SNAP", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_FULLSCREEN", "DM_LANG"
    ]

    var hasGame: Bool { !titleId.isEmpty }
    var usesSettingsList: Bool { list != nil }
    var envFilePath: String { NXPaths.envFilePath(titleId: titleId) }

    func load(titleId: String, gameName: String, appPath: String? = nil) {
        self.titleId = titleId
        self.gameName = gameName
        self.associatedAppPath = appPath
        self.statusMessage = nil

        let envValues = EnvFile.load(path: envFilePath)?.values ?? [:]
        list = appPath.flatMap { LauncherSettingsList.load(appPath: $0) }
        bundleId = appPath.flatMap { GameBundleInfo(appPath: $0)?.bundleId } ?? ""

        if let list = list, let appPath = appPath {
            let bundleEnv = EnvFile.load(path: NXPaths.bundleEnvFilePath(appPath: appPath))?.values ?? [:]
            values = GameSettingsResolver.effectiveValues(list: list, envValues: envValues,
                                                          bundleEnvValues: bundleEnv, bundleId: bundleId)
            pinnedByEnvFile = [:]
            fixedByBuild = [:]
            var migrate = false
            for row in list.usableSettings {
                if let fromEnv = envValues[row.env] {
                    // Moving it to the saved choices would let a value fixed by the build win instead.
                    if row.accepts(fromEnv) && bundleEnv[row.env] == nil {
                        migrate = true
                    } else {
                        pinnedByEnvFile[row.env] = fromEnv
                    }
                } else if let fromBuild = bundleEnv[row.env] {
                    fixedByBuild[row.env] = fromBuild
                }
            }
            hasEnvValuesToMigrate = migrate
        } else {
            values = [:]
            pinnedByEnvFile = [:]
            fixedByBuild = [:]
            hasEnvValuesToMigrate = false
            // Reset to defaults first, so values of the previously opened game
            // do not stick when a key is missing from env.txt.
            resetToDefaults()
            apply(envValues)
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

    func resetToDefaults() {
        if let list = list {
            for row in list.usableSettings where isEditable(row) {
                values[row.env] = row.defaultValue
            }
            return
        }
        fpsTarget = "60"
        opMode = "1"
        upscaling = "metalfx"
        showFps = true
        metalHud = false
        frameBuffering = true
        rumble = true
        rumbleGain = 1.0
        fullscreen = false
        language = AppPreferences.shared.defaultGameLanguage
    }

    private func apply(_ values: [String: String]) {
        for (key, val) in values {
            switch key {
            case "DM_FPS_TARGET": fpsTarget = val
            case "DM_OPMODE": opMode = val
            case "DM_PRESENT_UPSCALE": upscaling = val
            case "DM_SHOW_FPS": showFps = (val == "1")
            case "DM_METAL_HUD": metalHud = (val == "1")
            case "DM_PRESENT_SNAP": frameBuffering = (val == "1")
            case "DM_RUMBLE": rumble = (val == "1")
            case "DM_RUMBLE_GAIN": rumbleGain = Double(val) ?? 1.0
            case "DM_FULLSCREEN": fullscreen = (val == "1")
            case "DM_LANG": language = val
            default: break
            }
        }
    }

    // MARK: Settings-list mode

    /// Whether a row is drawn: sub-settings only while their parent row has the required value.
    func isVisible(_ row: LauncherSetting) -> Bool {
        guard let condition = row.condition, list?.setting(condition.env) != nil else { return true }
        return values[condition.env] == condition.value
    }

    func isEditable(_ row: LauncherSetting) -> Bool {
        pinnedByEnvFile[row.env] == nil && fixedByBuild[row.env] == nil
    }

    func binding(for row: LauncherSetting) -> String {
        values[row.env] ?? row.defaultValue
    }

    var isDocked: Bool {
        (values["DM_OPMODE"] ?? list?.setting("DM_OPMODE")?.defaultValue ?? "1") == "1"
    }

    /// Writes the saved choices and removes listed values from env.txt (keeping everything else).
    private func saveSettingsList(_ list: LauncherSettingsList) -> Bool {
        guard !bundleId.isEmpty else {
            showStatus(tr("Die App hat keine Bundle-ID – Einstellungen können nicht gesichert werden.",
                          "The app has no bundle ID – settings cannot be saved."), isError: true)
            return false
        }

        var choices: [String: String?] = [:]
        for row in list.usableSettings where isEditable(row) {
            let value = values[row.env] ?? row.defaultValue
            // updateValue keeps a nil entry (= remove the saved choice); `choices[key] = nil` would drop it.
            let stored: String? = (row.isDefault(value) || !row.accepts(value)) ? nil : value
            choices.updateValue(stored, forKey: row.env)
        }
        guard SavedChoices.write(choices, bundleId: bundleId) else {
            showStatus(tr("Speichern fehlgeschlagen (Einstellungen der Spiel-App).", "Saving failed (game app preferences)."), isError: true)
            return false
        }

        // Move listed values out of env.txt: env.txt would otherwise win over the saved choices.
        if let existing = EnvFile.load(path: envFilePath) {
            let keysToRemove = Set(list.usableSettings.map { $0.env }).union(Self.managedKeys)
                .subtracting(pinnedByEnvFile.keys)
            let remaining = existing.unmanagedLines(managedKeys: keysToRemove)
            if remaining != existing.lines {
                do {
                    if remaining.isEmpty {
                        // Nothing of the player's own left: move the file to the Trash (recoverable).
                        try FileManager.default.trashItem(at: URL(fileURLWithPath: envFilePath), resultingItemURL: nil)
                    } else {
                        try (remaining.joined(separator: "\n") + "\n").write(toFile: envFilePath, atomically: true, encoding: .utf8)
                    }
                } catch {
                    showStatus(tr("env.txt konnte nicht angepasst werden: \(error.localizedDescription)",
                                  "Could not update env.txt: \(error.localizedDescription)"), isError: true)
                    return false
                }
            }
        }
        hasEnvValuesToMigrate = false
        showStatus(tr("Einstellungen gespeichert", "Settings saved"), isError: false)
        return true
    }

    // MARK: Saving

    /// Saves the settings (saved choices or env.txt, depending on the build).
    /// Returns `false` if writing fails.
    @discardableResult
    func save() -> Bool {
        guard hasGame else { return false }
        if let list = list { return saveSettingsList(list) }

        let dir = NXPaths.gameConfigDirectory(titleId: titleId)
        let existing = EnvFile.load(path: envFilePath) ?? EnvFile()

        var lines: [String] = [
            "# nxnative \(tr("Konfiguration für", "configuration for")) \(gameName) (\(titleId))",
            "# \(tr("Wird automatisch beim Start des Spiels ausgelesen", "Automatically detected when the game starts"))",
            ""
        ]
        if !fpsTarget.isEmpty { lines.append("DM_FPS_TARGET=\(fpsTarget)") }
        lines.append("DM_OPMODE=\(opMode)")
        lines.append("DM_PRESENT_UPSCALE=\(upscaling)")
        lines.append("DM_SHOW_FPS=\(showFps ? "1" : "0")")
        lines.append("DM_METAL_HUD=\(metalHud ? "1" : "0")")
        lines.append("DM_PRESENT_SNAP=\(frameBuffering ? "1" : "0")")
        lines.append("DM_RUMBLE=\(rumble ? "1" : "0")")
        lines.append("DM_RUMBLE_GAIN=\(String(format: "%.1f", rumbleGain))")
        // Windowed = key absent, so nxnative uses its default.
        lines.append(fullscreen ? "DM_FULLSCREEN=1" : "# DM_FULLSCREEN=1")
        if !language.isEmpty { lines.append("DM_LANG=\(language)") }

        let preserved = existing.unmanagedLines(managedKeys: Self.managedKeys)
        if !preserved.isEmpty {
            lines.append("")
            lines.append(EnvFile.preservedHeader)
            lines.append(contentsOf: preserved)
        }

        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(toFile: envFilePath, atomically: true, encoding: .utf8)
            showStatus(tr("Einstellungen gespeichert", "Settings saved"), isError: false)
            return true
        } catch {
            showStatus(tr("Speichern fehlgeschlagen: \(error.localizedDescription)",
                          "Saving failed: \(error.localizedDescription)"), isError: true)
            return false
        }
    }

    /// Saves and launches the game – only if saving succeeded.
    @discardableResult
    func saveAndLaunch() -> Bool {
        guard save() else { return false }
        if let app = associatedAppPath, FileManager.default.fileExists(atPath: app) {
            GameActions.launch(appPath: app)
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
