import Foundation

// MARK: - Form state of the builder page

/// Free space check before a build. nxnative: a first build needs about twice the game's
/// size plus 10 GB; a rebuild that reuses the `<title ID>_build` folder needs much less.
struct DiskSpaceEstimate: Equatable {
    let required: Int64
    let available: Int64

    var isSufficient: Bool { available >= required }

    static let overhead: Int64 = 10 * 1_000_000_000

    static func make(gameBytes: Int64, folder: String) -> DiskSpaceEstimate? {
        guard gameBytes > 0,
              let values = try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSpaceEstimate(required: gameBytes * 2 + overhead, available: available)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Text of the "build anyway?" question asked when the space is below the estimate.
    func confirmationMessage(hasPreviousBuild: Bool) -> String {
        let free = Self.format(available)
        let needed = Self.format(required)
        return hasPreviousBuild
            ? tr("Frei sind \(free), ein erster Build braucht etwa \(needed). Ein früherer Build wird wiederverwendet, ein Neubau braucht meist deutlich weniger. nxnative bricht selbst ab, wenn der Platz nicht reicht.",
                 "\(free) is free; a first build needs about \(needed). A previous build is reused, so a rebuild usually needs much less. nxnative stops on its own if the space is not enough.")
            : tr("Frei sind \(free), der Build braucht etwa \(needed) (doppelte Spielgröße + 10 GB). Gib zuerst Speicher frei oder wähle einen Ordner auf einem anderen Laufwerk.",
                 "\(free) is free; the build needs about \(needed) (twice the game size + 10 GB). Free up space first or choose a folder on another drive.")
    }
}

final class BuilderFormModel: ObservableObject {
    @Published var gameDirectory: String = "" {
        didSet { if gameDirectory != oldValue { scanGameFolder() } }
    }
    @Published var platform: TargetPlatform = .macApp
    @Published var language: String = AppPreferences.shared.defaultGameLanguage
    @Published var showFps = false
    /// nxnative's own default: the next build of the same game reuses the extracted files.
    @Published var keepExtracted = true
    @Published var appName = ""
    @Published private(set) var detectedFiles: [DetectedGameFile] = []
    /// How the build script will read the folder (NSPs, a NUP or a dump folder).
    @Published private(set) var source: GameSourceKind = .none
    /// Title ID and profile of a detected Switch 2 game (NUP or dump folder).
    @Published private(set) var switch2TitleId: String?
    @Published private(set) var switch2Profile: NXGameProfile?

    /// Why a folder that holds game files cannot be built as it is.
    @Published private(set) var sourceHint: String?

    private let sizeQueue = DispatchQueue(label: "org.nxnative.builderSizes", qos: .utility)

    var needsProdKeys: Bool { source.needsProdKeys }
    var isSwitch2: Bool { source.isSwitch2Source }
    /// The folder already holds a `<title ID>_build` work folder: the build will be much faster.
    @Published private(set) var hasPreviousBuild = false
    @Published private(set) var diskSpace: DiskSpaceEstimate?

    func clear() {
        gameDirectory = ""
        detectedFiles.removeAll()
        resetSwitch2Info()
        hasPreviousBuild = false
        diskSpace = nil
    }

    private func resetSwitch2Info() {
        source = .none
        sourceHint = nil
        switch2TitleId = nil
        switch2Profile = nil
    }

    /// Uses a dropped folder or a dropped .nup file itself (the build script takes the file in
    /// place of its folder, whatever else lies beside it); for any other file, its folder.
    func setSource(from url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        let newDir = (isDir.boolValue || Self.isNUPFile(url)) ? url.path : url.deletingLastPathComponent().path
        if gameDirectory == newDir {
            scanGameFolder()
        } else {
            gameDirectory = newDir
        }
    }

    private static func isNUPFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "nup" && NUPReader.isNUP(url)
    }

    func scanGameFolder() {
        resetSwitch2Info()
        guard !gameDirectory.isEmpty else {
            detectedFiles = []
            hasPreviousBuild = false
            diskSpace = nil
            return
        }
        let folder = URL(fileURLWithPath: gameDirectory)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), !isDir.boolValue {
            // A .nup file given in place of the folder.
            source = Self.isNUPFile(folder) ? .nup(folder) : .none
        } else {
            source = GameSourceKind.detect(in: folder)
            if source == .none, GameSourceKind.hasSeveralNUPs(in: folder) {
                sourceHint = tr("In diesem Ordner liegen mehrere .nup-Dateien. Ziehe die gewünschte .nup-Datei hierher.",
                                "This folder holds several .nup files. Drop the one to build here.")
            }
        }

        switch source {
        case .nup(let nup):
            detectedFiles = [DetectedGameFile(url: nup)]
            applySwitch2Contents(NUPReader.read(nup))
        case .dump:
            let parts = Self.dumpParts(in: folder)
            detectedFiles = parts.map { DetectedGameFile(name: $0.name, path: $0.url.path, sizeBytes: nil, kind: $0.kind) }
            applySwitch2Contents(DumpFolderReader.read(folder))
            measureDumpParts(parts, of: gameDirectory)
        case .switch2Packages(let files):
            detectedFiles = files.map(DetectedGameFile.init(url:))
            switch2TitleId = GameSourceKind.switch2TitleID(in: files).flatMap { SwitchTitleID.baseID(of: $0) }
            switch2Profile = switch2TitleId.flatMap { ProfileDatabase.shared.profile(for: $0) }
        case .packages, .none:
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            detectedFiles = files
                .filter(NXPaths.isPackageFile)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map(DetectedGameFile.init(url:))
        }
        updateBuildEstimates()
    }

    /// The folder the build works in: the game folder, or the folder of a .nup file given in its place.
    private var workFolder: String {
        if case .nup(let nup) = source, nup.path == gameDirectory { return nup.deletingLastPathComponent().path }
        return gameDirectory
    }

    private func updateBuildEstimates() {
        hasPreviousBuild = !BuildWorkFolder.find(in: workFolder).isEmpty
        diskSpace = DiskSpaceEstimate.make(gameBytes: detectedFiles.reduce(0) { $0 + $1.sizeBytes }, folder: workFolder)
    }

    private func applySwitch2Contents(_ contents: GameSourceContents?) {
        switch2TitleId = contents?.titleId.flatMap { SwitchTitleID.baseID(of: $0) }
        switch2Profile = switch2TitleId.flatMap { ProfileDatabase.shared.profile(for: $0) }
    }

    private typealias DumpPart = (name: String, url: URL, kind: DetectedGameFile.Kind, measured: [URL])

    /// base/, updates/<version>/ and dlc/<title ID>/ of a dump folder as rows.
    private static func dumpParts(in folder: URL) -> [DumpPart] {
        var parts: [DumpPart] = []
        if let base = DumpFolderReader.baseFolder(in: folder) {
            // exefs/ and romfs/ directly in the folder count as base/.
            let measured = base == folder ? ["exefs", "romfs"].map(folder.appendingPathComponent) : [base]
            parts.append((base == folder ? "exefs, romfs" : "base", base, .base, measured))
        }
        for update in DumpFolderReader.updateFolders(in: folder)
            .sorted(by: { (Int($0.lastPathComponent) ?? 0) < (Int($1.lastPathComponent) ?? 0) }) {
            parts.append(("updates/\(update.lastPathComponent)", update, .update, [update]))
        }
        let dlcItems = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("dlc"),
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [.skipsHiddenFiles])) ?? []
        for dlc in dlcItems.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            parts.append(("dlc/\(dlc.lastPathComponent)", dlc, .dlc, [dlc]))
        }
        return parts
    }

    /// Sums the sizes off the main thread (a dump holds many thousands of files) and fills
    /// them in if the folder is still the chosen one.
    private func measureDumpParts(_ parts: [DumpPart], of directory: String) {
        sizeQueue.async { [weak self] in
            let measured = parts.map { part in
                DetectedGameFile(name: part.name, path: part.url.path,
                                 sizeBytes: part.measured.reduce(Int64(0)) { $0 + DumpFolderReader.totalSize(of: $1) },
                                 kind: part.kind)
            }
            DispatchQueue.main.async {
                guard let self, self.gameDirectory == directory, self.source == .dump else { return }
                self.detectedFiles = measured
                self.updateBuildEstimates()
            }
        }
    }

    func canStart(manager: BuildManager, monitor: ActiveBuildMonitor, prefs: AppPreferences) -> Bool {
        !manager.isRunning
            && monitor.activeBuild == nil
            && !gameDirectory.isEmpty
            && source.isBuildable
            && (!needsProdKeys || !prefs.prodKeysPath.isEmpty)
    }

    func makeOptions(prefs: AppPreferences) -> BuildOptions {
        BuildOptions(gameDirectory: gameDirectory,
                     prodKeysPath: needsProdKeys ? prefs.prodKeysPath : "",
                     platform: platform,
                     language: language,
                     showFps: showFps,
                     keepExtracted: keepExtracted,
                     appName: appName)
    }

    /// Measures the free space again (it may have been freed since the folder was chosen).
    func refreshedDiskSpace() -> DiskSpaceEstimate? {
        updateBuildEstimates()
        return diskSpace
    }

    /// Set when a build was asked for while the estimate says the disk is too full; the builder
    /// page asks whether to build anyway.
    @Published var lowSpaceConfirmationPending = false

    /// Starts the build (used by the toolbar button and the ⌘R menu command). When the free
    /// space is below the estimate, it asks first instead (`lowSpaceConfirmationPending`);
    /// `ignoringLowSpace` is the answer "build anyway".
    func startBuild(manager: BuildManager, monitor: ActiveBuildMonitor, prefs: AppPreferences, library: GameLibraryManager,
                    ignoringLowSpace: Bool = false) {
        guard canStart(manager: manager, monitor: monitor, prefs: prefs) else { return }
        if !ignoringLowSpace {
            if let space = refreshedDiskSpace(), !space.isSufficient {
                lowSpaceConfirmationPending = true
                return
            }
        }
        manager.startBuild(options: makeOptions(prefs: prefs)) { [weak self] in
            library.refreshLibrary()
            monitor.checkActiveBuild()
            self?.scanGameFolder()   // picks up the new work folder and the free space
        }
        monitor.checkActiveBuild()
    }
}
