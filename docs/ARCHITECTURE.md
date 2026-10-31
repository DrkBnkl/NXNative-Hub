# Architecture

NXNative Hub is a SwiftUI app (macOS 14+) built with plain `swiftc`. It does not convert games itself; it drives the nxnative build script and manages the results.

## Layers

| Folder | Responsibility | Key types |
|---|---|---|
| `Sources/App` | Entry point, scenes, navigation, menu bar | `NXNativeHubApp`, `AppRouter`, `AppCommands`, `GameActions` |
| `Sources/Core` | Infrastructure without UI | `NXPaths`, `CommandRunner`, `StreamingProcess`, `BuildEvent`, `BuildFailureTracker`, `LiveLogWriter`, `EnvFile`, `LauncherSettingsList`, `SavedChoices`, `ProdKeysFile`, `Notifier`, `SwitchTitleID`, `GameUpdateChecker`, `tr()` |
| `Sources/Models` | Value types and compatibility logic | `InstalledGame`, `TargetPlatform`, `ProfileDatabase`, `GameMetaDetector`, `GameUpdateStatus` |
| `Sources/Managers` | Business logic as `ObservableObject`s | `GameLibraryManager`, `BuildManager`, `ImportBatchManager`, `UpdateManager`, `ActiveBuildMonitor`, `GameSettingsModel`, `SetupChecker`, `AppPreferences`, `GameDiagnostics` |
| `Sources/Views` | SwiftUI views only | `ContentView`, `LibraryView`, `BuilderView`, `ImportView`, sheets, `GameStatusSheet`, `SettingsView` |

Dependencies point downwards only: Views → Managers → Models/Core.

## State and data flow

- All managers are created once as `@StateObject` in `NXNativeHubApp` and injected with `.environmentObject`.
- Sheets receive the same objects explicitly via `ContentView.withEnvironment(_:)`.
- `AppCommands` gets the same instances, so menu items and toolbar buttons trigger identical actions.
- `AppRouter` holds the navigation and presentation state (sidebar selection, selected game, open sheets).
- Long-running work runs on background queues; results are published on the main thread.

## Scenes

| Scene | Content |
|---|---|
| `Window` (single main window) | Sidebar (Library, Build Game) and detail view; sheets for import, game settings, updates, live log, setup |
| `Settings` | General (language, prod.keys, nxnative folder), Library (folders), Setup (checklist) |

A single `Window` is used on purpose: the app manages one build and import state.

## External processes

| Tool | Called by | Via |
|---|---|---|
| `venv/bin/python3 scripts/build_ipa_from_nsp.py … --progress json` | `BuildManager`, `ImportBatchManager` | `StreamingProcess` (line-based, main-thread callbacks) |
| `git`, `pip`, `dotnet` | `UpdateManager` | `CommandRunner` |
| `ps` | `ActiveBuildMonitor` (every 2.5 s, also detects builds started in Terminal) | `CommandRunner` |
| `xcode-select`, `python3 -m venv`, `pip` | `SetupChecker` | `CommandRunner` |
| `ditto` | `SaveGameImporter` (zip extraction) | `CommandRunner` |
| `xcodebuild`, `xcrun metal`, `brew` | `SetupChecker` (Xcode version, Metal toolchain, Homebrew tools) | `CommandRunner` |
| `venv/bin/python3 scripts/bug_report.py` | `GameDiagnostics` | `CommandRunner` |

Executables are always started with argument arrays, never through a shell. The build script reports progress as JSON lines, parsed by `BuildEvent`; `BuildFailureTracker` turns the exit code, the last `[RED]` message and stderr into the error shown to the user (exit codes per nxnative `docs/frontends.md`). A process killed by a signal is reported as 128 + signal.

## Game settings

nxnative's interface for front ends is described in its `docs/frontends.md`. A current Mac app carries `Contents/Resources/dm/launcher.json` (its settings with tested defaults) and reads, for each variable, in this order: launch environment → `env.txt` → bundle `dm/env.txt` → saved choices → tested default.

- `LauncherSettingsList` decodes the list (schema 1: unknown fields ignored, unknown kinds skipped, unknown sections shown by name).
- `GameSettingsModel` builds the form from it and stores changes as saved choices (`launcher.<VAR>` in the game's preferences domain, its bundle ID) via `SavedChoices` – only values that differ from the default. Listed keys in `env.txt` would win over those, so they are moved out of `env.txt` on save; values the list does not offer stay there and are shown read-only.
- `GameSettingsResolver` computes the effective values for the library badges.
- Builds without `launcher.json` use the legacy form, which writes a fixed set of keys to `env.txt`.

## Files and settings

| Location | Content | Owner |
|---|---|---|
| `NXPaths.repoPath` (default `~/NXNative/nxnative`) | nxnative repo, venv, profiles | user / `UpdateManager` |
| `~/NXNative/Games`, `~/NXNative/Import` | converted games, import queue | `GameLibraryManager`, `ImportBatchManager` |
| `~/NXNative/build_live.log` | log of the current build | `LiveLogWriter` |
| `~/Library/Application Support/nxnative/<TitleID>/env.txt` | per-game settings | `GameSettingsModel` via `EnvFile` |
| `…/<TitleID>/save`, `save_backup_<timestamp>` | saves and backups | `SaveGameImporter` |
| UserDefaults | prod.keys path, nxnative folder, languages, notifications, library folders, size cache | `AppPreferences`, `LanguageManager`, `GameLibraryManager` |
| Game's preferences domain (`org.nxnative.<title id>`) | saved choices `launcher.<VAR>` | `GameSettingsModel` via `SavedChoices` |
| `~/Library/Logs/nxnative/<TitleID>.log`, `.prev.log` | game logs (read only) | `GameDiagnostics` |
| `~/NXNative/Reports` | bug report zips | `GameDiagnostics` |

## Localization

`tr("German", "English")` returns the string for the current UI language (automatic or chosen in Settings). Changing the language rebuilds the view hierarchy via `.id(lang.currentChoice)`.
