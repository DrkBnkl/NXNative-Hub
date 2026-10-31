# Manual Test Checklist

There are no automated tests. Before a release – or after changes to the affected area – build with `./build.sh` and check the following.

## Launch and setup
- [ ] Without nxnative, the setup sheet opens at launch; with a complete installation it does not.
- [ ] "Create venv" and "Install" (Python packages) succeed and the checks turn green.
- [ ] The checklist shows macOS, Xcode (warning below 27.1, missing with only the Command Line Tools), the Metal toolchain, the Homebrew tools, .NET and Python ≥ 3.12.
- [ ] "Install" (Homebrew tools) and "Download" (Metal toolchain) run and the checks turn green.
- [ ] A text file chosen as prod.keys is reported as incomplete; a build with it stops before starting.
- [ ] Settings → General → nxnative: a custom folder is used; choosing `~/NXNative` resolves to `~/NXNative/nxnative`; "Automatic" restores the default.
- [ ] Help → Check Setup… opens the checklist; the sidebar hint disappears once everything is ready.

## Navigation and language
- [ ] ⌘1 / ⌘2 switch between Library and Build Game; ⌘, opens Settings.
- [ ] Switching the language updates the main window, menus and Settings immediately.

## Library
- [ ] Games show icon, size, version and badges; search filters by name and title ID.
- [ ] Double-click / ⌘↩ launches; the context menu works.
- [ ] Game with `launcher.json` (current build): the settings sheet shows the game's own rows and sections; "Show All Settings" reveals the non-basic rows; "Rumble strength" appears only while rumble is on; render scale shows the resulting resolution.
- [ ] Saving writes only changed values: `defaults read org.nxnative.<title id>` lists `launcher.*` keys for them; "Restore Defaults" + Save removes them. The game's own settings window shows the same values.
- [ ] An `env.txt` written by Hub 1.1.0 is announced in the sheet; after saving, the listed keys are gone from `env.txt`, custom entries are kept, and an otherwise empty `env.txt` is in the Trash.
- [ ] Older game without `launcher.json`: the legacy form saves `env.txt` and keeps custom entries.
- [ ] Library badges match the values the game uses (also after changing them in the game's own window).
- [ ] Context menu: "Open Game Log" / "Open Log of Previous Launch" are enabled only when the log exists; "Create Bug Report…" puts a zip into `~/NXNative/Reports` and reveals it.
- [ ] Dropping an `.app` or a folder adds it; both can be removed in Settings → Library.

## Builder
- [ ] Choosing or dropping a folder lists the detected game files, the free disk space and – if a `<title ID>_build` folder exists – the faster-rebuild hint.
- [ ] Build (⌘R) shows progress with integer counts; Cancel stops it and is shown as "Build cancelled", not as a failure.
- [ ] A failing build shows the reason of the last `[RED]` message and "Open Build Logs"; an argument error (exit code 2) shows the stderr text.
- [ ] With the app in the background, a finished or failed build posts a notification (can be turned off in Settings → General).
- [ ] After success: Launch, Settings and Show in Finder work.

## Batch import
- [ ] ⇧⌘I and the builder button open the import sheet.
- [ ] Loose files are sorted into subfolders, also when run twice.
- [ ] A confirmation appears before converting.
- [ ] "Cancel Batch" stops after the current game and keeps its source files.
- [ ] Successful games end up in `~/NXNative/Games`, their import folders in the Trash.
- [ ] A game without a produced `.app` keeps its source files and is reported as failed.
- [ ] A failed game logs its reason; the finished batch posts a notification while the app is in the background.

## Updates and monitoring
- [ ] The update check lists new commits; "Update Now" completes even with long pip/dotnet output.
- [ ] A build started in Terminal appears in the banner; "Live Log" shows its output.
