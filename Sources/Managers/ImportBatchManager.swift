import Foundation
import AppKit

// MARK: - Import folder & batch conversion

struct ImportGameItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let folderURL: URL
    /// Exact source files belonging to this game (used for read-only staging and Finder reveal).
    /// Empty for dump folders, where `folderURL` itself is the dump directory.
    let sourceFiles: [URL]
    let fileCount: Int
    let totalSizeBytes: Int64
    let fileNames: [String]
    let titleId: String?
    let baseTitleId: String?
    let supportStatus: ImportGameSupportStatus
    let source: GameSourceKind
    /// True for games discovered on an external/custom import source: never modified, moved, or deleted.
    let isReadOnly: Bool
    var isSelected: Bool

    var needsProdKeys: Bool { source.needsProdKeys }
    var isSwitch2: Bool { source.isSwitch2Source || baseTitleId.map(SwitchTitleID.isSwitch2) == true }

    /// Best URL to highlight when revealing this game in Finder.
    var revealURL: URL {
        if sourceFiles.count == 1, let single = sourceFiles.first {
            return single
        }
        return sourceFiles.first ?? folderURL
    }

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

    /// Custom/external import folder (e.g. a USB stick under /Volumes). Always treated as strictly read-only.
    @Published private(set) var customImportFolderURL: URL?
    /// Currently mounted external/removable volumes detected via macOS.
    @Published private(set) var mountedExternalVolumes: [URL] = []

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
    /// Off by default, and strictly ignored whenever `isReadOnlySource` is true.
    @Published var trashSourcesAfterConversion = false

    private var runner: StreamingProcess?
    private var failureTracker = BuildFailureTracker()

    /// `out` of the current game's `game` event, and the folder it is relative to.
    private var announcedOutput: URL?
    private var currentGameFolder: URL?
    /// Temporary local staging directory (symlinks to read-only external files) for the active conversion.
    private var currentStagingFolder: URL?
    private var cancelRequested = false
    /// The library's apps when the batch started, for each game's fallback icon.
    private var installedApps: [InstalledGame] = []
    private let scanQueue = DispatchQueue(label: "org.nxnative.importScan", qos: .userInitiated)
    private var volumeObservers: [NSObjectProtocol] = []

    /// Active folder being scanned for imports.
    var activeImportFolderURL: URL { customImportFolderURL ?? importFolderURL }
    /// Any custom/external import folder is strictly read-only: no files are ever created, moved, modified, or deleted there.
    var isReadOnlySource: Bool { customImportFolderURL != nil }

    var activeSourceExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: activeImportFolderURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    var activeSourceDisplayPath: String {
        guard let custom = customImportFolderURL else { return "~/NXNative/Import" }
        return custom.path
    }

    var activeSourceShortName: String {
        guard let custom = customImportFolderURL else { return tr("Standard (~/NXNative/Import)", "Default (~/NXNative/Import)") }
        return custom.lastPathComponent.isEmpty ? custom.path : custom.lastPathComponent
    }

    init() {
        NXPaths.ensureDirectory(importFolderURL)
        NXPaths.ensureDirectory(gamesFolderURL)
        if let savedPath = UserDefaults.standard.string(forKey: NXPaths.customImportPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !savedPath.isEmpty {
            let url = URL(fileURLWithPath: savedPath).standardizedFileURL
            if url.path != importFolderURL.standardizedFileURL.path {
                customImportFolderURL = url
            }
        }
        refreshExternalVolumes()
        startObservingVolumes()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for token in volumeObservers {
            nc.removeObserver(token)
        }
    }

    /// Switches the import source. Passing `nil` (or the default ~/NXNative/Import path) returns to the default folder.
    /// Any other path activates strict read-only mode.
    func setImportSource(_ url: URL?) {
        guard !isConverting else { return }
        if let url = url?.standardizedFileURL,
           url.path != importFolderURL.standardizedFileURL.path {
            customImportFolderURL = url
            trashSourcesAfterConversion = false
            UserDefaults.standard.set(url.path, forKey: NXPaths.customImportPathKey)
        } else {
            customImportFolderURL = nil
            UserDefaults.standard.removeObject(forKey: NXPaths.customImportPathKey)
        }
        scanImportFolder()
    }

    func refreshExternalVolumes() {
        mountedExternalVolumes = Self.detectMountedExternalVolumes()
    }

    private func startObservingVolumes() {
        let nc = NSWorkspace.shared.notificationCenter
        let handler: (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.refreshExternalVolumes()
                if self.isReadOnlySource && !self.isConverting {
                    self.scanImportFolder()
                }
            }
        }
        volumeObservers.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main, using: handler))
        volumeObservers.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main, using: handler))
    }

    /// Lists mounted removable/external volumes (e.g. USB sticks and external SSDs).
    static func detectMountedExternalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.filter { url in
            let path = url.path
            guard path != "/", !path.hasPrefix("/System/") else { return false }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isInternal = values?.volumeIsInternal ?? true
            let isRemovable = values?.volumeIsRemovable ?? false
            let isEjectable = values?.volumeIsEjectable ?? false
            return !isInternal || isRemovable || isEjectable
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
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

    /// Scans the active import folder on a background queue.
    /// For the default ~/NXNative/Import folder, loose files are sorted into subfolders.
    /// For any external/custom folder, scanning is strictly read-only: no files or folders
    /// are ever created, moved, modified, or deleted.
    func scanImportFolder() {
        guard !isScanning, !isConverting else { return }
        isScanning = true
        let folder = activeImportFolderURL
        let readOnly = isReadOnlySource

        scanQueue.async { [weak self] in
            ProfileDatabase.shared.reload()
            let found: [ImportGameItem]
            if readOnly {
                found = Self.findGamesReadOnly(in: folder)
            } else {
                Self.sortLooseFilesIntoFolders(in: folder)
                found = Self.findGames(in: folder)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Only apply if the user did not switch sources while scanning.
                if self.activeImportFolderURL.standardizedFileURL == folder.standardizedFileURL {
                    self.pendingGames = found
                    for base in Set(found.compactMap(\.baseTitleId)) {
                        NintendoIconSearch.ensureIcon(baseTitleId: base, installedApps: [])
                    }
                }
                self.isScanning = false
            }
        }
    }

    /// Moves loose .nsp/.xci/.nup files in the default import folder into one subfolder per game.
    /// Never called for external/custom (read-only) sources.
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
                                        sourceFiles: meta.gameFiles,
                                        fileCount: max(meta.gameFiles.count, 1),
                                        totalSizeBytes: totalSize,
                                        fileNames: meta.gameFiles.map(\.lastPathComponent),
                                        titleId: meta.titleId,
                                        baseTitleId: meta.baseTitleId,
                                        supportStatus: status,
                                        source: meta.source,
                                        isReadOnly: false,
                                        isSelected: status.isSupported))
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static let skippedExternalDirectoryNames: Set<String> = [
        "System Volume Information",
        "$RECYCLE.BIN",
        "RECYCLER",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd"
    ]

    /// Strictly read-only scan of an external volume or custom folder.
    /// Never creates, moves, modifies, or deletes any file or directory.
    /// Recognizes loose `.nsp`/`.xci`/`.nsz`/`.xcz` (grouped in memory by title ID or name),
    /// loose `.nup` containers, Switch 2 dump folders, and nested subfolders up to depth 4.
    static func findGamesReadOnly(in root: URL, maxDepth: Int = 4) -> [ImportGameItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }

        var found: [ImportGameItem] = []
        scanReadOnlyDirectory(root, root: root, depth: 0, maxDepth: maxDepth, results: &found)
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func scanReadOnlyDirectory(_ dir: URL, root: URL, depth: Int, maxDepth: Int, results: inout [ImportGameItem]) {
        let fm = FileManager.default

        if DumpFolderReader.isDump(dir) {
            let meta = GameMetaDetector.detect(in: dir)
            let status = GameMetaDetector.evaluateSupportStatus(meta: meta)
            let totalSize = DumpFolderReader.totalSize(of: dir)
            results.append(ImportGameItem(name: status.profile?.name ?? dir.lastPathComponent,
                                          folderURL: dir,
                                          sourceFiles: [],
                                          fileCount: 1,
                                          totalSizeBytes: totalSize,
                                          fileNames: [],
                                          titleId: meta.titleId,
                                          baseTitleId: meta.baseTitleId,
                                          supportStatus: status,
                                          source: .dump,
                                          isReadOnly: true,
                                          isSelected: status.isSupported))
            return
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return
        }

        var packageFiles: [URL] = []
        var nupFiles: [URL] = []
        var subdirectories: [URL] = []

        for entry in entries {
            let name = entry.lastPathComponent
            // Skip AppleDouble resource fork files (created by macOS on exFAT/FAT USB drives) and hidden entries.
            if name.hasPrefix(".") || name.hasPrefix("._") { continue }

            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if shouldSkipExternalDirectory(entry) { continue }
                subdirectories.append(entry)
            } else {
                let ext = entry.pathExtension.lowercased()
                if ext == "nup" {
                    if NUPReader.isNUP(entry) {
                        nupFiles.append(entry)
                    }
                } else if NXPaths.isPackageFile(entry) {
                    let size = Int64(values?.fileSize ?? 0)
                    if size > 0 {
                        packageFiles.append(entry)
                    }
                }
            }
        }

        // 1. Loose .nup containers: each .nup is an independent Switch 2 game.
        for nup in nupFiles.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let meta = GameMetaDetector.detect(in: nup)
            let status = GameMetaDetector.evaluateSupportStatus(meta: meta)
            let size = (((try? fm.attributesOfItem(atPath: nup.path))?[.size] as? NSNumber)?.int64Value) ?? 0
            let fallbackName = nup.deletingPathExtension().lastPathComponent
            results.append(ImportGameItem(name: status.profile?.name ?? fallbackName,
                                          folderURL: dir,
                                          sourceFiles: [nup],
                                          fileCount: 1,
                                          totalSizeBytes: size,
                                          fileNames: [nup.lastPathComponent],
                                          titleId: meta.titleId,
                                          baseTitleId: meta.baseTitleId,
                                          supportStatus: status,
                                          source: .nup(nup),
                                          isReadOnly: true,
                                          isSelected: status.isSupported))
        }

        // 2. Package files (.nsp / .xci / .nsz / .xcz): group in memory by base title ID (or name prefix)
        //    so a flat folder on a USB stick with multiple games works without moving any files.
        if !packageFiles.isEmpty {
            let groups = groupPackageFilesInMemory(packageFiles)
            for groupFiles in groups {
                let sortedFiles = groupFiles.sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                let fallbackName: String
                if dir != root && groups.count == 1 {
                    fallbackName = dir.lastPathComponent
                } else if let first = sortedFiles.first {
                    let stem = first.deletingPathExtension().lastPathComponent
                    fallbackName = stem.components(separatedBy: " [").first?.trimmingCharacters(in: .whitespaces) ?? stem
                } else {
                    fallbackName = dir.lastPathComponent
                }

                let meta = GameMetaDetector.detect(fromPackageFiles: sortedFiles, fallbackFolderName: fallbackName)
                let status = GameMetaDetector.evaluateSupportStatus(meta: meta)
                let totalSize = sortedFiles.reduce(Int64(0)) { sum, file in
                    sum + (((try? fm.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0)
                }

                results.append(ImportGameItem(name: status.profile?.name ?? fallbackName,
                                              folderURL: dir,
                                              sourceFiles: sortedFiles,
                                              fileCount: sortedFiles.count,
                                              totalSizeBytes: totalSize,
                                              fileNames: sortedFiles.map(\.lastPathComponent),
                                              titleId: meta.titleId,
                                              baseTitleId: meta.baseTitleId,
                                              supportStatus: status,
                                              source: meta.source,
                                              isReadOnly: true,
                                              isSelected: status.isSupported))
            }
        }

        // 3. Recurse into subdirectories up to maxDepth.
        guard depth < maxDepth else { return }
        for sub in subdirectories {
            scanReadOnlyDirectory(sub, root: root, depth: depth + 1, maxDepth: maxDepth, results: &results)
        }
    }

    private static func shouldSkipExternalDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") || skippedExternalDirectoryNames.contains(name) { return true }
        let lower = name.lowercased()
        if lower.hasSuffix(".app") || lower.hasSuffix("_build") || lower.hasSuffix("_survey") { return true }
        return false
    }

    /// Groups package files in a single directory by base Title ID (or filename prefix when no ID is present).
    private static func groupPackageFilesInMemory(_ files: [URL]) -> [[URL]] {
        var buckets: [String: [URL]] = [:]
        var order: [String] = []
        for file in files {
            let key: String
            if let tid = GameMetaDetector.detectTitleId(ofPackageFile: file) {
                let base = SwitchTitleID.baseID(of: tid) ?? tid
                key = "tid:\(base)"
            } else {
                let stem = file.deletingPathExtension().lastPathComponent
                let prefix = (stem.components(separatedBy: " [").first ?? stem)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                key = "name:\(prefix)"
            }
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(file)
        }
        return order.compactMap { buckets[$0] }
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
        cleanupStagingFolder()
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

    /// Creates a local temporary staging directory containing symbolic links to the read-only
    /// external source files so `build_ipa_from_nsp.py` writes all intermediate build files and
    /// the resulting `.app` strictly on the local Mac disk—never to the external USB stick.
    private func prepareStagingFolder(for game: ImportGameItem) throws -> URL {
        let fm = FileManager.default
        let stagingRoot = NXPaths.externalImportStagingRoot
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stagingDir = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        if game.source == .dump {
            let entries = try fm.contentsOfDirectory(at: game.folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for entry in entries where !entry.lastPathComponent.hasPrefix("._") {
                let linkURL = stagingDir.appendingPathComponent(entry.lastPathComponent)
                try fm.createSymbolicLink(at: linkURL, withDestinationURL: entry)
            }
        } else {
            for file in game.sourceFiles {
                let linkURL = stagingDir.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: linkURL.path) {
                    try fm.createSymbolicLink(at: linkURL, withDestinationURL: file)
                }
            }
        }
        return stagingDir
    }

    /// Removes only the local temporary staging directory (unlinking its symlinks without ever
    /// touching the symlink targets on the external medium).
    private func cleanupStagingFolder() {
        guard let staging = currentStagingFolder else { return }
        currentStagingFolder = nil
        let rootPath = NXPaths.externalImportStagingRoot.standardizedFileURL.path + "/"
        guard staging.standardizedFileURL.path.hasPrefix(rootPath) else { return }
        try? FileManager.default.removeItem(at: staging)
    }

    private func convertNextGame(prodKeysPath: String, language: String, onFinished: @escaping () -> Void) {
        guard !cancelRequested, currentGameIndex < activeBatchGames.count else {
            finishBatch(onFinished: onFinished)
            return
        }

        let game = activeBatchGames[currentGameIndex]
        let total = activeBatchGames.count
        announcedOutput = nil
        currentStagingFolder = nil
        currentGameName = game.name
        currentStageText = tr("Umwandlung wird gestartet …", "Starting conversion…")
        timeline = BuildTimeline()
        timeline.note(tr("Spiel \(currentGameIndex + 1) von \(activeBatchGames.count): \(game.name)",
                         "Game \(currentGameIndex + 1) of \(activeBatchGames.count): \(game.name)"))
        progressPercentage = Double(currentGameIndex) / Double(max(1, total))

        appendLog("")
        appendLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        appendLog("[\(currentGameIndex + 1)/\(total)] \(tr("Starte", "Starting")): \(game.name)")
        appendLog("\(tr("Quelle", "Source")): \(game.revealURL.path)")

        let buildDirectory: URL
        if game.isReadOnly {
            do {
                let stagingDir = try prepareStagingFolder(for: game)
                currentStagingFolder = stagingDir
                buildDirectory = stagingDir
                appendLog(tr("Schreibgeschützter Modus: temporärer Arbeitsordner lokal erstellt (externes Medium wird nicht beschrieben).",
                             "Read-only mode: temporary local work folder created (external volume is never written to)."))
            } catch {
                appendLog(tr("✗ Lokaler Arbeitsordner konnte nicht vorbereitet werden: \(error.localizedDescription)",
                             "✗ Could not prepare local staging folder: \(error.localizedDescription)"))
                conversionResults[game.name] = false
                currentGameIndex += 1
                convertNextGame(prodKeysPath: prodKeysPath, language: language, onFinished: onFinished)
                return
            }
        } else {
            buildDirectory = game.folderURL
        }
        currentGameFolder = buildDirectory

        let options = BuildOptions(gameDirectory: buildDirectory.path,
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
                self.cleanupStagingFolder()
                self.appendLog(tr("✗ „\(game.name)“ abgebrochen – Quelldateien bleiben erhalten.", "✗ “\(game.name)” cancelled – source files kept."))
            } else {
                self.cleanupStagingFolder()
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
            cleanupStagingFolder()
            appendLog(tr("✗ Build-Prozess konnte nicht gestartet werden: \(error.localizedDescription)",
                         "✗ Could not start build process: \(error.localizedDescription)"))
            conversionResults[game.name] = false
            currentGameIndex += 1
            convertNextGame(prodKeysPath: prodKeysPath, language: language, onFinished: onFinished)
        }
    }

    /// Moves the finished app to ~/NXNative/Games and, if opted in (and NOT read-only),
    /// cleans up the local import folder.
    ///
    /// Safety rules:
    ///  - Read-only / external sources are NEVER modified or deleted under any circumstances.
    ///  - Only the app the build announced in its `game` event is moved.
    ///  - Source files are kept unless `trashSourcesAfterConversion` is on (default local import only).
    ///  - Source files are only removed if ALL produced apps were moved successfully.
    ///  - An existing app with the same name is moved to the Trash, not deleted.
    ///  - The local import folder is moved to the Trash (recoverable).
    private func moveResultAndCleanUp(game: ImportGameItem) {
        let fm = FileManager.default
        let searchFolder = currentStagingFolder ?? game.folderURL
        let apps: [URL]
        if let out = announcedOutput {
            // Exactly the app this build wrote (the `game` event's `out`), not leftovers.
            apps = fm.fileExists(atPath: out.path) ? [out] : []
        } else {
            // Older nxnative without the `game` event.
            apps = ((try? fm.contentsOfDirectory(at: searchFolder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }

        guard !apps.isEmpty else {
            cleanupStagingFolder()
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

        // Hard safety guard: external/read-only sources are NEVER modified or trashed.
        if game.isReadOnly || isReadOnlySource {
            cleanupStagingFolder()
            if !movedAll {
                conversionResults[game.name] = false
            }
            appendLog(tr("Externes Medium blieb unverändert (schreibgeschützter Modus).",
                         "External source remained untouched (read-only mode)."))
            return
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

    /// Moves one local import candidate to the Trash and rescans.
    /// Strictly blocked for read-only / external sources.
    func moveToTrash(_ game: ImportGameItem) {
        guard !isConverting, !game.isReadOnly, !isReadOnlySource else { return }
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
        NSWorkspace.shared.activateFileViewerSelecting([game.revealURL])
    }

    func openImportFolderInFinder() {
        if isReadOnlySource {
            // Never create directories on an external/read-only source.
            guard activeSourceExists else { return }
            NSWorkspace.shared.open(activeImportFolderURL)
        } else {
            NXPaths.ensureDirectory(importFolderURL)
            NSWorkspace.shared.open(importFolderURL)
        }
    }
}

