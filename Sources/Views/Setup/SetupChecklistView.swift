import SwiftUI

// MARK: - Setup checklist
//
// Shared by the setup sheet (shown at launch when something required is missing)
// and the "Setup" tab of the Settings window.

struct SetupChecklistView: View {
    @EnvironmentObject private var checker: SetupChecker
    @EnvironmentObject private var prefs: AppPreferences
    @EnvironmentObject private var updater: UpdateManager
    @EnvironmentObject private var importManager: ImportBatchManager

    var body: some View {
        Form {
            Section {
                ForEach(checker.checks) { check in
                    SetupCheckRow(check: check, isBusy: checker.isFixing || checker.isChecking) { fix in
                        perform(fix)
                    }
                }
                if checker.checks.isEmpty {
                    ProgressView(tr("Wird geprüft …", "Checking…"))
                        .frame(maxWidth: .infinity)
                }
            } header: {
                HStack {
                    Text(summary)
                    Spacer()
                    if checker.isChecking {
                        ProgressView().controlSize(.small)
                    }
                    Button(tr("Erneut prüfen", "Check Again")) {
                        recheck()
                    }
                    .controlSize(.small)
                    .disabled(checker.isChecking || checker.isFixing)
                }
            } footer: {
                Text(tr("nxnative selbst wird nicht mitgeliefert: Installiere es per git clone nach ~/NXNative/nxnative oder wähle oben einen eigenen Ordner. Die App findet es dann automatisch.",
                        "nxnative itself is not bundled: install it with git clone into ~/NXNative/nxnative, or choose a custom folder above. The app then finds it automatically."))
            }

            if checker.isFixing || !checker.fixLog.isEmpty {
                Section(tr("Protokoll", "Log")) {
                    LogConsoleView(lines: checker.fixLog, minHeight: 90)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if !checker.hasRun { recheck() }
        }
    }

    private var summary: String {
        if !checker.hasRun { return tr("Voraussetzungen", "Prerequisites") }
        if checker.hasBlockingIssues {
            return tr("Einrichtung unvollständig", "Setup incomplete")
        }
        if checker.issueCount > 0 {
            return tr("Bereit – \(checker.issueCount) Hinweise", "Ready – \(checker.issueCount) notes")
        }
        return tr("Alles bereit", "All set")
    }

    private func recheck() {
        checker.run(prodKeysExists: prefs.prodKeysExists)
    }

    private func perform(_ fix: SetupCheck.Fix) {
        switch fix {
        case .chooseRepoFolder:
            guard let url = FilePanels.chooseFolders(
                multiple: false,
                prompt: tr("Auswählen", "Choose"),
                message: tr("Wähle den nxnative-Ordner (enthält scripts/build_ipa_from_nsp.py).",
                            "Choose the nxnative folder (contains scripts/build_ipa_from_nsp.py).")).first else { return }
            prefs.applyChosenRepoFolder(url)
            NXNativeLocation.didChange(checker: checker, prefs: prefs, updater: updater, importManager: importManager)
        case .chooseProdKeys:
            guard let url = FilePanels.chooseKeysFile() else { return }
            prefs.prodKeysPath = url.path
            recheck()
        case .createVenv:
            checker.createVenv(prodKeysExists: prefs.prodKeysExists)
        case .installPythonPackages:
            checker.installPythonPackages(prodKeysExists: prefs.prodKeysExists)
        case .installCommandLineTools:
            checker.installCommandLineTools(prodKeysExists: prefs.prodKeysExists)
        case .installBrewTools:
            checker.installBrewTools(prodKeysExists: prefs.prodKeysExists)
        case .downloadMetalToolchain:
            checker.downloadMetalToolchain(prodKeysExists: prefs.prodKeysExists)
        }
    }
}

// MARK: - One checklist row

struct SetupCheckRow: View {
    let check: SetupCheck
    let isBusy: Bool
    let onFix: (SetupCheck.Fix) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 22)
                .accessibilityLabel(statusLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.body.weight(.medium))
                Text(check.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let fix = check.fix, check.status != .ok || fix == .chooseRepoFolder {
                Button(title(for: fix)) { onFix(fix) }
                    .controlSize(.small)
                    .disabled(isBusy)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .missing: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch check.status {
        case .ok: return .green
        case .warning: return .orange
        case .missing: return .red
        }
    }

    private var statusLabel: String {
        switch check.status {
        case .ok: return tr("In Ordnung", "OK")
        case .warning: return tr("Hinweis", "Warning")
        case .missing: return tr("Fehlt", "Missing")
        }
    }

    private func title(for fix: SetupCheck.Fix) -> String {
        switch fix {
        case .chooseRepoFolder:
            return check.status == .ok ? tr("Ändern …", "Change…") : tr("Ordner wählen …", "Choose Folder…")
        case .createVenv: return tr("venv erstellen", "Create venv")
        case .installPythonPackages: return tr("Installieren", "Install")
        case .installCommandLineTools: return tr("Installieren …", "Install…")
        case .chooseProdKeys: return tr("Auswählen …", "Choose…")
        case .installBrewTools: return tr("Installieren", "Install")
        case .downloadMetalToolchain: return tr("Laden", "Download")
        }
    }
}

// MARK: - Setup sheet (shown at launch if required prerequisites are missing)

struct SetupSheet: View {
    @EnvironmentObject private var checker: SetupChecker
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Einrichtung prüfen", "Check Setup"))
                        .font(.headline)
                    Text(tr("Zum Bauen von Spielen werden nxnative und einige Werkzeuge benötigt.",
                            "Building games requires nxnative and a few tools."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            SetupChecklistView()

            Divider()

            HStack {
                Spacer()
                Button(checker.hasBlockingIssues ? tr("Später", "Later") : tr("Fertig", "Done")) {
                    router.showingSetup = false
                }
                .keyboardShortcut(checker.hasBlockingIssues ? KeyboardShortcut.cancelAction : KeyboardShortcut.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 620, height: 640)
    }
}

// MARK: - Reacting to a changed nxnative location

enum NXNativeLocation {
    /// Refreshes everything that depends on the nxnative folder.
    static func didChange(checker: SetupChecker, prefs: AppPreferences, updater: UpdateManager, importManager: ImportBatchManager) {
        checker.run(prodKeysExists: prefs.prodKeysExists)
        updater.fetchLocalCommitInfo()
        importManager.scanImportFolder()   // reloads the game profiles
    }
}
