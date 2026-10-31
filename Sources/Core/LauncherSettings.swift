import Foundation
import CoreFoundation

// MARK: - Settings list of a built game (launcher.json)
//
// Every Mac app built by a current nxnative carries `Contents/Resources/dm/launcher.json`:
// the settings the game offers, with its tested defaults resolved for the Mac.
// Reference: nxnative docs/frontends.md ("The settings list") and docs/launcher.schema.json.
//
// Compatibility rules from upstream (schema 1):
//  - unknown fields are ignored, unknown sections are shown under their own name,
//  - a row with an unknown `kind` is skipped (a new kind would mean schema 2).

struct LauncherSetting: Decodable, Identifiable, Equatable {
    enum Kind: String {
        case choice, range, toggle
    }

    let env: String
    let kindName: String
    let section: String
    let label: String
    let note: String
    let defaultValue: String
    let options: [[String]]?
    let min: Double?
    let max: Double?
    let step: Double?
    let on: String?
    let off: String?
    let base: RenderBase?
    let level: String?
    let needs: String?

    var id: String { env }
    var kind: Kind? { Kind(rawValue: kindName) }
    var isBasic: Bool { level == "basic" }

    struct RenderBase: Decodable, Equatable {
        let docked: [Int]
        let handheld: [Int]
    }

    private enum CodingKeys: String, CodingKey {
        case env, kind, section, label, note, options, min, max, step, on, off, base, level, needs
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        env = try c.decode(String.self, forKey: .env)
        kindName = try c.decode(String.self, forKey: .kind)
        section = (try? c.decode(String.self, forKey: .section)) ?? "Game"
        label = (try? c.decode(String.self, forKey: .label)) ?? env
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        defaultValue = (try? c.decode(String.self, forKey: .defaultValue)) ?? ""
        options = try? c.decode([[String]].self, forKey: .options)
        min = try? c.decode(Double.self, forKey: .min)
        max = try? c.decode(Double.self, forKey: .max)
        step = try? c.decode(Double.self, forKey: .step)
        on = try? c.decode(String.self, forKey: .on)
        off = try? c.decode(String.self, forKey: .off)
        base = try? c.decode(RenderBase.self, forKey: .base)
        level = try? c.decode(String.self, forKey: .level)
        needs = try? c.decode(String.self, forKey: .needs)
    }

    struct Choice: Hashable {
        let value: String
        let label: String
    }

    /// `[value, label]` pairs of a choice row (malformed pairs are dropped).
    var choices: [Choice] {
        (options ?? []).compactMap { $0.count >= 2 ? Choice(value: $0[0], label: $0[1]) : nil }
    }

    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }

    /// The condition of a sub-setting: `DM_RUMBLE=1` → ("DM_RUMBLE", "1").
    var condition: (env: String, value: String)? {
        guard let needs = needs else { return nil }
        let parts = needs.split(separator: "=", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// Whether the current build still offers `value` (upstream "validation on read").
    func accepts(_ value: String) -> Bool {
        switch kind {
        case .choice:
            return choices.contains { $0.value == value }
        case .toggle:
            return value == onValue || value == offValue
        case .range:
            guard let number = Double(value), let min = min, let max = max else { return false }
            let epsilon = 1e-9
            return number >= min - epsilon && number <= max + epsilon
        case nil:
            return false
        }
    }

    /// True if `value` means the same as the tested default (ranges compare numerically).
    func isDefault(_ value: String) -> Bool {
        if kind == .range, let a = Double(value), let b = Double(defaultValue) {
            return abs(a - b) < 1e-9
        }
        return value == defaultValue
    }

    // MARK: Ranges

    /// Number of decimals implied by the step (0.05 → 2, 0.1 → 1, 1 → 0).
    var stepDecimals: Int {
        guard let step = step, step > 0 else { return 2 }
        var decimals = 0
        var scaled = step
        while decimals < 4 && abs(scaled.rounded() - scaled) > 1e-9 {
            scaled *= 10
            decimals += 1
        }
        return decimals
    }

    func formatRange(_ number: Double) -> String {
        String(format: "%.\(stepDecimals)f", number)
    }

    /// Ranges are shown as a percentage, like the game's own settings window.
    func percentText(_ value: String) -> String {
        guard let number = Double(value) else { return value }
        return "\(Int((number * 100).rounded())) %"
    }

    /// Render scale only: the resulting 3D size for the chosen console mode, e.g. "1440×810".
    func resolutionText(_ value: String, docked: Bool) -> String? {
        guard let base = base, let scale = Double(value) else { return nil }
        let size = docked ? base.docked : base.handheld
        guard size.count == 2 else { return nil }
        return "\(Int((Double(size[0]) * scale).rounded()))×\(Int((Double(size[1]) * scale).rounded()))"
    }
}

struct LauncherSettingsList: Decodable {
    let schema: Int?
    let game: String
    let settings: [LauncherSetting]

    /// Rows the app can show (known kinds only).
    var usableSettings: [LauncherSetting] { settings.filter { $0.kind != nil } }

    /// Section names in order of their first row.
    var sections: [String] {
        var seen: [String] = []
        for row in usableSettings where !seen.contains(row.section) { seen.append(row.section) }
        return seen
    }

    var hasBasicRows: Bool { usableSettings.contains { $0.isBasic } }

    func setting(_ env: String) -> LauncherSetting? {
        usableSettings.first { $0.env == env }
    }

    /// Reads the list of a built Mac app; nil for builds made before nxnative shipped it.
    static func load(appPath: String) -> LauncherSettingsList? {
        let url = URL(fileURLWithPath: NXPaths.launcherListPath(appPath: appPath))
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(LauncherSettingsList.self, from: data),
              (list.schema ?? 1) == 1,
              !list.usableSettings.isEmpty else { return nil }
        return list
    }

    /// Localized heading for the sections nxnative uses today; unknown ones keep their name.
    static func localizedSection(_ name: String) -> String {
        switch name {
        case "Game": return tr("Spiel", "Game")
        case "Controls": return tr("Steuerung", "Controls")
        case "Performance": return tr("Leistung", "Performance")
        default: return name
        }
    }
}

// MARK: - Saved choices (the game's own preferences domain)
//
// The Mac app reads `launcher.<VAR>` strings from its preferences domain (its bundle ID)
// for every variable that neither the launch environment nor an env.txt sets.
// Only values that differ from the tested default are stored; a key is removed when the
// player picks the default again (docs/frontends.md, "Saved choices").

enum SavedChoices {
    private static func key(_ env: String) -> CFString { "launcher.\(env)" as CFString }

    /// Drops this process's cached copy of the domain, so changes the game's own
    /// settings window made are seen.
    static func refresh(bundleId: String) {
        CFPreferencesAppSynchronize(bundleId as CFString)
    }

    static func value(for env: String, bundleId: String) -> String? {
        CFPreferencesCopyAppValue(key(env), bundleId as CFString) as? String
    }

    /// Writes `values` (nil removes the key) and synchronizes the domain.
    @discardableResult
    static func write(_ values: [String: String?], bundleId: String) -> Bool {
        let domain = bundleId as CFString
        for (env, value) in values {
            CFPreferencesSetAppValue(key(env), value.map { $0 as CFString }, domain)
        }
        return CFPreferencesAppSynchronize(domain)
    }
}

// MARK: - Effective values (what the game will actually use)

enum GameSettingsResolver {
    /// Resolves each listed setting in the order the game's launcher uses:
    /// player's env.txt → bundle's dm/env.txt → saved choice (if still valid) → tested default.
    /// The launch environment (first in upstream's order) is not known here.
    static func effectiveValues(list: LauncherSettingsList,
                                envValues: [String: String],
                                bundleEnvValues: [String: String],
                                bundleId: String) -> [String: String] {
        SavedChoices.refresh(bundleId: bundleId)
        var result: [String: String] = [:]
        for row in list.usableSettings {
            if let fromEnv = envValues[row.env] ?? bundleEnvValues[row.env] {
                result[row.env] = fromEnv
            } else if let saved = SavedChoices.value(for: row.env, bundleId: bundleId), row.accepts(saved) {
                result[row.env] = saved
            } else {
                result[row.env] = row.defaultValue
            }
        }
        return result
    }
}
