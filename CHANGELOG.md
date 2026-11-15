# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Game settings are drawn from each game's `launcher.json`: every setting the game offers (e.g. 120 fps, render scale, Switch 2 controllers, the game's own languages), with its tested default.
- Setup check for macOS 26.6, Xcode 27.2, the Metal toolchain and its version, and the Homebrew tools, with one-click install of the Metal toolchain and the Homebrew tools.
- Switch 2 games: build from a `.nup` file or a dump folder (`base/`, `updates/`, `dlc/`) in the builder and the batch import, without prod.keys (a dropped `.nup` file is built itself, whatever lies beside it; dumps without `base/` are recognized); title ID, versions and profile are read from the container or `main.npdm`.
- Switch 2 games as NSP/XCI are recognized and marked as not buildable yet, with a hint to use a `.nup` file or dump folder.
- "Refresh" button in the game import list to rescan the Import folder.
- The Build Game overview lists the games in the Import folder, with checkboxes to pick the games to convert, refresh, Show in Finder and Move to Trash (asks first; not while a build runs).
- Option in the batch import to move source files to the Trash after a successful conversion.
- "Switch 2" badge in the library, the import list and the builder; warning when a Switch 2 game has no nxnative profile or is built as an IPA.

### Changed
- Game settings are saved as the game's saved choices (only values that differ from the tested default) instead of `env.txt`, so newer tested defaults apply and the game's own settings window shows the same values. "Save & Launch" skips the game's own settings window.
- Settings that Hub 1.1 wrote into `env.txt` are moved once: values equal to the old Hub defaults are dropped (MetalFX upscaling and frame buffering are then off unless the game's default says otherwise), other values become saved choices, and a choice the game's settings list does not offer stays in `env.txt`; the old file is kept as `env.txt.hub-1.1.bak`.
- The setup check requires Python 3.12 (arm64) and `backports.zstd` before Python 3.14 instead of `zstandard`; "Create venv" replaces a venv with an older Python.
- The game language for builds offers every code nxnative takes (`en-US`, `en-GB`, `fr-CA`, `es-419`, `pt-BR`, `ru`, …); a saved `en` becomes `en-US`.
- The updater no longer runs `dotnet build` for nx_extract (a native tool since nxnative 641636e2); the .NET check is removed.
- After a build, the Hub opens or moves exactly the app the build announced, not any `.app` in the game folder.
- Save import replaces the save as a whole; the current save is kept as `save_backup_<time>`, and nothing changes if that backup fails. Import is refused while the game runs and warns when the game syncs with a cloud saves folder.
- Batch import keeps the source files (NSP / XCI / NUP) in the Import folder by default.
- The setup sheet opens by itself at launch only for missing prerequisites it has not shown before.
- A game built without a settings list can still be launched from its settings sheet.
- A missing prod.keys is now a setup warning instead of a blocking issue; NSP/XCI builds still require it.
- The setup check also requires the Python packages `nsz` and `zbic` (and capstone 5.x), as current nxnative does.

## [1.1.0] – 2026-10-27

### Added
- Game library with search, per-game badges, double-click to launch and context menu.
- Builder for Mac apps and unsigned IPAs with live progress, log and advanced options (game language, FPS counter, keep extracted data, app name).
- Batch import from `~/NXNative/Import` with compatibility check against the nxnative game profiles; processed source files are moved to the Trash.
- Per-game settings stored in `env.txt` (frame rate, console mode, MetalFX, full screen, Metal HUD, FPS counter, rumble, language).
- Save import from JKSV, Checkpoint and Ryujinx with automatic backup.
- nxnative updater (git, Python packages, nx_extract).
- Detection of running builds, including builds started in Terminal.
- Setup check with one-click fixes; custom nxnative folder.
- Settings window, German and English UI.
