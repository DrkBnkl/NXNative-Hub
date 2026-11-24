import Foundation
import AppKit

// MARK: - Asynchronous, disk-cached icon loader for NSP/NUP/XCI packages
//
// Strictly read-only on source volumes (e.g. USB sticks): all caches are stored
// under ~/Library/Caches/org.nxnative.gui/.

@MainActor
final class PackageIconManager: ObservableObject {
    static let shared = PackageIconManager()

    @Published private(set) var icons: [String: NSImage] = [:]

    private var inFlightKeys = Set<String>()
    private var failedKeys = Set<String>()
    private var titleDBMap: [String: String]?
    private var titleDBLoadTask: Task<[String: String], Never>?

    private let cacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("org.nxnative.gui/package_icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var titleDBCacheFile: URL {
        cacheDir.deletingLastPathComponent().appendingPathComponent("titledb_icon_urls.json")
    }

    private init() {}

    /// Stable cache key for an import candidate (prefers normalized base Title ID).
    static func cacheKey(for item: ImportGameItem) -> String {
        if let base = item.baseTitleId, !base.isEmpty {
            return base.uppercased()
        }
        if let tid = item.titleId, !tid.isEmpty {
            return tid.uppercased()
        }
        return item.name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
    }

    func icon(for item: ImportGameItem) -> NSImage? {
        icons[Self.cacheKey(for: item)]
    }

    /// Loads an icon asynchronously if not yet cached in memory.
    func loadIconIfNeeded(for item: ImportGameItem, installedGames: [InstalledGame]) {
        let key = Self.cacheKey(for: item)
        if icons[key] != nil || inFlightKeys.contains(key) || failedKeys.contains(key) {
            return
        }
        inFlightKeys.insert(key)

        // Capture Sendable / value-type inputs for background work.
        let matchingAppPath = installedGames.first { game in
            let gTid = game.titleId.uppercased()
            let gBase = SwitchTitleID.baseID(of: gTid)?.uppercased() ?? gTid
            return gTid == key || gBase == key
        }?.path

        let nupPath: String?
        if case let .nup(url) = item.source {
            nupPath = url.path
        } else {
            nupPath = item.sourceFiles.first(where: { $0.pathExtension.lowercased() == "nup" })?.path
        }
        let localFolderPath: String? = item.isReadOnly ? nil : item.folderURL.path
        let titleIdForDB: String? = item.baseTitleId?.uppercased() ?? item.titleId?.uppercased()
        let diskFile = cacheDir.appendingPathComponent("\(key).img")
        let repoPath = NXPaths.repoPath
        let pythonPath = NXPaths.pythonPath

        Task {
            let loadedImage = await Task.detached(priority: .utility) { () -> NSImage? in
                // 1. Disk cache
                if FileManager.default.fileExists(atPath: diskFile.path),
                   let img = NSImage(contentsOfFile: diskFile.path) {
                    return img
                }

                // 2. Already installed app in "My Games"
                if let appPath = matchingAppPath,
                   let img = Self.loadIconFromInstalledApp(appPath: appPath) {
                    return img
                }

                // 3. Local build folder's extracted icon.jpg
                if let folder = localFolderPath,
                   let img = Self.loadIconFromLocalBuildFolder(folderPath: folder, titleId: titleIdForDB) {
                    return img
                }

                // 4. Embedded icon inside .nup container (read-only, fast TLV header read)
                if let nupPath = nupPath,
                   let data = Self.extractNupIcon(nupPath: nupPath, repoPath: repoPath, pythonPath: pythonPath),
                   let img = NSImage(data: data) {
                    try? data.write(to: diskFile, options: .atomic)
                    return img
                }

                return nil
            }.value

            if let img = loadedImage {
                self.icons[key] = img
                self.inFlightKeys.remove(key)
                return
            }

            // 5. Fallback: TitleDB eShop icon URL (cached once locally)
            if let tid = titleIdForDB {
                let db = await self.loadTitleDB()
                if let urlStr = db[tid], let url = URL(string: urlStr) {
                    let fetched = await Self.downloadIcon(from: url, saveTo: diskFile)
                    if let img = fetched {
                        self.icons[key] = img
                        self.inFlightKeys.remove(key)
                        return
                    }
                }
            }

            self.failedKeys.insert(key)
            self.inFlightKeys.remove(key)
        }
    }

    // MARK: - Local sources

    private nonisolated static func loadIconFromInstalledApp(appPath: String) -> NSImage? {
        let resURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources")
        for candidate in ["cover.jpg", "cover.png", "icon.jpg", "icon.png", "AppIcon.icns"] {
            let file = resURL.appendingPathComponent(candidate)
            if let img = NSImage(contentsOfFile: file.path) {
                return img
            }
        }
        return nil
    }

    private nonisolated static func loadIconFromLocalBuildFolder(folderPath: String, titleId: String?) -> NSImage? {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: folderPath)

        // Check direct icon/ folder or <tid>_build/extract/*/icon.jpg
        let directIcon = baseURL.appendingPathComponent("icon.jpg")
        if let img = NSImage(contentsOfFile: directIcon.path) { return img }

        if let tid = titleId {
            let extractDir = baseURL
                .appendingPathComponent("\(tid)_build/extract", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in entries {
                    let iconFile = entry.appendingPathComponent("icon.jpg")
                    if let img = NSImage(contentsOfFile: iconFile.path) {
                        return img
                    }
                }
            }
        }
        return nil
    }

    /// Reads the unencrypted meta block of a .nup file via nxnative's pack_nup.py.
    private nonisolated static func extractNupIcon(nupPath: String, repoPath: String, pythonPath: String) -> Data? {
        let scriptsDir = (repoPath as NSString).appendingPathComponent("scripts")
        let packNupPath = (scriptsDir as NSString).appendingPathComponent("pack_nup.py")
        guard FileManager.default.fileExists(atPath: pythonPath),
              FileManager.default.fileExists(atPath: packNupPath) else { return nil }

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nxnative_nup_icon_\(UUID().uuidString).img")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let snippet = """
        import sys
        from pathlib import Path
        sys.path.insert(0, sys.argv[1])
        import pack_nup
        with pack_nup.Nup(Path(sys.argv[2])) as n:
            for pkg in n.packages:
                ic = pack_nup.icon_of(pkg.meta())
                if ic:
                    Path(sys.argv[3]).write_bytes(ic)
                    break
        """
        let result = CommandRunner.run(pythonPath, ["-c", snippet, scriptsDir, nupPath, tempFile.path])
        guard result.succeeded,
              let data = try? Data(contentsOf: tempFile),
              !data.isEmpty else { return nil }
        return data
    }

    // MARK: - TitleDB lookup & download

    private func loadTitleDB() async -> [String: String] {
        if let existing = titleDBMap {
            return existing
        }
        if let running = titleDBLoadTask {
            return await running.value
        }

        let cacheFile = titleDBCacheFile
        let task = Task.detached(priority: .utility) { () -> [String: String] in
            // 1. Use local slim cache if fresh (< 14 days)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
               let mtime = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(mtime) < 14 * 86400,
               let data = try? Data(contentsOf: cacheFile),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data),
               !decoded.isEmpty {
                return decoded
            }

            // 2. Fetch US.en.json from blawar/titledb and distill to [TitleID: iconUrl]
            guard let url = URL(string: "https://raw.githubusercontent.com/blawar/titledb/master/US.en.json") else {
                return [:]
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
                guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
                    return [:]
                }
                var map: [String: String] = [:]
                map.reserveCapacity(raw.count)
                for (_, entry) in raw {
                    if let id = entry["id"] as? String,
                       let iconUrl = entry["iconUrl"] as? String,
                       !id.isEmpty, !iconUrl.isEmpty {
                        map[id.uppercased()] = iconUrl
                    }
                }
                if !map.isEmpty, let encoded = try? JSONEncoder().encode(map) {
                    try? encoded.write(to: cacheFile, options: .atomic)
                }
                return map
            } catch {
                // Fall back to stale cache if offline
                if let data = try? Data(contentsOf: cacheFile),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    return decoded
                }
                return [:]
            }
        }

        titleDBLoadTask = task
        let result = await task.value
        titleDBMap = result
        titleDBLoadTask = nil
        return result
    }

    private nonisolated static func downloadIcon(from url: URL, saveTo diskFile: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let img = NSImage(data: data) else { return nil }
            try? data.write(to: diskFile, options: .atomic)
            return img
        } catch {
            return nil
        }
    }
}
