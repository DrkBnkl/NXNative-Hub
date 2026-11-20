# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Redesigned live log: header with the current step, count, progress bar, elapsed time and ETA; a list of the build's steps with their state and duration; the log filtered to what matters ("Important" hides the repeated progress lines, "All", "Problems"), with search and a Copy button. Works for builds started in the app, the batch import and Terminal (`--progress lines` or `json`).

## [1.4.2] – 2026-11-20

### Changed
- Starting a build with less free space than estimated now asks first ("Build Anyway" / "Cancel") instead of only showing a warning; the direct update and recompile action in the library asks the same.

### Fixed
- The live log of a build started in Terminal shows that build's output (also with `| tee file.log` or `> file.log`) instead of an earlier build's log.

## [1.4.1] – 2026-11-17

### Fixed
- **NUP File Selection for Recompilation & Builder**:
  - Replaced directory-only file picker with `FilePanels.chooseGameSource`, allowing direct selection of `.nup` container files as well as game folders in both the recompilation prompt and the Builder interface.
  - Automatic source location now searches for loose `.nup` files in `~/NXNative/Import` and beside installed `.app` bundles.
  - Resolved `_build` folder discovery and log access when working with `.nup` container files directly.
  - Improved `GameMetaDetector.detect` to read metadata directly from `.nup` file paths.

## [1.4.0] – 2026-11-17

### Added
- **Gamepad Navigation for Cover Grid View & Library**:
  - Full support for navigating the cover/icon grid view and list view with game controllers (Nintendo Switch Pro Controller, Joy-Cons, Xbox, PlayStation DualSense/DualShock, and MFi gamepads) via Apple's GameController framework.
  - Responsive 2D spatial navigation with D-Pad and analog thumbstick, debounced auto-repeat, and smooth auto-scrolling to selected items via `ScrollViewReader`.
  - Dedicated controller actions: `(A)` Launch selected game in fullscreen (`DM_FULLSCREEN=1`), `(X)` Open game settings, `(Y)` Open nxnative status & recompilation sheet, `(B)` Dismiss modal sheets or clear search, `(LB/RB)` Cycle library filters or cover sizes, `(LT/RT)` Toggle view mode between Grid and List.
  - Automatic fullscreen: Games selected or launched via gamepad automatically open in fullscreen for a seamless TV/couch console experience.
  - Enhanced visual selection: active cover cards lift with an accent glow, 3px border, and smooth spring physics.
  - Floating Gamepad HUD pill docked at the bottom displaying active controller model and button hints whenever a gamepad is connected.
  - Keyboard navigation (Arrow keys, Return to launch, Space for settings) in Cover Grid View.
  - Gamepad connection status inspector in General Settings.

## [1.3.1] – 2026-11-17

### Fixed
- **Cover Grid Alignment**: Fixed vertical misalignment across cards by establishing uniform fixed-height rows for game titles (top-aligned 2-line box), version/size metadata, and configuration badge tags.
- **Cover Overlay Badges**: Enhanced readability of "Switch 2" and update badges over game cover art with an ultra-thin frosted glass pill background and drop shadow.

## [1.3.0] – 2026-11-17

### Added
- **Large Cover Grid View for "My Games" (`LibraryView`)**:
  - Seamless toggle in the toolbar between traditional List View and rich Cover Grid View (`GameCoverCardView`).
  - High-resolution artwork loading directly from app bundles (`cover.jpg`, `cover.png`, or full 1024×1024 `AppIcon.icns`).
  - Interactive hover actions: instant Play button overlay, Settings shortcut, and update badges directly on the cover.
  - Three customizable cover sizes: Small (130 px), Medium (175 px), and Large (230 px).
  - Context menu and double-click to launch fully preserved in Grid View.

## [1.2.2] – 2026-11-17

### Changed
- **Redesigned Single Game Builder ("Spiel bauen")**:
  - Removed duplicate and cluttered batch import list from the single game builder, replacing it with an unobtrusive, one-line banner pointing to Batch Import when pending games exist.
  - Replaced redundant separate path textfield and drop box with a unified drag-and-drop & browse card that converts into an informative Game Card once a source is selected.
  - Removed persistent `prod.keys` section when keys are already configured; replaced with a context-sensitive missing keys warning only when keys are required and missing.
  - Moved target platform selector (`macApp` vs `macDev`) into collapsible Advanced Options.
  - Added a prominent primary **"Spiel jetzt bauen (⌘R)"** button directly on the page with clear validation feedback.

## [1.2.1] – 2026-11-17

### Added
- Crystal-clear differentiation and localized descriptions for **Window Upscaling (Presentation)** (`DM_PRESENT_UPSCALE`) and **Game's Internal Upscaler** (`DM_UPSCALER`) in the Game Settings sheet.
- Complete German and English localization for all standard nxnative runtime settings and choices in the launcher settings list.
- Direct link and button in Game Settings to reveal and edit `env.txt` in Finder when settings are pinned.

### Fixed
- Direct update and recompile actions now automatically update and replace the installed `.app` bundle in `~/NXNative/Games/` upon build completion, ensuring the library immediately reflects the updated build.

## [1.2.0] – 2026-11-17

### Added
- One-click build folder cleanup (`<titleId>_build`) after successful builds and inside the game status sheet to safely free storage space (up to tens or hundreds of gigabytes) while keeping original NSP archives.
- Direct game update and recompile actions in the library, game status inspector, and settings sheet.
- Intelligent pre-flight check determining whether shaders must be recompiled or if a fast App Update is sufficient (preserving cached shaders).
- `GameSourceLocator` for automatic detection of game source archives (.nsp) and build folders (`<titleId>_build`).
- Filter options for App Updates, Recompilations, and All Updates in the game library.

## [1.1.0] – 2026-11-15

### Added
- Switch 2 games: build from a `.nup` file or a dump folder (`base/`, `updates/`, `dlc/`) in the builder and the batch import, without prod.keys; a dropped `.nup` file is built itself, and dumps without `base/` are recognized.
- Switch 2 games as NSP/XCI are recognized and marked as not buildable yet, with a hint to use a `.nup` file or dump folder.
- "Switch 2" badge in the library, the import list and the builder; warning when a Switch 2 game has no nxnative profile.
- The Build Game overview lists the games in the Import folder, with checkboxes, refresh, Show in Finder and Move to Trash (asks first; not while a build runs).
- Option in the batch import to move source files to the Trash after a successful conversion.
- Setup check: the Metal compiler version is compared with nxnative's `dmsh_chain.lock`.
- Save sync between Astris and nxnative in the game settings, with verified backups of both sides and automatic sync after a tested approval.

### Changed
- Batch import keeps the source files (NSP / XCI / NUP) in the Import folder by default.
- After a build, the Hub opens or moves exactly the app the build announced, not any `.app` in the game folder.
- Save import replaces the save as a whole; the current save is kept as `save_backup_<time>`, and nothing changes if that backup fails. Import is refused while the game runs and warns when the game syncs with a cloud saves folder.
- The game language for builds offers every code nxnative takes (`en-US`, `en-GB`, `fr-CA`, `es-419`, `pt-BR`, `ru`, …); a saved `en` becomes `en-US`.
- The setup check follows current nxnative: Xcode 27.2, the Python packages `zbic` and capstone 5.x, and no .NET SDK (nx_extract is a native tool since nxnative 641636e2; the updater no longer rebuilds it).
- A missing prod.keys is a setup warning instead of a blocking issue; NSP/XCI builds still require it.
- The setup sheet opens by itself at launch only for missing prerequisites it has not shown before.

### Fixed
- Importing from Ryujinx could pick a device save instead of the user's own save.

## [1.0.0] – 2026-10-31

### Initial Release

**NXNative Hub** – Native macOS companion app and management suite for [nxnative](https://github.com/seedds/nxnative) on Apple Silicon.

#### Features
- **Centralized Game Library**:
  - Management of converted native macOS applications with version, size, build commit, and active configuration badges.
  - Real-time search by game name and 16-character Title ID.
  - Direct launch via double-click or `⌘↩`.
  - Option to bypass the internal game settings window at launch (`DM_LAUNCHER=0` / `--no-launcher`) with global and per-game toggles, preserving the Option key (`⌥`) manual escape hatch.
  - Context menu actions: Open Game Log, Open Previous Launch Log, Open in Finder, and Create Bug Report.

- **Game Builder & Batch Import**:
  - Convert Nintendo Switch game dumps (`.nsp` / `.xci`) into standalone Apple Silicon applications (`.app`).
  - Real-time compilation tracking with stage progression, integer percentage, and streaming log output.
  - Disk space estimation comparing required storage against free disk space.
  - Incremental rebuild detection (`<titleID>_build`) for faster subsequent builds.
  - Batch import converting all queued dumps in `~/NXNative/Import` with pre-flight game profile verification.
  - Non-destructive workflow: source dump files are moved to the system Trash upon completion.

- **Configuration Engine**:
  - Dynamic form generation parsing the game's native `launcher.json` manifest.
  - Granular control over frame rate limits, handheld/docked mode, render scale multipliers, MetalFX upscaling, Metal HUD, and frame buffering.
  - Audio and haptic settings with adjustable rumble gain sliders.
  - Per-game runtime language overrides.
