import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Library ("My Games")

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case recompile
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Alle Spiele", "All Games")
        case .recompile: return tr("Neukompilierung empfohlen", "Recompile Recommended")
        case .updates: return tr("Updates verfügbar", "Updates Available")
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var filter: LibraryFilter = .all

    private var filteredGames: [InstalledGame] {
        var list = library.games
        switch filter {
        case .all: break
        case .recompile: list = list.filter { $0.updateStatus.isRecompileRecommended }
        case .updates: list = list.filter { $0.updateStatus.isUpdateAvailable }
        }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.titleId.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedGame: InstalledGame? {
        library.games.first { $0.id == router.selectedGameID }
    }

    private var subtitleText: String {
        guard !library.games.isEmpty else { return "" }
        let total = library.games.count
        let recompile = library.recompileRecommendedCount
        if recompile > 0 {
            return tr("\(total) Spiele • \(recompile) Neukompilierung empfohlen",
                      "\(total) games • \(recompile) recompile recommended")
        }
        return tr("\(total) Spiele", "\(total) games")
    }

    var body: some View {
        content
            .navigationTitle(SidebarItem.library.title)
            .navigationSubtitle(subtitleText)
            .searchable(text: $searchText, placement: .toolbar, prompt: tr("Spiele durchsuchen", "Search games"))
            .toolbar { toolbarContent }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.08))
                        .overlay {
                            Label(tr("Spiel (.app) oder Ordner hier ablegen", "Drop game (.app) or folder here"),
                                  systemImage: "plus.app")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if library.games.isEmpty {
            if library.isScanning {
                ProgressView(tr("Bibliothek wird geladen …", "Loading library…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        } else {
            List(selection: $router.selectedGameID) {
                ForEach(filteredGames) { game in
                    GameRowView(game: game,
                                onPlay: { GameActions.launch(game) },
                                onSettings: { openSettings(game) },
                                onShowStatus: { router.statusTargetGame = game })
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: InstalledGame.ID.self) { ids in
                if let game = findGame(for: ids) {
                    gameMenuItems(for: game)
                }
            } primaryAction: { ids in
                // Double-click / Return launches the game (standard macOS list behavior)
                if let game = findGame(for: ids) { GameActions.launch(game) }
            }
            .overlay {
                if filteredGames.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(tr("Noch keine Spiele", "No Games Yet"), systemImage: "gamecontroller")
        } description: {
            Text(tr("Wandle deine Switch-Spiele (.nsp / .xci) in native Mac-Apps um oder ziehe eine fertige .app hierher.",
                    "Convert your Switch games (.nsp / .xci) into native Mac apps, or drag a converted .app here."))
        } actions: {
            Button(tr("Spiel bauen", "Build Game")) {
                router.selection = .builder
            }
            .buttonStyle(.borderedProminent)
            Button(tr("Spiel hinzufügen …", "Add Game…")) {
                addApplications()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if library.updateAvailableCount > 0 {
                Picker(tr("Filter", "Filter"), selection: $filter) {
                    ForEach(LibraryFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .help(tr("Spiele nach Aktualisierungs- und Neukompilierungs-Status filtern",
                         "Filter games by update and recompilation status"))
            }

            Button {
                if let game = selectedGame { GameActions.launch(game) }
            } label: {
                Label(tr("Spielen", "Play"), systemImage: "play.fill")
            }
            .disabled(selectedGame == nil)
            .help(tr("Ausgewähltes Spiel starten", "Launch the selected game"))

            Button {
                if let game = selectedGame { openSettings(game) }
            } label: {
                Label(tr("Spiel-Einstellungen", "Game Settings"), systemImage: "slider.horizontal.3")
            }
            .disabled(selectedGame == nil)
            .help(tr("FPS, Konsolenmodus, MetalFX und Spielstände des ausgewählten Spiels", "FPS, console mode, MetalFX and saves of the selected game"))

            Menu {
                Button(tr("Spiel (.app) hinzufügen …", "Add Game (.app)…"), action: addApplications)
                Button(tr("Spiele-Ordner hinzufügen …", "Add Games Folder…"), action: addFolders)
            } label: {
                Label(tr("Hinzufügen", "Add"), systemImage: "plus")
            }
            .help(tr("Spiele oder Ordner zur Bibliothek hinzufügen", "Add games or folders to the library"))

            Button {
                library.refreshLibrary()
            } label: {
                Label(tr("Neu laden", "Reload"), systemImage: "arrow.clockwise")
            }
            .disabled(library.isScanning)
            .help(tr("Bibliothek neu laden", "Reload library"))
        }
    }

    @ViewBuilder
    private func gameMenuItems(for game: InstalledGame) -> some View {
        Button(tr("Spielen", "Play")) { GameActions.launch(game) }
        Button(tr("Spiel-Einstellungen …", "Game Settings…")) { openSettings(game) }
        Button(tr("nxnative-Status & Neukompilierung …", "nxnative Status & Recompilation…")) {
            router.statusTargetGame = game
        }
        Divider()
        Button(tr("Spielstand importieren …", "Import Save…")) { importSave(for: game) }
        Button(tr("Spielstand-Ordner öffnen", "Open Save Folder")) { SaveGameImporter.openSaveFolder(titleId: game.titleId) }
        Divider()
        Button(tr("Spiel-Protokoll öffnen", "Open Game Log")) { FilePanels.openInFinder(game.logPath) }
            .disabled(!GameDiagnostics.hasLog(game))
        Button(tr("Protokoll des vorherigen Starts öffnen", "Open Log of Previous Launch")) { FilePanels.openInFinder(game.previousLogPath) }
            .disabled(!GameDiagnostics.hasPreviousLog(game))
        Button(tr("Fehlerbericht erstellen …", "Create Bug Report…")) { createBugReport(for: game) }
        Divider()
        Button(tr("Im Finder zeigen", "Show in Finder")) { FilePanels.revealInFinder(game.path) }
    }

    // MARK: Actions

    private func findGame(for ids: Set<InstalledGame.ID>) -> InstalledGame? {
        guard let id = ids.first else { return nil }
        return library.games.first { $0.id == id }
    }

    private func openSettings(_ game: InstalledGame) {
        GameActions.openSettings(appPath: game.path, settings: gameSettings, router: router)
    }

    private func importSave(for game: InstalledGame) {
        let urls = FilePanels.chooseSaveSources()
        guard !urls.isEmpty else { return }
        let result = SaveGameImporter.importSaves(from: urls, titleId: game.titleId)
        let alert = NSAlert()
        alert.messageText = result.copiedCount > 0
            ? tr("Spielstand importiert", "Save Imported")
            : tr("Keine Spielstände gefunden", "No Save Data Found")
        alert.informativeText = result.copiedCount > 0
            ? tr("\(result.copiedCount) Dateien/Ordner wurden übernommen.", "\(result.copiedCount) files/folders were imported.")
                + (result.backupPath != nil ? "\n" + tr("Der vorherige Spielstand wurde gesichert.", "The previous save was backed up.") : "")
            : tr("In der Auswahl wurden keine Speicherdaten gefunden.", "No save data was found in the selection.")
        alert.alertStyle = result.copiedCount > 0 ? .informational : .warning
        alert.runModal()
    }

    private func createBugReport(for game: InstalledGame) {
        GameDiagnostics.createBugReport(for: game) { result in
            let alert = NSAlert()
            switch result {
            case let .created(path):
                alert.messageText = tr("Fehlerbericht erstellt", "Bug Report Created")
                alert.informativeText = tr("Die ZIP-Datei enthält Protokolle und Build-Informationen, aber keine Spieldaten oder Schlüssel. Hänge sie an ein Issue bei nxnative an.",
                                           "The zip file contains logs and build information, but no game data or keys. Attach it to an issue at nxnative.")
                alert.alertStyle = .informational
                FilePanels.revealInFinder(path)
            case let .failed(message):
                alert.messageText = tr("Fehlerbericht konnte nicht erstellt werden", "Could Not Create Bug Report")
                alert.informativeText = message
                alert.alertStyle = .warning
            }
            alert.runModal()
        }
    }

    private func addApplications() {
        FilePanels.chooseApplications().forEach { library.addManualApp($0.path) }
    }

    private func addFolders() {
        FilePanels.chooseFolders(multiple: true, prompt: tr("Hinzufügen", "Add"),
                                 message: tr("Ordner werden beim Laden der Bibliothek nach Spielen durchsucht.",
                                             "Folders are scanned for games when the library is loaded."))
            .forEach { library.addCustomFolder($0.path) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async { library.addDroppedItem(url) }
            }
        }
        return true
    }
}
