import AppKit
import UniformTypeIdentifiers

// MARK: - File and folder pickers (NSOpenPanel)

enum FilePanels {
    static func chooseApplications() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.application]
        panel.prompt = tr("Hinzufügen", "Add")
        panel.message = tr("Wähle eine oder mehrere konvertierte Spiele (.app) aus.", "Choose one or more converted games (.app).")
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseFolders(multiple: Bool, prompt: String, message: String? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = multiple
        panel.prompt = prompt
        if let message = message { panel.message = message }
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseKeysFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Auswählen", "Choose")
        panel.message = tr("Wähle deine prod.keys-Datei aus.", "Choose your prod.keys file.")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseSaveSources() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = tr("Importieren", "Import")
        panel.message = tr("Wähle den JKSV-Backup-Ordner, eine .zip-Datei oder Speicherdateien (.sav / slot_*) aus.",
                           "Choose the JKSV backup folder, a .zip file or save files (.sav / slot_*).")
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
