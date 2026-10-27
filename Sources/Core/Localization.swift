import Foundation

// MARK: - Localization (German & English)
//
// Lightweight inline system `tr("German", "English")` instead of String Catalogs,
// because the app is built with plain `swiftc` (no Xcode project).
// Language: automatic (system language) or chosen manually in Settings.

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case de = "de"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            let isSysDe = Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
            return tr("Automatisch (System: \(isSysDe ? "Deutsch" : "Englisch"))",
                      "Automatic (System: \(isSysDe ? "German" : "English"))")
        case .de:
            return "Deutsch"
        case .en:
            return "English"
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let defaultsKey = "app_language_choice"

    @Published var currentChoice: AppLanguage {
        didSet { UserDefaults.standard.set(currentChoice.rawValue, forKey: Self.defaultsKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.auto.rawValue
        self.currentChoice = AppLanguage(rawValue: saved) ?? .auto
    }

    var isGerman: Bool {
        switch currentChoice {
        case .de: return true
        case .en: return false
        case .auto: return Locale.preferredLanguages.first?.lowercased().hasPrefix("de") == true
        }
    }

    func tr(_ de: String, _ en: String) -> String {
        isGerman ? de : en
    }
}

/// Returns the text in the currently selected UI language.
func tr(_ de: String, _ en: String) -> String {
    LanguageManager.shared.tr(de, en)
}
