import Foundation

// MARK: - launcher.json (a built game's settings list)
//
// Upstream contract: nxnative docs/frontends.md ("The settings list", "Saved choices") and
// docs/launcher.schema.json (schema 1). A Mac app carries the list in
// Contents/Resources/dm/launcher.json. The semantics follow upstream's own reader
// (dm/ios/Sources/LauncherSettings.swift) and the Mac launcher (dm/mac/launcher.c), so the
// Hub, the game's own settings window and a start from Finder all agree.

struct LauncherSetting: Decodable, Identifiable, Hashable {
    let env: String
    let kind: String          // choice | range | toggle (schema 1)
    let label: String
    let note: String
    let defaultValue: String
    let section: String?
    let needs: String?        // "<VAR>=<value>": drawn only while that row has that value
    let level: String?        // "basic": shown first
    let options: [[String]]?  // choice: [value, label]
    let min: Double?
    let max: Double?
    let step: Double?
    let on: String?
    let off: String?

    var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var isBasic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }

    /// Schema 1 knows three kinds; a row of another kind cannot be drawn.
    var isSupportedKind: Bool { ["choice", "range", "toggle"].contains(kind) }

    /// A range compares as numbers (a slider may write "1.00" for "1.0").
    func isDefault(_ value: String) -> Bool {
        if kind == "range" {
            guard let a = Double(value), let b = Double(defaultValue) else { return value == defaultValue }
            return abs(a - b) < 1e-6
        }
        return value == defaultValue
    }

    /// Whether this build still offers the value (the check the Mac launcher applies to saved choices).
    func accepts(_ value: String) -> Bool {
        switch kind {
        case "choice":
            return options?.contains { $0.first == value } ?? false
        case "range":
            guard !value.isEmpty, value.first?.isWhitespace == false,
                  !value.contains(where: { $0 == "x" || $0 == "X" }),
                  let n = Double(value), n.isFinite, let lo = min, let hi = max else { return false }
            return n >= lo && n <= hi
        case "toggle":
            return value == onValue || value == offValue
        default:
            return false
        }
    }

    /// The value written for a range, with as many decimals as the step needs.
    func formatRange(_ value: Double) -> String {
        let decimals: Int
        if let step, step > 0 {
            var d = 0
            var s = step
            while d < 4 && abs(s.rounded() - s) > 1e-9 { s *= 10; d += 1 }
            decimals = d
        } else {
            decimals = 2
        }
        return String(format: "%.\(decimals)f", value)
    }

    /// The variable and value of `needs`, if any.
    var requirement: (key: String, value: String)? {
        guard let needs, let eq = needs.firstIndex(of: "=") else { return nil }
        return (String(needs[..<eq]), String(needs[needs.index(after: eq)...]))
    }

    enum CodingKeys: String, CodingKey {
        case env, kind, label, note, section, needs, level, options, min, max, step, on, off
        case defaultValue = "default"
    }
}

struct LauncherSettingsFile: Decodable {
    let schema: Int?
    let game: String?
    let settings: [LauncherSetting]

    /// `Contents/Resources/dm/launcher.json` of a Mac app.
    static func path(appPath: String) -> String {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/dm/launcher.json").path
    }

    /// Loads the list. Returns nil if the app has none (built before the list existed, or an
    /// unknown schema); such an app has no settings to offer.
    static func load(appPath: String) -> LauncherSettingsFile? {
        guard let data = FileManager.default.contents(atPath: path(appPath: appPath)),
              let file = try? JSONDecoder().decode(LauncherSettingsFile.self, from: data) else { return nil }
        if let schema = file.schema, schema != 1 { return nil }
        return file
    }

    var drawableSettings: [LauncherSetting] { settings.filter(\.isSupportedKind) }
}

// MARK: - Saved choices (the game's own preferences domain)
//
// One string per setting under `launcher.<ENV>` in the app's CFBundleIdentifier domain. Only
// choices that differ from the tested default are kept, so a later build's defaults reach
// the player.

struct SavedChoices {
    let bundleId: String

    /// Reads the domain from disk once, so choices the game's own window saved are seen.
    init(bundleId: String) {
        self.bundleId = bundleId
        CFPreferencesAppSynchronize(bundleId as CFString)
    }

    private var domain: CFString { bundleId as CFString }
    private static func key(_ env: String) -> CFString { "launcher.\(env)" as CFString }

    /// The saved string for a setting (a non-string value is ignored, as the launcher does).
    func value(for env: String) -> String? {
        CFPreferencesCopyAppValue(Self.key(env), domain) as? String
    }

    func store(_ value: String, for setting: LauncherSetting) {
        if setting.isDefault(value) {
            CFPreferencesSetAppValue(Self.key(setting.env), nil, domain)
        } else {
            CFPreferencesSetAppValue(Self.key(setting.env), value as CFString, domain)
        }
    }

    func remove(_ env: String) {
        CFPreferencesSetAppValue(Self.key(env), nil, domain)
    }

    @discardableResult
    func synchronize() -> Bool {
        CFPreferencesAppSynchronize(domain)
    }
}

// MARK: - Effective settings of an installed game

/// Resolves what a game will use at the next start from Finder, in upstream's order:
/// player's env.txt → bundle dm/env.txt → saved choices → tested defaults.
struct GameSettingsSnapshot {
    let settings: [LauncherSetting]
    /// Values set by an env file: shown, not changeable in the Hub (key → value).
    let fixed: [String: String]
    /// Effective value per setting.
    let values: [String: String]

    init(info: GameBundleInfo) {
        let list = LauncherSettingsFile.load(appPath: info.appPath)?.drawableSettings ?? []
        let playerEnv = EnvFile.load(path: NXPaths.envFilePath(titleId: info.titleId))?.values ?? [:]
        let bundleEnv = EnvFile.load(path: info.bundleEnvFilePath)?.values ?? [:]
        let saved = info.bundleId.map(SavedChoices.init(bundleId:))

        var fixed: [String: String] = [:]
        var values: [String: String] = [:]
        for setting in list {
            if let v = playerEnv[setting.env] ?? bundleEnv[setting.env] {
                fixed[setting.env] = v
                values[setting.env] = v
            } else if let v = saved?.value(for: setting.env), setting.accepts(v) {
                values[setting.env] = v
            } else {
                values[setting.env] = setting.defaultValue
            }
        }
        // Without a settings list only the env files say anything about the game.
        if list.isEmpty {
            values = bundleEnv.merging(playerEnv) { _, player in player }
        }
        self.settings = list
        self.fixed = fixed
        self.values = values
    }
}

// MARK: - Migration of env.txt files written by Hub 1.1

/// Hub 1.1 wrote every setting into the player's env.txt with its own defaults. env.txt wins
/// over the game's saved choices and its settings window shows those values as fixed, so later
/// tested defaults never applied. This moves the Hub's lines out of env.txt once:
/// - a value equal to the Hub 1.1 default was not a choice and is dropped,
/// - any other value this build offers becomes a saved choice (unless it is the tested default),
/// - a choice that cannot be carried over (the build has no such setting, or does not offer
///   the value) stays in env.txt, where it keeps applying,
/// - lines the player wrote themselves stay in env.txt.
/// The original file is kept as `env.txt.hub-1.1.bak` next to it.
enum LegacyEnvMigration {
    static let hubKeys: Set<String> = [
        "DM_FPS_TARGET", "DM_OPMODE", "DM_PRESENT_UPSCALE", "DM_SHOW_FPS", "DM_METAL_HUD",
        "DM_PRESENT_SNAP", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_FULLSCREEN", "DM_LANG"
    ]

    /// What Hub 1.1 wrote when the player changed nothing (DM_LANG had no fixed default).
    private static let hub11Defaults: [String: String] = [
        "DM_FPS_TARGET": "60", "DM_OPMODE": "1", "DM_PRESENT_UPSCALE": "metalfx", "DM_SHOW_FPS": "1",
        "DM_METAL_HUD": "0", "DM_PRESENT_SNAP": "1", "DM_RUMBLE": "1", "DM_RUMBLE_GAIN": "1.0"
    ]

    static func isHubGenerated(_ file: EnvFile) -> Bool {
        guard let first = file.lines.first?.trimmingCharacters(in: .whitespaces) else { return false }
        return first.hasPrefix("# nxnative Konfiguration für") || first.hasPrefix("# nxnative configuration for")
    }

    /// Migrates if needed. Returns true if env.txt was changed.
    @discardableResult
    static func migrateIfNeeded(info: GameBundleInfo) -> Bool {
        let envPath = NXPaths.envFilePath(titleId: info.titleId)
        guard let file = EnvFile.load(path: envPath), isHubGenerated(file),
              let bundleId = info.bundleId,
              let list = LauncherSettingsFile.load(appPath: info.appPath)?.drawableSettings else { return false }

        let fm = FileManager.default
        let backupPath = envPath + ".hub-1.1.bak"
        if !fm.fileExists(atPath: backupPath) {
            // Without a backup nothing is changed.
            do { try fm.copyItem(atPath: envPath, toPath: backupPath) } catch { return false }
        }

        let saved = SavedChoices(bundleId: bundleId)
        let values = file.values
        let settings = Dictionary(list.map { ($0.env, $0) }, uniquingKeysWith: { first, _ in first })
        // Hub lines that leave env.txt; a choice that cannot be carried over stays.
        var movedKeys = hubKeys
        for key in hubKeys {
            guard var value = values[key], hub11Defaults[key] != value else { continue }
            // Hub 1.1 wrote "en"; the settings list's code for it is "en-US".
            if key == "DM_LANG", value == "en" { value = "en-US" }
            guard let setting = settings[key], setting.accepts(value) else {
                movedKeys.remove(key)
                continue
            }
            // A choice the player already made in the game's own window wins.
            if !setting.isDefault(value), saved.value(for: key) == nil { saved.store(value, for: setting) }
        }
        saved.synchronize()

        let remaining = file.unmanagedLines(managedKeys: movedKeys)
        do {
            if remaining.isEmpty {
                // The backup holds the original; the now empty file is not needed.
                try fm.removeItem(atPath: envPath)
            } else {
                try (remaining.joined(separator: "\n") + "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
            }
            return true
        } catch {
            return false
        }
    }
}
