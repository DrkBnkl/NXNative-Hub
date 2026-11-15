# Manual Test Checklist

There are no automated tests. Before a release – or after changes to the affected area – build with `./build.sh` and check the following.

## Launch and setup
- [ ] Without nxnative, the setup sheet opens at launch; with a complete installation it does not.
- [ ] "Create venv" and "Install" (Python packages) succeed and the checks turn green.
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
- [ ] After success: Launch, Settings and Show in Finder work.
- [ ] A folder with a `.nup` (or a dropped `.nup` file) and a Switch 2 dump folder show the "Switch 2" row with title ID and profile; Build works without prod.keys and passes no `-k`.
- [ ] A `.nup` dropped from a folder that also holds NSPs or other `.nup` files builds that `.nup`; a folder with several `.nup` files shows the hint to drop one.
- [ ] A Switch 2 game without profile shows the orange warning; choosing iPhone / iPad shows the "Mac only" warning.

## Batch import
- [ ] ⇧⌘I and the builder button open the import sheet.
- [ ] Loose files are sorted into subfolders, also when run twice.
- [ ] A confirmation appears before converting.
- [ ] `.nup` files and dump folders are listed with a "Switch 2" badge; a selection of only Switch 2 games converts without prod.keys.
- [ ] "Cancel Batch" stops after the current game and keeps its source files.
- [ ] Successful games end up in `~/NXNative/Games`; their import folders stay in place, or go to the Trash when the option is checked.
- [ ] A game without a produced `.app` keeps its source files and is reported as failed.

## Updates and monitoring
- [ ] The update check lists new commits; "Update Now" completes even with long pip/dotnet output.
- [ ] A build started in Terminal appears in the banner; "Live Log" shows its output.
