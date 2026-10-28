# Manual Test Checklist

There are no automated tests. Before a release – or after changes to the affected area – build with `./build.sh` and check the following.

## Launch and setup
- [ ] Without nxnative, the setup sheet opens at launch; with a complete installation it does not.
- [ ] Xcode, Homebrew tools, .NET SDK 10 and Python 3.12+ are detected; missing items are reported.
- [ ] Without a venv, "Create venv & Install" creates `<nxnative>/venv` and installs the packages; with a venv, "Install" adds missing packages.
- [ ] "Install" for Homebrew tools installs `xcodegen` / `zstd`.
- [ ] Settings → General → nxnative: a custom folder is used; choosing `~/NXNative` resolves to `~/NXNative/nxnative`; "Automatic" restores the default.
- [ ] Help → Check Setup… opens the checklist; the sidebar hint disappears once everything is ready.

## Navigation and language
- [ ] ⌘1 / ⌘2 switch between Library and Build Game; ⌘, opens Settings.
- [ ] Switching the language updates the main window, menus and Settings immediately.

## Library
- [ ] Games show icon, size, version and badges; search filters by name and title ID.
- [ ] Double-click / ⌘↩ launches; the context menu works.
- [ ] Game settings (⌘I) save `env.txt` and keep custom entries.
- [ ] Dropping an `.app` or a folder adds it; both can be removed in Settings → Library.

## Builder
- [ ] Choosing or dropping a folder lists the detected game files.
- [ ] Build (⌘R) shows progress with integer counts; Cancel stops it.
- [ ] With .NET installed via Homebrew, a build succeeds (DOTNET_ROOT is not overridden).
- [ ] "Keep extracted data" off removes the extracted files after the build.
- [ ] After success: Launch, Settings and Show in Finder work.

## Batch import
- [ ] ⇧⌘I and the builder button open the import sheet.
- [ ] Loose files are sorted into subfolders, also when run twice.
- [ ] A confirmation appears before converting.
- [ ] "Cancel Batch" stops after the current game and keeps its source files.
- [ ] Successful games end up in `~/NXNative/Games`, their import folders in the Trash.
- [ ] A game without a produced `.app` keeps its source files and is reported as failed.

## Updates and monitoring
- [ ] The update check lists new commits; "Update Now" completes even with long pip output.
- [ ] A build started in Terminal appears in the banner; "Live Log" shows its output.
