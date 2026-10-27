import Foundation

// MARK: - Form state of the builder page

final class BuilderFormModel: ObservableObject {
    @Published var gameDirectory: String = "" {
        didSet { if gameDirectory != oldValue { scanGameFolder() } }
    }
    @Published var platform: TargetPlatform = .macApp
    @Published var language: String = AppPreferences.shared.defaultGameLanguage
    @Published var showFps = false
    @Published var keepExtracted = false
    @Published var appName = ""
    @Published private(set) var detectedFiles: [DetectedGameFile] = []

    func clear() {
        gameDirectory = ""
        detectedFiles.removeAll()
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
            return
        }
        detectedFiles = files
            .filter(NXPaths.isGameFile)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(DetectedGameFile.init(url:))
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
        manager.startBuild(options: makeOptions(prefs: prefs)) {
            library.refreshLibrary()
            monitor.checkActiveBuild()
        }
        monitor.checkActiveBuild()
    }
}
