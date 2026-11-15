# NXNative Hub

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

A native macOS companion app for [nxnative](https://github.com/seedds/nxnative): convert Nintendo Switch game dumps into native Apple Silicon apps, then manage and launch them from one library. The UI is available in English and German.

## Features

- **Library** – all converted games with version, size and current settings; search, double-click to play.
- **Builder** – build a single game as a Mac app or an unsigned IPA, with live progress and log.
- **Batch import** – convert every game in `~/NXNative/Import` in one go, with a compatibility check against the nxnative game profiles.
- **Per-game settings** – drawn from each game's own settings list (`launcher.json`) and saved as the game's saved choices, the same ones its own settings window uses.
- **Save import** – from JKSV, Checkpoint or Ryujinx; the imported save replaces the current one, which is kept as a backup.
- **Updater** – pull the latest nxnative commits and game profiles from within the app.
- **Setup check** – detects missing prerequisites and fixes most of them with one click.

## Requirements

- Apple Silicon Mac; the Hub runs on macOS 14 or later, building games needs macOS 26.6 or later
- Xcode 27.2, selected with `sudo xcode-select -s /Applications/Xcode.app`, and its Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`)
- Homebrew tools: `brew install zstd glslang xcodegen` (xcodegen only for IPA builds)
- Python 3.12 or later, arm64 (e.g. `brew install python`)
- `prod.keys` dumped from your own Nintendo Switch (not needed for Switch 2 games as `.nup` or dump folder)

## Installation

**1. Install nxnative**

```bash
git clone https://github.com/seedds/nxnative ~/NXNative/nxnative
cd ~/NXNative/nxnative
python3 -m venv venv
venv/bin/pip install lz4 "capstone>=5,<6" fonttools nsz zbic "backports.zstd; python_version < '3.14'"
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
| Convert a single game | **Build Game** → choose the folder with the `.nsp`/`.xci` files, or a Switch 2 `.nup` file or dump folder → **Build** (⌘R) |
| Convert several games | Put them into `~/NXNative/Import` → **Game → Open Game Import…** (⇧⌘I) |
| Change game settings | Select a game → **Game Settings** (⌘I) |
| Launch a game | Double-click it or press ⌘↩ |
| App settings | App menu → **Settings…** (⌘,) |

Source files stay in the Import folder by default; optionally they are moved to the Trash after a successful conversion, never deleted permanently.

## Directories

| Path | Purpose |
|---|---|
| `~/NXNative/nxnative` | nxnative (default location) |
| `~/NXNative/Games` | Converted games |
| `~/NXNative/Import` | Games waiting for batch conversion |
| `~/Library/Application Support/nxnative/<TitleID>/` | saves and an optional `env.txt` per game (expert overrides; they win over the settings) |
| `~/Library/Preferences/<bundle ID>.plist` | each game's saved choices (`launcher.<ENV>`), written by the Hub and by the game's own settings window |

## Documentation

- [CHANGELOG.md](CHANGELOG.md) – release history
- [CONTRIBUTING.md](CONTRIBUTING.md) – conventions, build, release
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – code structure and data flow
- [docs/TESTING.md](docs/TESTING.md) – manual test checklist

## Legal

NXNative Hub is a front end only. It does not contain or distribute Nintendo software, games, ROMs or keys. Use only game dumps and keys from hardware you own. Nintendo Switch is a trademark of Nintendo Co., Ltd.; this project is not affiliated with or endorsed by Nintendo.

## License

[MIT](LICENSE)
