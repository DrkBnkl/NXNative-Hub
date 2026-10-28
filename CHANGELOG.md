# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Setup check matches nxnative's requirements: full Xcode, Homebrew `xcodegen` and `zstd`, .NET SDK 10, Python 3.12+ with `backports.zstd` (instead of `zstandard`).
- The venv is optional: `python3` from the PATH is used if the nxnative folder has none. Without a venv, missing packages are installed into a new one.
- Missing Homebrew tools can be installed from the setup check.
- The updater no longer rebuilds `nx_extract` (the build script does) and updates Python packages only inside a venv.

### Fixed
- `DOTNET_ROOT` was forced to `~/.dotnet`, which broke builds with .NET installed via Homebrew.
- "Keep extracted data" turned off had no effect.

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
