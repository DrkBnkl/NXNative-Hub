import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Library ("My Games")

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case appUpdates
    case recompile
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Alle Spiele", "All Games")
        case .appUpdates: return tr("App-Updates", "App Updates")
        case .recompile: return tr("Neukompilierung empfohlen", "Recompile Recommended")
        case .updates: return tr("Alle Updates", "All Updates")
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var gamepad: GamepadManager
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var filter: LibraryFilter = .all
    @State private var gridColumnsCount: Int = 3

    private var filteredGames: [InstalledGame] {
        var list = library.games
        switch filter {
        case .all: break
        case .appUpdates: list = list.filter { $0.updateStatus.isAppUpdateSufficient }
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
        let appUpdates = library.appUpdateAvailableCount
        if recompile > 0 && appUpdates > 0 {
            return tr("\(total) Spiele • \(appUpdates) App-Update(s) • \(recompile) Neukompilierung empfohlen",
                      "\(total) games • \(appUpdates) app update(s) • \(recompile) recompile recommended")
        } else if recompile > 0 {
            return tr("\(total) Spiele • \(recompile) Neukompilierung empfohlen",
                      "\(total) games • \(recompile) recompile recommended")
        } else if appUpdates > 0 {
            return tr("\(total) Spiele • \(appUpdates) App-Update(s) verfügbar",
                      "\(total) games • \(appUpdates) app update(s) available")
        }
        return tr("\(total) Spiele", "\(total) games")
    }

    var body: some View {
        content
            .navigationTitle(SidebarItem.library.title)
            .navigationSubtitle(subtitleText)
            .searchable(text: $searchText, placement: .toolbar, prompt: tr("Spiele durchsuchen", "Search games"))
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) {
                gamepadHUD
            }
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
            .onAppear {
                if router.selectedGameID == nil, let first = filteredGames.first {
                    router.selectedGameID = first.id
                    router.isGamepadSelected = gamepad.isConnected
                }
            }
            .onReceive(gamepad.$isConnected) { connected in
                if connected {
                    router.isGamepadSelected = true
                    if router.selectedGameID == nil, let first = filteredGames.first {
                        router.selectedGameID = first.id
                    }
                }
            }
            .onReceive(gamepad.directionSubject) { direction in
                guard !router.hasActiveSheet else { return }
                handleGamepadDirection(direction)
            }
            .onReceive(gamepad.buttonSubject) { button in
                guard !router.hasActiveSheet else { return }
                handleGamepadButton(button)
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
            ZStack {
                if prefs.libraryViewMode == .list {
                    listView
                } else {
                    gridView
                }
            }
            .overlay {
                if filteredGames.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var listView: some View {
        List(selection: $router.selectedGameID) {
            ForEach(filteredGames) { game in
                GameRowView(game: game,
                            onPlay: { GameActions.launch(game, forceFullscreen: router.isGamepadSelected) },
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
            if let game = findGame(for: ids) { GameActions.launch(game, forceFullscreen: router.isGamepadSelected) }
        }
    }

    private var gridView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 20
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: prefs.coverSize.width, maximum: prefs.coverSize.width + 45), spacing: spacing)],
                        spacing: 24
                    ) {
                        ForEach(filteredGames) { game in
                            GameCoverCardView(
                                game: game,
                                isSelected: router.selectedGameID == game.id,
                                coverWidth: prefs.coverSize.width,
                                onPlay: { GameActions.launch(game, forceFullscreen: router.isGamepadSelected) },
                                onSettings: { openSettings(game) },
                                onShowStatus: { router.statusTargetGame = game }
                            )
                            .id(game.id)
                            .contentShape(RoundedRectangle(cornerRadius: 18))
                            .onTapGesture {
                                router.isGamepadSelected = false
                                router.selectedGameID = game.id
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    GameActions.launch(game, forceFullscreen: router.isGamepadSelected)
                                }
                            )
                            .contextMenu {
                                gameMenuItems(for: game)
                            }
                        }
                    }
                    .padding(20)
                }
                .focusable()
                .onKeyPress(.leftArrow) {
                    handleGamepadDirection(.left)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    handleGamepadDirection(.right)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    handleGamepadDirection(.up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    handleGamepadDirection(.down)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let game = selectedGame {
                        GameActions.launch(game, forceFullscreen: router.isGamepadSelected)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.space) {
                    if let game = selectedGame {
                        openSettings(game)
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: router.selectedGameID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: geo.size.width, initial: true) { _, newWidth in
                let w = max(100, newWidth - 40)
                gridColumnsCount = max(1, Int((w + spacing) / (prefs.coverSize.width + spacing)))
            }
            .onChange(of: prefs.coverSize) { _, newSize in
                let w = max(100, geo.size.width - 40)
                gridColumnsCount = max(1, Int((w + spacing) / (newSize.width + spacing)))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(tr("Noch keine Spiele", "No Games Yet"), systemImage: "gamecontroller")
        } description: {
            Text(tr("Wandle deine Switch-Spiele (.nsp / .xci) und Switch-2-Spiele (.nup / Dump) in native Mac-Apps um oder ziehe eine fertige .app hierher.",
                    "Convert your Switch games (.nsp / .xci) and Switch 2 games (.nup / dump) into native Mac apps, or drag a converted .app here."))
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
            // View Mode Switcher (List vs. Cover Grid)
            Picker(tr("Darstellung", "View Mode"), selection: $prefs.libraryViewMode) {
                Label(tr("Cover", "Cover"), systemImage: "square.grid.2x2").tag(LibraryViewMode.grid)
                Label(tr("Liste", "List"), systemImage: "list.bullet").tag(LibraryViewMode.list)
            }
            .pickerStyle(.segmented)
            .help(tr("Zwischen Cover- und Listenansicht wechseln", "Switch between cover and list view"))

            // Cover size menu when in grid mode
            if prefs.libraryViewMode == .grid {
                Menu {
                    Picker(tr("Cover-Größe", "Cover Size"), selection: $prefs.coverSize) {
                        ForEach(CoverSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                } label: {
                    Label(tr("Größe", "Size"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help(tr("Größe der Cover anpassen", "Adjust cover card size"))
            }

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
                if let game = selectedGame { GameActions.launch(game, forceFullscreen: router.isGamepadSelected) }
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
                library.refreshLibrary(forceRecheck: true)
            } label: {
                Label(tr("Neu laden", "Reload"), systemImage: "arrow.clockwise")
            }
            .disabled(library.isScanning)
            .help(tr("Bibliothek neu laden", "Reload library"))
        }
    }

    @ViewBuilder
    private func gameMenuItems(for game: InstalledGame) -> some View {
        Button(tr("Spielen", "Play")) { GameActions.launch(game, forceFullscreen: router.isGamepadSelected) }
        Button(tr("Spiel-Einstellungen …", "Game Settings…")) { openSettings(game) }
        Button(tr("nxnative-Status & Neukompilierung …", "nxnative Status & Recompilation…")) {
            router.statusTargetGame = game
        }
        if game.updateStatus.isUpdateAvailable {
            Button(game.updateStatus.isAppUpdateSufficient
                   ? tr("App aktualisieren …", "Update App…")
                   : tr("Spiel neu kompilieren …", "Recompile Game…")) {
                router.statusTargetGame = game
            }
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
        let bundleId = GameBundleInfo(appPath: game.path)?.bundleId
        let result = SaveGameImporter.importSaves(from: urls, titleId: game.titleId, bundleId: bundleId)
        let alert = NSAlert()
        if let error = result.errorMessage {
            alert.messageText = tr("Import nicht möglich", "Import Not Possible")
            alert.informativeText = error
            alert.alertStyle = .warning
        } else if result.copiedCount > 0 {
            alert.messageText = tr("Spielstand importiert", "Save Imported")
            var text = tr("\(result.copiedCount) Dateien/Ordner wurden übernommen.", "\(result.copiedCount) files/folders were imported.")
            if let backup = result.backupPath {
                text += "\n" + tr("Der vorherige Spielstand liegt in \((backup as NSString).lastPathComponent).",
                                   "The previous save is in \((backup as NSString).lastPathComponent).")
            }
            if let cloud = result.cloudSavesFolder {
                text += "\n\n" + tr("Achtung: Das Spiel synchronisiert seinen Spielstand mit \(cloud) und könnte beim nächsten Start die Cloud-Kopie verwenden.",
                                      "Note: the game syncs its save with \(cloud) and may use the cloud copy at its next start.")
            }
            alert.informativeText = text
            alert.alertStyle = result.cloudSavesFolder == nil ? .informational : .warning
        } else {
            alert.messageText = tr("Keine Spielstände gefunden", "No Save Data Found")
            alert.informativeText = tr("In der Auswahl wurden keine Speicherdaten gefunden.", "No save data was found in the selection.")
            alert.alertStyle = .warning
        }
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

    // MARK: - Gamepad & Keyboard Navigation

    private func handleGamepadDirection(_ direction: GamepadDirection) {
        guard !filteredGames.isEmpty else { return }

        guard let currentID = router.selectedGameID,
              let currentIndex = filteredGames.firstIndex(where: { $0.id == currentID }) else {
            router.selectedGameID = filteredGames[0].id
            router.isGamepadSelected = true
            return
        }

        let targetIndex: Int
        let columns = max(1, gridColumnsCount)

        switch direction {
        case .left:
            targetIndex = max(0, currentIndex - 1)
        case .right:
            targetIndex = min(filteredGames.count - 1, currentIndex + 1)
        case .up:
            if prefs.libraryViewMode == .list {
                targetIndex = max(0, currentIndex - 1)
            } else {
                targetIndex = max(0, currentIndex - columns)
            }
        case .down:
            if prefs.libraryViewMode == .list {
                targetIndex = min(filteredGames.count - 1, currentIndex + 1)
            } else {
                targetIndex = min(filteredGames.count - 1, currentIndex + columns)
            }
        }

        if targetIndex != currentIndex {
            router.selectedGameID = filteredGames[targetIndex].id
            router.isGamepadSelected = true
        }
    }

    private func handleGamepadButton(_ button: GamepadButton) {
        switch button {
        case .a:
            if let game = selectedGame {
                GameActions.launch(game, forceFullscreen: true)
            } else if let first = filteredGames.first {
                router.selectedGameID = first.id
                router.isGamepadSelected = true
            }
        case .b:
            if !searchText.isEmpty {
                searchText = ""
            }
        case .x:
            if let game = selectedGame {
                openSettings(game)
            }
        case .y:
            if let game = selectedGame {
                router.statusTargetGame = game
            }
        case .leftShoulder:
            if library.updateAvailableCount > 0 {
                cycleFilter(forward: false)
            } else {
                cycleCoverSize(forward: false)
            }
        case .rightShoulder:
            if library.updateAvailableCount > 0 {
                cycleFilter(forward: true)
            } else {
                cycleCoverSize(forward: true)
            }
        case .leftTrigger, .rightTrigger:
            prefs.libraryViewMode = (prefs.libraryViewMode == .grid ? .list : .grid)
        case .menu:
            if let game = selectedGame {
                openSettings(game)
            }
        }
    }

    private func cycleFilter(forward: Bool) {
        let cases = LibraryFilter.allCases
        guard let currentIdx = cases.firstIndex(of: filter) else { return }
        let nextIdx = forward ? (currentIdx + 1) % cases.count : (currentIdx - 1 + cases.count) % cases.count
        filter = cases[nextIdx]
    }

    private func cycleCoverSize(forward: Bool) {
        let sizes = CoverSize.allCases
        guard let idx = sizes.firstIndex(of: prefs.coverSize) else { return }
        let nextIdx = forward ? (idx + 1) % sizes.count : (idx - 1 + sizes.count) % sizes.count
        prefs.coverSize = sizes[nextIdx]
    }

    @ViewBuilder
    private var gamepadHUD: some View {
        if gamepad.isConnected {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(gamepad.controllerName)
                        .font(.caption.weight(.semibold))
                }

                Divider()
                    .frame(height: 12)

                gamepadHintPill(button: "A", label: tr("Spielen (Vollbild)", "Play (Fullscreen)"))
                gamepadHintPill(button: "X", label: tr("Einstellungen", "Settings"))
                gamepadHintPill(button: "Y", label: tr("Status", "Status"))
                if library.updateAvailableCount > 0 {
                    gamepadHintPill(button: "L/R", label: tr("Filter", "Filter"))
                } else {
                    gamepadHintPill(button: "L/R", label: tr("Größe", "Size"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func gamepadHintPill(button: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(button)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.12))
                .clipShape(Capsule())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
