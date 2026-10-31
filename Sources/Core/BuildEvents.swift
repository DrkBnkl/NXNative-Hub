import Foundation

// MARK: - JSON progress events from build_ipa_from_nsp.py (--progress json)
//
// Single parser shared by BuildManager, ImportBatchManager and ActiveBuildMonitor.
// Numbers are read via NSNumber: `as? Double` also succeeds for integers, so
// integral values are detected explicitly ("1200 / 4000" instead of "1200.0 / 4000.0").

enum BuildEvent {
    struct Progress {
        var step: String?
        var fraction: Double?
        var done: Double?
        var total: Double?
        var unit: String
        var eta: Double?
        var elapsed: Double?

        /// Formatted counter, e.g. "1200 / 4000 shader" or "1.5 / 3.2 GB".
        var countText: String? {
            guard let done = done, let total = total else { return nil }
            let suffix = unit.isEmpty ? "" : " \(unit)"
            if done.rounded() == done && total.rounded() == total {
                return "\(Int(done)) / \(Int(total))\(suffix)"
            }
            return String(format: "%.1f / %.1f", done, total) + suffix
        }

        /// Integer values for the periodic log line (only for item counts).
        var integralCounts: (done: Int, total: Int)? {
            guard let done = done, let total = total,
                  done.rounded() == done, total.rounded() == total else { return nil }
            return (Int(done), Int(total))
        }

        /// For large counts only log every 2500th item (otherwise the log floods).
        var shouldLogMilestone: Bool {
            guard let counts = integralCounts, counts.total > 1000 else { return false }
            return counts.done % 2500 == 0 || (counts.done > 0 && counts.done == counts.total)
        }

        var percent: Int {
            if let fraction = fraction { return Int(fraction * 100) }
            if let counts = integralCounts, counts.total > 0 { return counts.done * 100 / counts.total }
            return 0
        }
    }

    case stage(index: Int?, total: Int?, name: String?, step: String?)
    case step(String)
    case progress(Progress)
    case stageEnd(name: String, ok: Bool, elapsed: Double, summary: String)
    case say(String)
    case otherJSON(String)
    case text(String)

    /// Returns nil for empty lines.
    static func parse(_ rawLine: String) -> BuildEvent? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        guard line.hasPrefix("{"), line.hasSuffix("}"),
              let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ev = json["ev"] as? String else {
            return .text(line)
        }

        switch ev {
        case "stage":
            return .stage(index: int(json["k"]),
                          total: int(json["n"]),
                          name: json["name"] as? String,
                          step: json["step"] as? String)
        case "step":
            guard let step = json["step"] as? String else { return .otherJSON(line) }
            return .step(step)
        case "progress":
            return .progress(Progress(step: json["step"] as? String,
                                      fraction: number(json["frac"]),
                                      done: number(json["done"]),
                                      total: number(json["total"]),
                                      unit: (json["unit"] as? String) ?? "",
                                      eta: number(json["eta"]),
                                      elapsed: number(json["elapsed"])))
        case "stage_end":
            guard let name = json["name"] as? String, let ok = json["ok"] as? Bool else { return .otherJSON(line) }
            return .stageEnd(name: name,
                             ok: ok,
                             elapsed: number(json["elapsed"]) ?? 0,
                             summary: (json["summary"] as? String) ?? "")
        case "say":
            guard let msg = json["msg"] as? String else { return .otherJSON(line) }
            return .say(msg)
        default:
            return .otherJSON(line)
        }
    }

    /// Short, readable representation for log views (live log of external builds).
    var displayLine: String {
        switch self {
        case let .stage(index, total, name, step):
            let trans = BuildStageInfo.translate(name: name ?? "", step: step ?? "")
            let counter = (index != nil && total != nil) ? "[\(index!)/\(total!)] " : ""
            let stepText = (step?.isEmpty == false) ? " · \(step!)" : ""
            return "▶ \(counter)\(trans.title)\(stepText)"
        case let .step(step):
            return "  ↳ \(step)"
        case let .progress(progress):
            let count = progress.countText ?? ""
            return "  \(tr("Fortschritt", "Progress")): \(count) (\(progress.percent)%)"
        case let .stageEnd(name, ok, elapsed, _):
            let trans = BuildStageInfo.translate(name: name, step: "")
            return "\(ok ? "✓" : "✗") \(trans.title) \(tr("abgeschlossen", "finished")) (\(Self.formatElapsed(elapsed)))"
        case let .say(message):
            return message
        case let .otherJSON(line), let .text(line):
            return line
        }
    }

    // MARK: Helpers

    static func number(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        return number.doubleValue
    }

    static func int(_ any: Any?) -> Int? {
        guard let number = any as? NSNumber else { return nil }
        return number.intValue
    }

    /// "mm:ss"
    static func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// "3m 12s" or "42s"
    static func formatElapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

// MARK: - Human-readable build stage names

enum BuildStageInfo {
    static func translate(name: String, step: String) -> (title: String, explanation: String?) {
        let lower = name.lowercased()

        if lower.contains("nx_extract") {
            return (tr("Vorbereitung (nx_extract)", "Preparation (nx_extract)"),
                    tr("Entpackungs-Werkzeuge initialisieren", "Initializing extraction tools"))
        } else if lower.contains("extract") {
            return (tr("RomFS-Spieldaten entpacken", "Extract RomFS Data"),
                    tr("Spieldateien werden aus dem NSP-Image dekomprimiert …", "Decompressing game files from NSP image…"))
        } else if lower.contains("rewrite") {
            return (tr("ARM64-Binaries patchen", "Patch ARM64 Binaries"),
                    tr("Spielmodule werden für Apple Silicon optimiert und gepatcht …", "Optimizing and patching game modules for Apple Silicon…"))
        } else if lower.contains("shader split") {
            return (tr("Shader extrahieren (Shader Split)", "Extract Shaders (Shader Split)"),
                    tr("RomFS wird nach Switch-NVN-Grafikshadern durchsucht …", "Scanning RomFS for Switch NVN graphics shaders…"))
        } else if lower.contains("shader") {
            return (tr("Metal-Shader kompilieren", "Compile Metal Shaders"),
                    tr("Switch-Grafikshader werden nativ in Apple-Metal-Code übersetzt …", "Translating Switch graphics shaders into native Apple Metal code…"))
        } else if lower.contains("mac host") || lower.contains("host") {
            return (tr("Mac-Host-Runner erstellen", "Build Mac Host Runner"),
                    tr("Nativer dmhost-Launcher für macOS wird kompiliert …", "Compiling native dmhost launcher for macOS…"))
        } else if lower.contains("pipeline archive") || lower.contains("metal-tt") {
            return (tr("GPU-Pipeline-Archiv erstellen (metal-tt)", "Create GPU Pipeline Archive (metal-tt)"),
                    tr("Apples Metal-Compiler verknüpft alle Shader. Das dauert einige Minuten ohne Zwischenausgabe.",
                       "Apple's Metal compiler links all shaders. This takes a few minutes without output."))
        } else if lower.contains("mac app") || lower.contains("app") || lower.contains("pack") {
            return (tr("Mac-App fertigstellen", "Finalize Mac App"),
                    tr(".app-Bundle wird gepackt und signiert …", "Packaging and signing .app bundle…"))
        }
        return (name, step.isEmpty ? nil : step)
    }

    /// Phase 7/8 (metal-tt) runs for minutes without output – the UI shows a hint meanwhile.
    static func isPipelineArchivePhase(_ text: String) -> Bool {
        text.contains("Pipeline") || text.contains("metal-tt")
    }
}

// MARK: - Why a build ended (exit codes of build_ipa_from_nsp.py)
//
// From nxnative docs/frontends.md:
//   0 finished · 1 stopped on an error (the last `say` starting with "[RED] " gives the reason)
//   2 invalid command-line arguments (stderr only, no JSON events) · 130 interrupted

struct BuildFailureTracker {
    private(set) var lastError: String?
    private(set) var stderrTail: [String] = []

    static let redPrefix = "[RED] "

    mutating func noteSay(_ message: String) {
        if message.hasPrefix(Self.redPrefix) {
            lastError = String(message.dropFirst(Self.redPrefix.count))
        }
    }

    mutating func noteStderr(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stderrTail.append(trimmed)
        if stderrTail.count > 12 { stderrTail.removeFirst(stderrTail.count - 12) }
    }

    /// 130 = SIGINT (Python's own exit code, or the signal as reported by StreamingProcess), 143 = SIGTERM.
    static func wasInterrupted(_ exitCode: Int32) -> Bool {
        exitCode == 130 || exitCode == 143
    }

    /// A short explanation for the user, or nil for a successful build.
    func describe(exitCode: Int32) -> String? {
        let stderrSummary = stderrTail.suffix(4).joined(separator: "\n")
        switch exitCode {
        case 0:
            return nil
        case 2:
            let text = tr("nxnative hat die Aufrufparameter abgelehnt (Exit-Code 2). Meist passen nxnative und NXNative Hub nicht zusammen – aktualisiere nxnative über „Nach Updates suchen …“.",
                          "nxnative rejected the command-line arguments (exit code 2). This usually means nxnative and NXNative Hub do not match – update nxnative with “Check for Updates…”.")
            return stderrSummary.isEmpty ? text : text + "\n\n" + stderrSummary
        case _ where Self.wasInterrupted(exitCode):
            return tr("Build abgebrochen.", "Build cancelled.")
        default:
            if let lastError = lastError { return lastError }
            if let last = stderrTail.last { return last }
            return tr("Build fehlgeschlagen (Exit-Code \(exitCode)). Details stehen im Protokoll.",
                      "Build failed (exit code \(exitCode)). See the log for details.")
        }
    }
}

// MARK: - Work folder of a build (<NSP folder>/<title ID>_build)

enum BuildWorkFolder {
    /// `<title ID>_build` folders in a game folder. nxnative reuses them, so a rebuild is much faster.
    static func find(in gameDirectory: String) -> [URL] {
        let url = URL(fileURLWithPath: gameDirectory)
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { item in
            let name = item.lastPathComponent
            guard name.hasSuffix("_build"),
                  SwitchTitleID.normalized(String(name.dropLast("_build".count))) != nil else { return false }
            return (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    /// The full tool output of the last build (`<title ID>_build/logs`), if present.
    static func logsFolder(in gameDirectory: String) -> String? {
        find(in: gameDirectory)
            .map { $0.appendingPathComponent("logs").path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
