import Foundation

// MARK: - App-wide preferences (Settings window ⌘,)
//
// Shared by the builder, the import and the Settings window. The UserDefaults keys
// are unchanged from 1.0, so existing settings are kept.

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return tr("Listenansicht", "List View")
        case .grid: return tr("Coveransicht", "Cover Grid")
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum CoverSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return tr("Klein", "Small")
        case .medium: return tr("Mittel", "Medium")
        case .large: return tr("Groß", "Large")
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 130
        case .medium: return 175
        case .large: return 230
        }
    }
}

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Keys {
        static let prodKeys = "savedProdKeysPath"
        static let gameLanguage = "defaultGameLanguage"
        static let notifyBuilds = Notifier.enabledKey
        static let skipGameLauncher = "skipGameLauncher"
        static let libraryViewMode = "libraryViewMode"
        static let coverSize = "libraryCoverSize"
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

    /// Whether to skip the game's start / settings window when launching.
    @Published var skipGameLauncher: Bool {
        didSet { UserDefaults.standard.set(skipGameLauncher, forKey: Keys.skipGameLauncher) }
    }

    /// Layout mode for "My Games" library: list or grid of large covers.
    @Published var libraryViewMode: LibraryViewMode {
        didSet { UserDefaults.standard.set(libraryViewMode.rawValue, forKey: Keys.libraryViewMode) }
    }

    /// Size of covers in grid view (small, medium, large).
    @Published var coverSize: CoverSize {
        didSet { UserDefaults.standard.set(coverSize.rawValue, forKey: Keys.coverSize) }
    }

    init() {
        let defaults = UserDefaults.standard
        notifyWhenBuildsFinish = defaults.object(forKey: Keys.notifyBuilds) as? Bool ?? true
        skipGameLauncher = defaults.object(forKey: Keys.skipGameLauncher) as? Bool ?? true
        prodKeysPath = defaults.string(forKey: Keys.prodKeys) ?? ""
        customRepoPath = defaults.string(forKey: NXPaths.customRepoPathKey) ?? ""
        let savedLanguage = defaults.string(forKey: Keys.gameLanguage)
            ?? (LanguageManager.shared.isGerman ? "de" : "en-US")
        // 1.1 stored "en"; the build script's code for it is "en-US".
        defaultGameLanguage = savedLanguage == "en" ? "en-US" : savedLanguage

        let savedViewMode = defaults.string(forKey: Keys.libraryViewMode)
            .flatMap(LibraryViewMode.init(rawValue:)) ?? .grid
        libraryViewMode = savedViewMode

        let savedCoverSize = defaults.string(forKey: Keys.coverSize)
            .flatMap(CoverSize.init(rawValue:)) ?? .medium
        coverSize = savedCoverSize
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
