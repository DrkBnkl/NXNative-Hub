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
    /// Stages, progress and log entries for the live log.
    @Published private(set) var timeline = BuildTimeline()
    @Published private(set) var isFinished = false
    @Published private(set) var buildSucceeded = false
    @Published private(set) var createdArtifactPath: String?
    @Published private(set) var builtPlatform: TargetPlatform = .macApp
    @Published private(set) var errorMessage: String?
    @Published private(set) var wasCancelled = false
    /// `<title ID>_build/logs` of the last build (full tool output), shown after a failure.
    @Published private(set) var buildLogsPath: String?
    /// Game directory where the build was run.
    @Published private(set) var lastGameDirectory: String?

    var buildFolders: [URL] {
        guard let dir = lastGameDirectory else { return [] }
        return BuildWorkFolder.find(in: dir)
    }

    func trashBuildFolder(_ url: URL) -> Bool {
        do {
            try BuildWorkFolder.trashFolder(at: url)
            appendLog(tr("✓ Build-Ordner in den Papierkorb gelegt: \(url.lastPathComponent)",
                         "✓ Build folder moved to Trash: \(url.lastPathComponent)"))
            return true
        } catch {
            appendLog(tr("⚠︎ Build-Ordner konnte nicht entfernt werden: \(error.localizedDescription)",
                         "⚠︎ Could not remove build folder: \(error.localizedDescription)"))
            return false
        }
    }

    private var runner: StreamingProcess?
    private var failureTracker = BuildFailureTracker()

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
        timeline = BuildTimeline()
        isFinished = false
        buildSucceeded = false
        createdArtifactPath = nil
        errorMessage = nil
        announcedOutput = nil
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
        // Without prod.keys (Switch 2 NUPs and dumps need none) there is nothing to validate.
        switch options.prodKeysPath.isEmpty ? .valid : ProdKeysFile.validate(path: options.prodKeysPath) {
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
        timeline.note(tr("nxnative-Build wird gestartet …", "Starting nxnative build…"))
        runner.onStdoutLine = { [weak self] line in self?.handleOutputLine(line) }
        runner.onStderrLine = { [weak self] line in
            self?.failureTracker.noteStderr(line)
            self?.timeline.consumeStderr(line)
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
        timeline.consume(line)

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
        lastGameDirectory = options.gameDirectory
        let gameName = URL(fileURLWithPath: options.gameDirectory).lastPathComponent

        if buildSucceeded {
            appendLog("\n" + tr("✓ Build erfolgreich beendet.", "✓ Build finished successfully."))
            timeline.finish(.succeeded)
            timeline.note(tr("Build erfolgreich beendet", "Build finished"), kind: .success)
            findOutputArtifact(gameDir: Self.outputFolder(of: options.gameDirectory), platform: options.platform)
            Notifier.post(title: tr("Build fertig", "Build Finished"),
                          body: tr("„\(gameName)“ wurde erfolgreich gebaut.", "“\(gameName)” was built successfully."))
        } else if BuildFailureTracker.wasInterrupted(exitCode) {
            wasCancelled = true
            appendLog("\n" + tr("⏹ Build abgebrochen.", "⏹ Build cancelled."))
            errorMessage = failureTracker.describe(exitCode: exitCode)
            timeline.finish(.cancelled)
            timeline.note(tr("Build abgebrochen", "Build cancelled"), kind: .warning)
        } else {
            appendLog("\n" + tr("✗ Build mit Fehler beendet (Exit-Code \(exitCode)).", "✗ Build failed (exit code \(exitCode))."))
            errorMessage = failureTracker.describe(exitCode: exitCode)
            timeline.finish(.failed)
            timeline.note(tr("Build fehlgeschlagen (Exit-Code \(exitCode))", "Build failed (exit code \(exitCode))")
                          + (errorMessage.map { ": \($0)" } ?? ""), kind: .error)
            buildLogsPath = BuildWorkFolder.logsFolder(in: options.gameDirectory)
            Notifier.post(title: tr("Build fehlgeschlagen", "Build Failed"),
                          body: "\(gameName): \(errorMessage ?? "")")
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
        timeline.note(message, kind: .error)
        isFinished = true
        buildSucceeded = false
    }

    func appendLog(_ message: String) {
        logs.appendCapped(message)
        LiveLogWriter.shared.append(message)
    }
}
