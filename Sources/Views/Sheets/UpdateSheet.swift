import SwiftUI

// MARK: - nxnative update

struct UpdateSheet: View {
    @EnvironmentObject private var updater: UpdateManager
    @EnvironmentObject private var buildMonitor: ActiveBuildMonitor
    @EnvironmentObject private var library: GameLibraryManager
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let error = updater.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if updater.updateAvailable {
                GroupBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(updater.pendingCommitsList, id: \.self) { commit in
                                Text(commit)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(4)
                    }
                    .frame(height: 110)
                } label: {
                    Text(tr("Neue Änderungen", "What's New"))
                }
            }

            if !updater.updateLogs.isEmpty {
                LogConsoleView(lines: updater.updateLogs, minHeight: 100)
            }

            if let active = buildMonitor.activeBuild {
                Label(tr("Gerade läuft ein Build (\(active.gameName)). Bitte warte mit dem Update, bis er fertig ist.",
                         "A build is currently running (\(active.gameName)). Please wait until it has finished before updating."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Spacer(minLength: 0)

            HStack {
                if updater.updateSuccess {
                    Label(tr("Erfolgreich aktualisiert", "Updated successfully"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(tr("Schließen", "Close")) {
                    router.showingUpdateSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button(tr("Erneut prüfen", "Check Again")) {
                    updater.checkForUpdates()
                }
                .disabled(updater.isChecking || updater.isUpdating)

                if updater.updateAvailable {
                    Button {
                        updater.performUpdate { library.refreshLibrary() }
                    } label: {
                        if updater.isUpdating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(tr("Jetzt aktualisieren", "Update Now"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(updater.isUpdating || buildMonitor.activeBuild != nil)
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 460)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if updater.isChecking {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: headerSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(headerColor)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text("\(tr("Installiert", "Installed")): \(updater.currentCommitHash.isEmpty ? "–" : updater.currentCommitHash)"
                     + (updater.currentCommitSubject.isEmpty ? "" : " · \(updater.currentCommitSubject)"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let date = updater.lastCheckDate {
                    Text("\(tr("Zuletzt geprüft", "Last checked")): \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerTitle: String {
        if updater.isChecking { return tr("Suche nach Updates …", "Checking for updates…") }
        if updater.errorMessage != nil { return tr("Update-Prüfung fehlgeschlagen", "Update check failed") }
        if updater.updateAvailable {
            return tr("Neue Version verfügbar (\(updater.pendingCommitsCount) Commits)", "New version available (\(updater.pendingCommitsCount) commits)")
        }
        return tr("nxnative ist aktuell", "nxnative is up to date")
    }

    private var headerSymbol: String {
        if updater.errorMessage != nil { return "exclamationmark.circle.fill" }
        return updater.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill"
    }

    private var headerColor: Color {
        if updater.errorMessage != nil { return .red }
        return updater.updateAvailable ? .orange : .green
    }
}
