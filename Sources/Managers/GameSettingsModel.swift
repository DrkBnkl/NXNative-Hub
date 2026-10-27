import Foundation

// MARK: - Game settings (env.txt editor)

final class GameSettingsModel: ObservableObject {
    struct StatusMessage: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var titleId: String = ""
    @Published private(set) var gameName: String = ""
    @Published private(set) var associatedAppPath: String?
    /// Determined once on load (not on every view redraw).
    @Published private(set) var ryujinxSavePath: String?

    @Published var fpsTarget: String = "60"        // DM_FPS_TARGET
    @Published var opMode: String = "1"            // DM_OPMODE (1 = Docked 1080p, 0 = Handheld 720p)
    @Published var upscaling: String = "metalfx"   // DM_PRESENT_UPSCALE (off, metalfx)
    @Published var showFps: Bool = true            // DM_SHOW_FPS
    @Published var metalHud: Bool = false          // DM_METAL_HUD
    @Published var frameBuffering: Bool = true     // DM_PRESENT_SNAP
    @Published var rumble: Bool = true             // DM_RUMBLE
    @Published var rumbleGain: Double = 1.0        // DM_RUMBLE_GAIN
    @Published var fullscreen: Bool = false        // DM_FULLSCREEN
    @Published var language: String = ""          // DM_LANG

    @Published var statusMessage: StatusMessage?

    static let managedKeys: Set<String> = [
        "DM_FPS_TARGET", "DM_OPMODE", "DM_PRESENT_UPSCALE", "DM_SHOW_FPS", "DM_METAL_HUD",
        "DM_PRESENT_SNAP", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_FULLSCREEN", "DM_LANG"
    ]

    var hasGame: Bool { !titleId.isEmpty }
    var envFilePath: String { NXPaths.envFilePath(titleId: titleId) }

    func load(titleId: String, gameName: String, appPath: String? = nil) {
        self.titleId = titleId
        self.gameName = gameName
        self.associatedAppPath = appPath
        self.statusMessage = nil

        // Reset to defaults first, so values of the previously opened game
        // do not stick when a key is missing from env.txt.
        resetToDefaults()

        if let values = EnvFile.load(path: envFilePath)?.values {
            apply(values)
        }

        ryujinxSavePath = nil
        let tid = titleId
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let path = SaveGameImporter.ryujinxSavePath(titleId: tid)
            DispatchQueue.main.async {
                if self?.titleId == tid { self?.ryujinxSavePath = path }
            }
        }
    }

    func resetToDefaults() {
        fpsTarget = "60"
        opMode = "1"
        upscaling = "metalfx"
        showFps = true
        metalHud = false
        frameBuffering = true
        rumble = true
        rumbleGain = 1.0
        fullscreen = false
        language = AppPreferences.shared.defaultGameLanguage
    }

    private func apply(_ values: [String: String]) {
        for (key, val) in values {
            switch key {
            case "DM_FPS_TARGET": fpsTarget = val
            case "DM_OPMODE": opMode = val
            case "DM_PRESENT_UPSCALE": upscaling = val
            case "DM_SHOW_FPS": showFps = (val == "1")
            case "DM_METAL_HUD": metalHud = (val == "1")
            case "DM_PRESENT_SNAP": frameBuffering = (val == "1")
            case "DM_RUMBLE": rumble = (val == "1")
            case "DM_RUMBLE_GAIN": rumbleGain = Double(val) ?? 1.0
            case "DM_FULLSCREEN": fullscreen = (val == "1")
            case "DM_LANG": language = val
            default: break
            }
        }
    }

    /// Saves env.txt. Lines not managed by the app are preserved.
    /// Returns `false` if writing fails.
    @discardableResult
    func save() -> Bool {
        guard hasGame else { return false }

        let dir = NXPaths.gameConfigDirectory(titleId: titleId)
        let existing = EnvFile.load(path: envFilePath) ?? EnvFile()

        var lines: [String] = [
            "# nxnative \(tr("Konfiguration für", "configuration for")) \(gameName) (\(titleId))",
            "# \(tr("Wird automatisch beim Start des Spiels ausgelesen", "Automatically detected when the game starts"))",
            ""
        ]
        if !fpsTarget.isEmpty { lines.append("DM_FPS_TARGET=\(fpsTarget)") }
        lines.append("DM_OPMODE=\(opMode)")
        lines.append("DM_PRESENT_UPSCALE=\(upscaling)")
        lines.append("DM_SHOW_FPS=\(showFps ? "1" : "0")")
        lines.append("DM_METAL_HUD=\(metalHud ? "1" : "0")")
        lines.append("DM_PRESENT_SNAP=\(frameBuffering ? "1" : "0")")
        lines.append("DM_RUMBLE=\(rumble ? "1" : "0")")
        lines.append("DM_RUMBLE_GAIN=\(String(format: "%.1f", rumbleGain))")
        // Windowed = key absent, so nxnative uses its default.
        lines.append(fullscreen ? "DM_FULLSCREEN=1" : "# DM_FULLSCREEN=1")
        if !language.isEmpty { lines.append("DM_LANG=\(language)") }

        let preserved = existing.unmanagedLines(managedKeys: Self.managedKeys)
        if !preserved.isEmpty {
            lines.append("")
            lines.append(EnvFile.preservedHeader)
            lines.append(contentsOf: preserved)
        }

        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(toFile: envFilePath, atomically: true, encoding: .utf8)
            showStatus(tr("Einstellungen gespeichert", "Settings saved"), isError: false)
            return true
        } catch {
            showStatus(tr("Speichern fehlgeschlagen: \(error.localizedDescription)",
                          "Saving failed: \(error.localizedDescription)"), isError: true)
            return false
        }
    }

    /// Saves and launches the game – only if saving succeeded.
    @discardableResult
    func saveAndLaunch() -> Bool {
        guard save() else { return false }
        if let app = associatedAppPath, FileManager.default.fileExists(atPath: app) {
            GameActions.launch(appPath: app)
        }
        return true
    }

    func showStatus(_ text: String, isError: Bool) {
        let message = StatusMessage(text: text, isError: isError)
        statusMessage = message
        guard !isError else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
