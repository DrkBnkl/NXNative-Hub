# Contributing Guidelines

Thank you for your interest in contributing to **NXNative Hub**. This document outlines our development workflow, architectural conventions, coding style, and release processes.

---

## Prerequisites & Development Setup

- **Hardware & OS**: Apple Silicon Mac running macOS 14.0 or newer.
- **Developer Tools**: Xcode Command Line Tools (Swift 5.9+) or full Xcode.
- **Direct Build Pipeline**: NXNative Hub does not require an `.xcodeproj` file. The entire project compiles cleanly via Swift's standalone compiler:

```bash
# Build to standard output location (~/NXNative/NXNative.app)
./build.sh

# Or build to a specific target path
./build.sh ./NXNative.app
```

---

## Architectural & Coding Conventions

### 1. Separation of Concerns
- **Views**: SwiftUI views (`Sources/Views/`) must contain UI layout and user interaction logic only. File I/O, process handling, and background calculations must reside in `Sources/Managers/` or `Sources/Core/`.
- **Paths & Files**: Always resolve paths through `NXPaths`. Never hardcode user paths or assume fixed system directories.
- **Data Protection**: User data is never deleted permanently without confirmation; discarded files and import remnants must be moved to the Trash via `FileManager.trashItem(at:resultingItemURL:)`.

### 2. Process Safety
- Always invoke external executables via `CommandRunner` or `StreamingProcess` using **argument arrays** (`[String]`). Never execute raw shell strings through `/bin/sh` or `/bin/zsh`.

### 3. Upstream Protocol Compliance
- Interact with `nxnative` strictly through documented interfaces:
  - CLI build progress: `--progress json` events and semantic exit codes.
  - Configuration schema: `launcher.json` (Schema 1).
  - Runtime environment: `env.txt` and macOS `saved_choices`.
- Avoid scraping or pattern-matching unstructured console text.

### 4. Bilingual Localization
- User-facing text must support both **German** and **English**.
- Wrap all display strings in `tr("German Text", "English Text")` (`Sources/Core/Localization.swift`).
- Internal identifiers, comments, log messages, and git commits must remain in English.

### 5. UI Guidelines
- Strictly adhere to Apple's [Human Interface Guidelines (HIG)](https://developer.apple.com/design/human-interface-guidelines/):
  - Use system-provided controls, semantic typography, and standard button placements.
  - Employ `ContentUnavailableView` for empty states.
  - Avoid emoji icons within buttons or form controls.
  - Provide `.accessibilityLabel` for icon-only toolbar items.

---

## Quality Assurance & Verification

Before opening a pull request or tagging a release:
1. Verify clean compilation: `./build.sh` (ensure exit code 0 and zero warnings).
2. Execute the verification steps detailed in [docs/TESTING.md](docs/TESTING.md).
3. Ensure automated GitHub Actions workflows pass cleanly on macOS Apple Silicon runners.

---

## Release Procedure

Releases follow [Semantic Versioning (SemVer)](https://semver.org/):

1. **Update Documentation**:
   - Move relevant items from `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) to a versioned release section (`## [X.Y.Z] – YYYY-MM-DD`).
2. **Version Bump**:
   - Increment `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
3. **Build & Package**:
   - Run `./create_release.sh` to package the signed distribution zip.
4. **Git Tagging & Push**:
   - Commit changes, push to `main`, and create an annotated git tag (`git tag -a vX.Y.Z -m "Release vX.Y.Z"`).
   - Push tags (`git push origin vX.Y.Z`) to trigger automated GitHub Actions release packaging.
