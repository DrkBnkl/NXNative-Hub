# NXNative Hub

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

A native macOS companion app for [nxnative](https://github.com/seedds/nxnative): convert Nintendo Switch game dumps into native Apple Silicon apps, then manage and launch them from one library. The UI is available in English and German.

## Features

- **Library** – all converted games with version, size and current settings; search, double-click to play.
- **Builder** – build a single game as a native Mac app (.app), with live progress and log.
- **Batch import** – convert every game in `~/NXNative/Import` in one go, with a compatibility check against the nxnative game profiles.
- **Per-game settings** – the game's own settings list (frame rate, console mode, render scale, upscaling, rumble, language …), saved like the game's own launch window does; older builds use `env.txt`.
- **Save import** – from JKSV, Checkpoint or Ryujinx; the existing save is backed up first.
- **Updater** – pull the latest nxnative commits and game profiles from within the app.
- **Setup check** – detects missing prerequisites (Xcode, Metal toolchain, Homebrew tools, .NET, Python, prod.keys) and fixes most of them with one click.
- **Diagnostics** – clear error messages for failed builds, build and game logs, bug reports for nxnative issues, notifications when long builds finish.

## Requirements

NXNative Hub itself runs on macOS 14 or later. Building games with nxnative needs:

- Apple Silicon Mac with macOS 26.6 or later
- Xcode 27.1 with its Metal toolchain, [Homebrew](https://brew.sh) (arm64) and the .NET SDK
- Python 3.12 or later (e.g. `brew install python`)
- `prod.keys` dumped from your own Nintendo Switch

## Installation

**1. Install nxnative**

```bash
xcodebuild -downloadComponent MetalToolchain
brew install xcodegen zstd glslang
brew install --cask dotnet-sdk
git clone https://github.com/seedds/nxnative ~/NXNative/nxnative
cd ~/NXNative/nxnative
python3 -m venv venv
venv/bin/pip install lz4 capstone fonttools nsz "backports.zstd; python_version < '3.14'"
```

The setup check in the app (**Help → Check Setup…**) can do most of these steps for you. See the nxnative documentation for details. A different location can be selected in **Settings → General → nxnative**.

**2. Build NXNative Hub**

```bash
git clone https://github.com/DrkBnkl/NXNative-Hub.git
cd NXNative-Hub
./build.sh                       # → ~/NXNative/NXNative.app
./build.sh /Applications/NXNative.app
```

On first launch the setup check verifies the installation (also available under **Help → Check Setup…**).

> Builds are signed ad hoc. If Gatekeeper blocks the app, right-click it and choose **Open**, or run `xattr -cr /path/to/NXNative.app`.

## Usage

| Task | How |
|---|---|
| Convert a single game | **Build Game** → choose the folder with the `.nsp`/`.xci` files → **Build** (⌘R) |
| Convert several games | Put them into `~/NXNative/Import` → **Game → Open Game Import…** (⇧⌘I) |
| Change game settings | Select a game → **Game Settings** (⌘I) |
| Investigate a crash | Context menu → **Open Game Log** or **Create Bug Report…** |
| Launch a game | Double-click it or press ⌘↩ |
| App settings | App menu → **Settings…** (⌘,) |

Converted source files are moved to the Trash, never deleted permanently.

## Directories

| Path | Purpose |
|---|---|
| `~/NXNative/nxnative` | nxnative (default location) |
| `~/NXNative/Games` | Converted games |
| `~/NXNative/Import` | Games waiting for batch conversion |
| `~/Library/Application Support/nxnative/<TitleID>/` | `env.txt` and saves per game |
| `~/Library/Logs/nxnative/<TitleID>.log` | Game log of the last launch |
| `~/NXNative/Reports` | Bug reports created from the library |

## Documentation

- [CHANGELOG.md](CHANGELOG.md) – release history
- [CONTRIBUTING.md](CONTRIBUTING.md) – conventions, build, release
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – code structure and data flow
- [docs/TESTING.md](docs/TESTING.md) – manual test checklist

## Legal

NXNative Hub is a front end only. It does not contain or distribute Nintendo software, games, ROMs or keys. Use only game dumps and keys from hardware you own. Nintendo Switch is a trademark of Nintendo Co., Ltd.; this project is not affiliated with or endorsed by Nintendo.

## License

[MIT](LICENSE)
