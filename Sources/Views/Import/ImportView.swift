import SwiftUI
import AppKit

// MARK: - Sorting & filtering for NSP/NUP sources

enum PackageSortOrder: String, CaseIterable, Identifiable {
    case nameAsc
    case nameDesc
    case sizeDesc
    case sizeAsc
    case compatibility
    case platform
    case notInstalled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAsc: return tr("Name (A–Z)", "Name (A–Z)")
        case .nameDesc: return tr("Name (Z–A)", "Name (Z–A)")
        case .sizeDesc: return tr("Größe (Größte zuerst)", "Size (Largest First)")
        case .sizeAsc: return tr("Größe (Kleinste zuerst)", "Size (Smallest First)")
        case .compatibility: return tr("Kompatibilität (Unterstützt zuerst)", "Compatibility (Supported First)")
        case .platform: return tr("Plattform (Switch 2 / NUP zuerst)", "Platform (Switch 2 / NUP First)")
        case .notInstalled: return tr("Status (Noch nicht installiert zuerst)", "Status (Not Installed First)")
        }
    }

    var shortTitle: String {
        switch self {
        case .nameAsc: return tr("Name A–Z", "Name A–Z")
        case .nameDesc: return tr("Name Z–A", "Name Z–A")
        case .sizeDesc: return tr("Größe ↓", "Size ↓")
        case .sizeAsc: return tr("Größe ↑", "Size ↑")
        case .compatibility: return tr("Kompatibilität", "Compatibility")
        case .platform: return tr("Plattform", "Platform")
        case .notInstalled: return tr("Nicht installiert", "Not Installed")
        }
    }
}

enum PackageFilter: String, CaseIterable, Identifiable {
    case all
    case supported
    case notInstalled
    case installed
    case switch2
    case switch1
    case updateOrUnsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return tr("Alle Spiele", "All Games")
        case .supported: return tr("Unterstützt", "Supported")
        case .notInstalled: return tr("Noch nicht installiert", "Not Installed")
        case .installed: return tr("Bereits installiert", "Already Installed")
        case .switch2: return "Switch 2 (NUP/NSP)"
        case .switch1: return "Switch 1 (NSP/XCI)"
        case .updateOrUnsupported: return tr("Update / Nicht unterstützt", "Update / Unsupported")
        }
    }
}

// MARK: - NSP/NUP library & batch conversion
//
// Shown as the "NSP/NUP" sidebar section (and inside `ImportSheet`).

struct ImportView: View {
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var buildManager: BuildManager

    @ObservedObject private var iconManager = PackageIconManager.shared
    @AppStorage("nspNupSortOrder") private var sortOrderRaw: String = PackageSortOrder.nameAsc.rawValue
    @State private var filter: PackageFilter = .all
    @State private var searchText = ""
    @State private var showConvertConfirmation = false

    private var sortOrder: PackageSortOrder {
        PackageSortOrder(rawValue: sortOrderRaw) ?? .nameAsc
    }

    private var installedTitleIDs: Set<String> {
        var ids = Set<String>()
        for game in library.games {
            ids.insert(game.titleId.uppercased())
            if let base = SwitchTitleID.baseID(of: game.titleId) {
                ids.insert(base.uppercased())
            }
        }
        return ids
    }

    private func isInstalled(_ item: ImportGameItem, in installed: Set<String>) -> Bool {
        if let base = item.baseTitleId?.uppercased(), installed.contains(base) { return true }
        if let tid = item.titleId?.uppercased(), installed.contains(tid) { return true }
        return false
    }

    private func compatibilityRank(_ status: ImportGameSupportStatus) -> Int {
        switch status {
        case .supported: return 0
        case .updateRequired: return 1
        case .unsupported: return 2
        }
    }

    private var filteredAndSortedGames: [ImportGameItem] {
        let installed = installedTitleIDs
        var list = importManager.pendingGames

        switch filter {
        case .all:
            break
        case .supported:
            list = list.filter { $0.supportStatus.isSupported }
        case .notInstalled:
            list = list.filter { !isInstalled($0, in: installed) }
        case .installed:
            list = list.filter { isInstalled($0, in: installed) }
        case .switch2:
            list = list.filter { $0.isSwitch2 }
        case .switch1:
            list = list.filter { !$0.isSwitch2 }
        case .updateOrUnsupported:
            list = list.filter { !$0.supportStatus.isSupported }
        }

        if !searchText.isEmpty {
            list = list.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
                    || (item.baseTitleId?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (item.titleId?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || item.fileNames.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        let nameAsc: (ImportGameItem, ImportGameItem) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        switch sortOrder {
        case .nameAsc:
            return list.sorted(by: nameAsc)
        case .nameDesc:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .sizeDesc:
            return list.sorted { lhs, rhs in
                lhs.totalSizeBytes != rhs.totalSizeBytes ? lhs.totalSizeBytes > rhs.totalSizeBytes : nameAsc(lhs, rhs)
            }
        case .sizeAsc:
            return list.sorted { lhs, rhs in
                lhs.totalSizeBytes != rhs.totalSizeBytes ? lhs.totalSizeBytes < rhs.totalSizeBytes : nameAsc(lhs, rhs)
            }
        case .compatibility:
            return list.sorted { lhs, rhs in
                let r1 = compatibilityRank(lhs.supportStatus)
                let r2 = compatibilityRank(rhs.supportStatus)
                return r1 != r2 ? r1 < r2 : nameAsc(lhs, rhs)
            }
        case .platform:
            return list.sorted { lhs, rhs in
                lhs.isSwitch2 != rhs.isSwitch2 ? lhs.isSwitch2 : nameAsc(lhs, rhs)
            }
        case .notInstalled:
            return list.sorted { lhs, rhs in
                let i1 = isInstalled(lhs, in: installed)
                let i2 = isInstalled(rhs, in: installed)
                return i1 != i2 ? !i1 : nameAsc(lhs, rhs)
            }
        }
    }

    private var subtitleText: String {
        let source = importManager.activeSourceDisplayPath
        guard !importManager.pendingGames.isEmpty else { return source }
        let total = importManager.pendingGames.count
        let supported = importManager.supportedCount
        return "\(source) · \(tr("\(total) Spiele • \(supported) unterstützt", "\(total) games • \(supported) supported"))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !importManager.isConverting && !importManager.isFinished {
                sourceBar
                Divider()
            }
            content
        }
            .navigationTitle(SidebarItem.packages.title)
            .navigationSubtitle(subtitleText)
            .searchable(text: $searchText, placement: .toolbar, prompt: tr("NSP/NUP durchsuchen", "Search NSP/NUP"))
            .onAppear {
                importManager.refreshExternalVolumes()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !importManager.isConverting && !importManager.isFinished && !importManager.pendingGames.isEmpty {
                        Menu {
                            ForEach(PackageFilter.allCases) { option in
                                Button {
                                    filter = option
                                } label: {
                                    if filter == option {
                                        Label(option.title, systemImage: "checkmark")
                                    } else {
                                        Text(option.title)
                                    }
                                }
                            }
                        } label: {
                            Label(
                                filter == .all ? tr("Filter", "Filter") : filter.title,
                                systemImage: filter == .all
                                    ? "line.3.horizontal.decrease.circle"
                                    : "line.3.horizontal.decrease.circle.fill"
                            )
                        }
                        .help(tr("Spiele filtern", "Filter games"))

                        Menu {
                            ForEach(PackageSortOrder.allCases) { option in
                                Button {
                                    sortOrderRaw = option.rawValue
                                } label: {
                                    if sortOrder == option {
                                        Label(option.title, systemImage: "checkmark")
                                    } else {
                                        Text(option.title)
                                    }
                                }
                            }
                        } label: {
                            Label(sortOrder.shortTitle, systemImage: "arrow.up.arrow.down")
                        }
                        .help(tr("Spiele sortieren", "Sort games"))
                    }

                    Button {
                        importManager.openImportFolderInFinder()
                    } label: {
                        Label(tr("Im Finder öffnen", "Open in Finder"), systemImage: "folder")
                    }
                    .disabled(importManager.isReadOnlySource && !importManager.activeSourceExists)
                    .help(tr("Import-Ordner im Finder öffnen", "Open the Import folder in Finder"))

                    refreshButton
                }
            }
            .confirmationDialog(tr("\(importManager.selectedCount) Spiele umwandeln?", "Convert \(importManager.selectedCount) games?"),
                                isPresented: $showConvertConfirmation,
                                titleVisibility: .visible) {
                Button(tr("Umwandeln", "Convert")) { startConversion() }
                Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    private var confirmationMessage: String {
        if importManager.isReadOnlySource {
            return tr("Erfolgreich umgewandelte Spiele werden nach ~/NXNative/Games gespeichert. Alle Dateien auf dem externen Medium bleiben vollständig unverändert (schreibgeschützt).",
                      "Successfully converted games are saved to ~/NXNative/Games. All files on the external volume remain completely untouched (read-only).")
        }
        return importManager.trashSourcesAfterConversion
            ? tr("Erfolgreich umgewandelte Spiele werden nach ~/NXNative/Games verschoben. Ihre Quelldateien im Import-Ordner werden danach in den Papierkorb gelegt.",
                 "Successfully converted games are moved to ~/NXNative/Games. Their source files in the Import folder are then moved to the Trash.")
            : tr("Erfolgreich umgewandelte Spiele werden nach ~/NXNative/Games verschoben. Ihre Quelldateien bleiben im Import-Ordner.",
                 "Successfully converted games are moved to ~/NXNative/Games. Their source files stay in the Import folder.")
    }

    // MARK: Import source bar

    private var sourceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: importManager.isReadOnlySource ? "externaldrive.fill" : "folder")
                .foregroundStyle(importManager.isReadOnlySource ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(tr("Import-Quelle", "Import Source"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if importManager.isReadOnlySource {
                        Label(tr("Schreibgeschützt", "Read-only"), systemImage: "lock.shield.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .help(tr("Dateien auf dem externen Medium werden niemals verändert, verschoben oder gelöscht.",
                                     "Files on the external volume are never modified, moved, or deleted."))
                    }
                }
                Text(importManager.activeSourceDisplayPath)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(importManager.activeSourceDisplayPath)
            }

            Spacer()

            Menu {
                Button {
                    importManager.setImportSource(nil)
                } label: {
                    Label(tr("Standard (~/NXNative/Import)", "Default (~/NXNative/Import)"),
                          systemImage: importManager.isReadOnlySource ? "folder" : "checkmark")
                }

                if !importManager.mountedExternalVolumes.isEmpty {
                    Divider()
                    Section(tr("Externe Laufwerke / USB-Sticks (schreibgeschützt)", "External Drives / USB Sticks (Read-Only)")) {
                        ForEach(importManager.mountedExternalVolumes, id: \.self) { volume in
                            let isSelected = importManager.customImportFolderURL?.standardizedFileURL == volume.standardizedFileURL
                            Button {
                                importManager.setImportSource(volume)
                            } label: {
                                Label(volume.lastPathComponent,
                                      systemImage: isSelected ? "checkmark" : "externaldrive.fill")
                            }
                        }
                    }
                }

                Divider()
                Button {
                    chooseExternalImportFolder()
                } label: {
                    Label(tr("USB-Stick oder Ordner wählen …", "Choose USB Drive or Folder…"),
                          systemImage: "folder.badge.plus")
                }
            } label: {
                Label(tr("Quelle wählen", "Choose Source"), systemImage: "externaldrive.badge.plus")
            }
            .disabled(importManager.isScanning || importManager.isConverting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func chooseExternalImportFolder() {
        importManager.refreshExternalVolumes()
        guard let url = FilePanels.chooseFolders(
            multiple: false,
            prompt: tr("Auswählen", "Choose"),
            message: tr("Wähle einen USB-Stick oder Ordner mit .nsp- / .nup-Dateien (wird ausschließlich schreibgeschützt eingelesen).",
                        "Choose a USB drive or folder containing .nsp / .nup files (opened strictly read-only).")
        ).first else { return }
        importManager.setImportSource(url)
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

    @ViewBuilder
    private var emptyView: some View {
        if importManager.isReadOnlySource && !importManager.activeSourceExists {
            ContentUnavailableView {
                Label(tr("Externes Medium nicht verbunden", "External Volume Not Connected"), systemImage: "externaldrive.badge.xmark")
            } description: {
                Text(tr("Der gewählte Pfad „\(importManager.activeSourceDisplayPath)“ ist derzeit nicht erreichbar. Verbinde den USB-Stick erneut oder wähle eine andere Quelle.",
                        "The selected path “\(importManager.activeSourceDisplayPath)” is currently unavailable. Reconnect the USB drive or choose another source."))
            } actions: {
                Button(tr("USB-Stick / Ordner wählen …", "Choose USB Drive / Folder…")) {
                    chooseExternalImportFolder()
                }
                Button(tr("Standard-Ordner verwenden", "Use Default Folder")) {
                    importManager.setImportSource(nil)
                }
                refreshButton
            }
        } else if importManager.isReadOnlySource {
            ContentUnavailableView {
                Label(tr("Keine Spiele gefunden", "No Games Found"), systemImage: "externaldrive")
            } description: {
                Text(tr("Unter „\(importManager.activeSourceDisplayPath)“ wurden keine .nsp-, .xci- oder .nup-Dateien gefunden. Das Medium wird ausschließlich schreibgeschützt eingelesen.",
                        "No .nsp, .xci, or .nup files were found at “\(importManager.activeSourceDisplayPath)”. The volume is accessed strictly read-only."))
            } actions: {
                Button(tr("Andere Quelle wählen …", "Choose Another Source…")) {
                    chooseExternalImportFolder()
                }
                Button(tr("Standard-Ordner verwenden", "Use Default Folder")) {
                    importManager.setImportSource(nil)
                }
                refreshButton
            }
        } else {
            ContentUnavailableView {
                Label(tr("Import-Ordner ist leer", "Import Folder Is Empty"), systemImage: "tray")
            } description: {
                Text(tr("Lege Switch-Spiele (Ordner mit .nsp / .xci) oder Switch-2-Spiele (.nup-Datei oder Dump-Ordner) in ~/NXNative/Import ab – oder wähle direkt einen externen USB-Stick (schreibgeschützt).",
                        "Place Switch games (folders with .nsp / .xci) or Switch 2 games (a .nup file or dump folder) in ~/NXNative/Import – or point directly to an external USB drive (read-only)."))
            } actions: {
                Button(tr("USB-Stick / Ordner wählen …", "Choose USB Drive / Folder…")) {
                    chooseExternalImportFolder()
                }
                .buttonStyle(.borderedProminent)
                Button(tr("Import-Ordner öffnen", "Open Import Folder")) {
                    importManager.openImportFolderInFinder()
                }
                refreshButton
            }
        }
    }

    // MARK: Refresh

    /// Rescans ~/NXNative/Import, e.g. after files were added or removed in Finder.
    private var refreshButton: some View {
        Button {
            importManager.scanImportFolder()
        } label: {
            Label(tr("Aktualisieren", "Refresh"), systemImage: "arrow.clockwise")
        }
        .disabled(importManager.isScanning || importManager.isConverting)
        .help(tr("Import-Ordner neu einlesen", "Rescan the Import folder"))
    }

    // MARK: Pending games

    private var pendingView: some View {
        let visibleGames = filteredAndSortedGames
        let installed = installedTitleIDs

        return VStack(spacing: 0) {
            if visibleGames.isEmpty {
                ContentUnavailableView {
                    Label(tr("Keine passenden Spiele", "No Matching Games"), systemImage: "magnifyingglass")
                } description: {
                    Text(tr("Für die aktuelle Suche oder den gewählten Filter wurden keine Spiele gefunden.",
                            "No games match the current search or filter."))
                } actions: {
                    Button(tr("Filter & Suche zurücksetzen", "Reset Filter & Search")) {
                        filter = .all
                        searchText = ""
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(visibleGames) { game in
                            ImportGameRow(
                                game: game,
                                icon: iconManager.icon(for: game),
                                isInstalled: isInstalled(game, in: installed)
                            ) { isOn in
                                importManager.setSelection(for: game.id, to: isOn)
                            }
                            .onAppear {
                                iconManager.loadIconIfNeeded(for: game, installedGames: library.games)
                            }
                            .contextMenu { ImportGameContextMenu(game: game) }
                        }
                    } header: {
                        HStack {
                            if visibleGames.count != importManager.pendingGames.count {
                                Text(tr("\(visibleGames.count) von \(importManager.pendingGames.count) angezeigt",
                                        "Showing \(visibleGames.count) of \(importManager.pendingGames.count)"))
                                Text("·")
                            }
                            Text(tr("\(importManager.supportedCount) unterstützt", "\(importManager.supportedCount) supported"))
                            if importManager.unsupportedCount > 0 {
                                Text("·")
                                Text(tr("\(importManager.unsupportedCount) ohne Profil oder Update", "\(importManager.unsupportedCount) without profile or update"))
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            refreshButton
                                .buttonStyle(.borderless)
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
            }

            Divider()

            if importManager.isReadOnlySource {
                Label(tr("Schreibgeschützter Modus: Dateien auf dem externen Medium werden niemals verändert oder gelöscht.",
                         "Read-only mode: files on the external volume are never modified or deleted."),
                      systemImage: "lock.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .background(.bar)
            } else {
                Toggle(tr("Quelldateien nach erfolgreicher Umwandlung in den Papierkorb legen",
                          "Move source files to the Trash after a successful conversion"),
                       isOn: $importManager.trashSourcesAfterConversion)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .background(.bar)
            }

            HStack(spacing: 12) {
                if importManager.selectionNeedsProdKeys && !prefs.prodKeysExists {
                    Label(tr("prod.keys fehlt – bitte in den Einstellungen festlegen (Switch-2-Spiele brauchen keine).", "prod.keys missing – please set it in Settings (Switch 2 games need none)."),
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
                .disabled(importManager.selectedCount == 0 || (importManager.selectionNeedsProdKeys && !prefs.prodKeysExists) || buildManager.isRunning)
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
                    library.refreshLibrary(forceRecheck: true)
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
            library.refreshLibrary(forceRecheck: true)
        }
    }
}

// MARK: - Context menu for an import candidate

struct ImportGameContextMenu: View {
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var buildManager: BuildManager
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    let game: ImportGameItem

    /// No folder is trashed while any build runs (batch, single build or one started in Terminal):
    /// it may be reading this folder or writing into it.
    private var buildIsRunning: Bool {
        importManager.isConverting || buildManager.isRunning || buildMonitor.activeBuild != nil
    }

    var body: some View {
        Button(tr("Im Finder zeigen", "Show in Finder")) {
            importManager.revealInFinder(game)
        }
        if !game.isReadOnly && !importManager.isReadOnlySource {
            Divider()
            Button(tr("In den Papierkorb legen …", "Move to Trash…"), role: .destructive) {
                confirmMoveToTrash()
            }
            .disabled(buildIsRunning)
        }
    }

    private func confirmMoveToTrash() {
        let alert = NSAlert()
        alert.messageText = tr("„\(game.folderURL.lastPathComponent)“ in den Papierkorb legen?",
                               "Move “\(game.folderURL.lastPathComponent)” to the Trash?")
        alert.informativeText = tr("Der ganze Ordner mit den Spieldateien und einem begonnenen Build wird in den Papierkorb gelegt.",
                                   "The whole folder with the game files and any build in progress is moved to the Trash.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: tr("In den Papierkorb legen", "Move to Trash"))
        alert.addButton(withTitle: tr("Abbrechen", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, !buildIsRunning else { return }
        importManager.moveToTrash(game)
    }
}

// MARK: - Row for an import candidate

struct ImportGameRow: View {
    let game: ImportGameItem
    var icon: NSImage? = nil
    var isInstalled: Bool = false
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(get: { game.isSelected }, set: onToggle)) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(game.name)

            iconView

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(game.name)
                        .font(.headline)
                    if game.isSwitch2 {
                        BadgeView(text: "Switch 2", color: .red)
                    }
                    if isInstalled {
                        BadgeView(text: tr("Installiert", "Installed"), systemImage: "checkmark.circle.fill", color: .blue)
                    }
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
                    Text(game.sourceDescription)
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

    private var isNupSource: Bool {
        if case .nup = game.source { return true }
        return false
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((game.isSwitch2 ? Color.red : Color.accentColor).opacity(0.12))
                Image(systemName: isNupSource ? "shippingbox.fill" : "gamecontroller.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(game.isSwitch2 ? Color.red.opacity(0.75) : Color.accentColor.opacity(0.75))
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
