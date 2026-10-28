import Foundation

// MARK: - Game library

final class GameLibraryManager: ObservableObject {
    @Published private(set) var games: [InstalledGame] = []
    @Published private(set) var isScanning = false
    @Published private(set) var customFolders: [String] = []
    @Published private(set) var manuallyAddedAppPaths: [String] = []

    private let customFoldersKey = "nxnative_custom_folders"
    private let manualAppsKey = "nxnative_manual_apps"
    private let sizeCacheKey = "nxnative_size_cache"
    private let scanQueue = DispatchQueue(label: "org.nxnative.libraryScan", qos: .userInitiated)
    private var rescanRequested = false

    /// Folders skipped while scanning (tools, import sources).
    private let ignoredFolderNames: Set<String> = ["nxnative", "nxnative-gui", "Import", "venv"]

    init() {
        customFolders = UserDefaults.standard.stringArray(forKey: customFoldersKey) ?? []
        manuallyAddedAppPaths = UserDefaults.standard.stringArray(forKey: manualAppsKey) ?? []
        removeLegacySizeCacheEntries()
    }

    // MARK: Folders & manually added apps

    func addCustomFolder(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customFolders.contains(trimmed) else { return }
        customFolders.append(trimmed)
        UserDefaults.standard.set(customFolders, forKey: customFoldersKey)
        refreshLibrary()
    }

    func removeCustomFolder(_ path: String) {
        customFolders.removeAll { $0 == path }
        UserDefaults.standard.set(customFolders, forKey: customFoldersKey)
        refreshLibrary()
    }

    func addManualApp(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !manuallyAddedAppPaths.contains(trimmed) else { return }
        manuallyAddedAppPaths.append(trimmed)
        UserDefaults.standard.set(manuallyAddedAppPaths, forKey: manualAppsKey)
        refreshLibrary()
    }

    /// Removes a manually added app (Settings → Library).
    func removeManualApp(_ path: String) {
        manuallyAddedAppPaths.removeAll { $0 == path }
        UserDefaults.standard.set(manuallyAddedAppPaths, forKey: manualAppsKey)
        refreshLibrary()
    }

    /// Adds a dropped URL as an app or as a folder.
    func addDroppedItem(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if url.pathExtension == "app" {
            addManualApp(url.path)
        } else if isDir.boolValue {
            addCustomFolder(url.path)
        }
    }

    // MARK: Scan

    func refreshLibrary() {
        // If a scan is already running, queue exactly one more (instead of scanning in parallel).
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        let folders = customFolders
        let manualApps = manuallyAddedAppPaths

        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let found = self.scanForGames(customFolders: folders, manualApps: manualApps)
            DispatchQueue.main.async {
                self.games = found
                self.isScanning = false
                if self.rescanRequested {
                    self.rescanRequested = false
                    self.refreshLibrary()
                }
            }
        }
    }

    private func scanForGames(customFolders: [String], manualApps: [String]) -> [InstalledGame] {
        let fm = FileManager.default
        let home = NXPaths.home
        var baseFolders: [URL] = [
            NXPaths.gamesFolder,
            URL(fileURLWithPath: NXPaths.nxnativeRoot),
            URL(fileURLWithPath: "\(home)/Applications")
        ]
        for folderPath in customFolders {
            let url = URL(fileURLWithPath: folderPath)
            if !baseFolders.contains(url) && fm.fileExists(atPath: folderPath) {
                baseFolders.append(url)
            }
        }

        // .app bundles directly in the folder or one level deeper
        var appURLs: [URL] = []
        for base in baseFolders {
            guard let contents = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in contents {
                if item.pathExtension == "app" {
                    appURLs.append(item)
                } else if !ignoredFolderNames.contains(item.lastPathComponent),
                          let sub = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    appURLs.append(contentsOf: sub.filter { $0.pathExtension == "app" })
                }
            }
        }
        for manualPath in manualApps {
            let url = URL(fileURLWithPath: manualPath)
            if !appURLs.contains(url) && fm.fileExists(atPath: manualPath) {
                appURLs.append(url)
            }
        }

        var sizeCache = UserDefaults.standard.dictionary(forKey: sizeCacheKey) as? [String: [String: Any]] ?? [:]
        var usedCacheKeys = Set<String>()
        var result: [InstalledGame] = []
        var seenTitleIds = Set<String>()

        for app in appURLs {
            let resolved = app.resolvingSymlinksInPath()
            guard let info = GameBundleInfo(appPath: resolved.path),
                  info.titleId != "org.nxnative.gui",
                  seenTitleIds.insert(info.titleId).inserted else { continue }

            let size = folderSize(url: resolved, cache: &sizeCache)
            usedCacheKeys.insert(resolved.path)

            // Current game settings for the badges: what the game will use at launch
            // (settings list: env.txt → saved choice → tested default; older builds: env.txt only).
            var env = EnvFile.load(path: NXPaths.envFilePath(titleId: info.titleId))?.values ?? [:]
            let list = LauncherSettingsList.load(appPath: resolved.path)
            if let list = list {
                let bundleEnv = EnvFile.load(path: NXPaths.bundleEnvFilePath(appPath: resolved.path))?.values ?? [:]
                env.merge(GameSettingsResolver.effectiveValues(list: list, envValues: env,
                                                               bundleEnvValues: bundleEnv,
                                                               bundleId: info.bundleId)) { _, effective in effective }
            }

            result.append(InstalledGame(
                id: info.titleId,
                name: info.name,
                titleId: info.titleId,
                version: info.version,
                path: resolved.path,
                sizeFormatted: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                // A listed game without a frame-rate row has no FPS choice: no badge ("").
                fpsTarget: env["DM_FPS_TARGET"] ?? (list == nil ? "60" : ""),
                isDocked: (env["DM_OPMODE"] ?? "1") == "1",
                upscaling: env["DM_PRESENT_UPSCALE"] ?? (list == nil ? "metalfx" : "off"),
                isFullscreen: env["DM_FULLSCREEN"] == "1",
                language: env["DM_LANG"] ?? "",
                hasSettingsList: list != nil
            ))
        }

        // Keep the cache limited to existing games
        sizeCache = sizeCache.filter { usedCacheKeys.contains($0.key) }
        UserDefaults.standard.set(sizeCache, forKey: sizeCacheKey)

        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Size of an app bundle; cached by modification date because summing up
    /// thousands of shader files can take seconds.
    private func folderSize(url: URL, cache: inout [String: [String: Any]]) -> Int64 {
        let path = url.path
        let fm = FileManager.default
        let mtime = ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? Date()

        if let cached = cache[path],
           let cachedTime = cached["time"] as? Date,
           let cachedSize = cached["size"] as? NSNumber,
           abs(cachedTime.timeIntervalSince(mtime)) < 5 {
            return cachedSize.int64Value
        }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        cache[path] = ["time": mtime, "size": NSNumber(value: total)]
        return total
    }

    /// Version 1.0 stored one UserDefaults key "nx_size_<path>" per game and never
    /// removed it. These leftovers are cleaned up once.
    private func removeLegacySizeCacheEntries() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("nx_size_") {
            defaults.removeObject(forKey: key)
        }
    }
}
