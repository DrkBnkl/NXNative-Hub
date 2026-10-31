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

    /// .NET SDK: ~/.dotnet (dotnet-install script) or the Homebrew cask (/usr/local/bin/dotnet).
    static var dotnetExecutable: String? { findExecutable("dotnet") }

    /// Homebrew on Apple Silicon (an Intel Homebrew in /usr/local is not supported by nxnative).
    static let brewExecutable = "/opt/homebrew/bin/brew"

    /// Minimum versions nxnative documents (README, "Install the tools").
    static let minimumPython = (major: 3, minor: 12)
    static let minimumMacOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
    static let testedXcodeVersion = "27.1"

    /// A Python package required by the build script.
    struct PythonRequirement {
        /// Import names; any one of them is enough (`|` alternatives, e.g. a backport).
        let modules: [String]
        /// pip requirement (may carry an environment marker).
        let package: String
        let displayName: String
    }

    static let requiredPythonModules: [PythonRequirement] = [
        PythonRequirement(modules: ["lz4.block"], package: "lz4", displayName: "lz4"),
        PythonRequirement(modules: ["capstone"], package: "capstone", displayName: "capstone"),
        PythonRequirement(modules: ["fontTools"], package: "fonttools", displayName: "fonttools"),
        // zstd is built into Python from 3.14 (compression.zstd); before that the backport is needed.
        PythonRequirement(modules: ["compression.zstd", "backports.zstd"],
                          package: "backports.zstd; python_version < '3.14'",
                          displayName: "backports.zstd"),
        // Needed for .nsz / .xcz files.
        PythonRequirement(modules: ["nsz"], package: "nsz", displayName: "nsz")
    ]

    /// Homebrew formulae and the command each one provides (checked by the build script).
    static let requiredBrewTools: [(command: String, formula: String)] = [
        ("xcodegen", "xcodegen"),
        ("zstd", "zstd"),
        ("glslangValidator", "glslang")
    ]

    /// Bug reports created with nxnative's scripts/bug_report.py
    static var reportsFolder: URL { URL(fileURLWithPath: "\(nxnativeRoot)/Reports") }
    static var bugReportScriptPath: String { "\(repoPath)/scripts/bug_report.py" }

    static func gameConfigDirectory(titleId: String) -> String { "\(appSupport)/\(titleId)" }
    static func envFilePath(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/env.txt" }
    static func saveDirectory(titleId: String) -> String { "\(gameConfigDirectory(titleId: titleId))/save" }

    /// Log of the game's last run and of the run before it (written by the Mac app's host).
    static func gameLogPath(titleId: String) -> String { "\(home)/Library/Logs/nxnative/\(titleId).log" }
    static func previousGameLogPath(titleId: String) -> String { "\(home)/Library/Logs/nxnative/\(titleId).prev.log" }

    /// Settings list a built Mac app carries (nxnative docs/frontends.md, "Settings").
    static func launcherListPath(appPath: String) -> String { "\(appPath)/Contents/Resources/dm/launcher.json" }

    /// Switches fixed by the build itself (read after the player's env.txt, before saved choices).
    static func bundleEnvFilePath(appPath: String) -> String { "\(appPath)/Contents/Resources/dm/env.txt" }

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
        env["PATH"] = (toolSearchPath + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        // Only point .NET at ~/.dotnet if it is installed there; a Homebrew cask finds its own root.
        if FileManager.default.isExecutableFile(atPath: "\(dotnetRoot)/dotnet") {
            env["DOTNET_ROOT"] = dotnetRoot
            env["DOTNET_ROOT_ARM64"] = dotnetRoot
        }
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    /// GUI apps on macOS don't inherit the login PATH: Homebrew and .dotnet are added in front.
    static var toolSearchPath: [String] {
        [dotnetRoot, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    /// First executable with that name on the tool PATH (like `which`).
    static func findExecutable(_ name: String) -> String? {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in toolSearchPath + inherited {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
