# NXNative Hub

[![Build](https://github.com/DrkBnkl/NXNative-Hub/actions/workflows/build.yml/badge.svg)](https://github.com/DrkBnkl/NXNative-Hub/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/DrkBnkl/NXNative-Hub?color=blue&logo=github)](https://github.com/DrkBnkl/NXNative-Hub/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20%7C%20Apple%20Silicon-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

**NXNative Hub** is a dedicated, native macOS companion app and management suite for [nxnative](https://github.com/seedds/nxnative). It simplifies transforming Nintendo Switch game dumps into standalone Apple Silicon applications, providing centralized library management, granular game configurations, batch importing, and automated environment diagnostics.

The interface is fully localized in **English** and **German**.

---

## Key Features

### 🎮 Centralized Game Library
- **Catalog & Overview**: View all converted titles with application version, file size, build details, and active runtime configuration.
- **Instant Launch**: Double-click or press `⌘↩` to launch titles immediately.
- **Direct Launch Option**: Skip the internal settings window at launch (`--no-launcher` / `DM_LAUNCHER=0`) with global and per-game toggles, while retaining optional Option-key (`⌥`) invocation.
- **Save Management**: Import game saves from JKSV, Checkpoint, or Ryujinx with automated timestamped backups.

### 🔨 Native macOS Builder & Batch Converter
- **Single Game Builder**: Convert `.nsp` and `.xci` dumps into native macOS `.app` bundles with real-time build progress and live log output.
- **Batch Import**: Automatically queue and process multiple titles placed in `~/NXNative/Import` with pre-flight game profile verification.
- **Smart Rebuild Detection**: Detects existing build artifacts (`<titleID>_build`) to accelerate subsequent compilations and warns about insufficient storage.
- **Safety First**: Source dump files are moved to the system Trash upon successful processing, never permanently deleted.

### ⚙️ Deep Configuration Engine
- **Native Game Settings**: Dynamically parses the game's internal `launcher.json` (supported in modern nxnative builds) to render native macOS preferences.
- **Performance & Display**: Adjust frame rate limits, handheld/docked operating modes, render scale multipliers, MetalFX upscaling, Metal HUD, and frame buffering.
- **Audio & Haptics**: Full controller rumble toggle with adjustable gain sliders.
- **Language Selection**: Configure per-game runtime language overrides independently from system defaults.
- **Non-Destructive Storage**: Persists user customizations as macOS preferences (`saved_choices`) without overriding tested default profiles.

### 🔄 Update & Recompile Intelligence
- **Per-Game Update Indicators**: Real-time indicators alert you when an installed game would benefit from recompilation due to:
  - Upstream nxnative engine updates
  - Updated game compatibility profiles
  - Shader translation chain improvements
- **In-App Updater**: Fetch upstream git updates, Python virtual environment packages, and toolchain dependencies directly from within the app.

### 🩺 Environment & Toolchain Diagnostics
- **Automated Setup Check**: Verifies the host environment (Xcode, Metal toolchain, Apple Silicon Homebrew tools, .NET SDK, Python 3.12+, and `prod.keys`).
- **One-Click Remediation**: Resolves missing prerequisites and installs toolchain components with a single click.
- **Crash & Diagnostic Logging**: Direct access to current launch logs, previous launch logs, build failure diagnostics, and automated bug report packaging.

---

## Requirements

### Host Application
- **Operating System**: macOS 14.0 (Sonoma) or later
- **Architecture**: Apple Silicon (M1/M2/M3/M4 series)

### Build Toolchain (for compiling games)
- Apple Silicon Mac running macOS 26.6 or later
- Xcode 27.1 (or Xcode with Metal Toolchain component)
- Homebrew (arm64) with `xcodegen`, `zstd`, and `glslang`
- .NET SDK (via Homebrew cask `dotnet-sdk` or standard installer)
- Python 3.12 or newer
- Valid `prod.keys` extracted from your personal Nintendo Switch console

---

## Installation & Setup

### 1. Toolchain Setup (Prerequisites)

You can allow NXNative Hub to install missing prerequisites automatically via **Help → Check Setup…**, or manually configure them via Terminal:

```bash
# Install toolchain components
xcodebuild -downloadComponent MetalToolchain
brew install xcodegen zstd glslang
brew install --cask dotnet-sdk

# Clone and prepare nxnative
git clone https://github.com/seedds/nxnative ~/NXNative/nxnative
cd ~/NXNative/nxnative
python3 -m venv venv
venv/bin/pip install lz4 capstone fonttools nsz "backports.zstd; python_version < '3.14'"
```

### 2. Building NXNative Hub from Source

NXNative Hub requires no complex project generation and builds directly via the included script:

```bash
git clone https://github.com/DrkBnkl/NXNative-Hub.git
cd NXNative-Hub
./build.sh                       # Outputs to ~/NXNative/NXNative.app
./build.sh /Applications/NXNative.app # Or to Applications
```

> **Note on Gatekeeper**: Local builds use ad-hoc code signing. If macOS Gatekeeper prevents opening the app, right-click `NXNative.app` and choose **Open**, or run:
> ```bash
> xattr -cr /path/to/NXNative.app
> ```

---

## Quick Reference

| Action | Shortcut / Path | Description |
|---|---|---|
| **Switch to Library** | `⌘1` | Navigate to installed games catalog |
| **Switch to Builder** | `⌘2` | Open single game compilation view |
| **Open Settings** | `⌘,` | Configure app preferences and paths |
| **Launch Selected Game** | `⌘↩` / Double Click | Start game with saved configuration |
| **Game Settings** | `⌘I` | Open per-game graphics, control, and launch settings |
| **Batch Import** | `⇧⌘I` | Convert queued dumps in `~/NXNative/Import` |
| **Build Current Title** | `⌘R` | Start compilation in the Builder |
| **Check Environment** | **Help → Check Setup…** | Inspect prerequisites and dependency health |

---

## Standard Directories

| Path | Purpose |
|---|---|
| `~/NXNative/nxnative` | Upstream nxnative repository and virtual environment |
| `~/NXNative/Games` | Installed, playable native macOS applications |
| `~/NXNative/Import` | Target folder for batch compilation |
| `~/Library/Application Support/nxnative/<TitleID>/` | Game configuration (`env.txt`) and save game data |
| `~/Library/Logs/nxnative/<TitleID>.log` | Runtime log generated during the most recent execution |
| `~/NXNative/Reports` | Generated issue diagnostics and bug report archives |

---

## Project Documentation

- [CHANGELOG.md](CHANGELOG.md) – Version history and semantic releases.
- [CONTRIBUTING.md](CONTRIBUTING.md) – Coding conventions, architecture guidelines, and release procedures.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – Structural design, manager layer, and data flow.
- [docs/TESTING.md](docs/TESTING.md) – Pre-release quality assurance and manual test plan.

---

## Legal & Compliance Notice

NXNative Hub is an independent, open-source front-end management utility. It does not contain, distribute, or circumvent proprietary software, copyrighted game dumps, ROMs, or cryptographic keys. Users are exclusively responsible for obtaining their own keys (`prod.keys`) and software dumps from physical consoles and games they legitimately own.

*Nintendo Switch is a registered trademark of Nintendo Co., Ltd. NXNative Hub is an independent project and is neither affiliated with, maintained by, nor endorsed by Nintendo Co., Ltd.*

---

## License

This project is licensed under the [MIT License](LICENSE).
