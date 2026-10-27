# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
