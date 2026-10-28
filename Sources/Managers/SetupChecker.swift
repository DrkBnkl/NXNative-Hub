import Foundation

// MARK: - Setup check (prerequisites for building games)
//
// Verifies what nxnative's build_ipa_from_nsp.py needs but the app does not ship:
// Xcode, git, Homebrew tools (xcodegen, zstd), .NET SDK 10, the nxnative repo,
// Python 3.12+ with lz4 / capstone / fonttools / backports.zstd, and prod.keys.
// Checks run on a background queue; several issues can be fixed with one click.

struct SetupCheck: Identifiable, Equatable {
    enum Status: Equatable {
        case ok
        case warning   // optional or degraded – the app still works
        case missing   // required – building is not possible
    }

    enum Fix: Equatable {
        case chooseRepoFolder
        case chooseProdKeys
        case openXcodeInAppStore
        case installHomebrewPackages([String])
        case createVenv
        case installPythonPackages
    }

    let id: String
    let title: String
    let detail: String
    let status: Status
    let fix: Fix?
}

final class SetupChecker: ObservableObject {
    @Published private(set) var checks: [SetupCheck] = []
    @Published private(set) var isChecking = false
    @Published private(set) var isFixing = false
    @Published private(set) var fixLog: [String] = []
    @Published private(set) var lastRun: Date?

    private let queue = DispatchQueue(label: "org.nxnative.setupCheck", qos: .userInitiated)
    private var pendingCompletions: [() -> Void] = []

    /// Homebrew formulae the build script calls.
    static let homebrewTools = ["xcodegen", "zstd"]
    /// Required .NET SDK major version.
    static let requiredDotnetMajor = 10

    /// At least one required prerequisite is missing.
    var hasBlockingIssues: Bool { checks.contains { $0.status == .missing } }
    var issueCount: Int { checks.filter { $0.status != .ok }.count }
    var hasRun: Bool { lastRun != nil }

    // MARK: Running the checks

    func run(prodKeysExists: Bool, completion: (() -> Void)? = nil) {
        if let completion = completion { pendingCompletions.append(completion) }
        guard !isChecking else { return }
        isChecking = true

        queue.async { [weak self] in
            let results = Self.evaluate(prodKeysExists: prodKeysExists)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checks = results
                self.isChecking = false
                self.lastRun = Date()
                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    private static func evaluate(prodKeysExists: Bool) -> [SetupCheck] {
        var results = [xcodeCheck(), gitCheck(), homebrewToolsCheck(), dotnetCheck()]
        results += repoChecks()
        results.append(prodKeysCheck(exists: prodKeysExists))
        return results
    }

    // MARK: Tools

    private static func xcodeCheck() -> SetupCheck {
        let result = CommandRunner.run("/usr/bin/xcodebuild", ["-version"])
        let version = result.trimmedOutput.components(separatedBy: "\n").first ?? ""
        return SetupCheck(
            id: "xcode",
            title: "Xcode",
            detail: result.succeeded
                ? version
                : tr("Das vollständige Xcode wird benötigt (die Command Line Tools reichen nicht). Nach der Installation Xcode einmal starten bzw. mit „sudo xcode-select -s /Applications/Xcode.app“ auswählen.",
                     "The full Xcode is required (the Command Line Tools are not enough). After installing, launch Xcode once or select it with “sudo xcode-select -s /Applications/Xcode.app”."),
            status: result.succeeded ? .ok : .missing,
            fix: result.succeeded ? nil : .openXcodeInAppStore)
    }

    private static func gitCheck() -> SetupCheck {
        let git = CommandRunner.tool("git", ["--version"])
        return SetupCheck(
            id: "git",
            title: "git",
            detail: git.succeeded ? git.trimmedOutput : tr("Nicht gefunden – wird mit Xcode installiert", "Not found – installed with Xcode"),
            status: git.succeeded ? .ok : .missing,
            fix: nil)
    }

    private static func homebrewToolsCheck() -> SetupCheck {
        let missing = homebrewTools.filter { NXPaths.which($0) == nil }
        let hasBrew = NXPaths.which("brew") != nil
        let detail: String
        if missing.isEmpty {
            detail = homebrewTools.joined(separator: ", ")
        } else if hasBrew {
            detail = tr("Fehlt: \(missing.joined(separator: ", "))", "Missing: \(missing.joined(separator: ", "))")
        } else {
            detail = tr("Fehlt: \(missing.joined(separator: ", ")). Installiere zuerst Homebrew (brew.sh).",
                        "Missing: \(missing.joined(separator: ", ")). Install Homebrew first (brew.sh).")
        }
        return SetupCheck(
            id: "brew",
            title: tr("Homebrew-Werkzeuge", "Homebrew Tools"),
            detail: detail,
            status: missing.isEmpty ? .ok : .missing,
            fix: (missing.isEmpty || !hasBrew) ? nil : .installHomebrewPackages(missing))
    }

    private static func dotnetCheck() -> SetupCheck {
        let title = ".NET SDK \(requiredDotnetMajor)"
        let hint = tr("Installieren mit „brew install --cask dotnet-sdk“ (fragt nach dem Administratorpasswort).",
                      "Install with “brew install --cask dotnet-sdk” (asks for the administrator password).")
        guard let dotnet = NXPaths.dotnetExecutable else {
            return SetupCheck(id: "dotnet", title: title, detail: tr("Nicht gefunden. ", "Not found. ") + hint, status: .missing, fix: nil)
        }
        // Output lines look like "10.0.100 [/usr/local/share/dotnet/sdk]".
        let sdks = CommandRunner.run(dotnet, ["--list-sdks"]).output
            .split(separator: "\n")
            .compactMap { $0.split(separator: " ").first.map(String.init) }
        let suitable = sdks.filter { (Int($0.split(separator: ".").first ?? "") ?? 0) >= requiredDotnetMajor }
        return SetupCheck(
            id: "dotnet",
            title: title,
            detail: suitable.isEmpty
                ? tr("Gefunden: \(sdks.isEmpty ? "keine SDKs" : sdks.joined(separator: ", ")). ", "Found: \(sdks.isEmpty ? "no SDKs" : sdks.joined(separator: ", ")). ") + hint
                : suitable.joined(separator: ", "),
            status: suitable.isEmpty ? .missing : .ok,
            fix: nil)
    }

    // MARK: nxnative repo and Python

    private static func repoChecks() -> [SetupCheck] {
        let fm = FileManager.default
        let repo = NXPaths.repoPath
        var isDir: ObjCBool = false
        let repoExists = fm.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue
        let locationNote = NXPaths.customRepoPath != nil
            ? tr("Eigener Ordner", "Custom folder")
            : tr("Automatisch erkannt", "Detected automatically")

        var results = [SetupCheck(
            id: "repo",
            title: tr("nxnative-Ordner", "nxnative Folder"),
            detail: repoExists
                ? "\(locationNote): \(repo)"
                : tr("Nicht gefunden unter \(repo). Installiere nxnative per git clone oder wähle den Ordner aus.",
                     "Not found at \(repo). Install nxnative with git clone or choose its folder."),
            status: repoExists ? .ok : .missing,
            fix: .chooseRepoFolder)]

        guard repoExists else {
            let pending = tr("Erst den nxnative-Ordner einrichten", "Set up the nxnative folder first")
            results.append(SetupCheck(id: "script", title: tr("Build-Skript", "Build Script"), detail: pending, status: .missing, fix: nil))
            results.append(SetupCheck(id: "python", title: "Python", detail: pending, status: .missing, fix: nil))
            return results
        }

        let isGitClone = fm.fileExists(atPath: "\(repo)/.git")
        results.append(SetupCheck(
            id: "gitclone",
            title: tr("Git-Repository", "Git Repository"),
            detail: isGitClone
                ? tr("Updates über die App möglich", "Updates via the app are possible")
                : tr("Kein git clone – die Update-Funktion der App funktioniert nicht.", "Not a git clone – the app's update feature will not work."),
            status: isGitClone ? .ok : .warning,
            fix: nil))

        let scriptExists = fm.fileExists(atPath: NXPaths.buildScriptPath)
        results.append(SetupCheck(
            id: "script",
            title: tr("Build-Skript", "Build Script"),
            detail: scriptExists ? "scripts/build_ipa_from_nsp.py" : tr("Fehlt: \(NXPaths.buildScriptPath) – ist das der richtige Ordner?", "Missing: \(NXPaths.buildScriptPath) – is this the right folder?"),
            status: scriptExists ? .ok : .missing,
            fix: scriptExists ? nil : .chooseRepoFolder))

        let profileCount = ((try? fm.contentsOfDirectory(atPath: NXPaths.profileDirectory)) ?? [])
            .filter { SwitchTitleID.normalized($0) != nil }
            .count
        results.append(SetupCheck(
            id: "profiles",
            title: tr("Spielprofile", "Game Profiles"),
            detail: profileCount > 0
                ? tr("\(profileCount) Profile gefunden", "\(profileCount) profiles found")
                : tr("Keine Profile in dm/games – die Kompatibilitätsprüfung beim Import ist nicht möglich.", "No profiles in dm/games – the import compatibility check is not possible."),
            status: profileCount > 0 ? .ok : .warning,
            fix: nil))

        results += pythonChecks()
        return results
    }

    private static func pythonChecks() -> [SetupCheck] {
        let python = NXPaths.pythonPath
        let source = NXPaths.usesVenv ? "venv" : python
        let required = "\(NXPaths.minimumPython.major).\(NXPaths.minimumPython.minor)"

        guard FileManager.default.isExecutableFile(atPath: python), let version = pythonVersion(at: python) else {
            return [SetupCheck(
                id: "python", title: "Python",
                detail: tr("Kein Python gefunden. Installiere Python \(required) oder neuer, z. B. mit „brew install python“.",
                           "No Python found. Install Python \(required) or newer, e.g. with “brew install python”."),
                status: .missing, fix: nil)]
        }

        guard isSupported(version) else {
            return [SetupCheck(
                id: "python", title: "Python",
                detail: tr("Python \(version) (\(source)) ist zu alt – benötigt wird \(required) oder neuer, z. B. „brew install python“.",
                           "Python \(version) (\(source)) is too old – \(required) or newer is required, e.g. “brew install python”."),
                status: .missing,
                // An old venv can be replaced once a suitable Python is installed.
                fix: NXPaths.usesVenv ? .createVenv : nil)]
        }

        var results = [SetupCheck(id: "python", title: "Python", detail: "Python \(version) – \(source)", status: .ok, fix: nil)]

        let missing = missingPythonPackages()
        results.append(SetupCheck(
            id: "packages",
            title: tr("Python-Pakete", "Python Packages"),
            detail: missing.isEmpty
                ? tr("Vollständig", "Complete")
                : tr("Fehlt: \(missing.joined(separator: ", "))", "Missing: \(missing.joined(separator: ", "))")
                    + (NXPaths.usesVenv ? "" : tr(" – wird in einer neuen venv im nxnative-Ordner installiert.", " – will be installed into a new venv in the nxnative folder.")),
            status: missing.isEmpty ? .ok : .missing,
            // Homebrew's Python rejects pip outside a venv (PEP 668), so without a venv one is created.
            fix: missing.isEmpty ? nil : (NXPaths.usesVenv ? .installPythonPackages : .createVenv)))
        return results
    }

    private static func prodKeysCheck(exists: Bool) -> SetupCheck {
        SetupCheck(
            id: "keys",
            title: "prod.keys",
            detail: exists
                ? tr("Vorhanden", "Available")
                : tr("Nicht gefunden – die Schlüssel deiner eigenen Switch werden zum Entschlüsseln benötigt.", "Not found – the keys from your own Switch are required for decryption."),
            status: exists ? .ok : .missing,
            fix: exists ? nil : .chooseProdKeys)
    }

    // MARK: Python helpers

    /// "3.13" for the given interpreter, or nil.
    private static func pythonVersion(at executable: String) -> String? {
        let result = CommandRunner.run(executable, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
        return result.succeeded ? result.trimmedOutput : nil
    }

    private static func isSupported(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return (parts[0], parts[1]) >= (NXPaths.minimumPython.major, NXPaths.minimumPython.minor)
    }

    /// pip names of required packages the interpreter cannot import.
    private static func missingPythonPackages() -> [String] {
        let result = CommandRunner.run(NXPaths.pythonPath, ["-c", NXPaths.missingPythonModulesScript])
        guard result.succeeded else { return ["lz4", "capstone", "fonttools", "backports.zstd"] }
        return result.trimmedOutput.split(separator: " ").map(String.init)
    }

    // MARK: One-click fixes

    /// (Re)creates `<repo>/venv` with a Python ≥ 3.12 from the PATH and installs the packages.
    func createVenv(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            guard let python = NXPaths.which("python3"),
                  let version = Self.pythonVersion(at: python), Self.isSupported(version) else {
                log(tr("✗ Python \(NXPaths.minimumPython.major).\(NXPaths.minimumPython.minor) oder neuer wird benötigt. Installiere es z. B. mit „brew install python“.",
                       "✗ Python \(NXPaths.minimumPython.major).\(NXPaths.minimumPython.minor) or newer is required. Install it e.g. with “brew install python”."))
                return
            }
            log(tr("Python \(version) gefunden – venv wird erstellt …", "Found Python \(version) – creating venv…"))
            let venv = CommandRunner.run(python, ["-m", "venv", "--clear", NXPaths.venvPath])
            guard venv.succeeded else {
                log("✗ venv: \(venv.trimmedOutput)")
                return
            }
            log(tr("✓ venv erstellt", "✓ venv created"))
            Self.installPackages(log: log)
        }
    }

    func installPythonPackages(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            Self.installPackages(log: log)
        }
    }

    func installHomebrewPackages(_ packages: [String], prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            guard let brew = NXPaths.which("brew") else {
                log(tr("✗ Homebrew nicht gefunden (brew.sh)", "✗ Homebrew not found (brew.sh)"))
                return
            }
            log("brew install \(packages.joined(separator: " ")) …")
            let result = CommandRunner.run(brew, ["install"] + packages)
            log(result.succeeded ? tr("✓ Installiert", "✓ Installed") : "✗ brew: \(result.trimmedOutput)")
        }
    }

    private static func installPackages(log: (String) -> Void) {
        log(tr("Python-Pakete werden installiert …", "Installing Python packages…"))
        let pip = CommandRunner.run(NXPaths.venvPython, ["-m", "pip", "install", "--upgrade"] + NXPaths.pythonRequirements)
        log(pip.succeeded ? tr("✓ Python-Pakete installiert", "✓ Python packages installed") : "✗ pip: \(pip.trimmedOutput)")
    }

    /// Runs a fix in the background, collects its log and re-runs all checks afterwards.
    private func runFix(prodKeysExists: Bool, _ work: @escaping (_ log: (String) -> Void) -> Void) {
        guard !isFixing else { return }
        isFixing = true
        fixLog.removeAll()

        queue.async { [weak self] in
            work { line in
                DispatchQueue.main.async { self?.fixLog.appendCapped(line, limit: 500) }
            }
            DispatchQueue.main.async {
                self?.isFixing = false
                self?.run(prodKeysExists: prodKeysExists)
            }
        }
    }
}

// MARK: - Choosing the nxnative folder

extension AppPreferences {
    /// Applies a folder chosen by the user. If the user picked the parent folder
    /// (e.g. ~/NXNative), its `nxnative` subfolder is used when that contains the build script.
    func applyChosenRepoFolder(_ url: URL) {
        let fm = FileManager.default
        let script = "scripts/build_ipa_from_nsp.py"
        let nested = url.appendingPathComponent("nxnative")
        if !fm.fileExists(atPath: url.appendingPathComponent(script).path),
           fm.fileExists(atPath: nested.appendingPathComponent(script).path) {
            customRepoPath = nested.path
        } else {
            customRepoPath = url.path
        }
    }
}
