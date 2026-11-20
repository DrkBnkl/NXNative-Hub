import Foundation

// MARK: - A copy of each game's app icon, kept beside its settings
//
// A Switch 2 NUP or a dump carries no icon of its own, so a build from one gives the app a blank
// icon unless the build script gets one (`--fallback-icon`, used only when the game has none).
// The library backs up each installed app's icon to
// `~/Library/Application Support/nxnative/<base title ID>/icon.png`, and every build the app starts
// passes that copy, or the icon of the installed app, as the fallback. An update of a game whose
// new files carry no icon keeps the one it had.

enum GameIconStore {
    static func storedIconPath(baseTitleId: String) -> String {
        "\(NXPaths.gameConfigDirectory(titleId: baseTitleId))/icon.png"
    }

    /// The image to pass as `--fallback-icon` for a build of this game source (folder or .nup):
    /// the stored copy, else the icon of an installed app of the same game (stored first). Nil
    /// when the game is unknown or has no icon anywhere.
    static func fallbackIcon(forSource gameDirectory: String, installedApps: [InstalledGame]) -> String? {
        guard !gameDirectory.isEmpty,
              let base = GameMetaDetector.detect(in: URL(fileURLWithPath: gameDirectory)).baseTitleId else { return nil }
        let stored = storedIconPath(baseTitleId: base)
        if FileManager.default.fileExists(atPath: stored) { return stored }
        let app = installedApps.first { SwitchTitleID.baseID(of: $0.titleId) == base }
        guard let app, backUp(appPath: app.path, baseTitleId: base) else { return nil }
        return stored
    }

    /// Backs up the icons of installed apps whose copy is missing or older than the app's icon.
    static func backUp(_ games: [InstalledGame]) {
        for game in games {
            guard let base = SwitchTitleID.baseID(of: game.titleId) else { continue }
            backUp(appPath: game.path, baseTitleId: base)
        }
    }

    /// Converts the app's AppIcon.icns to the stored PNG when the copy is missing or older.
    @discardableResult
    static func backUp(appPath: String, baseTitleId: String) -> Bool {
        let fm = FileManager.default
        let icns = "\(appPath)/Contents/Resources/AppIcon.icns"
        guard let icnsDate = (try? fm.attributesOfItem(atPath: icns))?[.modificationDate] as? Date else { return false }
        let stored = storedIconPath(baseTitleId: baseTitleId)
        if let storedDate = (try? fm.attributesOfItem(atPath: stored))?[.modificationDate] as? Date, storedDate >= icnsDate {
            return true
        }
        try? fm.createDirectory(atPath: (stored as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let temp = stored + ".partial.png"
        let result = CommandRunner.run("/usr/bin/sips", ["-s", "format", "png", "-Z", "1024", icns, "--out", temp])
        guard result.succeeded, fm.fileExists(atPath: temp) else {
            try? fm.removeItem(atPath: temp)
            return false
        }
        try? fm.removeItem(atPath: stored)
        do {
            try fm.moveItem(atPath: temp, toPath: stored)
            return true
        } catch {
            try? fm.removeItem(atPath: temp)
            return false
        }
    }
}

// MARK: - Icon search at Nintendo by title ID
//
// Nintendo's own title ID service, `https://ec.nintendo.com/apps/<title ID>/<region>`, redirects
// to the game's store page (Switch and Switch 2). The page carries a square product image on
// assets.nintendo.com, which is fetched as a 1024 px PNG into the icon store. Only the title ID
// is sent; nothing about the user or the game files.

enum NintendoIconSearch {
    private static let regions = ["US", "GB", "DE", "JP"]
    private static let squareImage = try! NSRegularExpression(
        pattern: #"productImage\(\{\\"shape\\":\\"square\\"\}\)":\{[^}]*?"url":"([^"]+)""#)
    private static let queue = DispatchQueue(label: "org.nxnative.iconSearch", qos: .utility)
    private static var inFlight: Set<String> = []
    private static var failed: Set<String> = []   // not found this session: not asked again

    /// Makes sure the store holds an icon for the game: from an installed app, else from Nintendo
    /// (when enabled). Runs in the background; `completion` gets the stored path or nil (main thread).
    static func ensureIcon(baseTitleId: String, installedApps: [InstalledGame],
                           completion: ((String?) -> Void)? = nil) {
        let stored = GameIconStore.storedIconPath(baseTitleId: baseTitleId)
        let enabled = AppPreferences.shared.searchMissingIcons
        queue.async {
            var result: String?
            if FileManager.default.fileExists(atPath: stored) {
                result = stored
            } else if let app = installedApps.first(where: { SwitchTitleID.baseID(of: $0.titleId) == baseTitleId }),
                      GameIconStore.backUp(appPath: app.path, baseTitleId: baseTitleId) {
                result = stored
            } else if enabled, !inFlight.contains(baseTitleId), !failed.contains(baseTitleId) {
                inFlight.insert(baseTitleId)
                result = download(baseTitleId: baseTitleId, to: stored) ? stored : nil
                if result == nil { failed.insert(baseTitleId) }
                inFlight.remove(baseTitleId)
            }
            DispatchQueue.main.async { completion?(result) }
        }
    }

    /// As above for a game source (folder or .nup), whose title ID is read in the background.
    static func ensureIcon(forSource gameDirectory: String) {
        guard !gameDirectory.isEmpty else { return }
        queue.async {
            guard let base = GameMetaDetector.detect(in: URL(fileURLWithPath: gameDirectory)).baseTitleId else { return }
            DispatchQueue.main.async { ensureIcon(baseTitleId: base, installedApps: []) }
        }
    }

    /// Synchronous; call off the main thread.
    static func download(baseTitleId: String, to path: String) -> Bool {
        guard SwitchTitleID.normalized(baseTitleId) != nil else { return false }
        for region in regions {
            guard let page = URL(string: "https://ec.nintendo.com/apps/\(baseTitleId)/\(region)"),
                  let (html, finalURL) = fetchText(page),
                  finalURL.host?.hasSuffix("nintendo.com") == true,
                  let imageURL = squareImageURL(in: html),
                  let data = fetchData(imageURL), isPNG(data) else { continue }
            let fm = FileManager.default
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            let temp = path + ".partial.png"
            guard (try? data.write(to: URL(fileURLWithPath: temp))) != nil else { continue }
            try? fm.removeItem(atPath: path)
            if (try? fm.moveItem(atPath: temp, toPath: path)) != nil { return true }
            try? fm.removeItem(atPath: temp)
        }
        return false
    }

    /// The square product image as a 1024 px PNG (Cloudinary transformation on assets.nintendo.com).
    static func squareImageURL(in html: String) -> URL? {
        let range = NSRange(html.startIndex..., in: html)
        guard let m = squareImage.firstMatch(in: html, range: range),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        let raw = String(html[r]).replacingOccurrences(of: "\\u002F", with: "/")
        guard raw.hasPrefix("https://assets.nintendo.com/image/") else { return nil }
        return URL(string: raw.replacingOccurrences(of: "/q_auto/f_auto/", with: "/f_png,w_1024,h_1024,c_fill/"))
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.count > 1000 && data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Mozilla/5.0 (Macintosh; Mac OS X) NXNativeHub", forHTTPHeaderField: "User-Agent")
        return r
    }

    private static func fetchText(_ url: URL) -> (String, URL)? {
        guard let (data, response) = fetch(request(url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let final = response.url else { return nil }
        return (String(decoding: data, as: UTF8.self), final)
    }

    private static func fetchData(_ url: URL) -> Data? {
        guard let (data, response) = fetch(request(url)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func fetch(_ request: URLRequest) -> (Data, URLResponse)? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data, URLResponse)?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let response { result = (data, response) }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }
}
