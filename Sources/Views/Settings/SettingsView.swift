import SwiftUI

// MARK: - Settings window (⌘,)
//
// HIG: app-wide preferences live in the standard Settings scene, not in the main window.

struct SettingsView: View {
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(tr("Allgemein", "General"), systemImage: "gearshape") }
            LibrarySettingsView()
                .tabItem { Label(tr("Mediathek", "Library"), systemImage: "books.vertical") }
            SetupChecklistView()
                .tabItem { Label(tr("Einrichtung", "Setup"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 600, height: 520)
        .id(lang.currentChoice)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var updater: UpdateManager
    @EnvironmentObject private var setupChecker: SetupChecker
    @EnvironmentObject private var importManager: ImportBatchManager

    var body: some View {
        Form {
            Section {
                Picker(tr("Sprache der App", "App Language"), selection: $lang.currentChoice) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                Picker(tr("Standard-Spielsprache", "Default Game Language"), selection: $prefs.defaultGameLanguage) {
                    ForEach(GameLanguage.list) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Toggle(tr("Mitteilung, wenn ein Build fertig ist", "Notify When a Build Finishes"), isOn: $prefs.notifyWhenBuildsFinish)
                    .onChange(of: prefs.notifyWhenBuildsFinish) { _, enabled in
                        if enabled { Notifier.requestAuthorizationIfNeeded() }
                    }
                Toggle(tr("Startfenster der Spiele beim Start überspringen", "Skip Game Start Window at Launch"), isOn: $prefs.skipGameLauncher)
            } footer: {
                Text(tr("Spiele werden direkt mit den gewählten Einstellungen gestartet, ohne das nxnative-Startfenster zu öffnen. Die Spielsprache wird für neue Builds und den Stapel-Import verwendet.",
                        "Games launch directly with configured settings without opening the nxnative start window. The game language is used for new builds and batch imports."))
            }

            Section {
                HStack {
                    TextField("prod.keys", text: $prefs.prodKeysPath,
                              prompt: Text(tr("Pfad zur prod.keys-Datei", "Path to prod.keys file")))
                    Button(tr("Auswählen …", "Choose…")) {
                        if let url = FilePanels.chooseKeysFile() { prefs.prodKeysPath = url.path }
                    }
                }
                Button(tr("Automatisch suchen", "Detect Automatically")) {
                    prefs.autoDetectKeysIfNeeded()
                }
                .disabled(prefs.prodKeysExists)
            } header: {
                Text(tr("Schlüssel", "Keys"))
            } footer: {
                if prefs.prodKeysExists {
                    Label(tr("Datei gefunden", "File found"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(tr("Gesucht wird u. a. in ~/.switch, ~/NXNative/keys und im Ryujinx-Ordner.",
                            "Searched locations include ~/.switch, ~/NXNative/keys and the Ryujinx folder."))
                }
            }

            Section {
                Picker(tr("Ort", "Location"), selection: locationMode) {
                    Text(tr("Automatisch", "Automatic")).tag(false)
                    Text(tr("Eigener Ordner", "Custom Folder")).tag(true)
                }
                .pickerStyle(.radioGroup)

                if !prefs.customRepoPath.isEmpty {
                    HStack {
                        Text(prefs.customRepoPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(tr("Ändern …", "Change…"), action: chooseRepoFolder)
                    }
                }

                LabeledContent(tr("Verwendet", "In Use")) {
                    Text(updater.repoExists ? updater.repoPath : tr("Nicht gefunden", "Not found"))
                        .foregroundStyle(updater.repoExists ? Color.secondary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(tr("Version", "Version")) {
                    Text(updater.currentCommitHash.isEmpty ? "–" : updater.currentCommitHash)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("nxnative")
            } footer: {
                Text(tr("Automatisch: ~/NXNative/nxnative. Der Ordner muss scripts/build_ipa_from_nsp.py und venv/ enthalten – Details im Tab „Einrichtung“.",
                        "Automatic: ~/NXNative/nxnative. The folder must contain scripts/build_ipa_from_nsp.py and venv/ – see the “Setup” tab for details."))
            }
        }
        .formStyle(.grouped)
    }

    /// Automatic (false) vs. custom folder (true). Choosing "custom" opens the folder picker;
    /// cancelling it keeps the automatic mode.
    private var locationMode: Binding<Bool> {
        Binding(
            get: { !prefs.customRepoPath.isEmpty },
            set: { useCustom in
                if useCustom {
                    // Present the panel after the current view update has finished.
                    DispatchQueue.main.async { chooseRepoFolder() }
                } else if !prefs.customRepoPath.isEmpty {
                    prefs.customRepoPath = ""
                    locationChanged()
                }
            }
        )
    }

    private func chooseRepoFolder() {
        guard let url = FilePanels.chooseFolders(
            multiple: false,
            prompt: tr("Auswählen", "Choose"),
            message: tr("Wähle den nxnative-Ordner (enthält scripts/build_ipa_from_nsp.py).",
                        "Choose the nxnative folder (contains scripts/build_ipa_from_nsp.py).")).first else { return }
        prefs.applyChosenRepoFolder(url)
        locationChanged()
    }

    private func locationChanged() {
        NXNativeLocation.didChange(checker: setupChecker, prefs: prefs, updater: updater, importManager: importManager)
    }
}

struct LibrarySettingsView: View {
    @EnvironmentObject private var library: GameLibraryManager

    var body: some View {
        Form {
            Section {
                if library.customFolders.isEmpty {
                    Text(tr("Keine zusätzlichen Ordner", "No additional folders"))
                        .foregroundStyle(.secondary)
                }
                ForEach(library.customFolders, id: \.self) { folder in
                    removableRow(path: folder, systemImage: "folder") {
                        library.removeCustomFolder(folder)
                    }
                }
                Button(tr("Ordner hinzufügen …", "Add Folder…")) {
                    FilePanels.chooseFolders(multiple: true, prompt: tr("Hinzufügen", "Add"))
                        .forEach { library.addCustomFolder($0.path) }
                }
            } header: {
                Text(tr("Zusätzliche Spiele-Ordner", "Additional Game Folders"))
            } footer: {
                Text(tr("~/NXNative/Games, ~/NXNative und ~/Applications werden immer durchsucht.",
                        "~/NXNative/Games, ~/NXNative and ~/Applications are always scanned."))
            }

            Section(tr("Einzeln hinzugefügte Spiele", "Individually Added Games")) {
                if library.manuallyAddedAppPaths.isEmpty {
                    Text(tr("Keine", "None"))
                        .foregroundStyle(.secondary)
                }
                ForEach(library.manuallyAddedAppPaths, id: \.self) { path in
                    removableRow(path: path, systemImage: "app") {
                        library.removeManualApp(path)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func removableRow(path: String, systemImage: String, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: systemImage)
                .help(path)
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help(tr("Entfernen", "Remove"))
            .accessibilityLabel(tr("\(URL(fileURLWithPath: path).lastPathComponent) entfernen", "Remove \(URL(fileURLWithPath: path).lastPathComponent)"))
        }
    }
}
