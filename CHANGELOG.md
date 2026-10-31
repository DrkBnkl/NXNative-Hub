# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/).

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
  - Persistence via macOS preferences (`saved_choices`) without overriding tested profile defaults.
  - Legacy `env.txt` support for older nxnative builds.

- **Update & Recompilation Intelligence**:
  - Per-game update indicators evaluating installed titles against upstream engine commits, profile updates, and shader translation chain improvements.
  - Interactive status sheet detailing commit differences, shader versions, and recompilation recommendations.
  - In-app updater for upstream nxnative repository, Python packages, and toolchain dependencies.

- **Environment Diagnostics & Save Management**:
  - Automated setup checklist verifying macOS version, Xcode, Metal toolchain, Homebrew utilities, .NET SDK, Python 3.12+, and `prod.keys`.
  - One-click installation and remediation for missing dependencies.
  - Save game import supporting JKSV, Checkpoint, and Ryujinx archives with automated timestamped backups.

- **User Interface & Automation**:
  - Full bilingual localization in German and English with instantaneous runtime switching.
  - Apple Human Interface Guidelines compliant SwiftUI interface.
  - Automated GitHub Actions CI workflow building and packaging releases on Apple Silicon runners (`macos-15`).
