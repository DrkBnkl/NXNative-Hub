# NXNative Hub

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

A native macOS companion app for [nxnative](https://github.com/seedds/nxnative): convert Nintendo Switch game dumps into native Apple Silicon apps, then manage and launch them from one library. The UI is available in English and German.

## Features

- **Library** – all converted games with version, size and current settings; search, double-click to play.
- **Builder** – build a single game as a Mac app or an unsigned IPA, with live progress and log.
- **Batch import** – convert every game in `~/NXNative/Import` in one go, with a compatibility check against the nxnative game profiles.
- **Per-game settings** – frame rate, docked/handheld, MetalFX upscaling, full screen, Metal HUD, rumble, language (`env.txt`).
- **Save import** – from JKSV, Checkpoint or Ryujinx; the existing save is backed up first.
- **Updater** – pull the latest nxnative commits and game profiles from within the app.
- **Setup check** – detects missing prerequisites and fixes most of them with one click.

## Requirements

- Apple Silicon Mac with macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10 or later (e.g. `brew install python`)
- `prod.keys` dumped from your own Nintendo Switch

## Installation

**1. Install nxnative**

```bash
git clone https://github.com/seedds/nxnative ~/NXNative/nxnative
cd ~/NXNative/nxnative
python3 -m venv venv
venv/bin/pip install lz4 capstone fonttools zstandard
```

See the nxnative documentation for further requirements. A different location can be selected in **Settings → General → nxnative**.

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

## Documentation

- [CHANGELOG.md](CHANGELOG.md) – release history
- [CONTRIBUTING.md](CONTRIBUTING.md) – conventions, build, release
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – code structure and data flow
- [docs/TESTING.md](docs/TESTING.md) – manual test checklist

## Legal

NXNative Hub is a front end only. It does not contain or distribute Nintendo software, games, ROMs or keys. Use only game dumps and keys from hardware you own. Nintendo Switch is a trademark of Nintendo Co., Ltd.; this project is not affiliated with or endorsed by Nintendo.

## License

[MIT](LICENSE)
