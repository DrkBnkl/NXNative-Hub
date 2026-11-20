import Foundation
import AppKit

// MARK: - Import folder & batch conversion

struct ImportGameItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let folderURL: URL
    let fileCount: Int
    let totalSizeBytes: Int64
    let fileNames: [String]
    let titleId: String?
    let baseTitleId: String?
    let supportStatus: ImportGameSupportStatus
    let source: GameSourceKind
    var isSelected: Bool

    var needsProdKeys: Bool { source.needsProdKeys }
    var isSwitch2: Bool { source.isSwitch2Source || baseTitleId.map(SwitchTitleID.isSwitch2) == true }

    var sourceDescription: String {
        switch source {
        case .nup: return tr("NUP-Container", "NUP container")
        case .dump: return tr("Dump-Ordner", "Dump folder")
        case .switch2Packages: return tr("Switch-2-NSP", "Switch 2 NSP")
        case .packages, .none: return tr("\(fileCount) Dateien", "\(fileCount) files")
        }
    }
}

final class ImportBatchManager: ObservableObject {
    let importFolderURL = NXPaths.importFolder
    let gamesFolderURL = NXPaths.gamesFolder

    @Published private(set) var pendingGames: [ImportGameItem] = []
    @Published private(set) var activeBatchGames: [ImportGameItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConverting = false
    @Published private(set) var currentGameIndex = 0
    @Published private(set) var currentGameName = ""
    @Published private(set) var currentStageText = ""
    @Published private(set) var progressPercentage: Double = 0.0
    @Published private(set) var logs: [String] = []
    /// Stages, progress and log entries of the game being converted, for the live log.
    @Published private(set) var timeline = BuildTimeline()
    @Published private(set) var conversionResults: [String: Bool] = [:]
    @Published private(set) var wasCancelled = false
    @Published var isFinished = false
    /// Opt-in: move a game's source files to the Trash after a successful conversion.
    /// Off by default, so NSP / XCI / NUP files stay in the Import folder.
    @Published var trashSourcesAfterConversion = false

    private var runner: StreamingProcess?
    private var failureTracker = BuildFailureTracker()

    /// `out` of the current game's `game` event, and the folder it is relative to.
    private var announcedOutput: URL?
    private var currentGameFolder: URL?
    private var cancelRequested = false
    /// The library's apps when the batch started, for each game's fallback icon.
    private var installedApps: [InstalledGame] = []
    private let scanQueue = DispatchQueue(label: "org.nxnative.importScan", qos: .userInitiated)

    init() {
        NXPaths.ensureDirectory(importFolderURL)
        NXPaths.ensureDirectory(gamesFolderURL)
    }

    var pendingCount: Int { pendingGames.count }
    var selectedCount: Int { pendingGames.filter(\.isSelected).count }
    var supportedCount: Int { pendingGames.filter { $0.supportStatus.isSupported }.count }
    var unsupportedCount: Int { pendingCount - supportedCount }
    /// prod.keys is only needed when a selected game comes as NSP / XCI (not for Switch 2 NUPs or dumps).
    var selectionNeedsProdKeys: Bool { pendingGames.contains { $0.isSelected && $0.needsProdKeys } }

    // MARK: Selection

    func setSelection(for id: UUID, to value: Bool) {
        if let index = pendingGames.firstIndex(where: { $0.id == id }) {
            pendingGames[index].isSelected = value
        }
    }

    func selectAll() { setAll { _ in true } }
    func selectSupportedOnly() { setAll { $0.supportStatus.isSupported } }
    func deselectAll() { setAll { _ in false } }

    private func setAll(_ rule: (ImportGameItem) -> Bool) {
        for i in pendingGames.indices {
            pendingGames[i].isSelected = rule(pendingGames[i])
        }
    }

    // MARK: Scan

    /// Scans the import folder on a background queue. Loose files are sorted into
    /// folders in the same pass (no recursive rescan, so a failed move cannot loop).
    func scanImportFolder() {
        guard !isScanning, !isConverting else { return }
        isScanning = true
        let folder = importFolderURL

        scanQueue.async { [weak self] in
            Self.sortLooseFilesIntoFolders(in: folder)
            ProfileDatabase.shared.reload()
            let found = Self.findGames(in: folder)
            DispatchQueue.main.async {
                self?.pendingGames = found
                self?.isScanning = false
                for base in Set(found.compactMap(\.baseTitleId)) {
                    NintendoIconSearch.ensureIcon(baseTitleId: base, installedApps: [])
                }
            }
        }
    }

    /// Moves loose .nsp/.xci/.nup files in the import folder into one subfolder per game.
    private static func sortLooseFilesIntoFolders(in folder: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

        for item in contents where NXPaths.isGameFile(item) {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard !isDir else { continue }
            let baseName = item.deletingPathExtension().lastPathComponent
            let folderName = baseName.components(separatedBy: " [").first ?? baseName
            let targetDir = folder.appendingPathComponent(folderName)
            try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let destination = targetDir.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                try? fm.moveItem(at: item, to: destination)
            }
        }
    }

    private static func findGames(in folder: URL) -> [ImportGameItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }

        var found: [ImportGameItem] = []
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            let meta = GameMetaDetector.detect(in: item)
            guard !meta.gameFiles.isEmpty || meta.source == .dump else { continue }

            let totalSize = meta.source == .dump
                ? DumpFolderReader.totalSize(of: item)
                : meta.gameFiles.reduce(Int64(0)) { sum, file in
                    sum + (((try? fm.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0)
                }
            let status = GameMetaDetector.evaluateSupportStatus(meta: meta)

            found.append(ImportGameItem(name: status.profile?.name ?? item.lastPathComponent,
                                        folderURL: item,
                                        fileCount: max(meta.gameFiles.count, 1),
                                        totalSizeBytes: totalSize,
                                        fileNames: meta.gameFiles.map(\.lastPathComponent),
                                        titleId: meta.titleId,
                                        baseTitleId: meta.baseTitleId,
                                        supportStatus: status,
                                        source: meta.source,
                                        isSelected: status.isSupported))
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Batch conversion

    func startBatchConversion(prodKeysPath: String, language: String, installedApps: [InstalledGame] = [],
                              onFinished: @escaping () -> Void) {
        self.installedApps = installedApps
        let toConvert = pendingGames.filter(\.isSelected)
        guard !toConvert.isEmpty, !isConverting else { return }

        activeBatchGames = toConvert
        isConverting = true
        isFinished = false
        wasCancelled = false
        cancelRequested = false
        currentGameIndex = 0
        conversionResults.removeAll()
        logs.removeAll()
        LiveLogWriter.shared.reset()
        Notifier.requestAuthorizationIfNeeded()

        convertNextGame(prodKeysPath: prodKeysPath, language: language, onFinished: onFinished)
    }

    /// Cancels the running build and does NOT start any further games.
    func cancelBatch() {
        guard isConverting else { return }
        cancelRequested = true
        appendLog(tr("⏹ Stapelumwandlung wird abgebrochen …", "⏹ Cancelling batch conversion…"))
        runner?.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.runner?.terminate()
        }
    }

    private func finishBatch(onFinished: () -> Void) {
        runner = nil
        isConverting = false
        isFinished = true
        wasCancelled = cancelRequested
        progressPercentage = 1.0
        if cancelRequested {
            appendLog(tr("⏹ Stapelumwandlung abgebrochen.", "⏹ Batch conversion cancelled."))
        } else {
            let succeeded = conversionResults.values.filter { $0 }.count
            let failed = conversionResults.count - succeeded
            Notifier.post(title: tr("Stapel-Import fertig", "Batch Import Finished"),
                          body: failed == 0
                              ? tr("\(succeeded) Spiel(e) umgewandelt.", "\(succeeded) game(s) converted.")
                              : tr("\(succeeded) umgewandelt, \(failed) fehlgeschlagen.", "\(succeeded) converted, \(failed) failed."))
        }
        onFinished()
        scanImportFolder()
    }

    private func convertNextGame(prodKeysPath: String, language: String, onFinished: @escaping () -> Void) {
        guard !cancelRequested, currentGameIndex < activeBatchGames.count else {
            finishBatch(onFinished: onFinished)
            return
        }

        let game = activeBatchGames[currentGameIndex]
        let total = activeBatchGames.count
        announcedOutput = nil
        currentGameFolder = game.folderURL
        currentGameName = game.name
        currentStageText = tr("Umwandlung wird gestartet …", "Starting conversion…")
        timeline = BuildTimeline()
        timeline.note(tr("Spiel \(currentGameIndex + 1) von \(activeBatchGames.count): \(game.name)",
                         "Game \(currentGameIndex + 1) of \(activeBatchGames.count): \(game.name)"))
        progressPercentage = Double(currentGameIndex) / Double(max(1, total))

        appendLog("")
        appendLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        appendLog("[\(currentGameIndex + 1)/\(total)] \(tr("Starte", "Starting")): \(game.name)")
        appendLog("\(tr("Ordner", "Folder")): \(game.folderURL.path)")

        let options = BuildOptions(gameDirectory: game.folderURL.path,
                                   prodKeysPath: game.needsProdKeys ? prodKeysPath : "",
                                   platform: .macApp,
                                   language: language,
                                   showFps: false,
                                   keepExtracted: false,
                                   appName: "",
                                   fallbackIcon: GameIconStore.fallbackIcon(forSource: game.folderURL.path, installedApps: installedApps))
        let arguments = options.arguments(scriptPath: NXPaths.buildScriptPath)
        // The command line makes the live log recognizable for ActiveBuildMonitor.
        appendLog("[\(tr("Befehl", "Command"))] \(arguments.joined(separator: " "))")

        let runner = StreamingProcess(executable: NXPaths.pythonPath, arguments: arguments)
        runner.onStdoutLine = { [weak self] line in self?.handleOutputLine(line) }
        failureTracker = BuildFailureTracker()
        runner.onStderrLine = { [weak self] line in
            self?.failureTracker.noteStderr(line)
            self?.timeline.consumeStderr(line)
            self?.appendLog("[stderr] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        runner.onExit = { [weak self] status in
            guard let self = self else { return }
            let success = (status == 0) && !self.cancelRequested
            self.conversionResults[game.name] = success

            self.timeline.finish(success ? .succeeded : self.cancelRequested ? .cancelled : .failed)
            if success {
                self.appendLog(tr("✓ „\(game.name)“ erfolgreich umgewandelt.", "✓ “\(game.name)” converted successfully."))
                self.moveResultAndCleanUp(game: game)
            } else if self.cancelRequested {
                self.appendLog(tr("✗ „\(game.name)“ abgebrochen – Quelldateien bleiben erhalten.", "✗ “\(game.name)” cancelled – source files kept."))
            } else {
                self.appendLog(tr("✗ Umwandlung von „\(game.name)“ fehlgeschlagen (Exit-Code \(status)).",
                                  "✗ Conversion of “\(game.name)” failed (exit code \(status))."))
                if let reason = self.failureTracker.describe(exitCode: status) {
                    self.appendLog("  \(tr("Ursache", "Reason")): \(reason)")
                }
            }

            self.currentGameIndex += 1
            self.convertNextGame(prodKeysPath: prodKeysPath, language: language, onFinished: onFinished)
        }
        self.runner = runner

        do {
            try runner.start()
        } catch {
            appendLog(tr("✗ Build-Prozess konnte nicht gestartet werden: \(error.localizedDescription)",
                         "✗ Could not start build process: \(error.localizedDescription)"))
            conversionResults[game.name] = false
            currentGameIndex += 1
            convertNextGame(prodKeysPath: prodKeysPath, language: language, onFinished: onFinished)
        }
    }

    /// Moves the finished app to ~/NXNative/Games and, if opted in, cleans up the import folder.
    ///
    /// Safety rules:
    ///  - Only the app the build announced in its `game` event is moved.
    ///  - Source files are kept unless `trashSourcesAfterConversion` is on.
    ///  - Source files are only removed if ALL produced apps were moved successfully.
    ///  - An existing app with the same name is moved to the Trash, not deleted.
    ///  - The import folder is moved to the Trash (recoverable).
    private func moveResultAndCleanUp(game: ImportGameItem) {
        let fm = FileManager.default
        let apps: [URL]
        if let out = announcedOutput {
            // Exactly the app this build wrote (the `game` event's `out`), not leftovers.
            apps = fm.fileExists(atPath: out.path) ? [out] : []
        } else {
            // Older nxnative without the `game` event.
            apps = ((try? fm.contentsOfDirectory(at: game.folderURL, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }

        guard !apps.isEmpty else {
            appendLog(tr("⚠︎ Keine .app im Ordner gefunden – Quelldateien bleiben erhalten.",
                         "⚠︎ No .app found in folder – source files kept."))
            conversionResults[game.name] = false
            return
        }

        var movedAll = true
        for app in apps {
            let destination = gamesFolderURL.appendingPathComponent(app.lastPathComponent)
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.trashItem(at: destination, resultingItemURL: nil)
                    appendLog(tr("Ältere Version in den Papierkorb gelegt: \(destination.lastPathComponent)",
                                 "Moved previous version to Trash: \(destination.lastPathComponent)"))
                }
                try fm.moveItem(at: app, to: destination)
                appendLog("\(tr("App verschoben nach", "App moved to")): \(destination.path)")
            } catch {
                movedAll = false
                appendLog(tr("⚠︎ App konnte nicht verschoben werden: \(error.localizedDescription)",
                             "⚠︎ Could not move app: \(error.localizedDescription)"))
            }
        }

        guard movedAll else {
            appendLog(tr("Quelldateien bleiben erhalten, weil nicht alle Apps verschoben wurden.",
                         "Source files kept because not all apps could be moved."))
            conversionResults[game.name] = false
            return
        }

        guard trashSourcesAfterConversion else {
            appendLog(tr("Quelldateien bleiben im Import-Ordner: \(game.folderURL.lastPathComponent)",
                         "Source files kept in Import folder: \(game.folderURL.lastPathComponent)"))
            return
        }

        do {
            try fm.trashItem(at: game.folderURL, resultingItemURL: nil)
            appendLog(tr("Import-Ordner in den Papierkorb gelegt: \(game.folderURL.lastPathComponent)",
                         "Import folder moved to Trash: \(game.folderURL.lastPathComponent)"))
        } catch {
            appendLog(tr("⚠︎ Import-Ordner konnte nicht entfernt werden: \(error.localizedDescription)",
                         "⚠︎ Could not remove import folder: \(error.localizedDescription)"))
        }
    }

    // MARK: Output

    private func handleOutputLine(_ line: String) {
        guard let event = BuildEvent.parse(line) else { return }
        timeline.consume(line)

        switch event {
        case let .stage(index, total, name, step):
            guard let name = name else { return }
            let trans = BuildStageInfo.translate(name: name, step: step ?? "")
            let counter = (index != nil && total != nil) ? "[\(index!)/\(total!)] " : ""
            currentStageText = "\(counter)\(trans.title)"
            appendLog("▶ \(counter)\(trans.title)" + ((step?.isEmpty == false) ? " · \(step!)" : ""))
            if let explanation = trans.explanation {
                appendLog("  ℹ︎ \(explanation)")
            }

        case let .step(step):
            appendLog("  ↳ \(step)")

        case let .progress(progress):
            // Overall progress = finished games + fraction of the current game.
            if let fraction = progress.fraction {
                let total = Double(max(1, activeBatchGames.count))
                progressPercentage = (Double(currentGameIndex) + min(max(fraction, 0), 1)) / total
            }
            var etaText = ""
            if let eta = progress.eta, eta > 0 {
                etaText = "\(tr("Restzeit ca.", "About")) \(BuildEvent.formatClock(eta))\(LanguageManager.shared.isGerman ? " Min." : " min left")"
            }
            if let count = progress.countText {
                let baseStage = currentStageText.components(separatedBy: " · ").first ?? currentStageText
                currentStageText = "\(baseStage) · \(count) (\(progress.percent)%)" + (etaText.isEmpty ? "" : " • \(etaText)")
            }
            if progress.shouldLogMilestone, let counts = progress.integralCounts {
                appendLog("  \(tr("Fortschritt", "Progress")): \(counts.done) / \(counts.total) (\(progress.percent)%)" + (etaText.isEmpty ? "" : " • \(etaText)"))
            }

        case let .stageEnd(name, ok, elapsed, _):
            let trans = BuildStageInfo.translate(name: name, step: "")
            appendLog("\(ok ? "✓" : "✗") \(trans.title) \(tr("fertig", "done")) (\(BuildEvent.formatElapsed(elapsed)))")

        case let .say(message):
            failureTracker.noteSay(message)
            appendLog(message)

        case let .game(info):
            announcedOutput = info.out.map {
                URL(fileURLWithPath: $0, relativeTo: currentGameFolder).standardizedFileURL
            }

        case .otherJSON:
            break

        case let .text(text):
            appendLog(text)
        }
    }

    func appendLog(_ message: String) {
        logs.appendCapped(message)
        LiveLogWriter.shared.append(message)
    }

    /// Moves one import candidate (its folder or .nup file) to the Trash and rescans.
    func moveToTrash(_ game: ImportGameItem) {
        guard !isConverting else { return }
        do {
            try FileManager.default.trashItem(at: game.folderURL, resultingItemURL: nil)
        } catch {
            NSSound.beep()
            appendLog(tr("⚠︎ Konnte nicht in den Papierkorb gelegt werden: \(error.localizedDescription)",
                         "⚠︎ Could not move to Trash: \(error.localizedDescription)"))
        }
        scanImportFolder()
    }

    func revealInFinder(_ game: ImportGameItem) {
        NSWorkspace.shared.activateFileViewerSelecting([game.folderURL])
    }

    func openImportFolderInFinder() {
        NXPaths.ensureDirectory(importFolderURL)
        NSWorkspace.shared.open(importFolderURL)
    }
}

