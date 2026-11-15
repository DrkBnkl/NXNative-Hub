import Foundation

// MARK: - Switch 2 game sources (NUP container, dump folder)
//
// nxnative builds Switch 2 games from a `.nup` file or from a folder of the game's
// files (a dump), not from NSPs. Both are unencrypted, so neither needs prod.keys,
// and both require an nxnative profile. Layouts as read by scripts/pack_nup.py and
// scripts/pack_dump.py:
//
//   NUP:  superblock (0x80, TOC offset at 0x08) → TOC (0x30 header, package count at 0x04)
//         → package records (0x40 each: title ID, …, version at 0x14, kind at 0x18)
//   Dump: base/exefs/main.npdm, base/romfs/, updates/<version>/…, dlc/<DLC title ID>/<n>/romfs/
//         (exefs/ and romfs/ directly in the folder count as base/; a dump may have no base
//         when an update carries its own code and RomFS)

/// What a NUP or dump folder holds, as far as the import check needs it.
struct GameSourceContents {
    /// Program ID of the game (any of base / update title IDs), nil if unreadable.
    let titleId: String?
    /// Title versions: 0 for the base game (if the source has one) plus every update version.
    let versions: [Int]
}

enum NUPReader {
    private static let baseKind: UInt8 = 0
    private static let updateKind: UInt8 = 1

    static func isNUP(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return handle.readData(ofLength: 3) == Data("NUP".utf8)
    }

    static func read(_ url: URL) -> GameSourceContents? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let superblock = handle.readData(ofLength: 0x80)
        guard superblock.count == 0x80, superblock.prefix(3) == Data("NUP".utf8) else { return nil }
        let tocOffset = superblock.uint64(at: 0x08)

        guard (try? handle.seek(toOffset: tocOffset)) != nil else { return nil }
        let tocHeader = handle.readData(ofLength: 0x30)
        guard tocHeader.count == 0x30, tocHeader.prefix(4) == Data("TOC\u{1}".utf8) else { return nil }
        let packageCount = Int(tocHeader.uint32(at: 0x04))
        guard packageCount > 0, packageCount < 4096 else { return nil }

        let records = handle.readData(ofLength: packageCount * 0x40)
        guard records.count == packageCount * 0x40 else { return nil }

        var titleId: UInt64 = 0
        var versions: Set<Int> = []
        for i in 0..<packageCount {
            let base = i * 0x40
            let tid = records.uint64(at: base)
            let version = Int(records.uint32(at: base + 0x14))
            switch records[records.startIndex + base + 0x18] {
            case baseKind:
                versions.insert(0)
                // The base may be an empty placeholder with title ID 0 (Pokémon Pokopia).
                if tid != 0, titleId == 0 { titleId = tid }
            case updateKind:
                versions.insert(version)
                if titleId == 0 { titleId = tid }
            default:
                break
            }
        }
        return GameSourceContents(titleId: titleId == 0 ? nil : SwitchTitleID.format(titleId),
                                  versions: versions.sorted())
    }
}

enum DumpFolderReader {
    // The rules of scripts/pack_dump.py (has_code, is_version, base_of, is_dump).

    /// `exefs/main.npdm` is there: base/ or updates/<version>/ with its code.
    private static func hasCode(_ folder: URL) -> Bool {
        var isDir: ObjCBool = false
        let npdm = folder.appendingPathComponent("exefs/main.npdm").path
        return FileManager.default.fileExists(atPath: npdm, isDirectory: &isDir) && !isDir.boolValue
    }

    private static func hasRomFS(_ folder: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("romfs").path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Code and RomFS: one whole version of the game.
    private static func isVersion(_ folder: URL) -> Bool { hasCode(folder) && hasRomFS(folder) }

    /// The base game's folder: base/, or the folder itself when it holds exefs/ and romfs/
    /// directly; nil when the dump has no base.
    static func baseFolder(in folder: URL) -> URL? {
        let base = folder.appendingPathComponent("base")
        if hasCode(base) { return base }
        return isVersion(folder) ? folder : nil
    }

    static func isDump(_ folder: URL) -> Bool {
        let updates = updateFolders(in: folder)
        if let base = baseFolder(in: folder) {
            return hasRomFS(base) || updates.contains(where: hasRomFS)
        }
        return updates.contains(where: isVersion)
    }

    static func read(_ folder: URL) -> GameSourceContents {
        let base = baseFolder(in: folder)
        let updates = updateFolders(in: folder)
        // The title ID is the base game's program ID, else the newest whole update's.
        let codeFolder = base ?? updates.filter(isVersion).max { version(of: $0) < version(of: $1) }
        let npdm = codeFolder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("exefs/main.npdm")) }
        let versions = (base == nil ? [] : [0]) + updates.map(version(of:)).sorted()
        return GameSourceContents(titleId: npdm.flatMap(programID(npdm:)).map(SwitchTitleID.format),
                                  versions: versions)
    }

    private static func version(of updateFolder: URL) -> Int { Int(updateFolder.lastPathComponent) ?? 0 }

    /// updates/<version>/ folders (the version as a decimal number).
    static func updateFolders(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("updates"),
                                                                   includingPropertiesForKeys: [.isDirectoryKey],
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.filter {
            let name = $0.lastPathComponent
            return !name.isEmpty && name.allSatisfy { ("0"..."9").contains($0) }
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// The ACI0 program ID of an NPDM.
    private static func programID(npdm: Data) -> UInt64? {
        guard npdm.count >= 0x78, npdm.prefix(4) == Data("META".utf8) else { return nil }
        let offset = Int(npdm.uint32(at: 0x70))
        guard offset + 0x18 <= npdm.count,
              npdm.subdata(offset, 4) == Data("ACI0".utf8) else { return nil }
        return npdm.uint64(at: offset + 0x10)
    }

    /// Total size of all files below the folder.
    static func totalSize(of folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

/// How the build script will read a game folder (mirrors `nup_file` / `dump_folder`
/// in build_ipa_from_nsp.py: NSPs or XCIs in the folder take precedence).
enum GameSourceKind: Hashable {
    case packages   // NSP / XCI / NSZ / XCZ – needs prod.keys
    case nup(URL)   // one .nup container
    case dump       // folder of extracted files
    /// Switch 2 NSPs / XCIs: nxnative cannot build these yet, only NUPs and dumps.
    case switch2Packages([URL])
    case none

    var needsProdKeys: Bool { self == .packages }
    var isSwitch2Source: Bool {
        switch self {
        case .nup, .dump, .switch2Packages: return true
        case .packages, .none: return false
        }
    }

    static var switch2PackagesHint: String {
        tr("Switch-2-Spiele als NSP/XCI kann nxnative noch nicht bauen – nur als .nup-Datei oder Dump-Ordner (base/, updates/<Version>/, dlc/).",
           "nxnative cannot build Switch 2 games from NSP/XCI yet – only from a .nup file or a dump folder (base/, updates/<version>/, dlc/).")
    }

    /// The folder holds a game that nxnative can build.
    var isBuildable: Bool {
        switch self {
        case .packages, .nup, .dump: return true
        case .switch2Packages, .none: return false
        }
    }

    static func detect(in folder: URL) -> GameSourceKind {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        let packages = files.filter(NXPaths.isPackageFile)
        if !packages.isEmpty {
            return packages.contains(where: hasSwitch2TitleID) ? .switch2Packages(packages) : .packages
        }
        // One NUP per folder: with several the build script stops ("more than one NUP").
        let nups = nupFiles(in: files)
        if nups.count == 1 { return .nup(nups[0]) }
        if nups.count > 1 { return .none }
        if DumpFolderReader.isDump(folder) { return .dump }
        // Switch 2 NSPs sorted into base/, updates/ and dlc/ subfolders (as some dump tools write them)
        let nested = files
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .flatMap { sub in
                ((try? FileManager.default.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])) ?? [])
                    .filter(NXPaths.isPackageFile)
            }
        if nested.contains(where: hasSwitch2TitleID) { return .switch2Packages(nested) }
        return .none
    }

    private static func nupFiles(in files: [URL]) -> [URL] {
        files.filter { $0.pathExtension.lowercased() == "nup" && NUPReader.isNUP($0) }
    }

    /// The folder holds several NUPs and no game package: the build script cannot pick one.
    static func hasSeveralNUPs(in folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return !files.contains(where: NXPaths.isPackageFile) && nupFiles(in: files).count > 1
    }

    private static let switch2TitleIDRegex = try? NSRegularExpression(pattern: "\\[(04[0-9A-Fa-f]{14})\\]")

    /// "Name [0400…].nsp": a Switch 2 title ID in the file name.
    private static func hasSwitch2TitleID(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return switch2TitleIDRegex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// The first Switch 2 title ID found in the file names.
    static func switch2TitleID(in files: [URL]) -> String? {
        for url in files {
            let name = url.lastPathComponent
            if let match = switch2TitleIDRegex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
               let range = Range(match.range(at: 1), in: name) {
                return name[range].uppercased()
            }
        }
        return nil
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        subdata(offset, 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    func uint64(at offset: Int) -> UInt64 {
        subdata(offset, 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
    }

    func subdata(_ offset: Int, _ length: Int) -> Data {
        let start = startIndex + offset
        return subdata(in: start..<start + length)
    }
}
