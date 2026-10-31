# Contributing

## Requirements

- Apple Silicon Mac, macOS 14+, Xcode Command Line Tools (Swift 5.9+) – enough to build the Hub; building games needs nxnative's requirements (see README).
- No Xcode project: `./build.sh` compiles every `.swift` file under `Sources/` with `swiftc`.

## Build and run

```bash
./build.sh                    # → ~/NXNative/NXNative.app
./build.sh path/to/App.app    # custom destination
```

Before opening a pull request, build the app and run the relevant parts of [docs/TESTING.md](docs/TESTING.md).

## nxnative interface

Talk to nxnative only through what its `docs/frontends.md` documents: the build script's `--progress json` events and exit codes, `launcher.json`, the `env.txt` order and the saved choices. Do not parse human-readable log lines as an interface.

## Conventions

**Language**
- Code, comments, commit messages and documentation are written in English.
- The UI is bilingual. Every user-visible string uses `tr("German", "English")` (`Sources/Core/Localization.swift`).
- German literals outside `tr()` are allowed only as data for backward compatibility, with a comment explaining why.

**Code**
- Views contain no file or process logic; it belongs in `Sources/Managers` or `Sources/Core`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Resolve paths through `NXPaths`. Run external tools through `CommandRunner` or `StreamingProcess` with argument arrays – never a shell string.
- Never delete user data permanently; move it to the Trash.

**UI** – follow the [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/): system controls and button styles, toolbar for actions, grouped forms for settings, `ContentUnavailableView` for empty states, semantic fonts, no emoji in controls, accessibility labels for icon-only buttons, confirmation before destructive actions.

## Changes and releases

- Add every user-facing change to [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]` (Added, Changed, Deprecated, Removed, Fixed, Security).
- Versions follow [Semantic Versioning](https://semver.org/).
- To release: set `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, move the `[Unreleased]` entries to a new version heading with the date, build, then run `./create_release.sh` and tag the commit (`vX.Y.Z`).
