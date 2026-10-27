import Foundation

// MARK: - Setup check (prerequisites for building games)
//
// Verifies everything the app depends on but does not ship itself: Command Line Tools,
// git, the nxnative repo with its venv and Python packages, prod.keys and (optionally) .NET.
// Checks run on a background queue; some issues can be fixed with one click.

struct SetupCheck: Identifiable, Equatable {
    enum Status: Equatable {
        case ok
        case warning   // optional or degraded – the app still works
        case missing   // required – building is not possible
    }

    enum Fix: Equatable {
        case chooseRepoFolder
        case createVenv
        case installPythonPackages
        case installCommandLineTools
        case chooseProdKeys
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
        let fm = FileManager.default
        var results: [SetupCheck] = []

        // Xcode Command Line Tools (swiftc, codesign, git shim, metal toolchain)
        let clt = CommandRunner.run("/usr/bin/xcode-select", ["-p"])
        results.append(SetupCheck(
            id: "clt",
            title: tr("Xcode Command Line Tools", "Xcode Command Line Tools"),
            detail: clt.succeeded ? clt.trimmedOutput : tr("Nicht installiert", "Not installed"),
            status: clt.succeeded ? .ok : .missing,
            fix: clt.succeeded ? nil : .installCommandLineTools))

        // git
        let git = CommandRunner.tool("git", ["--version"])
        results.append(SetupCheck(
            id: "git",
            title: "git",
            detail: git.succeeded ? git.trimmedOutput : tr("Nicht gefunden – wird mit den Command Line Tools installiert", "Not found – installed with the Command Line Tools"),
            status: git.succeeded ? .ok : .missing,
            fix: nil))

        // nxnative folder
        let repo = NXPaths.repoPath
        var isDir: ObjCBool = false
        let repoExists = fm.fileExists(atPath: repo, isDirectory: &isDir) && isDir.boolValue
        let locationNote = NXPaths.customRepoPath != nil
            ? tr("Eigener Ordner", "Custom folder")
            : tr("Automatisch erkannt", "Detected automatically")
        results.append(SetupCheck(
            id: "repo",
            title: tr("nxnative-Ordner", "nxnative Folder"),
            detail: repoExists
                ? "\(locationNote): \(repo)"
                : tr("Nicht gefunden unter \(repo). Installiere nxnative per git clone oder wähle den Ordner aus.",
                     "Not found at \(repo). Install nxnative with git clone or choose its folder."),
            status: repoExists ? .ok : .missing,
            fix: .chooseRepoFolder))

        guard repoExists else {
            // Everything below lives inside the repo.
            let pending = tr("Erst den nxnative-Ordner einrichten", "Set up the nxnative folder first")
            results.append(SetupCheck(id: "script", title: tr("Build-Skript", "Build Script"), detail: pending, status: .missing, fix: nil))
            results.append(SetupCheck(id: "venv", title: tr("Python-Umgebung (venv)", "Python Environment (venv)"), detail: pending, status: .missing, fix: nil))
            results.append(prodKeysCheck(exists: prodKeysExists))
            results.append(dotnetCheck())
            return results
        }

        // git clone (needed by the updater)
        let isGitClone = fm.fileExists(atPath: "\(repo)/.git")
        results.append(SetupCheck(
            id: "gitclone",
            title: tr("Git-Repository", "Git Repository"),
            detail: isGitClone
                ? tr("Updates über die App möglich", "Updates via the app are possible")
                : tr("Kein git clone – die Update-Funktion der App funktioniert nicht.", "Not a git clone – the app's update feature will not work."),
            status: isGitClone ? .ok : .warning,
            fix: nil))

        // Build script
        let scriptExists = fm.fileExists(atPath: NXPaths.buildScriptPath)
        results.append(SetupCheck(
            id: "script",
            title: tr("Build-Skript", "Build Script"),
            detail: scriptExists ? "scripts/build_ipa_from_nsp.py" : tr("Fehlt: \(NXPaths.buildScriptPath) – ist das der richtige Ordner?", "Missing: \(NXPaths.buildScriptPath) – is this the right folder?"),
            status: scriptExists ? .ok : .missing,
            fix: scriptExists ? nil : .chooseRepoFolder))

        // Game profiles
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

        // venv
        let pythonExists = fm.isExecutableFile(atPath: NXPaths.pythonPath)
        results.append(SetupCheck(
            id: "venv",
            title: tr("Python-Umgebung (venv)", "Python Environment (venv)"),
            detail: pythonExists
                ? pythonVersion(at: NXPaths.pythonPath).map { "Python \($0) – venv/" } ?? "venv/"
                : tr("Fehlt: \(NXPaths.venvPath)", "Missing: \(NXPaths.venvPath)"),
            status: pythonExists ? .ok : .missing,
            fix: pythonExists ? nil : .createVenv))

        // Python packages
        if pythonExists {
            let missing = missingPythonPackages()
            results.append(SetupCheck(
                id: "packages",
                title: tr("Python-Pakete", "Python Packages"),
                detail: missing.isEmpty
                    ? NXPaths.requiredPythonModules.map { $0.package }.joined(separator: ", ")
                    : tr("Fehlt: \(missing.joined(separator: ", "))", "Missing: \(missing.joined(separator: ", "))"),
                status: missing.isEmpty ? .ok : .missing,
                fix: missing.isEmpty ? nil : .installPythonPackages))
        }

        results.append(prodKeysCheck(exists: prodKeysExists))
        results.append(dotnetCheck())
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

    private static func dotnetCheck() -> SetupCheck {
        let exists = FileManager.default.isExecutableFile(atPath: NXPaths.dotnetExecutable)
        return SetupCheck(
            id: "dotnet",
            title: tr(".NET (optional)", ".NET (optional)"),
            detail: exists
                ? NXPaths.dotnetExecutable
                : tr("Nicht unter ~/.dotnet installiert – nx_extract wird bei Updates nicht neu gebaut.", "Not installed in ~/.dotnet – nx_extract is not rebuilt during updates."),
            status: exists ? .ok : .warning,
            fix: nil)
    }

    /// "3.12" for the given interpreter, or nil.
    private static func pythonVersion(at executable: String) -> String? {
        let result = CommandRunner.run(executable, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
        return result.succeeded ? result.trimmedOutput : nil
    }

    /// pip names of required packages the venv cannot import.
    private static func missingPythonPackages() -> [String] {
        let modules = NXPaths.requiredPythonModules.map { $0.module }
        let script = "import importlib.util, sys; print(' '.join(m for m in sys.argv[1:] if importlib.util.find_spec(m) is None))"
        let result = CommandRunner.run(NXPaths.pythonPath, ["-c", script] + modules)
        guard result.succeeded else { return NXPaths.requiredPythonModules.map { $0.package } }
        let missingModules = Set(result.trimmedOutput.split(separator: " ").map(String.init))
        return NXPaths.requiredPythonModules.filter { missingModules.contains($0.module) }.map { $0.package }
    }

    // MARK: One-click fixes

    /// Creates `<repo>/venv` with a Python ≥ 3.10 from the PATH and installs the packages.
    func createVenv(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            let version = CommandRunner.tool("python3", ["-c", "import sys; print('%d.%d' % sys.version_info[:2]); sys.exit(0 if sys.version_info >= (3, 10) else 1)"])
            guard version.succeeded else {
                log(tr("✗ Python 3.10 oder neuer wird benötigt (gefunden: \(version.trimmedOutput.isEmpty ? "keins" : version.trimmedOutput)). Installiere es z. B. mit „brew install python“.",
                       "✗ Python 3.10 or newer is required (found: \(version.trimmedOutput.isEmpty ? "none" : version.trimmedOutput)). Install it e.g. with “brew install python”."))
                return
            }
            log(tr("Python \(version.trimmedOutput) gefunden – venv wird erstellt …", "Found Python \(version.trimmedOutput) – creating venv…"))
            let venv = CommandRunner.tool("python3", ["-m", "venv", NXPaths.venvPath])
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

    /// Opens Apple's installer dialog for the Command Line Tools.
    func installCommandLineTools(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            let result = CommandRunner.run("/usr/bin/xcode-select", ["--install"])
            log(result.succeeded
                ? tr("Das Installationsfenster von Apple wurde geöffnet. Nach der Installation bitte erneut prüfen.", "Apple's installer window has been opened. Check again after the installation.")
                : result.trimmedOutput)
        }
    }

    private static func installPackages(log: (String) -> Void) {
        let packages = NXPaths.requiredPythonModules.map { $0.package }
        log(tr("Python-Pakete werden installiert: \(packages.joined(separator: ", ")) …", "Installing Python packages: \(packages.joined(separator: ", "))…"))
        let pip = CommandRunner.run(NXPaths.pythonPath, ["-m", "pip", "install", "--upgrade"] + packages)
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
