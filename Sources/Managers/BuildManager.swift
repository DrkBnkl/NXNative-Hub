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

    /// Command line for build_ipa_from_nsp.py
    func arguments(scriptPath: String) -> [String] {
        var args = [scriptPath, gameDirectory,
                    "-k", prodKeysPath,
                    "--platform", platform.rawValue,
                    "--progress", "json"]
        if !language.isEmpty { args += ["-l", language] }
        args.append(showFps ? "--show-fps" : "--no-show-fps")
        // Explicit in both directions: nxnative keeps the extracted files by default.
        args.append(keepExtracted ? "--keep-extracted" : "--no-keep-extracted")
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
    @Published private(set) var wasCancelled = false
    /// `<title ID>_build/logs` of the last build (full tool output), shown after a failure.
    @Published private(set) var buildLogsPath: String?

    private var runner: StreamingProcess?
    private var failureTracker = BuildFailureTracker()

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
        wasCancelled = false
        buildLogsPath = nil
        failureTracker = BuildFailureTracker()
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
        switch ProdKeysFile.validate(path: options.prodKeysPath) {
        case .valid:
            break
        case .missing:
            fail(tr("prod.keys nicht gefunden unter:\n\(options.prodKeysPath)", "prod.keys not found at:\n\(options.prodKeysPath)"))
            return
        case .unreadable, .incomplete:
            fail(tr("Die gewählte prod.keys enthält nicht die nötigen Schlüssel:\n\(options.prodKeysPath)",
                    "The selected prod.keys does not contain the required keys:\n\(options.prodKeysPath)"))
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
        runner.onStderrLine = { [weak self] line in
            self?.failureTracker.noteStderr(line)
            self?.appendLog("[stderr] \(line)")
        }
        runner.onExit = { [weak self] status in
            self?.handleProcessFinished(exitCode: status, options: options)
            onFinished()
        }
        self.runner = runner

        Notifier.requestAuthorizationIfNeeded()

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
            failureTracker.noteSay(message)
            appendLog(message)

        case let .otherJSON(text), let .text(text):
            appendLog(text)
        }
    }

    private func handleProcessFinished(exitCode: Int32, options: BuildOptions) {
        isRunning = false
        isFinished = true
        runner = nil
        buildSucceeded = (exitCode == 0)
        let gameName = URL(fileURLWithPath: options.gameDirectory).lastPathComponent

        if buildSucceeded {
            appendLog("\n" + tr("✓ Build erfolgreich beendet.", "✓ Build finished successfully."))
            findOutputArtifact(gameDir: options.gameDirectory, platform: options.platform)
            Notifier.post(title: tr("Build fertig", "Build Finished"),
                          body: tr("„\(gameName)“ wurde erfolgreich gebaut.", "“\(gameName)” was built successfully."))
        } else if BuildFailureTracker.wasInterrupted(exitCode) {
            wasCancelled = true
            appendLog("\n" + tr("⏹ Build abgebrochen.", "⏹ Build cancelled."))
            errorMessage = failureTracker.describe(exitCode: exitCode)
        } else {
            appendLog("\n" + tr("✗ Build mit Fehler beendet (Exit-Code \(exitCode)).", "✗ Build failed (exit code \(exitCode))."))
            errorMessage = failureTracker.describe(exitCode: exitCode)
            buildLogsPath = BuildWorkFolder.logsFolder(in: options.gameDirectory)
            Notifier.post(title: tr("Build fehlgeschlagen", "Build Failed"),
                          body: "\(gameName): \(errorMessage ?? "")")
        }
    }

    private func findOutputArtifact(gameDir: String, platform: TargetPlatform) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: gameDir),
                                                                       includingPropertiesForKeys: nil) else { return }
        switch platform {
        case .macApp:
            if let artifact = files.first(where: { $0.pathExtension == "app" }) {
                createdArtifactPath = artifact.path
                appendLog("\(tr("Erstellt", "Created")): \(artifact.lastPathComponent)")
            }
        case .macDev:
            return
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
