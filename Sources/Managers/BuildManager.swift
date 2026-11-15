import Foundation

// MARK: - Single build (builder page)

struct BuildOptions {
    var gameDirectory: String
    var prodKeysPath: String
    var platform: TargetPlatform
    var language: String
    var showFps: Bool
    var keepExtracted: Bool
    var appName: String

    /// Command line for build_ipa_from_nsp.py. Without prod.keys (Switch 2 NUPs and dumps
    /// need none) `-k` is left out; the script would otherwise ask for it.
    func arguments(scriptPath: String) -> [String] {
        var args = [scriptPath, gameDirectory]
        if !prodKeysPath.isEmpty { args += ["-k", prodKeysPath] }
        args += ["--platform", platform.rawValue,
                 "--progress", "json"]
        if !language.isEmpty { args += ["-l", language] }
        args.append(showFps ? "--show-fps" : "--no-show-fps")
        if keepExtracted { args.append("--keep-extracted") }
        let name = appName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { args += ["--app-name", name] }
        return args
    }
}

final class BuildManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentStageIndex = 0
    @Published private(set) var totalStages = 0
    @Published private(set) var stageName = ""
    @Published private(set) var currentStep = ""
    @Published private(set) var progressFraction: Double?
    @Published private(set) var progressText = ""
    @Published private(set) var etaText = ""
    @Published private(set) var elapsedTimeText = ""
    @Published var logs: [String] = []
    @Published private(set) var isFinished = false
    @Published private(set) var buildSucceeded = false
    @Published private(set) var createdArtifactPath: String?
    @Published private(set) var builtPlatform: TargetPlatform = .macApp
    @Published private(set) var errorMessage: String?

    private var runner: StreamingProcess?

    /// `out` of the current build's `game` event (cleared when a build starts).
    private var announcedOutput: String?

    func reset() {
        isRunning = false
        currentStageIndex = 0
        totalStages = 0
        stageName = ""
        currentStep = ""
        progressFraction = nil
        progressText = ""
        etaText = ""
        elapsedTimeText = ""
        logs.removeAll()
        isFinished = false
        buildSucceeded = false
        createdArtifactPath = nil
        errorMessage = nil
        announcedOutput = nil
    }

    func cancel() {
        guard isRunning, let runner = runner else { return }
        appendLog(tr("[Info] Abbruch angefordert …", "[Info] Cancellation requested…"))
        runner.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak runner] in
            if self?.isRunning == true { runner?.terminate() }
        }
    }

    func startBuild(options: BuildOptions, onFinished: @escaping () -> Void) {
        guard !isRunning else { return }
        reset()
        builtPlatform = options.platform

        let fm = FileManager.default
        let pythonPath = NXPaths.pythonPath
        let scriptPath = NXPaths.buildScriptPath

        guard fm.fileExists(atPath: pythonPath) else {
            fail(tr("Python-Umgebung nicht gefunden unter:\n\(pythonPath)", "Python environment not found at:\n\(pythonPath)"))
            return
        }
        guard fm.fileExists(atPath: scriptPath) else {
            fail(tr("nxnative-Skript nicht gefunden unter:\n\(scriptPath)", "nxnative script not found at:\n\(scriptPath)"))
            return
        }
        guard options.prodKeysPath.isEmpty || fm.fileExists(atPath: options.prodKeysPath) else {
            fail(tr("prod.keys nicht gefunden unter:\n\(options.prodKeysPath)", "prod.keys not found at:\n\(options.prodKeysPath)"))
            return
        }

        isRunning = true
        let arguments = options.arguments(scriptPath: scriptPath)

        // Start a fresh live log for every build.
        LiveLogWriter.shared.reset()
        appendLog(tr("[Info] nxnative-Build wird gestartet …", "[Info] Starting nxnative build…"))
        appendLog("[\(tr("Befehl", "Command"))] \(arguments.joined(separator: " "))\n")

        let runner = StreamingProcess(executable: pythonPath, arguments: arguments)
        runner.onStdoutLine = { [weak self] line in self?.handleOutputLine(line) }
        runner.onStderrLine = { [weak self] line in self?.appendLog("[Error] \(line)") }
        runner.onExit = { [weak self] status in
            self?.handleProcessFinished(exitCode: status, options: options)
            onFinished()
        }
        self.runner = runner

        do {
            try runner.start()
        } catch {
            isRunning = false
            self.runner = nil
            fail(tr("Prozess konnte nicht gestartet werden: \(error.localizedDescription)",
                    "Could not start process: \(error.localizedDescription)"))
        }
    }

    // MARK: Output handling

    private func handleOutputLine(_ line: String) {
        guard let event = BuildEvent.parse(line) else { return }

        switch event {
        case let .stage(index, total, name, step):
            if let index = index { currentStageIndex = index }
            if let total = total { totalStages = total }
            if let name = name { stageName = name }
            if let step = step { currentStep = step }
            progressFraction = nil
            progressText = ""

            let trans = BuildStageInfo.translate(name: stageName, step: currentStep)
            appendLog("▶ [\(currentStageIndex)/\(totalStages)] \(trans.title)" + (currentStep.isEmpty ? "" : " · \(currentStep)"))
            if let explanation = trans.explanation {
                appendLog("  ℹ︎ \(explanation)")
            }

        case let .step(step):
            currentStep = step
            appendLog("  ↳ \(step)")

        case let .progress(progress):
            if let step = progress.step, !step.isEmpty { currentStep = step }
            if let fraction = progress.fraction { progressFraction = fraction }
            if let count = progress.countText { progressText = count }
            if let eta = progress.eta, eta > 0 {
                etaText = "\(tr("Rest", "Remaining")): \(BuildEvent.formatClock(eta))"
            }
            if let elapsed = progress.elapsed {
                elapsedTimeText = "\(tr("Dauer", "Elapsed")): \(BuildEvent.formatClock(elapsed))"
            }
            if progress.shouldLogMilestone, let counts = progress.integralCounts {
                let etaSuffix = etaText.isEmpty ? "" : " • \(etaText)"
                appendLog("  \(tr("Fortschritt", "Progress")): \(counts.done) / \(counts.total) (\(progress.percent)%)\(etaSuffix)")
            }

        case let .stageEnd(name, ok, elapsed, summary):
            let trans = BuildStageInfo.translate(name: name, step: "")
            appendLog("\(ok ? "✓" : "✗") [\(currentStageIndex)/\(totalStages)] \(trans.title) \(tr("fertig", "done")) (\(BuildEvent.formatElapsed(elapsed))) \(summary)")

        case let .say(message):
            appendLog(message)

        case let .game(info):
            announcedOutput = info.out
            if let out = info.out { appendLog("\(tr("Ausgabe", "Output")): \(out)") }

        case let .otherJSON(text), let .text(text):
            appendLog(text)
        }
    }

    private func handleProcessFinished(exitCode: Int32, options: BuildOptions) {
        isRunning = false
        isFinished = true
        runner = nil
        buildSucceeded = (exitCode == 0)

        if buildSucceeded {
            appendLog("\n" + tr("✓ Build erfolgreich beendet.", "✓ Build finished successfully."))
            findOutputArtifact(gameDir: Self.outputFolder(of: options.gameDirectory), platform: options.platform)
        } else {
            appendLog("\n" + tr("✗ Build mit Fehler beendet (Exit-Code \(exitCode)).", "✗ Build failed (exit code \(exitCode))."))
            errorMessage = tr("Build fehlgeschlagen. Details stehen im Protokoll.", "Build failed. See the log for details.")
        }
    }

    /// The folder the build writes into: the game folder, or the folder of a .nup file given
    /// in its place.
    private static func outputFolder(of gameSource: String) -> String {
        var isDir: ObjCBool = false
        let isFile = FileManager.default.fileExists(atPath: gameSource, isDirectory: &isDir) && !isDir.boolValue
        return isFile ? (gameSource as NSString).deletingLastPathComponent : gameSource
    }

    /// Uses the exact path from the `game` event; only an older nxnative without that event
    /// falls back to the first matching bundle in the game folder.
    private func findOutputArtifact(gameDir: String, platform: TargetPlatform) {
        if let out = announcedOutput {
            let url = URL(fileURLWithPath: out, relativeTo: URL(fileURLWithPath: gameDir, isDirectory: true)).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                createdArtifactPath = url.path
                appendLog("\(tr("Erstellt", "Created")): \(url.lastPathComponent)")
            } else {
                appendLog(tr("⚠︎ Angekündigte Ausgabe nicht gefunden: \(url.path)", "⚠︎ Announced output not found: \(url.path)"))
            }
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: gameDir),
                                                                       includingPropertiesForKeys: nil) else { return }
        let wanted: String
        switch platform {
        case .macApp: wanted = "app"
        case .ios: wanted = "ipa"
        case .macDev: return
        }
        if let artifact = files.first(where: { $0.pathExtension == wanted }) {
            createdArtifactPath = artifact.path
            appendLog("\(tr("Erstellt", "Created")): \(artifact.lastPathComponent)")
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        isFinished = true
        buildSucceeded = false
    }

    func appendLog(_ message: String) {
        logs.appendCapped(message)
        LiveLogWriter.shared.append(message)
    }
}
