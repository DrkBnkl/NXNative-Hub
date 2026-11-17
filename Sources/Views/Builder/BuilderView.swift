import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Build game
//
// HIG: standard grouped `Form` instead of hand-drawn cards. The primary action
// ("Build Game") lives in the toolbar and in the Game menu (⌘R).

struct BuilderView: View {
    @EnvironmentObject private var form: BuilderFormModel
    @EnvironmentObject private var manager: BuildManager
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @EnvironmentObject private var setupChecker: SetupChecker

    @State private var isDropTargeted = false
    @State private var showAdvanced = false

    private var isLocked: Bool { manager.isRunning }

    var body: some View {
        Form {
            if setupChecker.hasBlockingIssues && !manager.isRunning {
                Section {
                    HStack {
                        Label(tr("Die Einrichtung ist unvollständig – Builds schlagen fehl, bis alles bereit ist.",
                                 "Setup is incomplete – builds will fail until everything is ready."),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(tr("Einrichtung prüfen …", "Check Setup…")) {
                            router.showingSetup = true
                        }
                    }
                }
            }

            if !manager.isRunning {
                Section(tr("Stapel-Import", "Batch Import")) {
                    HStack {
                        Label(
                            importManager.pendingCount > 0
                                ? tr("\(importManager.pendingCount) Spiel(e) im Import-Ordner bereit", "\(importManager.pendingCount) game(s) ready in Import folder")
                                : tr("Stapel-Import aus ~/NXNative/Import", "Batch import from ~/NXNative/Import"),
                            systemImage: "tray.and.arrow.down.fill"
                        )
                        Spacer()
                        Button {
                            importManager.openImportFolderInFinder()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(tr("Import-Ordner im Finder öffnen", "Open the Import folder in Finder"))
                        Button {
                            importManager.scanImportFolder()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(importManager.isScanning || importManager.isConverting)
                        .help(tr("Import-Ordner neu einlesen", "Rescan the Import folder"))
                        if importManager.pendingCount > 0 {
                            Button(tr("Jetzt umwandeln (\(importManager.selectedCount))", "Convert Now (\(importManager.selectedCount))")) {
                                router.showingImportSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(importManager.selectedCount == 0)
                        } else {
                            Button(tr("Import öffnen …", "Open Import…")) {
                                router.showingImportSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if importManager.isScanning && importManager.pendingGames.isEmpty {
                        ProgressView(tr("Import-Ordner wird geprüft …", "Scanning Import folder…"))
                            .controlSize(.small)
                    }

                    ForEach(importManager.pendingGames) { game in
                        ImportOverviewRow(game: game) { isOn in
                            importManager.setSelection(for: game.id, to: isOn)
                        }
                        .disabled(importManager.isConverting)
                        .contextMenu { ImportGameContextMenu(game: game) }
                    }
                }
            }

            sourceSection
            keysSection
            platformSection
            advancedSection

            if manager.isRunning || manager.isFinished {
                Section(tr("Fortschritt", "Progress")) {
                    BuildProgressView()
                }
            } else if let active = buildMonitor.activeBuild {
                Section(tr("Laufender Hintergrund-Build", "Background Build in Progress")) {
                    externalBuildView(active)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarItem.builder.title)
        .toolbar { toolbarContent }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            HStack {
                TextField(tr("Ordner", "Folder"), text: $form.gameDirectory,
                          prompt: Text(tr("Ordner mit .nsp / .xci / .nup oder Switch-2-Dump, oder .nup-Datei", "Folder with .nsp / .xci / .nup or a Switch 2 dump, or a .nup file")))
                Button(tr("Auswählen …", "Choose…")) {
                    if let url = FilePanels.chooseFolders(multiple: false, prompt: tr("Auswählen", "Choose")).first {
                        form.gameDirectory = url.path
                    }
                }
            }
            .disabled(isLocked)

            dropZone

            if !form.detectedFiles.isEmpty {
                ForEach(form.detectedFiles) { file in
                    HStack(spacing: 8) {
                        Image(systemName: file.kind.systemImage)
                            .foregroundStyle(file.kind.color)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(file.name)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        BadgeView(text: file.kind.title, color: file.kind.color)
                        Text(file.sizeFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            if form.isSwitch2 {
                switch2Row
            }
        } header: {
            Text(tr("Spiele-Ordner", "Game Folder"))
        } footer: {
            if let hint = form.sourceHint {
                Text(hint)
                    .foregroundStyle(.orange)
            } else if !form.gameDirectory.isEmpty && form.detectedFiles.isEmpty {
                Text(tr("In diesem Ordner wurden keine .nsp-, .xci- oder .nup-Dateien und kein Switch-2-Dump (base/exefs, base/romfs) gefunden.",
                        "No .nsp, .xci or .nup files and no Switch 2 dump (base/exefs, base/romfs) were found in this folder."))
                    .foregroundStyle(.orange)
            } else if !form.detectedFiles.isEmpty {
                sourceFooter
            }
        }
    }

    /// Switch 2 game detected from a NUP or a dump folder: title ID and profile check.
    private var switch2Row: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                BadgeView(text: "Switch 2", color: .red)
                Text(form.switch2Profile?.name ?? tr("Unbekanntes Spiel", "Unknown game"))
                    .font(.callout.weight(.semibold))
                if let tid = form.switch2TitleId {
                    Text(tid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if case .switch2Packages = form.source {
                Label(GameSourceKind.switch2PackagesHint, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if form.switch2Profile != nil {
                Label(tr("nxnative-Profil vorhanden – keine prod.keys nötig.", "nxnative profile available – no prod.keys needed."),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label(tr("Kein nxnative-Profil für dieses Spiel – Switch-2-Spiele lassen sich nur mit Profil bauen.",
                         "No nxnative profile for this game – Switch 2 games can only be built with a profile."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if form.hasPreviousBuild {
                Label(tr("Ein früherer Build wurde gefunden – nxnative verwendet ihn wieder, der Neubau geht deutlich schneller.",
                         "A previous build was found – nxnative reuses it, so this build is much faster."),
                      systemImage: "bolt.fill")
            }
            if let space = form.diskSpace {
                if space.isSufficient {
                    Text(tr("Freier Speicher: \(DiskSpaceEstimate.format(space.available)) (benötigt etwa \(DiskSpaceEstimate.format(space.required)))",
                            "Free space: \(DiskSpaceEstimate.format(space.available)) (about \(DiskSpaceEstimate.format(space.required)) needed)"))
                } else {
                    Label(form.hasPreviousBuild
                          ? tr("Wenig Speicher frei: \(DiskSpaceEstimate.format(space.available)). Ein erster Build braucht etwa \(DiskSpaceEstimate.format(space.required)); ein Neubau meist deutlich weniger.",
                               "Low disk space: \(DiskSpaceEstimate.format(space.available)). A first build needs about \(DiskSpaceEstimate.format(space.required)); a rebuild usually much less.")
                          : tr("Zu wenig Speicher frei: \(DiskSpaceEstimate.format(space.available)) – der Build braucht etwa \(DiskSpaceEstimate.format(space.required)) (doppelte Spielgröße + 10 GB).",
                               "Not enough disk space: \(DiskSpaceEstimate.format(space.available)) – the build needs about \(DiskSpaceEstimate.format(space.required)) (twice the game size + 10 GB)."),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var dropZone: some View {
        Label(tr("Spiele-Ordner oder .nup-Datei hierher ziehen", "Drag a game folder or .nup file here"), systemImage: "arrow.down.doc")
            .font(.callout)
            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let provider = providers.first, !isLocked else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url = url else { return }
                    DispatchQueue.main.async { form.setSource(from: url) }
                }
                return true
            }
    }

    private var keysSection: some View {
        Section {
            HStack {
                TextField("prod.keys", text: $prefs.prodKeysPath,
                          prompt: Text(tr("Pfad zur prod.keys-Datei", "Path to prod.keys file")))
                Button(tr("Auswählen …", "Choose…")) {
                    if let url = FilePanels.chooseKeysFile() { prefs.prodKeysPath = url.path }
                }
            }
            .disabled(isLocked)
        } header: {
            Text(tr("Schlüssel", "Keys"))
        } footer: {
            if form.isSwitch2 && form.source.isBuildable {
                Text(tr("Für Switch-2-Spiele (.nup oder Dump-Ordner) werden keine prod.keys benötigt.",
                        "Switch 2 games (.nup or dump folder) need no prod.keys."))
            } else if prefs.prodKeysPath.isEmpty {
                Text(tr("Die prod.keys deiner eigenen Switch werden zum Entschlüsseln benötigt.", "The prod.keys from your own Switch are required for decryption."))
            } else if prefs.prodKeysExists {
                Label(tr("Datei gefunden", "File found"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label(tr("Datei nicht gefunden", "File not found"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var platformSection: some View {
        Section {
            Picker(tr("Zielplattform", "Target Platform"), selection: $form.platform) {
                ForEach(TargetPlatform.allCases) { platform in
                    Text(platform.title).tag(platform)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isLocked)
        } footer: {
            Text(form.platform.subtitle)
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(tr("Erweiterte Optionen", "Advanced Options"), isExpanded: $showAdvanced) {
                Picker(tr("Spielsprache", "Game Language"), selection: $form.language) {
                    ForEach(GameLanguage.list) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Toggle(tr("FPS-Anzeige einbauen", "Show FPS counter"), isOn: $form.showFps)
                Toggle(tr("Entpackte Daten behalten (schnellerer Neubau)", "Keep extracted data (faster rebuilds)"), isOn: $form.keepExtracted)
                TextField(tr("App-Name", "App Name"), text: $form.appName,
                          prompt: Text(tr("Automatisch", "Automatic")))
            }
            .disabled(isLocked)
        }
    }

    private func externalBuildView(_ build: ActiveBuildInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(build.gameName) {
                Text("PID \(build.pid)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(build.currentStageDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            if BuildStageInfo.isPipelineArchivePhase(build.currentStageDescription) {
                PipelinePhaseHint()
            }
            LogConsoleView(lines: build.recentLogLines, minHeight: 180)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if manager.isRunning {
                Button(role: .cancel) {
                    manager.cancel()
                } label: {
                    Label(tr("Abbrechen", "Cancel"), systemImage: "stop.fill")
                }
                .help(tr("Laufenden Build abbrechen", "Cancel the running build"))
            } else {
                if manager.isFinished {
                    Button {
                        manager.reset()
                    } label: {
                        Label(tr("Zurücksetzen", "Reset"), systemImage: "arrow.counterclockwise")
                    }
                    .help(tr("Ergebnis und Protokoll ausblenden", "Clear result and log"))
                }

                Button {
                    form.startBuild(manager: manager, monitor: buildMonitor, prefs: prefs, library: library)
                } label: {
                    Label(tr("Spiel bauen", "Build Game"), systemImage: "hammer.fill")
                }
                .disabled(!form.canStart(manager: manager, monitor: buildMonitor, prefs: prefs))
                .help(tr("Build starten (⌘R)", "Start build (⌘R)"))
            }
        }
    }
}

// MARK: - Progress & log of the build started from this app

struct BuildProgressView: View {
    @EnvironmentObject private var manager: BuildManager
    @EnvironmentObject private var form: BuilderFormModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @State private var showLog = true
    @State private var didTrashBuildFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if manager.isRunning {
                if let fraction = manager.progressFraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                HStack {
                    Text(manager.currentStep)
                        .lineLimit(1)
                    Spacer()
                    Text([manager.progressText, manager.etaText].filter { !$0.isEmpty }.joined(separator: " · "))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if BuildStageInfo.isPipelineArchivePhase(BuildStageInfo.translate(name: manager.stageName, step: "").title) {
                    PipelinePhaseHint()
                }
            }

            if let artifact = manager.createdArtifactPath {
                artifactRow(artifact)
            }

            if manager.buildSucceeded {
                cleanupSection
            }

            if let error = manager.errorMessage {
                Label(error, systemImage: manager.wasCancelled ? "stop.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(manager.wasCancelled ? Color.secondary : Color.red)
                    .textSelection(.enabled)
            }

            if let logsPath = manager.buildLogsPath {
                HStack {
                    Text(tr("Die vollständige Ausgabe aller Werkzeuge liegt im Build-Ordner.",
                            "The complete output of all tools is in the build folder."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Build-Logs öffnen", "Open Build Logs")) {
                        FilePanels.openInFinder(logsPath)
                    }
                    .controlSize(.small)
                }
            }

            DisclosureGroup(isExpanded: $showLog) {
                LogConsoleView(lines: manager.logs, minHeight: 200)
            } label: {
                HStack {
                    Text("\(tr("Protokoll", "Log")) (\(manager.logs.count))")
                    Spacer()
                    if !manager.logs.isEmpty {
                        Button(tr("Kopieren", "Copy"), action: copyLog)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusHeader: some View {
        if manager.isRunning {
            Label(manager.stageName.isEmpty
                  ? tr("Wird vorbereitet …", "Preparing…")
                  : "\(tr("Phase", "Phase")) \(manager.currentStageIndex)/\(manager.totalStages): \(BuildStageInfo.translate(name: manager.stageName, step: "").title)",
                  systemImage: "gearshape.2")
                .font(.headline)
        } else if manager.buildSucceeded {
            Label(tr("Build erfolgreich abgeschlossen", "Build completed successfully"), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        } else if manager.wasCancelled {
            Label(tr("Build abgebrochen", "Build cancelled"), systemImage: "stop.circle")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else if manager.isFinished {
            Label(tr("Build fehlgeschlagen", "Build failed"), systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
        }
    }

    private func artifactRow(_ artifact: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Ergebnis", "Result"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: artifact).lastPathComponent)
                    .font(.callout.weight(.semibold))
            }
            Spacer()
            Button(tr("Im Finder zeigen", "Show in Finder")) {
                FilePanels.revealInFinder(artifact)
            }
            if manager.builtPlatform == .macApp {
                Button(tr("Einstellungen …", "Settings…")) {
                    GameActions.openSettings(appPath: artifact, settings: gameSettings, router: router)
                }
                Button(tr("Starten", "Launch")) {
                    GameActions.launch(appPath: artifact)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var cleanupSection: some View {
        if let folder = manager.buildFolders.first, !didTrashBuildFolder {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "externaldrive.badge.minus")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Speicherplatz freigeben: Build-Ordner löschen", "Free Disk Space: Delete Build Folder"))
                        .font(.callout.weight(.semibold))
                    Text(tr("Der Build-Ordner (\(folder.lastPathComponent)) belegt \(BuildWorkFolder.formattedSize(of: folder)). Die NSP-Quelldateien bleiben erhalten.",
                            "The build folder (\(folder.lastPathComponent)) occupies \(BuildWorkFolder.formattedSize(of: folder)). The NSP source files are kept."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(tr("In Papierkorb legen", "Move to Trash")) {
                    if manager.trashBuildFolder(folder) {
                        didTrashBuildFolder = true
                        form.scanGameFolder()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if didTrashBuildFolder {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(tr("Build-Ordner wurde in den Papierkorb gelegt – Speicherplatz freigegeben.",
                        "Build folder was moved to the Trash – disk space freed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private func copyLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manager.logs.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - Compact row for the Import folder overview

private struct ImportOverviewRow: View {
    let game: ImportGameItem
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { game.isSelected }, set: onToggle)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(game.name)
            Image(systemName: game.supportStatus.iconName)
                .foregroundStyle(game.supportStatus.badgeColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(game.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if game.isSwitch2 {
                        BadgeView(text: "Switch 2", color: .red)
                    }
                }
                Text(game.fileNames.isEmpty ? game.sourceDescription : game.fileNames.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(game.supportStatus.statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(game.supportStatus.badgeColor)
            Text(ByteCountFormatter.string(fromByteCount: game.totalSizeBytes, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .help(game.supportStatus.statusDetail)
    }
}
