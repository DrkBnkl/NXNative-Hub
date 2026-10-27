import SwiftUI
import AppKit

// MARK: - Import & batch conversion
//
// Presented inside `ImportSheet` (opened from the builder and the Game menu).

struct ImportView: View {
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var buildManager: BuildManager

    @State private var showConvertConfirmation = false

    var body: some View {
        content
            .navigationTitle(tr("Spiele-Import & Stapelumwandlung", "Game Import & Batch Conversion"))
            .navigationSubtitle("~/NXNative/Import")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        importManager.openImportFolderInFinder()
                    } label: {
                        Label(tr("Im Finder öffnen", "Open in Finder"), systemImage: "folder")
                    }
                    .help(tr("Import-Ordner im Finder öffnen", "Open the Import folder in Finder"))

                    Button {
                        importManager.scanImportFolder()
                    } label: {
                        Label(tr("Erneut prüfen", "Rescan"), systemImage: "arrow.clockwise")
                    }
                    .disabled(importManager.isScanning || importManager.isConverting)
                    .help(tr("Import-Ordner neu scannen", "Rescan the Import folder"))
                }
            }
            .confirmationDialog(tr("\(importManager.selectedCount) Spiele umwandeln?", "Convert \(importManager.selectedCount) games?"),
                                isPresented: $showConvertConfirmation,
                                titleVisibility: .visible) {
                Button(tr("Umwandeln", "Convert")) { startConversion() }
                Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
            } message: {
                Text(tr("Erfolgreich umgewandelte Spiele werden nach ~/NXNative/Games verschoben. Ihre Quelldateien im Import-Ordner werden danach in den Papierkorb gelegt.",
                        "Successfully converted games are moved to ~/NXNative/Games. Their source files in the Import folder are then moved to the Trash."))
            }
    }

    @ViewBuilder
    private var content: some View {
        if importManager.isConverting {
            convertingView
        } else if importManager.isFinished {
            finishedView
        } else if importManager.pendingGames.isEmpty {
            if importManager.isScanning {
                ProgressView(tr("Import-Ordner wird geprüft …", "Scanning Import folder…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyView
            }
        } else {
            pendingView
        }
    }

    // MARK: Empty state

    private var emptyView: some View {
        ContentUnavailableView {
            Label(tr("Import-Ordner ist leer", "Import Folder Is Empty"), systemImage: "tray")
        } description: {
            Text(tr("Lege Switch-Spiele (Ordner mit .nsp / .xci) in ~/NXNative/Import ab. Sie werden hier erkannt und können gesammelt umgewandelt werden.",
                    "Place Switch games (folders with .nsp / .xci) in ~/NXNative/Import. They are detected here and can be converted in one go."))
        } actions: {
            Button(tr("Import-Ordner öffnen", "Open Import Folder")) {
                importManager.openImportFolderInFinder()
            }
            Button(tr("Erneut prüfen", "Rescan")) {
                importManager.scanImportFolder()
            }
        }
    }

    // MARK: Pending games

    private var pendingView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(importManager.pendingGames) { game in
                        ImportGameRow(game: game) { isOn in
                            importManager.setSelection(for: game.id, to: isOn)
                        }
                    }
                } header: {
                    HStack {
                        Text(tr("\(importManager.supportedCount) unterstützt", "\(importManager.supportedCount) supported"))
                        if importManager.unsupportedCount > 0 {
                            Text("·")
                            Text(tr("\(importManager.unsupportedCount) ohne Profil oder Update", "\(importManager.unsupportedCount) without profile or update"))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Menu(tr("Auswahl", "Select")) {
                            Button(tr("Alle auswählen", "Select All")) { importManager.selectAll() }
                            Button(tr("Nur unterstützte", "Supported Only")) { importManager.selectSupportedOnly() }
                            Button(tr("Keine", "None")) { importManager.deselectAll() }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } footer: {
                    if importManager.unsupportedCount > 0 {
                        Text(tr("Spiele mit fehlenden Updates oder ohne Profil wurden vorsorglich abgewählt.",
                                "Games with missing updates or without a profile were deselected to avoid failed builds."))
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 12) {
                if !prefs.prodKeysExists {
                    Label(tr("prod.keys fehlt – bitte in den Einstellungen festlegen.", "prod.keys missing – please set it in Settings."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if buildManager.isRunning {
                    Label(tr("Warte, bis der aktuelle Build fertig ist.", "Wait until the current build has finished."),
                          systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text(tr("Spiele werden nacheinander kompiliert.", "Games are compiled one after another."))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button(tr("Ausgewählte umwandeln (\(importManager.selectedCount))", "Convert Selected (\(importManager.selectedCount))")) {
                    showConvertConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(importManager.selectedCount == 0 || !prefs.prodKeysExists || buildManager.isRunning)
            }
            .padding(12)
            .background(.bar)
        }
    }

    // MARK: Conversion in progress

    private var convertingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tr("Wird umgewandelt", "Converting")) \(importManager.currentGameIndex + 1) / \(max(1, importManager.activeBatchGames.count)): \(importManager.currentGameName)")
                    .font(.headline)
                Text(importManager.currentStageText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ProgressView(value: importManager.progressPercentage)

            if BuildStageInfo.isPipelineArchivePhase(importManager.currentStageText) {
                PipelinePhaseHint()
            }

            LogConsoleView(lines: importManager.logs, minHeight: 200)
                .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Button(tr("Stapel abbrechen", "Cancel Batch"), role: .cancel) {
                    importManager.cancelBatch()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    // MARK: Finished

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: importManager.wasCancelled ? "stop.circle" : "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(importManager.wasCancelled ? Color.orange : Color.green)
                .accessibilityHidden(true)

            Text(importManager.wasCancelled
                 ? tr("Stapelumwandlung abgebrochen", "Batch Conversion Cancelled")
                 : tr("Stapelumwandlung abgeschlossen", "Batch Conversion Complete"))
                .font(.title2.weight(.semibold))

            List {
                ForEach(importManager.conversionResults.keys.sorted(), id: \.self) { name in
                    let ok = importManager.conversionResults[name] ?? false
                    HStack {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ok ? Color.green : Color.red)
                        Text(name)
                        Spacer()
                        Text(ok ? tr("In „Meine Spiele“", "In “My Games”") : tr("Fehlgeschlagen", "Failed"))
                            .foregroundStyle(ok ? Color.secondary : Color.red)
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: 520, maxHeight: 260)

            HStack {
                Button(tr("Protokoll kopieren", "Copy Log")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(importManager.logs.joined(separator: "\n"), forType: .string)
                }
                Button(tr("Fertig", "Done")) {
                    importManager.isFinished = false
                    library.refreshLibrary()
                    if importManager.conversionResults.values.contains(true) {
                        router.selection = .library
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startConversion() {
        importManager.startBatchConversion(prodKeysPath: prefs.prodKeysPath,
                                           language: prefs.defaultGameLanguage) {
            library.refreshLibrary()
        }
    }
}

// MARK: - Row for an import candidate

struct ImportGameRow: View {
    let game: ImportGameItem
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(get: { game.isSelected }, set: onToggle)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(game.name)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(game.name)
                        .font(.headline)
                    Spacer()
                    Label(game.supportStatus.statusTitle, systemImage: game.supportStatus.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(game.supportStatus.badgeColor)
                }

                HStack(spacing: 6) {
                    if let tid = game.baseTitleId {
                        Text(tid).font(.caption.monospaced())
                        Text("·")
                    }
                    Text(tr("\(game.fileCount) Dateien", "\(game.fileCount) files"))
                    Text("·")
                    Text(ByteCountFormatter.string(fromByteCount: game.totalSizeBytes, countStyle: .file))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(game.supportStatus.statusDetail)
                    .font(.callout)
                    .foregroundStyle(game.supportStatus.isSupported ? Color.secondary : game.supportStatus.badgeColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
