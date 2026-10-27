import SwiftUI
import AppKit

// MARK: - Game settings (env.txt)
//
// Grouped form with standard segmented pickers (keyboard and VoiceOver support).
// Esc = Cancel, Return = Save & Launch. Opened with ⌘I – ⌘, is reserved for the
// app settings window (HIG).

struct GameSettingsSheet: View {
    @EnvironmentObject private var settings: GameSettingsModel
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter

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
                    Text(tr("Die Einstellungen werden beim Spielstart aus env.txt in ~/Library/Application Support/nxnative/ geladen.",
                            "Settings are loaded at launch from env.txt in ~/Library/Application Support/nxnative/."))
                }

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
            .formStyle(.grouped)

            Divider()

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
        .frame(width: 580, height: 640)
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
