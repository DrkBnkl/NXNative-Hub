import AppKit
import Foundation

// MARK: - Locator for game source directory & direct update dispatcher

enum GameSourceLocator {
    /// Attempts to find the source folder (containing the NSPs or <titleId>_build) for an installed game.
    static func findSourceDirectory(for game: InstalledGame) -> String? {
        let fm = FileManager.default
        let tid = game.titleId
        let baseTid = SwitchTitleID.baseID(of: tid) ?? tid

        // 1. Check .key file beside the app bundle
        let keyPaths = [
            game.path + ".key",
            (game.path as NSString).deletingPathExtension + ".app.key"
        ]
        for keyPath in keyPaths {
            if fm.fileExists(atPath: keyPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: keyPath)),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let sources = json["sources"] as? [String: Any] {
                for (srcPath, _) in sources {
                    if fm.fileExists(atPath: srcPath) {
                        return srcPath
                    }
                    for searchTid in [tid, baseTid] {
                        let buildFolderMarker = "/\(searchTid)_build"
                        if let range = srcPath.range(of: buildFolderMarker) {
                            let candidate = String(srcPath[..<range.lowerBound])
                            if fm.fileExists(atPath: candidate) {
                                return candidate
                            }
                        }
                    }
                }
            }
        }

        // 2. Search ~/NXNative/Import subdirectories
        let importFolder = NXPaths.importFolder
        if let subdirs = try? fm.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil) {
            for dir in subdirs {
                let build1 = dir.appendingPathComponent("\(tid)_build")
                let build2 = dir.appendingPathComponent("\(baseTid)_build")
                if fm.fileExists(atPath: build1.path) || fm.fileExists(atPath: build2.path) {
                    return dir.path
                }
                let meta = GameMetaDetector.detect(in: dir)
                if meta.titleId == tid || meta.baseTitleId == tid || meta.titleId == baseTid || meta.baseTitleId == baseTid {
                    return dir.path
                }
            }
        }

        // 3. Check game app folder's parent directory
        let parent = URL(fileURLWithPath: game.path).deletingLastPathComponent()
        let parentBuild1 = parent.appendingPathComponent("\(tid)_build")
        let parentBuild2 = parent.appendingPathComponent("\(baseTid)_build")
        if fm.fileExists(atPath: parentBuild1.path) || fm.fileExists(atPath: parentBuild2.path) {
            return parent.path
        }
        if let siblings = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            for item in siblings where item.pathExtension.lowercased() == "nup" && NUPReader.isNUP(item) {
                let meta = GameMetaDetector.detect(in: item)
                if meta.titleId == tid || meta.baseTitleId == tid || meta.titleId == baseTid || meta.baseTitleId == baseTid {
                    return item.path
                }
            }
        }

        return nil
    }

    /// Finds the <titleId>_build folder for an installed game, if it exists.
    static func findBuildFolder(for game: InstalledGame) -> URL? {
        guard let sourceDir = findSourceDirectory(for: game) else { return nil }
        var isDir: ObjCBool = false
        let isFile = FileManager.default.fileExists(atPath: sourceDir, isDirectory: &isDir) && !isDir.boolValue
        let baseDirURL = isFile ? URL(fileURLWithPath: sourceDir).deletingLastPathComponent() : URL(fileURLWithPath: sourceDir)
        let tid = game.titleId
        let baseTid = SwitchTitleID.baseID(of: tid) ?? tid
        let candidates = [
            baseDirURL.appendingPathComponent("\(tid)_build"),
            baseDirURL.appendingPathComponent("\(baseTid)_build")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum GameUpdateAction {
    /// Directly performs an update or recompilation of the specified game.
    /// If the source directory is already known, it starts the build immediately.
    /// Otherwise, it prompts the user to select the game folder.
    static func performUpdate(
        for game: InstalledGame,
        router: AppRouter,
        builderForm: BuilderFormModel,
        buildManager: BuildManager,
        buildMonitor: ActiveBuildMonitor,
        prefs: AppPreferences,
        library: GameLibraryManager
    ) {
        guard !buildManager.isRunning && buildMonitor.activeBuild == nil else {
            let alert = NSAlert()
            alert.messageText = tr("Build läuft bereits", "Build Already Running")
            alert.informativeText = tr("Es wird derzeit bereits ein Spiel gebaut oder aktualisiert. Bitte warte, bis dieser Vorgang abgeschlossen ist.",
                                       "A game is already being built or updated. Please wait until this process finishes.")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        if let sourceDir = GameSourceLocator.findSourceDirectory(for: game) {
            startDirectBuild(
                sourceDir: sourceDir,
                game: game,
                router: router,
                builderForm: builderForm,
                buildManager: buildManager,
                buildMonitor: buildMonitor,
                prefs: prefs,
                library: library
            )
        } else {
            // Prompt user to pick the folder holding the NSPs or <titleId>_build, or a .nup file
            let chosen = FilePanels.chooseGameSource(
                prompt: tr("Auswählen", "Choose"),
                message: tr("Wähle den Ordner mit den Quelldateien (.nsp / .xci), eine .nup-Datei oder den Build-Ordner (\(game.titleId)_build).",
                            "Choose the folder containing the source files (.nsp / .xci), a .nup file or the build folder (\(game.titleId)_build).")
            )
            if let selected = chosen?.path {
                startDirectBuild(
                    sourceDir: selected,
                    game: game,
                    router: router,
                    builderForm: builderForm,
                    buildManager: buildManager,
                    buildMonitor: buildMonitor,
                    prefs: prefs,
                    library: library
                )
            } else {
                // User cancelled; open in builder so they can configure manually if desired
                builderForm.gameDirectory = ""
                router.statusTargetGame = nil
                router.selection = .builder
            }
        }
    }

    private static func startDirectBuild(
        sourceDir: String,
        game: InstalledGame,
        router: AppRouter,
        builderForm: BuilderFormModel,
        buildManager: BuildManager,
        buildMonitor: ActiveBuildMonitor,
        prefs: AppPreferences,
        library: GameLibraryManager
    ) {
        let targetAppPath = game.path
        builderForm.setSource(from: URL(fileURLWithPath: sourceDir))
        builderForm.platform = .macApp
        builderForm.language = game.language.isEmpty ? prefs.defaultGameLanguage : game.language
        builderForm.appName = game.name
        builderForm.keepExtracted = true

        router.statusTargetGame = nil
        guard builderForm.canStart(manager: buildManager, monitor: buildMonitor, prefs: prefs) else {
            router.selection = .builder
            return
        }

        if let space = builderForm.refreshedDiskSpace(), !space.isSufficient {
            let alert = NSAlert()
            alert.messageText = tr("Zu wenig Speicher frei", "Not enough disk space")
            alert.informativeText = space.confirmationMessage(hasPreviousBuild: builderForm.hasPreviousBuild)
            alert.alertStyle = .warning
            alert.addButton(withTitle: tr("Abbrechen", "Cancel"))
            alert.addButton(withTitle: tr("Trotzdem aktualisieren", "Update Anyway"))
            guard alert.runModal() == .alertSecondButtonReturn else {
                router.selection = .builder
                return
            }
        }

        let options = builderForm.makeOptions(prefs: prefs)
        buildManager.startBuild(options: options) {
            if buildManager.buildSucceeded, let newAppPath = buildManager.createdArtifactPath {
                let fm = FileManager.default
                let newURL = URL(fileURLWithPath: newAppPath).standardizedFileURL
                let targetURL = URL(fileURLWithPath: targetAppPath).standardizedFileURL
                if newURL.path != targetURL.path && fm.fileExists(atPath: newURL.path) {
                    do {
                        if fm.fileExists(atPath: targetURL.path) {
                            try fm.trashItem(at: targetURL, resultingItemURL: nil)
                        }
                        try fm.moveItem(at: newURL, to: targetURL)
                        buildManager.appendLog(tr("App in Bibliothek aktualisiert: \(targetURL.lastPathComponent)",
                                                  "Updated app in library: \(targetURL.lastPathComponent)"))
                    } catch {
                        buildManager.appendLog(tr("⚠︎ App konnte nicht in die Bibliothek verschoben werden: \(error.localizedDescription)",
                                                  "⚠︎ Could not update app in library: \(error.localizedDescription)"))
                    }
                }
            }
            library.refreshLibrary()
            buildMonitor.checkActiveBuild()
            builderForm.scanGameFolder()
        }
        buildMonitor.checkActiveBuild()
        router.showingLiveLog = true
    }
}
