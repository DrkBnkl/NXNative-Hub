import SwiftUI
import AppKit

// MARK: - Game settings (from the game's launcher.json)
//
// Grouped form with standard segmented pickers (keyboard and VoiceOver support).
// Esc = Cancel, Return = Save & Launch. Opened with ⌘I – ⌘, is reserved for the
// app settings window (HIG).

struct GameSettingsSheet: View {
    @EnvironmentObject private var settings: GameSettingsModel
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter
    @State private var showAdvanced = false

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
                    Text(tr("Gespeichert werden nur Abweichungen von den getesteten Standardwerten – dieselben Einstellungen wie im Einstellungsfenster des Spiels.",
                            "Only changes from the tested defaults are saved – the same settings as in the game's own settings window."))
                }

                if settings.hasSettingsList {
                    ForEach(settings.sections(basic: true), id: \.self) { section in
                        settingsSection(section, basic: true)
                    }

                    if !settings.sections(basic: false).isEmpty {
                        Section {
                            Toggle(tr("Weitere Einstellungen zeigen", "Show more settings"), isOn: $showAdvanced)
                        }
                        if showAdvanced {
                            ForEach(settings.sections(basic: false), id: \.self) { section in
                                settingsSection(section, basic: false)
                            }
                        }
                    }
                } else {
                    Section {
                        Text(tr("Dieses Spiel wurde ohne Einstellungsliste (launcher.json) gebaut. Baue es mit aktuellem nxnative neu, um die Einstellungen hier zu ändern.",
                                "This game was built without a settings list (launcher.json). Rebuild it with current nxnative to change its settings here."))
                            .foregroundStyle(.secondary)
                    }
                }

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
                    Text(tr("Backups aus JKSV, Checkpoint oder Ryujinx ersetzen den Spielstand. Der vorhandene wird vorher als save_backup_… gesichert.",
                            "Backups from JKSV, Checkpoint or Ryujinx replace the save. The existing one is kept as save_backup_… first."))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button(tr("Standardwerte", "Restore Defaults")) {
                    settings.resetToDefaults()
                }
                .disabled(!settings.differsFromDefaults)

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
                .disabled(!settings.hasSettingsList)

                Button(settings.hasSettingsList ? tr("Sichern & Starten", "Save & Launch") : tr("Starten", "Launch")) {
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
        .frame(width: 580, height: 640)
    }

    @ViewBuilder
    private func settingsSection(_ section: String, basic: Bool) -> some View {
        let rows = settings.rows(in: section, basic: basic)
        if !rows.isEmpty {
            Section(LauncherText.section(section)) {
                ForEach(rows) { setting in
                    LauncherSettingRow(setting: setting,
                                       value: binding(for: setting),
                                       fixedValue: settings.fixed[setting.env])
                }
            }
        }
    }

    private func binding(for setting: LauncherSetting) -> Binding<String> {
        Binding(
            get: { settings.value(setting) },
            set: { settings.values[setting.env] = $0 }
        )
    }

    private func close() {
        router.showingGameSettings = false
    }

    private func importSave() {
        let urls = FilePanels.chooseSaveSources()
        guard !urls.isEmpty else { return }
        let result = SaveGameImporter.importSaves(from: urls, titleId: settings.titleId, bundleId: settings.bundleId)
        report(result)
    }

    private func importFromRyujinx(_ path: String) {
        report(SaveGameImporter.importFromRyujinx(titleId: settings.titleId, bundleId: settings.bundleId, sourcePath: path))
    }

    private func report(_ result: SaveGameImporter.Result) {
        if let error = result.errorMessage {
            settings.showStatus(error, isError: true)
        } else if result.copiedCount > 0, let cloud = result.cloudSavesFolder {
            // Shown as a lasting notice: the game may replace the import with the cloud copy.
            settings.showStatus(tr("Spielstand importiert. Achtung: Das Spiel synchronisiert mit \(cloud) und könnte beim nächsten Start die Cloud-Kopie verwenden.",
                                   "Save imported. Note: the game syncs with \(cloud) and may use the cloud copy at its next start."), isError: true)
        } else if result.copiedCount > 0 {
            settings.showStatus(tr("Spielstand importiert (\(result.copiedCount) Objekte)", "Save imported (\(result.copiedCount) items)"), isError: false)
        } else {
            settings.showStatus(tr("Keine Speicherdaten gefunden", "No save data found"), isError: true)
        }
    }
}

// MARK: - One row of launcher.json

private struct LauncherSettingRow: View {
    let setting: LauncherSetting
    @Binding var value: String
    /// Set by an env file: shown, not changeable.
    let fixedValue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            control
                .disabled(fixedValue != nil)
            if let fixedValue {
                Label(tr("Festgelegt in env.txt (\(fixedValue))", "Set in env.txt (\(fixedValue))"), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !setting.note.isEmpty {
                Text(LauncherText.note(setting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        let label = LauncherText.label(setting)
        switch setting.kind {
        case "toggle":
            Toggle(label, isOn: Binding(
                get: { value == setting.onValue },
                set: { value = $0 ? setting.onValue : setting.offValue }
            ))
        case "range":
            LabeledContent(label) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(value) ?? Double(setting.defaultValue) ?? setting.min ?? 0 },
                        set: { value = setting.formatRange($0) }
                    ), in: (setting.min ?? 0)...(setting.max ?? 1), step: setting.step ?? 0.1)
                    .frame(maxWidth: 200)
                    .accessibilityLabel(label)
                    Text(rangeText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        default:
            let options = (setting.options ?? []).filter { $0.count == 2 }
            if options.count <= 3 {
                picker(label, options).pickerStyle(.segmented)
            } else {
                picker(label, options).pickerStyle(.menu)
            }
        }
    }

    private func picker(_ label: String, _ options: [[String]]) -> some View {
        Picker(label, selection: $value) {
            ForEach(options, id: \.[0]) { option in
                Text(LauncherText.option(option[0], label: option[1], of: setting)).tag(option[0])
            }
            // A value an env file sets that the list does not offer is still shown.
            if !options.contains(where: { $0[0] == value }) {
                Text(value).tag(value)
            }
        }
    }

    private var rangeText: String {
        let n = Double(value) ?? 0
        if setting.env == "DM_RENDER_SCALE" { return "\(Int((n * 100).rounded())) %" }
        if setting.env == "DM_RUMBLE_GAIN" { return String(format: "%.1f×", n) }
        return setting.formatRange(n)
    }
}
