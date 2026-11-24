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
                setupWarningSection
            }

            if importManager.pendingCount > 0 && !manager.isRunning {
                batchImportNoticeSection
            }

            sourceSection

            if form.needsProdKeys && !prefs.prodKeysExists && !manager.isRunning {
                missingKeysSection
            }

            if !manager.isRunning && !manager.isFinished {
                buildActionSection
            }

            advancedSection

            if manager.isRunning || manager.isFinished {
                Section(tr("Fortschritt & Ergebnis", "Progress & Result")) {
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
        .alert(tr("Zu wenig Speicher frei", "Not enough disk space"),
               isPresented: $form.lowSpaceConfirmationPending) {
            Button(tr("Trotzdem bauen", "Build Anyway"), role: .destructive) {
                form.startBuild(manager: manager, monitor: buildMonitor, prefs: prefs, library: library,
                                ignoringLowSpace: true)
            }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
        } message: {
            Text(lowSpaceMessage)
        }
    }

    private var lowSpaceMessage: String {
        form.diskSpace?.confirmationMessage(hasPreviousBuild: form.hasPreviousBuild) ?? ""
    }

    // MARK: Sections

    private var setupWarningSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Einrichtung unvollständig", "Setup Incomplete"))
                        .font(.callout.weight(.medium))
                    Text(tr("Einige Abhängigkeiten oder Werkzeuge fehlen. Builds werden fehlschlagen.",
                            "Some dependencies or tools are missing. Builds will fail."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("Einrichtung prüfen …", "Check Setup…")) {
                    router.showingSetup = true
                }
                .controlSize(.small)
            }
        }
    }

    private var batchImportNoticeSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(importManager.isReadOnlySource
                         ? tr("\(importManager.pendingCount) Spiel(e) auf externem Medium bereit",
                              "\(importManager.pendingCount) game(s) ready on external volume")
                         : tr("\(importManager.pendingCount) Spiel(e) im Import-Ordner bereit",
                              "\(importManager.pendingCount) game(s) ready in Import folder"))
                        .font(.callout.weight(.medium))
                    Text(tr("Mehrere Spiele können automatisch im Stapel umgewandelt werden.",
                            "Multiple games can be converted automatically in batch mode."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(tr("Stapel-Import öffnen …", "Open Batch Import…")) {
                    router.showingImportSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            if form.gameDirectory.isEmpty {
                emptySourceCard
            } else {
                selectedSourceCard
            }
        } header: {
            Text(tr("Spieldateien", "Game Files"))
        } footer: {
            sourceFooter
        }
    }

    private var emptySourceCard: some View {
        VStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                .font(.system(size: 34))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

            VStack(spacing: 4) {
                Text(tr("Spiele-Ordner oder .nup-Datei hier ablegen", "Drop a game folder or .nup file here"))
                    .font(.headline)
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.primary)
                Text(tr("Unterstützt .nsp, .xci, .nup sowie Switch-2-Dump-Ordner",
                        "Supports .nsp, .xci, .nup and Switch 2 dump folders"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(tr("Ordner oder .nup auswählen …", "Choose Folder or .nup…")) {
                if let url = FilePanels.chooseGameSource(prompt: tr("Auswählen", "Choose")) {
                    form.setSource(from: url)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
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

    private var selectedSourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: form.isSwitch2 ? "gamecontroller.fill" : "shippingbox.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(form.isSwitch2 ? Color.red : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(gameCardTitle)
                            .font(.headline)
                        if form.isSwitch2 {
                            BadgeView(text: "Switch 2", color: .red)
                        }
                    }
                    Text(form.gameDirectory)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(tr("Ändern …", "Change…")) {
                    if let url = FilePanels.chooseGameSource(prompt: tr("Ändern", "Change")) {
                        form.setSource(from: url)
                    }
                }
                .controlSize(.small)
                .disabled(isLocked)

                Button {
                    form.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("Auswahl aufheben", "Clear selection"))
                .disabled(isLocked)
            }

            if !form.detectedFiles.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(form.detectedFiles) { file in
                        HStack(spacing: 8) {
                            Image(systemName: file.kind.systemImage)
                                .foregroundStyle(file.kind.color)
                                .frame(width: 16)
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
            }

            if form.isSwitch2 {
                switch2Row
            }

            if form.hasPreviousBuild {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text(tr("Früherer Build vorhanden – Neubau wird stark beschleunigt.",
                            "Previous build found – rebuild will be significantly faster."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let space = form.diskSpace {
                HStack(spacing: 6) {
                    Image(systemName: space.isSufficient ? "externaldrive.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(space.isSufficient ? Color.secondary : Color.orange)
                    Text(space.isSufficient
                         ? tr("Freier Speicher: \(DiskSpaceEstimate.format(space.available)) (benötigt etwa \(DiskSpaceEstimate.format(space.required)))",
                              "Free space: \(DiskSpaceEstimate.format(space.available)) (about \(DiskSpaceEstimate.format(space.required)) needed)")
                         : tr("Wenig freier Speicher: \(DiskSpaceEstimate.format(space.available)) (benötigt etwa \(DiskSpaceEstimate.format(space.required)))",
                              "Low free space: \(DiskSpaceEstimate.format(space.available)) (about \(DiskSpaceEstimate.format(space.required)) needed)"))
                        .font(.caption)
                        .foregroundStyle(space.isSufficient ? Color.secondary : Color.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var gameCardTitle: String {
        if let p = form.switch2Profile { return p.name }
        if let first = form.detectedFiles.first {
            return URL(fileURLWithPath: first.name).deletingPathExtension().lastPathComponent
        }
        return URL(fileURLWithPath: form.gameDirectory).lastPathComponent
    }

    private var switch2Row: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case .switch2Packages = form.source {
                Label(GameSourceKind.switch2PackagesHint, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if form.switch2Profile != nil {
                Label(tr("nxnative-Profil vorhanden – keine prod.keys nötig.",
                         "nxnative profile available – no prod.keys needed."),
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
        if let hint = form.sourceHint {
            Text(hint)
                .foregroundStyle(.orange)
        } else if !form.gameDirectory.isEmpty && form.detectedFiles.isEmpty {
            Text(tr("In diesem Ordner wurden keine .nsp-, .xci- oder .nup-Dateien und kein Switch-2-Dump (base/exefs, base/romfs) gefunden.",
                    "No .nsp, .xci or .nup files and no Switch 2 dump (base/exefs, base/romfs) were found in this folder."))
                .foregroundStyle(.orange)
        }
    }

    private var missingKeysSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("prod.keys erforderlich", "prod.keys Required"))
                        .font(.callout.weight(.medium))
                    Text(tr("Zum Entschlüsseln von Switch-1-Spielen wird deine prod.keys-Datei benötigt.",
                            "Your prod.keys file is required to decrypt Switch 1 games."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(tr("prod.keys auswählen …", "Choose prod.keys…")) {
                    if let url = FilePanels.chooseKeysFile() {
                        prefs.prodKeysPath = url.path
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
    }

    private var buildActionSection: some View {
        Section {
            VStack(spacing: 6) {
                Button {
                    form.startBuild(manager: manager, monitor: buildMonitor, prefs: prefs, library: library)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill")
                        Text(tr("Spiel jetzt bauen (⌘R)", "Build Game Now (⌘R)"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!form.canStart(manager: manager, monitor: buildMonitor, prefs: prefs))

                if !form.canStart(manager: manager, monitor: buildMonitor, prefs: prefs) {
                    Text(buildDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var buildDisabledReason: String {
        if form.gameDirectory.isEmpty {
            return tr("Wähle zuerst Spieldateien oder einen Ordner aus.", "Choose game files or a folder first.")
        } else if !form.source.isBuildable {
            return form.sourceHint ?? tr("In diesem Ordner wurden keine baubaren Spieldateien gefunden.",
                                         "No buildable game files found in this folder.")
        } else if form.needsProdKeys && !prefs.prodKeysExists {
            return tr("prod.keys muss ausgewählt sein, um fortzufahren.", "prod.keys must be selected to proceed.")
        } else if buildMonitor.activeBuild != nil {
            return tr("Ein anderer Build läuft bereits im Hintergrund.", "Another build is already running in background.")
        }
        return ""
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(tr("Erweiterte Optionen", "Advanced Options"), isExpanded: $showAdvanced) {
                Picker(tr("Zielplattform", "Target Platform"), selection: $form.platform) {
                    ForEach(TargetPlatform.allCases) { platform in
                        Text(platform.title).tag(platform)
                    }
                }

                Picker(tr("Spielsprache", "Game Language"), selection: $form.language) {
                    ForEach(GameLanguage.list) { language in
                        Text(language.name).tag(language.code)
                    }
                }

                TextField(tr("App-Name (optional)", "App Name (optional)"), text: $form.appName,
                          prompt: Text(tr("Automatisch", "Automatic")))

                Toggle(tr("FPS-Anzeige im Spiel einbauen", "Show in-game FPS counter"), isOn: $form.showFps)
                Toggle(tr("Entpackte Zwischendaten behalten (schnellerer Neubau)",
                          "Keep extracted intermediate data (faster rebuilds)"),
                       isOn: $form.keepExtracted)

                HStack {
                    TextField("prod.keys", text: $prefs.prodKeysPath,
                              prompt: Text(tr("Pfad zur prod.keys-Datei", "Path to prod.keys file")))
                    Button(tr("Auswählen …", "Choose…")) {
                        if let url = FilePanels.chooseKeysFile() { prefs.prodKeysPath = url.path }
                    }
                    .controlSize(.small)
                }
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
