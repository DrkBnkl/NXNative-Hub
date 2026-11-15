import AppKit
import Foundation

// MARK: - Save sync state and triggers
//
//  - Automatic sync only runs for a save the person approved after a test. An approval belongs to the
//    Astris and game versions it was given for; after a change the save waits for a new one.
//  - Nothing is written while Astris or the game runs.
//  - All file work runs on one serial queue, so two syncs can never meet.

struct SaveSyncRow: Identifiable, Equatable {
    var id: String { pair.key }
    let pair: SavePair
    let astris: SaveSnapshot
    let nxnative: SaveSnapshot
    let decision: SyncDecision
    let state: SavePairState
    /// Why nothing can be written right now, if so.
    let blockedReason: String?
    let needsNewApproval: Bool
}

final class SaveSyncManager: ObservableObject {
    static let shared = SaveSyncManager()
    static let astrisBundleId = "V380-Ori.Astris"

    @Published private(set) var rows: [String: [SaveSyncRow]] = [:]
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?

    private let queue = DispatchQueue(label: "org.nxnative.savesync")
    private let engine: SaveSyncEngine
    private let store: SaveSyncStateStore
    private var games: [InstalledGame] = []
    private var observer: NSObjectProtocol?

    private init() {
        let root = URL(fileURLWithPath: NXPaths.nxnativeRoot)
        engine = SaveSyncEngine(stateFolder: root.appendingPathComponent("SaveSync"), backupFolder: root.appendingPathComponent("SaveBackups"))
        store = SaveSyncStateStore(url: root.appendingPathComponent("SaveSync/state.json"))
        queue.async { [engine] in engine.recover() }

        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, id == Self.astrisBundleId || id.hasPrefix("org.nxnative.") else { return }
            // Give the game a moment to finish writing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.syncApproved() }
        }
    }

    // MARK: Reading

    /// Called whenever the library changes.
    func setGames(_ games: [InstalledGame]) {
        self.games = games
        syncApproved()
    }

    func refresh(titleId: String) {
        guard let game = games.first(where: { $0.titleId == titleId }) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let found = self.makeRows(for: game)
            DispatchQueue.main.async { self.rows[titleId] = found }
        }
    }

    private func makeRows(for game: InstalledGame) -> [SaveSyncRow] {
        let states = store.read()
        let root = AstrisSaves.dataRoots.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("bis/user/save").path) }
        let slots = root.map { AstrisSaves.slots(inDataRoot: $0) } ?? []
        let lastUser = root.flatMap { AstrisSaves.lastOpenedUser(inDataRoot: $0) }
        return SaveKind.allCases.compactMap { kind in
            let folder = URL(fileURLWithPath: NXPaths.gameConfigDirectory(titleId: game.titleId)).appendingPathComponent(kind.nxFolderName)
            let slot = AstrisSaves.slot(titleId: game.titleId, kind: kind, in: slots, lastOpenedUser: lastUser)
            let pair = SavePair(titleId: game.titleId, kind: kind, nxnativeFolder: folder, slot: slot)
            let astris = slot.map { SaveTree.snapshot(of: $0.committed) } ?? SaveSnapshot(hash: "", files: 0, bytes: 0, newest: nil)
            let nxnative = SaveTree.snapshot(of: folder)
            let working = slot.map { SaveTree.snapshot(of: $0.working) }
            // A second save kind only shows when a game has one.
            if kind == .device, slot == nil, nxnative.isEmpty { return nil }
            let state = states[pair.key] ?? SavePairState()
            // A base from another slot or profile says nothing about this one.
            let base = state.slotID == pair.slotID ? state.baseHash : nil
            return SaveSyncRow(pair: pair, astris: astris, nxnative: nxnative,
                               decision: SaveSyncRules.decide(astris: astris, nxnative: nxnative, base: base, astrisWorking: working),
                               state: state, blockedReason: blockedReason(for: game),
                               needsNewApproval: state.autoEnabled && !approvalIsCurrent(state, game: game))
        }
    }

    private func bundleId(of game: InstalledGame) -> String {
        GameBundleInfo(appPath: game.path)?.bundleId ?? "org.nxnative.\(game.titleId.lowercased())"
    }

    /// The name of a running program that uses this game's saves. The save folders are also used by plain Ryujinx.
    private func runningUser(of game: InstalledGame) -> String? {
        let bundle = bundleId(of: game)
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == Self.astrisBundleId { return "Astris" }
            if app.localizedName?.localizedCaseInsensitiveContains("Ryujinx") == true { return "Ryujinx" }
            if app.bundleIdentifier == bundle { return game.name }
        }
        return nil
    }

    /// Syncs with one last look for a running game right before anything is swapped.
    private func syncNow(_ row: SaveSyncRow, game: InstalledGame, direction: SyncDirection) throws {
        engine.preflight = { [self] in
            if let name = runningUser(of: game) { throw SaveSyncError.gameRunning(name) }
        }
        let hash = try engine.apply(row.pair, direction: direction)
        try update(row.pair) { state in
            state.baseHash = hash
            state.slotID = row.pair.slotID
            state.lastSync = Date()
        }
    }

    private func blockedReason(for game: InstalledGame) -> String? {
        if let name = runningUser(of: game) {
            return tr("\(name) läuft.", "\(name) is running.")
        }
        let bundle = bundleId(of: game)
        // Two syncs on one save would work against each other.
        if let folder = CFPreferencesCopyAppValue("cloudSaves.folder" as CFString, bundle as CFString) as? String, !folder.isEmpty {
            return tr("Für dieses Spiel sind die Cloud-Spielstände von nxnative aktiv.", "nxnative's cloud saves are on for this game.")
        }
        return nil
    }

    private var astrisVersion: String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.astrisBundleId)
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
    }

    private func approvalIsCurrent(_ state: SavePairState, game: InstalledGame) -> Bool {
        state.approvedAstrisVersion == astrisVersion && state.approvedGameVersion == game.version
    }

    // MARK: Actions

    /// A sync the person chose, in the direction they chose.
    func apply(_ row: SaveSyncRow, direction: SyncDirection) {
        guard let game = games.first(where: { $0.titleId == row.pair.titleId }) else { return }
        run { [self] in
            if let reason = blockedReason(for: game) { return reason }
            do {
                try syncNow(row, game: game, direction: direction)
                return nil
            } catch {
                return "\(error)"
            }
        } done: { [self] in refresh(titleId: game.titleId) }
    }

    /// Turns on automatic sync, with the versions the person tested.
    func approve(_ row: SaveSyncRow) {
        guard let game = games.first(where: { $0.titleId == row.pair.titleId }) else { return }
        let version = astrisVersion
        run { [self] in
            do {
                try update(row.pair) { state in
                    state.autoEnabled = true
                    state.approvedAstrisVersion = version
                    state.approvedGameVersion = game.version
                    state.baseHash = row.astris.hash
                    state.slotID = row.pair.slotID
                }
                return nil
            } catch {
                return "\(error)"
            }
        } done: { [self] in refresh(titleId: game.titleId) }
    }

    func disableAuto(_ row: SaveSyncRow) {
        run { [self] in
            do {
                try update(row.pair) { $0.autoEnabled = false }
                return nil
            } catch {
                return "\(error)"
            }
        } done: { [self] in refresh(titleId: row.pair.titleId) }
    }

    /// Syncs every approved save that changed on one side only. Conflicts wait for the person.
    func syncApproved(titleId: String? = nil, then completion: (() -> Void)? = nil) {
        let targets = games.filter { titleId == nil || $0.titleId == titleId }
        run { [self] in
            var notes: [String] = []
            for game in targets {
                for row in makeRows(for: game) where row.state.autoEnabled && !row.needsNewApproval && row.blockedReason == nil {
                    switch row.decision {
                    case .copy(let direction):
                        do {
                            try syncNow(row, game: game, direction: direction)
                        } catch {
                            notes.append("\(game.name): \(error)")
                        }
                    case .conflict(let reason):
                        notes.append("\(game.name): \(reason)")
                    case .inSync:
                        // Equal again, for example after a sync that was completed on restart.
                        if row.state.baseHash != row.astris.hash || row.state.slotID != row.pair.slotID {
                            try? update(row.pair) { state in
                                state.baseHash = row.astris.hash
                                state.slotID = row.pair.slotID
                            }
                        }
                    case .noSaves, .setupNeeded:
                        break
                    }
                }
            }
            return notes.isEmpty ? nil : notes.joined(separator: "\n")
        } done: { [self] in
            for game in targets { refresh(titleId: game.titleId) }
            if let message {
                Notifier.post(title: tr("Spielstände brauchen dich", "Saves need your attention"), body: message)
            }
            completion?()
        }
    }

    private func update(_ pair: SavePair, change: (inout SavePairState) -> Void) throws {
        var states = store.read()
        var state = states[pair.key] ?? SavePairState()
        change(&state)
        states[pair.key] = state
        try store.write(states)
    }

    private func run(_ work: @escaping () -> String?, done: @escaping () -> Void) {
        isBusy = true
        queue.async { [weak self] in
            let result = work()
            DispatchQueue.main.async {
                self?.isBusy = false
                self?.message = result
                done()
            }
        }
    }
}
