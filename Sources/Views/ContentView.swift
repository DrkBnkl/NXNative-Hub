import SwiftUI

// MARK: - Main window
//
// HIG layout: NavigationSplitView with sidebar + detail, actions in the window toolbar.

struct ContentView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var updater: UpdateManager
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var buildManager: BuildManager
    @EnvironmentObject private var builderForm: BuilderFormModel
    @EnvironmentObject private var gameSettings: GameSettingsModel
    @EnvironmentObject private var setupChecker: SetupChecker
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let build = buildMonitor.activeBuild {
                        ActiveBuildBanner(
                            build: build,
                            stageOverride: (importManager.isConverting && !importManager.currentStageText.isEmpty)
                                ? importManager.currentStageText : nil,
                            onShowLog: { router.showingLiveLog = true }
                        )
                    }
                }
        }
        .frame(minWidth: 760, minHeight: 500)
        // Forces all texts to be rebuilt when the UI language changes.
        .id(lang.currentChoice)
        .onAppear {
            prefs.autoDetectKeysIfNeeded()
            // Show the setup sheet once per launch, only if something required is missing.
            if !setupChecker.hasRun {
                setupChecker.run(prodKeysExists: prefs.prodKeysExists) {
                    if setupChecker.hasBlockingIssues { router.showingSetup = true }
                }
            }
            updater.checkForUpdates(silent: true)
            library.refreshLibrary()
            importManager.scanImportFolder()
        }
        .sheet(isPresented: $router.showingGameSettings) {
            withEnvironment(GameSettingsSheet())
        }
        .sheet(isPresented: $router.showingUpdateSheet) {
            withEnvironment(UpdateSheet())
        }
        .sheet(isPresented: $router.showingLiveLog) {
            withEnvironment(LiveLogSheet())
        }
        .sheet(isPresented: $router.showingImportSheet) {
            withEnvironment(ImportSheet())
        }
        .sheet(isPresented: $router.showingSetup) {
            withEnvironment(SetupSheet())
        }
    }

    /// Passes all state objects to sheets explicitly (independent of whether the
    /// running macOS version propagates the environment into sheets).
    private func withEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .environmentObject(router)
            .environmentObject(prefs)
            .environmentObject(library)
            .environmentObject(buildManager)
            .environmentObject(builderForm)
            .environmentObject(updater)
            .environmentObject(gameSettings)
            .environmentObject(buildMonitor)
            .environmentObject(importManager)
            .environmentObject(setupChecker)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection ?? .library {
        case .library: LibraryView()
        case .builder: BuilderView()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var importManager: ImportBatchManager
    @EnvironmentObject private var updater: UpdateManager
    @EnvironmentObject private var setupChecker: SetupChecker

    var body: some View {
        List(selection: $router.selection) {
            Section(tr("Mediathek", "Library")) {
                Label(SidebarItem.library.title, systemImage: SidebarItem.library.systemImage)
                    .badge(library.games.count)
                    .tag(SidebarItem.library)
            }

            Section(tr("Erstellen", "Create")) {
                Label(SidebarItem.builder.title, systemImage: SidebarItem.builder.systemImage)
                    .badge(importManager.pendingCount > 0 ? "\(importManager.pendingCount)" : nil)
                    .tag(SidebarItem.builder)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if setupChecker.hasBlockingIssues {
                    setupFooter
                }
                updateFooter
            }
        }
    }

    /// Visible only while required prerequisites are missing.
    private var setupFooter: some View {
        Button {
            router.showingSetup = true
        } label: {
            Label(tr("Einrichtung unvollständig", "Setup incomplete"), systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .help(tr("Zeigt, was zum Bauen von Spielen noch fehlt", "Shows what is still missing to build games"))
    }

    /// nxnative version / update status at the bottom of the sidebar.
    private var updateFooter: some View {
        Button {
            router.showingUpdateSheet = true
            updater.checkForUpdates()
        } label: {
            HStack(spacing: 6) {
                if updater.isChecking || updater.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: updater.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle")
                        .foregroundStyle(updater.updateAvailable ? Color.orange : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(updater.updateAvailable
                         ? tr("Update verfügbar (\(updater.pendingCommitsCount))", "Update available (\(updater.pendingCommitsCount))")
                         : "nxnative")
                        .font(.callout)
                    if !updater.currentCommitHash.isEmpty {
                        Text(updater.currentCommitHash)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(tr("Nach nxnative-Updates und neuen Spielprofilen suchen", "Check for nxnative updates and new game profiles"))
    }
}
