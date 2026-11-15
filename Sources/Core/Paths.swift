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
    /// Metal compiler versions the shaders were tested with (`metal_macosx` etc.).
    static var shaderChainLockPath: String { "\(repoPath)/dm/gfx/tools/dmsh_chain.lock" }

    /// A Python package required by the build script (check_prereqs in build_ipa_from_nsp.py).
    struct PythonRequirement {
        let name: String       // shown in the setup check
        let modules: [String]  // import names; any one of them is enough
        let package: String    // pip requirement
    }

    /// The build script needs Python 3.12 or newer.
    static let minimumPythonVersion = (major: 3, minor: 12)

    static let requiredPythonModules: [PythonRequirement] = [
        PythonRequirement(name: "lz4", modules: ["lz4.block"], package: "lz4"),
        PythonRequirement(name: "capstone", modules: ["capstone"], package: "capstone>=5,<6"),
        PythonRequirement(name: "fonttools", modules: ["fontTools"], package: "fonttools"),
        PythonRequirement(name: "nsz", modules: ["nsz"], package: "nsz"),
        PythonRequirement(name: "zbic", modules: ["zbic"], package: "zbic"),
        // zstd is built into Python from 3.14 (compression.zstd); before that backports.zstd.
        PythonRequirement(name: "zstd", modules: ["compression.zstd", "backports.zstd"],
                          package: "backports.zstd; python_version < '3.14'")
    ]

    static func gameConfigDirectory(titleId: String) -> String { "\(appSupport)/\(titleId)" }
    static func envFilePath(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/env.txt" }
    static func saveDirectory(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/save" }

    /// File extensions of encrypted Switch game packages (need prod.keys)
    static let packageFileExtensions: Set<String> = ["nsp", "xci", "nsz", "xcz"]
    /// All game file extensions, including the Switch 2 NUP container
    static let gameFileExtensions: Set<String> = packageFileExtensions.union(["nup"])

    static func isGameFile(_ url: URL) -> Bool {
        gameFileExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPackageFile(_ url: URL) -> Bool {
        packageFileExtensions.contains(url.pathExtension.lowercased())
    }

    /// First existing path, otherwise the last candidate (used in error messages).
    static func firstExisting(_ candidates: [String]) -> String {
        candidates.first { FileManager.default.fileExists(atPath: $0) } ?? (candidates.last ?? "")
    }

    /// Environment for all tool invocations (Python, git, pip, xcrun).
    /// GUI apps on macOS don't inherit the login PATH, so the Homebrew folders are added.
    static func toolEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (dirs + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
