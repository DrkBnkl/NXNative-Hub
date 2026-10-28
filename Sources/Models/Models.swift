import SwiftUI
import AppKit

// MARK: - Navigation (sidebar)

/// Sidebar sections of the main window.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case library
    case builder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return tr("Meine Spiele", "My Games")
        case .builder: return tr("Spiel bauen", "Build Game")
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "gamecontroller"
        case .builder: return "hammer"
        }
    }
}

// MARK: - Build target platform

enum TargetPlatform: String, CaseIterable, Identifiable {
    case macApp = "mac-app"
    case ios = "ios"
    case macDev = "mac"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macApp: return tr("Mac-App", "Mac App")
        case .ios: return tr("iPhone / iPad", "iPhone / iPad")
        case .macDev: return tr("Entwicklertest", "Developer Test")
        }
    }

    var subtitle: String {
        switch self {
        case .macApp: return tr("Eigenständige macOS-App (.app) – per Doppelklick spielbar.", "Standalone macOS app (.app) – double-click to play.")
        case .ios: return tr("Unsignierte IPA-Datei für Sideloading (TrollStore / AltStore).", "Unsigned IPA file for sideloading (TrollStore / AltStore).")
        case .macDev: return tr("Direkter Start im Terminal zum Testen.", "Runs directly in Terminal for debugging.")
        }
    }

    var systemImage: String {
        switch self {
        case .macApp: return "macwindow"
        case .ios: return "iphone"
        case .macDev: return "terminal"
        }
    }
}

// MARK: - Game language (DM_LANG / -l)

struct GameLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    /// Computed (not `static let`) so the names follow UI language changes.
    static var list: [GameLanguage] {
        [
            GameLanguage(code: "", name: tr("Automatisch (Spiel-Standard)", "Automatic (Game Default)")),
            GameLanguage(code: "de", name: tr("Deutsch", "German")),
            GameLanguage(code: "en", name: tr("Englisch", "English")),
            GameLanguage(code: "ja", name: tr("Japanisch", "Japanese")),
            GameLanguage(code: "fr", name: tr("Französisch", "French")),
            GameLanguage(code: "es", name: tr("Spanisch", "Spanish")),
            GameLanguage(code: "it", name: tr("Italienisch", "Italian")),
            GameLanguage(code: "nl", name: tr("Niederländisch", "Dutch")),
            GameLanguage(code: "pt", name: tr("Portugiesisch", "Portuguese")),
            GameLanguage(code: "zh-Hans", name: tr("Chinesisch (vereinfacht)", "Chinese (Simplified)")),
            GameLanguage(code: "zh-Hant", name: tr("Chinesisch (traditionell)", "Chinese (Traditional)")),
            GameLanguage(code: "ko", name: tr("Koreanisch", "Korean"))
        ]
    }
}

// MARK: - Installed game (library)

struct InstalledGame: Identifiable, Hashable {
    let id: String
    let name: String
    let titleId: String
    let version: String
    let path: String
    let sizeFormatted: String
    var fpsTarget: String
    var isDocked: Bool
    var upscaling: String
    var isFullscreen: Bool
    var language: String
    /// Built with a current nxnative that ships launcher.json (settings list, saved choices).
    var hasSettingsList: Bool

    var logPath: String { NXPaths.gameLogPath(titleId: titleId) }
    var previousLogPath: String { NXPaths.previousGameLogPath(titleId: titleId) }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

/// Reads title ID, name and version from a converted game's Info.plist.
struct GameBundleInfo {
    let titleId: String
    let name: String
    let version: String
    /// Preferences domain of the game's own launcher (saved choices), e.g. `org.nxnative.0100…`.
    let bundleId: String

    init?(appPath: String) {
        let plistURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let tid = plist["DMTitleID"] as? String, !tid.isEmpty else { return nil }
        self.titleId = tid
        self.name = (plist["CFBundleName"] as? String) ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        self.version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        self.bundleId = (plist["CFBundleIdentifier"] as? String) ?? "org.nxnative.\(tid.lowercased())"
    }
}

// MARK: - Game file detected in the build folder

struct DetectedGameFile: Identifiable {
    enum Kind {
        case base, update, dlc, rom

        var title: String {
            switch self {
            case .base: return tr("Basis", "Base")
            case .update: return "Update"
            case .dlc: return "DLC"
            case .rom: return "ROM"
            }
        }

        var systemImage: String {
            switch self {
            case .base: return "gamecontroller.fill"
            case .update: return "arrow.triangle.2.circlepath.circle.fill"
            case .dlc: return "plus.rectangle.fill"
            case .rom: return "doc.fill"
            }
        }

        var color: Color {
            switch self {
            case .base: return .blue
            case .update: return .green
            case .dlc: return .purple
            case .rom: return .secondary
            }
        }
    }

    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64
    let sizeFormatted: String
    let kind: Kind

    init(url: URL) {
        self.name = url.lastPathComponent
        self.path = url.path

        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        self.sizeBytes = size
        self.sizeFormatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        // Heuristic based on the common file name pattern "Name [TitleID][vXXXX].nsp"
        let lower = url.lastPathComponent.lowercased()
        if lower.contains("[v0]") {
            self.kind = .base
        } else if lower.contains("[v") {
            self.kind = .update
        } else if lower.contains("dlc") || (lower.contains("[0100") && !lower.hasSuffix("800].nsp") && !lower.hasSuffix("000].nsp")) {
            self.kind = .dlc
        } else {
            self.kind = .rom
        }
    }
}
