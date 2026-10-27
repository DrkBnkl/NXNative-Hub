import SwiftUI

// MARK: - Game profiles from the upstream repo (dm/games/<TitleID>/game.tsv)

struct NXGameBuild: Hashable {
    let tag: String
    let version: String

    /// "v131072" → 131072
    var versionNumber: Int? { Int(tag.replacingOccurrences(of: "v", with: "")) }
}

struct NXGameProfile: Hashable {
    let titleId: String
    let name: String
    let builds: [NXGameBuild]
    let defaultPackage: String?

    var requiredVersionsDescription: String {
        if builds.isEmpty { return tr("Unbekannt", "Unknown") }
        return builds.map { "\($0.version) (\($0.tag))" }.joined(separator: ", ")
    }
}

// MARK: - Compatibility status of an import candidate

enum ImportGameSupportStatus: Hashable {
    case supported(profile: NXGameProfile, activeVersionDesc: String)
    case updateRequired(profile: NXGameProfile, requiredDesc: String, foundDesc: String)
    case unsupported(reason: String)

    var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    var profile: NXGameProfile? {
        switch self {
        case let .supported(profile, _), let .updateRequired(profile, _, _): return profile
        case .unsupported: return nil
        }
    }

    var badgeColor: Color {
        switch self {
        case .supported: return .green
        case .updateRequired: return .orange
        case .unsupported: return .red
        }
    }

    var iconName: String {
        switch self {
        case .supported: return "checkmark.seal.fill"
        case .updateRequired: return "exclamationmark.triangle.fill"
        case .unsupported: return "xmark.octagon.fill"
        }
    }

    var statusTitle: String {
        switch self {
        case .supported: return tr("Unterstützt", "Supported")
        case .updateRequired: return tr("Update erforderlich", "Update Required")
        case .unsupported: return tr("Nicht unterstützt", "Unsupported")
        }
    }

    var statusDetail: String {
        switch self {
        case .supported(_, let ver):
            return ver.isEmpty
                ? tr("Offizielles nxnative-Profil vorhanden", "Official nxnative profile available")
                : "\(tr("Offizielles Profil vorhanden", "Official profile available")) (\(ver))"
        case .updateRequired(_, let req, let found):
            return "\(tr("Erfordert", "Requires")): \(req) • \(tr("Vorhanden", "Found")): \(found)"
        case .unsupported(let reason):
            return reason
        }
    }
}

// MARK: - Profile database

/// Thread safety: `reload()` and `profile(for:)` are only called from the import scan,
/// which runs serially on a background queue.
final class ProfileDatabase {
    static let shared = ProfileDatabase()

    private(set) var profiles: [String: NXGameProfile] = [:]

    init() {
        reload()
    }

    func reload() {
        let fm = FileManager.default
        var loaded: [String: NXGameProfile] = [:]

        let dirPath = NXPaths.profileDirectory
        if let items = try? fm.contentsOfDirectory(atPath: dirPath) {
            for item in items {
                guard let titleId = SwitchTitleID.normalized(item) else { continue }
                let tsvPath = "\(dirPath)/\(item)/game.tsv"
                guard let content = try? String(contentsOfFile: tsvPath, encoding: .utf8) else { continue }

                var name = item
                var builds: [NXGameBuild] = []
                var package: String?

                for line in content.components(separatedBy: .newlines) {
                    let parts = line.split(separator: "\t").map(String.init)
                    guard parts.count >= 2 else { continue }
                    switch parts[0] {
                    case "name": name = parts[1]
                    case "package": package = parts[1]
                    case "build" where parts.count >= 3: builds.append(NXGameBuild(tag: parts[1], version: parts[2]))
                    default: break
                    }
                }

                loaded[titleId] = NXGameProfile(titleId: titleId, name: name, builds: builds, defaultPackage: package)
            }
        }
        profiles = loaded
    }

    func profile(for titleId: String) -> NXGameProfile? {
        guard let clean = SwitchTitleID.normalized(titleId) else { return nil }
        if let p = profiles[clean] { return p }
        if let base = SwitchTitleID.baseID(of: clean), let p = profiles[base] { return p }
        if let legacy = SwitchTitleID.legacyBaseID(of: clean), let p = profiles[legacy] { return p }
        return nil
    }
}

// MARK: - Detect game metadata in an import folder

struct DetectedGameMeta {
    let titleId: String?
    let baseTitleId: String?
    let detectedVersions: [Int]
    let gameFiles: [URL]
}

enum GameMetaDetector {
    private static let tidRegex = try? NSRegularExpression(pattern: "\\[([0-9A-Fa-f]{16})\\]")
    private static let verRegex = try? NSRegularExpression(pattern: "(?:\\[v|[_\\.\\-])v?(\\d+)(?:\\]|\\b|_)")
    private static let tikRegex = try? NSRegularExpression(pattern: "([0-9a-fA-F]{16})[0-9a-fA-F]{16}\\.tik")

    static func detect(in folderURL: URL) -> DetectedGameMeta {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return DetectedGameMeta(titleId: nil, baseTitleId: nil, detectedVersions: [], gameFiles: [])
        }

        let gameFiles = files.filter(NXPaths.isGameFile)
        var detectedTid: String?
        var versions: Set<Int> = []

        // 1. Title ID and version from file names "[0100…][v131072]"
        for file in gameFiles {
            let name = file.lastPathComponent
            if detectedTid == nil, let tid = firstGroup(tidRegex, in: name) {
                detectedTid = tid.uppercased()
            }
            if let v = firstGroup(verRegex, in: name).flatMap({ Int($0) }) {
                versions.insert(v)
            }
        }

        // 2. Title ID from the folder name
        if detectedTid == nil, let tid = firstGroup(tidRegex, in: folderURL.lastPathComponent) {
            detectedTid = tid.uppercased()
        }

        // 3. Title ID from the ticket name in the NSP's PFS0 header
        if detectedTid == nil {
            for file in gameFiles where file.pathExtension.lowercased() == "nsp" {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }
                let data = handle.readData(ofLength: 8192)
                guard data.count >= 16, data.starts(with: [0x50, 0x46, 0x53, 0x30]), // "PFS0"
                      let str = String(data: data, encoding: .ascii),
                      let tid = firstGroup(tikRegex, in: str) else { continue }
                detectedTid = tid.uppercased()
                break
            }
        }

        let baseTid = detectedTid.flatMap { SwitchTitleID.baseID(of: $0) } ?? detectedTid

        return DetectedGameMeta(titleId: detectedTid,
                                baseTitleId: baseTid,
                                detectedVersions: versions.sorted(),
                                gameFiles: gameFiles)
    }

    private static func firstGroup(_ regex: NSRegularExpression?, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex?.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Compares detected versions with the builds listed in the profile.
    static func evaluateSupportStatus(meta: DetectedGameMeta) -> ImportGameSupportStatus {
        guard let baseTid = meta.baseTitleId else {
            return .unsupported(reason: tr("Keine Switch-Title-ID erkannt", "No Switch title ID detected"))
        }
        guard let profile = ProfileDatabase.shared.profile(for: meta.titleId ?? baseTid)
                ?? ProfileDatabase.shared.profile(for: baseTid) else {
            return .unsupported(reason: tr("Kein nxnative-Profil für ID \(baseTid) vorhanden (experimentell)",
                                           "No nxnative profile for ID \(baseTid) (experimental)"))
        }

        let profileNumbers = Set(profile.builds.compactMap(\.versionNumber))
        let foundSet = Set(meta.detectedVersions)
        let matches = foundSet.intersection(profileNumbers)

        if !matches.isEmpty {
            let desc = profile.builds
                .filter { build in build.versionNumber.map { matches.contains($0) } ?? false }
                .map { "\($0.version) (\($0.tag))" }
                .joined(separator: ", ")
            return .supported(profile: profile, activeVersionDesc: desc)
        }

        if foundSet.contains(0) && !profileNumbers.contains(0) {
            return .updateRequired(profile: profile,
                                   requiredDesc: profile.requiredVersionsDescription,
                                   foundDesc: "v0 (\(tr("Basisspiel", "Base game")))")
        }

        if !foundSet.isEmpty {
            return .updateRequired(profile: profile,
                                   requiredDesc: profile.requiredVersionsDescription,
                                   foundDesc: meta.detectedVersions.map { "v\($0)" }.joined(separator: ", "))
        }

        if profileNumbers.contains(0) {
            return .supported(profile: profile, activeVersionDesc: tr("Basisspiel", "Base game"))
        }
        return .updateRequired(profile: profile,
                               requiredDesc: profile.requiredVersionsDescription,
                               foundDesc: tr("Keine Versionsinfo erkannt", "No version info detected"))
    }
}
