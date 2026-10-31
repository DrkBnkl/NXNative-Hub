import Foundation

// MARK: - Game logs and bug reports
//
// The Mac app writes ~/Library/Logs/nxnative/<title ID>.log (and .prev.log for the run before).
// nxnative's scripts/bug_report.py collects logs and build information – never game data or
// key values – into one zip to attach to an issue.

enum GameDiagnostics {
    enum ReportResult {
        case created(path: String)
        case failed(message: String)
    }

    static func hasLog(_ game: InstalledGame) -> Bool {
        FileManager.default.fileExists(atPath: game.logPath)
    }

    static func hasPreviousLog(_ game: InstalledGame) -> Bool {
        FileManager.default.fileExists(atPath: game.previousLogPath)
    }

    /// Creates a bug report zip in ~/NXNative/Reports. The completion runs on the main thread.
    static func createBugReport(for game: InstalledGame, completion: @escaping (ReportResult) -> Void) {
        let python = NXPaths.pythonPath
        let script = NXPaths.bugReportScriptPath
        let fm = FileManager.default

        guard fm.isExecutableFile(atPath: python), fm.fileExists(atPath: script) else {
            completion(.failed(message: tr("scripts/bug_report.py wurde nicht gefunden – bitte nxnative aktualisieren.",
                                           "scripts/bug_report.py was not found – please update nxnative.")))
            return
        }

        NXPaths.ensureDirectory(NXPaths.reportsFolder)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let output = NXPaths.reportsFolder
            .appendingPathComponent("nxnative-report-\(game.titleId)-\(formatter.string(from: Date())).zip").path

        DispatchQueue.global(qos: .userInitiated).async {
            let result = CommandRunner.run(python, [script, game.path, "--out", output])
            let outcome: ReportResult = result.succeeded && fm.fileExists(atPath: output)
                ? .created(path: output)
                : .failed(message: result.trimmedOutput.isEmpty
                          ? tr("Exit-Code \(result.exitCode)", "Exit code \(result.exitCode)")
                          : String(result.trimmedOutput.suffix(600)))
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}
