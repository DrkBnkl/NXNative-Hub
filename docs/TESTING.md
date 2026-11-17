# Quality Assurance & Manual Test Plan

This checklist outlines the manual test matrix to verify application stability, upstream integration, and UI fidelity before tagging a release.

---

## 1. Launch & Environment Setup

- [ ] **First Run**: Without `nxnative` installed, launching the app presents the setup checklist automatically.
- [ ] **Fully Provisioned**: With all dependencies installed, the app launches cleanly into the Library without blocking sheets.
- [ ] **Virtual Environment**: Clicking **Create venv** creates `~/NXNative/nxnative/venv` and updates status to green.
- [ ] **Package Provisioning**: Clicking **Install** for Python dependencies installs required wheels into the virtual environment.
- [ ] **Toolchain Inspection**: The checklist validates macOS, Xcode, Metal toolchain, Homebrew tools (`xcodegen`, `zstd`, `glslang`), and Python ≥ 3.12.
- [ ] **Keys Verification**: Choosing an empty or corrupted text file as `prod.keys` is flagged as incomplete; builds are prevented until valid keys are selected.
- [ ] **Custom Path**: Setting a custom path under **Settings → General → nxnative** persists across launches; clicking **Automatic** restores default.

---

## 2. Navigation, Shortcuts & Localization

- [ ] **Navigation Shortcuts**: `⌘1` navigates to Library, `⌘2` navigates to Builder, and `⌘,` opens Settings.
- [ ] **Instant Language Switching**: Toggling between German and English in Settings updates all views, menus, sheets, and badges without restarting the application.
- [ ] **Window Layout**: Split view resizing and window states persist across restarts.

---

## 3. Game Library & Execution

- [ ] **Catalog Display**: Installed titles correctly display title icons, resolved game names, versions, file sizes, and status badges.
- [ ] **Search & Filtering**: Searching by name or 16-character Title ID filters the library instantly.
- [ ] **Direct Launching**: Double-clicking an item or pressing `⌘↩` launches the application.
- [ ] **Launcher Window Bypass**:
  - With **Skip Game Start Window** enabled, launching starts the game immediately without showing the nxnative configuration dialog.
  - Holding the Option key (`⌥`) while launching forces the start window to appear.
- [ ] **Context Menu Operations**:
  - **Open Game Log** / **Open Previous Launch Log** open the corresponding `.log` files in Console.
  - **Create Bug Report…** packages game logs, system specifications, and configuration into `~/NXNative/Reports/` and reveals it in Finder.

---

## 4. Game Configuration & Persistence

- [ ] **Modern Builds (`launcher.json`)**:
  - Displays the game's native sections, labels, and default choices.
  - Toggling **Show All Settings** reveals advanced configurations.
  - Sliders (e.g. Rumble gain) react dynamically to dependencies (Rumble toggle).
  - Saving persists only modified choices to `~/Library/Preferences/org.nxnative.<titleID>.plist` without overriding tested profiles.
- [ ] **Legacy Builds**:
  - Legacy configuration form reads from and writes to `~/Library/Application Support/nxnative/<TitleID>/env.txt`.
- [ ] **Save Import**:
  - Importing a save folder creates an automatic backup in `save_backup_<timestamp>` before writing new save data.
  - Opening the save directory in Finder reveals the correct per-game path.

---

## 5. Recompilation & Update Intelligence

- [ ] **Status Badges & Intelligence**: Library items display accurate update status (Up-to-Date, App Update Available, Recompile Recommended).
  - Verifies whether shaders actually need to be recompiled (due to shader chain changes or shader profile file modifications) or if an App Update is sufficient.
  - Distinguishes fast App Updates (blue badge, host/engine changes without shader recompile) from full Recompilation (orange badge, shader chain or shader table mismatch).
- [ ] **Status Inspector**: Clicking a status badge opens the detailed breakdown showing upstream engine commit differences, shader chains, shader status, and profile revisions.
- [ ] **Direct Update**: Status inspector and game rows directly offer "App jetzt aktualisieren" / "Jetzt neu kompilieren", which automatically resolves the game's source/build directory and starts the build with live progress.
- [ ] **Filter Integration**: The library filter allows filtering titles specifically by App Updates, Recompilation, or All Updates.
- [ ] **Storage Reclamation in Status Sheet**: Displays the exact size of any existing intermediate `<titleID>_build` directory and allows safely moving it to the system Trash with one click while retaining the permanent source `.nsp`.

---

## 6. Single Game Builder

- [ ] **File Inspection**: Selecting or dropping a folder populates the detected files, Title ID, estimated build size, and free disk space.
- [ ] **Incremental Build Detection**: If an existing `<titleID>_build` directory exists, the app displays the accelerated rebuild indicator.
- [ ] **Execution**: Starting a build (`⌘R`) displays live stage progress, percentage, and streaming log lines.
- [ ] **Post-Build Storage Cleanup**: Upon successful build completion, both the Builder view and Live Log sheet present a cleanup banner displaying the exact size of `<titleID>_build` with a one-click option to move it to the macOS Trash.
- [ ] **Cancellation**: Clicking **Cancel** halts child processes cleanly without leaving zombie build tasks.
- [ ] **Error Handling**: Build failures extract the relevant diagnostic error line and offer **Open Build Logs**.

---

## 7. Batch Import

- [ ] **Directory Processing**: Opening batch import (`⇧⌘I`) catalogs all `.nsp`/`.xci` files in `~/NXNative/Import`.
- [ ] **Confirmation**: Requires explicit user confirmation before converting queued games.
- [ ] **Success & Cleanup**: Successfully converted games are placed into `~/NXNative/Games/`; processed source archives are safely moved to the Trash.
- [ ] **Interruption**: Cancelling a batch allows the active game to complete or safely terminate, leaving remaining files untouched.
