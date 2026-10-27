# Architecture

NXNative Hub is a SwiftUI app (macOS 14+) built with plain `swiftc`. It does not convert games itself; it drives the nxnative build script and manages the results.

## Layers

| Folder | Responsibility | Key types |
|---|---|---|
| `Sources/App` | Entry point, scenes, navigation, menu bar | `NXNativeHubApp`, `AppRouter`, `AppCommands`, `GameActions` |
| `Sources/Core` | Infrastructure without UI | `NXPaths`, `CommandRunner`, `StreamingProcess`, `BuildEvent`, `LiveLogWriter`, `EnvFile`, `SwitchTitleID`, `tr()` |
| `Sources/Models` | Value types and compatibility logic | `InstalledGame`, `TargetPlatform`, `ProfileDatabase`, `GameMetaDetector` |
| `Sources/Managers` | Business logic as `ObservableObject`s | `GameLibraryManager`, `BuildManager`, `ImportBatchManager`, `UpdateManager`, `ActiveBuildMonitor`, `GameSettingsModel`, `SetupChecker`, `AppPreferences` |
| `Sources/Views` | SwiftUI views only | `ContentView`, `LibraryView`, `BuilderView`, `ImportView`, sheets, `SettingsView` |

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

Executables are always started with argument arrays, never through a shell. The build script reports progress as JSON lines, parsed by `BuildEvent`.

## Files and settings

| Location | Content | Owner |
|---|---|---|
| `NXPaths.repoPath` (default `~/NXNative/nxnative`) | nxnative repo, venv, profiles | user / `UpdateManager` |
| `~/NXNative/Games`, `~/NXNative/Import` | converted games, import queue | `GameLibraryManager`, `ImportBatchManager` |
| `~/NXNative/build_live.log` | log of the current build | `LiveLogWriter` |
| `~/Library/Application Support/nxnative/<TitleID>/env.txt` | per-game settings | `GameSettingsModel` via `EnvFile` |
| `…/<TitleID>/save`, `save_backup_<timestamp>` | saves and backups | `SaveGameImporter` |
| UserDefaults | prod.keys path, nxnative folder, languages, library folders, size cache | `AppPreferences`, `LanguageManager`, `GameLibraryManager` |

## Localization

`tr("German", "English")` returns the string for the current UI language (automatic or chosen in Settings). Changing the language rebuilds the view hierarchy via `.id(lang.currentChoice)`.
