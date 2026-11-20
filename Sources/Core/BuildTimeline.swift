import Foundation

// MARK: - Structured view of a build's output (live log)
//
// Fed with raw output lines, from the app's own builds (`--progress json`) or from a build
// started in Terminal (`--progress lines`, plain text). Keeps the stages with their state and
// duration, the current count and ETA, and the log entries with a kind, so the live log can
// show a step list and hide the repeated progress lines.

struct BuildTimeline: Equatable {
    enum StageState: Equatable { case running, done, warning, failed }

    struct Stage: Equatable, Identifiable {
        let index: Int
        var id: Int { index }
        var name: String
        var step: String = ""
        var state: StageState = .running
        var fraction: Double?
        var done: Double?
        var total: Double?
        var unit: String = ""
        var etaSeconds: Double?
        var elapsedSeconds: Double?
        var summary: String = ""

        var title: String { BuildStageInfo.translate(name: name, step: step).title }
    }

    struct Entry: Equatable, Identifiable {
        enum Kind: Equatable { case info, stageStart, step, progress, stageDone, stageWarning, stageFailed, warning, error, success }
        let id: Int
        var time: String?
        var kind: Kind
        var text: String

        /// Shown with the filter "Important": everything but steps and progress lines.
        var isImportant: Bool { kind != .progress && kind != .step }
        var isProblem: Bool { [.warning, .error, .stageWarning, .stageFailed].contains(kind) }
    }

    enum Outcome: Equatable { case succeeded, failed, cancelled }

    private(set) var stages: [Stage] = []
    private(set) var plannedStages = 0
    private(set) var entries: [Entry] = []
    private(set) var gameName: String?
    private(set) var startDate: Date?
    private(set) var lastDate: Date?
    private(set) var outcome: Outcome?

    /// Oldest entries are dropped beyond this (the stage list keeps everything).
    var entryLimit = 5_000

    var currentStage: Stage? { stages.last { $0.state == .running } }
    var isEmpty: Bool { entries.isEmpty && stages.isEmpty }
    var hiddenEntryCount: Int { entries.filter { !$0.isImportant }.count }

    /// Stages the build announced but has not started yet.
    var remainingStageCount: Int { max(0, plannedStages - (stages.map(\.index).max() ?? 0)) }

    // MARK: Input

    /// One line of the build's stdout (JSON event or text).
    mutating func consume(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix("{"), line.hasSuffix("}"),
           let data = line.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let ev = json["ev"] as? String {
            consumeJSON(ev, json)
        } else {
            consumeText(line)
        }
    }

    /// A line of the build's stderr.
    mutating func consumeStderr(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        add(Self.messageKind(text) == .info ? .info : Self.messageKind(text), text, time: nil)
    }

    /// A message of the app itself (start, result).
    mutating func note(_ text: String, kind: Entry.Kind = .info) {
        add(kind, text, time: Self.clock(Date()))
    }

    /// Ends a build seen only through its log (started outside the app): cancelled when this app
    /// stopped it or the log says so, failed after a red message or a failed stage, else done.
    mutating func finishFromLog(cancelled: Bool) {
        guard outcome == nil else { return }
        let tail = entries.suffix(10)
        if cancelled || tail.contains(where: { $0.text.contains("[RED] stopped") || $0.text.contains("[RED] interrupted") }) {
            finish(.cancelled)
        } else if stages.contains(where: { $0.state == .failed }) || tail.contains(where: { $0.kind == .error }) {
            finish(.failed)
        } else {
            finish(.succeeded)
        }
    }

    mutating func finish(_ outcome: Outcome) {
        self.outcome = outcome
        if let i = stages.lastIndex(where: { $0.state == .running }) {
            stages[i].state = outcome == .succeeded ? .done : .failed
        }
    }

    // MARK: JSON (--progress json)

    private mutating func consumeJSON(_ ev: String, _ json: [String: Any]) {
        let date = (json["t"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let time = date.map(Self.clock)
        if let date { see(date) }
        let k = (json["k"] as? NSNumber)?.intValue
        let name = json["name"] as? String
        let step = json["step"] as? String

        switch ev {
        case "stage":
            startStage(index: k ?? (stages.count + 1), total: (json["n"] as? NSNumber)?.intValue, name: name ?? "", step: step ?? "", time: time)
        case "step":
            if let step { setStep(step, time: time) }
        case "progress":
            guard let i = stageIndex(k) else { return }
            if let step, !step.isEmpty { stages[i].step = step }
            stages[i].done = Self.number(json["done"])
            stages[i].total = Self.number(json["total"])
            stages[i].unit = (json["unit"] as? String) ?? ""
            stages[i].fraction = Self.number(json["frac"])
            stages[i].etaSeconds = Self.number(json["eta"])
            stages[i].elapsedSeconds = Self.number(json["elapsed"])
            // Count lines only now and then, like the text mode's 30 s beat.
            if let elapsed = stages[i].elapsedSeconds, Int(elapsed) / 30 != lastProgressBeat {
                lastProgressBeat = Int(elapsed) / 30
                add(.progress, progressText(stages[i]), time: time)
            }
        case "stage_end":
            let warn = (json["warn"] as? Bool) == true
            let ok = (json["ok"] as? Bool) ?? true
            endStage(index: k, state: !ok ? .failed : warn ? .warning : .done,
                     elapsed: Self.number(json["elapsed"]), summary: (json["summary"] as? String) ?? "", time: time)
        case "say":
            if let msg = json["msg"] as? String { message(msg, time: time) }
        case "game":
            if let name = json["name"] as? String { gameName = name }
        default:
            break
        }
    }

    private var lastProgressBeat = -1

    // MARK: Text (--progress lines)

    private static let clockPrefix = try! NSRegularExpression(pattern: #"^\[(\d{1,2}:\d{2}:\d{2})\] (.*)$"#)
    private static let endLine = try! NSRegularExpression(pattern: #"^(✓|✗|⚠) \[(\d+)/(\d+)\] (.+?) \(([\d:]+)\)(?:: (.*))?$"#)
    private static let startLine = try! NSRegularExpression(pattern: #"^\[(\d+)/(\d+)\] (.+?)(?: · (.+))? …$"#)
    private static let progressLine = try! NSRegularExpression(pattern: #"^\[(\d+)/(\d+)\] (.+?)(?: · (.+?))?: (.+)$"#)

    private mutating func consumeText(_ line: String) {
        var time: String?
        var rest = line
        if let m = Self.match(Self.clockPrefix, line) {
            time = m[1]; rest = m[2] ?? ""
            if let time, let date = Self.date(forClock: time, after: lastDate) { see(date) }
        }

        if let m = Self.match(Self.endLine, rest), let k = Int(m[2] ?? "") {
            let state: StageState = m[1] == "✗" ? .failed : m[1] == "⚠" ? .warning : .done
            if stageIndex(k) == nil { startStage(index: k, total: Int(m[3] ?? ""), name: m[4] ?? "", step: "", time: time, log: false) }
            endStage(index: k, state: state, elapsed: Self.seconds(m[5] ?? ""), summary: m[6] ?? "", time: time)
        } else if let m = Self.match(Self.startLine, rest), let k = Int(m[1] ?? "") {
            if let i = stageIndex(k), stages[i].state == .running {
                setStep(m[4] ?? "", time: time)
            } else {
                startStage(index: k, total: Int(m[2] ?? ""), name: m[3] ?? "", step: m[4] ?? "", time: time)
            }
        } else if let m = Self.match(Self.progressLine, rest), let k = Int(m[1] ?? "") {
            if stageIndex(k) == nil { startStage(index: k, total: Int(m[2] ?? ""), name: m[3] ?? "", step: m[4] ?? "", time: time, log: false) }
            guard let i = stageIndex(k) else { return }
            if let step = m[4], !step.isEmpty { stages[i].step = step }
            applyProgressFields(m[5] ?? "", to: i)
            add(.progress, progressText(stages[i]), time: time)
        } else {
            if gameName == nil, rest.hasPrefix("app name: "),
               let end = rest.range(of: ";") {
                gameName = String(rest[rest.index(rest.startIndex, offsetBy: 10)..<end.lowerBound])
            }
            message(rest, time: time)
        }
    }

    /// "17%, 7,374/42,847 shaders, 42,847 not cached, 11:11 · ETA 51:13"
    private mutating func applyProgressFields(_ text: String, to i: Int) {
        var body = text
        stages[i].etaSeconds = nil
        if let eta = body.range(of: " · ETA ") {
            stages[i].etaSeconds = Self.seconds(String(body[eta.upperBound...]))
            body = String(body[..<eta.lowerBound])
        }
        var parts = body.components(separatedBy: ", ")
        if let last = parts.last, let elapsed = Self.seconds(last) {
            stages[i].elapsedSeconds = elapsed
            parts.removeLast()
        }
        stages[i].fraction = nil
        if let first = parts.first, first.hasSuffix("%"), let pct = Double(first.dropLast()) {
            stages[i].fraction = pct / 100
            parts.removeFirst()
        }
        stages[i].done = nil; stages[i].total = nil; stages[i].unit = ""
        if let count = parts.first {
            let words = count.split(separator: " ", maxSplits: 1)
            let numbers = words.first?.split(separator: "/") ?? []
            if numbers.count == 2,
               let done = Double(numbers[0].replacingOccurrences(of: ",", with: "")),
               let total = Double(numbers[1].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "~", with: "")) {
                stages[i].done = done; stages[i].total = total
                stages[i].unit = words.count > 1 ? String(words[1]) : ""
            }
        }
    }

    // MARK: Stages

    private func stageIndex(_ k: Int?) -> Int? {
        guard let k else { return stages.indices.last }
        return stages.lastIndex { $0.index == k }
    }

    private mutating func startStage(index: Int, total: Int?, name: String, step: String, time: String?, log: Bool = true) {
        for i in stages.indices where stages[i].state == .running { stages[i].state = .done }
        if let total { plannedStages = max(total, index) }
        stages.removeAll { $0.index >= index }   // a stage number used again (a new plan) replaces the old one
        stages.append(Stage(index: index, name: name, step: step))
        lastProgressBeat = -1
        if log {
            let title = stages[stages.count - 1].title
            add(.stageStart, title + (step.isEmpty ? "" : " · \(step)"), time: time)
        }
    }

    private mutating func setStep(_ step: String, time: String?) {
        guard let i = stages.indices.last, stages[i].state == .running else { return }
        stages[i].step = step
        stages[i].fraction = nil; stages[i].done = nil; stages[i].total = nil; stages[i].etaSeconds = nil
        add(.step, step, time: time)
    }

    private mutating func endStage(index: Int?, state: StageState, elapsed: Double?, summary: String, time: String?) {
        guard let i = stageIndex(index) else { return }
        stages[i].state = state
        stages[i].elapsedSeconds = elapsed ?? stages[i].elapsedSeconds
        stages[i].summary = summary
        stages[i].etaSeconds = nil
        if state == .done { stages[i].fraction = 1 }
        let kind: Entry.Kind = state == .failed ? .stageFailed : state == .warning ? .stageWarning : .stageDone
        add(kind, stages[i].title + (summary.isEmpty ? "" : " – \(summary)"), time: time)
    }

    private mutating func message(_ text: String, time: String?) {
        add(Self.messageKind(text), text, time: time)
    }

    private mutating func add(_ kind: Entry.Kind, _ text: String, time: String?) {
        entries.append(Entry(id: nextID, time: time, kind: kind, text: text))
        nextID += 1
        if entries.count > entryLimit { entries.removeFirst(entries.count - entryLimit) }
    }

    private var nextID = 0

    private mutating func see(_ date: Date) {
        if startDate == nil { startDate = date }
        lastDate = date
    }

    func progressText(_ stage: Stage) -> String {
        var parts: [String] = []
        if let fraction = stage.fraction { parts.append("\(Int(fraction * 100)) %") }
        if let count = Self.countText(stage) { parts.append(count) }
        if let eta = stage.etaSeconds { parts.append(tr("noch \(Self.duration(eta))", "\(Self.duration(eta)) left")) }
        return ([stage.step].filter { !$0.isEmpty } + [parts.joined(separator: " · ")]).joined(separator: ": ")
    }

    // MARK: Helpers

    static func messageKind(_ text: String) -> Entry.Kind {
        let lower = text.lowercased()
        if text.hasPrefix("✗") || text.contains("[RED]") || lower.hasPrefix("error") || lower.hasPrefix("[error]")
            || lower.contains("traceback") || lower.hasPrefix("fatal") {
            return .error
        }
        if text.hasPrefix("⚠") || text.contains("[YELLOW]") || lower.hasPrefix("warning") || lower.hasPrefix("[warnung]") || lower.hasPrefix("[warning]") {
            return .warning
        }
        if text.hasPrefix("✓") { return .success }
        return .info
    }

    /// "12,480 / 42,847 shaders" or "1.5 / 3.2 GB"
    static func countText(_ stage: Stage) -> String? {
        guard let done = stage.done else { return nil }
        let unit = stage.unit.isEmpty ? "" : " \(stage.unit)"
        if stage.unit == "B" {
            let f = ByteCountFormatter()
            return f.string(fromByteCount: Int64(done)) + (stage.total.map { " / " + f.string(fromByteCount: Int64($0)) } ?? "")
        }
        let n = NumberFormatter(); n.numberStyle = .decimal; n.maximumFractionDigits = 1
        let d = n.string(from: NSNumber(value: done)) ?? "\(done)"
        guard let total = stage.total else { return d + unit }
        return "\(d) / \(n.string(from: NSNumber(value: total)) ?? "\(total)")\(unit)"
    }

    /// "0:06", "4:36", "1:02:10"
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1:26" / "1:02:10" → seconds
    static func seconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    private static func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    /// Today's date at that clock time (or the next day's when the clock passed midnight).
    private static func date(forClock clock: String, after previous: Date?) -> Date? {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let cal = Calendar.current
        let base = previous ?? Date()
        guard var date = cal.date(bySettingHour: parts[0], minute: parts[1], second: parts[2], of: base) else { return nil }
        if let previous, date < previous.addingTimeInterval(-60) { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        if previous == nil, date > Date().addingTimeInterval(60) { date = cal.date(byAdding: .day, value: -1, to: date) ?? date }
        return date
    }

    private static func match(_ regex: NSRegularExpression, _ text: String) -> [String?]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}
