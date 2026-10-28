import Foundation

// MARK: - Setup check (prerequisites for building games)
//
// Verifies everything nxnative's build script needs (its README, "Install the tools"):
// macOS and Xcode versions, the Metal toolchain, Homebrew tools, .NET, the nxnative repo with
// its venv and Python packages, and prod.keys.
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
        case installBrewTools
        case downloadMetalToolchain
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
        let keysPath = AppPreferences.shared.prodKeysPath

        queue.async { [weak self] in
            let results = Self.evaluate(prodKeysPath: keysPath)
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

    private static func evaluate(prodKeysPath: String) -> [SetupCheck] {
        let fm = FileManager.default
        var results: [SetupCheck] = []

        results.append(macOSCheck())
        results.append(contentsOf: xcodeChecks())

        // git
        let git = CommandRunner.tool("git", ["--version"])
        results.append(SetupCheck(
            id: "git",
            title: "git",
            detail: git.succeeded ? git.trimmedOutput : tr("Nicht gefunden – wird mit Xcode installiert", "Not found – installed with Xcode"),
            status: git.succeeded ? .ok : .missing,
            fix: nil))

        results.append(brewToolsCheck())
        results.append(dotnetCheck())

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
            results.append(prodKeysCheck(path: prodKeysPath))
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

        // venv (Python 3.12 or newer)
        let pythonExists = fm.isExecutableFile(atPath: NXPaths.pythonPath)
        let venvVersion = pythonExists ? pythonVersion(at: NXPaths.pythonPath) : nil
        let versionOK = venvVersion.map(isSupportedPython) ?? false
        let minimum = "\(NXPaths.minimumPython.major).\(NXPaths.minimumPython.minor)"
        results.append(SetupCheck(
            id: "venv",
            title: tr("Python-Umgebung (venv)", "Python Environment (venv)"),
            detail: !pythonExists
                ? tr("Fehlt: \(NXPaths.venvPath)", "Missing: \(NXPaths.venvPath)")
                : versionOK
                    ? "Python \(venvVersion ?? "?") – venv/"
                    : tr("Python \(venvVersion ?? "?") ist zu alt – nxnative braucht \(minimum) oder neuer. venv/ in den Papierkorb legen und neu erstellen.",
                         "Python \(venvVersion ?? "?") is too old – nxnative needs \(minimum) or newer. Move venv/ to the Trash and create it again."),
            status: pythonExists && versionOK ? .ok : .missing,
            fix: pythonExists ? nil : .createVenv))

        // Python packages
        if pythonExists {
            let missing = missingPythonPackages()
            results.append(SetupCheck(
                id: "packages",
                title: tr("Python-Pakete", "Python Packages"),
                detail: missing.isEmpty
                    ? NXPaths.requiredPythonModules.map { $0.displayName }.joined(separator: ", ")
                    : tr("Fehlt: \(missing.map { $0.displayName }.joined(separator: ", "))", "Missing: \(missing.map { $0.displayName }.joined(separator: ", "))"),
                status: missing.isEmpty ? .ok : .missing,
                fix: missing.isEmpty ? nil : .installPythonPackages))
        }

        results.append(prodKeysCheck(path: prodKeysPath))
        return results
    }

    // MARK: Individual checks

    private static func macOSCheck() -> SetupCheck {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(version.majorVersion).\(version.minorVersion)"
        let minimum = NXPaths.minimumMacOS
        let ok = ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum)
        return SetupCheck(
            id: "macos",
            title: "macOS",
            detail: ok
                ? "macOS \(current)"
                : tr("macOS \(current) – nxnative verlangt macOS \(minimum.majorVersion).\(minimum.minorVersion) oder neuer.",
                     "macOS \(current) – nxnative requires macOS \(minimum.majorVersion).\(minimum.minorVersion) or later."),
            status: ok ? .ok : .missing,
            fix: nil)
    }

    /// Xcode (not only the Command Line Tools) and its Metal toolchain.
    private static func xcodeChecks() -> [SetupCheck] {
        let select = CommandRunner.run("/usr/bin/xcode-select", ["-p"])
        guard select.succeeded else {
            return [SetupCheck(
                id: "xcode",
                title: "Xcode",
                detail: tr("Nicht installiert. nxnative braucht Xcode \(NXPaths.testedXcodeVersion) aus dem App Store.",
                           "Not installed. nxnative needs Xcode \(NXPaths.testedXcodeVersion) from the App Store."),
                status: .missing,
                fix: .installCommandLineTools)]
        }

        let developerDir = select.trimmedOutput
        if developerDir.contains("CommandLineTools") {
            return [SetupCheck(
                id: "xcode",
                title: "Xcode",
                detail: tr("Nur die Command Line Tools sind aktiv (\(developerDir)). nxnative braucht das vollständige Xcode \(NXPaths.testedXcodeVersion); nach der Installation „sudo xcode-select -s /Applications/Xcode.app“ ausführen.",
                           "Only the Command Line Tools are active (\(developerDir)). nxnative needs the full Xcode \(NXPaths.testedXcodeVersion); after installing it, run “sudo xcode-select -s /Applications/Xcode.app”."),
                status: .missing,
                fix: nil)]
        }

        var results: [SetupCheck] = []
        let versionLine = CommandRunner.run("/usr/bin/xcodebuild", ["-version"]).trimmedOutput
            .split(separator: "\n").first.map(String.init) ?? "Xcode"
        let version = versionLine.replacingOccurrences(of: "Xcode", with: "").trimmingCharacters(in: .whitespaces)
        let tested = version.compare(NXPaths.testedXcodeVersion, options: .numeric) != .orderedAscending
        results.append(SetupCheck(
            id: "xcode",
            title: "Xcode",
            detail: tested
                ? versionLine
                : tr("\(versionLine) – nxnative ist mit Xcode \(NXPaths.testedXcodeVersion) getestet; ältere Versionen können Shader anders übersetzen.",
                     "\(versionLine) – nxnative is tested with Xcode \(NXPaths.testedXcodeVersion); older versions may compile shaders differently."),
            status: tested ? .ok : .warning,
            fix: nil))

        // Since Xcode 26 the Metal compiler is a separate download.
        let metal = CommandRunner.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"])
        results.append(SetupCheck(
            id: "metal",
            title: tr("Metal-Toolchain", "Metal Toolchain"),
            detail: metal.succeeded
                ? (metal.trimmedOutput.split(separator: "\n").first.map(String.init) ?? tr("Installiert", "Installed"))
                : tr("Der Metal-Compiler fehlt – er wird seit Xcode 26 separat geladen.", "The Metal compiler is missing – since Xcode 26 it is downloaded separately."),
            status: metal.succeeded ? .ok : .missing,
            fix: metal.succeeded ? nil : .downloadMetalToolchain))
        return results
    }

    private static func brewToolsCheck() -> SetupCheck {
        let missing = NXPaths.requiredBrewTools.filter { NXPaths.findExecutable($0.command) == nil }
        let brewInstalled = FileManager.default.isExecutableFile(atPath: NXPaths.brewExecutable)
        let detail: String
        if missing.isEmpty {
            detail = NXPaths.requiredBrewTools.map { $0.formula }.joined(separator: ", ")
        } else if brewInstalled {
            detail = tr("Fehlt: \(missing.map { $0.formula }.joined(separator: ", "))", "Missing: \(missing.map { $0.formula }.joined(separator: ", "))")
        } else {
            detail = tr("Homebrew (brew.sh) ist nicht installiert – es wird für \(missing.map { $0.formula }.joined(separator: ", ")) benötigt.",
                        "Homebrew (brew.sh) is not installed – it is needed for \(missing.map { $0.formula }.joined(separator: ", ")).")
        }
        return SetupCheck(
            id: "brew",
            title: tr("Homebrew-Werkzeuge", "Homebrew Tools"),
            detail: detail,
            status: missing.isEmpty ? .ok : .missing,
            fix: missing.isEmpty || !brewInstalled ? nil : .installBrewTools)
    }

    private static func prodKeysCheck(path: String) -> SetupCheck {
        let validity = ProdKeysFile.validate(path: path)
        let detail: String
        switch validity {
        case .valid:
            detail = tr("Vorhanden", "Available")
        case .missing:
            detail = tr("Nicht gefunden – die Schlüssel deiner eigenen Switch werden zum Entschlüsseln benötigt.", "Not found – the keys from your own Switch are required for decryption.")
        case .unreadable:
            detail = tr("Die Datei kann nicht gelesen werden.", "The file cannot be read.")
        case .incomplete:
            detail = tr("Die Datei enthält nicht die nötigen Schlüssel (header_key, key_area_key_application_*). Ist es wirklich die prod.keys?",
                        "The file does not contain the required keys (header_key, key_area_key_application_*). Is it really prod.keys?")
        }
        return SetupCheck(
            id: "keys",
            title: "prod.keys",
            detail: detail,
            status: validity == .valid ? .ok : .missing,
            fix: validity == .valid ? nil : .chooseProdKeys)
    }

    private static func dotnetCheck() -> SetupCheck {
        let path = NXPaths.dotnetExecutable
        return SetupCheck(
            id: "dotnet",
            title: ".NET SDK",
            detail: path ?? tr("Nicht gefunden – nxnative baut damit nx_extract zum Entpacken der Spiele. Installation: „brew install --cask dotnet-sdk“ im Terminal (fragt nach dem Administrator-Passwort).",
                               "Not found – nxnative uses it to build nx_extract, which unpacks games. Install it with “brew install --cask dotnet-sdk” in Terminal (asks for the administrator password)."),
            status: path != nil ? .ok : .missing,
            fix: nil)
    }

    /// "3.12" for the given interpreter, or nil.
    private static func pythonVersion(at executable: String) -> String? {
        let result = CommandRunner.run(executable, ["-c", "import sys; print('%d.%d' % sys.version_info[:2])"])
        return result.succeeded ? result.trimmedOutput : nil
    }

    private static func isSupportedPython(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return (parts[0], parts[1]) >= (NXPaths.minimumPython.major, NXPaths.minimumPython.minor)
    }

    /// Required packages the venv cannot import (any of a requirement's alternatives counts).
    private static func missingPythonPackages() -> [NXPaths.PythonRequirement] {
        let script = """
        import importlib.util, sys
        def found(name):
            try:
                return importlib.util.find_spec(name) is not None
            except Exception:
                return False
        print(' '.join(arg for arg in sys.argv[1:] if not any(found(m) for m in arg.split('|'))))
        """
        let requirements = NXPaths.requiredPythonModules
        let arguments = requirements.map { $0.modules.joined(separator: "|") }
        let result = CommandRunner.run(NXPaths.pythonPath, ["-c", script] + arguments)
        guard result.succeeded else { return requirements }
        let missing = Set(result.trimmedOutput.split(separator: " ").map(String.init))
        return requirements.filter { missing.contains($0.modules.joined(separator: "|")) }
    }

    // MARK: One-click fixes

    /// Creates `<repo>/venv` with a Python ≥ 3.12 from the PATH and installs the packages.
    func createVenv(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            let minimum = NXPaths.minimumPython
            let version = CommandRunner.tool("python3", ["-c", "import sys; print('%d.%d' % sys.version_info[:2]); sys.exit(0 if sys.version_info >= (\(minimum.major), \(minimum.minor)) else 1)"])
            guard version.succeeded else {
                log(tr("✗ Python \(minimum.major).\(minimum.minor) oder neuer wird benötigt (gefunden: \(version.trimmedOutput.isEmpty ? "keins" : version.trimmedOutput)). Installiere es z. B. mit „brew install python“.",
                       "✗ Python \(minimum.major).\(minimum.minor) or newer is required (found: \(version.trimmedOutput.isEmpty ? "none" : version.trimmedOutput)). Install it e.g. with “brew install python”."))
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

    /// Installs the missing Homebrew formulae (xcodegen, zstd, glslang).
    func installBrewTools(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            let formulae = NXPaths.requiredBrewTools
                .filter { NXPaths.findExecutable($0.command) == nil }
                .map { $0.formula }
            guard !formulae.isEmpty else { return }
            log(tr("brew install \(formulae.joined(separator: " ")) – das kann einige Minuten dauern …",
                   "brew install \(formulae.joined(separator: " ")) – this can take a few minutes…"))
            let result = CommandRunner.run(NXPaths.brewExecutable, ["install"] + formulae)
            log(result.succeeded ? tr("✓ Homebrew-Werkzeuge installiert", "✓ Homebrew tools installed")
                                 : "✗ brew: \(result.trimmedOutput.suffix(800))")
        }
    }

    /// Downloads Xcode's Metal toolchain (separate component since Xcode 26).
    func downloadMetalToolchain(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            log(tr("Metal-Toolchain wird geladen (xcodebuild -downloadComponent MetalToolchain) – das kann einige Minuten dauern …",
                   "Downloading the Metal toolchain (xcodebuild -downloadComponent MetalToolchain) – this can take a few minutes…"))
            let result = CommandRunner.run("/usr/bin/xcodebuild", ["-downloadComponent", "MetalToolchain"])
            log(result.succeeded ? tr("✓ Metal-Toolchain installiert", "✓ Metal toolchain installed")
                                 : "✗ xcodebuild: \(result.trimmedOutput.suffix(800))")
        }
    }

    private static func installPackages(log: (String) -> Void) {
        let packages = NXPaths.requiredPythonModules.map { $0.package }
        let names = NXPaths.requiredPythonModules.map { $0.displayName }.joined(separator: ", ")
        log(tr("Python-Pakete werden installiert: \(names) …", "Installing Python packages: \(names)…"))
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
