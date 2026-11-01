import Foundation
import AppKit

// MARK: - Save import (JKSV, Checkpoint, Ryujinx)
//
//  - Every import (including Ryujinx) backs up the existing save first.
//  - The title ID is read from ExtraData0 without alignment assumptions (`loadUnaligned`).

enum SaveGameImporter {
    struct Result {
        let copiedCount: Int
        let backupPath: String?
    }

    static func openSaveFolder(titleId: String) {
        guard !titleId.isEmpty else { return }
        let path = NXPaths.saveDirectory(titleId: titleId)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Imports folders, .zip archives or single files into the save folder.
    static func importSaves(from urls: [URL], titleId: String) -> Result {
        let fm = FileManager.default
        let target = NXPaths.saveDirectory(titleId: titleId)
        try? fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        let backup = backupExistingSave(titleId: titleId)

        var copied = 0
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let zips = ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0.lowercased().hasSuffix(".zip") }
                if zips.isEmpty {
                    copied += copyContents(of: url.path, to: target)
                } else {
                    for zip in zips {
                        copied += extractZip((url.path as NSString).appendingPathComponent(zip), to: target)
                    }
                }
            } else if url.pathExtension.lowercased() == "zip" {
                copied += extractZip(url.path, to: target)
            } else {
                let dst = (target as NSString).appendingPathComponent(url.lastPathComponent)
                if replaceItem(at: dst, with: url.path) { copied += 1 }
            }
        }
        return Result(copiedCount: copied, backupPath: backup)
    }

    static func importFromRyujinx(titleId: String, sourcePath: String) -> Result {
        let target = NXPaths.saveDirectory(titleId: titleId)
        try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
        let backup = backupExistingSave(titleId: titleId)
        return Result(copiedCount: copyContents(of: sourcePath, to: target), backupPath: backup)
    }

    /// Finds the Ryujinx save folder by the title ID stored in ExtraData0.
    static func ryujinxSavePath(titleId: String) -> String? {
        for root in AstrisSaves.dataRoots {
            // A game can have several slots, such as a device save; the import target is the user's own save.
            let slots = AstrisSaves.slots(inDataRoot: root)
            guard let slot = AstrisSaves.slot(titleId: titleId, kind: .account, in: slots,
                                              lastOpenedUser: AstrisSaves.lastOpenedUser(inDataRoot: root)) else { continue }
            return FileManager.default.fileExists(atPath: slot.committed.path) ? slot.committed.path : slot.url.path
        }
        return nil
    }

    // MARK: Helpers

    /// Copies the current save to save_backup_<timestamp>, if one exists.
    private static func backupExistingSave(titleId: String) -> String? {
        let fm = FileManager.default
        let source = NXPaths.saveDirectory(titleId: titleId)
        guard let items = try? fm.contentsOfDirectory(atPath: source), !items.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupDir = "\(NXPaths.gameConfigDirectory(titleId: titleId))/save_backup_\(formatter.string(from: Date()))"
        do {
            try fm.copyItem(atPath: source, toPath: backupDir)
            return backupDir
        } catch {
            return nil
        }
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
            if replaceItem(at: dst, with: src) { count += 1 }
        }
        return count
    }

    private static func replaceItem(at destination: String, with source: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination) {
            try? fm.removeItem(atPath: destination)
        }
        return (try? fm.copyItem(atPath: source, toPath: destination)) != nil
    }
}
