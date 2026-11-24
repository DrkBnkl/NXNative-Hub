import SwiftUI
import AppKit

// MARK: - Game update & recompilation status sheet

struct GameStatusSheet: View {
    private let initialGame: InstalledGame
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var builderForm: BuilderFormModel
    @EnvironmentObject private var buildManager: BuildManager
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var updater: UpdateManager

    @State private var buildFolderURL: URL?
    @State private var buildFolderSizeText: String?
    @State private var didTrashBuildFolder = false

    init(game: InstalledGame) {
        self.initialGame = game
    }

    private var game: InstalledGame {
        library.games.first(where: { $0.id == initialGame.id }) ?? initialGame
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusBanner

                    comparisonSection

                    if let folder = buildFolderURL, !didTrashBuildFolder {
                        buildFolderCleanupCard(folder)
                    } else if didTrashBuildFolder {
                        trashedSuccessBadge
                    }

                    if !game.updateStatus.commitTitles.isEmpty {
                        profileCommitsSection
                    }
                }
                .padding(20)
            }

            Divider()

            bottomBar
        }
        .frame(width: 560, height: 530)
        .onAppear {
            updater.fetchLocalCommitInfo()
            checkForBuildFolder()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: game.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(game.titleId)
                        .font(.caption.monospaced())
                    Text("·")
                    Text("v\(game.version)")
                    Text("·")
                    Text(game.sizeFormatted)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: Status Banner

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: game.updateStatus.statusIcon)
                    .font(.system(size: 26))
                    .foregroundStyle(game.updateStatus.statusColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.updateStatus.statusTitle)
                        .font(.headline)
                        .foregroundStyle(game.updateStatus.statusColor)

                    Text(game.updateStatus.tooltip)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
            }

            if game.updateStatus.isAppUpdateSufficient {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.blue)
                    Text(tr("Shader sind aktuell. Ein schnelles App-Update aktualisiert die Host-App und Spieleinstellungen in wenigen Sekunden (keine Shader-Neukompilierung nötig).",
                            "Shaders are up to date. A quick app update updates the host app and settings in seconds (no shader recompilation needed)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            } else if game.updateStatus.requiresShaderRecompile {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.orange)
                    Text(tr("Shader müssen neu kompiliert werden, da sich die Shader-Chain oder Shader-Definitionen geändert haben. Das dauert je nach Spiel einige Minuten.",
                            "Shaders must be recompiled because the shader chain or shader definitions have changed. Depending on the game, this takes a few minutes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(game.updateStatus.statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(game.updateStatus.statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Comparison Section

    private var comparisonSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Text(tr("Eigenschaft", "Property"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tr("Spiel-Build", "Game Build"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .trailing)
                    Text(tr("Aktuelles nxnative", "Current nxnative"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .trailing)
                }

                Divider()

                comparisonRow(
                    label: tr("nxnative-Commit", "nxnative Commit"),
                    buildValue: game.buildCommit ?? tr("Älterer Build", "Older build"),
                    repoValue: updater.currentCommitHash.isEmpty ? "–" : updater.currentCommitHash,
                    isMismatch: !GameUpdateChecker.commitsMatch(game.buildCommit, updater.currentCommitHash)
                )

                comparisonRow(
                    label: tr("Shader-Chain", "Shader Chain"),
                    buildValue: game.shaderChain.map { "b-\($0)" } ?? "–",
                    repoValue: currentRepoChain.map { "b-\($0)" } ?? "–",
                    isMismatch: game.shaderChain != currentRepoChain
                )

                HStack {
                    Text(tr("Shader-Status", "Shader Status"))
                        .font(.callout)
                    Spacer()
                    if game.updateStatus.requiresShaderRecompile {
                        Text(tr("Neukompilierung erforderlich", "Recompile Required"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.orange)
                    } else if game.updateStatus.isAppUpdateSufficient {
                        Text(tr("Aktuell (App-Update reicht)", "Up to Date (App Update Sufficient)"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.green)
                    } else {
                        Text(tr("Aktuell", "Up to Date"))
                            .font(.callout)
                            .foregroundStyle(Color.green)
                    }
                }

                HStack {
                    Text(tr("Build-Datum", "Build Date"))
                        .font(.callout)
                    Spacer()
                    Text(game.mtime.formatted(date: .abbreviated, time: .shortened))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Text(tr("Vergleich Build vs. nxnative", "Comparison: Build vs. nxnative"))
        }
    }

    private func comparisonRow(label: String, buildValue: String, repoValue: String, isMismatch: Bool) -> some View {
        HStack {
            Text(label)
                .font(.callout)
            Spacer()
            Text(buildValue)
                .font(.callout.monospaced())
                .foregroundStyle(isMismatch ? Color.orange : Color.primary)
                .frame(width: 140, alignment: .trailing)
            Text(repoValue)
                .font(.callout.monospaced())
                .foregroundStyle(isMismatch ? Color.green : Color.primary)
                .frame(width: 140, alignment: .trailing)
        }
    }

    private var currentRepoChain: String? {
        let chainHeaderPath = (NXPaths.repoPath as NSString).appendingPathComponent("dm/gfx/nvn/dmsh_chain.h")
        guard let content = try? String(contentsOfFile: chainHeaderPath, encoding: .utf8),
              let match = content.range(of: #"DMSH_CHAIN\s+"([0-9a-fA-F]+)""#, options: .regularExpression) else {
            return nil
        }
        let matchedStr = String(content[match])
        guard let quote1 = matchedStr.firstIndex(of: "\""),
              let quote2 = matchedStr.lastIndex(of: "\""),
              quote1 < quote2 else { return nil }
        let start = matchedStr.index(after: quote1)
        return String(matchedStr[start..<quote2])
    }

    // MARK: Profile Commits Section

    private var profileCommitsSection: some View {
        GroupBox {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(game.updateStatus.commitTitles, id: \.self) { commit in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(commit)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 120)
        } label: {
            Text(tr("Änderungen am Spielprofil (dm/games/\(game.titleId))",
                    "Game profile changes (dm/games/\(game.titleId))"))
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button(tr("Im Finder zeigen", "Show in Finder")) {
                FilePanels.revealInFinder(game.path)
            }

            Spacer()

            Button(tr("Schließen", "Close")) {
                router.statusTargetGame = nil
            }
            .keyboardShortcut(.cancelAction)

            if game.updateStatus.isUpdateAvailable {
                Button(tr("Im Builder anpassen …", "Customize in Builder…")) {
                    openInBuilder()
                }
                .buttonStyle(.bordered)

                Button(action: performUpdate) {
                    Label(
                        game.updateStatus.isAppUpdateSufficient
                            ? tr("App jetzt aktualisieren", "Update App Now")
                            : tr("Jetzt neu kompilieren", "Recompile Now"),
                        systemImage: game.updateStatus.isAppUpdateSufficient
                            ? "arrow.up.circle.fill"
                            : "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(tr("Im Builder öffnen", "Open in Builder")) {
                    openInBuilder()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private func performUpdate() {
        GameUpdateAction.performUpdate(
            for: game,
            router: router,
            builderForm: builderForm,
            buildManager: buildManager,
            buildMonitor: buildMonitor,
            prefs: prefs,
            library: library
        )
    }

    private func openInBuilder() {
        if let source = GameSourceLocator.findSourceDirectory(for: game) {
            builderForm.setSource(from: URL(fileURLWithPath: source))
        }
        router.statusTargetGame = nil
        router.selection = .builder
    }

    // MARK: Build Folder Cleanup

    @ViewBuilder
    private func buildFolderCleanupCard(_ folder: URL) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "externaldrive.badge.minus")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Build-Cache belegt \(buildFolderSizeText ?? "…")",
                            "Build cache occupies \(buildFolderSizeText ?? "…")"))
                        .font(.callout.weight(.semibold))
                    Text(tr("Der Build-Ordner (\(folder.lastPathComponent)) kann gelöscht werden, um Speicherplatz freizugeben. Die NSP-Quelldateien bleiben erhalten.",
                            "The build folder (\(folder.lastPathComponent)) can be deleted to free space. The NSP source files will be kept."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(tr("In Papierkorb legen", "Move to Trash")) {
                    trashBuildFolder(folder)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(4)
        } label: {
            Text(tr("Speicherplatz-Bereinigung", "Disk Space Cleanup"))
        }
    }

    private var trashedSuccessBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(tr("Build-Ordner wurde in den Papierkorb gelegt – Speicherplatz erfolgreich freigegeben.",
                    "Build folder was moved to the Trash – disk space freed successfully."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func trashBuildFolder(_ folder: URL) {
        do {
            try BuildWorkFolder.trashFolder(at: folder)
            didTrashBuildFolder = true
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Fehler beim Löschen", "Error Deleting")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func checkForBuildFolder() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let folder = GameSourceLocator.findBuildFolder(for: game) {
                let size = BuildWorkFolder.formattedSize(of: folder)
                DispatchQueue.main.async {
                    self.buildFolderURL = folder
                    self.buildFolderSizeText = size
                }
            }
        }
    }
}
