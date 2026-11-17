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
    case appUpdateAvailable(reason: AppUpdateReason)
    case recompileRecommended(reason: RecompileReason)
    case engineUpdateAvailable(commitCount: Int)
    case unknown(reason: String)

    enum AppUpdateReason: Hashable {
        case engineOnly(commitsCount: Int)
        case profileNonShader(commitsCount: Int, commitTitles: [String])
        case engineAndProfile(commitsCount: Int, commitTitles: [String])
    }

    enum RecompileReason: Hashable {
        case shaderChainUpdated(currentChain: String, repoChain: String)
        case shaderProfileUpdated(commitsCount: Int, commitTitles: [String], changedFiles: [String])
        case chainAndProfileUpdated(commitsCount: Int, commitTitles: [String], currentChain: String, repoChain: String)
        case legacyBuild(reason: String)
        case profileUpdated(commitsCount: Int, commitTitles: [String])
        case profileAndShaderUpdated(commitsCount: Int, commitTitles: [String], currentChain: String, repoChain: String)
    }

    var isUpdateAvailable: Bool {
        switch self {
        case .recompileRecommended, .appUpdateAvailable, .engineUpdateAvailable:
            return true
        case .upToDate, .unknown:
            return false
        }
    }

    var isRecompileRecommended: Bool {
        switch self {
        case .recompileRecommended:
            return true
        case .appUpdateAvailable, .engineUpdateAvailable, .upToDate, .unknown:
            return false
        }
    }

    /// Whether a fast App Update is sufficient (shaders are unchanged, no recompilation needed).
    var isAppUpdateSufficient: Bool {
        switch self {
        case .appUpdateAvailable, .engineUpdateAvailable:
            return true
        case .recompileRecommended, .upToDate, .unknown:
            return false
        }
    }

    /// Whether shaders must be recompiled because the shader chain or shader definitions changed.
    var requiresShaderRecompile: Bool {
        switch self {
        case .recompileRecommended:
            return true
        case .appUpdateAvailable, .engineUpdateAvailable, .upToDate, .unknown:
            return false
        }
    }

    var badge: GameUpdateBadge? {
        switch self {
        case .appUpdateAvailable:
            return GameUpdateBadge(
                text: tr("App-Update", "App Update"),
                icon: "arrow.up.circle.fill",
                color: .blue
            )
        case .recompileRecommended(let reason):
            switch reason {
            case .shaderChainUpdated, .chainAndProfileUpdated:
                return GameUpdateBadge(
                    text: tr("Shader-Update", "Shader Update"),
                    icon: "cpu",
                    color: .orange
                )
            case .shaderProfileUpdated, .profileAndShaderUpdated:
                return GameUpdateBadge(
                    text: tr("Neukompilierung empfohlen", "Recompile Recommended"),
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    color: .orange
                )
            case .profileUpdated:
                return GameUpdateBadge(
                    text: tr("Profil-Update", "Profile Update"),
                    icon: "sparkles",
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
                text: tr("App-Update", "App Update"),
                icon: "arrow.up.circle.fill",
                color: .blue
            )
        case .upToDate, .unknown:
            return nil
        }
    }

    var tooltip: String {
        switch self {
        case .appUpdateAvailable(let reason):
            switch reason {
            case let .engineOnly(count):
                return tr(
                    "App-Update verfügbar (\(count) Engine-Commits). Shader sind aktuell – schnelles App-Update reicht aus.",
                    "App update available (\(count) engine commits). Shaders are up to date – quick app update is sufficient."
                )
            case let .profileNonShader(count, _):
                return tr(
                    "App-Update verfügbar: \(count) Änderung(en) am Spielprofil (keine Shader betroffen). Schnelles App-Update reicht aus.",
                    "App update available: \(count) profile change(s) (no shaders affected). Quick app update is sufficient."
                )
            case let .engineAndProfile(count, _):
                return tr(
                    "App-Update verfügbar: Engine- & Profil-Updates (\(count) Commits). Shader sind aktuell – schnelles App-Update reicht aus.",
                    "App update available: Engine & profile updates (\(count) commits). Shaders are up to date – quick app update is sufficient."
                )
            }
        case .recompileRecommended(let reason):
            switch reason {
            case let .shaderChainUpdated(current, repo):
                return tr(
                    "Shader-Update: Neue Shader-Chain (\(current) → \(repo)). Neukompilierung der Shader erforderlich.",
                    "Shader update: New shader chain (\(current) → \(repo)). Shader recompilation required."
                )
            case let .shaderProfileUpdated(count, _, files):
                let fileList = files.joined(separator: ", ")
                return tr(
                    "Shader-Definitionen geändert (\(fileList)). Neukompilierung der Shader empfohlen (\(count) Commits).",
                    "Shader definitions changed (\(fileList)). Shader recompilation recommended (\(count) commits)."
                )
            case let .chainAndProfileUpdated(count, _, current, repo):
                return tr(
                    "Neukompilierung empfohlen: \(count) Profil-Änderung(en) und neue Shader-Chain (\(current) → \(repo)).",
                    "Recompilation recommended: \(count) profile change(s) and new shader chain (\(current) → \(repo))."
                )
            case let .legacyBuild(reason):
                return tr(
                    "Neukompilierung empfohlen: \(reason).",
                    "Recompilation recommended: \(reason)."
                )
            case let .profileUpdated(count, _):
                return tr(
                    "Profil-Update: \(count) Änderung(en) am Spielprofil in nxnative. Neukompilierung empfohlen.",
                    "Profile update: \(count) change(s) to the game profile in nxnative. Recompilation recommended."
                )
            case let .profileAndShaderUpdated(count, _, current, repo):
                return tr(
                    "Neukompilierung empfohlen: \(count) Profil-Änderung(en) und neue Shader-Chain (\(current) → \(repo)).",
                    "Recompilation recommended: \(count) profile change(s) and new shader chain (\(current) → \(repo))."
                )
            }
        case .engineUpdateAvailable(let count):
            return tr(
                "App-Update verfügbar: \(count) neue(r) Commit(s). Shader sind aktuell – schnelles App-Update reicht aus.",
                "App update available: \(count) new commit(s). Shaders are up to date – quick app update is sufficient."
            )
        case .upToDate:
            return tr("nxnative ist aktuell – keine Aktualisierung nötig.", "nxnative is up to date – no update needed.")
        case .unknown(let reason):
            return reason
        }
    }

    var statusTitle: String {
        switch self {
        case .appUpdateAvailable, .engineUpdateAvailable:
            return tr("App-Update verfügbar (Shader aktuell)", "App Update Available (Shaders Up to Date)")
        case .recompileRecommended:
            return tr("Neukompilierung empfohlen (Shader-Update)", "Recompilation Recommended (Shader Update)")
        case .upToDate:
            return tr("nxnative ist aktuell", "nxnative is Up to Date")
        case .unknown:
            return tr("Status unbekannt", "Status Unknown")
        }
    }

    var statusColor: Color {
        switch self {
        case .appUpdateAvailable, .engineUpdateAvailable: return .blue
        case .recompileRecommended: return .orange
        case .upToDate: return .green
        case .unknown: return .secondary
        }
    }

    var statusIcon: String {
        switch self {
        case .appUpdateAvailable, .engineUpdateAvailable: return "arrow.up.circle.fill"
        case .recompileRecommended: return "exclamationmark.triangle.fill"
        case .upToDate: return "checkmark.seal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var commitTitles: [String] {
        switch self {
        case .appUpdateAvailable(let reason):
            switch reason {
            case let .profileNonShader(_, titles), let .engineAndProfile(_, titles):
                return titles
            default:
                return []
            }
        case .recompileRecommended(let reason):
            switch reason {
            case let .shaderProfileUpdated(_, titles, _):
                return titles
            case let .chainAndProfileUpdated(_, titles, _, _):
                return titles
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
