import SwiftUI
import AppKit

// MARK: - Game settings
//
// Grouped form with standard controls (keyboard and VoiceOver support).
// Games built with a current nxnative describe their own settings (launcher.json); the form is
// generated from that list. Older builds get the fixed legacy form.
// Esc = Cancel, Return = Save & Launch. Opened with ⌘I – ⌘, is reserved for the
// app settings window (HIG).

struct GameSettingsSheet: View {
    @EnvironmentObject private var settings: GameSettingsModel
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter
    @AppStorage("gameSettingsShowAll") private var showAllSettings = false

    private var matchingGame: InstalledGame? {
        library.games.first { $0.path == settings.associatedAppPath || $0.titleId == settings.titleId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Title-ID") {
                        Text(settings.titleId)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text(settings.gameName.isEmpty ? tr("Spiel", "Game") : settings.gameName)
                        .font(.headline)
                } footer: {
                    headerFooter
                }

                if let game = matchingGame {
                    Section(tr("nxnative-Build-Status", "nxnative Build Status")) {
                        LabeledContent(tr("Status", "Status")) {
                            HStack(spacing: 6) {
                                Image(systemName: game.updateStatus.statusIcon)
                                    .foregroundStyle(game.updateStatus.statusColor)
                                Text(game.updateStatus.statusTitle)
                                    .font(.body.weight(.medium))
                            }
                        }
                        Text(game.updateStatus.tooltip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LabeledContent(tr("Build-Commit", "Build Commit")) {
                            Text(game.buildCommit ?? tr("Älterer Build (nicht erfasst)", "Older build (not recorded)"))
                                .font(.body.monospaced())
                        }
                        if let chain = game.shaderChain {
                            LabeledContent(tr("Shader-Chain", "Shader Chain")) {
                                Text("b-\(chain)")
                                    .font(.body.monospaced())
                            }
                        }
                    }
                }

                if let list = settings.list {
                    listSections(list)
                } else {
                    legacySections
                }

                launchOptionsSection

                savesSection

                SaveSyncSection(titleId: settings.titleId)
            }
            .formStyle(.grouped)

            Divider()

            bottomBar
        }
        .frame(width: 580, height: 640)
    }

    // MARK: Header

    @ViewBuilder
    private var headerFooter: some View {
        if settings.usesSettingsList {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Die Einstellungen stammen aus dem Spiel selbst und gelten auch für sein eigenes Startfenster. Gespeichert werden nur Abweichungen von den getesteten Standardwerten.",
                        "These settings come from the game itself and also apply to its own launch window. Only changes from the tested defaults are saved."))
                if settings.hasEnvValuesToMigrate {
                    Label(tr("env.txt enthält noch Werte einer älteren Hub-Version. Beim Sichern werden sie übernommen und aus env.txt entfernt, damit die getesteten Standardwerte wieder greifen.",
                             "env.txt still contains values from an older Hub version. Saving takes them over and removes them from env.txt, so the tested defaults apply again."),
                          systemImage: "info.circle")
                }
            }
        } else {
            Text(tr("Älterer Build ohne Einstellungsliste: Die Werte werden beim Spielstart aus env.txt in ~/Library/Application Support/nxnative/ geladen. Neu bauen, um die Einstellungen des Spiels zu erhalten.",
                    "Older build without a settings list: values are loaded at launch from env.txt in ~/Library/Application Support/nxnative/. Rebuild the game to get its own settings."))
        }
    }

    // MARK: Settings list (launcher.json)

    @ViewBuilder
    private func listSections(_ list: LauncherSettingsList) -> some View {
        let showAll = showAllSettings || !list.hasBasicRows
        ForEach(list.sections, id: \.self) { section in
            let rows = list.usableSettings.filter {
                $0.section == section && settings.isVisible($0) && (showAll || $0.isBasic)
            }
            if !rows.isEmpty {
                Section(LauncherSettingsList.localizedSection(section)) {
                    ForEach(rows) { row in
                        settingRow(row)
                    }
                }
            }
        }
        if list.hasBasicRows {
            Section {
                Toggle(tr("Alle Einstellungen anzeigen", "Show All Settings"), isOn: $showAllSettings)
            } footer: {
                Text(tr("Ohne diese Option sind nur die wichtigsten Einstellungen sichtbar.", "Without this option only the most important settings are shown."))
            }
        }
    }

    @ViewBuilder
    private func settingRow(_ row: LauncherSetting) -> some View {
        let value = valueBinding(row)
        VStack(alignment: .leading, spacing: 4) {
            if let pinned = settings.pinnedByEnvFile[row.env] {
                fixedRow(row, value: pinned,
                         reason: tr("In env.txt festgelegt – dort ändern oder entfernen.", "Set in env.txt – change or remove it there."))
            } else if let fixed = settings.fixedByBuild[row.env] {
                fixedRow(row, value: fixed,
                         reason: tr("Vom Build festgelegt (dm/env.txt in der App).", "Fixed by the build (dm/env.txt inside the app)."))
            } else {
                switch row.kind {
                case .choice:
                    Picker(row.label, selection: value) {
                        ForEach(row.choices, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .modifier(ChoicePickerStyle(segmented: row.choices.count <= 3))
                case .toggle:
                    Toggle(row.label, isOn: Binding(
                        get: { value.wrappedValue == row.onValue },
                        set: { value.wrappedValue = $0 ? row.onValue : row.offValue }))
                case .range:
                    rangeRow(row, value: value)
                case nil:
                    EmptyView()
                }
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func fixedRow(_ row: LauncherSetting, value: String, reason: String) -> some View {
        let label = row.choices.first { $0.value == value }?.label ?? value
        LabeledContent(row.label) {
            Text(label)
        }
        Text(reason)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func rangeRow(_ row: LauncherSetting, value: Binding<String>) -> some View {
        let lower = row.min ?? 0
        let upper = Swift.max(row.max ?? 1, lower)
        let number = Binding<Double>(
            get: { Double(value.wrappedValue) ?? Double(row.defaultValue) ?? lower },
            set: { value.wrappedValue = row.formatRange($0) })
        return LabeledContent(row.label) {
            HStack {
                if let step = row.step, step > 0 {
                    Slider(value: number, in: lower...upper, step: step)
                        .frame(maxWidth: 200)
                        .accessibilityLabel(row.label)
                } else {
                    Slider(value: number, in: lower...upper)
                        .frame(maxWidth: 200)
                        .accessibilityLabel(row.label)
                }
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.percentText(value.wrappedValue))
                    if let resolution = row.resolutionText(value.wrappedValue, docked: settings.isDocked) {
                        Text(resolution).font(.caption2)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            }
        }
    }

    private func valueBinding(_ row: LauncherSetting) -> Binding<String> {
        Binding(get: { settings.binding(for: row) },
                set: { settings.values[row.env] = $0 })
    }

    // MARK: Legacy form (builds without launcher.json)

    @ViewBuilder
    private var legacySections: some View {
        Section(tr("Grafik & Bildrate", "Graphics & Frame Rate")) {
            Picker(tr("Bildrate", "Frame Rate"), selection: $settings.fpsTarget) {
                Text(tr("60 FPS (flüssig)", "60 FPS (smooth)")).tag("60")
                Text(tr("30 FPS (original)", "30 FPS (original)")).tag("30")
            }
            .pickerStyle(.segmented)

            Picker(tr("Konsolenmodus", "Console Mode"), selection: $settings.opMode) {
                Text("Docked (1080p)").tag("1")
                Text("Handheld (720p)").tag("0")
            }
            .pickerStyle(.segmented)

            Picker(tr("Hochskalierung", "Upscaling"), selection: $settings.upscaling) {
                Text("Apple MetalFX").tag("metalfx")
                Text(tr("Aus", "Off")).tag("off")
            }
            .pickerStyle(.segmented)

            Toggle(tr("Frame-Buffering (weniger Ruckler)", "Frame buffering (reduces stutter)"), isOn: $settings.frameBuffering)
            Toggle(tr("FPS-Anzeige im Spiel", "In-game FPS counter"), isOn: $settings.showFps)
            Toggle(tr("Metal-Performance-HUD", "Metal Performance HUD"), isOn: $settings.metalHud)
        }

        Section(tr("Anzeige & Steuerung", "Display & Controls")) {
            Picker(tr("Start im", "Launch In"), selection: $settings.fullscreen) {
                Text(tr("Fenster", "Window")).tag(false)
                Text(tr("Vollbild", "Full Screen")).tag(true)
            }
            .pickerStyle(.segmented)

            Picker(tr("Spielsprache", "Game Language"), selection: $settings.language) {
                ForEach(GameLanguage.list) { language in
                    Text(language.name).tag(language.code)
                }
            }

            Toggle(tr("Controller-Vibration", "Controller Rumble"), isOn: $settings.rumble)

            LabeledContent(tr("Vibrationsstärke", "Rumble Strength")) {
                HStack {
                    Slider(value: $settings.rumbleGain, in: 0.5...2.5, step: 0.5)
                        .frame(maxWidth: 200)
                        .accessibilityLabel(tr("Vibrationsstärke", "Rumble Strength"))
                    Text(String(format: "%.1f×", settings.rumbleGain))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .disabled(!settings.rumble)
        }
    }

    // MARK: Launch Options

    private var launchOptionsSection: some View {
        Section {
            Toggle(tr("Startfenster des Spiels überspringen", "Skip game start window"), isOn: $settings.skipLauncher)
        } header: {
            Text(tr("Start-Optionen", "Launch Options"))
        } footer: {
            Text(tr("Startet das Spiel direkt mit den festgelegten Parametern (Sprache, FPS usw.), ohne das nxnative-Startfenster zu öffnen. Bei gedrückter Wahltaste (⌥) beim Start wird das Fenster weiterhin angezeigt.",
                    "Starts the game directly with the configured parameters (language, FPS, etc.) without opening the nxnative start window. Holding Option (⌥) at launch will still show the window."))
        }
    }

    // MARK: Saves

    private var savesSection: some View {
        Section {
            HStack {
                Button(tr("Spielstand importieren …", "Import Save…"), action: importSave)
                if let ryujinxPath = settings.ryujinxSavePath {
                    Button(tr("Aus Ryujinx übernehmen", "Import from Ryujinx")) {
                        importFromRyujinx(ryujinxPath)
                    }
                }
                Spacer()
                Button(tr("Im Finder öffnen", "Open in Finder")) {
                    SaveGameImporter.openSaveFolder(titleId: settings.titleId)
                }
            }
        } header: {
            Text(tr("Spielstände", "Saves"))
        } footer: {
            Text(tr("Backups aus JKSV, Checkpoint oder Ryujinx können direkt übernommen werden. Der vorhandene Spielstand wird vorher gesichert.",
                    "Backups from JKSV, Checkpoint or Ryujinx can be imported directly. The existing save is backed up first."))
        }
    }

    // MARK: Buttons

    private var bottomBar: some View {
        HStack {
            Button(tr("Standardwerte", "Restore Defaults")) {
                settings.resetToDefaults()
            }

            if let status = settings.statusMessage {
                Label(status.text, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? Color.red : Color.green)
                    .font(.callout)
                    .lineLimit(2)
            }

            Spacer()

            Button(tr("Abbrechen", "Cancel")) {
                close()
            }
            .keyboardShortcut(.cancelAction)

            Button(tr("Sichern", "Save")) {
                if settings.save() { library.refreshLibrary() }
            }

            Button(tr("Sichern & Starten", "Save & Launch")) {
                if settings.saveAndLaunch() {
                    library.refreshLibrary()
                    close()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(settings.associatedAppPath == nil)
        }
        .padding(14)
    }

    private func close() {
        router.showingGameSettings = false
    }

    private func importSave() {
        let urls = FilePanels.chooseSaveSources()
        guard !urls.isEmpty else { return }
        let result = SaveGameImporter.importSaves(from: urls, titleId: settings.titleId)
        report(result)
    }

    private func importFromRyujinx(_ path: String) {
        report(SaveGameImporter.importFromRyujinx(titleId: settings.titleId, sourcePath: path))
    }

    private func report(_ result: SaveGameImporter.Result) {
        if result.copiedCount > 0 {
            settings.showStatus(tr("Spielstand importiert (\(result.copiedCount) Objekte)", "Save imported (\(result.copiedCount) items)"), isError: false)
        } else {
            settings.showStatus(tr("Keine Speicherdaten gefunden", "No save data found"), isError: true)
        }
    }
}

/// Segmented control for up to three options, a pop-up menu for longer lists (HIG).
private struct ChoicePickerStyle: ViewModifier {
    let segmented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if segmented {
            content.pickerStyle(.segmented)
        } else {
            content.pickerStyle(.menu)
        }
    }
}
