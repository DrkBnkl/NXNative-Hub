import SwiftUI
import AppKit

// MARK: - Live log of a running build
//
// Header with the current stage, its count, a progress bar, elapsed time and ETA; a list of
// the stages on the left; the log on the right, filtered to what matters by default (the
// repeated progress lines are hidden). Fed by a `BuildTimeline`: the app's own build, the
// batch import, or a build started outside the app (read from its log file).

struct LiveLogSheet: View {
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var buildManager: BuildManager
    @EnvironmentObject private var router: AppRouter
    @State private var didTrashBuildFolder = false
    @State private var filter: LogFilter = .important
    @State private var search = ""

    private struct Source {
        var timeline: BuildTimeline
        var gameName: String
        var origin: String
        var originIcon: String
        var logFile: String?
        var errorMessage: String?
        var isAppBuild = false
    }

    private var source: Source? {
        if importManager.isConverting {
            return Source(timeline: importManager.timeline,
                          gameName: importManager.timeline.gameName ?? importManager.currentGameName,
                          origin: tr("Batch-Import · Spiel \(importManager.currentGameIndex + 1) von \(importManager.activeBatchGames.count)",
                                     "Batch import · game \(importManager.currentGameIndex + 1) of \(importManager.activeBatchGames.count)"),
                          originIcon: "square.stack.3d.down.right",
                          logFile: NXPaths.liveLogPath)
        }
        if buildManager.isRunning || (buildManager.isFinished && !buildManager.timeline.isEmpty) {
            let folderName = buildManager.lastGameDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
            return Source(timeline: buildManager.timeline,
                          gameName: buildManager.timeline.gameName ?? folderName ?? tr("Build", "Build"),
                          origin: tr("In NXNative Hub gestartet", "Started in NXNative Hub"),
                          originIcon: "macwindow",
                          logFile: NXPaths.liveLogPath,
                          errorMessage: buildManager.errorMessage,
                          isAppBuild: true)
        }
        if let build = buildMonitor.activeBuild {
            var timeline = build.timeline ?? BuildTimeline()
            if timeline.isEmpty { build.recentLogLines.forEach { timeline.consume($0) } }
            let file = build.latestLogFile.map { ($0 as NSString).lastPathComponent }
            return Source(timeline: timeline,
                          gameName: timeline.gameName ?? build.gameName,
                          origin: tr("Außerhalb der App gestartet", "Started outside the app") + (file.map { " · \($0)" } ?? ""),
                          originIcon: "terminal",
                          logFile: build.latestLogFile)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let source {
                LiveLogHeader(timeline: source.timeline, gameName: source.gameName)

                if let stage = source.timeline.currentStage, BuildStageInfo.isPipelineArchivePhase(stage.title) {
                    PipelinePhaseHint()
                }
                if source.timeline.outcome == .failed, let message = source.errorMessage {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                HStack(alignment: .top, spacing: 14) {
                    StageListView(timeline: source.timeline)
                        .frame(width: 230)
                    LogEntriesView(timeline: source.timeline, filter: $filter, search: $search)
                }
                .frame(maxHeight: .infinity)

                if source.isAppBuild { buildFolderCleanup }

                footer(source)
            } else {
                ContentUnavailableView(tr("Kein laufender Build", "No Build Running"),
                                       systemImage: "checkmark.circle",
                                       description: Text(tr("Derzeit wird kein Spiel kompiliert.", "No game is being compiled right now.")))
                HStack {
                    Spacer()
                    closeButton
                }
            }
        }
        .padding(20)
        .frame(minWidth: 780, idealWidth: 860, minHeight: 560, idealHeight: 640)
    }

    private func footer(_ source: Source) -> some View {
        HStack(spacing: 8) {
            Label(source.origin, systemImage: source.originIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let logPath = source.logFile, FileManager.default.fileExists(atPath: logPath) {
                Button(tr("Logdatei im Finder", "Show Log File")) {
                    FilePanels.revealInFinder(logPath)
                }
            }
            Button(tr("Kopieren", "Copy")) {
                let text = source.timeline.entries
                    .map { [$0.time, $0.text].compactMap { $0 }.joined(separator: " ") }
                    .joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .help(tr("Das ganze Protokoll in die Zwischenablage kopieren", "Copy the whole log to the clipboard"))
            closeButton
        }
    }

    private var closeButton: some View {
        Button(tr("Schließen", "Close")) {
            router.showingLiveLog = false
        }
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private var buildFolderCleanup: some View {
        if buildManager.isFinished && buildManager.buildSucceeded,
           let folder = buildManager.buildFolders.first, !didTrashBuildFolder {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.minus")
                    .foregroundStyle(.blue)
                Text(tr("Build-Ordner (\(folder.lastPathComponent), \(BuildWorkFolder.formattedSize(of: folder))) löschen? NSPs bleiben erhalten.",
                        "Delete build folder (\(folder.lastPathComponent), \(BuildWorkFolder.formattedSize(of: folder)))? NSPs are kept."))
                    .font(.caption)
                Spacer()
                Button(tr("In Papierkorb legen", "Move to Trash")) {
                    if buildManager.trashBuildFolder(folder) {
                        didTrashBuildFolder = true
                    }
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        } else if didTrashBuildFolder {
            Label(tr("Build-Ordner in den Papierkorb gelegt – Speicherplatz freigegeben.",
                     "Build folder moved to Trash – disk space freed."),
                  systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Header: stage, count, progress bar, times

private struct LiveLogHeader: View {
    let timeline: BuildTimeline
    let gameName: String

    private var stage: BuildTimeline.Stage? { timeline.currentStage }

    private var subtitle: String {
        switch timeline.outcome {
        case .succeeded: return tr("Build abgeschlossen", "Build finished")
        case .failed: return tr("Build fehlgeschlagen", "Build failed")
        case .cancelled: return tr("Build abgebrochen", "Build cancelled")
        case nil: break
        }
        guard let stage else { return tr("Build wird vorbereitet …", "Preparing build…") }
        let of = timeline.plannedStages > 0
            ? tr("Schritt \(stage.index) von \(timeline.plannedStages)", "Step \(stage.index) of \(timeline.plannedStages)")
            : tr("Schritt \(stage.index)", "Step \(stage.index)")
        return "\(of) · \(stage.title)"
    }

    private var outcomeIcon: (name: String, color: Color) {
        switch timeline.outcome {
        case .succeeded: return ("checkmark.circle.fill", .green)
        case .failed: return ("xmark.octagon.fill", .red)
        case .cancelled: return ("stop.circle.fill", .orange)
        case nil: return ("gamecontroller.fill", .accentColor)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: outcomeIcon.name)
                    .font(.title2)
                    .foregroundStyle(outcomeIcon.color)
                    .frame(width: 40, height: 40)
                    .background(outcomeIcon.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(gameName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let stage, let count = BuildTimeline.countText(stage), timeline.outcome == nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(count)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        if let step = stage.step.isEmpty ? nil : stage.step {
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if timeline.outcome == nil {
                if let fraction = stage?.fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Text(leftCaption(now: context.date))
                    Spacer()
                    if let eta = stage?.etaSeconds, timeline.outcome == nil {
                        Text(tr("Schritt noch etwa \(BuildTimeline.duration(eta))", "About \(BuildTimeline.duration(eta)) left in this step"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private func leftCaption(now: Date) -> String {
        var parts: [String] = []
        if let fraction = stage?.fraction, timeline.outcome == nil { parts.append("\(Int(fraction * 100)) %") }
        if let start = timeline.startDate {
            let end = timeline.outcome == nil ? now : (timeline.lastDate ?? now)
            let elapsed = BuildTimeline.duration(end.timeIntervalSince(start))
            parts.append(timeline.outcome == nil ? tr("läuft seit \(elapsed)", "running for \(elapsed)")
                                                 : tr("Dauer \(elapsed)", "took \(elapsed)"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Stage list

private struct StageListView: View {
    let timeline: BuildTimeline

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if timeline.stages.isEmpty {
                    Text(tr("Noch keine Schritte.", "No steps yet."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                ForEach(timeline.stages) { stage in
                    StageRow(stage: stage)
                }
                if timeline.remainingStageCount > 0 && timeline.outcome == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .frame(width: 16)
                        Text(timeline.remainingStageCount == 1
                             ? tr("1 weiterer Schritt", "1 more step")
                             : tr("\(timeline.remainingStageCount) weitere Schritte", "\(timeline.remainingStageCount) more steps"))
                    }
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
            .padding(6)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

private struct StageRow: View {
    let stage: BuildTimeline.Stage

    private var isRunning: Bool { stage.state == .running }

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 16)
            Text(stage.title)
                .lineLimit(2)
                .fontWeight(isRunning ? .semibold : .regular)
            Spacer(minLength: 4)
            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isRunning ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .help(stage.summary.isEmpty ? stage.name : "\(stage.name): \(stage.summary)")
    }

    @ViewBuilder
    private var icon: some View {
        switch stage.state {
        case .running: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var trailing: String {
        if isRunning {
            if let fraction = stage.fraction { return "\(Int(fraction * 100)) %" }
            return stage.elapsedSeconds.map(BuildTimeline.duration) ?? ""
        }
        return stage.elapsedSeconds.map(BuildTimeline.duration) ?? ""
    }
}

// MARK: - Log entries with filter and search

enum LogFilter: Hashable { case important, all, problems }

private struct LogEntriesView: View {
    let timeline: BuildTimeline
    @Binding var filter: LogFilter
    @Binding var search: String

    private static let bottomID = -1

    private var problemCount: Int { timeline.entries.filter(\.isProblem).count }

    private var shown: [BuildTimeline.Entry] {
        timeline.entries.filter { entry in
            let passes: Bool
            switch filter {
            case .important: passes = entry.isImportant
            case .all: passes = true
            case .problems: passes = entry.isProblem
            }
            return passes && (search.isEmpty || entry.text.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(tr("Anzeigen", "Show"), selection: $filter) {
                    Text(tr("Wichtiges", "Important")).tag(LogFilter.important)
                    Text(tr("Alles", "All")).tag(LogFilter.all)
                    Text(problemCount > 0 ? tr("Probleme (\(problemCount))", "Problems (\(problemCount))")
                                          : tr("Probleme", "Problems")).tag(LogFilter.problems)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                TextField(tr("Suchen", "Search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            let entries = shown
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if entries.isEmpty {
                            Text(search.isEmpty ? tr("Noch keine Ausgabe.", "No output yet.") : tr("Keine Treffer.", "No matches."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                        if filter == .important && search.isEmpty && timeline.hiddenEntryCount > 0 {
                            Button {
                                filter = .all
                            } label: {
                                Text(timeline.hiddenEntryCount == 1
                                     ? tr("1 Fortschrittszeile ausgeblendet – alle zeigen", "1 progress line hidden – show all")
                                     : tr("\(timeline.hiddenEntryCount) Fortschrittszeilen ausgeblendet – alle zeigen",
                                          "\(timeline.hiddenEntryCount) progress lines hidden – show all"))
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .padding(.top, 4)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                .onChange(of: entries.last?.id) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .onChange(of: filter) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: BuildTimeline.Entry

    private var style: (icon: String?, color: Color) {
        switch entry.kind {
        case .stageStart: return ("play.circle", .accentColor)
        case .step: return ("arrow.turn.down.right", .secondary)
        case .progress: return ("chart.bar", .secondary)
        case .stageDone: return ("checkmark.circle", .green)
        case .stageWarning, .warning: return ("exclamationmark.triangle", .orange)
        case .stageFailed: return ("xmark.circle", .red)
        case .error: return ("xmark.octagon", .red)
        case .success: return ("checkmark.seal", .green)
        case .info: return (nil, .primary)
        }
    }

    /// Without the script's colour tags ("[RED] …").
    private var text: String {
        var t = entry.text
        for tag in ["[RED] ", "[YELLOW] ", "[GREEN] "] where t.hasPrefix(tag) { t.removeFirst(tag.count) }
        return t
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.time ?? "")
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)
            Group {
                if let icon = style.icon { Image(systemName: icon) } else { Text("") }
            }
            .foregroundStyle(style.color)
            .frame(width: 14)
            Text(text)
                .foregroundStyle(entry.kind == .progress || entry.kind == .step ? .secondary : style.color == .primary ? .primary : style.color)
                .fontWeight([.stageStart, .stageDone, .stageFailed, .stageWarning].contains(entry.kind) ? .medium : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
}
