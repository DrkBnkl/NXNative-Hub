import SwiftUI
import AppKit

// MARK: - Game update & recompilation status sheet

struct GameStatusSheet: View {
    let game: InstalledGame
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var builderForm: BuilderFormModel
    @EnvironmentObject private var updater: UpdateManager

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

                    if !game.updateStatus.commitTitles.isEmpty {
                        profileCommitsSection
                    }
                }
                .padding(20)
            }

            Divider()

            bottomBar
        }
        .frame(width: 540, height: 500)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(game.updateStatus.statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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
                    isMismatch: game.buildCommit != updater.currentCommitHash
                )

                comparisonRow(
                    label: tr("Shader-Chain", "Shader Chain"),
                    buildValue: game.shaderChain.map { "b-\($0)" } ?? "–",
                    repoValue: currentRepoChain.map { "b-\($0)" } ?? "–",
                    isMismatch: game.shaderChain != currentRepoChain
                )

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

            Button(tr("Im Builder öffnen", "Open in Builder")) {
                openInBuilder()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func openInBuilder() {
        // Try locating matching game files in ~/NXNative/Import/
        let importFolder = NXPaths.importFolder
        var matchingFolder: String?
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil) {
            for dir in subdirs {
                let meta = GameMetaDetector.detect(in: dir)
                if meta.titleId == game.titleId || meta.baseTitleId == game.titleId {
                    matchingFolder = dir.path
                    break
                }
            }
        }

        if let source = matchingFolder {
            builderForm.gameDirectory = source
        }
        router.statusTargetGame = nil
        router.selection = .builder
    }
}
