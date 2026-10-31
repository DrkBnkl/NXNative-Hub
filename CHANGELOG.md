# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] – 2026-10-31

### Added
- Indicator for installed games showing whether an nxnative update is available and whether recompilation is recommended (profile changes, shader chain updates, engine commits), with interactive status sheet, tooltips, and library filter.
- Game settings come from the game itself (`launcher.json` of current nxnative builds): its own rows, sections, defaults and sub-settings, basic rows first with "Show All Settings", render scale with the resulting resolution. Older builds keep the previous form.
- Notifications when a build or batch import finishes while the app is in the background (Settings → General).
- Builder shows the free disk space against the space a build needs, and a hint when a previous build will be reused.
- "Open Build Logs" after a failed build; "Open Game Log", "Open Log of Previous Launch" and "Create Bug Report…" for games in the library.
- Setup check for macOS 26.6, Xcode 27.1, the Metal toolchain, the Homebrew tools (xcodegen, zstd, glslang) with one-click install, the .NET SDK (also the Homebrew cask), Python 3.12 and the contents of prod.keys.

### Changed
- Game settings are saved as the game's saved choices – only changes from the tested defaults – so the game's own launch window shows the same values.
- Library badges show the values the game actually uses.
- "Keep extracted data" is on by default and passed explicitly in both directions; batch imports no longer keep extracted data.
- Python packages follow nxnative: `backports.zstd` (before Python 3.14) and `nsz` replace `zstandard`.

### Fixed
- Saving game settings no longer pins every value in `env.txt` over the game's tested defaults; values written by 1.1.0 are moved to the saved choices on the next save.
- Failed builds show the reason (last error message or stderr) instead of only the exit code; cancelled builds are no longer reported as failed.

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
