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
                        if importManager.pendingCount > 0 {
                            Button(tr("Jetzt umwandeln (\(importManager.pendingCount))", "Convert Now (\(importManager.pendingCount))")) {
                                router.showingImportSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(tr("Import öffnen …", "Open Import…")) {
                                router.showingImportSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
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
                          prompt: Text(tr("Ordner mit .nsp / .xci", "Folder containing .nsp / .xci")))
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
        } header: {
            Text(tr("Spiele-Ordner", "Game Folder"))
        } footer: {
            if !form.gameDirectory.isEmpty && form.detectedFiles.isEmpty {
                Text(tr("In diesem Ordner wurden keine .nsp-/.xci-Dateien gefunden.", "No .nsp / .xci files were found in this folder."))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var dropZone: some View {
        Label(tr("Spiele-Ordner hierher ziehen", "Drag a game folder here"), systemImage: "arrow.down.doc")
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
            if prefs.prodKeysPath.isEmpty {
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
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @State private var showLog = true

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

            if let error = manager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
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

    private func copyLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(manager.logs.joined(separator: "\n"), forType: .string)
    }
}
