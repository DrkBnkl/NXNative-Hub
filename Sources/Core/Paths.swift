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
    static var buildScriptPath: String { "\(repoPath)/scripts/build_ipa_from_nsp.py" }
    static var profileDirectory: String { "\(repoPath)/dm/games" }
    static var nxExtractProject: String { "\(repoPath)/dm/tools/nx_extract" }

    // MARK: Python

    /// Optional virtual environment inside the repo. nxnative itself does not require one,
    /// but Homebrew's Python refuses `pip install` outside a venv (PEP 668).
    static var venvPath: String { "\(repoPath)/venv" }
    static var venvPython: String { "\(venvPath)/bin/python3" }
    static var usesVenv: Bool { FileManager.default.isExecutableFile(atPath: venvPython) }

    /// Interpreter that runs the build script: the repo's venv if present, otherwise `python3` from the PATH.
    static var pythonPath: String {
        usesVenv ? venvPython : (which("python3") ?? "/usr/bin/python3")
    }

    /// Minimum Python version of build_ipa_from_nsp.py.
    static let minimumPython = (major: 3, minor: 12)

    /// pip requirement specifiers of the build script's third-party modules.
    /// `backports.zstd` is only needed before Python 3.14 (the marker lets pip decide).
    static let pythonRequirements = ["lz4", "capstone", "fonttools", "backports.zstd; python_version < \"3.14\""]

    /// Prints the pip names of missing modules (empty output = complete).
    static let missingPythonModulesScript = """
    import importlib.util, sys
    def has(name):
        try:
            return importlib.util.find_spec(name) is not None
        except ModuleNotFoundError:
            return False
    missing = [pip for module, pip in (("lz4.block", "lz4"), ("capstone", "capstone"), ("fontTools", "fonttools")) if not has(module)]
    if sys.version_info < (3, 14) and not has("backports.zstd"):
        missing.append("backports.zstd")
    print(" ".join(missing))
    """

    // MARK: .NET

    /// Locations of the `dotnet` executable (Homebrew cask, official installer, user install).
    static var dotnetCandidates: [String] {
        ["/usr/local/share/dotnet/dotnet", "/opt/homebrew/bin/dotnet", "/usr/local/bin/dotnet", "\(home)/.dotnet/dotnet"]
    }

    static var dotnetExecutable: String? {
        dotnetCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

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

    /// Directories searched for tools. GUI apps on macOS don't inherit the login PATH,
    /// so Homebrew and the .NET locations are added (same list as nxnative's TOOL_PATHS).
    static var toolSearchPath: [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/local/share/dotnet", "\(home)/.dotnet",
         "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    /// Environment for all tool invocations (Python, git, dotnet, pip).
    /// `DOTNET_ROOT` is deliberately not set: nxnative determines it itself from
    /// `dotnet --list-runtimes`, and a wrong value would break Homebrew installations.
    static func toolEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (toolSearchPath + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    /// First executable named `name` in `toolSearchPath`.
    static func which(_ name: String) -> String? {
        toolSearchPath
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
