import Foundation

// Tests for Sources/Core/SaveSync.swift. They only touch a temporary folder, never real saves.
// Run: Tests/SaveSyncTests/run.sh

func tr(_ german: String, _ english: String) -> String { german }

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FEHLER Zeile \(line): \(message)")
    }
}

let fm = FileManager.default
let realSaves: URL? = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil

final class World {
    let root = fm.temporaryDirectory.appendingPathComponent("savesync-\(UUID().uuidString)")
    let engine: SaveSyncEngine
    let pair: SavePair
    let slotFolder: URL
    let nx: URL

    init(astris: [String: String]? = ["a.dat": "astris"], nxnative: [String: String]? = ["a.dat": "nx"], keep: Int = 10) {
        slotFolder = root.appendingPathComponent("Ryujinx/bis/user/save/0000000000000001")
        nx = root.appendingPathComponent("nxnative/0100000000010000/save")
        engine = SaveSyncEngine(stateFolder: root.appendingPathComponent("state"), backupFolder: root.appendingPathComponent("backups"), backupsToKeep: keep)
        try! fm.createDirectory(at: slotFolder, withIntermediateDirectories: true)
        try! fm.createDirectory(at: nx.deletingLastPathComponent(), withIntermediateDirectories: true)
        var extra = Data(count: 512)
        extra.replaceSubrange(0..<8, with: withUnsafeBytes(of: UInt64(0x0100000000010000).littleEndian) { Data($0) })
        extra[8] = 1
        extra[0x20] = 1
        try! extra.write(to: slotFolder.appendingPathComponent("ExtraData0"))
        try! extra.write(to: slotFolder.appendingPathComponent("ExtraData1"))
        if let astris {
            World.write(astris, to: slotFolder.appendingPathComponent("0"))
            World.write(astris, to: slotFolder.appendingPathComponent("1"))
        }
        if let nxnative { World.write(nxnative, to: nx) }
        let slot = AstrisSaves.slots(inDataRoot: root.appendingPathComponent("Ryujinx")).first
        pair = SavePair(titleId: "0100000000010000", kind: .account, nxnativeFolder: nx, slot: slot)
    }

    static func write(_ files: [String: String], to folder: URL) {
        try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = folder.appendingPathComponent(name)
            try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(content.utf8).write(to: url)
        }
    }

    func text(_ url: URL, _ name: String = "a.dat") -> String? { try? String(contentsOf: url.appendingPathComponent(name), encoding: .utf8) }
    var committed: URL { slotFolder.appendingPathComponent("0") }
    var working: URL { slotFolder.appendingPathComponent("1") }
    var backups: [String] { (try? fm.subpathsOfDirectory(atPath: root.appendingPathComponent("backups").path)) ?? [] }
    func cleanUp() { try? fm.removeItem(at: root) }
}

// MARK: Hash

do {
    let world = World(astris: ["a.dat": "gleich", "b/c.dat": "x"], nxnative: ["b/c.dat": "x", "a.dat": "gleich"])
    expect(SaveTree.snapshot(of: world.committed).hash == SaveTree.snapshot(of: world.nx).hash, "Gleicher Inhalt, gleicher Hash")
    expect(SaveTree.snapshot(of: world.nx).files == 2, "Zwei Dateien")
    try! Data("x".utf8).write(to: world.nx.appendingPathComponent(".DS_Store"))
    expect(SaveTree.snapshot(of: world.committed).hash == SaveTree.snapshot(of: world.nx).hash, ".DS_Store zählt nicht")
    try! Data("y".utf8).write(to: world.nx.appendingPathComponent("a.dat"))
    expect(SaveTree.snapshot(of: world.committed).hash != SaveTree.snapshot(of: world.nx).hash, "Anderer Inhalt, anderer Hash")
    expect(SaveTree.snapshot(of: world.root.appendingPathComponent("weg")).isEmpty, "Fehlend zählt als leer")
    world.cleanUp()
}

// MARK: Decisions

do {
    func snap(_ hash: String, _ bytes: UInt64 = 1000) -> SaveSnapshot { SaveSnapshot(hash: hash, files: 1, bytes: bytes, newest: nil) }
    let empty = SaveSnapshot(hash: "", files: 0, bytes: 0, newest: nil)
    expect(SaveSyncRules.decide(astris: snap("a"), nxnative: snap("a"), base: nil) == .inSync, "Gleich ist abgeglichen")
    expect(SaveSyncRules.decide(astris: empty, nxnative: empty, base: nil) == .noSaves, "Beide leer")
    expect(SaveSyncRules.decide(astris: snap("a"), nxnative: snap("b"), base: nil) == .setupNeeded, "Ohne Basis entscheidet die Person")
    expect(SaveSyncRules.decide(astris: snap("a"), nxnative: snap("b"), base: "a") == .copy(.toAstris), "Nur nxnative geändert")
    expect(SaveSyncRules.decide(astris: snap("b"), nxnative: snap("a"), base: "a") == .copy(.toNXNative), "Nur Astris geändert")
    if case .conflict = SaveSyncRules.decide(astris: snap("b"), nxnative: snap("c"), base: "a") {} else { expect(false, "Beide geändert ist ein Konflikt") }
    if case .conflict = SaveSyncRules.decide(astris: snap("b", 100), nxnative: snap("a", 1000), base: "a") {} else { expect(false, "Frischer Stand überschreibt nicht") }
    if case .conflict = SaveSyncRules.decide(astris: empty, nxnative: snap("a"), base: "a") {} else { expect(false, "Leere Quelle überschreibt nicht") }
    let fewer = SaveSnapshot(hash: "b", files: 1, bytes: 1000, newest: nil)
    let more = SaveSnapshot(hash: "a", files: 5, bytes: 1000, newest: nil)
    if case .conflict = SaveSyncRules.decide(astris: fewer, nxnative: more, base: "a") {} else { expect(false, "Weniger Dateien überschreiben nicht") }
    if case .conflict = SaveSyncRules.decide(astris: snap("a"), nxnative: snap("b"), base: "a", astrisWorking: snap("c")) {} else { expect(false, "Abweichender Ordner 1 stoppt die Automatik") }
    expect(SaveSyncRules.decide(astris: snap("a"), nxnative: snap("b"), base: "a", astrisWorking: snap("a")) == .copy(.toAstris), "Gleicher Ordner 1 stört nicht")
    expect(SaveSyncRules.decide(astris: snap("a"), nxnative: snap("b"), base: "a", astrisWorking: empty) == .copy(.toAstris), "Fehlender Ordner 1 stört nicht")
}

// MARK: Slots

do {
    let world = World()
    let root = world.root.appendingPathComponent("Ryujinx")
    let device = root.appendingPathComponent("bis/user/save/0000000000000002")
    try! fm.createDirectory(at: device, withIntermediateDirectories: true)
    var extra = Data(count: 512)
    extra.replaceSubrange(0..<8, with: withUnsafeBytes(of: UInt64(0x0100000000010000).littleEndian) { Data($0) })
    extra[0x20] = 3
    try! extra.write(to: device.appendingPathComponent("ExtraData0"))
    let slots = AstrisSaves.slots(inDataRoot: root)
    expect(slots.count == 2, "Zwei Slots")
    expect(AstrisSaves.slot(titleId: "0100000000010000", kind: .device, in: slots, lastOpenedUser: nil)?.url.lastPathComponent == "0000000000000002", "Geräte-Spielstand wird nicht mit dem Benutzer-Spielstand verwechselt")
    expect(AstrisSaves.slot(titleId: "0100000000010000", kind: .account, in: slots, lastOpenedUser: nil)?.url.lastPathComponent == "0000000000000001", "Benutzer-Spielstand")
    expect(AstrisSaves.slot(titleId: "0100000000099000", kind: .account, in: slots, lastOpenedUser: nil) == nil, "Fremdes Spiel hat keinen Slot")

    let second = AstrisSlot(url: device, titleId: "0100000000010000", type: 1, user: "02" + String(repeating: "0", count: 30))
    let first = slots[0]
    expect(AstrisSaves.slot(titleId: first.titleId, kind: .account, in: [second, first], lastOpenedUser: first.user)?.url == first.url, "Mehrere Profile: das zuletzt geöffnete")
    expect(AstrisSaves.slot(titleId: first.titleId, kind: .account, in: [second, first], lastOpenedUser: nil) == nil, "Mehrere Profile ohne Angabe: keine Vermutung")

    try! fm.createDirectory(at: root.appendingPathComponent("system"), withIntermediateDirectories: true)
    try! Data(#"{"last_opened":"00000000000000010000000000000000"}"#.utf8).write(to: root.appendingPathComponent("system/Profiles.json"))
    expect(AstrisSaves.lastOpenedUser(inDataRoot: root) == "01000000000000000000000000000000", "Profil-ID wird wie in ExtraData gelesen")
    world.cleanUp()
}

// MARK: Copying

do {
    let world = World()
    let hash = try! world.engine.apply(world.pair, direction: .toAstris)
    expect(world.text(world.committed) == "nx", "Astris 0 hat den neuen Stand")
    expect(world.text(world.working) == "nx", "Astris 1 hat den neuen Stand")
    expect(world.text(world.nx) == "nx", "Quelle unverändert")
    expect(hash == SaveTree.snapshot(of: world.nx).hash, "Hash passt")
    expect(fm.fileExists(atPath: world.slotFolder.appendingPathComponent("ExtraData0").path), "ExtraData bleibt")
    expect(!fm.fileExists(atPath: world.root.appendingPathComponent("Ryujinx/bis/user/.nspm-sync").path), "Keine Reste bei Astris")
    expect(world.backups.contains { $0.contains(" astris ") && $0.hasSuffix("0/a.dat") }, "Backup von Astris")
    expect(world.backups.contains { $0.contains(" nxnative ") && $0.hasSuffix("a.dat") }, "Backup von nxnative")
    expect(world.backups.contains { $0.contains(" astris ") && $0.hasSuffix("ExtraData0") }, "Backup enthält ExtraData")
    expect(world.pair.slotID == "0000000000000001|01000000000000000000000000000000", "Slot-Kennung aus Ordner und Benutzer: \(world.pair.slotID ?? "-")")
    expect(world.backups.contains { $0.hasSuffix(".manifest.json") }, "Backup hat ein Manifest")
    world.cleanUp()
}

do {
    let world = World()
    try! world.engine.apply(world.pair, direction: .toNXNative)
    expect(world.text(world.nx) == "astris", "nxnative hat den neuen Stand")
    let siblings = try! fm.contentsOfDirectory(atPath: world.nx.deletingLastPathComponent().path)
    expect(siblings == ["save"], "Keine Reste neben save: \(siblings)")
    world.cleanUp()
}

do {
    let world = World(astris: nil)
    expect((try? world.engine.apply(SavePair(titleId: world.pair.titleId, kind: .account, nxnativeFolder: world.nx, slot: nil), direction: .toAstris)) == nil, "Ohne Slot kein Schreiben")
    world.cleanUp()
}

do {
    let world = World(nxnative: nil)
    do {
        try world.engine.apply(world.pair, direction: .toAstris)
        expect(false, "Leere Quelle muss scheitern")
    } catch {
        expect(error as? SaveSyncError == .sourceMissing, "Leere Quelle: \(error)")
    }
    expect(world.text(world.committed) == "astris", "Ziel unverändert")
    world.cleanUp()
}

// MARK: Faults

// Killed at every occurrence of every step, a restart must leave the complete old state or the complete new one, never a mix.
func state(_ world: World, _ direction: SyncDirection) -> (target: String, working: String) {
    (SaveTree.snapshot(of: direction == .toAstris ? world.committed : world.nx).hash, SaveTree.snapshot(of: world.working).hash)
}

let steps: [(name: String, toAstris: Int, toNX: Int, completes: Bool)] = [
    ("backups", 1, 1, false), ("journal", 1, 1, false), ("staged", 1, 1, false), ("moved-old", 2, 1, false), ("moved-new", 2, 1, false),
    ("verified", 1, 1, false), ("committed", 1, 1, true), ("cleaned", 1, 1, true)
]
var killPoints = 0
for direction in [SyncDirection.toAstris, .toNXNative] {
    for step in steps {
        for occurrence in 1...(direction == .toAstris ? step.toAstris : step.toNX) {
            let world = World(astris: ["a.dat": "astris", "sub/b.dat": "alt"], nxnative: ["a.dat": "nx", "sub/b.dat": "neu"])
            let sourceURL = direction == .toAstris ? world.nx : world.committed
            let targetURL = direction == .toAstris ? world.committed : world.nx
            let sourceHash = SaveTree.snapshot(of: sourceURL).hash
            let targetHash = SaveTree.snapshot(of: targetURL).hash
            let workingHash = SaveTree.snapshot(of: world.working).hash
            var seen = 0
            world.engine.checkpoint = { point in
                if point == step.name {
                    seen += 1
                    if seen == occurrence { throw SaveSyncTestStop.killed }
                }
            }
            expect((try? world.engine.apply(world.pair, direction: direction)) == nil, "\(step.name)#\(occurrence): soll abbrechen")
            world.engine.checkpoint = { _ in }
            world.engine.recover()
            killPoints += 1
            let label = "\(direction) \(step.name)#\(occurrence)"
            if step.completes {
                expect(SaveTree.snapshot(of: targetURL).hash == sourceHash, "\(label): bestätigter Stand bleibt")
                if direction == .toAstris { expect(SaveTree.snapshot(of: world.working).hash == sourceHash, "\(label): auch Ordner 1 neu") }
            } else {
                expect(SaveTree.snapshot(of: targetURL).hash == targetHash, "\(label): alter Stand zurück")
                if direction == .toAstris { expect(SaveTree.snapshot(of: world.working).hash == workingHash, "\(label): auch Ordner 1 alt") }
            }
            expect(SaveTree.snapshot(of: sourceURL).hash == sourceHash, "\(label): Quelle unverändert")
            let pending = (try? fm.contentsOfDirectory(atPath: world.root.appendingPathComponent("state/pending").path)) ?? []
            expect(pending.isEmpty, "\(label): Journal leer")
            let siblings = (try? fm.contentsOfDirectory(atPath: world.nx.deletingLastPathComponent().path)) ?? []
            expect(siblings == ["save"], "\(label): keine Reste neben save: \(siblings)")
            expect(!fm.fileExists(atPath: world.root.appendingPathComponent("Ryujinx/bis/user/.nspm-sync").path), "\(label): keine Reste bei Astris")
            // After a restart the same sync must work.
            if !step.completes {
                try! world.engine.apply(world.pair, direction: direction)
                expect(SaveTree.snapshot(of: targetURL).hash == sourceHash, "\(label): zweiter Versuch klappt")
            }
            world.cleanUp()
        }
    }
}
expect(killPoints == 18, "Alle Abbruchstellen erreicht: \(killPoints)")

// The Hub dies right after a proven sync, the person plays, and only then does it restart: the progress stays.
do {
    let world = World()
    world.engine.checkpoint = { if $0 == "committed" { throw SaveSyncTestStop.killed } }
    _ = try? world.engine.apply(world.pair, direction: .toAstris)
    try! Data("stundenlang gespielt".utf8).write(to: world.committed.appendingPathComponent("a.dat"))
    world.engine.checkpoint = { _ in }
    world.engine.recover()
    expect(world.text(world.committed) == "stundenlang gespielt", "Neuer Fortschritt bleibt nach dem Neustart")
    world.cleanUp()
}

// Between the two swaps a game writes to the half-finished state: undone, but the data is kept aside.
do {
    let world = World()
    var seen = 0
    world.engine.checkpoint = { point in
        if point == "moved-new" {
            seen += 1
            if seen == 1 { throw SaveSyncTestStop.killed }
        }
    }
    _ = try? world.engine.apply(world.pair, direction: .toAstris)
    try! Data("gespeichert".utf8).write(to: world.committed.appendingPathComponent("a.dat"))
    world.engine.checkpoint = { _ in }
    world.engine.recover()
    expect(world.text(world.committed) == "astris", "Alter Stand zurück")
    let rescued = (try? fm.subpathsOfDirectory(atPath: world.root.appendingPathComponent("state/rescued").path)) ?? []
    expect(rescued.contains { $0.hasSuffix("a.dat") }, "Geschriebenes bleibt erhalten: \(rescued)")
    world.cleanUp()
}

// A folder that did not exist before is gone again after an undo.
do {
    let world = World()
    try! fm.removeItem(at: world.working)
    var seen = 0
    world.engine.checkpoint = { point in
        if point == "moved-new" {
            seen += 1
            if seen == 2 { throw SaveSyncTestStop.killed }
        }
    }
    _ = try? world.engine.apply(world.pair, direction: .toAstris)
    world.engine.checkpoint = { _ in }
    world.engine.recover()
    expect(world.text(world.committed) == "astris", "Ordner 0 alt")
    expect(!fm.fileExists(atPath: world.working.path), "Ordner 1 fehlt wieder, kein Mischzustand")
    world.cleanUp()
}

// A game starts in the moment before the swap.
do {
    let world = World()
    world.engine.preflight = { throw SaveSyncError.gameRunning("Astris") }
    do {
        try world.engine.apply(world.pair, direction: .toAstris)
        expect(false, "Laufendes Spiel muss stoppen")
    } catch {
        expect(error as? SaveSyncError == .gameRunning("Astris"), "\(error)")
    }
    expect(world.text(world.committed) == "astris", "Nichts ersetzt")
    world.cleanUp()
}

do {
    let world = World()
    world.engine.checkpoint = { point in
        if point == "staged" { try! Data("neu gespielt".utf8).write(to: world.nx.appendingPathComponent("a.dat")) }
    }
    do {
        try world.engine.apply(world.pair, direction: .toAstris)
        expect(false, "Änderung während des Abgleichs muss stoppen")
    } catch {
        expect(error as? SaveSyncError == .changedDuringSync, "\(error)")
    }
    expect(world.text(world.committed) == "astris", "Ziel bleibt")
    expect(world.text(world.nx) == "neu gespielt", "Neue Quelle bleibt")
    world.cleanUp()
}

do {
    // The target changes before staging ends: a game was saving on it.
    let world = World()
    world.engine.checkpoint = { point in
        if point == "staged" { try! Data("Astris speichert".utf8).write(to: world.committed.appendingPathComponent("a.dat")) }
    }
    expect((try? world.engine.apply(world.pair, direction: .toAstris)) == nil, "Änderung am Ziel muss stoppen")
    expect(world.text(world.committed) == "Astris speichert", "Ziel nicht überschrieben")
    world.cleanUp()
}

do {
    // New data only in the working folder.
    let world = World()
    world.engine.checkpoint = { point in
        if point == "staged" { try! Data("nur in 1".utf8).write(to: world.working.appendingPathComponent("a.dat")) }
    }
    expect((try? world.engine.apply(world.pair, direction: .toAstris)) == nil, "Änderung in Ordner 1 muss stoppen")
    expect(world.text(world.working) == "nur in 1", "Ordner 1 nicht überschrieben")
    world.cleanUp()
}

do {
    let world = World()
    world.engine.checkpoint = { point in if point == "moved-new" { throw SaveSyncError.verifyFailed } }
    expect((try? world.engine.apply(world.pair, direction: .toNXNative)) == nil, "Fehler nach dem Tausch")
    expect(world.text(world.nx) == "nx", "Fehler rollt sofort zurück")
    world.cleanUp()
}

do {
    let world = World()
    let blocker = world.root.appendingPathComponent("backups")
    try! Data().write(to: blocker)
    do {
        try world.engine.apply(world.pair, direction: .toAstris)
        expect(false, "Ohne Backup kein Schreiben")
    } catch {
        if case SaveSyncError.backupFailed = error {} else { expect(false, "\(error)") }
    }
    expect(world.text(world.committed) == "astris", "Ziel unverändert ohne Backup")
    world.cleanUp()
}

// MARK: Backups

do {
    // Failing syncs must not push out good backups.
    let world = World(keep: 1)
    world.engine.preflight = { throw SaveSyncError.gameRunning("x") }
    let folder = world.root.appendingPathComponent("backups/0100000000010000/account")
    for _ in 0..<3 {
        _ = try? world.engine.apply(world.pair, direction: .toAstris)
        Thread.sleep(forTimeInterval: 1.05)
    }
    let names = try! fm.contentsOfDirectory(atPath: folder.path)
    expect(names.filter { $0.contains(" astris ") && !$0.hasSuffix(".json") }.count == 1, "Unveränderter Stand wird nicht mehrfach gesichert: \(names)")
    world.cleanUp()
}

do {
    let world = World()
    try! Data("gestört".utf8).write(to: world.working.appendingPathComponent("a.dat"))
    try! world.engine.apply(world.pair, direction: .toAstris)
    let folder = world.root.appendingPathComponent("backups/0100000000010000/account")
    let manifestName = try! fm.contentsOfDirectory(atPath: folder.path).first { $0.contains(" astris ") && $0.hasSuffix(".manifest.json") }!
    let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(manifestName))) as! [String: Any]
    let files = manifest["files"] as! [[String: Any]]
    let paths = files.map { $0["path"] as! String }
    expect(paths.contains("ExtraData0") && paths.contains("0/a.dat") && paths.contains("1/a.dat"), "Manifest listet jede Datei: \(paths)")
    expect(files.allSatisfy { ($0["sha256"] as? String)?.count == 64 }, "Manifest hat SHA-256")
    let backup = folder.appendingPathComponent(String(manifestName.dropLast(".manifest.json".count)))
    expect(world.text(backup.appendingPathComponent("1")) == "gestört", "Backup enthält auch Ordner 1")
    world.cleanUp()
}

// MARK: Backup retention

do {
    let world = World(keep: 2)
    for round in 0..<4 {
        try! Data("r\(round)".utf8).write(to: world.nx.appendingPathComponent("a.dat"))
        try! world.engine.apply(world.pair, direction: .toAstris)
        Thread.sleep(forTimeInterval: 1.05)
    }
    let folder = world.root.appendingPathComponent("backups/0100000000010000/account")
    let names = try! fm.contentsOfDirectory(atPath: folder.path)
    expect(names.filter { $0.contains(" astris ") && !$0.hasSuffix(".json") }.count == 2, "Zwei Astris-Backups bleiben: \(names)")
    expect(names.filter { $0.contains(" nxnative ") && !$0.hasSuffix(".json") }.count == 2, "Zwei nxnative-Backups bleiben")
    expect(names.filter { $0.hasSuffix(".manifest.json") }.count == 4, "Manifeste folgen den Backups")
    world.cleanUp()
}

// MARK: State

do {
    let world = World()
    let store = SaveSyncStateStore(url: world.root.appendingPathComponent("state/state.json"))
    expect(store.read().isEmpty, "Leer ohne Datei")
    try! store.write(["k": SavePairState(baseHash: "h", autoEnabled: true)])
    expect(store.read()["k"]?.baseHash == "h", "Zustand bleibt")
    world.cleanUp()
}

// MARK: Copies of real saves, if a folder of them was given

if let realSaves {
    let titles = (try? fm.contentsOfDirectory(at: realSaves, includingPropertiesForKeys: nil)) ?? []
    for title in titles.filter({ !$0.lastPathComponent.hasPrefix(".") }) {
        let astris = title.appendingPathComponent("astris")
        let nx = title.appendingPathComponent("nx")
        let world = World(astris: nil, nxnative: nil)
        try! fm.copyItem(at: astris, to: world.committed)
        try! fm.copyItem(at: astris, to: world.working)
        try! fm.copyItem(at: nx, to: world.nx)
        let nxBefore = SaveTree.snapshot(of: world.nx)
        let astrisBefore = SaveTree.snapshot(of: world.committed)
        if nxBefore.isEmpty {
            // A real case: Mario Kart 8 Deluxe's device save can be empty on one side.
            expect((try? world.engine.apply(world.pair, direction: .toAstris)) == nil, "\(title.lastPathComponent): leere Quelle überschreibt nichts")
            expect(SaveTree.snapshot(of: world.committed).hash == astrisBefore.hash, "\(title.lastPathComponent): Ziel unverändert")
            print("  \(title.lastPathComponent): nxnative leer, Astris \(astrisBefore.files) Dateien / \(astrisBefore.bytes) B")
            world.cleanUp()
            continue
        }
        try! world.engine.apply(world.pair, direction: .toAstris)
        expect(SaveTree.snapshot(of: world.committed).hash == nxBefore.hash, "\(title.lastPathComponent): nach Astris")
        expect(SaveTree.snapshot(of: world.working).hash == nxBefore.hash, "\(title.lastPathComponent): auch Astris 1")
        let backup = (try! fm.subpathsOfDirectory(atPath: world.root.appendingPathComponent("backups").path)).first { $0.contains(" astris ") && $0.hasSuffix("/0") }
        expect(backup != nil, "\(title.lastPathComponent): Backup da")
        if let backup {
            expect(SaveTree.snapshot(of: world.root.appendingPathComponent("backups").appendingPathComponent(backup)).hash == astrisBefore.hash, "\(title.lastPathComponent): Backup gleicht dem alten Stand")
        }
        print("  \(title.lastPathComponent): Astris \(astrisBefore.files) Dateien / \(astrisBefore.bytes) B, nxnative \(nxBefore.files) Dateien / \(nxBefore.bytes) B")
        world.cleanUp()
    }
}

print("\(checks) Prüfungen, \(failures) Fehler")
exit(failures == 0 ? 0 : 1)
