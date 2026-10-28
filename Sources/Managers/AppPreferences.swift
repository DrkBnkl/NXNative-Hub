import Foundation

// MARK: - App-wide preferences (Settings window ⌘,)
//
// Shared by the builder, the import and the Settings window. The UserDefaults keys
// are unchanged from 1.0, so existing settings are kept.

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Keys {
        static let prodKeys = "savedProdKeysPath"
        static let gameLanguage = "defaultGameLanguage"
        static let notifyBuilds = Notifier.enabledKey
    }

    @Published var prodKeysPath: String {
        didSet { UserDefaults.standard.set(prodKeysPath, forKey: Keys.prodKeys) }
    }

    /// Default game language for new builds and batch imports.
    @Published var defaultGameLanguage: String {
        didSet { UserDefaults.standard.set(defaultGameLanguage, forKey: Keys.gameLanguage) }
    }

    /// nxnative folder chosen in Settings; empty = automatic detection
    /// (~/NXNative/nxnative). Stored under the key that
    /// `NXPaths` reads, so all path resolution follows the change immediately.
    @Published var customRepoPath: String {
        didSet { UserDefaults.standard.set(customRepoPath, forKey: NXPaths.customRepoPathKey) }
    }

    /// Post a notification when a build or batch import finishes while the app is in the background.
    @Published var notifyWhenBuildsFinish: Bool {
        didSet { UserDefaults.standard.set(notifyWhenBuildsFinish, forKey: Keys.notifyBuilds) }
    }

    init() {
        let defaults = UserDefaults.standard
        notifyWhenBuildsFinish = defaults.object(forKey: Keys.notifyBuilds) as? Bool ?? true
        prodKeysPath = defaults.string(forKey: Keys.prodKeys) ?? ""
        customRepoPath = defaults.string(forKey: NXPaths.customRepoPathKey) ?? ""
        defaultGameLanguage = defaults.string(forKey: Keys.gameLanguage)
            ?? (LanguageManager.shared.isGerman ? "de" : "en")
    }

    var prodKeysExists: Bool {
        !prodKeysPath.isEmpty && FileManager.default.fileExists(atPath: prodKeysPath)
    }

    /// Looks for prod.keys in common locations if no valid path is set yet.
    func autoDetectKeysIfNeeded() {
        guard !prodKeysExists else { return }
        let home = NXPaths.home
        let candidates = [
            "\(home)/.switch/prod.keys",
            "\(home)/NXNative/keys/prod.keys",
            "\(home)/Documents/switch library manager/prod.keys",
            "\(home)/Library/Containers/V380-Ori.Astris/Data/Library/Application Support/Ryujinx/system/prod.keys",
            "\(home)/Library/Application Support/Ryujinx/system/prod.keys",
            "\(home)/keys/prod.keys"
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            prodKeysPath = found
        }
    }
}
