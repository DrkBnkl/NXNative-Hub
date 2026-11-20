import Foundation

// MARK: - System-wide detection of running builds
//
// Also detects builds started outside the app (e.g. in Terminal).
//  - Calls `/bin/ps` directly (no shell pipeline).
//  - A new check only starts after the previous one finished (no pile-up).
//  - JSON lines are parsed with the shared `BuildEvent` parser.

struct ActiveBuildInfo: Equatable, Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let gameName: String
    let gameDirectory: String
    let buildDirectory: String?
    let currentStageDescription: String
    let compiledShadersCount: Int?
    let latestLogFile: String?
    let recentLogLines: [String]
    /// Stages, progress and log entries read from `latestLogFile`.
    var timeline: BuildTimeline?
}

/// Reads a growing log file from where the last read stopped and feeds a timeline.
/// Only used on the monitor's serial queue.
private final class LogFollower {
    private var path: String?
    private var offset: UInt64 = 0
    private var partial = Data()
    private(set) var timeline = BuildTimeline()

    /// Larger logs are read from this many bytes before their end (a JSON log of a long build).
    private static let maxInitialRead: UInt64 = 16 << 20

    func update(path newPath: String) -> BuildTimeline {
        guard let handle = FileHandle(forReadingAtPath: newPath) else { return timeline }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var skipFirstLine = false
        if newPath != path || size < offset {   // another file, or the file was truncated
            path = newPath
            timeline = BuildTimeline()
            partial = Data()
            offset = size > Self.maxInitialRead ? size - Self.maxInitialRead : 0
            skipFirstLine = offset > 0
        }
        guard size > offset else { return timeline }
        try? handle.seek(toOffset: offset)
        var data = partial + ((try? handle.read(upToCount: Int(size - offset))) ?? Data())
        offset = size
        if skipFirstLine, let nl = data.firstIndex(of: 0x0A) { data = data[(nl + 1)...] }
        // Keep an unfinished last line for the next read.
        if let lastNL = data.lastIndex(of: 0x0A) {
            partial = Data(data[(lastNL + 1)...])
            data = data[..<lastNL]
        } else {
            partial = Data(data); return timeline
        }
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "\n")
        for line in text.split(separator: "\n") { timeline.consume(String(line)) }
        return timeline
    }
}

final class ActiveBuildMonitor: ObservableObject {
    @Published private(set) var activeBuild: ActiveBuildInfo?

    private var timer: Timer?
    private var isChecking = false
    private static let follower = LogFollower()
    private let queue = DispatchQueue(label: "org.nxnative.buildMonitor", qos: .utility)

    init() {
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    func startMonitoring() {
        timer?.invalidate()
        checkActiveBuild()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.checkActiveBuild()
        }
    }

    func checkActiveBuild() {
        guard !isChecking else { return }
        isChecking = true
        queue.async { [weak self] in
            let info = Self.detectRunningBuild()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                if self.activeBuild != info { self.activeBuild = info }
            }
        }
    }

    // MARK: Detection

    private static func detectRunningBuild() -> ActiveBuildInfo? {
        let ps = CommandRunner.run("/bin/ps", ["-axo", "pid=,args="])
        guard ps.succeeded else { return nil }

        let relevant = ps.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("build_ipa_from_nsp") || $0.contains("own_compilers") }
        guard !relevant.isEmpty else { return nil }

        var mainPid: Int32 = 0
        var buildPids: [Int32] = []
        var gameFolder = ""
        var isCompilingShaders = false
        var isLinkingPipelines = false

        for line in relevant {
            if line.contains("build_ipa_from_nsp.py") {
                if let pid = line.split(separator: " ", maxSplits: 1).first.flatMap({ Int32($0) }) {
                    mainPid = pid
                    buildPids.append(pid)
                }
                if let range = line.range(of: "build_ipa_from_nsp.py ") {
                    let after = line[range.upperBound...]
                    // The game folder ends at the first option (`-k` is missing for Switch 2 builds).
                    let end = [" -k ", " --platform "].compactMap { after.range(of: $0)?.lowerBound }.min() ?? after.endIndex
                    gameFolder = String(after[..<end])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
            if line.contains("own_compilers.py") || line.contains("metal ") {
                isCompilingShaders = true
            }
            if line.contains("metal-tt") {
                isLinkingPipelines = true
            }
        }

        guard !gameFolder.isEmpty else { return nil }
        let gameName = URL(fileURLWithPath: gameFolder).lastPathComponent
        let fm = FileManager.default

        let buildDir = (try? fm.contentsOfDirectory(atPath: gameFolder))?
            .first { $0.hasSuffix("_build") }
            .map { (gameFolder as NSString).appendingPathComponent($0) }

        var stageDesc = tr("Build wird ausgeführt …", "Build in progress…")
        var shaderCount: Int?
        var latestLogPath: String?
        var recentLines: [String] = []

        if let buildDir = buildDir {
            shaderCount = countCompiledShaders(buildDir: buildDir)

            if isLinkingPipelines {
                stageDesc = pipelineStageText
            } else if isCompilingShaders {
                if let count = shaderCount {
                    let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
                    stageDesc = tr("Phase 5/8: Metal-Shader kompilieren (\(formatted) fertig)", "Phase 5/8: Compiling Metal shaders (\(formatted) done)")
                } else {
                    stageDesc = tr("Phase 5/8: Metal-Shader kompilieren", "Phase 5/8: Compiling Metal shaders")
                }
            } else {
                stageDesc = tr("RomFS-/ExeFS-Daten werden verarbeitet", "Processing RomFS / ExeFS data")
            }

            // The build's own output first (e.g. `… | tee build.log` in Terminal); otherwise the newest
            // log written since the build started, so an earlier build's log is never shown.
            latestLogPath = outputLogFile(of: buildPids)
                ?? newestBuildLog(buildDir: buildDir, notBefore: startDate(of: mainPid))

            if let logPath = latestLogPath {
                let rawLines = tailLines(of: logPath, maxBytes: 32_768)
                let events = rawLines.compactMap { BuildEvent.parse($0) }
                recentLines = events.suffix(45).map(\.displayLine)

                // Determine the most recent stage from the log.
                // `tailLines` only returns non-empty lines → events and rawLines have equal length.
                for (event, raw) in zip(events, rawLines).reversed() {
                    if case let .stage(index, total, name, step) = event, let name = name {
                        let trans = BuildStageInfo.translate(name: name, step: step ?? "")
                        let counter = (index != nil && total != nil) ? "[\(index!)/\(total!)]" : ""
                        stageDesc = "\(tr("Phase", "Phase")) \(counter): \(trans.title)"
                            + (trans.explanation.map { " – \($0)" } ?? "")
                        break
                    } else if raw.contains("Pipeline archive") || raw.contains("metal-tt") {
                        stageDesc = pipelineStageText
                        break
                    } else if raw.contains("Mac shaders") || raw.contains("shaders ready") {
                        stageDesc = raw
                        break
                    }
                }
            }

            if recentLines.isEmpty {
                recentLines = [
                    tr("Aktiver Build: \(gameName) (PID \(mainPid))", "Active build: \(gameName) (PID \(mainPid))"),
                    stageDesc,
                    tr("Verarbeitung läuft im Hintergrund …", "Processing in the background…")
                ]
            }
        }

        let timeline = latestLogPath.map { follower.update(path: $0) }

        return ActiveBuildInfo(pid: mainPid,
                               gameName: gameName,
                               gameDirectory: gameFolder,
                               buildDirectory: buildDir,
                               currentStageDescription: stageDesc,
                               compiledShadersCount: shaderCount,
                               latestLogFile: latestLogPath,
                               recentLogLines: recentLines,
                               timeline: timeline)
    }

    private static var pipelineStageText: String {
        tr("Phase 7/8: GPU-Pipeline-Archiv erstellen (metal-tt verknüpft Shader – bitte warten)",
           "Phase 7/8: Creating GPU pipeline archive (metal-tt links shaders – please wait)")
    }

    private static func countCompiledShaders(buildDir: String) -> Int? {
        let fm = FileManager.default
        let cacheDir = (buildDir as NSString).appendingPathComponent("shader/cache")
        guard let subdirs = try? fm.contentsOfDirectory(atPath: cacheDir) else { return nil }
        let total = subdirs.reduce(0) { sum, sub in
            sum + ((try? fm.contentsOfDirectory(atPath: (cacheDir as NSString).appendingPathComponent(sub)).count) ?? 0)
        }
        return total > 0 ? total : nil
    }

    /// The file the build writes its output to: its stdout when that is a file (`> build.log`),
    /// or the file of the `tee` reading its stdout pipe (`| tee build.log`).
    private static func outputLogFile(of pids: [Int32]) -> String? {
        guard !pids.isEmpty else { return nil }
        let own = lsofFiles(["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "1"])
        if let file = own.first(where: { $0.type == "REG" }) { return file.name }
        let peers = Set(own.filter { $0.type == "PIPE" }.compactMap { $0.name.hasPrefix("->") ? String($0.name.dropFirst(2)) : nil })
        guard !peers.isEmpty else { return nil }
        let tees = lsofFiles(["-c", "tee"])
        let readers = Set(tees.filter { $0.fd == "0" && $0.type == "PIPE" && peers.contains($0.device) }.map(\.pid))
        return tees.first { readers.contains($0.pid) && $0.type == "REG" && $0.access.contains("w") }?.name
    }

    private struct OpenFile {
        var pid = "", fd = "", access = "", type = "", device = "", name = ""
    }

    /// Open files from `lsof -F` (one field per line: p pid, f fd, a access, t type, d device, n name).
    private static func lsofFiles(_ args: [String]) -> [OpenFile] {
        let result = CommandRunner.run("/usr/sbin/lsof", ["-w", "-F", "pfatdn"] + args)
        var files: [OpenFile] = []
        var pid = ""
        for line in result.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = value
            case "f": files.append(OpenFile(pid: pid, fd: value))
            case "a": if !files.isEmpty { files[files.count - 1].access = value }
            case "t": if !files.isEmpty { files[files.count - 1].type = value }
            case "d": if !files.isEmpty { files[files.count - 1].device = value }
            case "n": if !files.isEmpty { files[files.count - 1].name = value }
            default: break
            }
        }
        return files
    }

    /// When the process started, from `ps -o etime` (`[[dd-]hh:]mm:ss`).
    private static func startDate(of pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        let text = CommandRunner.run("/bin/ps", ["-o", "etime=", "-p", String(pid)]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dayParts = text.split(separator: "-")
        guard let clock = dayParts.last else { return nil }
        let days = dayParts.count == 2 ? Int(dayParts[0]) : 0
        let units = clock.split(separator: ":").map { Int($0) }
        guard let days, !units.isEmpty, units.count <= 3, !units.contains(where: { $0 == nil }) else { return nil }
        let seconds = units.reduce(0) { $0 * 60 + $1! } + days * 86_400
        return Date().addingTimeInterval(-TimeInterval(seconds))
    }

    /// Newest log file that recognizably belongs to a build and was written since `notBefore`.
    private static func newestBuildLog(buildDir: String, notBefore: Date?) -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if fm.fileExists(atPath: NXPaths.liveLogPath) {
            candidates.append(NXPaths.liveLogPath)
        }
        let logsDir = (buildDir as NSString).appendingPathComponent("logs")
        if let files = try? fm.contentsOfDirectory(atPath: logsDir) {
            candidates += files.filter { $0.hasSuffix(".log") }.map { (logsDir as NSString).appendingPathComponent($0) }
        }

        let markers = ["build_ipa_from_nsp", "shaders", "Mac app", "game profile:", "dmsh_build"]
        var newest: (path: String, date: Date)?

        for path in candidates {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value, size > 256,
                  let modified = attrs[.modificationDate] as? Date,
                  let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { continue }
            let sample = String(decoding: handle.readData(ofLength: 2048), as: UTF8.self)
            try? handle.close()

            let belongsToBuild = markers.contains { sample.contains($0) } || path.contains("build_console")
            let current = notBefore.map { modified >= $0.addingTimeInterval(-5) } ?? true
            if belongsToBuild && current && modified > (newest?.date ?? .distantPast) {
                newest = (path, modified)
            }
        }
        return newest?.path
    }

    /// Reads the last `maxBytes` of a file and returns its non-empty lines.
    private static func tailLines(of path: String, maxBytes: UInt64) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return [] }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > maxBytes ? fileSize - maxBytes : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
