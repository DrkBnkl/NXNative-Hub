import CryptoKit
import Foundation

// MARK: - Save sync between Astris and nxnative
//
// Rules this file keeps:
//  - Nothing is overwritten without a verified backup of both sides first; a failed backup stops the sync.
//  - A new save is staged, compared with its source, and only then swapped in. Killed at any moment, recover() restores the old one.
//  - A conflict is never decided by date: the person chooses.
//  - Slot folders in Astris are never created here; a game has to create its own first.

enum SaveKind: String, Codable, CaseIterable {
    case account
    case device

    /// Save type in a Ryujinx ExtraData file.
    var astrisType: UInt8 { self == .account ? 1 : 3 }
    /// nxnative keeps a device save beside the normal one.
    var nxFolderName: String { self == .account ? "save" : "save_device" }
}

enum SaveSide: String, Codable {
    case astris
    case nxnative
}

enum SyncDirection: String, Codable {
    case toAstris
    case toNXNative

    var source: SaveSide { self == .toAstris ? .nxnative : .astris }
    var target: SaveSide { self == .toAstris ? .astris : .nxnative }
}

enum SaveSyncError: Error, CustomStringConvertible, Equatable {
    case sourceMissing
    case backupFailed(String)
    case stagingMismatch
    case changedDuringSync
    case verifyFailed
    case slotMissing
    case gameRunning(String)

    var description: String {
        switch self {
        case .sourceMissing: return tr("Die Quelle ist leer oder fehlt.", "The source is empty or missing.")
        case .backupFailed(let detail): return tr("Backup fehlgeschlagen: \(detail)", "Backup failed: \(detail)")
        case .stagingMismatch: return tr("Die vorbereitete Kopie stimmt nicht mit der Quelle überein.", "The prepared copy does not match the source.")
        case .changedDuringSync: return tr("Ein Spielstand hat sich während des Abgleichs geändert.", "A save changed during the sync.")
        case .verifyFailed: return tr("Der übernommene Spielstand stimmt nicht mit der Quelle überein, der alte wurde wiederhergestellt.",
                                      "The copied save does not match the source; the old one was restored.")
        case .slotMissing: return tr("Astris hat für dieses Spiel noch keinen Spielstand.", "Astris has no save for this game yet.")
        case .gameRunning(let name): return tr("\(name) läuft gerade, deshalb wurde nichts kopiert.", "\(name) is running, so nothing was copied.")
        }
    }
}

struct SaveFileEntry: Equatable {
    let path: String
    let size: UInt64
    let sha256: String
}

struct SaveSnapshot: Equatable {
    let hash: String
    let files: Int
    let bytes: UInt64
    let newest: Date?

    var isEmpty: Bool { files == 0 }
}

enum SaveTree {
    /// A hash over names and contents, not dates: the same save has the same hash wherever it lies. Missing counts as empty.
    static func snapshot(of folder: URL) -> SaveSnapshot {
        let fm = FileManager.default
        var hasher = SHA256()
        var files = 0
        var bytes: UInt64 = 0
        var newest: Date?
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return SaveSnapshot(hash: "", files: 0, bytes: 0, newest: nil)
        }
        let base = folder.standardizedFileURL.path
        var entries: [(path: String, url: URL)] = []
        for case let url as URL in walker where url.lastPathComponent != ".DS_Store" && !url.lastPathComponent.hasPrefix("._") {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            entries.append((String(url.standardizedFileURL.path.dropFirst(base.count + 1)), url))
        }
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            guard let handle = try? FileHandle(forReadingFrom: entry.url) else { continue }
            defer { try? handle.close() }
            hasher.update(data: Data(entry.path.utf8))
            hasher.update(data: Data([0]))
            var size: UInt64 = 0
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
                size += UInt64(chunk.count)
            }
            hasher.update(data: Data("\(size)".utf8))
            files += 1
            bytes += size
            if let date = (try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                newest = max(newest ?? date, date)
            }
        }
        guard files > 0 else { return SaveSnapshot(hash: "", files: 0, bytes: 0, newest: nil) }
        return SaveSnapshot(hash: hasher.finalize().map { String(format: "%02x", $0) }.joined(), files: files, bytes: bytes, newest: newest)
    }
}

extension SaveTree {
    /// Every file with its size and hash, for a backup's manifest.
    static func listing(of folder: URL) -> [SaveFileEntry] {
        let base = folder.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var entries: [SaveFileEntry] = []
        for case let url as URL in walker where url.lastPathComponent != ".DS_Store" && !url.lastPathComponent.hasPrefix("._") {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true, let data = try? Data(contentsOf: url) else { continue }
            entries.append(SaveFileEntry(path: String(url.standardizedFileURL.path.dropFirst(base.count + 1)), size: UInt64(data.count),
                                         sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
        }
        return entries.sorted { $0.path < $1.path }
    }
}

// MARK: - Astris slots

struct AstrisSlot: Equatable {
    let url: URL
    let titleId: String
    let type: UInt8
    /// The user ID as stored in ExtraData, in hex.
    let user: String

    var committed: URL { url.appendingPathComponent("0") }
    var working: URL { url.appendingPathComponent("1") }
}

enum AstrisSaves {
    static var dataRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Library/Containers/V380-Ori.Astris/Data/Library/Application Support/Ryujinx",
                "Library/Application Support/Ryujinx"].map { home.appendingPathComponent($0) }
    }

    static func slots(inDataRoot root: URL) -> [AstrisSlot] {
        let saves = root.appendingPathComponent("bis/user/save")
        let folders = (try? FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("ExtraData0")), data.count > 0x20 else { return nil }
            let id = data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return AstrisSlot(url: folder, titleId: String(format: "%016llX", UInt64(littleEndian: id)), type: data[0x20],
                              user: data[8..<24].map { String(format: "%02x", $0) }.joined())
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// `Profiles.json` writes the user ID as two big-endian halves, ExtraData as two little-endian ones.
    static func lastOpenedUser(inDataRoot root: URL) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("system/Profiles.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["last_opened"] as? String, text.count == 32 else { return nil }
        let swapHalf = { (half: Substring) -> String in
            stride(from: 14, through: 0, by: -2).map { offset -> String in
                let start = half.index(half.startIndex, offsetBy: offset)
                return String(half[start..<half.index(start, offsetBy: 2)])
            }.joined()
        }
        let lower = text.lowercased()
        return swapHalf(lower.prefix(16)) + swapHalf(lower.suffix(16))
    }

    /// The slot of a game. With several profiles it is the last opened one; a device save belongs to no user.
    static func slot(titleId: String, kind: SaveKind, in slots: [AstrisSlot], lastOpenedUser: String?) -> AstrisSlot? {
        let matching = slots.filter { $0.titleId == titleId.uppercased() && $0.type == kind.astrisType }
        guard matching.count > 1, kind == .account else { return matching.first }
        return matching.first { $0.user == lastOpenedUser }
    }
}

// MARK: - Decision

enum SyncDecision: Equatable {
    case inSync
    case noSaves
    /// The two sides differ and were never synced: only the person can say which one leads.
    case setupNeeded
    case copy(SyncDirection)
    case conflict(String)
}

enum SaveSyncRules {
    /// A freshly created save is often smaller or has fewer files. It must not overwrite one by itself.
    /// Many games use saves of a fixed size, so this cannot catch every case: a new Astris slot is caught by its slot ID instead.
    static func looksFresh(source: SaveSnapshot, target: SaveSnapshot) -> Bool {
        source.isEmpty || source.bytes * 4 < target.bytes || source.files < target.files
    }

    /// `astrisWorking` is Astris's folder "1". If it differs from "0", it may hold data this comparison would miss.
    static func decide(astris: SaveSnapshot, nxnative: SaveSnapshot, base: String?, astrisWorking: SaveSnapshot? = nil) -> SyncDecision {
        if astris.isEmpty, nxnative.isEmpty { return .noSaves }
        if let astrisWorking, !astrisWorking.isEmpty, astrisWorking.hash != astris.hash {
            return .conflict(tr("In Astris unterscheiden sich die Ordner 0 und 1. Dort könnten neuere Daten liegen, deshalb wird nichts automatisch kopiert.",
                                "Astris's folders 0 and 1 differ. They may hold newer data, so nothing is copied automatically."))
        }
        if astris.hash == nxnative.hash { return .inSync }
        guard let base else { return .setupNeeded }
        let direction: SyncDirection
        if astris.hash == base {
            direction = .toAstris
        } else if nxnative.hash == base {
            direction = .toNXNative
        } else {
            return .conflict(tr("Beide Seiten wurden seit dem letzten Abgleich verändert.", "Both sides changed since the last sync."))
        }
        let source = direction == .toAstris ? nxnative : astris
        let target = direction == .toAstris ? astris : nxnative
        if looksFresh(source: source, target: target) {
            return .conflict(tr("Der neue Stand ist auffällig klein oder hat weniger Dateien und könnte frisch angelegt sein.",
                                "The new save is unusually small or has fewer files and may be freshly created."))
        }
        return .copy(direction)
    }
}

// MARK: - State

struct SavePairState: Codable, Equatable {
    var baseHash: String?
    /// The Astris slot and user the base belongs to. Another slot is another save, not a change of this one.
    var slotID: String?
    var autoEnabled = false
    var approvedAstrisVersion: String?
    var approvedGameVersion: String?
    var lastSync: Date?
}

struct SaveSyncStateStore {
    let url: URL

    func read() -> [String: SavePairState] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: SavePairState].self, from: data)) ?? [:]
    }

    func write(_ states: [String: SavePairState]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(states).write(to: url, options: .atomic)
    }
}

// MARK: - Engine

struct SavePair: Equatable {
    let titleId: String
    let kind: SaveKind
    let nxnativeFolder: URL
    let slot: AstrisSlot?

    var key: String { "\(titleId.uppercased()).\(kind.rawValue)" }
    /// Slot and user together: another slot or profile is another save.
    var slotID: String? { slot.map { "\($0.url.lastPathComponent)|\($0.user)" } }
}

/// One folder to be replaced. The journal is written before anything moves, so an interrupted sync can always be sorted out.
private struct PendingSwap: Codable {
    var live: String
    var old: String
    var new: String
    var hadLive: Bool
}

private struct PendingSync: Codable {
    /// The hash the replaced folders must end up with.
    var expected: String
    /// Set once every folder is swapped and proven. From then on the new state stands, whatever happens.
    var committed = false
    var swaps: [PendingSwap]
}

final class SaveSyncEngine {
    let stateFolder: URL
    let backupFolder: URL
    let backupsToKeep: Int
    /// Runs right before anything is swapped, so a game started during the sync still stops it.
    var preflight: () throws -> Void = {}
    /// Called between the steps; tests use it to interrupt a sync at every point.
    var checkpoint: (String) throws -> Void = { _ in }

    init(stateFolder: URL, backupFolder: URL, backupsToKeep: Int = 10) {
        self.stateFolder = stateFolder
        self.backupFolder = backupFolder
        self.backupsToKeep = backupsToKeep
    }

    private var pendingFolder: URL { stateFolder.appendingPathComponent("pending") }
    private var rescueFolder: URL { stateFolder.appendingPathComponent("rescued") }

    /// Copies one side over the other and returns the new common hash.
    @discardableResult
    func apply(_ pair: SavePair, direction: SyncDirection) throws -> String {
        recover()
        guard let slot = pair.slot else { throw SaveSyncError.slotMissing }
        let astris = slot.committed
        let nxnative = pair.nxnativeFolder
        let source = direction == .toAstris ? nxnative : astris
        let before = SaveTree.snapshot(of: source)
        guard !before.isEmpty else { throw SaveSyncError.sourceMissing }
        let targetSide = direction == .toAstris ? astris : nxnative
        let targetBefore = SaveTree.snapshot(of: targetSide)
        // Astris's working folder is replaced too, so what it holds has to be unchanged at the end as well.
        let workingBefore = SaveTree.snapshot(of: slot.working)

        try backUp(pair, side: .astris, folder: slot.url)
        try backUp(pair, side: .nxnative, folder: nxnative)
        try checkpoint("backups")

        let fm = FileManager.default
        let token = UUID().uuidString
        var swaps: [PendingSwap] = []
        if direction == .toAstris {
            let staging = slot.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".nspm-sync/\(token)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            // Astris opens a save from "0" and rebuilds "1" from it; both get the same content so neither can win over the other.
            for name in ["0", "1"] {
                let live = slot.url.appendingPathComponent(name)
                swaps.append(PendingSwap(live: live.path, old: staging.appendingPathComponent("old\(name)").path,
                                         new: staging.appendingPathComponent("new\(name)").path, hadLive: fm.fileExists(atPath: live.path)))
            }
        } else {
            swaps.append(PendingSwap(live: nxnative.path, old: "\(nxnative.path).nspm-old-\(token)", new: "\(nxnative.path).nspm-new-\(token)",
                                     hadLive: fm.fileExists(atPath: nxnative.path)))
        }

        var pending = PendingSync(expected: before.hash, swaps: swaps)
        try write(pending, for: pair)
        do {
            try checkpoint("journal")
            for swap in swaps {
                try fm.copyItem(at: source, to: URL(fileURLWithPath: swap.new))
            }
            try checkpoint("staged")
            for swap in swaps where SaveTree.snapshot(of: URL(fileURLWithPath: swap.new)).hash != before.hash {
                throw SaveSyncError.stagingMismatch
            }
            guard SaveTree.snapshot(of: source).hash == before.hash,
                  SaveTree.snapshot(of: targetSide).hash == targetBefore.hash,
                  SaveTree.snapshot(of: slot.working).hash == workingBefore.hash else {
                throw SaveSyncError.changedDuringSync
            }
            try preflight()

            for swap in swaps {
                if swap.hadLive { try fm.moveItem(atPath: swap.live, toPath: swap.old) }
                try checkpoint("moved-old")
                try fm.moveItem(atPath: swap.new, toPath: swap.live)
                try checkpoint("moved-new")
            }
            for swap in swaps where SaveTree.snapshot(of: URL(fileURLWithPath: swap.live)).hash != before.hash {
                throw SaveSyncError.verifyFailed
            }
            try checkpoint("verified")

            pending.committed = true
            try write(pending, for: pair)
            try checkpoint("committed")
        } catch {
            // A checkpoint in a test stands for a kill: nothing further runs, as after a real one.
            if case SaveSyncTestStop.killed = error { throw error }
            recover()
            throw error
        }
        finish(pending, for: pair)
        try checkpoint("cleaned")
        prune(pair, side: .astris)
        prune(pair, side: .nxnative)
        return before.hash
    }

    /// Sorts out what an interrupted sync left. Call before any other work.
    /// A proven sync is completed. An unproven one is undone, and nothing that changed since is thrown away.
    func recover() {
        let files = (try? FileManager.default.contentsOfDirectory(at: pendingFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let pending = try? JSONDecoder().decode(PendingSync.self, from: data) else { continue }
            if !pending.committed { rollBack(pending) }
            removeLeftovers(pending)
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func rollBack(_ pending: PendingSync) {
        let fm = FileManager.default
        for swap in pending.swaps {
            let moved = !fm.fileExists(atPath: swap.new) && fm.fileExists(atPath: swap.live)
                && (swap.hadLive ? fm.fileExists(atPath: swap.old) : true)
            if moved {
                // Someone played on the half-finished state: kept, never deleted.
                if SaveTree.snapshot(of: URL(fileURLWithPath: swap.live)).hash != pending.expected {
                    let rescue = rescueFolder.appendingPathComponent(UUID().uuidString)
                    try? fm.createDirectory(at: rescueFolder, withIntermediateDirectories: true)
                    try? fm.copyItem(atPath: swap.live, toPath: rescue.path)
                }
                try? fm.removeItem(atPath: swap.live)
            }
            if !fm.fileExists(atPath: swap.live), fm.fileExists(atPath: swap.old) {
                try? fm.moveItem(atPath: swap.old, toPath: swap.live)
            }
        }
    }

    private func finish(_ pending: PendingSync, for pair: SavePair) {
        removeLeftovers(pending)
        try? FileManager.default.removeItem(at: pendingFolder.appendingPathComponent("\(pair.key).json"))
    }

    /// Removes what the sync prepared, once it no longer holds the only copy of anything.
    private func removeLeftovers(_ pending: PendingSync) {
        let fm = FileManager.default
        for swap in pending.swaps {
            try? fm.removeItem(atPath: swap.new)
            try? fm.removeItem(atPath: swap.old)
        }
        guard let first = pending.swaps.first, first.old.contains("/.nspm-sync/") else { return }
        let token = URL(fileURLWithPath: first.old).deletingLastPathComponent()
        try? fm.removeItem(at: token)
        let parent = token.deletingLastPathComponent()
        if (try? fm.contentsOfDirectory(atPath: parent.path))?.isEmpty == true { try? fm.removeItem(at: parent) }
    }

    private func write(_ pending: PendingSync, for pair: SavePair) throws {
        try FileManager.default.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: pendingFolder.appendingPathComponent("\(pair.key).json"), options: .atomic)
    }

    private func kindFolder(_ pair: SavePair) -> URL {
        backupFolder.appendingPathComponent(pair.titleId.uppercased()).appendingPathComponent(pair.kind.rawValue)
    }

    /// Copies a whole side and proves every file of the copy, including ExtraData and both folders of a slot.
    /// A side unchanged since its newest backup is not copied again, so failing syncs cannot push out good backups.
    private func backUp(_ pair: SavePair, side: SaveSide, folder: URL) throws {
        let fm = FileManager.default
        let original = SaveTree.snapshot(of: folder)
        guard fm.fileExists(atPath: folder.path) else {
            if side == .nxnative { return }
            throw SaveSyncError.backupFailed(folder.lastPathComponent)
        }
        let kindFolder = kindFolder(pair)
        if newestManifestHash(in: kindFolder, side: side) == original.hash, !original.isEmpty { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let target = kindFolder.appendingPathComponent("\(formatter.string(from: Date())) \(side.rawValue) \(UUID().uuidString.prefix(4))")
        do {
            try fm.createDirectory(at: kindFolder, withIntermediateDirectories: true)
            try fm.copyItem(at: folder, to: target)
        } catch {
            throw SaveSyncError.backupFailed(error.localizedDescription)
        }
        let listing = SaveTree.listing(of: folder)
        guard SaveTree.snapshot(of: target).hash == original.hash, SaveTree.listing(of: target) == listing else {
            try? fm.removeItem(at: target)
            throw SaveSyncError.backupFailed(tr("Die Kopie stimmt nicht mit dem Original überein", "The copy does not match the original"))
        }
        let manifest: [String: Any] = ["side": side.rawValue, "titleId": pair.titleId, "kind": pair.kind.rawValue, "hash": original.hash,
                                       "source": folder.path, "files": listing.map { ["path": $0.path, "size": $0.size, "sha256": $0.sha256] }]
        do {
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: kindFolder.appendingPathComponent(target.lastPathComponent + ".manifest.json"))
        } catch {
            try? fm.removeItem(at: target)
            throw SaveSyncError.backupFailed(error.localizedDescription)
        }
    }

    private func backupNames(in folder: URL, side: SaveSide) -> [String] {
        // The date leads each name, so sorting by name is sorting by time.
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.contains(" \(side.rawValue) ") && !$0.hasSuffix(".manifest.json") }.sorted()
    }

    private func newestManifestHash(in folder: URL, side: SaveSide) -> String? {
        guard let newest = backupNames(in: folder, side: side).last,
              let data = try? Data(contentsOf: folder.appendingPathComponent(newest + ".manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["hash"] as? String
    }

    /// Runs only after a successful sync, so failures never cost an older backup.
    private func prune(_ pair: SavePair, side: SaveSide) {
        let folder = kindFolder(pair)
        for name in backupNames(in: folder, side: side).dropLast(backupsToKeep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".manifest.json"))
        }
    }
}

/// Only thrown by test checkpoints, to stand for a process being killed at that point.
enum SaveSyncTestStop: Error {
    case killed
}
