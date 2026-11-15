import SwiftUI

// MARK: - Game update & recompilation status

/// Visual badge for a game row in the library.
struct GameUpdateBadge: Hashable {
    let text: String
    let icon: String?
    let color: Color
}

/// Status indicating whether an nxnative update exists for a game and whether recompilation is recommended.
enum GameUpdateStatus: Hashable {
    case upToDate
    case recompileRecommended(reason: RecompileReason)
    case engineUpdateAvailable(commitCount: Int)
    case unknown(reason: String)

    enum RecompileReason: Hashable {
        case profileUpdated(commitsCount: Int, commitTitles: [String])
        case shaderChainUpdated(currentChain: String, repoChain: String)
        case profileAndShaderUpdated(commitsCount: Int, commitTitles: [String], currentChain: String, repoChain: String)
        case legacyBuild(reason: String)
    }

    var isUpdateAvailable: Bool {
        switch self {
        case .recompileRecommended, .engineUpdateAvailable:
            return true
        case .upToDate, .unknown:
            return false
        }
    }

    var isRecompileRecommended: Bool {
        switch self {
        case .recompileRecommended:
            return true
        case .engineUpdateAvailable, .upToDate, .unknown:
            return false
        }
    }

    var badge: GameUpdateBadge? {
        switch self {
        case .recompileRecommended(let reason):
            switch reason {
            case .profileUpdated:
                return GameUpdateBadge(
                    text: tr("Profil-Update", "Profile Update"),
                    icon: "sparkles",
                    color: .orange
                )
            case .shaderChainUpdated:
                return GameUpdateBadge(
                    text: tr("Shader-Update", "Shader Update"),
                    icon: "cpu",
                    color: .orange
                )
            case .profileAndShaderUpdated:
                return GameUpdateBadge(
                    text: tr("Neukompilierung empfohlen", "Recompile Recommended"),
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    color: .orange
                )
            case .legacyBuild:
                return GameUpdateBadge(
                    text: tr("Neukompilierung empfohlen", "Recompile Recommended"),
                    icon: "clock.arrow.circlepath",
                    color: .orange
                )
            }
        case .engineUpdateAvailable:
            return GameUpdateBadge(
                text: tr("nxnative-Update", "nxnative Update"),
                icon: "arrow.up.circle",
                color: .blue
            )
        case .upToDate, .unknown:
            return nil
        }
    }

    var tooltip: String {
        switch self {
        case .recompileRecommended(let reason):
            switch reason {
            case let .profileUpdated(count, _):
                return tr(
                    "Profil-Update: \(count) Änderung(en) am Spielprofil in nxnative. Neukompilierung empfohlen.",
                    "Profile update: \(count) change(s) to the game profile in nxnative. Recompilation recommended."
                )
            case let .shaderChainUpdated(current, repo):
                return tr(
                    "Shader-Update: Neue Shader-Chain (\(current) → \(repo)). Neukompilierung empfohlen.",
                    "Shader update: New shader chain (\(current) → \(repo)). Recompilation recommended."
                )
            case let .profileAndShaderUpdated(count, _, current, repo):
                return tr(
                    "Neukompilierung empfohlen: \(count) Profil-Änderung(en) und neue Shader-Chain (\(current) → \(repo)).",
                    "Recompilation recommended: \(count) profile change(s) and new shader chain (\(current) → \(repo))."
                )
            case let .legacyBuild(reason):
                return tr(
                    "Neukompilierung empfohlen: \(reason).",
                    "Recompilation recommended: \(reason)."
                )
            }
        case .engineUpdateAvailable(let count):
            return tr(
                "nxnative-Update: \(count) neue(r) Commit(s) seit dem Build. Neukompilierung optional.",
                "nxnative update: \(count) new commit(s) since the build. Recompilation optional."
            )
        case .upToDate:
            return tr("nxnative ist aktuell – keine Neukompilierung nötig.", "nxnative is up to date – no recompilation needed.")
        case .unknown(let reason):
            return reason
        }
    }

    var statusTitle: String {
        switch self {
        case .recompileRecommended:
            return tr("Neukompilierung empfohlen", "Recompilation Recommended")
        case .engineUpdateAvailable:
            return tr("nxnative-Aktualisierung verfügbar", "nxnative Update Available")
        case .upToDate:
            return tr("nxnative ist aktuell", "nxnative is Up to Date")
        case .unknown:
            return tr("Status unbekannt", "Status Unknown")
        }
    }

    var statusColor: Color {
        switch self {
        case .recompileRecommended: return .orange
        case .engineUpdateAvailable: return .blue
        case .upToDate: return .green
        case .unknown: return .secondary
        }
    }

    var statusIcon: String {
        switch self {
        case .recompileRecommended: return "exclamationmark.triangle.fill"
        case .engineUpdateAvailable: return "arrow.up.circle.fill"
        case .upToDate: return "checkmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var commitTitles: [String] {
        switch self {
        case .recompileRecommended(let reason):
            switch reason {
            case let .profileUpdated(_, titles), let .profileAndShaderUpdated(_, titles, _, _):
                return titles
            default:
                return []
            }
        default:
            return []
        }
    }
}
