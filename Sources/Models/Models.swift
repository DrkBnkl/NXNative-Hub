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
    case macDev = "mac"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macApp: return tr("Mac-App", "Mac App")
        case .macDev: return tr("Entwicklertest", "Developer Test")
        }
    }

    var subtitle: String {
        switch self {
        case .macApp: return tr("Eigenständige macOS-App (.app) – per Doppelklick spielbar.", "Standalone macOS app (.app) – double-click to play.")
        case .macDev: return tr("Direkter Start im Terminal zum Testen.", "Runs directly in Terminal for debugging.")
        }
    }

    var systemImage: String {
        switch self {
        case .macApp: return "macwindow"
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
    /// The nxnative git commit hash stamped into Info.plist (DMCommit), if recorded.
    var buildCommit: String?
    /// The shader chain version the game carries (Contents/Resources/msl/b-<chain> or DMChain).
    var shaderChain: String?
    /// Modification date of the game bundle.
    var mtime: Date
    /// Indicator whether an nxnative update exists and whether recompiling is recommended.
    var updateStatus: GameUpdateStatus

    var logPath: String { NXPaths.gameLogPath(titleId: titleId) }
    var previousLogPath: String { NXPaths.previousGameLogPath(titleId: titleId) }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

/// Reads title ID, name, version, commit and shader chain from a converted game's Info.plist and bundle.
struct GameBundleInfo {
    let titleId: String
    let name: String
    let version: String
    /// Preferences domain of the game's own launcher (saved choices), e.g. `org.nxnative.0100…`.
    let bundleId: String
    let commit: String?
    let chain: String?
    let mtime: Date

    init?(appPath: String) {
        let appURL = URL(fileURLWithPath: appPath)
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let tid = plist["DMTitleID"] as? String, !tid.isEmpty else { return nil }
        self.titleId = tid
        self.name = (plist["CFBundleName"] as? String) ?? appURL.deletingPathExtension().lastPathComponent
        self.version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        self.bundleId = (plist["CFBundleIdentifier"] as? String) ?? "org.nxnative.\(tid.lowercased())"
        self.commit = plist["DMCommit"] as? String

        var foundChain = plist["DMChain"] as? String
        if foundChain == nil {
            let mslDir = appURL.appendingPathComponent("Contents/Resources/msl")
            if let items = try? FileManager.default.contentsOfDirectory(atPath: mslDir.path) {
                for item in items where item.hasPrefix("b-") {
                    foundChain = String(item.dropFirst(2))
                    break
                }
            }
        }
        self.chain = foundChain

        let attrs = try? FileManager.default.attributesOfItem(atPath: appPath)
        self.mtime = (attrs?[.modificationDate] as? Date) ?? Date()
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
