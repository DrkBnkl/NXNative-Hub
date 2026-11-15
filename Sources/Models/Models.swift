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

// MARK: - Game language packed at build time (-l); codes as build_ipa_from_nsp.py takes them

struct GameLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    /// Computed (not `static let`) so the names follow UI language changes.
    static var list: [GameLanguage] {
        [
            GameLanguage(code: "", name: tr("Automatisch (Spiel-Standard)", "Automatic (Game Default)")),
            GameLanguage(code: "de", name: tr("Deutsch", "German")),
            GameLanguage(code: "en-US", name: tr("Englisch (USA)", "English (US)")),
            GameLanguage(code: "en-GB", name: tr("Englisch (Großbritannien)", "English (UK)")),
            GameLanguage(code: "fr", name: tr("Französisch", "French")),
            GameLanguage(code: "fr-CA", name: tr("Französisch (Kanada)", "French (Canada)")),
            GameLanguage(code: "es", name: tr("Spanisch", "Spanish")),
            GameLanguage(code: "es-419", name: tr("Spanisch (Lateinamerika)", "Spanish (Latin America)")),
            GameLanguage(code: "it", name: tr("Italienisch", "Italian")),
            GameLanguage(code: "nl", name: tr("Niederländisch", "Dutch")),
            GameLanguage(code: "pt", name: tr("Portugiesisch", "Portuguese")),
            GameLanguage(code: "pt-BR", name: tr("Portugiesisch (Brasilien)", "Portuguese (Brazil)")),
            GameLanguage(code: "ru", name: tr("Russisch", "Russian")),
            GameLanguage(code: "ja", name: tr("Japanisch", "Japanese")),
            GameLanguage(code: "ko", name: tr("Koreanisch", "Korean")),
            GameLanguage(code: "zh-Hans", name: tr("Chinesisch (vereinfacht)", "Chinese (Simplified)")),
            GameLanguage(code: "zh-Hant", name: tr("Chinesisch (traditionell)", "Chinese (Traditional)"))
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
    /// nil if the game offers no such setting.
    var fpsTarget: String?
    var isDocked: Bool?
    var upscaling: String
    var isFullscreen: Bool
    var language: String

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }
}

/// Reads title ID, name, version and bundle ID from a converted game's Info.plist.
struct GameBundleInfo {
    let appPath: String
    let titleId: String
    let name: String
    let version: String
    /// CFBundleIdentifier: the preferences domain of the game's saved choices.
    let bundleId: String?

    /// The bundle's own env.txt (`Contents/Resources/dm/env.txt`).
    var bundleEnvFilePath: String {
        URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources/dm/env.txt").path
    }

    init?(appPath: String) {
        let plistURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let tid = plist["DMTitleID"] as? String, !tid.isEmpty else { return nil }
        self.titleId = tid
        self.name = (plist["CFBundleName"] as? String) ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        self.version = (plist["CFBundleShortVersionString"] as? String) ?? "1.0"
        self.appPath = appPath
        let bid = plist["CFBundleIdentifier"] as? String
        self.bundleId = (bid?.isEmpty == false) ? bid : nil
    }
}

// MARK: - Game file detected in the build folder

struct DetectedGameFile: Identifiable {
    enum Kind {
        case base, update, dlc, rom, nup

        var title: String {
            switch self {
            case .base: return tr("Basis", "Base")
            case .update: return "Update"
            case .dlc: return "DLC"
            case .rom: return "ROM"
            case .nup: return "NUP"
            }
        }

        var systemImage: String {
            switch self {
            case .base: return "gamecontroller.fill"
            case .update: return "arrow.triangle.2.circlepath.circle.fill"
            case .dlc: return "plus.rectangle.fill"
            case .rom: return "doc.fill"
            case .nup: return "shippingbox.fill"
            }
        }

        var color: Color {
            switch self {
            case .base: return .blue
            case .update: return .green
            case .dlc: return .purple
            case .rom: return .secondary
            case .nup: return .red
            }
        }
    }

    let id = UUID()
    let name: String
    let path: String
    let sizeFormatted: String
    let kind: Kind

    /// An entry of a Switch 2 dump folder (base/, updates/<version>/, dlc/<title ID>/);
    /// `sizeBytes` is nil while the size is still being summed.
    init(name: String, path: String, sizeBytes: Int64?, kind: Kind) {
        self.name = name
        self.path = path
        self.sizeFormatted = sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…"
        self.kind = kind
    }

    init(url: URL) {
        self.name = url.lastPathComponent
        self.path = url.path

        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        self.sizeFormatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        // Heuristic based on the common file name pattern "Name [TitleID][vXXXX].nsp"
        let lower = url.lastPathComponent.lowercased()
        if url.pathExtension.lowercased() == "nup" {
            self.kind = .nup   // base game, updates and DLC in one container
        } else if lower.contains("[v0]") {
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
