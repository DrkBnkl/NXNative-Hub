import Foundation

// MARK: - Upstream updater (nxnative git repo)

final class UpdateManager: ObservableObject {
    @Published private(set) var isChecking = false
    @Published private(set) var isUpdating = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var currentCommitHash = ""
    @Published private(set) var currentCommitSubject = ""
    @Published private(set) var remoteCommitHash = ""
    @Published private(set) var pendingCommitsCount = 0
    @Published private(set) var pendingCommitsList: [String] = []
    @Published private(set) var updateLogs: [String] = []
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var updateSuccess = false

    private let queue = DispatchQueue(label: "org.nxnative.updater", qos: .userInitiated)
    private let branch = "main"

    var repoPath: String { NXPaths.repoPath }
    var repoExists: Bool { FileManager.default.fileExists(atPath: repoPath) }

    init() {
        fetchLocalCommitInfo()
    }

    func fetchLocalCommitInfo() {
        guard repoExists else {
            currentCommitHash = ""
            currentCommitSubject = ""
            updateAvailable = false
            return
        }
        let repo = repoPath
        queue.async { [weak self] in
            let hash = CommandRunner.git(repo, "rev-parse", "--short", "HEAD").trimmedOutput
            let subject = CommandRunner.git(repo, "log", "-1", "--pretty=format:%s").trimmedOutput
            DispatchQueue.main.async {
                self?.currentCommitHash = hash
                self?.currentCommitSubject = subject
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        guard !isChecking, !isUpdating else { return }
        guard repoExists else {
            if !silent {
                errorMessage = tr("nxnative wurde nicht gefunden unter:\n\(repoPath)",
                                  "nxnative was not found at:\n\(repoPath)")
            }
            return
        }
        isChecking = true
        errorMessage = nil
        updateSuccess = false
        let repo = repoPath
        let branch = self.branch

        queue.async { [weak self] in
            let fetch = CommandRunner.git(repo, "fetch", "origin", branch)
            guard fetch.succeeded else {
                DispatchQueue.main.async {
                    self?.isChecking = false
                    if !silent {
                        self?.errorMessage = tr("Keine Verbindung zu GitHub. Bitte Internetverbindung prüfen.",
                                                "Could not connect to GitHub. Please check your internet connection.")
                            + "\n" + fetch.trimmedOutput
                    }
                }
                return
            }

            let localHash = CommandRunner.git(repo, "rev-parse", "--short", "HEAD").trimmedOutput
            let remoteHash = CommandRunner.git(repo, "rev-parse", "--short", "origin/\(branch)").trimmedOutput
            let subject = CommandRunner.git(repo, "log", "-1", "--pretty=format:%s").trimmedOutput
            let count = Int(CommandRunner.git(repo, "rev-list", "--count", "HEAD..origin/\(branch)").trimmedOutput) ?? 0

            var commits: [String] = []
            if count > 0 {
                commits = CommandRunner.git(repo, "log", "HEAD..origin/\(branch)", "--oneline", "-n", "25")
                    .output.split(separator: "\n").map(String.init)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                self.currentCommitHash = localHash
                self.currentCommitSubject = subject
                self.remoteCommitHash = remoteHash
                self.pendingCommitsCount = count
                self.pendingCommitsList = commits
                self.updateAvailable = count > 0
                self.lastCheckDate = Date()
            }
        }
    }

    func performUpdate(onComplete: (() -> Void)? = nil) {
        guard !isUpdating, repoExists else { return }
        isUpdating = true
        updateLogs.removeAll()
        errorMessage = nil
        updateSuccess = false
        let repo = repoPath
        let branch = self.branch

        queue.async { [weak self] in
            guard let self = self else { return }

            // 1. Stash local changes to tracked files – only if there are any and
            //    `stash push` succeeded, so an unrelated older stash is never popped.
            self.log(tr("[1/4] Lokale Anpassungen sichern (git stash) …", "[1/4] Saving local changes (git stash)…"))
            let status = CommandRunner.git(repo, "status", "--porcelain", "--untracked-files=no")
            var didStash = false
            if status.succeeded && !status.trimmedOutput.isEmpty {
                let stash = CommandRunner.git(repo, "stash", "push", "-m", "nxnative-gui-autostash")
                didStash = stash.succeeded
                self.log(didStash ? tr("✓ Lokale Anpassungen zwischengespeichert", "✓ Local changes stashed")
                                  : tr("[Warnung] git stash fehlgeschlagen: \(stash.trimmedOutput)", "[Warning] git stash failed: \(stash.trimmedOutput)"))
            }

            // 2. Pull
            self.log(tr("[2/4] Aktualisierungen von GitHub laden …", "[2/4] Downloading updates from GitHub…"))
            let pull = CommandRunner.git(repo, "pull", "origin", branch)
            self.log(pull.trimmedOutput)

            // 3. Restore the stash
            if didStash {
                self.log(tr("Lokale Anpassungen werden wiederhergestellt …", "Restoring local changes…"))
                let pop = CommandRunner.git(repo, "stash", "pop")
                if !pop.succeeded {
                    self.log(tr("[Hinweis] Konflikt beim Wiederherstellen. Deine Änderungen liegen weiterhin im git-Stash „nxnative-gui-autostash“.\n\(pop.trimmedOutput)",
                                "[Note] Conflict while restoring. Your changes remain in the git stash “nxnative-gui-autostash”.\n\(pop.trimmedOutput)"))
                }
            }

            guard pull.succeeded else {
                DispatchQueue.main.async {
                    self.isUpdating = false
                    self.errorMessage = tr("git pull fehlgeschlagen (Exit-Code \(pull.exitCode)):", "git pull failed (exit code \(pull.exitCode)):")
                        + "\n" + pull.trimmedOutput
                }
                return
            }

            // 4. Rebuild nx_extract if .NET is installed
            let dotnet = NXPaths.dotnetExecutable
            if FileManager.default.fileExists(atPath: dotnet) {
                self.log(tr("[3/4] nx_extract wird neu kompiliert …", "[3/4] Rebuilding nx_extract…"))
                let build = CommandRunner.run(dotnet, ["build", NXPaths.nxExtractProject, "-c", "Release"])
                self.log(build.succeeded ? tr("✓ nx_extract erfolgreich gebaut", "✓ nx_extract built successfully")
                                         : "[\(tr("Warnung", "Warning"))] nx_extract: \(build.trimmedOutput)")
            }

            // 5. Upgrade Python packages
            let pip = NXPaths.pipPath
            if FileManager.default.fileExists(atPath: pip) {
                self.log(tr("[4/4] Python-Bibliotheken prüfen (lz4, capstone, fonttools, zstandard) …",
                            "[4/4] Checking Python libraries (lz4, capstone, fonttools, zstandard)…"))
                let pipResult = CommandRunner.run(pip, ["install", "--upgrade"] + NXPaths.requiredPythonModules.map { $0.package })
                self.log(pipResult.succeeded ? tr("✓ Python-Pakete aktuell", "✓ Python packages up to date")
                                             : "[\(tr("Warnung", "Warning"))] pip: \(pipResult.trimmedOutput)")
            }

            let newHash = CommandRunner.git(repo, "rev-parse", "--short", "HEAD").trimmedOutput
            let newSubject = CommandRunner.git(repo, "log", "-1", "--pretty=format:%s").trimmedOutput

            DispatchQueue.main.async {
                self.isUpdating = false
                self.currentCommitHash = newHash
                self.currentCommitSubject = newSubject
                self.updateAvailable = false
                self.pendingCommitsCount = 0
                self.pendingCommitsList.removeAll()
                self.updateSuccess = true
                self.updateLogs.append(tr("✓ nxnative ist auf dem neuesten Stand (\(newHash)).", "✓ nxnative is up to date (\(newHash))."))
                onComplete?()
            }
        }
    }

    private func log(_ message: String) {
        guard !message.isEmpty else { return }
        DispatchQueue.main.async {
            self.updateLogs.append(message)
        }
    }
}
