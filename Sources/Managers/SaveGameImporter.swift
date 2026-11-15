import Foundation
import AppKit

// MARK: - Save import (JKSV, Checkpoint, Ryujinx)
//
//  - The import is assembled in a staging folder first; the current save is only touched
//    once the staging folder holds data.
//  - The current save is renamed to save_backup_<timestamp> (never deleted). If that fails,
//    nothing is changed. The imported save replaces it as a whole, so no mixed save results.
//  - Refused while the game runs; warns when the game syncs its save with a cloud folder.
//  - The title ID is read from ExtraData0 without alignment assumptions (`loadUnaligned`).

enum SaveGameImporter {
    struct Result {
        let copiedCount: Int
        let backupPath: String?
        /// Set when nothing was imported for a reason other than "no data found".
        let errorMessage: String?
        /// The game's cloud saves folder (`cloudSaves.folder`), if set: the game may replace
        /// the imported save with the cloud copy at its next start.
        let cloudSavesFolder: String?

        static func failed(_ message: String) -> Result {
            Result(copiedCount: 0, backupPath: nil, errorMessage: message, cloudSavesFolder: nil)
        }
    }

    static func openSaveFolder(titleId: String) {
        guard !titleId.isEmpty else { return }
        let path = NXPaths.saveDirectory(titleId: titleId)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Imports folders, .zip archives or single files as the game's save.
    static func importSaves(from urls: [URL], titleId: String, bundleId: String?) -> Result {
        performImport(titleId: titleId, bundleId: bundleId) { staging in
            let fm = FileManager.default
            var copied = 0
            for url in urls {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    let zips = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0.lowercased().hasSuffix(".zip") }
                    if zips.isEmpty {
                        copied += copyContents(of: url.path, to: staging)
                    } else {
                        for zip in zips {
                            copied += extractZip((url.path as NSString).appendingPathComponent(zip), to: staging)
                        }
                    }
                } else if url.pathExtension.lowercased() == "zip" {
                    copied += extractZip(url.path, to: staging)
                } else {
                    let dst = (staging as NSString).appendingPathComponent(url.lastPathComponent)
                    if copyIntoStaging(at: dst, from: url.path) { copied += 1 }
                }
            }
            return copied
        }
    }

    static func importFromRyujinx(titleId: String, bundleId: String?, sourcePath: String) -> Result {
        performImport(titleId: titleId, bundleId: bundleId) { staging in
            copyContents(of: sourcePath, to: staging)
        }
    }

    /// Fills a staging folder, then swaps it in for the current save.
    private static func performImport(titleId: String, bundleId: String?, fill: (String) -> Int) -> Result {
        let fm = FileManager.default
        if isGameRunning(titleId: titleId) {
            return .failed(tr("Das Spiel läuft gerade. Beende es vor dem Import.",
                              "The game is running. Quit it before importing."))
        }

        let configDir = NXPaths.gameConfigDirectory(titleId: titleId)
        let target = NXPaths.saveDirectory(titleId: titleId)
        let staging = "\(configDir)/save.importing-\(UUID().uuidString)"
        do {
            try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
        } catch {
            return .failed(tr("Import fehlgeschlagen: \(error.localizedDescription)", "Import failed: \(error.localizedDescription)"))
        }
        // The staging folder holds only copies made here.
        defer { if fm.fileExists(atPath: staging) { try? fm.removeItem(atPath: staging) } }

        let copied = fill(staging)
        guard copied > 0 else {
            return Result(copiedCount: 0, backupPath: nil, errorMessage: nil, cloudSavesFolder: nil)
        }

        // Keep the current save as a backup (rename, no copy that could fail half-way).
        var backup: String?
        let existing = (try? fm.contentsOfDirectory(atPath: target)) ?? []
        if !existing.isEmpty {
            var path = "\(configDir)/save_backup_\(timestamp())"
            var n = 2
            while fm.fileExists(atPath: path) { path = "\(configDir)/save_backup_\(timestamp())_\(n)"; n += 1 }
            do {
                try fm.moveItem(atPath: target, toPath: path)
                backup = path
            } catch {
                return .failed(tr("Der vorhandene Spielstand konnte nicht gesichert werden – nichts wurde geändert. (\(error.localizedDescription))",
                                  "The existing save could not be backed up – nothing was changed. (\(error.localizedDescription))"))
            }
        } else if fm.fileExists(atPath: target) {
            // An empty save folder holds no data.
            try? fm.removeItem(atPath: target)
        }

        do {
            try fm.moveItem(atPath: staging, toPath: target)
        } catch {
            if let backup { try? fm.moveItem(atPath: backup, toPath: target) }
            return .failed(tr("Import fehlgeschlagen: \(error.localizedDescription)", "Import failed: \(error.localizedDescription)"))
        }

        return Result(copiedCount: copied, backupPath: backup, errorMessage: nil,
                      cloudSavesFolder: bundleId.flatMap(cloudSavesFolder(bundleId:)))
    }

    /// Whether a running app is this game (by DMTitleID in its Info.plist).
    private static func isGameRunning(titleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let path = app.bundleURL?.path, path.hasSuffix(".app") else { return false }
            return GameBundleInfo(appPath: path)?.titleId.uppercased() == titleId.uppercased()
        }
    }

    /// The folder the game syncs its save with (docs/frontends.md, "The cloud saves folder").
    static func cloudSavesFolder(bundleId: String) -> String? {
        CFPreferencesAppSynchronize(bundleId as CFString)
        guard let folder = CFPreferencesCopyAppValue("cloudSaves.folder" as CFString, bundleId as CFString) as? String,
              !folder.isEmpty else { return nil }
        return folder
    }

    /// Finds the Ryujinx save folder by the title ID stored in ExtraData0.
    static func ryujinxSavePath(titleId: String) -> String? {
        guard let tidNum = UInt64(titleId, radix: 16) else { return nil }
        let fm = FileManager.default
        let home = NXPaths.home
        let saveRoots = [
            "\(home)/Library/Containers/V380-Ori.Astris/Data/Library/Application Support/Ryujinx/bis/user/save",
            "\(home)/Library/Application Support/Ryujinx/bis/user/save"
        ]

        for root in saveRoots {
            guard let folders = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for folderName in folders {
                let folder = (root as NSString).appendingPathComponent(folderName)
                let extra = (folder as NSString).appendingPathComponent("ExtraData0")
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: extra)), data.count >= 8 else { continue }
                let tid = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
                if UInt64(littleEndian: tid) == tidNum {
                    let inner = (folder as NSString).appendingPathComponent("0")
                    return fm.fileExists(atPath: inner) ? inner : folder
                }
            }
        }
        return nil
    }

    // MARK: Helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private static func extractZip(_ zipPath: String, to target: String) -> Int {
        let fm = FileManager.default
        let temp = (NSTemporaryDirectory() as NSString).appendingPathComponent("jksv_unzip_\(UUID().uuidString)")
        try? fm.createDirectory(atPath: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: temp) }

        let result = CommandRunner.run("/usr/bin/ditto", ["-xk", zipPath, temp])
        guard result.succeeded else { return 0 }

        // If the archive contains exactly one root folder, use its contents
        var effective = temp
        let visible = ((try? fm.contentsOfDirectory(atPath: temp)) ?? []).filter { !$0.hasPrefix(".") && !$0.hasPrefix("__MACOSX") }
        if visible.count == 1 {
            let single = (temp as NSString).appendingPathComponent(visible[0])
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: single, isDirectory: &isDir), isDir.boolValue {
                effective = single
            }
        }
        return copyContents(of: effective, to: target)
    }

    private static func copyContents(of sourceDir: String, to targetDir: String) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: sourceDir) else { return 0 }
        var count = 0
        for item in items where !item.hasPrefix(".") && !item.hasPrefix("__MACOSX") {
            let src = (sourceDir as NSString).appendingPathComponent(item)
            let dst = (targetDir as NSString).appendingPathComponent(item)
            if copyIntoStaging(at: dst, from: src) { count += 1 }
        }
        return count
    }

    /// Copies into the staging folder. An item already there came from an earlier source of
    /// the same import (a copy made here), so it is replaced.
    private static func copyIntoStaging(at destination: String, from source: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination) {
            try? fm.removeItem(atPath: destination)
        }
        return (try? fm.copyItem(atPath: source, toPath: destination)) != nil
    }
}
