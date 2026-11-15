import Foundation

// MARK: - German texts for launcher.json
//
// launcher.json carries English labels. In the German UI the known ones are translated here;
// a label nxnative adds later is shown in English until it is added to this table.

enum LauncherText {
    static func section(_ name: String) -> String {
        guard LanguageManager.shared.isGerman else { return name }
        return sections[name] ?? name
    }

    static func label(_ setting: LauncherSetting) -> String {
        guard LanguageManager.shared.isGerman else { return setting.label }
        return labels[setting.env] ?? setting.label
    }

    static func note(_ setting: LauncherSetting) -> String {
        guard LanguageManager.shared.isGerman, !setting.note.isEmpty else { return setting.note }
        // Only the notes this table knows; a changed upstream note stays English.
        return notes[setting.note] ?? setting.note
    }

    static func option(_ value: String, label: String, of setting: LauncherSetting) -> String {
        guard LanguageManager.shared.isGerman else { return label }
        if setting.env == "DM_LANG" { return languages[value] ?? label }
        return options[label] ?? label
    }

    private static let sections: [String: String] = [
        "Game": "Spiel",
        "Controls": "Steuerung",
        "Performance": "Leistung"
    ]

    private static let labels: [String: String] = [
        "DM_FPS_TARGET": "Bildrate",
        "DM_DYNAMIC_RESOLUTION": "Dynamische Auflösung",
        "DM_RENDER_SCALE": "Render-Skalierung",
        "DM_OPMODE": "Konsolenmodus",
        "DM_PRESENT_UPSCALE": "Hochskalierung",
        "DM_UPSCALER": "Upscaler des Spiels",
        "DM_LANG": "Spielsprache",
        "DM_FULLSCREEN": "Anzeigemodus",
        "DM_RUMBLE": "Vibration",
        "DM_RUMBLE_GAIN": "Vibrationsstärke",
        "DM_RUMBLE_MIN": "Vibrationsschwelle",
        "DM_PAD_PRESS_TO_JOIN": "Beitreten per Tastendruck",
        "DM_SW2": "Switch-2-Controller",
        "DM_SCREEN_ASPECT": "Bildformat",
        "DM_PRESENT_SNAP": "Frame-Buffering",
        "DM_PSO_MTL4": "Metal-4-Pipelines",
        "DM_PSO_PREBUILD": "Pipelines vorab erstellen",
        "DM_NVN_ENC_THREAD": "Encode-Thread",
        "DM_FPS_HOLD": "Frames bei Verzögerung halten",
        "DM_METAL_HUD": "Performance-HUD"
    ]

    private static let notes: [String: String] = [
        "Uses more GPU time and can increase heat.":
            "Braucht mehr GPU-Zeit und kann die Wärme erhöhen.",
        "Lets the game lower its resolution under load. Turn off to keep full resolution for the selected console mode.":
            "Das Spiel darf die Auflösung unter Last senken. Aus = volle Auflösung für den gewählten Konsolenmodus.",
        "Plays Joy-Con 2 and Pro Controller 2 over Bluetooth: hold Sync on one during the game to pair it. macOS asks once for Bluetooth access.":
            "Joy-Con 2 und Pro Controller 2 über Bluetooth: Während des Spiels Sync gedrückt halten, um zu koppeln. macOS fragt einmal nach Bluetooth-Zugriff.",
        "Renders about a quarter more pixels: a little slower and warmer.":
            "Rendert etwa ein Viertel mehr Pixel: etwas langsamer und wärmer.",
        "Up to one frame more display latency.":
            "Bis zu einem Frame mehr Anzeigeverzögerung.",
        "Keeps a pipeline archive; uses more memory.":
            "Behält ein Pipeline-Archiv; braucht mehr Speicher.",
        "The first start waits a few minutes for it, once.":
            "Der erste Start wartet einmalig einige Minuten darauf.",
        "This game's files do not list its languages, so some of these may not be in the game. It may then show another one.":
            "Die Spieldateien nennen ihre Sprachen nicht, daher fehlen manche davon eventuell im Spiel. Es zeigt dann eine andere."
    ]

    private static let options: [String: String] = [
        "Docked": "Docked",
        "Handheld": "Handheld",
        "Standard": "Standard",
        "Game's own": "Eigener des Spiels",
        "Window": "Fenster",
        "Fullscreen": "Vollbild",
        "16:9 (Switch)": "16:9 (Switch)",
        "Fit": "Einpassen",
        "Fill": "Füllen"
    ]

    private static let languages: [String: String] = [
        "en-US": "Englisch (USA)",
        "en-GB": "Englisch (Großbritannien)",
        "ja": "Japanisch",
        "fr": "Französisch",
        "de": "Deutsch",
        "es-419": "Spanisch (Lateinamerika)",
        "es": "Spanisch",
        "it": "Italienisch",
        "nl": "Niederländisch",
        "fr-CA": "Französisch (Kanada)",
        "pt": "Portugiesisch",
        "ru": "Russisch",
        "ko": "Koreanisch",
        "zh-Hant": "Chinesisch (traditionell)",
        "zh-Hans": "Chinesisch (vereinfacht)",
        "pt-BR": "Portugiesisch (Brasilien)"
    ]
}
