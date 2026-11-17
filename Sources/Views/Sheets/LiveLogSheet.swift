import SwiftUI

// MARK: - Live log of a running build

struct LiveLogSheet: View {
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var buildManager: BuildManager
    @EnvironmentObject private var router: AppRouter
    @State private var didTrashBuildFolder = false

    /// Builds started by this app are streamed live; external builds are read from the log file every 2.5 s.
    private var displayLines: [String] {
        if importManager.isConverting && !importManager.logs.isEmpty {
            return Array(importManager.logs.suffix(300))
        }
        if buildManager.isRunning && !buildManager.logs.isEmpty {
            return Array(buildManager.logs.suffix(300))
        }
        return buildMonitor.activeBuild?.recentLogLines ?? []
    }

    private var isStreaming: Bool {
        importManager.isConverting || buildManager.isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let build = buildMonitor.activeBuild {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(build.gameName)
                            .font(.headline)
                        Text(build.currentStageDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let count = build.compiledShadersCount {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tr("Shader", "Shaders"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(count.formatted())
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }

                if BuildStageInfo.isPipelineArchivePhase(build.currentStageDescription) {
                    PipelinePhaseHint()
                }

                LogConsoleView(lines: displayLines, minHeight: 240)
                    .frame(maxHeight: .infinity)

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
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(tr("Build-Ordner in den Papierkorb gelegt – Speicherplatz freigegeben.",
                                "Build folder moved to Trash – disk space freed."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(isStreaming
                         ? tr("Echtzeit-Ausgabe", "Live output")
                         : tr("Wird alle 2,5 Sekunden aktualisiert", "Refreshes every 2.5 seconds"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let logPath = build.latestLogFile {
                        Button(tr("Logdatei im Finder zeigen", "Show Log File in Finder")) {
                            FilePanels.revealInFinder(logPath)
                        }
                    }
                    Button(tr("Schließen", "Close")) {
                        router.showingLiveLog = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                ContentUnavailableView(tr("Kein laufender Build", "No Build Running"),
                                       systemImage: "checkmark.circle",
                                       description: Text(tr("Derzeit wird kein Spiel kompiliert.", "No game is being compiled right now.")))
                HStack {
                    Spacer()
                    Button(tr("Schließen", "Close")) {
                        router.showingLiveLog = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 700, height: 520)
    }
}
