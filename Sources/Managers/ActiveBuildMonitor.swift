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
}

final class ActiveBuildMonitor: ObservableObject {
    @Published private(set) var activeBuild: ActiveBuildInfo?

    private var timer: Timer?
    private var isChecking = false
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
        var gameFolder = ""
        var isCompilingShaders = false
        var isLinkingPipelines = false

        for line in relevant {
            if line.contains("build_ipa_from_nsp.py") {
                if let pid = line.split(separator: " ", maxSplits: 1).first.flatMap({ Int32($0) }) {
                    mainPid = pid
                }
                if let range = line.range(of: "build_ipa_from_nsp.py ") {
                    let after = line[range.upperBound...]
                    let end = after.range(of: " -k ")?.lowerBound ?? after.endIndex
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

            latestLogPath = newestBuildLog(buildDir: buildDir)

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

        return ActiveBuildInfo(pid: mainPid,
                               gameName: gameName,
                               gameDirectory: gameFolder,
                               buildDirectory: buildDir,
                               currentStageDescription: stageDesc,
                               compiledShadersCount: shaderCount,
                               latestLogFile: latestLogPath,
                               recentLogLines: recentLines)
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

    /// Newest log file that recognizably belongs to a build.
    private static func newestBuildLog(buildDir: String) -> String? {
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
            if belongsToBuild && modified > (newest?.date ?? .distantPast) {
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
