import Foundation

// MARK: - Setup check (prerequisites for building games)
//
// Verifies everything the app depends on but does not ship itself, as nxnative's README and
// check_prereqs (scripts/build_ipa_from_nsp.py) require: macOS, Xcode 27.2 with its Metal
// toolchain, the Homebrew tools, git, the nxnative repo with its venv (Python 3.12+) and
// Python packages, and prod.keys.
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
        case installMetalToolchain
        case installHomebrewTools
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

    private static let acknowledgedIssuesKey = "setupAcknowledgedIssues"
    private var missingIDs: [String] { checks.filter { $0.status == .missing }.map(\.id).sorted() }

    /// Whether the setup sheet should open by itself at launch: something required is missing
    /// that the user has not already seen and left as it is. Missing prerequisites for building
    /// (an older macOS, no full Xcode) must not prompt at every start of someone who only plays.
    var shouldPromptAtLaunch: Bool {
        hasBlockingIssues && missingIDs != (UserDefaults.standard.stringArray(forKey: Self.acknowledgedIssuesKey) ?? [])
    }

    /// Called when the setup sheet is closed: what is still missing then is known to the user.
    func acknowledgeCurrentIssues() {
        UserDefaults.standard.set(missingIDs, forKey: Self.acknowledgedIssuesKey)
    }
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

        results.append(macOSCheck())
        let xcode = xcodeChecks()
        results.append(contentsOf: xcode.checks)
        results.append(homebrewToolsCheck())

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
        let venvPython = pythonExists ? pythonInfo(at: NXPaths.pythonPath) : nil
        let venvUsable = venvPython?.isSupported ?? false
        let minimum = "\(NXPaths.minimumPythonVersion.major).\(NXPaths.minimumPythonVersion.minor)"
        results.append(SetupCheck(
            id: "venv",
            title: tr("Python-Umgebung (venv)", "Python Environment (venv)"),
            detail: !pythonExists
                ? tr("Fehlt: \(NXPaths.venvPath)", "Missing: \(NXPaths.venvPath)")
                : venvUsable
                    ? "Python \(venvPython!.version) – venv/"
                    : tr("Python \(venvPython?.description ?? "?") – nxnative braucht Python \(minimum) oder neuer (arm64). venv neu erstellen.",
                         "Python \(venvPython?.description ?? "?") – nxnative needs Python \(minimum) or newer (arm64). Recreate the venv."),
            status: venvUsable ? .ok : .missing,
            fix: venvUsable ? nil : .createVenv))

        // Python packages
        if pythonExists {
            let missing = missingPythonPackages()
            results.append(SetupCheck(
                id: "packages",
                title: tr("Python-Pakete", "Python Packages"),
                detail: missing.isEmpty
                    ? NXPaths.requiredPythonModules.map(\.name).joined(separator: ", ")
                    : tr("Fehlt: \(missing.joined(separator: ", "))", "Missing: \(missing.joined(separator: ", "))"),
                status: missing.isEmpty ? .ok : .missing,
                fix: missing.isEmpty ? nil : .installPythonPackages))
        }

        if let metal = metalLockCheck(actual: xcode.metalVersion) { results.append(metal) }
        results.append(prodKeysCheck(exists: prodKeysExists))
        return results
    }

    private static func prodKeysCheck(exists: Bool) -> SetupCheck {
        SetupCheck(
            id: "keys",
            title: "prod.keys",
            detail: exists
                ? tr("Vorhanden", "Available")
                : tr("Nicht gefunden – die Schlüssel deiner eigenen Switch werden zum Entschlüsseln von NSP/XCI benötigt (Switch-2-Spiele als .nup oder Dump brauchen keine).",
                     "Not found – the keys from your own Switch are required to decrypt NSP/XCI (Switch 2 games as .nup or dump need none)."),
            // Only a warning: Switch 2 games build without keys; NSP/XCI builds still check for them.
            status: exists ? .ok : .warning,
            fix: exists ? nil : .chooseProdKeys)
    }

    private static func macOSCheck() -> SetupCheck {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let ok = (v.majorVersion, v.minorVersion) >= (26, 6)
        let current = "macOS \(v.majorVersion).\(v.minorVersion)"
        return SetupCheck(
            id: "macos",
            title: "macOS",
            detail: ok ? current
                : tr("\(current) – nxnative braucht macOS 26.6 oder neuer, um Spiele zu bauen.",
                     "\(current) – nxnative needs macOS 26.6 or later to build games."),
            status: ok ? .ok : .missing,
            fix: nil)
    }

    /// Full Xcode (not only the Command Line Tools) and its Metal compiler.
    /// `metalVersion` is the first line of `metal --version`, nil if the compiler does not run.
    private static func xcodeChecks() -> (checks: [SetupCheck], metalVersion: String?) {
        let selectCommand = "sudo xcode-select -s /Applications/Xcode.app"
        let path = CommandRunner.run("/usr/bin/xcode-select", ["-p"]).trimmedOutput
        let version = CommandRunner.run("/usr/bin/xcodebuild", ["-version"])
        let versionLine = version.trimmedOutput.split(separator: "\n").first.map(String.init) ?? ""
        let isFullXcode = version.succeeded && versionLine.hasPrefix("Xcode ") && !path.contains("CommandLineTools")

        let xcode: SetupCheck
        if !isFullXcode {
            xcode = SetupCheck(
                id: "xcode",
                title: "Xcode",
                detail: tr("Kein vollständiges Xcode ausgewählt (\(path.isEmpty ? "nichts" : path)). Installiere Xcode 27.2 und wähle es im Terminal aus: \(selectCommand)",
                           "No full Xcode selected (\(path.isEmpty ? "none" : path)). Install Xcode 27.2 and select it in Terminal: \(selectCommand)"),
                status: .missing,
                fix: nil)
        } else {
            let number = versionLine.dropFirst("Xcode ".count)
            let parts = number.split(separator: ".").compactMap { Int($0) }
            let tested = parts.count >= 2 && parts[0] == 27 && parts[1] == 2
            xcode = SetupCheck(
                id: "xcode",
                title: "Xcode",
                detail: tested
                    ? "\(versionLine) – \(path)"
                    : tr("\(versionLine) ausgewählt – nxnative ist mit Xcode 27.2 getestet. Bei mehreren Versionen: \(selectCommand)",
                         "\(versionLine) selected – nxnative is tested with Xcode 27.2. With several versions: \(selectCommand)"),
                status: tested ? .ok : .warning,
                fix: nil)
        }
        guard isFullXcode else { return ([xcode], nil) }

        // Xcode 26 and later install the Metal toolchain separately.
        let metal = CommandRunner.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"])
        let metalCheck = SetupCheck(
            id: "metal",
            title: tr("Metal-Toolchain", "Metal Toolchain"),
            detail: metal.succeeded
                ? (metal.trimmedOutput.split(separator: "\n").first.map(String.init) ?? "metal")
                : tr("Der Metal-Compiler läuft nicht – Installation mit „xcodebuild -downloadComponent MetalToolchain“.",
                     "The Metal compiler does not run – install it with “xcodebuild -downloadComponent MetalToolchain”."),
            status: metal.succeeded ? .ok : .missing,
            fix: metal.succeeded ? nil : .installMetalToolchain)
        let metalVersion = metal.succeeded ? metal.trimmedOutput.split(separator: "\n").first.map(String.init) : nil
        return ([xcode, metalCheck], metalVersion)
    }

    /// The shaders of NVN games are built only with the Metal compiler recorded in the repo's
    /// dmsh_chain.lock; another one stops those builds (unless --allow-other-metal).
    private static func metalLockCheck(actual: String?) -> SetupCheck? {
        guard let lock = try? String(contentsOfFile: NXPaths.shaderChainLockPath, encoding: .utf8) else { return nil }
        let expected = lock.split(separator: "\n").compactMap { line -> String? in
            let cols = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return cols.count == 2 && cols[0] == "metal_macosx" ? cols[1].trimmingCharacters(in: .whitespaces) : nil
        }.first
        guard let expected, let actual else { return nil }
        let matches = actual.trimmingCharacters(in: .whitespaces) == expected
        return SetupCheck(
            id: "metallock",
            title: tr("Metal-Compiler-Version", "Metal Compiler Version"),
            detail: matches
                ? tr("Passt zu dmsh_chain.lock", "Matches dmsh_chain.lock")
                : tr("\(actual) – nxnative erwartet \(expected). Builds von NVN-Spielen brechen damit vor den Shadern ab.",
                     "\(actual) – nxnative expects \(expected). Builds of NVN games stop before their shaders."),
            status: matches ? .ok : .warning,
            fix: nil)
    }

    /// Homebrew tools check_prereqs looks for (xcodegen only for IPA builds).
    static let homebrewTools: [(command: String, formula: String, required: Bool)] = [
        ("zstd", "zstd", true),
        ("glslangValidator", "glslang", true),
        ("xcodegen", "xcodegen", false)
    ]

    static func missingHomebrewTools() -> [(command: String, formula: String, required: Bool)] {
        homebrewTools.filter { !CommandRunner.tool("which", [$0.command]).succeeded }
    }

    private static func homebrewToolsCheck() -> SetupCheck {
        let missing = missingHomebrewTools()
        let names = homebrewTools.map(\.formula).joined(separator: ", ")
        let missingNames = missing.map(\.formula).joined(separator: " ")
        let requiredMissing = missing.contains { $0.required }
        return SetupCheck(
            id: "brew",
            title: tr("Homebrew-Tools", "Homebrew Tools"),
            detail: missing.isEmpty
                ? names
                : requiredMissing
                    ? tr("Fehlt: \(missingNames) – brew install \(missingNames)", "Missing: \(missingNames) – brew install \(missingNames)")
                    : tr("Fehlt: xcodegen – nur für IPA-Builds nötig", "Missing: xcodegen – only needed for IPA builds"),
            status: missing.isEmpty ? .ok : (requiredMissing ? .missing : .warning),
            fix: missing.isEmpty ? nil : .installHomebrewTools)
    }

    struct PythonInfo {
        let version: String
        let major: Int
        let minor: Int
        let machine: String
        var isSupported: Bool {
            (major, minor) >= NXPaths.minimumPythonVersion && machine == "arm64"
        }
        var description: String { machine == "arm64" ? version : "\(version) (\(machine))" }
    }

    /// Version and architecture of an interpreter, or nil.
    private static func pythonInfo(at executable: String) -> PythonInfo? {
        let result = CommandRunner.run(executable, ["-c", "import sys, platform; print('%d %d %s' % (sys.version_info[0], sys.version_info[1], platform.machine()))"])
        return parsePythonInfo(result)
    }

    private static func parsePythonInfo(_ result: CommandRunner.Result) -> PythonInfo? {
        guard result.succeeded else { return nil }
        let parts = result.trimmedOutput.split(separator: " ").map(String.init)
        guard parts.count == 3, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return PythonInfo(version: "\(major).\(minor)", major: major, minor: minor, machine: parts[2])
    }

    /// The newest suitable Python on the PATH (python3.15 … python3.12, then python3).
    private static func findSuitablePython() -> (name: String, info: PythonInfo)? {
        let names = (NXPaths.minimumPythonVersion.minor...20).reversed().map { "python3.\($0)" } + ["python3"]
        for name in names {
            let result = CommandRunner.tool(name, ["-c", "import sys, platform; print('%d %d %s' % (sys.version_info[0], sys.version_info[1], platform.machine()))"])
            if let info = parsePythonInfo(result), info.isSupported { return (name, info) }
        }
        return nil
    }

    /// Names of required packages the venv cannot import.
    private static func missingPythonPackages() -> [String] {
        let modules = NXPaths.requiredPythonModules.flatMap(\.modules)
        // find_spec of a dotted name imports its parent, which may not exist either.
        let script = """
        import importlib.util, sys
        def ok(m):
            try: return importlib.util.find_spec(m) is not None
            except ImportError: return False
        print(' '.join(m for m in sys.argv[1:] if not ok(m)))
        """
        let result = CommandRunner.run(NXPaths.pythonPath, ["-c", script] + modules)
        guard result.succeeded else { return NXPaths.requiredPythonModules.map(\.name) }
        let missingModules = Set(result.trimmedOutput.split(separator: " ").map(String.init))
        return NXPaths.requiredPythonModules
            .filter { req in req.modules.allSatisfy { missingModules.contains($0) } }
            .map(\.name)
    }

    // MARK: One-click fixes

    /// Creates (or recreates) `<repo>/venv` with Python 3.12+ (arm64) from the PATH and installs the packages.
    func createVenv(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            guard let python = Self.findSuitablePython() else {
                log(tr("✗ Python 3.12 oder neuer (arm64) wurde nicht gefunden. Installiere es z. B. mit „brew install python“.",
                       "✗ Python 3.12 or newer (arm64) was not found. Install it e.g. with “brew install python”."))
                return
            }
            log(tr("Python \(python.info.version) gefunden (\(python.name)) – venv wird erstellt …",
                   "Found Python \(python.info.version) (\(python.name)) – creating venv…"))
            // --clear replaces an existing venv built with an older Python.
            let venv = CommandRunner.tool(python.name, ["-m", "venv", "--clear", NXPaths.venvPath])
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

    /// Downloads the Metal toolchain (Xcode 26 and later install it separately). Takes a while.
    func installMetalToolchain(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            log(tr("Metal-Toolchain wird geladen (xcodebuild -downloadComponent MetalToolchain) …",
                   "Downloading the Metal toolchain (xcodebuild -downloadComponent MetalToolchain)…"))
            let result = CommandRunner.run("/usr/bin/xcodebuild", ["-downloadComponent", "MetalToolchain"])
            log(result.succeeded ? tr("✓ Metal-Toolchain installiert", "✓ Metal toolchain installed")
                                 : "✗ xcodebuild: \(result.trimmedOutput)")
        }
    }

    /// Installs the missing Homebrew tools with `brew install`.
    func installHomebrewTools(prodKeysExists: Bool) {
        runFix(prodKeysExists: prodKeysExists) { log in
            guard CommandRunner.tool("which", ["brew"]).succeeded else {
                log(tr("✗ Homebrew ist nicht installiert – siehe https://brew.sh", "✗ Homebrew is not installed – see https://brew.sh"))
                return
            }
            let formulas = Self.missingHomebrewTools().map(\.formula)
            guard !formulas.isEmpty else { return }
            log("brew install \(formulas.joined(separator: " ")) …")
            let result = CommandRunner.tool("brew", ["install"] + formulas)
            log(result.succeeded ? tr("✓ Homebrew-Tools installiert", "✓ Homebrew tools installed")
                                 : "✗ brew: \(result.trimmedOutput)")
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
