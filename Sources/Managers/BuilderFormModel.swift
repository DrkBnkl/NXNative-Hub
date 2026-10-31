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
    /// The folder already holds a `<title ID>_build` work folder: the build will be much faster.
    @Published private(set) var hasPreviousBuild = false
    @Published private(set) var diskSpace: DiskSpaceEstimate?

    func clear() {
        gameDirectory = ""
        detectedFiles.removeAll()
        hasPreviousBuild = false
        diskSpace = nil
    }

    /// Uses a dropped folder, or the folder containing a dropped file.
    func setSource(from url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        gameDirectory = isDir.boolValue ? url.path : url.deletingLastPathComponent().path
    }

    func scanGameFolder() {
        guard !gameDirectory.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: gameDirectory),
                                                                       includingPropertiesForKeys: [.fileSizeKey]) else {
            detectedFiles = []
            hasPreviousBuild = false
            diskSpace = nil
            return
        }
        detectedFiles = files
            .filter(NXPaths.isGameFile)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(DetectedGameFile.init(url:))
        hasPreviousBuild = !BuildWorkFolder.find(in: gameDirectory).isEmpty
        diskSpace = DiskSpaceEstimate.make(gameBytes: detectedFiles.reduce(0) { $0 + $1.sizeBytes }, folder: gameDirectory)
    }

    func canStart(manager: BuildManager, monitor: ActiveBuildMonitor, prefs: AppPreferences) -> Bool {
        !manager.isRunning
            && monitor.activeBuild == nil
            && !gameDirectory.isEmpty
            && !prefs.prodKeysPath.isEmpty
    }

    func makeOptions(prefs: AppPreferences) -> BuildOptions {
        BuildOptions(gameDirectory: gameDirectory,
                     prodKeysPath: prefs.prodKeysPath,
                     platform: platform,
                     language: language,
                     showFps: showFps,
                     keepExtracted: keepExtracted,
                     appName: appName)
    }

    /// Starts the build (used by the toolbar button and the ⌘R menu command).
    func startBuild(manager: BuildManager, monitor: ActiveBuildMonitor, prefs: AppPreferences, library: GameLibraryManager) {
        guard canStart(manager: manager, monitor: monitor, prefs: prefs) else { return }
        manager.startBuild(options: makeOptions(prefs: prefs)) { [weak self] in
            library.refreshLibrary()
            monitor.checkActiveBuild()
            self?.scanGameFolder()   // picks up the new work folder and the free space
        }
        monitor.checkActiveBuild()
    }
}
