import Foundation

// MARK: - Central path resolution
//
// All tool, script, repo and data paths are resolved here and nowhere else.

enum NXPaths {
    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// The app's working directory (~/NXNative)
    static var nxnativeRoot: String { "\(home)/NXNative" }
    static var gamesFolder: URL { URL(fileURLWithPath: "\(nxnativeRoot)/Games") }
    static var importFolder: URL { URL(fileURLWithPath: "\(nxnativeRoot)/Import") }
    static var liveLogPath: String { "\(nxnativeRoot)/build_live.log" }
    static var dotnetRoot: String { "\(home)/.dotnet" }

    /// Configurations (env.txt) and saves per title ID
    static var appSupport: String { "\(home)/Library/Application Support/nxnative" }

    /// UserDefaults key of the nxnative folder chosen in Settings (empty = automatic).
    static let customRepoPathKey = "nxnativeCustomRepoPath"

    /// Default install location of the upstream repo (used when no custom folder is set).
    static var defaultRepoCandidates: [String] {
        ["\(nxnativeRoot)/nxnative"]
    }

    /// Folder chosen in Settings, or nil for automatic detection.
    /// Read straight from UserDefaults so it is safe to use from background queues.
    static var customRepoPath: String? {
        let value = UserDefaults.standard.string(forKey: customRepoPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// A custom folder is used exclusively; otherwise the default location.
    static var repoCandidates: [String] {
        customRepoPath.map { [$0] } ?? defaultRepoCandidates
    }

    /// The nxnative repo in use. Every other nxnative path is derived from it, so python,
    /// script and profiles always come from the same installation.
    static var repoPath: String { firstExisting(repoCandidates) }
    static var venvPath: String { "\(repoPath)/venv" }
    static var pythonPath: String { "\(venvPath)/bin/python3" }
    static var pipPath: String { "\(venvPath)/bin/pip" }
    static var buildScriptPath: String { "\(repoPath)/scripts/build_ipa_from_nsp.py" }
    static var profileDirectory: String { "\(repoPath)/dm/games" }
    static var nxExtractProject: String { "\(repoPath)/dm/tools/nx_extract" }
    static var dotnetExecutable: String { "\(dotnetRoot)/dotnet" }

    /// A Python package required by the build script.
    struct PythonRequirement {
        let module: String   // import name
        let package: String  // pip name
    }

    static let requiredPythonModules: [PythonRequirement] = [
        PythonRequirement(module: "lz4", package: "lz4"),
        PythonRequirement(module: "capstone", package: "capstone"),
        PythonRequirement(module: "fontTools", package: "fonttools"),
        PythonRequirement(module: "zstandard", package: "zstandard")
    ]

    static func gameConfigDirectory(titleId: String) -> String { "\(appSupport)/\(titleId)" }
    static func envFilePath(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/env.txt" }
    static func saveDirectory(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/save" }

    /// File extensions of Switch game files
    static let gameFileExtensions: Set<String> = ["nsp", "xci", "nsz", "xcz"]

    static func isGameFile(_ url: URL) -> Bool {
        gameFileExtensions.contains(url.pathExtension.lowercased())
    }

    /// First existing path, otherwise the last candidate (used in error messages).
    static func firstExisting(_ candidates: [String]) -> String {
        candidates.first { FileManager.default.fileExists(atPath: $0) } ?? (candidates.last ?? "")
    }

    /// Environment for all tool invocations (Python, git, dotnet, pip).
    /// GUI apps on macOS don't inherit the login PATH, so Homebrew and .dotnet are added.
    static func toolEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let dirs = [dotnetRoot, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (dirs + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        env["DOTNET_ROOT"] = dotnetRoot
        env["DOTNET_ROOT_ARM64"] = dotnetRoot
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
